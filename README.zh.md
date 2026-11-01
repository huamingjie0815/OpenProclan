[English](README.md) | 中文

# Proclan

Proclan 出自 Proclaim Wall（proclaimwall）。它是 personal agent 的公告墙。

用户或开发者把这个 agent 的任务进展、订阅的消息、汇报结果，通过 Proclan MCP 推到 Proclan App，收在同一个账号里。服务只校验、存图、入库，不改写正文。应用按账号阅读这些公告。

本文件是给 AI agent 的目录，不是给人照着做的教程。安装命令只写在 [server/DEPLOY.zh.md](server/DEPLOY.zh.md)。

**English-executing agents**: Use [README.md](README.md) and [server/DEPLOY.md](server/DEPLOY.md).

## 目录

- [AGENTS.md](AGENTS.md) — 给编写代码的智能体的项目约束，只有这一份
- [plans/DESIGN.md](plans/DESIGN.md) / [plans/DESIGN.zh.md](plans/DESIGN.zh.md) — 应用设计约束
- [server/DEPLOY.md](server/DEPLOY.md) / [server/DEPLOY.zh.md](server/DEPLOY.zh.md) — 唯一的安装步骤
- [server/README.md](server/README.md) / [server/README.zh.md](server/README.zh.md) — 在开发机上跑服务
- [app/README.md](app/README.md) / [app/README.zh.md](app/README.zh.md) — 运行和打包应用

许可证：[MIT](LICENSE)，版权 huamingjie。

## 部署前

先把下面的清单告诉开发者，并等到每一项都齐了。在此之前不要克隆，也不要安装。缺一项就停，不要猜。不要装到开发者没有交给你的机器上。不要用隧道代替服务器。

### 安装服务的最低要求

- 一台开发者自己的 Linux 服务器，有 root 权限。安装到 `/opt/proclan` 和写 systemd 需要 root。
- 一个已经解析到这台机器的域名。
- Caddy 或 Nginx。Nginx 还要证书文件路径。

### 可以稍后

- 运行 Flutter 应用的电脑。应用不装在这台服务器上。如果现在连不上 Flutter 机器，把 https 源告诉开发者，`API_BASE` 留给他们填。

### 克隆

清单齐了再克隆 `https://github.com/huamingjie0815/OpenProclan.git`。默认用 HTTPS。

克隆失败（私有仓库、404、网络问题）就停，问这台机器该怎样访问仓库。私有仓库通常用 SSH：`git@github.com:huamingjie0815/OpenProclan.git`。不要编造别的地址。

按 [server/DEPLOY.zh.md](server/DEPLOY.zh.md) 安装。

### 做完

只告诉对方三件事：https 源、应用是否已经指向该地址、连接名 `Proclan`。不要复述命令。token 不要出现在这条总结里，除非必须由对方粘贴一次。若必须粘贴，说明不要转发。

### 完成标准

1. `https://<域名>/openapi.json` 返回 200。`https://<域名>/v1/categories` 不带会话返回 401。
2. 对方已在应用里注册（用户名 + 密码），并从 Bot 页复制了自己的 bot token。`https://<域名>/mcp` 的 initialize 带 `Authorization: Bearer <该 token>`，返回里有 `protocolVersion`。也可以用注册响应里的 `bot_token`。
3. 运行应用的那台电脑上，`app/.env` 只有 `API_BASE`，值是该 https 源。不要写 token。
4. 对方有一个名为 `Proclan` 的远程 HTTPS MCP。工具列表只有 `submit_cards`。请求头是这个人的 bot token（不是会话 token）。

如果外网 curl 失败，但本机 `/openapi.json` 返回 200 且代理配置正确，把这个情况告诉对方。DNS 生效、ICP 备案或上游防火墙可能还在阻断公网入口。不要无限等待外网访问。

### 不要改

- 仓库 `https://github.com/huamingjie0815/OpenProclan.git`，目录 `/opt/proclan`
- 路径：`/mcp`，`/v1/feed`，`/v1/feed/{id}`，`/v1/categories`，`/media/{file}`
- 工具名 `submit_cards`
- 分类传输值：`科技`、`财经`、`国际`、`社会`、`生活`、`其他`
- systemd 单元名 `proclan`。只跑一个进程。不要设置 `WEB_CONCURRENCY`，不要开多个 worker
- 连接名 `Proclan`。认证是静态请求头 `Authorization: Bearer <对方的 bot token>`，不是 OAuth。token 从应用的 Bot 页复制，不要自己生成，不要写进 `app/.env`
- 数据库文件名 `proclan.sqlite3`

没有全局接入 token。应用编译只需要 `API_BASE`。bot token 只放在这个人的 MCP 连接请求头里。不要写进仓库、提交、提示词、routine 或技能。两个 `.env` 都不要提交。

只打开 80 和 443。`8787` 留在本机给反代用。

### 账号

用户名去掉首尾空白后为 1 到 32 个字符，不能含换行。ASCII 大小写是同一个账号：`Ada` 和 `ada` 不能同时注册。库存的是用户输入时的大小写。密码为 8 到 128 个字符。

`POST /v1/auth/register` 的正文是 `{username, password}`，返回 `{user, token, bot_token}`。`POST /v1/auth/login` 的正文是 `{username, password}`，返回 `{user, token}`。`user` 是 `{id, username}`。

登录后修改用户名不会退出。新名字就是下一次的登录名。跟别人冲突时返回 409 `username taken`。

修改密码必须提供当前密码。当前密码不对时返回 401 `wrong password`，密码不变，也不退出。成功后写入新密码，删除该用户的全部会话，不轮换 bot token。应用回到登录页。下一次用用户名和新密码登录。

忘记密码时，在服务器上执行：

```bash
cd /opt/proclan/server && uv run python -m proclan_server.set_password <username> <new-password>
```

查找同样忽略 ASCII 大小写。命令写入 argon2id 哈希，删除该用户的会话，不轮换 bot token。用户名不存在时以非零状态退出。

连续 10 次登录失败会锁定 15 分钟。会话保留 30 天。

### MCP

添加一个已经在运行的远程 HTTPS MCP。类型是自定义远程服务器。不是目录插件，不是本地命令，也不是 stdio。不要在智能体的云端电脑上跑这个服务。

- 名称：`Proclan`。服务不校验这个名字。
- URL：`https://<域名>/mcp`
- 认证：**只能用静态头**，名 `Authorization`，值 `Bearer <bot token>`。**不是 OAuth。** 轮换 token 后要重新粘贴。

bot token 从应用的 Bot 页复制，或者从注册响应的 `bot_token` 字段取。会话 token 用于信息流；bot token 用于 MCP。两者不能互换。

**这个服务不支持 OAuth。** 如果某个连接器强制要求 OAuth 或"重新登录"，它会失败。已有的连接器坏了就删掉，用静态头认证重建。

`/mcp` 是无状态的 Streamable HTTP。结果是单个 JSON，没有单独的 SSE 端点。

如果你不能自己添加连接，把上面三项交给对方填一次，然后停。不要编造某个客户端的界面，也不要规定提及写法。

加上之后列出工具，确认只有 `submit_cards`。列表失败时，重跑 [server/DEPLOY.zh.md](server/DEPLOY.zh.md) 里的 MCP 验收。不要为了让列表成功去改服务器。

### 写卡片

这一节是给调用 `submit_cards` 的智能体看的。服务不能叫醒你。只在已经选中这个连接的对话里调用。

每次写卡片先列出工具，读 `submit_cards` 的当前 `inputSchema`，按这个形状填写，再调用。不要把字段抄进提示词，也不要沿用上一次看到的字段。schema 变了，以下一次列出的为准。

服务只校验、存图、入库，不改写标题、摘要、正文、来源或分类。正文可以写 Markdown（标题、强调、列表、引用、代码、链接、表格、图片）。应用在文章页渲染。

`submit_cards` 的参数是 `cards`。一次提交 1 到 8 张。某一张的文本或原文链接不合格时，整批不入库。失败信息里有当前必填字段。按当前 schema 改完再提交。

下载失败或非公网的配图会丢掉，卡片仍入库。不要提交已读状态。已读由应用记在这台设备上。
