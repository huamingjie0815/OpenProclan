English | [中文](DEPLOY.zh.md)

# Deploy the Proclan server (a runbook for an agent)

Install the Proclan server on a Linux machine the developer owns, with an HTTPS reverse proxy in front. This is the only install and upgrade procedure; [../README.md](../README.md) is only an index. Do not copy these commands into other docs, and do not install this service on an agent's cloud computer.

Three sentences save most of the rework:

1. Decide first whether this machine is a **first install** or an **existing install**. Taking the wrong branch overwrites someone's data.
2. Every phase states the evidence that passes. If the evidence does not match, stop and read the failure note instead of stacking the next step on top.
3. There is exactly one dataset: the database plus `media/`. Ask a person before any action that deletes data.

There is no global ingest token. The feed and deletes use the login session. Images already stored under `/media` also use it. `/mcp` uses that person's bot token, copied from the app. The two are not interchangeable.

## 0. Decide what you are doing

| Situation | How to tell | Go to |
| --- | --- | --- |
| Never installed here | `test -d /opt/proclan` is false and `systemctl cat proclan` says not found | Section 2, first install |
| Installed, update the code | `/opt/proclan/.git` exists and `systemctl is-active proclan` is active | Section 3, upgrade |
| Installed but not running | As above, but `systemctl status` is not active | Section 5 first, then talk about upgrading |
| Rebuilding on a new machine | New machine, old one still alive | Section 2, then move data with Section 4 |
| Only a config change | One line in `.env` | Section 2.4, restart, then Section 2.7 |

Record the scene before touching anything:

```bash
uname -a
id -u
sudo -n true && echo "sudo-ok"
df -h /opt
```

If `id -u` is not 0 and `sudo -n` fails, settle permissions first. Never ask for a root password in chat and never put one on a command line.

## 1. What a person must provide first

If one item is missing, stop. Do not guess, and do not substitute a tunnel or a private address.

| Need | Why | If missing |
| --- | --- | --- |
| A Linux server the developer owns, with root or sudo | `/opt/proclan` and systemd need it | Stop and ask |
| A domain that already resolves here | The app and MCP both need an HTTPS origin | Stop and ask; do not use a bare IP |
| Caddy or Nginx | The service listens locally and issues no certificate | Stop and ask which; Nginx also needs certificate paths |
| A bot token | Verifying `/mcp` | The person copies it from the app's bot page; do not generate one |

Can defer: the machine that runs the Flutter app. The app is not installed on the server. If that machine is unreachable now, hand over the https origin and leave `API_BASE` for later.

## 2. First install

The directory is always `/opt/proclan`. Each phase gives a command and the evidence that passes. If the evidence does not match, read the failure note.

### 2.1 Clone

```bash
git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan
```

- Passes: `/opt/proclan/.git` exists and `git -C /opt/proclan log -1 --oneline` prints a commit.
- Fails: on a private repo, 404, or a network error, stop and ask how this machine should reach the repository. A private repo usually means SSH: `git@github.com:huamingjie0815/OpenProclan.git`. Do not invent a URL.

### 2.2 Dependencies

```bash
cd /opt/proclan/server
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv sync --frozen --no-dev
cp .env.example .env
```

- Passes: `/opt/proclan/server/.venv/bin/python -V` prints Python 3.12.x.
- `uv sync` installs into `server/.venv` and prepares Python 3.12 from `server/.python-version`. Do not commit `.venv`.
- Fails: if `uv sync` stalls because PyPI is slow or blocked, export and install:

```bash
uv export --frozen --no-dev > requirements.txt
.venv/bin/pip install -r requirements.txt
```

### 2.3 Check the port

```bash
ss -tlnp | grep :8787
```

- Passes: no output, so the port is free.
- Occupied: choose another port, set `PORT` in `server/.env`, and point the proxy at the same port. Do not kill a process you do not recognize.

### 2.4 Write .env

`server/.env` holds the listen address and the optional settings. The process reads it at start, and a variable already in the environment wins.

```bash
HOST=127.0.0.1
PORT=8787
```

With `HOST=127.0.0.1`, only a proxy on this machine can connect. That is the default and the requirement.

| Variable | Effect |
| --- | --- |
| `BOT_MESSAGE_TTL_HOURS` | How many hours a card stays on the wall. Default `24`, below 1 becomes 1. This is product behavior, not a cleanup job |
| `PROCLAN_DATA_DIR` | Database and image directory, default `server/data`. Use an absolute path |
| `FORWARDED_ALLOW_IPS` | Proxy addresses allowed to rewrite the scheme, default `127.0.0.1,::1` |
| `PROCLAN_WORKERS` | Worker count, default `2`. Do not set `WEB_CONCURRENCY` |
| `PROCLAN_BOT_BURST`, `PROCLAN_BOT_REFILL_SECONDS` | Per-bot write quota, default `48` cards then 1 every `2` seconds |

`.env` changes need a restart. Never commit it and never put it in a backup bundle.

### 2.5 Reverse proxy and HTTPS

The proxy must pass the original host in `Host`, set `X-Forwarded-Proto` to `https`, and forward `X-Forwarded-For`. Open only 80 and 443. Leave `8787` on the machine.

Caddy:

```caddy
proclan.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

Nginx (swap in the real certificate paths):

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

When the proxy is not on `127.0.0.1`, set `FORWARDED_ALLOW_IPS` to that address. Never `*`.

Some installs keep a static filing or landing page at `/` and proxy everything else:

```nginx
    location = / {
        root /var/www/landing;
        try_files /index.html =404;
    }

    location = /index.html {
        root /var/www/landing;
    }
```

`location = /` matches only the home page; other paths use the `location /` above.

- Passes: `curl -sS -o /dev/null -w '%{http_code}\n' https://<domain>/openapi.json` prints `200` once the service runs.
- Fails: certificate not issued, domain not resolving, or the security group blocks 443. See Section 5.

### 2.6 Keep it running

The worker count comes from the environment, not the unit. The unit carries no token.

```ini
[Unit]
Description=Proclan inbox service
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

Save it as `/etc/systemd/system/proclan.service`, then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now proclan
sudo systemctl status proclan --no-pager
```

- Passes: `active (running)`, and `journalctl -u proclan -n 50` shows `Uvicorn running on http://127.0.0.1:<PORT>` with no traceback.
- The database and its tables are created on first start. There is no separate migration command.

### 2.7 Verify

Three checks on the machine:

```bash
curl -sS -o /dev/null -w 'openapi %{http_code}\n' http://127.0.0.1:8787/openapi.json
curl -sS -o /dev/null -w 'categories %{http_code}\n' http://127.0.0.1:8787/v1/categories
curl -sS -o /dev/null -w 'feed %{http_code}\n' http://127.0.0.1:8787/v1/feed
```

Expect `openapi 200`, `categories 401`, `feed 401`. A 401 means the route exists and wants a login, which is success; a 404 here means the wrong build or the wrong port.

Two checks from outside, with the real domain:

```bash
curl -sS -o /dev/null -w 'public-openapi %{http_code}\n' https://<domain>/openapi.json
curl -sS -o /dev/null -w 'public-categories %{http_code}\n' https://<domain>/v1/categories
```

Expect `200` and `401`.

One MCP check. It needs that person's bot token, copied from the app's bot page or taken from the `bot_token` field of the register response:

```bash
curl -sS https://<domain>/mcp \
  -H "Authorization: Bearer <bot token>" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"deploy-check","version":"0"}}}'
```

- Passes: the body contains `protocolVersion`.
- 401: the token is wrong, or a session token was used instead of the bot token. Do not change the server to accommodate it.
- After it connects, list the tools. The only tool must be `submit_cards`.

If the public curl fails while loopback returns 200 and the proxy config is right, report that. DNS, ICP filing, the security group, or an upstream firewall may still block the edge. Do not loop forever.

## The app (on another machine)

After the server is up, the app is not built on this machine. Hand over the https origin and have the machine with Flutter set `API_BASE` to it; everything else is in [../app/README.md](../app/README.md). Do not install Flutter on the server to produce a build.

The feed and deletes use the login session, not the bot token; images already stored under `/media` use it too. New cards point at submitted http(s) URLs, and those requests carry no session.

## 3. Upgrade an existing install

### 3.1 Record the scene

```bash
cd /opt/proclan
git status --porcelain
git log -1 --oneline
sudo systemctl is-active proclan
```

- The worktree must be clean. If it is not, find out who changed it; never overwrite.
- Keep the current commit. A rollback needs it.

Record the data counts. Copy through SQLite rather than `cp` a database that is being written:

```bash
/opt/proclan/server/.venv/bin/python - <<'EOF'
import sqlite3
src = sqlite3.connect('/opt/proclan/server/data/proclan.sqlite3')
dst = sqlite3.connect('/tmp/proclan-check.sqlite3')
src.backup(dst)
q = lambda s: dst.execute(s).fetchone()[0]
print('cards', q('select count(*) from cards'))
print('users', q('select count(*) from users'))
print('bots', q("select count(distinct created_bot) from cards"))
print('tables', sorted(r[0] for r in dst.execute("select name from sqlite_master where type='table'")))
print('card_cols', [r[1] for r in dst.execute('pragma table_info(cards)')])
EOF
```

Swap the path when `PROCLAN_DATA_DIR` is set. The copy lives in `/tmp`: it holds password hashes and bot tokens, so delete it after use.

### 3.2 Fast-forward main

```bash
cd /opt/proclan
git fetch origin main
git log --oneline HEAD..origin/main
git merge --ff-only origin/main
git log -1 --oneline
git status --porcelain
```

- Fast-forward only. Never rebase, reset, or force-push a production checkout.
- Passes: `HEAD` equals `origin/main` and `git status` is empty.
- Fails: "not possible to fast-forward" means local commits exist. Stop and ask; do not reset.

### 3.3 Dependencies

Reinstall only if these two files changed:

```bash
git diff --name-only <commit before> HEAD -- server/pyproject.toml server/uv.lock
```

- Output means run `cd /opt/proclan/server && uv sync --frozen --no-dev`.
- No output means skip it. Do not reinstall anyway.
- Never rewrite `server/.env` during an upgrade. If config must change, raise it separately and back it up first.

### 3.4 Rebuild and restart

The new version adds tables and columns on start: `store.init` runs `CREATE TABLE IF NOT EXISTS` plus conditional `ALTER TABLE` every time. Do not hand-run `ALTER` on the database and do not look for a migration script. The repository has none and needs none.

```bash
sudo systemctl restart proclan
sleep 3
sudo systemctl status proclan --no-pager
sudo journalctl -u proclan -n 100 --no-pager
```

- Passes: `active (running)`, `Application startup complete` in the log, no traceback. Downtime is usually 1 to 5 seconds.
- Fails: use Section 5, restore service first, then decide about a rollback.

### 3.5 Verify after the upgrade

```bash
ss -tlnp | grep :8787
curl -sS -o /dev/null -w 'openapi %{http_code}\n' http://127.0.0.1:8787/openapi.json
curl -sS -o /dev/null -w 'feed %{http_code}\n' http://127.0.0.1:8787/v1/feed
```

Run the count snippet from 3.1 again into a fresh temp file and compare each line:

- Cards, users, and bot names match, so nothing was lost.
- New tables and new `cards` columns exist.
- A new route without a session returns 401, not 404.

For extra proof, run the schema logic a second time on the **copy** and confirm it is idempotent (`Store(path).init()` twice without an error). Never experiment on the production database.

### 3.6 Roll back

Code rollback:

```bash
cd /opt/proclan
git switch --detach <commit before>
sudo systemctl restart proclan
```

A new version only adds tables and columns, and old code ignores them, so a rollback needs no database work. Re-run the 3.5 checks after it. A rollback is a repair, not a request for approval, but the report must say why you rolled back and which commit is live.

After a rollback, HEAD is detached. To return to the main line:

```bash
cd /opt/proclan
git switch main
git merge --ff-only origin/main
sudo systemctl restart proclan
```

## 4. Backup and restore

SQLite's own backup API works without stopping the service:

```bash
sudo mkdir -p /var/backups/proclan
/opt/proclan/server/.venv/bin/python - <<'EOF'
import sqlite3
src = sqlite3.connect('/opt/proclan/server/data/proclan.sqlite3')
dst = sqlite3.connect('/var/backups/proclan/backup.sqlite3')
src.backup(dst)
EOF
```

Or stop and copy the directory:

```bash
sudo systemctl stop proclan
cp -a /opt/proclan/server/data /var/backups/proclan-data
sudo systemctl start proclan
```

- With `PROCLAN_DATA_DIR` changed, copy that directory.
- A backup holds password hashes and bot tokens. Ask before putting one anywhere it can leave the machine.
- Keep `server/.env` separately and out of the bundle.
- Restore: stop, replace the data directory with the backup, start, then run the 2.7 checks. This is the reverse of deleting data, so confirm which backup first.

## 5. Failures

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Loopback `:8787` refuses the connection | Service down, or `PORT` is not 8787 | `systemctl status`, `journalctl`, `ss -tlnp`; match the port to the proxy |
| Public 502 or 504 | Proxy points at the wrong port, or the service is down | Prove loopback is 200, then check the proxy upstream |
| Public times out, loopback 200 | DNS, filing, security group, or upstream firewall | Hand the loopback evidence over; do not change the service |
| `/openapi.json` is 404 | Request hits another site, or the proxy rewrites the path | Check `server_name` and `location /` |
| `/media/...` becomes `http://127.0.0.1:8787/...` | Proxy drops `Host`/`X-Forwarded-Proto`, or its address is not trusted | Fix the headers or add the proxy address; never `*` |
| `/mcp` is 401 | Wrong or rotated token, or a session token was used | Have the person copy the bot token again; do not generate one |
| `/mcp` is 405 | Probing with GET | Send `initialize` with POST |
| Images or video do not show | The URL is not http(s), or names a private or loopback host, so it was dropped | Resubmit a public URL; domains are not resolved on the server, by design |
| Cards suddenly disappear | Older than `BOT_MESSAGE_TTL_HOURS` (24 hours by default) | Product behavior; raise the TTL and restart |
| 429 `retry later` on a write | Bot or bot-name quota | Wait for the quota; never edit the counters in the database |
| 413 `payload too large` | Body over 1 MiB | Split the submission |
| MCP still works after a password change | A password change does not rotate the bot token | To cut it off, `POST /v1/me/bot-token` and paste the new token into the connection |
| `uv sync` stalls | PyPI slow or blocked | Use the export install in 2.2 |
| Repeated `database is locked` | A second process writes the same file | Check `ps`/`ss` for a duplicate server, stop the extra one, restart |
| Service will not start after an upgrade | Dependencies skipped, or a broken `.env` | Read the traceback; install per 3.3, or return to the previous commit |

## 6. Actions that need a person's approval

Do not perform these even when you can, without asking first:

- Deleting or overwriting the data directory, the database, or files under `media/`
- Replacing current data with a backup
- Rewriting `server/.env`
- Changing the domain, the certificate source, or the proxy's site config
- Opening a new public port, or editing the security group or firewall
- Editing `sudoers`, the login method, or the SSH configuration
- Hand-running `ALTER`/`DROP` on the production database, or any self-written migration
- Moving the service to another machine, or reinstalling the OS

## 7. How to report

Six lines at most. Write "not done" for what you skipped, and do not recap the commands:

1. Site: `https://<domain>`, and whether the app already points at it.
2. Version: commit before → commit now; whether the worktree is clean.
3. Data: cards / users / bot names, before → after.
4. Service: active or not, listen address, seconds of downtime, anything odd in the log.
5. Checks: loopback and public status codes, whether `/mcp` returned `protocolVersion`.
6. Open items: whether the client needs a new APK (`./scripts/apk production` on a machine with Flutter).

Keep tokens out of the report. If the person must paste one once, tell them not to forward it.

---

## Appendix: replace in place

This replaces an existing install on the same machine; it is not a first install. It touches data and config, so confirm before starting.

1. Stop the service: `sudo systemctl stop proclan`
2. Move the old directory aside: `sudo mv /opt/proclan /opt/proclan.old`
3. Clone again: `git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan`
4. Put `.env` back: `cp /opt/proclan.old/server/.env /opt/proclan/server/.env`
5. To keep cards, restore the data directory: `cp -a /opt/proclan.old/server/data /opt/proclan/server/data`
6. Reinstall dependencies: `cd /opt/proclan/server && uv sync --frozen --no-dev`
7. Start and verify: `sudo systemctl start proclan`, then run Section 2.7

Starting on an empty database makes every person register again: old accounts and bot tokens are gone, and MCP connections using the old token fail. Prefer the upgrade in Section 3.
