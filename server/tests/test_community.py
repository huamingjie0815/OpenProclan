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
            "bots": [{"name": "b00", "listed": True, "direct": False, "bot_desc": "盯着值得看的。"}],
        }
    ]


async def _titles_of(client, headers) -> list[str]:
    feed = await client.get("/v1/feed", headers=headers)
    return [item["title"] for item in feed.json()["cards"]]


async def _grant(client, headers, name: str, username: str) -> dict:
    response = await client.post(
        "/v1/community/direct",
        json={"name": name, "username": username},
        headers=headers,
    )
    assert response.status_code == 200
    return response.json()


async def _activate(client, headers, name: str, on: bool = True):
    return await client.post(
        "/v1/community/direct/active",
        json={"name": name, "on": on},
        headers=headers,
    )


async def test_direct_share_is_invisible_and_copies_only_to_the_list(api):
    client, app = api
    owner = await _register(client, "Ada")
    bea = await _register(client, "Bea")
    cy = await _register(client, "Cy")
    stranger = await _register(client, "Dan")
    owner_headers = _auth(owner["token"])
    bea_headers = _auth(bea["token"])
    cy_headers = _auth(cy["token"])
    stranger_headers = _auth(stranger["token"])
    owner_id = owner["user"]["id"]
    _publish(app, owner_id, "日报", title="更早")

    saved = await _grant(client, owner_headers, "日报", "bea")
    assert saved["listed"] is False
    assert saved["direct"] is False
    assert saved["code"] is None
    assert saved["audience"] == ["Bea"]
    again = await _grant(client, owner_headers, "日报", "Bea")
    assert again["audience"] == ["Bea"]
    both = await _grant(client, owner_headers, "日报", "Cy")
    assert both["audience"] == ["Bea", "Cy"]
    self_grant = await client.post(
        "/v1/community/direct",
        json={"name": "日报", "username": "Ada"},
        headers=owner_headers,
    )
    assert self_grant.status_code == 400
    missing = await client.post(
        "/v1/community/direct",
        json={"name": "日报", "username": "没有这个人"},
        headers=owner_headers,
    )
    assert missing.status_code == 404

    opened = await _activate(client, owner_headers, "日报")
    assert opened.status_code == 200
    body = opened.json()
    code = body["code"]
    assert body["listed"] is False
    assert body["direct"] is True
    assert body["audience"] == ["Bea", "Cy"]
    assert len(code) == 8

    board = await client.get("/v1/community/board", headers=stranger_headers)
    assert board.json()["bots"] == []
    by_name = await client.get(
        "/v1/community/search",
        params={"q": "日报"},
        headers=stranger_headers,
    )
    assert by_name.json()["bots"] == []
    by_code = await client.get(
        "/v1/community/search",
        params={"q": code.lower()},
        headers=stranger_headers,
    )
    assert by_code.json()["bots"] == []
    hidden = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner_id, "name": "日报"},
        headers=stranger_headers,
    )
    assert hidden.status_code == 404
    copies = await client.get(
        "/v1/community/copies",
        params={"owner_id": owner_id, "name": "日报"},
        headers=stranger_headers,
    )
    assert copies.status_code == 404

    bea_found = await client.get(
        "/v1/community/search",
        params={"q": code},
        headers=bea_headers,
    )
    assert bea_found.json()["bots"][0]["name"] == "日报"
    assert bea_found.json()["bots"][0]["direct"] is True
    directed = await client.get("/v1/community/directed", headers=cy_headers)
    assert [item["name"] for item in directed.json()["bots"]] == ["日报"]
    detail = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner_id, "name": "日报"},
        headers=cy_headers,
    )
    assert detail.status_code == 200
    assert detail.json()["direct"] is True
    assert detail.json()["listed"] is False

    for headers in (bea_headers, cy_headers):
        followed = await client.post(
            "/v1/community/follow",
            json={"owner_id": owner_id, "name": "日报"},
            headers=headers,
        )
        assert followed.status_code == 204
    voted = await client.post(
        "/v1/community/vote",
        json={"owner_id": owner_id, "name": "日报", "vote": 1},
        headers=bea_headers,
    )
    assert voted.status_code == 409

    _publish(app, owner_id, "日报", title="之后")
    assert await _titles_of(client, bea_headers) == ["之后"]
    assert await _titles_of(client, cy_headers) == ["之后"]
    assert (await client.get("/v1/community/directed", headers=bea_headers)).json()["bots"] == []

    removed = await client.delete(
        "/v1/community/direct",
        params={"name": "日报", "username": "Bea"},
        headers=owner_headers,
    )
    assert removed.status_code == 200
    assert removed.json()["audience"] == ["Cy"]
    assert removed.json()["direct"] is True
    _publish(app, owner_id, "日报", title="移出后")
    assert await _titles_of(client, bea_headers) == ["之后"]
    assert await _titles_of(client, cy_headers) == ["移出后", "之后"]
    left = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner_id, "name": "日报"},
        headers=bea_headers,
    )
    assert left.status_code == 200
    assert left.json()["direct"] is False
    assert left.json()["listed"] is False
    assert left.json()["card"] is None
    copies = await client.get(
        "/v1/community/copies",
        params={"owner_id": owner_id, "name": "日报"},
        headers=bea_headers,
    )
    assert copies.status_code == 200
    assert [item["title"] for item in copies.json()["cards"]] == ["之后"]
    await client.delete(
        "/v1/community/follow",
        params={"owner_id": owner_id, "name": "日报"},
        headers=bea_headers,
    )
    blocked = await client.post(
        "/v1/community/follow",
        json={"owner_id": owner_id, "name": "日报"},
        headers=bea_headers,
    )
    assert blocked.status_code == 409
    gone = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner_id, "name": "日报"},
        headers=bea_headers,
    )
    assert gone.status_code == 404


async def test_direct_pause_keeps_the_list_and_skips_the_gap(api):
    client, app = api
    owner = await _register(client, "Ada")
    bea = await _register(client, "Bea")
    stranger = await _register(client, "Dan")
    owner_headers = _auth(owner["token"])
    bea_headers = _auth(bea["token"])
    stranger_headers = _auth(stranger["token"])
    owner_id = owner["user"]["id"]
    _publish(app, owner_id, "日报")
    await _grant(client, owner_headers, "日报", "Bea")
    opened = await _activate(client, owner_headers, "日报")
    code = opened.json()["code"]
    await client.post(
        "/v1/community/follow",
        json={"owner_id": owner_id, "name": "日报"},
        headers=bea_headers,
    )
    _publish(app, owner_id, "日报", title="之前")

    paused = await _activate(client, owner_headers, "日报", on=False)
    assert paused.status_code == 200
    assert paused.json()["direct"] is False
    assert paused.json()["audience"] == ["Bea"]
    assert paused.json()["code"] == code
    assert (await client.get("/v1/community/directed", headers=bea_headers)).json()["bots"] == []
    for headers in (bea_headers, stranger_headers, owner_headers):
        found = await client.get("/v1/community/search", params={"q": code}, headers=headers)
        assert found.json()["bots"] == []
    _publish(app, owner_id, "日报", title="停用期间")
    assert await _titles_of(client, bea_headers) == ["之前"]

    resumed = await _activate(client, owner_headers, "日报")
    assert resumed.json()["direct"] is True
    assert resumed.json()["audience"] == ["Bea"]
    assert resumed.json()["code"] == code
    _publish(app, owner_id, "日报", title="恢复后")
    assert await _titles_of(client, bea_headers) == ["恢复后", "之前"]


async def test_public_share_must_stop_before_direct_when_outsiders_follow(api):
    client, app = api
    owner = await _register(client, "Ada")
    bea = await _register(client, "Bea")
    cy = await _register(client, "Cy")
    owner_headers = _auth(owner["token"])
    bea_headers = _auth(bea["token"])
    cy_headers = _auth(cy["token"])
    owner_id = owner["user"]["id"]
    _publish(app, owner_id, "日报")
    await _share(client, owner_headers, "日报")
    await _grant(client, owner_headers, "日报", "Bea")
    await client.post(
        "/v1/community/follow",
        json={"owner_id": owner_id, "name": "日报"},
        headers=bea_headers,
    )
    await client.post(
        "/v1/community/follow",
        json={"owner_id": owner_id, "name": "日报"},
        headers=cy_headers,
    )
    blocked = await _activate(client, owner_headers, "日报")
    assert blocked.status_code == 409
    still = await client.get("/v1/community/board", params={"kind": "likes"}, headers=bea_headers)
    assert [item["name"] for item in still.json()["bots"]] == ["日报"]
    _publish(app, owner_id, "日报", title="仍公开")
    assert await _titles_of(client, cy_headers) == ["仍公开"]

    await client.delete("/v1/community/share", params={"name": "日报"}, headers=owner_headers)
    opened = await _activate(client, owner_headers, "日报")
    assert opened.status_code == 200
    assert opened.json()["listed"] is False
    assert opened.json()["direct"] is True
    assert opened.json()["audience"] == ["Bea"]
    _publish(app, owner_id, "日报", title="只给名单")
    assert await _titles_of(client, bea_headers) == ["只给名单", "仍公开"]
    assert await _titles_of(client, cy_headers) == ["仍公开"]
    cy_detail = await client.get(
        "/v1/community/bot",
        params={"owner_id": owner_id, "name": "日报"},
        headers=cy_headers,
    )
    assert cy_detail.json()["direct"] is False
    assert cy_detail.json()["listed"] is False
    assert cy_detail.json()["card"] is None

    public = await _share(client, owner_headers, "日报")
    assert public["listed"] is True
    assert public["direct"] is False
    assert public["audience"] == ["Bea"]
    await client.delete("/v1/community/share", params={"name": "日报"}, headers=owner_headers)
    profile = await client.get("/v1/bots/profile", params={"name": "日报"}, headers=owner_headers)
    assert profile.json()["community"]["direct"] is False
    assert profile.json()["community"]["audience"] == ["Bea"]
    assert (await client.get("/v1/community/directed", headers=bea_headers)).json()["bots"] == []


async def test_direct_with_no_outside_follower_leaves_the_board(api):
    client, app = api
    owner = await _register(client, "Ada")
    bea = await _register(client, "Bea")
    owner_headers = _auth(owner["token"])
    bea_headers = _auth(bea["token"])
    owner_id = owner["user"]["id"]
    _publish(app, owner_id, "日报")
    await _share(client, owner_headers, "日报")
    await _grant(client, owner_headers, "日报", "Bea")
    await client.post(
        "/v1/community/follow",
        json={"owner_id": owner_id, "name": "日报"},
        headers=bea_headers,
    )
    opened = await _activate(client, owner_headers, "日报")
    assert opened.status_code == 200
    assert opened.json()["listed"] is False
    board = await client.get("/v1/community/board", headers=bea_headers)
    assert board.json()["bots"] == []
    _publish(app, owner_id, "日报", title="继续")
    assert await _titles_of(client, bea_headers) == ["继续"]


async def test_deleting_the_bot_name_pauses_direct_and_keeps_the_list(api):
    client, app = api
    owner = await _register(client, "Ada")
    bea = await _register(client, "Bea")
    owner_headers = _auth(owner["token"])
    bea_headers = _auth(bea["token"])
    owner_id = owner["user"]["id"]
    _publish(app, owner_id, "日报")
    await _grant(client, owner_headers, "日报", "Bea")
    opened = await _activate(client, owner_headers, "日报")
    code = opened.json()["code"]
    await client.delete("/v1/bots/profile", params={"name": "日报"}, headers=owner_headers)
    _publish(app, owner_id, "日报", title="回来了")
    profile = await client.get("/v1/bots/profile", params={"name": "日报"}, headers=owner_headers)
    assert profile.json()["community"]["code"] == code
    assert profile.json()["community"]["direct"] is False
    assert profile.json()["community"]["listed"] is False
    assert profile.json()["community"]["audience"] == ["Bea"]
    assert (await client.get("/v1/community/directed", headers=bea_headers)).json()["bots"] == []
    resumed = await _activate(client, owner_headers, "日报")
    assert resumed.json()["direct"] is True
    assert resumed.json()["code"] == code
    assert (await client.get("/v1/community/directed", headers=bea_headers)).json()["bots"][0]["name"] == "日报"

