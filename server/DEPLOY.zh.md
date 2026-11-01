[English](DEPLOY.md) | 中文

# 部署 Proclan 服务

把 Proclan 服务部署到对方自己的 Linux 机器上，前面用 HTTPS 反向代理。不要把这个服务装进智能体的云端电脑。服务本身不签发证书，也不对外直接提供 TLS。

没有全局接入 token。信息流、删除和图片要带登录后的会话。`/mcp` 要带这个人自己的 bot token，从应用里复制。两者不能互换。

这是唯一的安装步骤。[../README.zh.md](../README.zh.md) 是给 AI agent 的目录。不要把这些命令再抄进别的文档。

## 准备

- 一台对方自己的 Linux 服务器，有公网地址和域名。
- Python 3.12 或更新版本。`uv` 会按 `server/.python-version` 准备解释器。
- 一个反向代理，例如 Caddy 或 Nginx，负责 443 端口。
- 服务器能主动访问公网。卡片里的图片由服务自己下载，不是客户端上传。

只打开 80 和 443。`8787` 留在本机，给反向代理用。

## 安装

部署目录用 `/opt/proclan`。

```bash
git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan
cd /opt/proclan/server
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv sync --frozen --no-dev
cp .env.example .env
```

`uv sync` 把依赖装进 `server/.venv`，并按 `server/.python-version` 准备 Python 3.12。`.venv` 不要提交。

`server/.env` 只需要监听地址。进程启动时读取这个文件。环境里已经存在的同名变量优先，文件不会覆盖它们。

```bash
HOST=127.0.0.1
PORT=8787
```

`HOST=127.0.0.1` 时，只有这台机器上的反向代理能连到服务。

| 变量 | 作用 |
| --- | --- |
| `HOST` | 监听地址。和代理在同一台机器时用 `127.0.0.1` |
| `PORT` | 监听端口，默认 `8787` |
| `BOT_MESSAGE_TTL_HOURS` | 可选。每条消息在服务端保留的小时数，默认 `24`，小于 1 时按 1 |
| `PROCLAN_DATA_DIR` | 可选。数据库和图片目录，默认是 `server/data`。用绝对路径 |
| `FORWARDED_ALLOW_IPS` | 可选。允许改写协议的代理来源，默认 `127.0.0.1,::1` |

数据放在 `PROCLAN_DATA_DIR`：

- `proclan.sqlite3`：卡片
- `media/`：下载后的图片

这个目录会随卡片变大。不要删除正在使用的 `media/`，否则文章里的插图会消失。

## 账号

应用用用户名和密码注册、登录。忘记密码时，在这台服务器上执行：

```bash
cd /opt/proclan/server
uv run python -m proclan_server.set_password <username> <new-password>
```

查找忽略 ASCII 大小写。命令写入 argon2id 哈希，删除该用户的会话，不轮换 bot token。用户名不存在时以非零状态退出。账号规则见 [../AGENTS.md](../AGENTS.md)。

## HTTPS

代理和本服务在同一台机器上时，保持 `FORWARDED_ALLOW_IPS` 的默认值。代理必须把原始域名放进 `Host`，并把 `X-Forwarded-Proto` 设为 `https`。图片地址用这两个值拼出来。代理没被信任，或没传这两项时，图片地址会变成 `http://127.0.0.1:8787/media/...`，手机上的应用打不开。

一次提交最多 8 张卡、每张最多 6 张图，每张图的下载上限是 15 秒。把代理的读超时设到至少 180 秒。图片多并且源站慢时再加大。

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

把 `proclan.example.com` 换成对方的域名。Caddy 会申请证书，并把请求从本机转到 `8787`。

### Nginx

证书换成对方自己的文件。

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

代理不在 `127.0.0.1` 上时，把 `FORWARDED_ALLOW_IPS` 设成那台代理的地址。不要写成 `*`，否则任意来源都能改写协议。

## 常驻运行

只跑一个进程。不要设置 `WEB_CONCURRENCY`，也不要开多个 worker。写入锁在进程内部。

下面的单元使用上面的克隆路径。`.env` 里已经有 `HOST` 和 `PORT`。不要在单元里写 token。

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

把单元保存为 `/etc/systemd/system/proclan.service`。

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now proclan
sudo systemctl status proclan
```

本机可以先看服务是否起来。`/openapi.json` 是 200。`/v1/categories` 不带会话是 401。

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8787/openapi.json
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8787/v1/categories
```

## 从外网验收

把域名换成实际的。

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://proclan.example.com/openapi.json
curl -sS -o /dev/null -w '%{http_code}\n' https://proclan.example.com/v1/categories
```

MCP 地址是 `https://proclan.example.com/mcp`。这是无状态的 Streamable HTTP，结果是单个 JSON，没有单独的 SSE 端点。请求要带这个人的 bot token，并接受 JSON。token 从应用复制。没有就停，不要自己生成。

```bash
curl -sS https://proclan.example.com/mcp \
  -H "Authorization: Bearer <对方的 bot token>" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"deploy-check","version":"0"}}}'
```

返回里能看到 `protocolVersion` 即可。

写卡片时先列出工具，读 `submit_cards` 的当前 inputSchema。不要把字段表写进提示词。服务不改写标题、摘要、正文、来源或分类。

## 应用

在运行应用的那台电脑上，把 `API_BASE` 设成这个 https 源，然后按 [../app/README.zh.md](../app/README.zh.md) 做。不要在服务器上编译应用。不要把地址写进源码。

信息流、删除和文章插图带的是登录会话，不是 bot token。插图地址必须是 `https://proclan.example.com/media/...` 这种形式。

添加一个名为 `Proclan` 的远程 HTTPS MCP，地址是 `https://proclan.example.com/mcp`，请求头是 `Authorization: Bearer <对方的 bot token>`。

## 更新和备份

```bash
cd /opt/proclan
git pull
cd server
uv sync --frozen --no-dev
sudo systemctl restart proclan
```

备份前先停服务，再复制整个数据目录，然后启动：

```bash
sudo systemctl stop proclan
cp -a /opt/proclan/server/data /var/backups/proclan-data
sudo systemctl start proclan
```

如果改过 `PROCLAN_DATA_DIR`，复制那个目录。`server/.env` 单独保管，不要放进会传出去的备份包。
