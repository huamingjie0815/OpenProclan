"""SQLite storage. Writes are serialized."""

from __future__ import annotations

import json
import sqlite3
import threading
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

from proclan_server.hashing import digest, new_secret


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
        self._lock = threading.Lock()

    def init(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as conn:
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

    def insert_cards(self, cards: list[Card]) -> None:
        with self._lock, self._connect() as conn:
            for card in cards:
                conn.execute(
                    """
                    INSERT INTO cards
                        (id, message_id, title, summary, body, category, tags_json, images_json,
                         source, source_urls_json, created_bot, processor, is_read, created_at, user_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        card.created_bot,
                        card.processor,
                        0,
                        card.created_at,
                        card.user_id,
                    ),
                )

    def remember_bot(self, user_id: str, name: str, *, created_at: str, bot_desc: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute(
                """
                INSERT INTO bot_names (user_id, name, created_at, bot_desc)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(user_id, name) DO UPDATE SET bot_desc = excluded.bot_desc
                """,
                (user_id, name, created_at, bot_desc),
            )

    def list_bots(self, user_id: str) -> list[str]:
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                "SELECT name FROM bot_names WHERE user_id = ? ORDER BY name",
                (user_id,),
            ).fetchall()
        return [row["name"] for row in rows]

    def get_bot(self, user_id: str, name: str) -> tuple[str, str, str] | None:
        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT name, created_at, bot_desc FROM bot_names WHERE user_id = ? AND name = ?",
                (user_id, name),
            ).fetchone()
        if row is None:
            return None
        return row["name"], row["created_at"], row["bot_desc"]

    def delete_bot(self, user_id: str, name: str) -> bool:
        with self._lock, self._connect() as conn:
            cursor = conn.execute(
                "DELETE FROM bot_names WHERE user_id = ? AND name = ?",
                (user_id, name),
            )
        return cursor.rowcount == 1

    def cards_for_bot(self, user_id: str, name: str) -> list[Card]:
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                """
                SELECT * FROM cards
                WHERE user_id = ? AND created_bot = ?
                ORDER BY created_at DESC
                """,
                (user_id, name),
            ).fetchall()
        return [_card(row) for row in rows]

    def list_cards(
        self,
        *,
        category: str | None,
        limit: int,
        offset: int = 0,
        user_id: str | None = None,
    ) -> list[Card]:
        sql = "SELECT * FROM cards"
        clauses: list[str] = []
        params: list[object] = []
        if user_id is not None:
            clauses.append("user_id = ?")
            params.append(user_id)
        if category:
            clauses.append("category = ?")
            params.append(category)
        if clauses:
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        with self._lock, self._connect() as conn:
            rows = conn.execute(sql, params).fetchall()
        return [_card(row) for row in rows]

    def get_card(self, card_id: str, *, user_id: str | None = None) -> Card | None:
        with self._lock, self._connect() as conn:
            row = conn.execute("SELECT * FROM cards WHERE id = ?", (card_id,)).fetchone()
        if row is None:
            return None
        card = _card(row)
        if user_id is not None and card.user_id != user_id:
            return None
        return card

    def user_has_image(self, user_id: str, filename: str) -> bool:
        with self._lock, self._connect() as conn:
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
        with self._lock, self._connect() as conn:
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
        with self._lock, self._connect() as conn:
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
        with self._lock, self._connect() as conn:
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
        with self._lock, self._connect() as conn:
            row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        return _user(row) if row else None

    def user_by_username(self, username: str) -> User | None:
        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM users WHERE username = ? COLLATE NOCASE",
                (username,),
            ).fetchone()
        return _user(row) if row else None

    def set_username(self, user_id: str, username: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute("UPDATE users SET username = ? WHERE id = ?", (username, user_id))

    def set_password(self, user_id: str, password_hash: str) -> None:
        with self._lock, self._connect() as conn:
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
        with self._lock, self._connect() as conn:
            conn.execute(f"UPDATE users SET {', '.join(sets)} WHERE id = ?", params)

    def note_login_failure(self, user_id: str, *, fails: int, locked_until: str | None) -> None:
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE users SET login_fails = ?, locked_until = ? WHERE id = ?",
                (fails, locked_until, user_id),
            )

    def clear_login_failures(self, user_id: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE users SET login_fails = 0, locked_until = NULL WHERE id = ?",
                (user_id,),
            )

    def create_session(self, user_id: str, *, expires_at: str) -> str:
        token = new_secret()
        with self._lock, self._connect() as conn:
            conn.execute(
                "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)",
                (digest(token), user_id, expires_at),
            )
        return token

    def user_id_for_session(self, token: str, *, now: str) -> str | None:
        hashed = digest(token)
        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT user_id, expires_at FROM sessions WHERE token_hash = ?",
                (hashed,),
            ).fetchone()
            if row is None:
                return None
            if row["expires_at"] <= now:
                conn.execute("DELETE FROM sessions WHERE token_hash = ?", (hashed,))
                return None
            return row["user_id"]

    def delete_session(self, token: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash = ?", (digest(token),))

    def delete_sessions(self, user_id: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))

    def set_bot_token(self, user_id: str, token: str) -> str:
        with self._lock, self._connect() as conn:
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
        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT token FROM bot_tokens WHERE user_id = ?",
                (user_id,),
            ).fetchone()
        return row["token"] if row else None

    def user_id_for_bot_token(self, token: str) -> str | None:
        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT user_id FROM bot_tokens WHERE token_hash = ?",
                (digest(token),),
            ).fetchone()
        return row["user_id"] if row else None

    @contextmanager
    def _connect(self):
        conn = sqlite3.connect(self.path, timeout=30, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()


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
