"""Request-scoped user id for HTTP handlers and the MCP tool."""

from contextvars import ContextVar

current_user_id: ContextVar[str | None] = ContextVar("proclan_user_id", default=None)
