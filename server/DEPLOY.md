English | [中文](DEPLOY.zh.md)

# Deploy Proclan

Deploy the Proclan server on a Linux machine the person owns, with an HTTPS reverse proxy in front. Do not install it on an agent's cloud computer. The server does not issue certificates and does not serve TLS itself.

There is no global ingest token. The feed, delete, and images use the session from login. `/mcp` uses that person's own bot token, copied from the app. The two credentials are not interchangeable.

This is the only install procedure. [../README.md](../README.md) is the index for an AI agent. Do not copy these commands into another doc.

## Prepare

- A Linux server the person owns, with a public address and a domain.
- Python 3.12 or newer. `uv` installs the interpreter named in `server/.python-version`.
- A reverse proxy, such as Caddy or Nginx, listening on 443.
- Outbound access to the public internet. The server downloads card images itself. The client does not upload them.

Open 80 and 443 only. Leave `8787` on the loopback interface for the proxy.

## Install

Use `/opt/proclan`.

```bash
git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan
cd /opt/proclan/server
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv sync --frozen --no-dev
cp .env.example .env
```

`uv sync` installs dependencies into `server/.venv` and prepares Python 3.12 from `server/.python-version`. Do not commit `.venv`.

`server/.env` only needs the listen address. The process reads that file on startup. A variable that is already in the environment wins. The file does not override it.

```bash
HOST=127.0.0.1
PORT=8787
```

With `HOST=127.0.0.1`, only a proxy on this machine can reach the server.

| Variable | Role |
| --- | --- |
| `HOST` | Listen address. Use `127.0.0.1` when the proxy is on this machine |
| `PORT` | Listen port. Default `8787` |
| `BOT_MESSAGE_TTL_HOURS` | Optional. Hours the server keeps each message. Default `24`. Values below 1 become 1 |
| `PROCLAN_DATA_DIR` | Optional. Database and image directory. Default `server/data`. Use an absolute path |
| `FORWARDED_ALLOW_IPS` | Optional. Proxy addresses allowed to rewrite the scheme. Default `127.0.0.1,::1` |

Data lives in `PROCLAN_DATA_DIR`:

- `proclan.sqlite3` holds the cards
- `media/` holds downloaded images

The directory grows with the cards. Do not delete a `media/` directory that is in use, or the pictures in articles disappear.

## Accounts

The app registers and signs in with a username and a password. Reset a forgotten password on this server:

```bash
cd /opt/proclan/server
uv run python -m proclan_server.set_password <username> <new-password>
```

ASCII case is ignored in the lookup. The command stores an argon2id hash, deletes that user's sessions, and does not rotate the bot token. It exits non-zero when the username does not exist. The account rules are in [../AGENTS.md](../AGENTS.md).

## HTTPS

When the proxy and this server are on the same machine, leave `FORWARDED_ALLOW_IPS` at its default. The proxy must put the original host in `Host` and set `X-Forwarded-Proto` to `https`. Image URLs are built from those two values. If the proxy is not trusted, or omits either value, image URLs become `http://127.0.0.1:8787/media/...` and the app on a phone cannot open them.

One submit carries at most 8 cards, and each card at most 6 images. Each image download is capped at 15 seconds. Set the proxy read timeout to at least 180 seconds. Raise it when many images come from a slow origin.

### Caddy

```caddy
proclan.example.com {
    reverse_proxy 127.0.0.1:8787 {
        transport http {
            response_header_timeout 180s
            read_timeout 180s
        }
    }
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
        proxy_read_timeout 180s;
    }
}
```

When the proxy is not on `127.0.0.1`, set `FORWARDED_ALLOW_IPS` to that proxy's address. Do not set it to `*`. Any client could then rewrite the scheme.

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

The MCP URL is `https://proclan.example.com/mcp`. It is stateless Streamable HTTP. The result is one JSON body. There is no separate SSE endpoint. The request needs that person's bot token and must accept JSON. Copy the token from the app. If you do not have it, stop. Do not generate one.

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

The feed, delete, and article images send the login session, not the bot token. Image URLs must look like `https://proclan.example.com/media/...`.

Add a remote HTTPS MCP named `Proclan` at `https://proclan.example.com/mcp`, with the header `Authorization: Bearer <the person's bot token>`.

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
