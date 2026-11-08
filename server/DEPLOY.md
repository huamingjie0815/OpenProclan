English | [中文](DEPLOY.zh.md)

# Deploy Proclan

Deploy the Proclan server on a Linux machine the person owns, with an HTTPS reverse proxy in front. Do not install it on an agent's cloud computer. The server does not issue certificates and does not serve TLS itself.

There is no global ingest token. The feed and delete use the session from login. An image already stored under `/media` uses that session too. `/mcp` uses that person's own bot token, copied from the app. The two credentials are not interchangeable: the session token is for the feed and those stored images; the bot token is for MCP.

This is the only install procedure. [../README.md](../README.md) is the index for an AI agent. Do not copy these commands into another doc.

## Prepare

Minimum to start server installation:

- A Linux server the person owns, with root access and a public address.
- A domain that already resolves to that machine.
- Caddy or Nginx. For Nginx, also the certificate file paths.

Flutter / app packaging can be deferred. If the agent cannot reach the Flutter machine now, install the server first, report the https origin to the person, and leave `API_BASE` for them to set later.

Open 80 and 443 only. Leave `8787` on the loopback interface for the proxy.

## Install

Use `/opt/proclan`.

### Clone

```bash
git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan
```

If the clone fails (private repo, 404, network error), stop and ask how this machine should reach the repository. The usual fix for a private repo is SSH: `git clone git@github.com:huamingjie0815/OpenProclan.git /opt/proclan`. Do not invent another URL.

### Dependencies

```bash
cd /opt/proclan/server
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv sync --frozen --no-dev
cp .env.example .env
```

`uv sync` installs dependencies into `server/.venv` and prepares Python 3.12 from `server/.python-version`. Do not commit `.venv`.

If `uv sync --frozen --no-dev` stalls (slow or blocked PyPI access), one fallback is to export and install with pip:

```bash
uv export --frozen --no-dev > requirements.txt
.venv/bin/pip install -r requirements.txt
```

### Check port

The default listen port is `8787`. Check if it is already in use:

```bash
ss -tlnp | grep :8787
```

If another process holds `8787`, choose a different port. Set `PORT` in `server/.env` and point the reverse proxy at that same port.

### .env

`server/.env` holds the listen address. The process reads that file on startup. A variable that is already in the environment wins.

Required:

```bash
HOST=127.0.0.1
PORT=8787
```

With `HOST=127.0.0.1`, only a proxy on this machine can reach the server.

Optional variables:

| Variable | Role |
| --- | --- |
| `BOT_MESSAGE_TTL_HOURS` | Hours the server keeps each message. Default `24`. Values below 1 become 1 |
| `PROCLAN_DATA_DIR` | Database and image directory. Default `server/data`. Use an absolute path |
| `FORWARDED_ALLOW_IPS` | Proxy addresses allowed to rewrite the scheme. Default `127.0.0.1,::1` |

**Troubleshooting image URLs**: Images already stored on disk are served from `/media`. If those URLs look like `http://127.0.0.1:8787/media/...` instead of `https://<domain>/media/...`, the proxy is not setting `Host` and `X-Forwarded-Proto` correctly, or its address is not in `FORWARDED_ALLOW_IPS`. Fix the proxy headers or add its address to `FORWARDED_ALLOW_IPS`. A new card's images are the submitted URLs and do not use these headers.

### Data directory

Data lives in `PROCLAN_DATA_DIR`:

- `proclan.sqlite3` holds the cards
- `media/` holds image files that older cards still reference

New cards store the submitted URL and do not add files. The directory shrinks as those cards expire or are deleted. Do not delete a file that a card still uses, or that picture disappears.

## Accounts

The app registers and signs in with a username and a password. Reset a forgotten password on this server:

```bash
cd /opt/proclan/server
uv run python -m proclan_server.set_password <username> <new-password>
```

ASCII case is ignored in the lookup. The command stores an argon2id hash, deletes that user's sessions, and does not rotate the bot token. It exits non-zero when the username does not exist. The account rules are in [../AGENTS.md](../AGENTS.md).

## HTTPS

When the proxy and this server are on the same machine, leave `FORWARDED_ALLOW_IPS` at its default. The proxy must put the original host in `Host` and set `X-Forwarded-Proto` to `https`. The server builds `/media` URLs for image files already on disk from those two values. If the proxy is not trusted, or omits either value, those URLs become `http://127.0.0.1:8787/media/...` and the app on a phone cannot open them. A new card's images are the submitted URLs and do not use these headers.

### Caddy

```caddy
proclan.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

Replace `proclan.example.com` with the person's domain. Caddy obtains the certificate and forwards to `8787` on this machine.

### Nginx

Replace the certificate paths with the person's files.

```nginx
server {
    listen 443 ssl;
    server_name proclan.example.com;

    ssl_certificate     /etc/ssl/proclan.example.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/proclan.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

When the proxy is not on `127.0.0.1`, set `FORWARDED_ALLOW_IPS` to that proxy's address. Do not set it to `*`. Any client could then rewrite the scheme.

### Nginx with static landing page

Some setups serve a static ICP or landing page at `/` while proxying the API. Use `location = /` for an exact match:

```nginx
server {
    listen 443 ssl;
    server_name proclan.example.com;

    ssl_certificate     /etc/ssl/proclan.example.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/proclan.example.com/privkey.pem;

    location = / {
        root /var/www/landing;
        try_files /index.html =404;
    }

    location = /index.html {
        root /var/www/landing;
    }

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 180s;
    }
}
```

The exact-match `location = /` serves the landing page. All other paths go to the app.

## One process

Run one process. Do not set `WEB_CONCURRENCY`, and do not add workers. The write lock is inside the process.

The unit below assumes the clone path above. `HOST` and `PORT` are already in `.env`. Do not put a token in the unit.

```ini
[Unit]
Description=Proclan inbox
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/proclan/server
ExecStart=/opt/proclan/server/.venv/bin/python -m proclan_server
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Save it as `/etc/systemd/system/proclan.service`.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now proclan
sudo systemctl status proclan
```

On the server, `/openapi.json` is 200. `/v1/categories` without a session is 401.

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8787/openapi.json
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8787/v1/categories
```

## Check from outside

Replace the domain.

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://proclan.example.com/openapi.json
curl -sS -o /dev/null -w '%{http_code}\n' https://proclan.example.com/v1/categories
```

If the public curl fails but loopback `/openapi.json` returns 200 and the proxy config is correct, report that to the person. DNS propagation, ICP filing, or upstream firewall may still block the public edge. Do not loop forever waiting for external access.

### MCP check

The MCP URL is `https://proclan.example.com/mcp`. It is stateless Streamable HTTP. The result is one JSON body. There is no separate SSE endpoint.

The request needs that person's bot token. Copy the token from the app's bot page, or from the `bot_token` field in the `POST /v1/auth/register` response when registering. If you do not have a bot token, stop. Do not generate one.

```bash
curl -sS https://proclan.example.com/mcp \
  -H "Authorization: Bearer <the person's bot token>" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"deploy-check","version":"0"}}}'
```

A returned `protocolVersion` is enough.

When writing cards, list the tools and read the live `submit_cards` inputSchema. Do not copy a field table into a prompt. The server does not rewrite the title, summary, body, source, or category.

## App

On the computer that runs the app, set `API_BASE` to this https origin and follow [../app/README.md](../app/README.md). Do not compile the app on the server. Do not write the origin into source.

The feed and delete send the login session, not the bot token. An image already stored under `/media` sends that session too. A new card's images are the submitted http(s) URLs, and those requests do not send the session.

## MCP connection

Add a remote HTTPS MCP:

- **Name**: `Proclan`
- **URL**: `https://<domain>/mcp`
- **Auth**: Static header only. Name `Authorization`, value `Bearer <bot token>`. Not OAuth.

The bot token comes from the app's bot page or from the `bot_token` field in the register response. The session token is for the feed; the bot token is for MCP. The two are not interchangeable.

**This server does not support OAuth.** If a connector forces OAuth or "re-login", it will fail. If an existing connector is broken, remove it and recreate with the static header auth type.

After connection, call `tools/list`. The only tool must be `submit_cards`. If it fails, run the MCP check above again. Always read the live `inputSchema` before calling `submit_cards`; do not copy field tables into prompts.

## Update and backup

```bash
cd /opt/proclan
git pull
cd server
uv sync --frozen --no-dev
sudo systemctl restart proclan
```

Stop the service before a backup, copy the whole data directory, then start it again:

```bash
sudo systemctl stop proclan
cp -a /opt/proclan/server/data /var/backups/proclan-data
sudo systemctl start proclan
```

If `PROCLAN_DATA_DIR` was changed, copy that directory. Keep `server/.env` aside. Do not put it in a backup archive that will be shared.

---

## Appendix: same-host replace

This section is for replacing an existing install on the same host, not for first-time installs.

1. Stop the service: `sudo systemctl stop proclan`
2. Move the old tree aside: `sudo mv /opt/proclan /opt/proclan.old`
3. Clone fresh: `git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan`
4. Copy `.env` back: `cp /opt/proclan.old/server/.env /opt/proclan/server/.env`
5. Restore data if keeping cards: `cp -a /opt/proclan.old/server/data /opt/proclan/server/data`
6. Reinstall dependencies: `cd /opt/proclan/server && uv sync --frozen --no-dev`
7. Restart: `sudo systemctl start proclan`

If starting with an empty database, all users must register again. The old accounts and bot tokens are gone. MCP connections with old tokens will fail; update them with new tokens after register.
