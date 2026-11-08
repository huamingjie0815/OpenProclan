#!/usr/bin/env python3
"""
Proclan 压测脚本。

安全设计：
- 默认只访问 127.0.0.1:8787
- 非本地目标需显式 --confirm-remote 和 --max-concurrency/--max-duration 限制
- 凭据仅从环境变量或运行时获取，不回显不记录
- 不自动创建无限 bot 绕过限制
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import statistics
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

import httpx

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8787
REMOTE_MAX_CONCURRENCY = 10
REMOTE_MAX_DURATION = 60

CATEGORIES = ["科技", "财经", "国际", "社会", "生活", "其他"]


@dataclass
class Stats:
    """测试统计。"""
    success: int = 0
    rate_limited: int = 0  # 429 或 MCP 业务限流
    concurrency_full: int = 0  # 503
    timeout: int = 0
    network_error: int = 0
    unexpected_5xx: int = 0
    mcp_error: int = 0  # 200 内含非限流 MCP error
    latencies_ms: list[float] = field(default_factory=list)

    @property
    def total(self) -> int:
        return (
            self.success
            + self.rate_limited
            + self.concurrency_full
            + self.timeout
            + self.network_error
            + self.unexpected_5xx
            + self.mcp_error
        )

    def percentile(self, p: float) -> float | None:
        if not self.latencies_ms:
            return None
        sorted_lat = sorted(self.latencies_ms)
        idx = int(len(sorted_lat) * p / 100)
        idx = min(idx, len(sorted_lat) - 1)
        return sorted_lat[idx]

    def merge(self, other: Stats) -> None:
        self.success += other.success
        self.rate_limited += other.rate_limited
        self.concurrency_full += other.concurrency_full
        self.timeout += other.timeout
        self.network_error += other.network_error
        self.unexpected_5xx += other.unexpected_5xx
        self.mcp_error += other.mcp_error
        self.latencies_ms.extend(other.latencies_ms)


@dataclass
class Config:
    """压测配置。"""
    target: str
    concurrency: int
    duration: float | None
    requests: int | None
    mode: Literal["read", "write", "mixed"]
    bot_token: str
    session_token: str
    bot_name: str = "loadtest-bot"
    cards_per_batch: int = 1
    disable_rate_limit: bool = False


def make_card(index: int, bot_name: str) -> dict:
    """生成测试卡片。"""
    return {
        "title": f"压测卡片-{index}",
        "category": CATEGORIES[index % len(CATEGORIES)],
        "summary": f"压测摘要 {index}",
        "body": f"压测正文内容 {index}",
        "tags": ["loadtest"],
        "source": "loadtest",
        "created_bot": bot_name,
        "bot_desc": "压力测试 bot",
        "source_urls": [],
        "image_urls": [],
    }


def make_submit_body(cards: list[dict]) -> dict:
    """生成 MCP submit_cards 请求体。"""
    return {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": "submit_cards", "arguments": {"cards": cards}},
    }


async def do_write(
    client: httpx.AsyncClient,
    config: Config,
    index: int,
    stats: Stats,
    *,
    bot_name: str | None = None,
) -> None:
    """执行一次写入请求。"""
    effective_bot_name = bot_name or config.bot_name
    cards = [make_card(index * config.cards_per_batch + i, effective_bot_name) for i in range(config.cards_per_batch)]
    body = make_submit_body(cards)
    headers = {
        "Authorization": f"Bearer {config.bot_token}",
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    start = time.perf_counter()
    try:
        resp = await client.post(f"{config.target}/mcp", json=body, headers=headers, timeout=30)
        elapsed = (time.perf_counter() - start) * 1000
        if resp.status_code == 200:
            data = resp.json()
            if "error" in data:
                error_msg = data.get("error", {}).get("message", "")
                if "太快" in error_msg or "稍后" in error_msg or "名字" in error_msg:
                    stats.rate_limited += 1
                else:
                    stats.mcp_error += 1
            elif "result" in data:
                result = data["result"]
                structured = result.get("structuredContent") or {}
                if "card_ids" in structured or (isinstance(result.get("content"), list) and "card_ids" in str(result["content"])):
                    stats.success += 1
                    stats.latencies_ms.append(elapsed)
                else:
                    stats.mcp_error += 1
            else:
                stats.mcp_error += 1
        elif resp.status_code == 429:
            stats.rate_limited += 1
        elif resp.status_code == 503:
            stats.concurrency_full += 1
        elif 500 <= resp.status_code < 600:
            stats.unexpected_5xx += 1
        else:
            stats.mcp_error += 1
    except httpx.TimeoutException:
        stats.timeout += 1
    except httpx.RequestError:
        stats.network_error += 1


async def do_read(
    client: httpx.AsyncClient,
    config: Config,
    stats: Stats,
) -> None:
    """执行一次读取请求。"""
    headers = {"Authorization": f"Bearer {config.session_token}"}
    start = time.perf_counter()
    try:
        resp = await client.get(f"{config.target}/v1/feed", headers=headers, timeout=30)
        elapsed = (time.perf_counter() - start) * 1000
        if resp.status_code == 200:
            data = resp.json()
            if "cards" in data:
                stats.success += 1
                stats.latencies_ms.append(elapsed)
            else:
                stats.mcp_error += 1
        elif resp.status_code == 429:
            stats.rate_limited += 1
        elif resp.status_code == 503:
            stats.concurrency_full += 1
        elif 500 <= resp.status_code < 600:
            stats.unexpected_5xx += 1
        else:
            stats.mcp_error += 1
    except httpx.TimeoutException:
        stats.timeout += 1
    except httpx.RequestError:
        stats.network_error += 1


async def worker(
    config: Config,
    worker_id: int,
    stop_event: asyncio.Event,
    request_counter: list[int],
    max_requests: int | None,
) -> Stats:
    """单个并发 worker。"""
    stats = Stats()
    index = 0
    read_count = 0
    write_count = 0
    
    async with httpx.AsyncClient() as client:
        while not stop_event.is_set():
            if max_requests is not None:
                if request_counter[0] >= max_requests:
                    break
                request_counter[0] += 1
            
            if config.mode == "read":
                await do_read(client, config, stats)
                read_count += 1
            elif config.mode == "write":
                await do_write(client, config, index, stats, bot_name=config.bot_name)
                index += config.cards_per_batch
                write_count += 1
            else:
                if index % 2 == 0:
                    await do_read(client, config, stats)
                    read_count += 1
                await do_write(client, config, index, stats, bot_name=config.bot_name)
                index += 1
                write_count += 1
            await asyncio.sleep(0)
    
    return stats


async def run_load_test(config: Config) -> Stats:
    """运行压测。"""
    stop_event = asyncio.Event()
    request_counter = [0]
    
    tasks = [
        asyncio.create_task(worker(config, i, stop_event, request_counter, config.requests))
        for i in range(config.concurrency)
    ]
    
    start_time = time.perf_counter()
    if config.duration:
        await asyncio.sleep(config.duration)
        stop_event.set()
    
    results = await asyncio.gather(*tasks)
    elapsed = time.perf_counter() - start_time
    
    total_stats = Stats()
    for r in results:
        total_stats.merge(r)
    
    return total_stats


def print_report(stats: Stats, config: Config, elapsed: float, env_info: dict) -> None:
    """打印测试报告。"""
    print("\n" + "=" * 60)
    print("Proclan 压测报告")
    print("=" * 60)
    
    print("\n【测试环境】")
    print(f"  目标: {config.target}")
    print(f"  模式: {config.mode}")
    print(f"  并发: {config.concurrency}")
    if config.duration:
        print(f"  时长: {config.duration}s")
    if config.requests:
        print(f"  请求数: {config.requests}")
    print(f"  实际耗时: {elapsed:.2f}s")
    if env_info.get("workers"):
        print(f"  服务 workers: {env_info['workers']}")
    if env_info.get("bot_burst"):
        print(f"  bot_burst: {env_info['bot_burst']}")
    if env_info.get("mcp_inflight"):
        print(f"  mcp_inflight: {env_info['mcp_inflight']}")
    
    print("\n【请求统计】")
    print(f"  总请求: {stats.total}")
    print(f"  成功: {stats.success}")
    print(f"  限流 (429/MCP): {stats.rate_limited}")
    print(f"  并发满 (503): {stats.concurrency_full}")
    print(f"  超时: {stats.timeout}")
    print(f"  网络错误: {stats.network_error}")
    print(f"  非预期 5xx: {stats.unexpected_5xx}")
    print(f"  MCP 业务错误: {stats.mcp_error}")
    
    print("\n【吞吐量】")
    total_rps = stats.total / elapsed if elapsed > 0 else 0
    success_rps = stats.success / elapsed if elapsed > 0 else 0
    print(f"  总请求速率: {total_rps:.2f} req/s")
    print(f"  成功吞吐: {success_rps:.2f} req/s")
    
    print("\n【成功请求延迟】")
    if stats.latencies_ms:
        print(f"  样本数: {len(stats.latencies_ms)}")
        print(f"  P50: {stats.percentile(50):.2f} ms")
        print(f"  P95: {stats.percentile(95):.2f} ms")
        print(f"  P99: {stats.percentile(99):.2f} ms")
        print(f"  平均: {statistics.mean(stats.latencies_ms):.2f} ms")
    else:
        print("  无成功请求")
    
    print("\n" + "=" * 60)


async def setup_test_account(target: str) -> tuple[str, str, str]:
    """创建测试账户并返回 (user_id, session_token, bot_token)。"""
    username = f"loadtest_{int(time.time())}"
    password = "loadtest-password-12345"
    
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{target}/v1/auth/register",
            json={"username": username, "password": password},
        )
        if resp.status_code != 200:
            raise RuntimeError(f"注册失败: {resp.status_code} {resp.text}")
        data = resp.json()
        return data["user"]["id"], data["token"], data["bot_token"]


async def count_cards(target: str, session_token: str) -> int:
    """统计当前用户的卡片数。"""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{target}/v1/feed",
            headers={"Authorization": f"Bearer {session_token}"},
            params={"limit": 100},
        )
        if resp.status_code == 200:
            return len(resp.json().get("cards", []))
        return 0


def is_local_target(target: str) -> bool:
    """检查是否为本地目标。"""
    import urllib.parse
    parsed = urllib.parse.urlparse(target)
    host = parsed.hostname or ""
    return host in ("127.0.0.1", "localhost", "::1")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Proclan 压测脚本",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 本地读取压测
  PROCLAN_SESSION=xxx python bench.py --mode read --concurrency 5 --duration 10

  # 本地写入压测（same-bot 模式，会触发单 bot 限流）
  PROCLAN_BOT_TOKEN=xxx PROCLAN_SESSION=xxx python bench.py --mode write --concurrency 1 --duration 10

  # 混合压测
  PROCLAN_BOT_TOKEN=xxx PROCLAN_SESSION=xxx python bench.py --mode mixed --concurrency 5 --requests 100

环境变量（必须）:
  PROCLAN_BOT_TOKEN    - bot token（写入模式需要）
  PROCLAN_SESSION      - session token（读取模式需要）
  PROCLAN_TARGET       - 目标 URL（默认 http://127.0.0.1:8787）

注意:
  - 写入模式使用单一 bot 名，会触发单 bot 48 张/2 秒恢复 1 张的限流
  - 如需测试吞吐上限，请用 run_tests.py（每 worker 独立 bot）
  - 凭据只能通过环境变量传入，不支持命令行参数
""",
    )
    parser.add_argument("--target", default=None, help="目标 URL")
    parser.add_argument("--mode", choices=["read", "write", "mixed"], default="read", help="测试模式")
    parser.add_argument("--concurrency", "-c", type=int, default=5, help="并发数")
    parser.add_argument("--duration", "-d", type=float, default=None, help="测试时长（秒）")
    parser.add_argument("--requests", "-n", type=int, default=None, help="总请求数")
    parser.add_argument("--bot-name", default="loadtest-bot", help="写入使用的 bot 名称（单一 bot）")
    parser.add_argument("--cards-per-batch", type=int, default=1, help="每次写入的卡片数（1-8）")
    parser.add_argument("--confirm-remote", action="store_true", help="确认允许访问非本地目标")
    parser.add_argument("--setup", action="store_true", help="自动创建测试账户")
    parser.add_argument("--verify-writes", action="store_true", help="写入后验证实际入库数")
    parser.add_argument("--output", "-o", help="输出 JSON 结果到文件")
    parser.add_argument("--quiet", "-q", action="store_true", help="减少输出")
    return parser.parse_args()


async def main() -> int:
    args = parse_args()
    
    target = args.target or os.environ.get("PROCLAN_TARGET") or f"http://{DEFAULT_HOST}:{DEFAULT_PORT}"
    
    if not is_local_target(target):
        if not args.confirm_remote:
            print(f"错误: 非本地目标 {target} 需要 --confirm-remote 参数", file=sys.stderr)
            return 1
        if args.concurrency > REMOTE_MAX_CONCURRENCY:
            print(f"错误: 非本地目标并发数限制为 {REMOTE_MAX_CONCURRENCY}", file=sys.stderr)
            return 1
        if args.duration and args.duration > REMOTE_MAX_DURATION:
            print(f"错误: 非本地目标时长限制为 {REMOTE_MAX_DURATION}s", file=sys.stderr)
            return 1
    
    if args.duration is None and args.requests is None:
        args.duration = 10.0
    
    bot_token = os.environ.get("PROCLAN_BOT_TOKEN")
    session_token = os.environ.get("PROCLAN_SESSION")
    
    if args.setup:
        if not args.quiet:
            print(f"创建测试账户...")
        user_id, session_token, bot_token = await setup_test_account(target)
        if not args.quiet:
            print(f"账户已创建: {user_id[:8]}...")
    
    if args.mode in ("write", "mixed") and not bot_token:
        print("错误: 写入模式需要 --bot-token 或 PROCLAN_BOT_TOKEN", file=sys.stderr)
        return 1
    if args.mode in ("read", "mixed") and not session_token:
        print("错误: 读取模式需要 --session-token 或 PROCLAN_SESSION", file=sys.stderr)
        return 1
    
    if args.cards_per_batch < 1 or args.cards_per_batch > 8:
        print("错误: --cards-per-batch 必须在 1-8 之间", file=sys.stderr)
        return 1
    
    cards_before = 0
    if args.verify_writes and args.mode in ("write", "mixed"):
        cards_before = await count_cards(target, session_token)
    
    config = Config(
        target=target,
        concurrency=args.concurrency,
        duration=args.duration,
        requests=args.requests,
        mode=args.mode,
        bot_token=bot_token or "",
        session_token=session_token or "",
        bot_name=args.bot_name,
        cards_per_batch=args.cards_per_batch,
    )
    
    env_info: dict = {}
    
    if not args.quiet:
        print(f"开始压测: {config.mode} 模式, {config.concurrency} 并发")
    
    start = time.perf_counter()
    stats = await run_load_test(config)
    elapsed = time.perf_counter() - start
    
    if args.verify_writes and args.mode in ("write", "mixed"):
        cards_after = await count_cards(target, session_token)
        actual_writes = cards_after - cards_before
        expected_writes = stats.success * args.cards_per_batch if args.mode == "write" else stats.success * args.cards_per_batch // 2
        if not args.quiet:
            print(f"\n写入验证: 预期 {expected_writes}, 实际 {actual_writes}")
            if actual_writes != expected_writes:
                print(f"警告: 写入数不一致！")
    
    if not args.quiet:
        print_report(stats, config, elapsed, env_info)
    
    if args.output:
        result = {
            "target": target,
            "mode": args.mode,
            "concurrency": args.concurrency,
            "duration": args.duration,
            "requests": args.requests,
            "elapsed": elapsed,
            "stats": {
                "total": stats.total,
                "success": stats.success,
                "rate_limited": stats.rate_limited,
                "concurrency_full": stats.concurrency_full,
                "timeout": stats.timeout,
                "network_error": stats.network_error,
                "unexpected_5xx": stats.unexpected_5xx,
                "mcp_error": stats.mcp_error,
            },
            "latency_ms": {
                "p50": stats.percentile(50),
                "p95": stats.percentile(95),
                "p99": stats.percentile(99),
                "samples": len(stats.latencies_ms),
            },
            "throughput": {
                "total_rps": stats.total / elapsed if elapsed > 0 else 0,
                "success_rps": stats.success / elapsed if elapsed > 0 else 0,
            },
        }
        Path(args.output).write_text(json.dumps(result, indent=2, ensure_ascii=False))
        if not args.quiet:
            print(f"结果已保存到: {args.output}")
    
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
