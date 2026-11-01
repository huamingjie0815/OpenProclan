English | [中文](README.zh.md)

# proclan-server

Local server for the announcement wall. From the repository root, `./scripts/serve` starts it. The public install is only in [DEPLOY.md](DEPLOY.md).

```bash
cd server
uv run pytest
uv run python -m proclan_server
```

Accounts are a username and a password. Reset a forgotten password with the command in [DEPLOY.md](DEPLOY.md).
