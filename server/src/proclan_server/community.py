"""Community routes. Sharing, follows, votes, boards, and search."""

from __future__ import annotations

from collections.abc import Callable

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

from proclan_server.config import Settings
from proclan_server.store import CommunityError, Store


class _Name(BaseModel):
    name: str


class _Target(BaseModel):
    owner_id: str
    name: str


class _Vote(BaseModel):
    owner_id: str
    name: str
    vote: int


class _Grant(BaseModel):
    name: str
    username: str


class _Direct(BaseModel):
    name: str
    on: bool


def register_community(
    app: FastAPI,
    store: Store,
    settings: Settings,
    card_json: Callable,
    cutoff,
) -> None:
    def fail(action):
        try:
            return action()
        except CommunityError as exc:
            raise HTTPException(exc.status, exc.detail) from exc

    @app.post("/v1/community/share")
    def share(request: Request, body: _Name) -> dict:
        return fail(lambda: store.share_bot(request.state.user_id, body.name))

    @app.delete("/v1/community/share")
    def unshare(request: Request, name: str) -> dict:
        return fail(lambda: store.unshare_bot(request.state.user_id, name))

    @app.post("/v1/community/direct")
    def grant(request: Request, body: _Grant) -> dict:
        return fail(
            lambda: store.grant_bot(request.state.user_id, body.name, body.username)
        )

    @app.delete("/v1/community/direct")
    def revoke(request: Request, name: str, username: str) -> dict:
        return fail(lambda: store.revoke_bot(request.state.user_id, name, username))

    @app.post("/v1/community/direct/active")
    def direct(request: Request, body: _Direct) -> dict:
        return fail(lambda: store.set_direct(request.state.user_id, body.name, body.on))

    @app.get("/v1/community/directed")
    def directed(request: Request) -> dict:
        return {"bots": store.community_directed(request.state.user_id)}

    @app.post("/v1/community/follow", status_code=204)
    def follow(request: Request, body: _Target) -> None:
        fail(lambda: store.follow_bot(request.state.user_id, body.owner_id, body.name))

    @app.delete("/v1/community/follow", status_code=204)
    def unfollow(request: Request, owner_id: str, name: str) -> None:
        store.unfollow_bot(request.state.user_id, owner_id, name)

    @app.post("/v1/community/vote", status_code=204)
    def vote(request: Request, body: _Vote) -> None:
        fail(
            lambda: store.vote_bot(
                request.state.user_id,
                body.owner_id,
                body.name,
                body.vote,
            )
        )

    @app.get("/v1/community/board")
    def board(kind: str = "likes") -> dict:
        if kind not in {"likes", "follows"}:
            raise HTTPException(400, "bad board")
        return {"bots": store.community_board(kind)}

    @app.get("/v1/community/search")
    def search(request: Request, q: str = "") -> dict:
        return {"bots": store.community_search(request.state.user_id, q)}

    @app.get("/v1/community/bot")
    def bot(request: Request, owner_id: str, name: str) -> dict:
        found = fail(
            lambda: store.community_detail(
                request.state.user_id,
                owner_id,
                name,
                not_before=cutoff(settings),
            )
        )
        card = found.pop("card")
        if card is not None:
            card.source_username = found["owner_name"]
            found["card"] = card_json(card, request)
        else:
            found["card"] = None
        return found

    @app.get("/v1/community/following")
    def following(request: Request) -> dict:
        return {"users": store.community_following(request.state.user_id)}

    @app.get("/v1/community/copies")
    def copies(request: Request, owner_id: str, name: str) -> dict:
        found = fail(
            lambda: store.community_copies(
                request.state.user_id,
                owner_id,
                name,
                not_before=cutoff(settings),
            )
        )
        found["cards"] = [card_json(card, request) for card in found["cards"]]
        return found
