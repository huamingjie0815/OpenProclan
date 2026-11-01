"""Set a password on the machine that runs the server. This is not an HTTP route."""

from __future__ import annotations

import sys

from proclan_server.accounts import AccountError, set_password_for
from proclan_server.config import load_settings
from proclan_server.store import Store


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 2:
        print(
            "usage: python -m proclan_server.set_password <username> <new-password>",
            file=sys.stderr,
        )
        return 2
    settings = load_settings()
    store = Store(settings.db_path)
    store.init()
    try:
        set_password_for(store, username=args[0], new_password=args[1])
    except AccountError as exc:
        print(exc.detail, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
