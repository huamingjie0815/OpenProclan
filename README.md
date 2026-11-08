English | [中文](README.zh.md)

# Proclan

Proclan comes from Proclaim Wall (proclaimwall). It is the announcement wall for a personal agent.

A user or a developer pushes that agent's task progress, subscribed messages, and reported results through the Proclan MCP into the Proclan app. They land on one account. The server checks them, stores the submitted image URLs, and inserts them. It does not rewrite the text. The app reads that account's announcements.

This file is the index for an AI agent. It is not a tutorial. Install commands live only in [server/DEPLOY.md](server/DEPLOY.md).

**For Chinese-executing agents**: Use [README.zh.md](README.zh.md) and [server/DEPLOY.zh.md](server/DEPLOY.zh.md).

## Index

- [AGENTS.md](AGENTS.md) — project constraints for a coding agent
- [plans/DESIGN.md](plans/DESIGN.md) / [plans/DESIGN.zh.md](plans/DESIGN.zh.md) — app design constraints
- [server/DEPLOY.md](server/DEPLOY.md) / [server/DEPLOY.zh.md](server/DEPLOY.zh.md) — the only install procedure
- [server/README.md](server/README.md) / [server/README.zh.md](server/README.zh.md) — run the server on a dev machine
- [app/README.md](app/README.md) / [app/README.zh.md](app/README.zh.md) — run and package the app

License: [MIT](LICENSE), copyright huamingjie.

## Before deployment

Tell the developer this list and wait until every item is in hand. Do not clone, and do not install, before that. If one item is missing, stop. Do not guess. Do not install on a machine the developer did not give you. Do not replace the server with a tunnel.

### Minimum to start server install

- A Linux server the developer owns, with root access. Installing to `/opt/proclan` and writing systemd needs root.
- A domain that already resolves to that machine.
- Caddy or Nginx. For Nginx, also the certificate file paths.

### Can defer

- The computer that will run the Flutter app. The app is not installed on the server. If you cannot reach the Flutter machine now, report the https origin to the developer and leave `API_BASE` for them to set later.

### Clone

After the list is complete, clone `https://github.com/huamingjie0815/OpenProclan.git`. HTTPS is the default.

If the clone fails (private repo, 404, network error), stop and ask how this machine should reach the repository. The usual fix for a private repo is SSH: `git@github.com:huamingjie0815/OpenProclan.git`. Do not invent another URL.

Follow [server/DEPLOY.md](server/DEPLOY.md).

### When done

Tell the developer three things: the https origin, whether the app points at that origin, and the connection name `Proclan`. Do not recap the commands. Leave the bot token out of that summary unless the developer must paste it once. If they must paste it, tell them not to forward it.

### Done when

1. `https://<domain>/openapi.json` returns 200. `https://<domain>/v1/categories` without a session returns 401.
2. The person has registered in the app (username + password) and copied their bot token from the bot page. `https://<domain>/mcp` initialize with `Authorization: Bearer <that token>` returns a body that contains `protocolVersion`. You can also use the `bot_token` from the register response.
3. On the computer that runs the app, `app/.env` contains only `API_BASE`, and the value is that https origin. No token.
4. That person has a remote HTTPS MCP named `Proclan`. Its tool list is only `submit_cards`. The request header is that person's bot token (not the session token).

If the public curl fails but loopback `/openapi.json` returns 200 and the proxy config is correct, report that to the person. DNS propagation, ICP filing, or upstream firewall may still block the public edge. Do not loop forever waiting for external access.

### Leave these alone

- Repository `https://github.com/huamingjie0815/OpenProclan.git`, directory `/opt/proclan`
- Paths: `/mcp`, `/v1/feed`, `/v1/feed/{id}`, `/v1/categories`, `/media/{file}`
- Tool name `submit_cards`
- Category wire values: `科技`, `财经`, `国际`, `社会`, `生活`, `其他`
- systemd unit name `proclan`. One process. Do not set `WEB_CONCURRENCY`. Do not add workers.
- Connection name `Proclan`. Auth is the static header `Authorization: Bearer <the person's bot token>`, not OAuth. Copy the token from the app's bot page. Do not generate one. Do not write it into `app/.env`.
- Database file name `proclan.sqlite3`

There is no global ingest token. The app build needs `API_BASE` only. The bot token lives only in that person's MCP connection header. Do not write it into the repository, a commit, a prompt, a routine, or a skill. Do not commit either `.env`.

Open ports 80 and 443 only. Leave `8787` on the machine for the reverse proxy.

### Accounts

After trim, the username is 1 to 32 characters and must not contain a line break. ASCII case is one account: `Ada` and `ada` cannot both register. The stored spelling is the one the person typed. The password is 8 to 128 characters.

`POST /v1/auth/register` takes `{username, password}` and returns `{user, token, bot_token}`. `POST /v1/auth/login` takes `{username, password}` and returns `{user, token}`. `user` is `{id, username}`.

Changing the username while signed in keeps the session. The new name is the next login name. A name someone else already has returns 409 `username taken`.

Changing the password requires the current password. A wrong current password stays on 401 `wrong password`, leaves the password as it is, and does not sign the user out. Success sets the new password, deletes every session for that user, and does not rotate the bot token. The app returns to login. The next login is the username plus the new password.

Reset a forgotten password on the server:

```bash
cd /opt/proclan/server && uv run python -m proclan_server.set_password <username> <new-password>
```

The same ASCII case-insensitive lookup applies. The command stores an argon2id hash, deletes that user's sessions, and does not rotate the bot token. It exits non-zero when the username does not exist.

Ten failed logins lock the account for 15 minutes. A session lasts 30 days.

### MCP

Add a remote HTTPS MCP that is already running. The type is a custom remote server. It is not a catalog plugin, not a local command, and not stdio. Do not run this service on an agent's cloud computer.

- Name: `Proclan`. The server does not check the name.
- URL: `https://<domain>/mcp`
- Auth: **Static header only**, name `Authorization`, value `Bearer <the bot token>`. **Not OAuth.** After a token rotation, paste the new token again.

The bot token comes from the app's bot page or from the `bot_token` field in the register response. The session token is for the feed; the bot token is for MCP. The two are not interchangeable.

**This server does not support OAuth.** If a connector forces OAuth or "re-login", it will fail. If an existing connector is broken, remove it and recreate with the static header auth type.

`/mcp` is stateless Streamable HTTP. The result is one JSON body. There is no separate SSE endpoint.

If you cannot add the connection yourself, give the person those three items once, then stop. Do not invent a client screen or a mention syntax.

After it is connected, list the tools and confirm the only one is `submit_cards`. If the list fails, run the initialize check in [server/DEPLOY.md](server/DEPLOY.md) again. Do not change the server to make the list succeed.

### Writing cards

This section is for the agent that calls `submit_cards`. The server cannot wake you. Call the tool only in a conversation where this connection is selected.

Each time, list the tools, read the live `submit_cards` `inputSchema`, fill that shape, then call. Do not copy fields into a prompt, and do not reuse a shape you saw earlier. When the schema changes, the next list wins.

The server checks, stores the submitted public image URLs, and inserts. It does not rewrite the title, summary, body, source, or category. The body may be Markdown (headings, emphasis, lists, quotes, code, links, tables, images). The app renders that in the article.

`submit_cards` takes `cards`. Send 1 to 8. If any card's text or source link is invalid, the whole batch is rejected. The error names the current required fields. Fix the payload to the current schema and submit again.

A picture that is not a public http(s) URL is dropped. The card is still stored. Do not submit read state. The app records that on the device.
