from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from proclan_server.app import create_app
from proclan_server.publish import publish_cards

from test_api import _auth, _register, card, settings


@pytest.fixture
async def api(tmp_path: Path):
    app = create_app(settings(tmp_path))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client, app


def _publish(app, user_id: str, name: str, title: str = "模型降价"):
    return publish_cards(
        app.state.store,
        app.state.settings.media_dir,
        [card(title=title, created_bot=name, bot_desc="盯着值得看的。")],
        user_id=user_id,
        burst=80,
        name_cap=80,
        name_burst=80,
    )


async def _share(client, headers, name: str) -> dict:
    response = await client.post("/v1/community/share", json={"name": name}, headers=headers)
    assert response.status_code == 200
    return response.json()


async def test_share_code_survives_unshare_and_delete(api):
    client, app = api
    owner = await _register(client, "Ada")
    headers = _auth(owner["token"])
    _publish(app, owner["user"]["id"], "日报")
    shared = await _share(client, headers, "日报")
    code = shared["code"]
    assert shared["listed"] is True
    assert len(code) == 8

    paused = await client.delete("/v1/community/share", params={"name": "日报"}, headers=headers)
    assert paused.status_code == 200
    assert paused.json()["listed"] is False
    assert paused.json()["code"] == code

    again = await _share(client, headers, "日报")
    assert again["code"] == code

    removed = await client.delete("/v1/bots/profile", params={"name": "日报"}, headers=headers)
    assert removed.status_code == 204
    _publish(app, owner["user"]["id"], "日报", title="回来了")
    profile = await client.get("/v1/bots/profile", params={"name": "日报"}, headers=headers)
    assert profile.json()["community"]["code"] == code
    assert profile.json()["community"]["listed"] is False
    assert profile.json()["cards"][0]["title"] == "回来了"
    restored = await _share(client, headers, "日报")
    assert restored["code"] == code
    assert restored["listed"] is True


async def test_follow_copies_only_future_cards(api):
    client, app = api
    owner = await _register(client, "Ada")
    reader = await _register(client, "Bea")
    owner_headers = _auth(owner["token"])
    reader_headers = _auth(reader["token"])
    _publish(app, owner["user"]["id"], "日报", title="更早")
    await _share(client, owner_headers, "日报")
    detail = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=reader_headers,
    )
    assert detail.status_code == 200
    assert detail.json()["card"]["title"] == "更早"
    assert detail.json()["card"]["source_username"] == "Ada"

    followed = await client.post(
        "/v1/community/follow",
        json={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=reader_headers,
    )
    assert followed.status_code == 204
    before = (await client.get("/v1/feed", headers=reader_headers)).json()["cards"]
    assert before == []

    _publish(app, owner["user"]["id"], "日报", title="之后")
    feed = (await client.get("/v1/feed", headers=reader_headers)).json()["cards"]
    assert [item["title"] for item in feed] == ["之后"]
    assert feed[0]["source_username"] == "Ada"
    assert feed[0]["created_bot"] == "日报"
    owner_feed = (await client.get("/v1/feed", headers=owner_headers)).json()["cards"]
    assert [item["title"] for item in owner_feed] == ["之后", "更早"]
    assert "source_username" not in owner_feed[0]

    original_id = owner_feed[1]["id"]
    deleted = await client.delete(f"/v1/feed/{original_id}", headers=owner_headers)
    assert deleted.status_code == 204
    still = (await client.get("/v1/feed", headers=reader_headers)).json()["cards"]
    assert [item["title"] for item in still] == ["之后"]

    stopped = await client.delete(
        "/v1/community/follow",
        params={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=reader_headers,
    )
    assert stopped.status_code == 204
    _publish(app, owner["user"]["id"], "日报", title="错过")
    await client.post(
        "/v1/community/follow",
        json={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=reader_headers,
    )
    _publish(app, owner["user"]["id"], "日报", title="重新之后")
    titles = [
        item["title"]
        for item in (await client.get("/v1/feed", headers=reader_headers)).json()["cards"]
    ]
    assert titles == ["重新之后", "之后"]
    bots = (await client.get("/v1/bots", headers=reader_headers)).json()["bots"]
    assert bots == []
    profile = await client.get(
        "/v1/bots/profile",
        params={"name": "日报"},
        headers=reader_headers,
    )
    assert profile.status_code == 404
    _publish(app, reader["user"]["id"], "日报", title="自己的")
    own = await client.get(
        "/v1/bots/profile",
        params={"name": "日报"},
        headers=reader_headers,
    )
    assert own.status_code == 200
    assert [item["title"] for item in own.json()["cards"]] == ["自己的"]


async def test_unshare_pauses_and_resume_skips_the_gap(api):
    client, app = api
    owner = await _register(client, "Ada")
    reader = await _register(client, "Bea")
    owner_headers = _auth(owner["token"])
    reader_headers = _auth(reader["token"])
    _publish(app, owner["user"]["id"], "日报")
    shared = await _share(client, owner_headers, "日报")
    await client.post(
        "/v1/community/follow",
        json={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=reader_headers,
    )
    await client.post(
        "/v1/community/vote",
        json={"owner_id": owner["user"]["id"], "name": "日报", "vote": 1},
        headers=reader_headers,
    )
    await client.delete("/v1/community/share", params={"name": "日报"}, headers=owner_headers)
    blocked = await client.post(
        "/v1/community/vote",
        json={"owner_id": owner["user"]["id"], "name": "日报", "vote": -1},
        headers=reader_headers,
    )
    assert blocked.status_code == 409
    clear = await client.post(
        "/v1/community/vote",
        json={"owner_id": owner["user"]["id"], "name": "日报", "vote": 0},
        headers=reader_headers,
    )
    assert clear.status_code == 409
    detail = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=reader_headers,
    )
    assert detail.json()["listed"] is False
    assert detail.json()["likes"] == 1
    assert detail.json()["vote"] == 1
    _publish(app, owner["user"]["id"], "日报", title="下线期间")
    quiet = (await client.get("/v1/feed", headers=reader_headers)).json()["cards"]
    assert quiet == []
    await _share(client, owner_headers, "日报")
    assert (await _share(client, owner_headers, "日报"))["code"] == shared["code"]
    _publish(app, owner["user"]["id"], "日报", title="恢复后")
    titles = [
        item["title"]
        for item in (await client.get("/v1/feed", headers=reader_headers)).json()["cards"]
    ]
    assert titles == ["恢复后"]
    board = await client.get("/v1/community/board", params={"kind": "likes"}, headers=reader_headers)
    assert [item["name"] for item in board.json()["bots"]] == ["日报"]


async def test_votes_are_exclusive_and_cannot_target_yourself(api):
    client, app = api
    owner = await _register(client, "Ada")
    reader = await _register(client, "Bea")
    owner_headers = _auth(owner["token"])
    reader_headers = _auth(reader["token"])
    _publish(app, owner["user"]["id"], "日报")
    await _share(client, owner_headers, "日报")
    self_follow = await client.post(
        "/v1/community/follow",
        json={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=owner_headers,
    )
    assert self_follow.status_code == 400
    self_vote = await client.post(
        "/v1/community/vote",
        json={"owner_id": owner["user"]["id"], "name": "日报", "vote": 1},
        headers=owner_headers,
    )
    assert self_vote.status_code == 400
    await client.post(
        "/v1/community/vote",
        json={"owner_id": owner["user"]["id"], "name": "日报", "vote": 1},
        headers=reader_headers,
    )
    await client.post(
        "/v1/community/vote",
        json={"owner_id": owner["user"]["id"], "name": "日报", "vote": -1},
        headers=reader_headers,
    )
    detail = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=reader_headers,
    )
    assert detail.json()["likes"] == 0
    assert detail.json()["dislikes"] == 1
    assert detail.json()["vote"] == -1
    await client.post(
        "/v1/community/vote",
        json={"owner_id": owner["user"]["id"], "name": "日报", "vote": 0},
        headers=reader_headers,
    )
    cleared = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner["user"]["id"], "name": "日报"},
        headers=reader_headers,
    )
    assert cleared.json()["dislikes"] == 0
    assert cleared.json()["vote"] == 0


async def test_board_keeps_fifty_and_search_finds_the_rest(api):
    client, app = api
    owner = await _register(client, "Ada")
    reader = await _register(client, "Bea")
    headers = _auth(owner["token"])
    reader_headers = _auth(reader["token"])
    names = [f"b{index:02d}" for index in range(51)]
    for name in names:
        _publish(app, owner["user"]["id"], name, title=name)
        await _share(client, headers, name)
    await client.post(
        "/v1/community/follow",
        json={"owner_id": owner["user"]["id"], "name": "b00"},
        headers=reader_headers,
    )
    likes = await client.get("/v1/community/board", params={"kind": "likes"}, headers=headers)
    follows = await client.get(
        "/v1/community/board",
        params={"kind": "follows"},
        headers=headers,
    )
    like_rows = likes.json()["bots"]
    follow_rows = follows.json()["bots"]
    assert len(like_rows) == 50
    assert len(follow_rows) == 50
    assert like_rows[0]["rank"] == 1
    assert like_rows[0]["name"] == "b00"
    assert like_rows[-1]["name"] == "b49"
    assert follow_rows[0]["name"] == "b00"
    assert follow_rows[0]["follows"] == 1
    assert all(item["owner_name"] == "Ada" for item in like_rows)
    missed = await client.get("/v1/community/search", params={"q": "b50"}, headers=headers)
    assert [item["name"] for item in missed.json()["bots"]] == ["b50"]
    hidden = await client.delete("/v1/community/share", params={"name": "b50"}, headers=headers)
    assert hidden.status_code == 200
    by_name = await client.get("/v1/community/search", params={"q": "b50"}, headers=reader_headers)
    assert by_name.json()["bots"] == []
    code = hidden.json()["code"]
    by_code = await client.get(
        "/v1/community/search",
        params={"q": code.lower()},
        headers=reader_headers,
    )
    assert by_code.json()["bots"][0]["name"] == "b50"
    assert by_code.json()["bots"][0]["listed"] is False
    groups = await client.get("/v1/community/following", headers=reader_headers)
    assert groups.json()["users"] == [
        {
            "owner_id": owner["user"]["id"],
            "owner_name": "Ada",
            "bots": [{"name": "b00", "listed": True, "bot_desc": "盯着值得看的。"}],
        }
    ]
