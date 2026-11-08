"""HTTP API and the mounted MCP endpoint."""

from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import timedelta
from typing import Annotated

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from fastmcp import FastMCP
from pydantic import BaseModel, Field
from fastmcp.exceptions import ToolError

from proclan_server.accounts import (
    AccountError,
    change_password,
    change_settings,
    change_username,
    login,
    register,
)
from proclan_server.categories import CATEGORIES
from proclan_server.config import Settings, load_settings
from proclan_server.hashing import new_secret
from proclan_server.identity import current_user_id
from proclan_server.publish import MAX_CARDS, SUBMIT_CARDS_DOC, CardIn, CardRejected, publish_cards
from proclan_server.store import Card, Store, User, now


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()
    store = Store(settings.db_path)
    mcp = FastMCP("Proclan")

    @mcp.tool(description=SUBMIT_CARDS_DOC)
    async def submit_cards(
        cards: Annotated[list[CardIn], Field(min_length=1, max_length=MAX_CARDS)],
    ) -> dict:
        user_id = current_user_id.get()
        if not user_id:
            raise ToolError("invalid token")
        try:
            ids = publish_cards(
                store,
                settings.media_dir,
                [card.model_dump() for card in cards],
                user_id=user_id,
            )
        except CardRejected as exc:
            raise ToolError(exc.detail) from exc
        _expire(store, settings)
        return {"card_ids": ids}

    mcp_app = mcp.http_app(path="/", stateless_http=True, json_response=True)
    settings.media_dir.mkdir(parents=True, exist_ok=True)
    store.init()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.settings = settings
        app.state.store = store
        async with mcp_app.lifespan(app):
            yield

    app = FastAPI(title="Proclan", lifespan=lifespan)
    app.state.settings = settings
    app.state.store = store
    app.state.mcp = mcp
    app.mount("/mcp", mcp_app)

    @app.post("/v1/auth/register")
    def auth_register(body: _Register) -> dict:
        user, token, bot = _call(
            lambda: register(store, username=body.username, password=body.password)
        )
        return {"user": _user_json(user), "token": token, "bot_token": bot}

    @app.post("/v1/auth/login")
    def auth_login(body: _Login) -> dict:
        user, token = _call(lambda: login(store, username=body.username, password=body.password))
        return {"user": _user_json(user), "token": token}

    @app.post("/v1/auth/logout", status_code=204)
    def auth_logout(request: Request) -> None:
        store.delete_session(request.state.token)

    @app.post("/v1/auth/password", status_code=204)
    def auth_password(request: Request, body: _PasswordChange) -> None:
        _call(
            lambda: change_password(
                store,
                request.state.user_id,
                current_password=body.current_password,
                new_password=body.new_password,
            )
        )

    @app.get("/v1/me")
    def me(request: Request) -> dict:
        return _user_json(_user_or_401(store, request.state.user_id))

    @app.patch("/v1/me")
    def patch_me(request: Request, body: _Username) -> dict:
        user = _call(lambda: change_username(store, request.state.user_id, body.username))
        return _user_json(user)

    @app.get("/v1/me/settings")
    def get_settings(request: Request) -> dict:
        return _settings_json(_user_or_401(store, request.state.user_id))

    @app.patch("/v1/me/settings")
    def patch_settings(request: Request, body: _SettingsIn) -> dict:
        user = _call(
            lambda: change_settings(
                store,
                request.state.user_id,
                cache_mode=body.cache_mode,
                locale=body.locale,
                unread_only=body.unread_only,
            )
        )
        return _settings_json(user)

    @app.get("/v1/me/bot-token")
    def get_bot_token(request: Request) -> dict:
        token = store.bot_token(request.state.user_id)
        if token is None:
            raise HTTPException(404, "token not found")
        return {"token": token}

    @app.post("/v1/me/bot-token")
    def rotate_bot_token(request: Request) -> dict:
        return {"token": store.set_bot_token(request.state.user_id, new_secret())}

    @app.get("/v1/bots")
    def bots(request: Request) -> dict:
        return {"bots": [{"name": name} for name in store.list_bots(request.state.user_id)]}

    @app.get("/v1/bots/profile")
    def bot_profile(request: Request, name: str) -> dict:
        _expire(store, settings)
        found = store.get_bot(request.state.user_id, name)
        if found is None:
            raise HTTPException(404, "bot not found")
        bot_name, first_seen, bot_desc = found
        cards = store.cards_for_bot(request.state.user_id, bot_name)
        return {
            "name": bot_name,
            "first_seen": first_seen,
            "bot_desc": bot_desc,
            "cards": [_card_json(card, request) for card in cards],
        }

    @app.delete("/v1/bots/profile", status_code=204)
    def delete_bot_name(request: Request, name: str) -> None:
        if not store.delete_bot(request.state.user_id, name):
            raise HTTPException(404, "bot not found")

    @app.get("/v1/categories")
    def categories() -> dict[str, list[str]]:
        return {"categories": list(CATEGORIES)}

    @app.get("/v1/feed")
    def feed(request: Request, limit: int = 30, offset: int = 0, category: str | None = None) -> dict:
        if category is not None and category not in CATEGORIES:
            raise HTTPException(400, "unknown category")
        limit = min(max(limit, 1), 100)
        offset = max(offset, 0)
        _expire(store, settings)
        cards = store.list_cards(
            category=category,
            limit=limit,
            offset=offset,
            user_id=request.state.user_id,
        )
        return {"cards": [_card_json(card, request) for card in cards]}

    @app.get("/v1/feed/{card_id}")
    def feed_one(card_id: str, request: Request) -> dict:
        _expire(store, settings)
        card = store.get_card(card_id, user_id=request.state.user_id)
        if card is None:
            raise HTTPException(404, "card not found")
        return _card_json(card, request)

    @app.delete("/v1/feed/{card_id}", status_code=204)
    def delete_card(card_id: str, request: Request) -> None:
        removed = store.delete_card(card_id, user_id=request.state.user_id)
        if removed is None:
            raise HTTPException(404, "card not found")
        for name in removed:
            _unlink(settings, name)

    @app.get("/media/{filename}")
    def media(filename: str, request: Request) -> FileResponse:
        if "/" in filename or "\\" in filename or ".." in filename or filename.startswith("."):
            raise HTTPException(404, "not found")
        if not store.user_has_image(request.state.user_id, filename):
            raise HTTPException(404, "not found")
        path = settings.media_dir / filename
        if not path.is_file():
            raise HTTPException(404, "not found")
        return FileResponse(path)

    @app.middleware("http")
    async def require_token(request: Request, call_next):
        kind = _kind(request.url.path)
        if kind is None:
            return await call_next(request)
        presented = _bearer(request)
        user_id = _user_for(store, presented, kind)
        if user_id is None:
            return JSONResponse({"detail": "invalid token"}, status_code=401)
        request.state.user_id = user_id
        request.state.token = presented
        token = current_user_id.set(user_id)
        try:
            return await call_next(request)
        finally:
            current_user_id.reset(token)

    app.add_middleware(_MCPPath)
    return app


class _MCPPath:
    def __init__(self, app) -> None:
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope.get("type") == "http" and scope.get("path") == "/mcp":
            scope = dict(scope)
            scope["path"] = "/mcp/"
            scope["raw_path"] = b"/mcp/"
        await self.app(scope, receive, send)


_OPEN_AUTH = {"/v1/auth/register", "/v1/auth/login"}


def _kind(path: str) -> str | None:
    if path.startswith("/mcp"):
        return "bot"
    bare = path.rstrip("/") or "/"
    if bare in _OPEN_AUTH:
        return None
    if path.startswith("/v1/") or path.startswith("/media/"):
        return "session"
    return None


def _bearer(request: Request) -> str:
    header = request.headers.get("authorization", "")
    if not header.startswith("Bearer "):
        return ""
    return header.removeprefix("Bearer ").strip()


def _user_for(store: Store, token: str, kind: str) -> str | None:
    if not token:
        return None
    if kind == "bot":
        return store.user_id_for_bot_token(token)
    return store.user_id_for_session(token, now=now().isoformat())


def _expire(store: Store, settings: Settings) -> None:
    cutoff = (now() - timedelta(hours=settings.message_ttl_hours)).isoformat()
    for name in store.prune(before=cutoff):
        _unlink(settings, name)


def _unlink(settings: Settings, name: str) -> None:
    if name.startswith(("http://", "https://")):
        return
    path = settings.media_dir / name
    if path.is_file() and path.parent == settings.media_dir:
        path.unlink()


def _call(action):
    try:
        return action()
    except AccountError as exc:
        raise HTTPException(exc.status, exc.detail) from exc


def _user_or_401(store: Store, user_id: str) -> User:
    user = store.user_by_id(user_id)
    if user is None:
        raise HTTPException(401, "invalid token")
    return user


def _user_json(user: User) -> dict:
    return {"id": user.id, "username": user.username}


def _settings_json(user: User) -> dict:
    return {
        "cache_mode": user.cache_mode,
        "locale": user.locale,
        "unread_only": user.unread_only,
    }


def _image_url(name: str, base: str) -> str:
    if name.startswith(("http://", "https://")):
        return name
    return f"{base}/media/{name}"


def _card_json(card: Card, request: Request) -> dict:
    base = str(request.base_url).rstrip("/")
    return {
        "id": card.id,
        "title": card.title,
        "summary": card.summary,
        "body": card.body,
        "category": card.category,
        "tags": card.tags,
        "images": [_image_url(name, base) for name in card.images],
        "source": card.source,
        "source_urls": card.source_urls,
        "created_bot": card.created_bot,
        "created_at": card.created_at,
    }


class _Register(BaseModel):
    username: str
    password: str


class _Login(BaseModel):
    username: str
    password: str


class _PasswordChange(BaseModel):
    current_password: str
    new_password: str


class _Username(BaseModel):
    username: str


class _SettingsIn(BaseModel):
    cache_mode: str | None = None
    locale: str | None = None
    unread_only: bool | None = None


def main() -> None:
    settings = load_settings()
    uvicorn.run(create_app(settings), host=settings.host, port=settings.port)
