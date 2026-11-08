# Proclan 压测工具

对 Proclan 服务进行压力测试和限流验证的脚本集。

## 安全设计

- **默认只访问本地**：默认目标是 `127.0.0.1:8787`
- **远程保护**：非本地目标需要 `--confirm-remote` 参数，且并发数限制为 10、时长限制为 60 秒
- **凭据安全**：凭据仅从环境变量或命令行获取，不回显、不记录到日志
- **隔离测试**：`run_tests.py` 使用临时数据库和临时账户，测试完自动清理
- **不修改配置**：不自动关闭限流或更改服务配置

## 文件说明

| 文件 | 用途 |
|------|------|
| `bench.py` | 独立压测脚本，支持读/写/混合模式 |
| `run_tests.py` | 完整测试套件，自动启动服务和验证 |

## 快速开始

### 运行完整测试套件

```bash
cd server
uv run python loadtest/run_tests.py
```

这会：
1. 在临时目录创建合成数据库
2. 启动两 worker 的测试服务
3. 创建测试账户
4. 运行读取吞吐、写入吞吐、限流边界、写入验证等测试
5. 输出报告并自动清理

### 单独使用 bench.py

首先启动本地服务：

```bash
cd server
./scripts/serve  # 或手动 uvicorn
```

然后运行压测：

```bash
# 读取压测（需要 session token）
uv run python loadtest/bench.py --mode read --concurrency 10 --duration 10 \
    --session-token "$PROCLAN_SESSION"

# 写入压测（需要 bot token 和 session token）
uv run python loadtest/bench.py --mode write --concurrency 5 --duration 10 \
    --bot-token "$PROCLAN_BOT_TOKEN" --session-token "$PROCLAN_SESSION"

# 混合模式
uv run python loadtest/bench.py --mode mixed --concurrency 5 --requests 100 \
    --bot-token "$PROCLAN_BOT_TOKEN" --session-token "$PROCLAN_SESSION"

# 自动创建测试账户
uv run python loadtest/bench.py --mode write --setup --concurrency 5 --duration 10
```

## bench.py 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--target` | 目标 URL | `http://127.0.0.1:8787` |
| `--mode` | 测试模式：read/write/mixed | `read` |
| `--concurrency`, `-c` | 并发数 | `5` |
| `--duration`, `-d` | 测试时长（秒） | `10` |
| `--requests`, `-n` | 总请求数（与 duration 二选一） | - |
| `--bot-token` | MCP bot token | 环境变量 `PROCLAN_BOT_TOKEN` |
| `--session-token` | 登录 session token | 环境变量 `PROCLAN_SESSION` |
| `--bot-name` | 写入使用的 bot 名称 | `loadtest-bot` |
| `--cards-per-batch` | 每次写入的卡片数（1-8） | `1` |
| `--setup` | 自动创建测试账户 | - |
| `--verify-writes` | 写入后验证实际入库数 | - |
| `--output`, `-o` | 输出 JSON 结果到文件 | - |
| `--confirm-remote` | 确认允许访问非本地目标 | - |

## run_tests.py 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--workers` | 服务 worker 数 | `2` |
| `--no-cleanup` | 不清理临时文件 | - |
| `--output`, `-o` | 输出 JSON 结果 | - |

## 测试场景

### run_tests.py 包含的测试

| 测试 | 说明 |
|------|------|
| 读取吞吐量 | 并发读取 feed，统计 RPS 和延迟 |
| 写入吞吐量 | 并发写入卡片（每 worker 用不同 bot 避免限流） |
| 限流边界验证 | 单 bot 连续发 55 张，验证 48 张后限流 |
| 并发突发限流 | 同时发 60 个请求，验证只入库 ≤48 张 |
| bot 名称限流 | 连续创建新 bot 名，验证 8 个后限流 |
| 写入验证 | 检查成功响应数与实际入库数一致 |

### 手动限流验证

```bash
# 验证单 bot 限流（burst=48）
uv run python loadtest/bench.py --mode write --setup \
    --concurrency 1 --requests 55 --verify-writes

# 验证名称限流（burst=8）
uv run python loadtest/bench.py --mode write --setup \
    --concurrency 1 --requests 12 --bot-name "new-bot-{n}"
```

## 输出说明

### 统计指标

- **成功**：HTTP 200 且 MCP 响应包含 `result.card_ids`（写入）或 `cards`（读取）
- **限流 (429/MCP)**：HTTP 429 或 MCP 响应包含限流相关错误
- **并发满 (503)**：HTTP 503
- **超时**：请求超时
- **网络错误**：连接失败等网络问题
- **非预期 5xx**：其他 5xx 错误
- **MCP 业务错误**：200 内含非限流的 MCP error

### 吞吐量

- **总请求速率**：包含所有请求（成功 + 失败）
- **成功吞吐**：仅统计成功的请求，**不把 429 的低延迟当作成功**

### 延迟

仅统计成功请求的延迟：

- **P50/P95/P99**：百分位延迟（毫秒）
- **样本数**：成功请求数

## 示例输出

```
============================================================
Proclan 压测报告
============================================================

【测试环境】
  目标: http://127.0.0.1:8787
  模式: write
  并发: 5
  时长: 10s
  实际耗时: 10.05s

【请求统计】
  总请求: 487
  成功: 240
  限流 (429/MCP): 247
  并发满 (503): 0
  超时: 0
  网络错误: 0
  非预期 5xx: 0
  MCP 业务错误: 0

【吞吐量】
  总请求速率: 48.46 req/s
  成功吞吐: 23.88 req/s

【成功请求延迟】
  样本数: 240
  P50: 15.23 ms
  P95: 28.45 ms
  P99: 35.67 ms
  平均: 17.89 ms

============================================================
```

## 限制说明

### 当前限流配置（生产默认）

| 配置 | 值 | 说明 |
|------|-----|------|
| `bot_burst` | 48 | 每 bot 突发卡片数 |
| `bot_refill_seconds` | 2 | 每 2 秒恢复 1 张 |
| `bot_name_cap` | 32 | 每账号最多 bot 名数 |
| `bot_name_burst` | 8 | 新名字突发数 |
| `bot_name_refill_seconds` | 60 | 每 60 秒恢复 1 个名额 |
| `body_bytes` | 1 MiB | 请求体大小限制 |
| `mcp_inflight` | 128 | 同时处理的 MCP 请求 |
| `limit_concurrency` | 256 | uvicorn 并发连接数 |

### 测试模式说明

| 模式 | 说明 |
|------|------|
| `bench.py --mode write` | **same-bot 模式**：使用单一 bot 名，会触发单 bot 限流（48 张/突发） |
| `run_tests.py` 写入吞吐 | **multi-bot 模式**：每 worker 使用独立 bot 名，测试非限流下的吞吐 |

**注意**：`bench.py` 不自动派生 bot 名，避免悄悄绕过单 bot 限流。如需测试吞吐上限，使用 `run_tests.py`。

### 环境限制

- **本次测试环境**：4 核 16GB 云代理环境，**非 2c2g**，结果仅供参考
- **不能外推 2c2g 容量**：未在 2c2g 环境实测，不承诺用户数/QPS
- **SQLite WAL**：多 worker 共享同一数据库，写入有锁竞争
- **临时服务**：测试服务在临时目录运行，结束后清理

## 注意事项

1. **不要压测生产环境**：脚本默认只访问本地，远程需要显式确认
2. **凭据安全**：不要把 token 写入代码或提交到版本库
3. **资源清理**：`run_tests.py` 会自动清理，`bench.py` 需要手动清理测试数据
4. **结果解读**：限流是正常行为，只有非预期 5xx 和写入不一致才是问题
