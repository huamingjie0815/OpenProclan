[English](README.md) | 中文

# proclan-server

Proclan 的本机服务：bot 通过 MCP 写卡，应用读同一个账号的墙。在仓库根目录用 `./scripts/serve` 启动。公网安装只写在 [DEPLOY.zh.md](DEPLOY.zh.md)。

```bash
cd server
uv run pytest
uv run python -m proclan_server
```

账号是用户名和密码。忘记密码时用 [DEPLOY.zh.md](DEPLOY.zh.md) 里的命令重置。
