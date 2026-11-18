"""SQLite storage. One immediate write transaction at a time. Reads stay reads."""

from __future__ import annotations

import json
import secrets
import sqlite3
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

from proclan_server.hashing import digest, new_secret
from proclan_server.limits import (
    DatabaseBusy,
    NameCap,
    RateLimited,
    bot_limit_error,
    name_cap_error,
    name_rate_error,
)


@dataclass
class Card:
    id: str
    message_id: str
    title: str
    summary: str
    body: str
    category: str
    tags: list[str]
    images: list[str]
    source: str
    source_urls: list[str]
    created_bot: str
    processor: str
    is_read: bool
    created_at: str
    user_id: str | None = None
    source_user_id: str | None = None
    source_bot_name: str | None = None
    source_card_id: str | None = None
    source_username: str | None = None
    charts: list[dict] = field(default_factory=list)
    video_urls: list[str] = field(default_factory=list)


class CommunityError(Exception):
    def __init__(self, status: int, detail: str) -> None:
        super().__init__(detail)
        self.status = status
        self.detail = detail


_CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"


@dataclass
class User:
    id: str
    username: str
    password_hash: str
    cache_mode: str
    locale: str
    unread_only: bool
    login_fails: int
    locked_until: str | None
    created_at: str


class Store:
    def __init__(self, path: Path) -> None:
        self.path = path

    def init(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        last: sqlite3.OperationalError | None = None
        for attempt in range(5):
            try:
                self._init_schema()
                return
            except sqlite3.OperationalError as exc:
                last = exc
                time.sleep(0.05 * (attempt + 1))
        if last is not None:
            raise last

    def _init_schema(self) -> None:
        conn = self._open()
        try:
            self._create_schema(conn)
        finally:
            conn.close()

    def _create_schema(self, conn: sqlite3.Connection) -> None:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS cards (
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
                    charts_json TEXT NOT NULL DEFAULT '[]',
                    video_urls_json TEXT NOT NULL DEFAULT '[]',
                    created_bot TEXT NOT NULL DEFAULT '',
                    processor TEXT NOT NULL,
                    is_read INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_cards_created ON cards(created_at DESC);
                CREATE INDEX IF NOT EXISTS idx_cards_category ON cards(category, created_at DESC);

                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    username TEXT NOT NULL,
                    password_hash TEXT NOT NULL,
                    cache_mode TEXT NOT NULL DEFAULT '7d',
                    locale TEXT NOT NULL DEFAULT 'system',
                    unread_only INTEGER NOT NULL DEFAULT 0,
                    login_fails INTEGER NOT NULL DEFAULT 0,
                    locked_until TEXT,
                    created_at TEXT NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS users_username_nocase
                    ON users(username COLLATE NOCASE);

                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    expires_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS bot_tokens (
                    user_id TEXT PRIMARY KEY,
                    token TEXT NOT NULL,
                    token_hash TEXT NOT NULL UNIQUE
                );

                CREATE TABLE IF NOT EXISTS bot_names (
                    user_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    bot_desc TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (user_id, name)
                );

                CREATE TABLE IF NOT EXISTS runtime (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS rate_buckets (
                    user_id TEXT NOT NULL,
                    bot_name TEXT NOT NULL,
                    tokens REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (user_id, bot_name)
                );

                CREATE TABLE IF NOT EXISTS bot_name_admission (
                    user_id TEXT PRIMARY KEY,
                    tokens REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS community_bots (
                    owner_id TEXT NOT NULL,
                    bot_name TEXT NOT NULL,
                    code TEXT NOT NULL,
                    shared_at TEXT NOT NULL,
                    listed INTEGER NOT NULL,
                    bot_desc TEXT NOT NULL DEFAULT '',
                    direct INTEGER NOT NULL DEFAULT 0,
                    opened INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (owner_id, bot_name)
                );
                CREATE UNIQUE INDEX IF NOT EXISTS community_bots_code
                    ON community_bots(code);

                CREATE TABLE IF NOT EXISTS community_grants (
                    owner_id TEXT NOT NULL,
                    bot_name TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    PRIMARY KEY (owner_id, bot_name, user_id)
                );
                CREATE INDEX IF NOT EXISTS idx_community_grants_user
                    ON community_grants(user_id);

                CREATE TABLE IF NOT EXISTS follows (
                    follower_id TEXT NOT NULL,
                    owner_id TEXT NOT NULL,
                    bot_name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    PRIMARY KEY (follower_id, owner_id, bot_name)
                );
                CREATE INDEX IF NOT EXISTS idx_follows_target
                    ON follows(owner_id, bot_name);

                CREATE TABLE IF NOT EXISTS bot_votes (
                    voter_id TEXT NOT NULL,
                    owner_id TEXT NOT NULL,
                    bot_name TEXT NOT NULL,
                    vote INTEGER NOT NULL,
                    PRIMARY KEY (voter_id, owner_id, bot_name)
                );
                CREATE INDEX IF NOT EXISTS idx_votes_target
                    ON bot_votes(owner_id, bot_name);
                """
            )
            have = {row[1] for row in conn.execute("PRAGMA table_info(cards)")}
            if "created_bot" not in have:
                conn.execute("ALTER TABLE cards ADD COLUMN created_bot TEXT NOT NULL DEFAULT ''")
            if "is_read" not in have:
                conn.execute("ALTER TABLE cards ADD COLUMN is_read INTEGER NOT NULL DEFAULT 0")
            if "user_id" not in have:
                conn.execute("ALTER TABLE cards ADD COLUMN user_id TEXT")
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_cards_user ON cards(user_id, created_at DESC)"
            )
            names = {row[1] for row in conn.execute("PRAGMA table_info(bot_names)")}
            if "bot_desc" not in names:
                conn.execute(
                    "ALTER TABLE bot_names ADD COLUMN bot_desc TEXT NOT NULL DEFAULT ''"
                )
            for column in ("source_user_id", "source_bot_name", "source_card_id"):
                if column not in have:
                    conn.execute(f"ALTER TABLE cards ADD COLUMN {column} TEXT")
            for column in ("charts_json", "video_urls_json"):
                if column not in have:
                    conn.execute(
                        f"ALTER TABLE cards ADD COLUMN {column} TEXT NOT NULL DEFAULT '[]'"
                    )
            community = {row[1] for row in conn.execute("PRAGMA table_info(community_bots)")}
            if "direct" not in community:
                conn.execute(
                    "ALTER TABLE community_bots ADD COLUMN direct INTEGER NOT NULL DEFAULT 0"
                )
            if "opened" not in community:
                conn.execute(
                    "ALTER TABLE community_bots ADD COLUMN opened INTEGER NOT NULL DEFAULT 0"
                )
                conn.execute("UPDATE community_bots SET opened = 1")

    def publish_batch(
        self,
        cards: list[Card],
        bots: list[tuple[str, str, str, str]],
        *,
        burst: int,
        refill_seconds: float,
        name_cap: int = 32,
        name_burst: int = 8,
        name_refill_seconds: float = 60,
    ) -> None:
        """Insert cards and bot names, and spend card and new-name budgets, in one write."""
        moment = time.time()
        per_second = 1.0 / refill_seconds if refill_seconds > 0 else 0.5
        name_per_second = 1.0 / name_refill_seconds if name_refill_seconds > 0 else 1.0 / 60
        counts: dict[tuple[str, str], int] = {}
        for card in cards:
            key = (card.user_id or "", card.created_bot)
            counts[key] = counts.get(key, 0) + 1
        fresh: dict[tuple[str, str], tuple[str, str]] = {}
        for user_id, name, created_at, bot_desc in bots:
            fresh[(user_id, name)] = (created_at, bot_desc)
        with self._write() as conn:
            refreshed: list[tuple[str, str, float]] = []
            for (user_id, name), count in counts.items():
                row = conn.execute(
                    """
                    SELECT tokens, updated_at FROM rate_buckets
                    WHERE user_id = ? AND bot_name = ?
                    """,
                    (user_id, name),
                ).fetchone()
                if row is None:
                    tokens = float(burst)
                else:
                    elapsed = max(0.0, moment - float(row["updated_at"]))
                    tokens = min(float(burst), float(row["tokens"]) + elapsed * per_second)
                if tokens < count:
                    raise RateLimited(bot_limit_error(burst, refill_seconds))
                refreshed.append((user_id, name, tokens - count))
            new_by_user: dict[str, list[str]] = {}
            for user_id, name in fresh:
                row = conn.execute(
                    "SELECT 1 FROM bot_names WHERE user_id = ? AND name = ?",
                    (user_id, name),
                ).fetchone()
                if row is None:
                    new_by_user.setdefault(user_id, []).append(name)
            admitted: list[tuple[str, float]] = []
            for user_id, names in new_by_user.items():
                existing = conn.execute(
                    "SELECT COUNT(*) FROM bot_names WHERE user_id = ?",
                    (user_id,),
                ).fetchone()[0]
                if existing + len(names) > name_cap:
                    raise NameCap(name_cap_error(name_cap))
                row = conn.execute(
                    "SELECT tokens, updated_at FROM bot_name_admission WHERE user_id = ?",
                    (user_id,),
                ).fetchone()
                if row is None:
                    tokens = float(name_burst)
                else:
                    elapsed = max(0.0, moment - float(row["updated_at"]))
                    tokens = min(float(name_burst), float(row["tokens"]) + elapsed * name_per_second)
                if tokens < len(names):
                    raise RateLimited(name_rate_error(name_burst, name_refill_seconds))
                admitted.append((user_id, tokens - len(names)))
            for user_id, name, left in refreshed:
                conn.execute(
                    """
                    INSERT INTO rate_buckets (user_id, bot_name, tokens, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id, bot_name) DO UPDATE SET
                        tokens = excluded.tokens,
                        updated_at = excluded.updated_at
                    """,
                    (user_id, name, left, moment),
                )
            for user_id, left in admitted:
                conn.execute(
                    """
                    INSERT INTO bot_name_admission (user_id, tokens, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET
                        tokens = excluded.tokens,
                        updated_at = excluded.updated_at
                    """,
                    (user_id, left, moment),
                )
            for card in cards:
                _insert_card(conn, card)
            for (user_id, name), (created_at, bot_desc) in fresh.items():
                conn.execute(
                    """
                    INSERT INTO bot_names (user_id, name, created_at, bot_desc)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id, name) DO UPDATE SET bot_desc = excluded.bot_desc
                    """,
                    (user_id, name, created_at, bot_desc),
                )
                conn.execute(
                    """
                    UPDATE community_bots SET bot_desc = ?
                    WHERE owner_id = ? AND bot_name = ?
                    """,
                    (bot_desc, user_id, name),
                )
            _fan_out(conn, cards)

    def claim_prune(self, *, interval_seconds: float = 60) -> bool:
        moment = time.time()
        with self._write() as conn:
            row = conn.execute("SELECT value FROM runtime WHERE key = 'prune_at'").fetchone()
            if row is not None and float(row["value"]) > moment - interval_seconds:
                return False
            conn.execute(
                """
                INSERT INTO runtime (key, value) VALUES ('prune_at', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (str(moment),),
            )
            return True

    def insert_cards(self, cards: list[Card]) -> None:
        with self._write() as conn:
            for card in cards:
                _insert_card(conn, card)

    def list_bots(self, user_id: str) -> list[str]:
        with self._read() as conn:
            rows = conn.execute(
                "SELECT name FROM bot_names WHERE user_id = ? ORDER BY name",
                (user_id,),
            ).fetchall()
        return [row["name"] for row in rows]

    def get_bot(self, user_id: str, name: str) -> tuple[str, str, str] | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT name, created_at, bot_desc FROM bot_names WHERE user_id = ? AND name = ?",
                (user_id, name),
            ).fetchone()
        if row is None:
            return None
        return row["name"], row["created_at"], row["bot_desc"]

    def delete_bot(self, user_id: str, name: str) -> bool:
        with self._write() as conn:
            cursor = conn.execute(
                "DELETE FROM bot_names WHERE user_id = ? AND name = ?",
                (user_id, name),
            )
            conn.execute(
                """
                UPDATE community_bots SET listed = 0, direct = 0
                WHERE owner_id = ? AND bot_name = ?
                """,
                (user_id, name),
            )
        return cursor.rowcount == 1

    def cards_for_bot(
        self,
        user_id: str,
        name: str,
        *,
        not_before: str | None = None,
    ) -> list[Card]:
        sql = (
            f"{_CARD_SELECT} WHERE cards.user_id = ? AND cards.created_bot = ?"
            " AND cards.source_user_id IS NULL"
        )
        params: list[object] = [user_id, name]
        if not_before is not None:
            sql += " AND cards.created_at >= ?"
            params.append(not_before)
        sql += " ORDER BY cards.created_at DESC"
        with self._read() as conn:
            rows = conn.execute(sql, params).fetchall()
        return [_card(row) for row in rows]

    def list_cards(
        self,
        *,
        category: str | None,
        limit: int,
        offset: int = 0,
        user_id: str | None = None,
        not_before: str | None = None,
    ) -> list[Card]:
        sql = _CARD_SELECT
        clauses: list[str] = []
        params: list[object] = []
        if user_id is not None:
            clauses.append("cards.user_id = ?")
            params.append(user_id)
        if category:
            clauses.append("cards.category = ?")
            params.append(category)
        if not_before is not None:
            clauses.append("cards.created_at >= ?")
            params.append(not_before)
        if clauses:
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY cards.created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        with self._read() as conn:
            rows = conn.execute(sql, params).fetchall()
        return [_card(row) for row in rows]

    def get_card(
        self,
        card_id: str,
        *,
        user_id: str | None = None,
        not_before: str | None = None,
    ) -> Card | None:
        with self._read() as conn:
            row = conn.execute(f"{_CARD_SELECT} WHERE cards.id = ?", (card_id,)).fetchone()
        if row is None:
            return None
        card = _card(row)
        if user_id is not None and card.user_id != user_id:
            return None
        if not_before is not None and card.created_at < not_before:
            return None
        return card

    def user_has_image(self, user_id: str, filename: str) -> bool:
        with self._read() as conn:
            rows = conn.execute(
                "SELECT images_json FROM cards WHERE user_id = ?",
                (user_id,),
            ).fetchall()
        for row in rows:
            if filename in json.loads(row["images_json"]):
                return True
        return False

    def delete_card(self, card_id: str, *, user_id: str) -> list[str] | None:
        """Delete one owned card. Return newly unused image filenames, or None if missing."""
        with self._write() as conn:
            row = conn.execute(
                "SELECT images_json, user_id FROM cards WHERE id = ?",
                (card_id,),
            ).fetchone()
            if row is None or row["user_id"] != user_id:
                return None
            filenames = json.loads(row["images_json"])
            conn.execute("DELETE FROM cards WHERE id = ?", (card_id,))
            return _unused(conn, filenames)

    def prune(self, *, before: str) -> list[str]:
        """Delete owned cards older than `before`. Leave rows that have no user."""
        with self._write() as conn:
            rows = conn.execute(
                """
                SELECT images_json FROM cards
                WHERE user_id IS NOT NULL AND created_at < ?
                """,
                (before,),
            ).fetchall()
            filenames: list[str] = []
            for row in rows:
                filenames.extend(json.loads(row["images_json"]))
            conn.execute(
                "DELETE FROM cards WHERE user_id IS NOT NULL AND created_at < ?",
                (before,),
            )
            return _unused(conn, filenames)

    def create_user(self, *, username: str, password_hash: str, created_at: str) -> User:
        user_id = str(uuid4())
        with self._write() as conn:
            conn.execute(
                """
                INSERT INTO users
                    (id, username, password_hash, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (user_id, username, password_hash, created_at),
            )
        user = self.user_by_id(user_id)
        if user is None:
            raise RuntimeError("user insert failed")
        return user

    def user_by_id(self, user_id: str) -> User | None:
        with self._read() as conn:
            row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        return _user(row) if row else None

    def user_by_username(self, username: str) -> User | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT * FROM users WHERE username = ? COLLATE NOCASE",
                (username,),
            ).fetchone()
        return _user(row) if row else None

    def set_username(self, user_id: str, username: str) -> None:
        with self._write() as conn:
            conn.execute("UPDATE users SET username = ? WHERE id = ?", (username, user_id))

    def set_password(self, user_id: str, password_hash: str) -> None:
        with self._write() as conn:
            conn.execute(
                "UPDATE users SET password_hash = ?, login_fails = 0, locked_until = NULL WHERE id = ?",
                (password_hash, user_id),
            )

    def set_settings(
        self,
        user_id: str,
        *,
        cache_mode: str | None,
        locale: str | None,
        unread_only: bool | None,
    ) -> None:
        sets: list[str] = []
        params: list[object] = []
        if cache_mode is not None:
            sets.append("cache_mode = ?")
            params.append(cache_mode)
        if locale is not None:
            sets.append("locale = ?")
            params.append(locale)
        if unread_only is not None:
            sets.append("unread_only = ?")
            params.append(1 if unread_only else 0)
        if not sets:
            return
        params.append(user_id)
        with self._write() as conn:
            conn.execute(f"UPDATE users SET {', '.join(sets)} WHERE id = ?", params)

    def record_login_failure(self, user_id: str, *, now: str, lock_until: str) -> None:
        """Count one bad password. Ten failures lock the account. The tenth stays 401."""
        with self._write() as conn:
            row = conn.execute(
                "SELECT login_fails, locked_until FROM users WHERE id = ?",
                (user_id,),
            ).fetchone()
            if row is None:
                return
            locked = row["locked_until"]
            if locked and locked > now:
                return
            fails = 0 if locked else int(row["login_fails"])
            fails += 1
            if fails >= 10:
                conn.execute(
                    "UPDATE users SET login_fails = 0, locked_until = ? WHERE id = ?",
                    (lock_until, user_id),
                )
                return
            conn.execute(
                "UPDATE users SET login_fails = ?, locked_until = NULL WHERE id = ?",
                (fails, user_id),
            )

    def clear_login_failures(self, user_id: str) -> None:
        with self._write() as conn:
            conn.execute(
                "UPDATE users SET login_fails = 0, locked_until = NULL WHERE id = ?",
                (user_id,),
            )

    def create_session(self, user_id: str, *, expires_at: str) -> str:
        token = new_secret()
        with self._write() as conn:
            conn.execute(
                "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)",
                (digest(token), user_id, expires_at),
            )
        return token

    def user_id_for_session(self, token: str, *, now: str) -> str | None:
        hashed = digest(token)
        with self._read() as conn:
            row = conn.execute(
                "SELECT user_id, expires_at FROM sessions WHERE token_hash = ?",
                (hashed,),
            ).fetchone()
        if row is None:
            return None
        if row["expires_at"] <= now:
            with self._write() as conn:
                conn.execute("DELETE FROM sessions WHERE token_hash = ?", (hashed,))
            return None
        return row["user_id"]

    def delete_session(self, token: str) -> None:
        with self._write() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash = ?", (digest(token),))

    def delete_sessions(self, user_id: str) -> None:
        with self._write() as conn:
            conn.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))

    def set_bot_token(self, user_id: str, token: str) -> str:
        with self._write() as conn:
            conn.execute(
                """
                INSERT INTO bot_tokens (user_id, token, token_hash)
                VALUES (?, ?, ?)
                ON CONFLICT(user_id) DO UPDATE SET token = excluded.token, token_hash = excluded.token_hash
                """,
                (user_id, token, digest(token)),
            )
        return token

    def bot_token(self, user_id: str) -> str | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT token FROM bot_tokens WHERE user_id = ?",
                (user_id,),
            ).fetchone()
        return row["token"] if row else None

    def user_id_for_bot_token(self, token: str) -> str | None:
        with self._read() as conn:
            row = conn.execute(
                "SELECT user_id FROM bot_tokens WHERE token_hash = ?",
                (digest(token),),
            ).fetchone()
        return row["user_id"] if row else None

    def community_for_owner(self, owner_id: str, name: str) -> dict:
        with self._read() as conn:
            return _community_owner(conn, owner_id, name)

    def share_bot(self, owner_id: str, name: str) -> dict:
        moment = now().isoformat()
        with self._write() as conn:
            bot = conn.execute(
                "SELECT bot_desc FROM bot_names WHERE user_id = ? AND name = ?",
                (owner_id, name),
            ).fetchone()
            if bot is None:
                raise CommunityError(404, "bot not found")
            row = conn.execute(
                """
                SELECT code FROM community_bots
                WHERE owner_id = ? AND bot_name = ?
                """,
                (owner_id, name),
            ).fetchone()
            if row is None:
                conn.execute(
                    """
                    INSERT INTO community_bots
                        (owner_id, bot_name, code, shared_at, listed, bot_desc, direct, opened)
                    VALUES (?, ?, ?, ?, 1, ?, 0, 1)
                    """,
                    (owner_id, name, _fresh_code(conn), moment, bot["bot_desc"]),
                )
            else:
                conn.execute(
                    """
                    UPDATE community_bots
                    SET listed = 1, direct = 0, opened = 1, bot_desc = ?
                    WHERE owner_id = ? AND bot_name = ?
                    """,
                    (bot["bot_desc"], owner_id, name),
                )
            return _community_owner(conn, owner_id, name)

    def grant_bot(self, owner_id: str, name: str, username: str) -> dict:
        person = _person_name(username)
        with self._write() as conn:
            _require_bot(conn, owner_id, name)
            user_id = _user_id_by_name(conn, person)
            if user_id == owner_id:
                raise CommunityError(400, "cannot share with yourself")
            conn.execute(
                """
                INSERT INTO community_grants (owner_id, bot_name, user_id, created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(owner_id, bot_name, user_id) DO NOTHING
                """,
                (owner_id, name, user_id, now().isoformat()),
            )
            return _community_owner(conn, owner_id, name)

    def revoke_bot(self, owner_id: str, name: str, username: str) -> dict:
        person = _person_name(username)
        with self._write() as conn:
            _require_bot(conn, owner_id, name)
            user_id = _user_id_by_name(conn, person)
            conn.execute(
                """
                DELETE FROM community_grants
                WHERE owner_id = ? AND bot_name = ? AND user_id = ?
                """,
                (owner_id, name, user_id),
            )
            return _community_owner(conn, owner_id, name)

    def set_direct(self, owner_id: str, name: str, on: bool) -> dict:
        moment = now().isoformat()
        with self._write() as conn:
            bot = _require_bot(conn, owner_id, name)
            row = conn.execute(
                """
                SELECT listed FROM community_bots
                WHERE owner_id = ? AND bot_name = ?
                """,
                (owner_id, name),
            ).fetchone()
            if on:
                if row is not None and row["listed"] and _outside_follower(conn, owner_id, name):
                    raise CommunityError(409, "stop sharing first")
                if row is None:
                    conn.execute(
                        """
                        INSERT INTO community_bots
                            (owner_id, bot_name, code, shared_at, listed, bot_desc, direct, opened)
                        VALUES (?, ?, ?, ?, 0, ?, 1, 0)
                        """,
                        (owner_id, name, _fresh_code(conn), moment, bot["bot_desc"]),
                    )
                else:
                    conn.execute(
                        """
                        UPDATE community_bots
                        SET listed = 0, direct = 1, bot_desc = ?
                        WHERE owner_id = ? AND bot_name = ?
                        """,
                        (bot["bot_desc"], owner_id, name),
                    )
            elif row is not None:
                conn.execute(
                    """
                    UPDATE community_bots SET direct = 0
                    WHERE owner_id = ? AND bot_name = ?
                    """,
                    (owner_id, name),
                )
            return _community_owner(conn, owner_id, name)

    def unshare_bot(self, owner_id: str, name: str) -> dict:
        with self._write() as conn:
            row = conn.execute(
                """
                SELECT 1 FROM community_bots
                WHERE owner_id = ? AND bot_name = ?
                """,
                (owner_id, name),
            ).fetchone()
            if row is None:
                raise CommunityError(404, "bot not found")
            conn.execute(
                """
                UPDATE community_bots SET listed = 0
                WHERE owner_id = ? AND bot_name = ?
                """,
                (owner_id, name),
            )
            return _community_owner(conn, owner_id, name)

    def follow_bot(self, follower_id: str, owner_id: str, name: str) -> None:
        if follower_id == owner_id:
            raise CommunityError(400, "cannot follow yourself")
        with self._write() as conn:
            _require_receivable(conn, follower_id, owner_id, name)
            conn.execute(
                """
                INSERT INTO follows (follower_id, owner_id, bot_name, created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(follower_id, owner_id, bot_name)
                    DO UPDATE SET created_at = excluded.created_at
                """,
                (follower_id, owner_id, name, now().isoformat()),
            )

    def unfollow_bot(self, follower_id: str, owner_id: str, name: str) -> None:
        with self._write() as conn:
            conn.execute(
                """
                DELETE FROM follows
                WHERE follower_id = ? AND owner_id = ? AND bot_name = ?
                """,
                (follower_id, owner_id, name),
            )

    def vote_bot(self, voter_id: str, owner_id: str, name: str, vote: int) -> None:
        if vote not in (-1, 0, 1):
            raise CommunityError(400, "bad vote")
        if voter_id == owner_id:
            raise CommunityError(400, "cannot vote on yourself")
        with self._write() as conn:
            _require_listed(conn, owner_id, name)
            if vote == 0:
                conn.execute(
                    """
                    DELETE FROM bot_votes
                    WHERE voter_id = ? AND owner_id = ? AND bot_name = ?
                    """,
                    (voter_id, owner_id, name),
                )
                return
            conn.execute(
                """
                INSERT INTO bot_votes (voter_id, owner_id, bot_name, vote)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(voter_id, owner_id, bot_name)
                    DO UPDATE SET vote = excluded.vote
                """,
                (voter_id, owner_id, name, vote),
            )

    def community_board(self, kind: str, *, limit: int = 50) -> list[dict]:
        order = "likes" if kind == "likes" else "follows"
        with self._read() as conn:
            rows = conn.execute(
                f"""
                {_COMMUNITY_SELECT}
                WHERE c.listed = 1
                ORDER BY {order} DESC, c.shared_at ASC, c.bot_name ASC, c.owner_id ASC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [_public_bot(row, rank=index + 1) for index, row in enumerate(rows)]

    def community_search(self, viewer_id: str, query: str) -> list[dict]:
        text = "".join(query.split())
        if not text:
            return []
        code = text.upper()
        with self._read() as conn:
            found: list[dict] = []
            skip: tuple[str, str] | None = None
            if len(code) == 8 and all(character in _CODE_ALPHABET for character in code):
                row = conn.execute(
                    f"{_COMMUNITY_SELECT} WHERE c.code = ? COLLATE NOCASE",
                    (code,),
                ).fetchone()
                if row is not None and _code_visible(conn, row, viewer_id):
                    found.append(_public_bot(row))
                    skip = (row["owner_id"], row["bot_name"])
            needle = _like(query.strip())
            rows = conn.execute(
                f"""
                {_COMMUNITY_SELECT}
                WHERE c.listed = 1
                  AND (
                    c.bot_name LIKE ? ESCAPE '\\'
                    OR u.username LIKE ? ESCAPE '\\' COLLATE NOCASE
                  )
                ORDER BY follows DESC, c.shared_at ASC, c.bot_name ASC, c.owner_id ASC
                """,
                (needle, needle),
            ).fetchall()
        for row in rows:
            if skip == (row["owner_id"], row["bot_name"]):
                continue
            found.append(_public_bot(row))
        return found

    def community_detail(
        self,
        viewer_id: str,
        owner_id: str,
        name: str,
        *,
        not_before: str | None = None,
    ) -> dict:
        with self._read() as conn:
            row = conn.execute(
                f"{_COMMUNITY_SELECT} WHERE c.owner_id = ? AND c.bot_name = ?",
                (owner_id, name),
            ).fetchone()
            if row is None:
                raise CommunityError(404, "bot not found")
            follow = conn.execute(
                """
                SELECT 1 FROM follows
                WHERE follower_id = ? AND owner_id = ? AND bot_name = ?
                """,
                (viewer_id, owner_id, name),
            ).fetchone()
            if not _visible(conn, row, viewer_id, following=follow is not None):
                raise CommunityError(404, "bot not found")
            vote = conn.execute(
                """
                SELECT vote FROM bot_votes
                WHERE voter_id = ? AND owner_id = ? AND bot_name = ?
                """,
                (viewer_id, owner_id, name),
            ).fetchone()
            direct = _direct_for(conn, row, viewer_id)
            card = _latest_original(conn, owner_id, name, not_before)
        body = _public_bot(row)
        body["direct"] = direct
        body["following"] = follow is not None
        body["vote"] = int(vote["vote"]) if vote is not None else 0
        body["mine"] = viewer_id == owner_id
        body["card"] = card
        return body

    def community_directed(self, viewer_id: str) -> list[dict]:
        with self._read() as conn:
            rows = conn.execute(
                f"""
                {_COMMUNITY_SELECT}
                WHERE c.direct = 1
                  AND EXISTS (
                    SELECT 1 FROM community_grants g
                    WHERE g.owner_id = c.owner_id AND g.bot_name = c.bot_name
                      AND g.user_id = ?
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM follows f
                    WHERE f.follower_id = ? AND f.owner_id = c.owner_id
                      AND f.bot_name = c.bot_name
                  )
                ORDER BY u.username COLLATE NOCASE, c.bot_name ASC
                """,
                (viewer_id, viewer_id),
            ).fetchall()
        return [_public_bot(row) for row in rows]

    def community_following(self, follower_id: str) -> list[dict]:
        with self._read() as conn:
            rows = conn.execute(
                """
                SELECT f.owner_id, f.bot_name, u.username AS owner_name,
                       COALESCE(c.listed, 0) AS listed,
                       COALESCE(c.bot_desc, '') AS bot_desc,
                       CASE
                         WHEN c.direct = 1 AND EXISTS (
                           SELECT 1 FROM community_grants g
                           WHERE g.owner_id = f.owner_id AND g.bot_name = f.bot_name
                             AND g.user_id = f.follower_id
                         ) THEN 1
                         ELSE 0
                       END AS direct
                FROM follows f
                JOIN users u ON u.id = f.owner_id
                LEFT JOIN community_bots c
                    ON c.owner_id = f.owner_id AND c.bot_name = f.bot_name
                WHERE f.follower_id = ?
                ORDER BY u.username COLLATE NOCASE, f.bot_name
                """,
                (follower_id,),
            ).fetchall()
        groups: list[dict] = []
        index: dict[str, dict] = {}
        for row in rows:
            group = index.get(row["owner_id"])
            if group is None:
                group = {
                    "owner_id": row["owner_id"],
                    "owner_name": row["owner_name"],
                    "bots": [],
                }
                index[row["owner_id"]] = group
                groups.append(group)
            group["bots"].append(
                {
                    "name": row["bot_name"],
                    "listed": bool(row["listed"]),
                    "direct": bool(row["direct"]),
                    "bot_desc": row["bot_desc"],
                }
            )
        return groups

    def community_copies(
        self,
        viewer_id: str,
        owner_id: str,
        name: str,
        *,
        not_before: str | None = None,
    ) -> dict:
        with self._read() as conn:
            owner = conn.execute(
                "SELECT username FROM users WHERE id = ?",
                (owner_id,),
            ).fetchone()
            if owner is None:
                raise CommunityError(404, "bot not found")
            community = conn.execute(
                """
                SELECT listed, direct, opened, bot_desc FROM community_bots
                WHERE owner_id = ? AND bot_name = ?
                """,
                (owner_id, name),
            ).fetchone()
            follow = conn.execute(
                """
                SELECT 1 FROM follows
                WHERE follower_id = ? AND owner_id = ? AND bot_name = ?
                """,
                (viewer_id, owner_id, name),
            ).fetchone()
            if community is not None and not _visible(
                conn,
                {
                    "owner_id": owner_id,
                    "bot_name": name,
                    "listed": community["listed"],
                    "direct": community["direct"],
                    "opened": community["opened"],
                },
                viewer_id,
                following=follow is not None,
            ):
                raise CommunityError(404, "bot not found")
            direct = community is not None and bool(community["direct"]) and (
                viewer_id == owner_id or _granted(conn, owner_id, name, viewer_id)
            )
            sql = (
                f"{_CARD_SELECT} WHERE cards.user_id = ? AND cards.source_user_id = ?"
                " AND cards.source_bot_name = ?"
            )
            params: list[object] = [viewer_id, owner_id, name]
            if not_before is not None:
                sql += " AND cards.created_at >= ?"
                params.append(not_before)
            sql += " ORDER BY cards.created_at DESC"
            cards = [_card(row) for row in conn.execute(sql, params).fetchall()]
        return {
            "owner_id": owner_id,
            "owner_name": owner["username"],
            "name": name,
            "listed": bool(community["listed"]) if community is not None else False,
            "direct": direct,
            "bot_desc": community["bot_desc"] if community is not None else "",
            "cards": cards,
        }

    def _open(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL").fetchone()
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA busy_timeout=5000")
        conn.execute("PRAGMA foreign_keys=ON")
        return conn

    @contextmanager
    def _read(self) -> Iterator[sqlite3.Connection]:
        conn = self._open()
        try:
            yield conn
        finally:
            conn.close()

    @contextmanager
    def _write(self) -> Iterator[sqlite3.Connection]:
        conn = self._open()
        started = False
        try:
            conn.execute("BEGIN IMMEDIATE")
            started = True
            yield conn
            conn.commit()
        except Exception as exc:
            if started:
                try:
                    conn.rollback()
                except sqlite3.Error:
                    pass
            if isinstance(exc, sqlite3.OperationalError) and _busy(exc):
                raise DatabaseBusy() from exc
            raise
        finally:
            conn.close()


_CARD_SELECT = """
SELECT cards.*, source_user.username AS source_username
FROM cards
LEFT JOIN users AS source_user ON source_user.id = cards.source_user_id
"""

_COMMUNITY_SELECT = """
SELECT c.owner_id, c.bot_name, c.code, c.shared_at, c.listed, c.direct, c.opened, c.bot_desc,
       u.username AS owner_name,
       (SELECT COUNT(*) FROM bot_votes v
        WHERE v.owner_id = c.owner_id AND v.bot_name = c.bot_name AND v.vote = 1) AS likes,
       (SELECT COUNT(*) FROM bot_votes v
        WHERE v.owner_id = c.owner_id AND v.bot_name = c.bot_name AND v.vote = -1) AS dislikes,
       (SELECT COUNT(*) FROM follows f
        WHERE f.owner_id = c.owner_id AND f.bot_name = c.bot_name) AS follows
FROM community_bots c
JOIN users u ON u.id = c.owner_id
"""


def _fresh_code(conn: sqlite3.Connection) -> str:
    for _ in range(8):
        code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(8))
        taken = conn.execute(
            "SELECT 1 FROM community_bots WHERE code = ?",
            (code,),
        ).fetchone()
        if taken is None:
            return code
    raise CommunityError(409, "retry later")


def _require_listed(conn: sqlite3.Connection, owner_id: str, name: str) -> None:
    row = conn.execute(
        "SELECT listed FROM community_bots WHERE owner_id = ? AND bot_name = ?",
        (owner_id, name),
    ).fetchone()
    if row is None or not row["listed"]:
        raise CommunityError(409, "not shared")


def _require_receivable(
    conn: sqlite3.Connection,
    follower_id: str,
    owner_id: str,
    name: str,
) -> None:
    row = conn.execute(
        """
        SELECT listed, direct FROM community_bots
        WHERE owner_id = ? AND bot_name = ?
        """,
        (owner_id, name),
    ).fetchone()
    if row is None:
        raise CommunityError(409, "not shared")
    if row["listed"]:
        return
    if row["direct"] and _granted(conn, owner_id, name, follower_id):
        return
    raise CommunityError(409, "not shared")


def _person_name(value: str) -> str:
    name = value.strip()
    if not name or len(name) > 32 or "\n" in name or "\r" in name:
        raise CommunityError(400, "invalid username")
    return name


def _require_bot(conn: sqlite3.Connection, owner_id: str, name: str) -> sqlite3.Row:
    row = conn.execute(
        "SELECT bot_desc FROM bot_names WHERE user_id = ? AND name = ?",
        (owner_id, name),
    ).fetchone()
    if row is None:
        raise CommunityError(404, "bot not found")
    return row


def _user_id_by_name(conn: sqlite3.Connection, username: str) -> str:
    row = conn.execute(
        "SELECT id FROM users WHERE username = ? COLLATE NOCASE",
        (username,),
    ).fetchone()
    if row is None:
        raise CommunityError(404, "user not found")
    return row["id"]


def _granted(conn: sqlite3.Connection, owner_id: str, name: str, user_id: str) -> bool:
    row = conn.execute(
        """
        SELECT 1 FROM community_grants
        WHERE owner_id = ? AND bot_name = ? AND user_id = ?
        """,
        (owner_id, name, user_id),
    ).fetchone()
    return row is not None


def _outside_follower(conn: sqlite3.Connection, owner_id: str, name: str) -> bool:
    row = conn.execute(
        """
        SELECT 1 FROM follows f
        WHERE f.owner_id = ? AND f.bot_name = ?
          AND NOT EXISTS (
            SELECT 1 FROM community_grants g
            WHERE g.owner_id = f.owner_id AND g.bot_name = f.bot_name
              AND g.user_id = f.follower_id
          )
        LIMIT 1
        """,
        (owner_id, name),
    ).fetchone()
    return row is not None


def _audience(conn: sqlite3.Connection, owner_id: str, name: str) -> list[str]:
    rows = conn.execute(
        """
        SELECT u.username
        FROM community_grants g
        JOIN users u ON u.id = g.user_id
        WHERE g.owner_id = ? AND g.bot_name = ?
        ORDER BY g.created_at ASC, u.username COLLATE NOCASE
        """,
        (owner_id, name),
    ).fetchall()
    return [row["username"] for row in rows]


def _visible(conn: sqlite3.Connection, row, viewer_id: str, *, following: bool) -> bool:
    if viewer_id == row["owner_id"] or following or row["listed"]:
        return True
    if row["direct"]:
        return _granted(conn, row["owner_id"], row["bot_name"], viewer_id)
    return bool(row["opened"])


def _direct_for(conn: sqlite3.Connection, row, viewer_id: str) -> bool:
    if not row["direct"]:
        return False
    if viewer_id == row["owner_id"]:
        return True
    return _granted(conn, row["owner_id"], row["bot_name"], viewer_id)


def _code_visible(conn: sqlite3.Connection, row, viewer_id: str) -> bool:
    if row["listed"]:
        return True
    if row["direct"]:
        return viewer_id == row["owner_id"] or _granted(
            conn, row["owner_id"], row["bot_name"], viewer_id
        )
    return bool(row["opened"])


def _community_owner(conn: sqlite3.Connection, owner_id: str, name: str) -> dict:
    row = conn.execute(
        """
        SELECT code, listed, direct FROM community_bots
        WHERE owner_id = ? AND bot_name = ?
        """,
        (owner_id, name),
    ).fetchone()
    audience = _audience(conn, owner_id, name)
    if row is None:
        return {
            "listed": False,
            "direct": False,
            "code": None,
            "likes": 0,
            "dislikes": 0,
            "follows": 0,
            "audience": audience,
        }
    likes, dislikes, follows = _counts(conn, owner_id, name)
    return {
        "listed": bool(row["listed"]),
        "direct": bool(row["direct"]),
        "code": row["code"],
        "likes": likes,
        "dislikes": dislikes,
        "follows": follows,
        "audience": audience,
    }


def _counts(conn: sqlite3.Connection, owner_id: str, name: str) -> tuple[int, int, int]:
    likes = conn.execute(
        """
        SELECT COUNT(*) FROM bot_votes
        WHERE owner_id = ? AND bot_name = ? AND vote = 1
        """,
        (owner_id, name),
    ).fetchone()[0]
    dislikes = conn.execute(
        """
        SELECT COUNT(*) FROM bot_votes
        WHERE owner_id = ? AND bot_name = ? AND vote = -1
        """,
        (owner_id, name),
    ).fetchone()[0]
    follows = conn.execute(
        """
        SELECT COUNT(*) FROM follows
        WHERE owner_id = ? AND bot_name = ?
        """,
        (owner_id, name),
    ).fetchone()[0]
    return int(likes), int(dislikes), int(follows)


def _public_bot(row: sqlite3.Row, *, rank: int | None = None) -> dict:
    body = {
        "owner_id": row["owner_id"],
        "owner_name": row["owner_name"],
        "name": row["bot_name"],
        "bot_desc": row["bot_desc"],
        "code": row["code"],
        "listed": bool(row["listed"]),
        "direct": bool(row["direct"]),
        "shared_at": row["shared_at"],
        "likes": int(row["likes"]),
        "dislikes": int(row["dislikes"]),
        "follows": int(row["follows"]),
    }
    if rank is not None:
        body["rank"] = rank
    return body


def _like(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escaped}%"


def _latest_original(
    conn: sqlite3.Connection,
    owner_id: str,
    name: str,
    not_before: str | None,
) -> Card | None:
    sql = (
        f"{_CARD_SELECT} WHERE cards.user_id = ? AND cards.created_bot = ?"
        " AND cards.source_user_id IS NULL"
    )
    params: list[object] = [owner_id, name]
    if not_before is not None:
        sql += " AND cards.created_at >= ?"
        params.append(not_before)
    sql += " ORDER BY cards.created_at DESC LIMIT 1"
    row = conn.execute(sql, params).fetchone()
    return _card(row) if row is not None else None


def _insert_card(conn: sqlite3.Connection, card: Card) -> None:
    conn.execute(
        """
        INSERT INTO cards
            (id, message_id, title, summary, body, category, tags_json, images_json,
             source, source_urls_json, charts_json, video_urls_json, created_bot, processor,
             is_read, created_at, user_id, source_user_id, source_bot_name, source_card_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            card.id,
            card.message_id,
            card.title,
            card.summary,
            card.body,
            card.category,
            json.dumps(card.tags, ensure_ascii=False),
            json.dumps(card.images, ensure_ascii=False),
            card.source,
            json.dumps(card.source_urls, ensure_ascii=False),
            json.dumps(card.charts, ensure_ascii=False),
            json.dumps(card.video_urls, ensure_ascii=False),
            card.created_bot,
            card.processor,
            0,
            card.created_at,
            card.user_id,
            card.source_user_id,
            card.source_bot_name,
            card.source_card_id,
        ),
    )


def _fan_out(conn: sqlite3.Connection, cards: list[Card]) -> None:
    for card in cards:
        if not card.user_id or card.source_user_id:
            continue
        state = conn.execute(
            """
            SELECT listed, direct FROM community_bots
            WHERE owner_id = ? AND bot_name = ?
            """,
            (card.user_id, card.created_bot),
        ).fetchone()
        if state is None or (not state["listed"] and not state["direct"]):
            continue
        if state["listed"]:
            followers = conn.execute(
                """
                SELECT follower_id FROM follows
                WHERE owner_id = ? AND bot_name = ?
                """,
                (card.user_id, card.created_bot),
            ).fetchall()
        else:
            followers = conn.execute(
                """
                SELECT f.follower_id FROM follows f
                JOIN community_grants g
                  ON g.owner_id = f.owner_id AND g.bot_name = f.bot_name
                 AND g.user_id = f.follower_id
                WHERE f.owner_id = ? AND f.bot_name = ?
                """,
                (card.user_id, card.created_bot),
            ).fetchall()
        for follower in followers:
            follower_id = follower["follower_id"]
            if follower_id == card.user_id:
                continue
            _insert_card(
                conn,
                Card(
                    id=new_id(),
                    message_id=card.message_id,
                    title=card.title,
                    summary=card.summary,
                    body=card.body,
                    category=card.category,
                    tags=list(card.tags),
                    images=list(card.images),
                    source=card.source,
                    source_urls=list(card.source_urls),
                    created_bot=card.created_bot,
                    charts=[dict(item) for item in card.charts],
                    video_urls=list(card.video_urls),
                    processor=card.processor,
                    is_read=False,
                    created_at=card.created_at,
                    user_id=follower_id,
                    source_user_id=card.user_id,
                    source_bot_name=card.created_bot,
                    source_card_id=card.id,
                ),
            )


def _busy(exc: sqlite3.OperationalError) -> bool:
    text = str(exc).lower()
    return "locked" in text or "busy" in text


def _unused(conn: sqlite3.Connection, filenames: list[str]) -> list[str]:
    used: set[str] = set()
    for row in conn.execute("SELECT images_json FROM cards"):
        used.update(json.loads(row["images_json"]))
    return [name for name in filenames if name not in used]


def _card(row: sqlite3.Row) -> Card:
    keys = row.keys()
    return Card(
        id=row["id"],
        message_id=row["message_id"],
        title=row["title"],
        summary=row["summary"],
        body=row["body"],
        category=row["category"],
        tags=json.loads(row["tags_json"]),
        images=json.loads(row["images_json"]),
        source=row["source"],
        source_urls=json.loads(row["source_urls_json"]),
        created_bot=row["created_bot"],
        processor=row["processor"],
        is_read=bool(row["is_read"]),
        created_at=row["created_at"],
        user_id=row["user_id"] if "user_id" in keys else None,
        source_user_id=row["source_user_id"] if "source_user_id" in keys else None,
        source_bot_name=row["source_bot_name"] if "source_bot_name" in keys else None,
        source_card_id=row["source_card_id"] if "source_card_id" in keys else None,
        source_username=row["source_username"] if "source_username" in keys else None,
        charts=json.loads(row["charts_json"]) if "charts_json" in keys and row["charts_json"] else [],
        video_urls=json.loads(row["video_urls_json"])
        if "video_urls_json" in keys and row["video_urls_json"]
        else [],
    )


def _user(row: sqlite3.Row) -> User:
    return User(
        id=row["id"],
        username=row["username"],
        password_hash=row["password_hash"],
        cache_mode=row["cache_mode"],
        locale=row["locale"],
        unread_only=bool(row["unread_only"]),
        login_fails=row["login_fails"],
        locked_until=row["locked_until"],
        created_at=row["created_at"],
    )


def new_id() -> str:
    return str(uuid4())


def now() -> datetime:
    return datetime.now(timezone.utc)


def session_expiry(moment: datetime | None = None) -> datetime:
    return (moment or now()) + timedelta(days=30)
