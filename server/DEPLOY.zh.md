[English](DEPLOY.md) | 中文

# 部署 Proclan 服务（给 agent 的执行手册）

把 Proclan 服务部署到开发者自己的 Linux 机器上，前面用 HTTPS 反向代理。这是唯一的安装与升级步骤，[../README.zh.md](../README.zh.md) 只是目录。不要把命令抄进别的文档，也不要把这个服务装进智能体的云端电脑。

先读这三句，能省掉一半返工：

1. 先判断这台机器是**首次安装**还是**已有安装**。走错分支会覆盖别人的数据。
2. 每一步都有「通过的证据」。证据不对就停下看对应的失败处理，不要继续往下叠。
3. 数据只有一份：数据库加 `media/`。任何删数据的动作都要先问人。

没有全局接入 token。信息流和删除要带登录后的会话。已经落在 `/media` 的图片也带这个会话。`/mcp` 要带这个人自己的 bot token，从应用里复制。两者不能互换。

## 0. 先判断要做什么

| 现场 | 判断方式 | 去哪一节 |
| --- | --- | --- |
| 这台机器没装过 | `test -d /opt/proclan` 为假，`systemctl cat proclan` 报 not found | 第 2 节，首次安装 |
| 已经装过，要更新代码 | `/opt/proclan/.git` 存在，`systemctl is-active proclan` 是 active | 第 3 节，升级 |
| 已经装过，但服务起不来 | 同上，但 `systemctl status` 不是 active | 第 5 节故障表，先修再谈升级 |
| 换机器重建 | 机器是新的，旧机器还在 | 第 2 节安装 + 第 4 节把数据搬过来 |
| 只想改配置 | `.env` 里的一行 | 第 2.4 节改完重启，然后跑第 2.6 节验收 |

先记录现场，再动手：

```bash
uname -a
id -u
sudo -n true && echo "sudo-ok"
df -h /opt
```

`id -u` 不是 0，且 `sudo -n` 失败时，先解决权限再继续。不要在对话里要 root 口令，也不要把它写进命令行。

## 1. 开工前，人必须给的东西

缺一项就停，不要猜，不要用隧道或内网地址顶上。

| 需要 | 为什么 | 缺了怎么办 |
| --- | --- | --- |
| 一台开发者自己的 Linux 服务器，有 root 或可 sudo 的账号 | 装 `/opt/proclan`、写 systemd 都要它 | 停下来问 |
| 一个已经解析到这台机器的域名 | 应用和 MCP 都要求 HTTPS 源 | 停下来问；不要拿 IP 代替 |
| Caddy 或 Nginx | 服务本身只监听本机，不发证书 | 停下来问选择哪个；Nginx 还要证书路径 |
| bot token | 验收 `/mcp` 用 | 让对方在应用的 Bot 页复制；不要自己生成 |

可以稍后：跑 Flutter 应用的电脑。应用不装在服务器上。现在连不上那台机器，就把 https 源交出去，`API_BASE` 留给对方填。

## 2. 首次安装

目录固定 `/opt/proclan`。下面每一步都给「命令」和「通过的证据」。证据不对就看「失败怎么办」。

### 2.1 拉代码

```bash
git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan
```

- 通过：`/opt/proclan/.git` 存在，`git -C /opt/proclan log -1 --oneline` 有输出。
- 失败：私有仓库、404 或网络不通就停，问这台机器怎样访问仓库。私有仓库通常用 SSH：`git@github.com:huamingjie0815/OpenProclan.git`。不要编造地址。

### 2.2 装依赖

```bash
cd /opt/proclan/server
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv sync --frozen --no-dev
cp .env.example .env
```

- 通过：`/opt/proclan/server/.venv/bin/python -V` 输出 Python 3.12.x。
- `uv sync` 把依赖装进 `server/.venv`，并按 `server/.python-version` 准备 Python 3.12。`.venv` 不要提交。
- 失败：`uv sync` 卡住（PyPI 慢或被阻断）时改走导出安装：

```bash
uv export --frozen --no-dev > requirements.txt
.venv/bin/pip install -r requirements.txt
```

### 2.3 确认端口

```bash
ss -tlnp | grep :8787
```

- 通过：没有输出（说明空闲）。
- 有进程占用：换成别的端口，在 `server/.env` 写 `PORT`，反向代理指向同一个端口。不要杀掉不认识的进程。

### 2.4 写 .env

`server/.env` 只放监听地址和可选项，进程启动时读取，环境里已有的同名变量优先。

```bash
HOST=127.0.0.1
PORT=8787
```

`HOST=127.0.0.1` 时只有本机的反向代理能连进来，这是默认也是要求。

| 变量 | 作用 |
| --- | --- |
| `BOT_MESSAGE_TTL_HOURS` | 卡片在墙上的时长（小时），默认 `24`，小于 1 按 1。这是产品行为，不是清理任务 |
| `PROCLAN_DATA_DIR` | 数据库和图片目录，默认 `server/data`。用绝对路径 |
| `FORWARDED_ALLOW_IPS` | 允许改写协议的代理来源，默认 `127.0.0.1,::1` |
| `PROCLAN_WORKERS` | worker 数，默认 `2`。不要设置 `WEB_CONCURRENCY` |
| `PROCLAN_BOT_BURST`、`PROCLAN_BOT_REFILL_SECONDS` | 每个 bot 的写卡配额，默认 `48` 张、`2` 秒 1 张 |

改完 `.env` 要重启服务才生效。`.env` 不进仓库，也不进备份包。

### 2.5 反向代理和 HTTPS

代理必须把原始域名放进 `Host`，把 `X-Forwarded-Proto` 设为 `https`，并把 `X-Forwarded-For` 传下去。只开放 80 和 443，`8787` 留在本机。

Caddy：

```caddy
proclan.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

Nginx（证书换成自己的路径）：

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

代理不在 `127.0.0.1` 上时，把 `FORWARDED_ALLOW_IPS` 设成那台代理的地址。不要写 `*`。

有些部署在 `/` 放静态的备案或落地页，其他路径代理到应用：

```nginx
    location = / {
        root /var/www/landing;
        try_files /index.html =404;
    }

    location = /index.html {
        root /var/www/landing;
    }
```

`location = /` 精确匹配首页，其他路径走上面的 `location /`。

- 通过：`curl -sS -o /dev/null -w '%{http_code}\n' https://<域名>/openapi.json` 是 `200`（服务起来以后）。
- 失败：证书没签下来、域名没解析、或安全组没放 443，见第 5 节。

### 2.6 常驻运行

worker 数来自环境变量，不写在单元里。单元里不写 token。

```ini
[Unit]
Description=Proclan 收件服务
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

保存为 `/etc/systemd/system/proclan.service`，然后：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now proclan
sudo systemctl status proclan --no-pager
```

- 通过：`active (running)`，`journalctl -u proclan -n 50` 里有 `Uvicorn running on http://127.0.0.1:<PORT>`，没有 traceback。
- 数据库和表在第一次启动时自动建好，不需要单独的迁移命令。

### 2.7 验收

本机三条：

```bash
curl -sS -o /dev/null -w 'openapi %{http_code}\n' http://127.0.0.1:8787/openapi.json
curl -sS -o /dev/null -w 'categories %{http_code}\n' http://127.0.0.1:8787/v1/categories
curl -sS -o /dev/null -w 'feed %{http_code}\n' http://127.0.0.1:8787/v1/feed
```

期望 `openapi 200`、`categories 401`、`feed 401`。401 是「路由在，且要登录」，不是错误；这里看到 404 才说明装错了版本或端口。

外网两条，域名换成实际的：

```bash
curl -sS -o /dev/null -w 'public-openapi %{http_code}\n' https://<域名>/openapi.json
curl -sS -o /dev/null -w 'public-categories %{http_code}\n' https://<域名>/v1/categories
```

期望 `200` 和 `401`。

MCP 一条。需要这个人的 bot token，从应用 Bot 页复制，或注册响应里的 `bot_token`：

```bash
curl -sS https://<域名>/mcp \
  -H "Authorization: Bearer <bot token>" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"deploy-check","version":"0"}}}'
```

- 通过：返回里能看到 `protocolVersion`。
- 401：token 不对，或把会话 token 当成了 bot token。不要改服务器去迁就它。
- 连上后列出工具，唯一的工具必须是 `submit_cards`。

如果外网 curl 失败，但本机 200 且代理配置正确，把这个情况告诉对方：DNS 生效、ICP 备案、安全组或上游防火墙可能还在挡公网入口。不要无限等待。

## 应用（在另一台机器上）

服务装好以后，应用不在这台服务器上编译。把 https 源交给对方，让装着 Flutter 的那台机器把 `API_BASE` 写成这个源，其余按 [../app/README.zh.md](../app/README.zh.md) 做。不要在服务器上装 Flutter，也不要为了打包去装。

信息流和删除带的是登录会话，不是 bot token；已经落在 `/media` 的图片也带会话。新卡的图是提交的 http(s) 地址，这些请求不带会话。

## 3. 升级（已有安装）

### 3.1 记录现场

```bash
cd /opt/proclan
git status --porcelain
git log -1 --oneline
sudo systemctl is-active proclan
```

- 工作区必须是空的。有改动先查明是谁改的，不要覆盖。
- 记下当前 commit，回滚要用。

再记录数据计数（服务在跑也能安全复制，不要直接 `cp` 正在写的库）：

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

用了 `PROCLAN_DATA_DIR` 就把路径换掉。这份副本留在 `/tmp`，用完删掉：里面有密码哈希和 bot token。

### 3.2 快进 main

```bash
cd /opt/proclan
git fetch origin main
git log --oneline HEAD..origin/main
git merge --ff-only origin/main
git log -1 --oneline
git status --porcelain
```

- 只用快进。不要 rebase、reset 或强推生产检出。
- 通过：`HEAD` 等于 `origin/main`，`git status` 空。
- 失败：提示 not possible to fast-forward 时，说明本地有提交。停下来问，不要 reset。

### 3.3 依赖

只有这两个文件变了才重装：

```bash
git diff --name-only <升级前commit> HEAD -- server/pyproject.toml server/uv.lock
```

- 有输出：`cd /opt/proclan/server && uv sync --frozen --no-dev`。
- 没有输出：跳过，不要重装。
- 永远不要在这次升级里改写 `server/.env`。配置要变，单独提出，改前备份。

### 3.4 重建和重启

表和新字段由新版启动时自己补：`store.init` 每次执行 `CREATE TABLE IF NOT EXISTS` 和条件 `ALTER TABLE`。不要在库上先手工跑 `ALTER`，也不要找迁移脚本，仓库里没有也不需要。

```bash
sudo systemctl restart proclan
sleep 3
sudo systemctl status proclan --no-pager
sudo journalctl -u proclan -n 100 --no-pager
```

- 通过：`active (running)`，日志里 `Application startup complete`，没有 traceback，断线通常 1 到 5 秒。
- 失败：看第 5 节，先恢复服务，再决定是否回滚。

### 3.5 升级后核对

```bash
ss -tlnp | grep :8787
curl -sS -o /dev/null -w 'openapi %{http_code}\n' http://127.0.0.1:8787/openapi.json
curl -sS -o /dev/null -w 'feed %{http_code}\n' http://127.0.0.1:8787/v1/feed
```

再跑一次 3.1 的计数脚本，换一个新的临时文件名，逐项对比：

- 卡片、用户、bot 名三个数一致，说明没丢数据。
- 新表和 `cards` 的新字段出现。
- 新路由不带会话返回 401，不是 404。

需要额外证明时，在**副本**上再执行一次建表逻辑，确认幂等（`Store(path).init()` 连跑两次不报错）。不要在生产的库上试。

### 3.6 回滚

代码回滚：

```bash
cd /opt/proclan
git switch --detach <升级前commit>
sudo systemctl restart proclan
```

新版只加表和加列，旧版代码忽略它们，所以回滚不需要动数据库。回滚后再跑 3.5 的核对。回滚是修复动作，不用等人批准；但要在汇报里写清楚为什么回滚、现在停在哪个 commit。

回滚后 HEAD 是游离状态。要回到主线：

```bash
cd /opt/proclan
git switch main
git merge --ff-only origin/main
sudo systemctl restart proclan
```

## 4. 备份和恢复

备份不停机也可以用 SQLite 自己的备份接口：

```bash
sudo mkdir -p /var/backups/proclan
/opt/proclan/server/.venv/bin/python - <<'EOF'
import sqlite3
src = sqlite3.connect('/opt/proclan/server/data/proclan.sqlite3')
dst = sqlite3.connect('/var/backups/proclan/backup.sqlite3')
src.backup(dst)
EOF
```

或者停服务再整体复制：

```bash
sudo systemctl stop proclan
cp -a /opt/proclan/server/data /var/backups/proclan-data
sudo systemctl start proclan
```

- 改过 `PROCLAN_DATA_DIR` 就复制那个目录。
- 备份里有密码哈希和 bot token。放进会传出去的地方之前先问人。
- `server/.env` 单独保管，不要塞进备份包。
- 恢复：停服务，用备份覆盖数据目录，启动，跑第 2.7 节的验收。这是删数据的反向操作，动手前确认是哪一份备份。

## 5. 故障表

| 症状 | 多半是 | 动作 |
| --- | --- | --- |
| 本机 `curl :8787` 连接被拒 | 服务没起，或 `PORT` 不是 8787 | `systemctl status`、`journalctl`、`ss -tlnp`，确认端口与代理一致 |
| 外网 502 / 504 | 代理指向错端口，或服务没起 | 先验本机 200，再查代理的 upstream |
| 外网超时，本机 200 | DNS、备案、安全组或上游防火墙 | 把本机证据交给对方；不要改服务 |
| `/openapi.json` 404 | 请求打到了别的站点，或代理路径被改写 | 查 `server_name` 和 `location /` |
| `/media/...` 变成 `http://127.0.0.1:8787/...` | 代理没传 `Host`/`X-Forwarded-Proto`，或地址不在 `FORWARDED_ALLOW_IPS` | 修代理头或加入代理地址；不要写 `*` |
| `/mcp` 401 | token 错、被轮换，或用了会话 token | 让对方从 Bot 页重新复制 bot token；不要自己生成 |
| `/mcp` 405 | 用 GET 探活 | 用 POST 发 initialize |
| 图片或视频不显示 | 地址不是 http(s)，或写成内网、本机地址，被丢弃 | 换公网地址重发；域名在服务器上不解析，这是设计 |
| 卡片突然少了 | 超过 `BOT_MESSAGE_TTL_HOURS`（默认 24 小时） | 这是产品行为；调大 TTL 后重启 |
| 写卡 429 `retry later` | bot 配额或名字配额 | 等配额恢复；不要改数据库计数器 |
| 写卡 413 `payload too large` | 请求体超过 1 MiB | 拆分提交 |
| 改密码后 MCP 还通 | 改密码不轮换 bot token | 需要断开就 `POST /v1/me/bot-token`，再把新 token 贴回连接 |
| `uv sync` 卡住 | PyPI 慢或被阻断 | 走 2.2 的导出安装 |
| 日志里 `database is locked` 反复出现 | 有另一个进程在写同一个库 | 查 `ss`/`ps` 是否跑了第二份服务，杀掉多余的，再重启 |
| 升级后服务起不来 | 依赖没装，或 `.env` 被改坏 | 看 traceback；按 3.3 补依赖，或恢复到升级前的 commit |

## 6. 必须由人确认的动作

以下动作即使 agent 有能力也不要自己做，先问：

- 删除或覆盖数据目录、数据库、`media/` 里的文件
- 用备份覆盖当前数据
- 改写 `server/.env`
- 换域名、换证书来源、改反向代理的站点
- 打开新的公网端口、改安全组或防火墙
- 改 `sudoers`、改登录方式、改 SSH 配置
- 在生产库上手工 `ALTER`、`DROP`，或执行任何自写迁移
- 换机器、重装系统、把服务换到另一台主机

## 7. 做完怎么汇报

给对方不超过六行，缺什么写「未做」，不要复述命令：

1. 站点：`https://<域名>`，应用是否已指向它。
2. 版本：升级前 commit → 现在 commit；工作区是否干净。
3. 数据：卡片 / 用户 / bot 名三个数，升级前 → 升级后。
4. 服务：active 与否、监听地址、断线秒数、日志有没有异常。
5. 验收：本机与外网的状态码、`/mcp` 是否返回 `protocolVersion`。
6. 待办：客户端是否要重新打 APK（`./scripts/apk production`，在装了 Flutter 的机器上做）。

token 不要出现在汇报里。必须让对方粘贴一次时，说明不要转发。

---

## 附录：同机替换

这一节是给同一台机器上替换已有安装的，不是首次安装。它会动数据和配置，动手前先确认。

1. 停服务：`sudo systemctl stop proclan`
2. 把旧目录挪开：`sudo mv /opt/proclan /opt/proclan.old`
3. 重新克隆：`git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan`
4. 把 `.env` 拷回来：`cp /opt/proclan.old/server/.env /opt/proclan/server/.env`
5. 要保留卡片就恢复数据目录：`cp -a /opt/proclan.old/server/data /opt/proclan/server/data`
6. 重装依赖：`cd /opt/proclan/server && uv sync --frozen --no-dev`
7. 启动并验收：`sudo systemctl start proclan`，然后跑第 2.7 节

用空数据库启动时所有用户都要重新注册，旧账号和 bot token 会消失，用旧 token 的 MCP 连接会失败。能用第 3 节升级就不要走这一节。
