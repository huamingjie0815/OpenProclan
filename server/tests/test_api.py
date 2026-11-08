import sqlite3
from pathlib import Path

import pytest
from fastmcp import Client
from httpx import ASGITransport, AsyncClient

from proclan_server.app import create_app
from proclan_server.categories import CATEGORIES
from proclan_server.config import Settings
from proclan_server.publish import CardIn, CardRejected, publish_cards
from proclan_server.set_password import main as set_password_main
from proclan_server.store import Card, Store, new_id, now


def settings(tmp_path: Path, **overrides) -> Settings:
    values = dict(
        data_dir=tmp_path,
        host="127.0.0.1",
        port=8787,
    )
    values.update(overrides)
    return Settings(**values)


def card(**overrides) -> dict:
    body = {
        "title": "模型降价",
        "category": "科技",
        "summary": "价格下调",
        "body": "正文",
        "tags": ["AI"],
        "source": "Hacker News",
        "created_bot": "Proclan",
        "bot_desc": "盯着值得看的科技和财经。",
        "source_urls": ["https://1.1.1.1/story"],
        "image_urls": [],
    }
    body.update(overrides)
    return body


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
async def api(tmp_path: Path):
    app = create_app(settings(tmp_path))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client, app


async def _register(client: AsyncClient, username: str = "Ada"):
    response = await client.post(
        "/v1/auth/register",
        json={"username": username, "password": "password-1"},
    )
    assert response.status_code == 200
    return response.json()


async def test_feed_requires_a_session_and_starts_empty(api):
    client, _ = api
    assert (await client.get("/v1/feed")).status_code == 401
    account = await _register(client)
    headers = _auth(account["token"])
    response = await client.get("/v1/feed", headers=headers)
    assert response.status_code == 200
    assert response.json()["cards"] == []
    categories = await client.get("/v1/categories", headers=headers)
    assert categories.json()["categories"] == list(CATEGORIES)


async def test_publish_stores_a_finished_card(api):
    client, app = api
    account = await _register(client)
    ids = publish_cards(
        app.state.store,
        app.state.settings.media_dir,
        [card(), card(title="汇率波动", category="财经")],
        user_id=account["user"]["id"],
    )
    headers = _auth(account["token"])
    feed = (await client.get("/v1/feed", headers=headers)).json()["cards"]
    assert [item["title"] for item in feed] == ["模型降价", "汇率波动"]
    assert "read" not in feed[0]
    assert "processor" not in feed[0]
    assert feed[0]["source"] == "Hacker News"
    assert feed[0]["created_bot"] == "Proclan"
    assert feed[0]["source_urls"] == ["https://1.1.1.1/story"]
    one = await client.get(f"/v1/feed/{ids[0]}", headers=headers)
    assert one.json()["summary"] == "价格下调"
    tech = await client.get("/v1/feed", params={"category": "科技"}, headers=headers)
    assert [item["title"] for item in tech.json()["cards"]] == ["模型降价"]
    older = await client.get("/v1/feed", params={"limit": 1, "offset": 1}, headers=headers)
    assert [item["title"] for item in older.json()["cards"]] == ["汇率波动"]
    bad = await client.get("/v1/feed", params={"category": "八卦"}, headers=headers)
    assert bad.status_code == 400


async def test_invalid_card_rejects_the_whole_batch(api):
    _, app = api
    with pytest.raises(CardRejected, match="第 2 张的 category"):
        publish_cards(
            app.state.store,
            app.state.settings.media_dir,
            [card(), card(title="汇率", category="八卦")],
            user_id="user-1",
        )
    assert app.state.store.list_cards(category=None, limit=10) == []

    with pytest.raises(CardRejected, match="title 超过 40"):
        publish_cards(
            app.state.store,
            app.state.settings.media_dir,
            [card(title="价" * 41)],
            user_id="user-1",
        )
    with pytest.raises(CardRejected, match="created_bot 不能为空"):
        publish_cards(
            app.state.store,
            app.state.settings.media_dir,
            [card(created_bot="  ")],
            user_id="user-1",
        )
    with pytest.raises(CardRejected, match="bot_desc 不能为空"):
        publish_cards(
            app.state.store,
            app.state.settings.media_dir,
            [card(bot_desc="  ")],
            user_id="user-1",
        )
    with pytest.raises(CardRejected, match="bot_desc 超过 200"):
        publish_cards(
            app.state.store,
            app.state.settings.media_dir,
            [card(bot_desc="介" * 201)],
            user_id="user-1",
        )
    with pytest.raises(CardRejected, match="字段 note 不在 inputSchema 里"):
        publish_cards(
            app.state.store,
            app.state.settings.media_dir,
            [card(note="多余")],
            user_id="user-1",
        )
    assert app.state.store.list_cards(category=None, limit=10) == []


async def test_submit_cards_schema_is_the_contract(api):
    _, app = api
    model = CardIn.model_json_schema()
    assert model["required"] == ["title", "category", "created_bot", "bot_desc"]
    assert model["properties"]["category"]["enum"] == list(CATEGORIES)
    assert model["properties"]["title"]["maxLength"] == 40
    assert model["properties"]["bot_desc"]["maxLength"] == 200
    assert model["properties"]["tags"]["maxItems"] == 4
    assert model["additionalProperties"] is False
    with pytest.raises(CardRejected, match="当前必填：title、category、created_bot、bot_desc"):
        publish_cards(
            app.state.store,
            app.state.settings.media_dir,
            [card(title="")],
            user_id="user-1",
        )
    async with app.router.lifespan_context(app):
        async with Client(app.state.mcp) as mcp:
            tool = (await mcp.list_tools())[0]
    assert tool.name == "submit_cards"
    assert "inputSchema" in tool.description
    raw = tool.model_dump(by_alias=True)
    schema = raw.get("inputSchema") or raw.get("input_schema")
    cards = schema["properties"]["cards"]
    assert cards["minItems"] == 1
    assert cards["maxItems"] == 8
    item = cards["items"]
    if "$ref" in item:
        item = schema["$defs"][item["$ref"].rsplit("/", 1)[-1]]
    assert item["required"] == model["required"]


async def test_cards_belong_to_the_token_and_expire_after_a_day(api):
    client, app = api
    owner = await _register(client)
    other = await _register(client, username="Bea")
    media = app.state.settings.media_dir
    kept = publish_cards(app.state.store, media, [card(title="今天")], user_id=owner["user"]["id"])
    old = publish_cards(
        app.state.store,
        media,
        [card(title="昨天", created_bot="旧 bot")],
        user_id=owner["user"]["id"],
    )
    theirs = publish_cards(app.state.store, media, [card(title="别人的")], user_id=other["user"]["id"])
    with sqlite3.connect(app.state.store.path) as conn:
        conn.execute(
            "UPDATE cards SET created_at = ? WHERE id = ?",
            ("2000-01-01T00:00:00+00:00", old[0]),
        )
    headers = _auth(owner["token"])
    feed = (await client.get("/v1/feed", headers=headers)).json()["cards"]
    assert [item["title"] for item in feed] == ["今天"]
    assert (await client.get(f"/v1/feed/{theirs[0]}", headers=headers)).status_code == 404
    assert (await client.delete(f"/v1/feed/{theirs[0]}", headers=headers)).status_code == 404
    names = (await client.get("/v1/bots", headers=headers)).json()["bots"]
    assert [item["name"] for item in names] == ["Proclan", "旧 bot"]
    assert app.state.store.get_card(kept[0], user_id=owner["user"]["id"]) is not None
    assert app.state.store.get_card(old[0]) is None


async def test_bot_profile_can_be_deleted_and_returns_on_the_next_push(api):
    client, app = api
    owner = await _register(client)
    other = await _register(client, username="Bea")
    media = app.state.settings.media_dir
    user_id = owner["user"]["id"]
    publish_cards(
        app.state.store,
        media,
        [
            card(title="新", bot_desc="先写的介绍"),
            card(title="旧", bot_desc="后来的介绍"),
        ],
        user_id=user_id,
    )
    empty = publish_cards(
        app.state.store,
        media,
        [card(title="过期", created_bot="空", bot_desc="暂时没有")],
        user_id=user_id,
    )
    publish_cards(
        app.state.store,
        media,
        [card(title="别人的")],
        user_id=other["user"]["id"],
    )
    with sqlite3.connect(app.state.store.path) as conn:
        conn.execute(
            "UPDATE cards SET created_at = ? WHERE id = ?",
            ("2000-01-01T00:00:00+00:00", empty[0]),
        )
    headers = _auth(owner["token"])
    assert (
        await client.get("/v1/bots/profile", params={"name": "Proclan"}, headers=_auth(owner["bot_token"]))
    ).status_code == 401

    quiet = await client.get("/v1/bots/profile", params={"name": "空"}, headers=headers)
    assert quiet.status_code == 200
    assert quiet.json()["name"] == "空"
    assert quiet.json()["first_seen"]
    assert quiet.json()["bot_desc"] == "暂时没有"
    assert quiet.json()["cards"] == []
    assert "latest" not in quiet.json()

    shown = await client.get("/v1/bots/profile", params={"name": "Proclan"}, headers=headers)
    assert shown.status_code == 200
    body = shown.json()
    assert body["bot_desc"] == "后来的介绍"
    assert [item["title"] for item in body["cards"]] == ["新", "旧"]
    assert body["cards"][0]["summary"] == "价格下调"
    assert body["cards"][0]["category"] == "科技"
    assert body["cards"][0]["source"] == "Hacker News"
    assert body["cards"][0]["body"] == "正文"
    seen = body["first_seen"]
    publish_cards(
        app.state.store,
        media,
        [card(title="补充", bot_desc="更新后的介绍")],
        user_id=user_id,
    )
    updated = await client.get("/v1/bots/profile", params={"name": "Proclan"}, headers=headers)
    assert updated.json()["bot_desc"] == "更新后的介绍"
    assert updated.json()["first_seen"] == seen
    assert [item["title"] for item in updated.json()["cards"]][0] == "补充"

    removed = await client.delete("/v1/bots/profile", params={"name": "Proclan"}, headers=headers)
    assert removed.status_code == 204
    names = (await client.get("/v1/bots", headers=headers)).json()["bots"]
    assert [item["name"] for item in names] == ["空"]
    feed = (await client.get("/v1/feed", headers=headers)).json()["cards"]
    assert [item["title"] for item in feed] == ["补充", "新", "旧"]
    other_names = (await client.get("/v1/bots", headers=_auth(other["token"]))).json()["bots"]
    assert [item["name"] for item in other_names] == ["Proclan"]
    assert (await client.get("/v1/bots/profile", params={"name": "Proclan"}, headers=headers)).status_code == 404
    assert (await client.delete("/v1/bots/profile", params={"name": "Proclan"}, headers=headers)).status_code == 404

    publish_cards(
        app.state.store,
        media,
        [card(title="又来了", bot_desc="又介绍")],
        user_id=user_id,
    )
    again = await client.get("/v1/bots/profile", params={"name": "Proclan"}, headers=headers)
    assert again.status_code == 200
    assert again.json()["bot_desc"] == "又介绍"
    assert [item["title"] for item in again.json()["cards"]][0] == "又来了"
    assert "新" in [item["title"] for item in again.json()["cards"]]
    listed = (await client.get("/v1/bots", headers=headers)).json()["bots"]
    assert [item["name"] for item in listed] == ["Proclan", "空"]

    publish_cards(
        app.state.store,
        media,
        [card(title="斜线", created_bot="旧/bot")],
        user_id=user_id,
    )
    slash = await client.get("/v1/bots/profile", params={"name": "旧/bot"}, headers=headers)
    assert slash.status_code == 200
    assert slash.json()["cards"][0]["title"] == "斜线"


async def test_same_bot_keeps_every_card_inside_the_window(api):
    _, app = api
    publish_cards(
        app.state.store,
        app.state.settings.media_dir,
        [card(title="一"), card(title="二")],
        user_id="user-1",
    )
    titles = [item.title for item in app.state.store.list_cards(category=None, limit=10, user_id="user-1")]
    assert titles == ["一", "二"]
    assert app.state.store.list_bots("user-1") == ["Proclan"]


def test_existing_database_gains_owner_column(tmp_path: Path):
    path = tmp_path / "proclan.sqlite3"
    with sqlite3.connect(path) as conn:
        conn.execute(
            """
            CREATE TABLE cards (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                title TEXT NOT NULL,
                summary TEXT NOT NULL,
                body TEXT NOT NULL,
                category TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                images_json TEXT NOT NULL,
                source TEXT NOT NULL,
                source_urls_json TEXT NOT NULL,
                processor TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
    Store(path).init()
    with sqlite3.connect(path) as conn:
        columns = {row[1] for row in conn.execute("PRAGMA table_info(cards)")}
    assert "created_bot" in columns
    assert "user_id" in columns


def test_existing_bot_names_gain_description(tmp_path: Path):
    path = tmp_path / "proclan.sqlite3"
    with sqlite3.connect(path) as conn:
        conn.execute(
            """
            CREATE TABLE bot_names (
                user_id TEXT NOT NULL,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY (user_id, name)
            )
            """
        )
    Store(path).init()
    with sqlite3.connect(path) as conn:
        columns = {row[1] for row in conn.execute("PRAGMA table_info(bot_names)")}
    assert "bot_desc" in columns


async def test_publish_keeps_public_image_urls(api):
    client, app = api
    account = await _register(client)
    media = app.state.settings.media_dir
    ids = publish_cards(
        app.state.store,
        media,
        [
            card(
                image_urls=[
                    "https://1.1.1.1/keep.jpg",
                    "http://127.0.0.1/secret.jpg",
                    "https://1.1.1.1/keep.jpg",
                    "https://1.1.1.1/second.jpg",
                ]
            )
        ],
        user_id=account["user"]["id"],
    )
    headers = _auth(account["token"])
    one = (await client.get(f"/v1/feed/{ids[0]}", headers=headers)).json()
    assert one["images"] == [
        "https://1.1.1.1/keep.jpg",
        "https://1.1.1.1/second.jpg",
    ]
    assert list(media.iterdir()) == []


async def test_delete_removes_unused_image(api):
    client, app = api
    account = await _register(client)
    media = app.state.settings.media_dir
    (media / "keep.jpg").write_bytes(b"img")
    card_id = new_id()
    app.state.store.insert_cards(
        [
            Card(
                id=card_id,
                message_id="",
                title="旧图",
                summary="",
                body="",
                category="科技",
                tags=[],
                images=["keep.jpg"],
                source="",
                source_urls=[],
                created_bot="Proclan",
                processor="",
                is_read=False,
                created_at=now().isoformat(),
                user_id=account["user"]["id"],
            )
        ]
    )
    headers = _auth(account["token"])
    one = (await client.get(f"/v1/feed/{card_id}", headers=headers)).json()
    assert one["images"] == ["http://test/media/keep.jpg"]
    assert (await client.get("/media/keep.jpg", headers=headers)).status_code == 200
    deleted = await client.delete(f"/v1/feed/{card_id}", headers=headers)
    assert deleted.status_code == 204
    assert (await client.get(f"/v1/feed/{card_id}", headers=headers)).status_code == 404
    assert not (media / "keep.jpg").exists()
    assert (await client.get("/media/keep.jpg", headers=headers)).status_code == 404


async def test_session_and_bot_token_do_not_cross(api):
    client, app = api
    account = await _register(client)
    session = _auth(account["token"])
    bot = _auth(account["bot_token"])
    assert (await client.get("/v1/feed", headers=bot)).status_code == 401
    assert (await client.get("/v1/categories", headers=bot)).status_code == 401
    async with app.router.lifespan_context(app):
        denied = await client.post(
            "/mcp",
            json={"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            headers={"accept": "application/json, text/event-stream", **session},
        )
        assert denied.status_code == 401
        opened = await client.post(
            "/mcp",
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {},
                    "clientInfo": {"name": "proclan-test", "version": "0"},
                },
            },
            headers={"accept": "application/json, text/event-stream", **bot},
        )
        assert opened.status_code == 200
        assert "protocolVersion" in opened.text
        submitted = await client.post(
            "/mcp",
            json={
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {"name": "submit_cards", "arguments": {"cards": [card(title="来自 bot")]}},
            },
            headers={"accept": "application/json, text/event-stream", **bot},
        )
        assert submitted.status_code == 200
        assert "card_ids" in submitted.text
    feed = (await client.get("/v1/feed", headers=session)).json()["cards"]
    assert [item["title"] for item in feed] == ["来自 bot"]
    async with Client(app.state.mcp) as mcp:
        tools = await mcp.list_tools()
        assert [tool.name for tool in tools] == ["submit_cards"]


async def test_register_login_and_password_change(api, tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    client, _ = api
    account = await _register(client)
    assert account["user"] == {"id": account["user"]["id"], "username": "Ada"}
    assert "email" not in account["user"]
    assert account["bot_token"]
    taken = await client.post(
        "/v1/auth/register",
        json={"username": "ada", "password": "password-1"},
    )
    assert taken.status_code == 409

    login = await client.post(
        "/v1/auth/login",
        json={"username": "ADA", "password": "password-1"},
    )
    assert login.status_code == 200
    session = login.json()["token"]
    wrong = await client.post(
        "/v1/auth/password",
        json={"current_password": "nope-nope", "new_password": "password-2"},
        headers=_auth(session),
    )
    assert wrong.status_code == 401
    assert wrong.json()["detail"] == "wrong password"
    assert (await client.get("/v1/me", headers=_auth(session))).status_code == 200
    changed = await client.post(
        "/v1/auth/password",
        json={"current_password": "password-1", "new_password": "password-2"},
        headers=_auth(session),
    )
    assert changed.status_code == 204
    assert (await client.get("/v1/me", headers=_auth(session))).status_code == 401
    again = await client.post(
        "/v1/auth/login",
        json={"username": "Ada", "password": "password-2"},
    )
    assert again.status_code == 200
    token = again.json()["token"]
    me = await client.get("/v1/me", headers=_auth(token))
    assert me.json()["username"] == "Ada"
    renamed = await client.patch(
        "/v1/me",
        json={"username": "艾达"},
        headers=_auth(token),
    )
    assert renamed.status_code == 200
    assert renamed.json()["username"] == "艾达"
    assert (await client.get("/v1/me", headers=_auth(token))).status_code == 200
    clash = await _register(client, username="Bea")
    blocked = await client.patch(
        "/v1/me",
        json={"username": "bea"},
        headers=_auth(token),
    )
    assert blocked.status_code == 409
    assert clash["user"]["username"] == "Bea"

    monkeypatch.setenv("PROCLAN_DATA_DIR", str(tmp_path))
    assert set_password_main(["missing", "password-9"]) == 1
    assert set_password_main(["艾达", "password-3"]) == 0
    assert (await client.get("/v1/me", headers=_auth(token))).status_code == 401
    restored = await client.post(
        "/v1/auth/login",
        json={"username": "艾达", "password": "password-3"},
    )
    assert restored.status_code == 200


async def test_settings_and_bot_token_rotation(api):
    client, app = api
    account = await _register(client)
    headers = _auth(account["token"])
    current = await client.get("/v1/me/settings", headers=headers)
    assert current.json() == {"cache_mode": "7d", "locale": "system", "unread_only": False}
    updated = await client.patch(
        "/v1/me/settings",
        json={"cache_mode": "after_read", "locale": "en", "unread_only": True},
        headers=headers,
    )
    assert updated.json()["cache_mode"] == "after_read"
    invalid = await client.patch("/v1/me/settings", json={"cache_mode": "30d"}, headers=headers)
    assert invalid.status_code == 400
    shown = await client.get("/v1/me/bot-token", headers=headers)
    assert shown.json()["token"] == account["bot_token"]
    rotated = await client.post("/v1/me/bot-token", headers=headers)
    assert rotated.json()["token"] != account["bot_token"]
    async with app.router.lifespan_context(app):
        stale = await client.post(
            "/mcp",
            json={"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            headers={"accept": "application/json, text/event-stream", **_auth(account["bot_token"])},
        )
        assert stale.status_code == 401
        fresh = await client.post(
            "/mcp",
            json={"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            headers={"accept": "application/json, text/event-stream", **_auth(rotated.json()["token"])},
        )
        assert fresh.status_code == 200
    await client.post("/v1/auth/logout", headers=headers)
    assert (await client.get("/v1/me", headers=headers)).status_code == 401


async def test_login_locks_after_repeated_failures(api):
    client, _ = api
    await _register(client)
    for _ in range(9):
        failed = await client.post(
            "/v1/auth/login",
            json={"username": "Ada", "password": "wrong-password"},
        )
        assert failed.status_code == 401
    last = await client.post(
        "/v1/auth/login",
        json={"username": "Ada", "password": "wrong-password"},
    )
    assert last.status_code == 401
    locked = await client.post(
        "/v1/auth/login",
        json={"username": "Ada", "password": "password-1"},
    )
    assert locked.status_code == 429
