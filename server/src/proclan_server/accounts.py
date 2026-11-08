"""Register, login, and profile changes."""

from __future__ import annotations

import sqlite3
from datetime import datetime, timedelta, timezone

from proclan_server.hashing import hash_password, new_secret, verify_password
from proclan_server.store import Store, User

_CACHE = {"after_read", "1d", "7d"}
_LOCALES = {"system", "zh", "en"}


class AccountError(Exception):
    def __init__(self, status: int, detail: str) -> None:
        super().__init__(detail)
        self.status = status
        self.detail = detail


def register(store: Store, *, username: str, password: str) -> tuple[User, str, str]:
    name = _username(username)
    _password(password)
    if store.user_by_username(name) is not None:
        raise AccountError(409, "username taken")
    try:
        user = store.create_user(
            username=name,
            password_hash=hash_password(password),
            created_at=_now().isoformat(),
        )
    except sqlite3.IntegrityError as exc:
        raise AccountError(409, "username taken") from exc
    bot = store.set_bot_token(user.id, new_secret())
    session = store.create_session(user.id, expires_at=_session_expiry())
    return user, session, bot


def login(store: Store, *, username: str, password: str) -> tuple[User, str]:
    name = _username(username)
    user = store.user_by_username(name)
    if user is None:
        raise AccountError(401, "invalid credentials")
    moment = _now()
    if user.locked_until and user.locked_until > moment.isoformat():
        raise AccountError(429, "retry later")
    if not isinstance(password, str) or not verify_password(user.password_hash, password):
        store.record_login_failure(
            user.id,
            now=moment.isoformat(),
            lock_until=(moment + timedelta(minutes=15)).isoformat(),
        )
        raise AccountError(401, "invalid credentials")
    store.clear_login_failures(user.id)
    fresh = store.user_by_id(user.id)
    if fresh is None:
        raise AccountError(401, "invalid credentials")
    return fresh, store.create_session(fresh.id, expires_at=_session_expiry())


def change_password(
    store: Store, user_id: str, *, current_password: str, new_password: str
) -> None:
    user = store.user_by_id(user_id)
    if user is None:
        raise AccountError(401, "invalid token")
    if not isinstance(current_password, str) or not verify_password(user.password_hash, current_password):
        raise AccountError(401, "wrong password")
    _password(new_password)
    store.set_password(user_id, hash_password(new_password))
    store.delete_sessions(user_id)


def set_password_for(store: Store, *, username: str, new_password: str) -> None:
    name = _username(username)
    _password(new_password)
    user = store.user_by_username(name)
    if user is None:
        raise AccountError(404, "user not found")
    store.set_password(user.id, hash_password(new_password))
    store.delete_sessions(user.id)


def change_username(store: Store, user_id: str, username: str) -> User:
    name = _username(username)
    existing = store.user_by_username(name)
    if existing is not None and existing.id != user_id:
        raise AccountError(409, "username taken")
    try:
        store.set_username(user_id, name)
    except sqlite3.IntegrityError as exc:
        raise AccountError(409, "username taken") from exc
    user = store.user_by_id(user_id)
    if user is None:
        raise AccountError(401, "invalid token")
    return user


def change_settings(
    store: Store,
    user_id: str,
    *,
    cache_mode: str | None,
    locale: str | None,
    unread_only: bool | None,
) -> User:
    if cache_mode is not None and cache_mode not in _CACHE:
        raise AccountError(400, "invalid cache_mode")
    if locale is not None and locale not in _LOCALES:
        raise AccountError(400, "invalid locale")
    store.set_settings(
        user_id,
        cache_mode=cache_mode,
        locale=locale,
        unread_only=unread_only,
    )
    user = store.user_by_id(user_id)
    if user is None:
        raise AccountError(401, "invalid token")
    return user


def _username(value: object) -> str:
    if not isinstance(value, str):
        raise AccountError(400, "invalid username")
    name = value.strip()
    if not name or len(name) > 32 or "\n" in name or "\r" in name:
        raise AccountError(400, "invalid username")
    return name


def _password(value: object) -> None:
    if not isinstance(value, str) or not 8 <= len(value) <= 128:
        raise AccountError(400, "invalid password")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _session_expiry() -> str:
    return (_now() + timedelta(days=30)).isoformat()
