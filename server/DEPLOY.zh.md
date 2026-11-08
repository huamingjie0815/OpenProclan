[English](DEPLOY.md) | 中文

# 部署 Proclan 服务

把 Proclan 服务部署到对方自己的 Linux 机器上，前面用 HTTPS 反向代理。不要把这个服务装进智能体的云端电脑。服务本身不签发证书，也不对外直接提供 TLS。

没有全局接入 token。信息流和删除要带登录后的会话。已经落在 `/media` 的图片也带这个会话。`/mcp` 要带这个人自己的 bot token，从应用里复制。两者不能互换：会话 token 用于信息流和这些已保存的图片；bot token 用于 MCP。

这是唯一的安装步骤。[../README.zh.md](../README.zh.md) 是给 AI agent 的目录。不要把这些命令再抄进别的文档。

## 准备

安装服务的最低要求：

- 一台对方自己的 Linux 服务器，有 root 权限和公网地址。
- 一个已经解析到这台机器的域名。
- Caddy 或 Nginx。Nginx 还要证书文件路径。

Flutter / 应用打包可以稍后处理。如果现在连不上 Flutter 机器，先装好服务，把 https 源告诉对方，`API_BASE` 留给他们填。

只打开 80 和 443。`8787` 留在本机，给反向代理用。

## 安装

部署目录用 `/opt/proclan`。

### 克隆

```bash
git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan
```

克隆失败（私有仓库、404、网络问题）就停，问这台机器该怎样访问仓库。私有仓库通常用 SSH：`git clone git@github.com:huamingjie0815/OpenProclan.git /opt/proclan`。不要编造别的地址。

### 依赖

```bash
cd /opt/proclan/server
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv sync --frozen --no-dev
cp .env.example .env
```

`uv sync` 把依赖装进 `server/.venv`，并按 `server/.python-version` 准备 Python 3.12。`.venv` 不要提交。

如果 `uv sync --frozen --no-dev` 卡住（PyPI 访问慢或被阻断），一个备选方案是导出后用 pip 安装：

```bash
uv export --frozen --no-dev > requirements.txt
.venv/bin/pip install -r requirements.txt
```

### 检查端口

默认监听端口是 `8787`。检查是否被占用：

```bash
ss -tlnp | grep :8787
```

如果已有进程占用 `8787`，选一个其他端口。在 `server/.env` 里设置 `PORT`，并把反向代理指向同一个端口。

### .env

`server/.env` 存放监听地址。进程启动时读取这个文件。环境里已经存在的同名变量优先。

必填：

```bash
HOST=127.0.0.1
PORT=8787
```

`HOST=127.0.0.1` 时，只有这台机器上的反向代理能连到服务。

可选变量：

| 变量 | 作用 |
| --- | --- |
| `BOT_MESSAGE_TTL_HOURS` | 每条消息在服务端保留的小时数，默认 `24`，小于 1 时按 1 |
| `PROCLAN_DATA_DIR` | 数据库和图片目录，默认是 `server/data`。用绝对路径 |
| `FORWARDED_ALLOW_IPS` | 允许改写协议的代理来源，默认 `127.0.0.1,::1` |

**图片地址问题排查**：已经落在磁盘上的图片从 `/media` 提供。如果这些地址变成 `http://127.0.0.1:8787/media/...` 而不是 `https://<域名>/media/...`，说明代理没有正确设置 `Host` 和 `X-Forwarded-Proto`，或其地址不在 `FORWARDED_ALLOW_IPS` 里。修正代理头或把代理地址加进 `FORWARDED_ALLOW_IPS`。新卡的图片是提交的 URL，不用这两项。

### 数据目录

数据放在 `PROCLAN_DATA_DIR`：

- `proclan.sqlite3`：卡片
- `media/`：旧卡仍在引用的图片文件

新卡保存提交的 URL，不再往这里加文件。这些旧卡过期或被删除后，目录会变小。不要删掉仍被卡片引用的文件，否则那张图会消失。

## 账号

应用用用户名和密码注册、登录。忘记密码时，在这台服务器上执行：

```bash
cd /opt/proclan/server
uv run python -m proclan_server.set_password <username> <new-password>
```

查找忽略 ASCII 大小写。命令写入 argon2id 哈希，删除该用户的会话，不轮换 bot token。用户名不存在时以非零状态退出。账号规则见 [../AGENTS.md](../AGENTS.md)。

## HTTPS

代理和本服务在同一台机器上时，保持 `FORWARDED_ALLOW_IPS` 的默认值。代理必须把原始域名放进 `Host`，并把 `X-Forwarded-Proto` 设为 `https`。已经在磁盘上的图片，服务用这两个值拼出 `/media` 地址。代理没被信任，或没传这两项时，这些地址会变成 `http://127.0.0.1:8787/media/...`，手机上的应用打不开。新卡的图片是提交的 URL，不用这两项。

### Caddy

```caddy
proclan.example.com {
    reverse_proxy 127.0.0.1:8787
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
    }
}
```

代理不在 `127.0.0.1` 上时，把 `FORWARDED_ALLOW_IPS` 设成那台代理的地址。不要写成 `*`，否则任意来源都能改写协议。

### Nginx 加静态首页

有些部署在 `/` 放一个静态的 ICP 或落地页，其他路径代理到应用。用 `location = /` 精确匹配：

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

`location = /` 精确匹配首页。其他路径走应用。

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

如果外网 curl 失败，但本机 `/openapi.json` 返回 200 且代理配置正确，把这个情况告诉对方。DNS 生效、ICP 备案或上游防火墙可能还在阻断公网入口。不要无限等待外网访问。

### MCP 验收

MCP 地址是 `https://proclan.example.com/mcp`。这是无状态的 Streamable HTTP，结果是单个 JSON，没有单独的 SSE 端点。

请求要带这个人的 bot token。token 从应用的 Bot 页复制，或者从 `POST /v1/auth/register` 的响应里取 `bot_token` 字段。没有 bot token 就停，不要自己生成。

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

信息流和删除带的是登录会话，不是 bot token。已经落在 `/media` 的图片也带这个会话。新卡的图片是提交的 http(s)，这些请求不带会话。

## MCP 连接

添加一个远程 HTTPS MCP：

- **名称**：`Proclan`
- **URL**：`https://<域名>/mcp`
- **认证**：**只能用静态头**。名 `Authorization`，值 `Bearer <bot token>`。**不是 OAuth。**

bot token 从应用的 Bot 页复制，或者从注册响应的 `bot_token` 字段取。会话 token 用于信息流；bot token 用于 MCP。两者不能互换。

**这个服务不支持 OAuth。** 如果某个连接器强制要求 OAuth 或"重新登录"，它会失败。已有的连接器坏了就删掉，用静态头认证重建。

连上之后调 `tools/list`。唯一的工具必须是 `submit_cards`。失败就重跑上面的 MCP 验收。每次调 `submit_cards` 前都要读当前的 `inputSchema`；不要把字段表写进提示词。

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

---

## 附录：同机替换

这一节是给同一台机器上替换已有安装的，不是首次安装。

1. 停服务：`sudo systemctl stop proclan`
2. 把旧目录挪开：`sudo mv /opt/proclan /opt/proclan.old`
3. 重新克隆：`git clone https://github.com/huamingjie0815/OpenProclan.git /opt/proclan`
4. 把 `.env` 拷回来：`cp /opt/proclan.old/server/.env /opt/proclan/server/.env`
5. 如果要保留卡片，恢复数据目录：`cp -a /opt/proclan.old/server/data /opt/proclan/server/data`
6. 重装依赖：`cd /opt/proclan/server && uv sync --frozen --no-dev`
7. 启动：`sudo systemctl start proclan`

如果用空数据库启动，所有用户都要重新注册。旧账号和 bot token 会消失。用旧 token 的 MCP 连接会失败；注册后用新 token 更新它们。
