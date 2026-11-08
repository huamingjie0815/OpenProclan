"""Admission control. Crash shields stay in memory. Bot quotas live in SQLite."""

from __future__ import annotations

import json
import threading
from contextvars import ContextVar

from starlette.types import ASGIApp, Receive, Scope, Send

_RETRY = {"detail": "retry later"}
_TOO_BIG = {"detail": "payload too large"}

rate_limit_flag: ContextVar[dict[str, bool] | None] = ContextVar("proclan_rate_limit", default=None)


class RateLimited(Exception):
    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class DatabaseBusy(Exception):
    pass


def bot_limit_text(burst: int, refill_seconds: float) -> str:
    return (
        f"每个 bot 立刻最多 {_num(burst)} 张，之后每 {_num(refill_seconds)} 秒恢复 1 张。"
        "超出则整批不入库。"
    )


def bot_limit_error(burst: int, refill_seconds: float) -> str:
    return f"这个 bot 推得太快。{bot_limit_text(burst, refill_seconds)}请稍后再试。"


def name_limit_text(burst: int, refill_seconds: float, cap: int) -> str:
    return (
        f"每个账号最多 {_num(cap)} 个 bot 名字。"
        f"新名字立刻最多 {_num(burst)} 个，之后每 {_num(refill_seconds)} 秒再增加 1 个。"
    )


def name_rate_error(burst: int, refill_seconds: float) -> str:
    return (
        f"新的 bot 名字加得太快。立刻最多 {_num(burst)} 个，"
        f"之后每 {_num(refill_seconds)} 秒再增加 1 个。请稍后再试。"
    )


def name_cap_error(cap: int) -> str:
    return f"这个账号的 bot 名字已经有 {_num(cap)} 个。先删掉不用的，再加新的。"


class NameCap(Exception):
    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


def mark_limited() -> None:
    flag = rate_limit_flag.get()
    if flag is not None:
        flag["hit"] = True


def retry_body() -> bytes:
    return json.dumps(_RETRY).encode()


def too_big_body() -> bytes:
    return json.dumps(_TOO_BIG).encode()


class Inflight:
    def __init__(self, limit: int) -> None:
        self.limit = limit
        self._current = 0
        self._lock = threading.Lock()

    def try_enter(self) -> bool:
        with self._lock:
            if self._current >= self.limit:
                return False
            self._current += 1
            return True

    def leave(self) -> None:
        with self._lock:
            if self._current > 0:
                self._current -= 1


class BodyLimit:
    def __init__(self, app: ASGIApp, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return
        length = _content_length(scope)
        if length is not None and length > self.max_bytes:
            await _send_json(send, 413, too_big_body())
            return
        received = 0
        started = False

        async def limited_receive() -> dict:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body") or b"")
                if received > self.max_bytes:
                    raise _TooBig()
            return message

        async def limited_send(message: dict) -> None:
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, limited_send)
        except _TooBig:
            if not started:
                await _send_json(send, 413, too_big_body())


def _num(value: float) -> str:
    return f"{value:g}"


def _content_length(scope: Scope) -> int | None:
    for key, value in scope.get("headers") or []:
        if key.lower() == b"content-length":
            try:
                return int(value)
            except ValueError:
                return None
    return None


async def _send_json(send: Send, status: int, body: bytes) -> None:
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(body)).encode()),
            ],
        }
    )
    await send({"type": "http.response.body", "body": body})


class _TooBig(Exception):
    pass
