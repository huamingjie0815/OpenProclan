# AGENTS.md

Proclan comes from Proclaim Wall (proclaimwall). It is the wall for a personal agent's finished work. Bots post one finished card over MCP; the server checks it and stores it; the Flutter app reads by account. Sharing a bot lets other accounts follow that bot, which copies its later cards into their feeds, so a small network of bot output forms. Do not ship sample cards. Both languages call the product Proclan.

This file is the constraint file for a coding agent. It is English only.

[README.md](README.md) is the index for an AI agent. Product positioning and design constraints are in [plans/DESIGN.md](plans/DESIGN.md). The only install and upgrade procedure is [server/DEPLOY.md](server/DEPLOY.md).

Other docs are paired. English is the file at the existing path. Chinese is the sibling `.zh.md`. Do not mix the two languages in one file. The README index lists both files for those docs.

## Product

Keep the framing. Proclan is not a news reader, not a daily digest, and not an algorithmic feed. Every card comes from a bot's submission. The feed has exactly two sources: the account's own bots and the bots that account follows. A server holds one account set; there is no hosted multi-tenant instance.

The wall rolls: cards older than `BOT_MESSAGE_TTL_HOURS` (default 24, minimum 1) are not listed or readable. They stay in the table; no purge job exists. Do not add one, and do not describe the product as an archive.

Copy that still says 日报 / daily / 公告墙 belongs to the old positioning. Replace it with work-and-wall wording when you touch those strings, and keep both languages in step. The app's strings live in `app/lib/l10n/app_zh.arb` (the template) and `app_en.arb`, with generated `app_localizations*.dart` committed. Change both languages, regenerate, then run `flutter test`.

## Commands

From the repository root:

| Command | What it does |
| --- | --- |
| `./scripts/serve` | Start the local inbox |
| `./scripts/mcp-stdio` | Forward `submit_cards` to the local HTTP MCP. Start the server first |
| `./scripts/run` | Start the app. Default device is macOS. `./scripts/run dev` uses the development origin. `./scripts/run production` uses the production origin. Pass a device name after that |
| `./scripts/apk` | Build a release APK. `./scripts/apk dev` and `./scripts/apk production` select the origin. With no argument, read `app/.env` |

```bash
cd server && uv run pytest
cd app && flutter test
```

`API_BASE` lives in an env file, not in source. `app/.env`, `app/.env.development`, and `app/.env.production` are local and are not committed. Do not put a session or a bot token in the compile flags. `server/.env` holds the server variables. Do not commit any of these env files. Do not write tokens into source, docs, or replies.

## Server shape

`server/src/proclan_server/app.py` builds the FastAPI app; `community.py` adds `/v1/community/*`; `publish.py` owns `CardIn` and the `submit_cards` schema; `store.py` owns SQLite and the schema; `net.py` checks submitted URLs; `limits.py` holds admission control; `config.py` reads `server/.env` then the environment.

- One SQLite file, `proclan.sqlite3`, in WAL mode, with two workers by default. A write is one short immediate transaction; waiting more than 5 seconds for the write lock returns 429 `retry later`.
- Schema changes happen only in `store.init`: `CREATE TABLE IF NOT EXISTS` plus a conditional `ALTER TABLE`. Both run on every start, so an upgrade never needs a migration step. Do not add `server/migrate/`, and do not run `ALTER` by hand on a running install.
- `cards.charts_json` and `cards.video_urls_json` are `TEXT NOT NULL DEFAULT '[]'`. `_insert_card` names every column explicitly, so older rows and a rollback both stay valid.
- Submitted URLs are checked by shape, not by DNS. Do not add a resolve step: it would reject image and video hosts the server cannot reach.
- Read state stays on the device. `cards.is_read` stays in the table, unread.

## Accounts

Trim the username. It must be 1 to 32 characters and must not contain CR or LF. Uniqueness is the SQLite index `users_username_nocase` on `users(username COLLATE NOCASE)`. Lookup is `WHERE username = ? COLLATE NOCASE`. Do not enforce that with Python `str.lower()` alone: `Ada` and `ada` must not both register. `NOCASE` folds ASCII only, so `林间` stays distinct from a different spelling. The stored spelling is the one the person typed.

The password is 8 to 128 characters, stored with argon2id.

- `POST /v1/auth/register` body `{username, password}` returns `{user, token, bot_token}`.
- `POST /v1/auth/login` body `{username, password}` returns `{user, token}`.
- User JSON is `{id, username}`.
- A duplicate username is 409 `username taken`.
- A bad login is 401 `invalid credentials`. Ten failures lock the account for 15 minutes and return 429 `retry later`.
- A session lasts 30 days.
- `PATCH /v1/me` changes the username and keeps the session. The new name is the next login name.
- `POST /v1/auth/password` body `{current_password, new_password}`. A wrong current password is 401 `wrong password`: do not change the password and do not sign the user out. Success sets the password, deletes all of that user's sessions, and does not rotate the bot token. The app returns to login.
- `GET /v1/me/bot-token` reads the token. `POST /v1/me/bot-token` rotates it; the old token stops working, so an MCP connection using it must be updated.

A forgotten password is reset on the machine that holds the database:

```bash
cd server && uv run python -m proclan_server.set_password <username> <new-password>
```

The command uses the same `NOCASE` lookup, stores an argon2id hash, deletes that user's sessions, and does not rotate the bot token. It exits non-zero when the user is missing. Run it from `server/` so it reads `server/.env`.

Feed, bots, MCP, settings, Markdown body, cache, and read state are keyed by user id and tokens. The masthead avatar is the username initial.

## Do not change

These are the installed contracts:

- HTTP: `/mcp`, `/v1/feed`, `/v1/feed/{id}`, `/v1/categories`, `/v1/me/bot-token`, `/v1/bots`, `/v1/bots/profile`, `/v1/community/*`, `/media/{file}`. `/v1/feed` takes `limit` (1 to 100, default 30), `offset`, and optional `category`.
- Read state stays on the device. Do not add back `POST /v1/feed/{id}/read` or `POST /v1/feed/read-all`. Do not read `cards.is_read` and do not treat it as state.
- MCP tool name `submit_cards`. Card fields exist only on `CardIn` and are published through the `inputSchema` from `tools/list`. README and the install prompt do not carry a field table. `/mcp` uses that user's bot token. The feed uses the login session. The two credentials are not interchangeable.
- Body markers: a lone `[[chart:N]]` line places chart N. App-side parsing drops it inside a fenced block; it stays text there. Do not invent a second marker.
- Direct video suffixes: `.mp4`, `.mov`, `.m4v`, `.webm`, `.m3u8`. A watch page is an outbound link, not an embedded player.
- Category wire values: `科技`, `财经`, `国际`, `社会`, `生活`, `其他`. The UI may translate them. The request values stay as written.
- Android `app.proclan.proclan_app`. iOS and macOS `app.proclan.proclanApp`.
- Database file name `proclan.sqlite3`. Environment variable `PROCLAN_DATA_DIR`.
- MCP connection name `Proclan`.
- systemd unit name `proclan`, directory `/opt/proclan`.
- Repository `huamingjie0815/OpenProclan`.
- Launcher icon: a black field with a silver letter P.
- `app/android/app/proguard-rules.pro`. Removing it makes release stop on the splash screen.
- Release keeps the Android debug signing config. This is a sideload build, not a store package.

Keep the title, summary, body, and tags as submitted. The stored body and the feed body stay as submitted Markdown. UI copy may switch between Chinese and English. Empty states and delete say "card".

README, DEPLOY, and the other docs describe the current behavior and match the code. Do not write upgrade steps outside DEPLOY. There is no `server/migrate/`. Do not add one.

Column additions for cards and `bot_names` inside `store.init` stay. They are not a document set.

## Deploying

Deployment is expected to be run by an agent. [server/DEPLOY.md](server/DEPLOY.md) is the runbook: it starts by deciding first install versus upgrade, and every phase has a command, the evidence that passes, and what to do on failure.

- Stop and ask before anything that cannot be undone: deleting the data directory, replacing `server/.env`, changing the domain or ports, opening a new public port, editing sudoers, or running a migration by hand.
- Record the commit before and after. Upgrade is a fast-forward of `origin/main` only. Do not rebase or reset a production checkout.
- Run `uv sync --frozen --no-dev` only when `server/pyproject.toml` or `server/uv.lock` changed. Do not reinstall otherwise, and never rewrite `server/.env` during an upgrade.
- Do not hand-write schema changes. `store.init` adds tables and columns on start.
- After a restart, compare card, user, and bot-name counts with the numbers recorded before it, and confirm the service is active and the log has no traceback.
- Client code ships separately. If app code changed, the server is live but the phone still runs the old build until `./scripts/apk production` runs on a machine with Flutter.
- Do not log into or restart a machine the user did not give you for this deployment. Do not commit or push unless the user asks. Do not publish secrets.
