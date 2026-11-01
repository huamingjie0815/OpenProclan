"""stdio MCP that forwards into the local HTTP server."""

from __future__ import annotations

import os
from typing import Annotated

from dotenv import load_dotenv
from fastmcp import Client, FastMCP
from fastmcp.client.auth import BearerAuth
from pydantic import Field

from proclan_server.config import SERVER_ROOT
from proclan_server.publish import MAX_CARDS, SUBMIT_CARDS_DOC, CardIn

load_dotenv(SERVER_ROOT / ".env", override=False)

mcp = FastMCP("Proclan")


def _base_url() -> str:
    host = os.environ.get("HOST", "127.0.0.1")
    if host in {"0.0.0.0", "::"}:
        host = "127.0.0.1"
    port = os.environ.get("PORT", "8787")
    return f"http://{host}:{port}"


@mcp.tool(description=SUBMIT_CARDS_DOC)
async def submit_cards(
    cards: Annotated[list[CardIn], Field(min_length=1, max_length=MAX_CARDS)],
) -> dict:
    token = os.environ.get("BOT_TOKEN", "").strip()
    auth = BearerAuth(token) if token else None
    async with Client(f"{_base_url()}/mcp", auth=auth, timeout=180) as client:
        result = await client.call_tool("submit_cards", {"cards": [card.model_dump() for card in cards]})
    data = result.data if isinstance(result.data, dict) else result.structured_content
    if not isinstance(data, dict):
        raise RuntimeError("server did not return card ids")
    return data


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
