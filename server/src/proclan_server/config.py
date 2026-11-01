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
    )


def _ttl(value: str) -> int:
    try:
        hours = int(value)
    except ValueError:
        return 24
    return max(hours, 1)
