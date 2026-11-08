# AGENTS.md

Proclan comes from Proclaim Wall (proclaimwall). It is the announcement wall for a personal agent. An agent submits finished cards over MCP. The server checks them, stores the submitted image URLs, and inserts them. The Flutter app reads by account. Do not ship sample cards. Both languages call the product Proclan.

This file is the constraint file for a coding agent. It is English only.

[README.md](README.md) is the index for an AI agent. Design constraints are in [plans/DESIGN.md](plans/DESIGN.md). The only install procedure is [server/DEPLOY.md](server/DEPLOY.md).

Other docs are paired. English is the file at the existing path. Chinese is the sibling `.zh.md`. Do not mix the two languages in one file. The README index lists both files for those docs.

## Commands

From the repository root:

| Command | What it does |
| --- | --- |
| `./scripts/serve` | Start the local inbox |
| `./scripts/mcp-stdio` | Forward `submit_cards` to the local HTTP MCP. Start the server first |
| `./scripts/run` | Start the app. Default device is macOS. Pass another device name after the command |
| `./scripts/apk` | Build a release APK |

```bash
cd server && uv run pytest
cd app && flutter test
```

`API_BASE` lives only in `app/.env`. Do not put a session or a bot token in the compile flags. `server/.env` holds the server variables. Commit neither file. Do not write those values into source, docs, or replies.

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

A forgotten password is reset on the machine that holds the database:

```bash
cd server && uv run python -m proclan_server.set_password <username> <new-password>
```

The command uses the same `NOCASE` lookup, stores an argon2id hash, deletes that user's sessions, and does not rotate the bot token. It exits non-zero when the user is missing. Run it from `server/` so it reads `server/.env`.

Feed, bots, MCP, settings, Markdown body, cache, and read state are keyed by user id and tokens. The masthead avatar is the username initial.

## Do not change

These are the installed contracts:

- HTTP: `/mcp`, `/v1/feed`, `/v1/feed/{id}`, `/v1/categories`, `/media/{file}`
- Read state stays on the device. Do not add back `POST /v1/feed/{id}/read` or `POST /v1/feed/read-all`. Leave the `cards.is_read` column. Do not read it, and do not treat it as state.
- MCP tool name `submit_cards`. Card fields exist only on `CardIn` and are published through the `inputSchema` from `tools/list`. README and the install prompt do not carry a field table. `/mcp` uses that user's bot token. The feed uses the login session. The two credentials are not interchangeable.
- Category wire values: `科技`, `财经`, `国际`, `社会`, `生活`, `其他`. The UI may translate them. The request values stay as written.
- Android `app.proclan.proclan_app`. iOS and macOS `app.proclan.proclanApp`.
- Database file name `proclan.sqlite3`. Environment variable `PROCLAN_DATA_DIR`.
- MCP connection name `Proclan`.
- systemd unit name `proclan`, directory `/opt/proclan`.
- Repository `huamingjie0815/OpenProclan`.
- Launcher icon: a black field with a silver letter P.
- `app/android/app/proguard-rules.pro`. Removing it makes release stop on the splash screen.
- Release keeps the Android debug signing config. This is a sideload build, not a store package.

Keep the title, summary, body, and tags as submitted. UI copy may switch between Chinese and English. Empty states and delete say "card".

README, DEPLOY, and the other docs describe the current behavior and match the code. Do not write upgrade steps. There is no `server/migrate/`. Do not add one.

Column additions for cards and `bot_names` inside `store.init` stay. They are not a document set.

Do not log into or restart a machine the user did not give you for this deployment. On a machine they did give you, install and restart only by [server/DEPLOY.md](server/DEPLOY.md). Do not commit or push unless the user asks. Do not publish secrets.
