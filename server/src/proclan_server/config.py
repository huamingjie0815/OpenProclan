"""Runtime settings. Secrets stay in the environment or a gitignored .env file."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

SERVER_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(SERVER_ROOT / ".env", override=False)


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    host: str
    port: int
    message_ttl_hours: int = 24
    workers: int = 2
    bot_burst: int = 48
    bot_refill_seconds: float = 2
    bot_name_cap: int = 32
    bot_name_burst: int = 8
    bot_name_refill_seconds: float = 60
    body_bytes: int = 1024 * 1024
    mcp_inflight: int = 128
    limit_concurrency: int = 256

    @property
    def media_dir(self) -> Path:
        return self.data_dir / "media"

    @property
    def db_path(self) -> Path:
        return self.data_dir / "proclan.sqlite3"


def load_settings() -> Settings:
    data_dir = Path(os.environ.get("PROCLAN_DATA_DIR", SERVER_ROOT / "data"))
    return Settings(
        data_dir=data_dir,
        host=os.environ.get("HOST", "127.0.0.1"),
        port=int(os.environ.get("PORT", "8787")),
        message_ttl_hours=_ttl(os.environ.get("BOT_MESSAGE_TTL_HOURS", "24")),
        workers=_at_least(os.environ.get("PROCLAN_WORKERS"), minimum=1, default=2),
        bot_burst=_at_least(os.environ.get("PROCLAN_BOT_BURST"), minimum=1, default=48),
        bot_refill_seconds=_positive(os.environ.get("PROCLAN_BOT_REFILL_SECONDS"), default=2),
    )


def _ttl(value: str) -> int:
    try:
        hours = int(value)
    except ValueError:
        return 24
    return max(hours, 1)


def _at_least(value: str | None, *, minimum: int, default: int) -> int:
    if value is None or value == "":
        return default
    try:
        number = int(value)
    except ValueError:
        return default
    return number if number >= minimum else default


def _positive(value: str | None, *, default: float) -> float:
    if value is None or value == "":
        return default
    try:
        number = float(value)
    except ValueError:
        return default
    return number if number > 0 else default
