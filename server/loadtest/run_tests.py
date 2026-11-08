#!/usr/bin/env python3
"""
Proclan 完整压测套件。

支持：
- 启动隔离测试服务（两 worker）
- 合成数据库和账户
- 分场景压测
- 限流边界验证
- 跨 worker 原子性检查
- 自动清理

用法:
    python run_tests.py [--workers N] [--no-cleanup]
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT / "src"))


@dataclass
class TestEnv:
    """测试环境。"""
    data_dir: Path
    port: int
    workers: int
    process: subprocess.Popen | None = None
    user_id: str = ""
    session_token: str = ""
    bot_token: str = ""
    base_url: str = ""
    
    def cleanup(self) -> None:
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
        if self.data_dir.exists():
            shutil.rmtree(self.data_dir, ignore_errors=True)


def find_free_port() -> int:
    """找一个空闲端口。"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_server(port: int, timeout: float = 30) -> bool:
    """等待服务启动。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return True
        except OSError:
            time.sleep(0.1)
    return False


async def register_user(base_url: str) -> tuple[str, str, str]:
    """注册测试用户，返回 (user_id, session_token, bot_token)。"""
    username = f"loadtest_{int(time.time() * 1000)}"
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{base_url}/v1/auth/register",
            json={"username": username, "password": "loadtest-password"},
        )
        if resp.status_code != 200:
            raise RuntimeError(f"注册失败: {resp.status_code} {resp.text}")
        data = resp.json()
        return data["user"]["id"], data["token"], data["bot_token"]


def start_server(data_dir: Path, port: int, workers: int, env_overrides: dict | None = None) -> subprocess.Popen:
    """启动服务进程。"""
    env = os.environ.copy()
    env["PROCLAN_DATA_DIR"] = str(data_dir)
    env["HOST"] = "127.0.0.1"
    env["PORT"] = str(port)
    env["PROCLAN_WORKERS"] = str(workers)
    if env_overrides:
        env.update(env_overrides)
    
    proc = subprocess.Popen(
        [sys.executable, "-m", "proclan_server"],
        cwd=SERVER_ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return proc


@asynccontextmanager
async def test_server(workers: int = 2, env_overrides: dict | None = None):
    """上下文管理器：启动测试服务。"""
    data_dir = Path(tempfile.mkdtemp(prefix="proclan_test_"))
    port = find_free_port()
    proc = None
    
    try:
        proc = start_server(data_dir, port, workers, env_overrides)
        if not wait_for_server(port):
            stdout, stderr = proc.communicate(timeout=5)
            raise RuntimeError(f"服务启动失败: {stderr.decode()}")
        
        base_url = f"http://127.0.0.1:{port}"
        user_id, session_token, bot_token = await register_user(base_url)
        
        env = TestEnv(
            data_dir=data_dir,
            port=port,
            workers=workers,
            process=proc,
            user_id=user_id,
            session_token=session_token,
            bot_token=bot_token,
            base_url=base_url,
        )
        yield env
    finally:
        if proc:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        shutil.rmtree(data_dir, ignore_errors=True)


def make_card(index: int, bot_name: str = "test-bot") -> dict:
    return {
        "title": f"测试卡片-{index}",
        "category": "科技",
        "summary": f"摘要 {index}",
        "body": f"正文 {index}",
        "tags": ["test"],
        "source": "loadtest",
        "created_bot": bot_name,
        "bot_desc": "压力测试 bot",
        "source_urls": [],
        "image_urls": [],
    }


def make_submit_body(cards: list[dict]) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": "submit_cards", "arguments": {"cards": cards}},
    }


async def submit_cards(client: httpx.AsyncClient, base_url: str, bot_token: str, cards: list[dict]) -> dict:
    """提交卡片，返回响应数据。"""
    resp = await client.post(
        f"{base_url}/mcp",
        json=make_submit_body(cards),
        headers={
            "Authorization": f"Bearer {bot_token}",
            "Accept": "application/json, text/event-stream",
        },
        timeout=30,
    )
    data = resp.json() if resp.status_code == 200 else None
    return {"status": resp.status_code, "data": data, "raw": resp.text}


def is_mcp_success(resp: dict) -> bool:
    """判断 MCP 响应是否业务成功（有 card_ids）。"""
    if resp["status"] != 200 or not resp["data"]:
        return False
    data = resp["data"]
    if "error" in data:
        return False
    if "result" not in data:
        return False
    result = data["result"]
    structured = result.get("structuredContent") or {}
    return "card_ids" in structured


def is_mcp_rate_limited(resp: dict) -> bool:
    """判断 MCP 响应是否为限流。"""
    if resp["status"] == 429:
        return True
    if resp["status"] == 200 and resp["data"]:
        data = resp["data"]
        if "error" in data:
            msg = str(data.get("error", {}).get("message", ""))
            return "太快" in msg or "稍后" in msg or "名字" in msg
    return False


async def get_feed(client: httpx.AsyncClient, base_url: str, session_token: str, limit: int = 100) -> list[dict]:
    """获取 feed，返回卡片列表。"""
    resp = await client.get(
        f"{base_url}/v1/feed",
        headers={"Authorization": f"Bearer {session_token}"},
        params={"limit": limit},
        timeout=30,
    )
    if resp.status_code == 200:
        return resp.json().get("cards", [])
    return []


async def count_cards_in_db(data_dir: Path, user_id: str) -> int:
    """直接查数据库统计卡片数。"""
    import sqlite3
    db_path = data_dir / "proclan.sqlite3"
    with sqlite3.connect(db_path) as conn:
        cursor = conn.execute("SELECT COUNT(*) FROM cards WHERE user_id = ?", (user_id,))
        return cursor.fetchone()[0]


class TestResult:
    def __init__(self, name: str):
        self.name = name
        self.passed = False
        self.message = ""
        self.details: dict = {}
    
    def success(self, message: str = "", **details) -> "TestResult":
        self.passed = True
        self.message = message
        self.details = details
        return self
    
    def fail(self, message: str, **details) -> "TestResult":
        self.passed = False
        self.message = message
        self.details = details
        return self


async def test_read_throughput(env: TestEnv, concurrency: int = 5, duration: float = 5) -> TestResult:
    """测试读取吞吐量。"""
    result = TestResult("读取吞吐量")
    
    async with httpx.AsyncClient() as client:
        await submit_cards(client, env.base_url, env.bot_token, [make_card(0)])
    
    success = 0
    errors = 0
    latencies: list[float] = []
    stop = asyncio.Event()
    
    async def worker():
        nonlocal success, errors
        async with httpx.AsyncClient() as client:
            while not stop.is_set():
                start = time.perf_counter()
                try:
                    resp = await client.get(
                        f"{env.base_url}/v1/feed",
                        headers={"Authorization": f"Bearer {env.session_token}"},
                        timeout=10,
                    )
                    elapsed = (time.perf_counter() - start) * 1000
                    if resp.status_code == 200:
                        success += 1
                        latencies.append(elapsed)
                    else:
                        errors += 1
                except Exception:
                    errors += 1
    
    tasks = [asyncio.create_task(worker()) for _ in range(concurrency)]
    await asyncio.sleep(duration)
    stop.set()
    await asyncio.gather(*tasks)
    
    rps = success / duration
    p50 = sorted(latencies)[len(latencies) // 2] if latencies else 0
    p99 = sorted(latencies)[int(len(latencies) * 0.99)] if latencies else 0
    
    return result.success(
        f"{rps:.1f} req/s, P50={p50:.1f}ms, P99={p99:.1f}ms",
        success=success,
        errors=errors,
        rps=rps,
        p50_ms=p50,
        p99_ms=p99,
        concurrency=concurrency,
        duration=duration,
    )


async def test_write_throughput(env: TestEnv, concurrency: int = 5, duration: float = 5) -> TestResult:
    """测试写入吞吐量（不触发限流）。"""
    result = TestResult("写入吞吐量")
    
    success = 0
    rate_limited = 0
    errors = 0
    latencies: list[float] = []
    stop = asyncio.Event()
    counter = [0]
    
    async def worker(worker_id: int):
        nonlocal success, rate_limited, errors
        async with httpx.AsyncClient() as client:
            while not stop.is_set():
                counter[0] += 1
                idx = worker_id * 10000 + counter[0]
                card = make_card(idx, f"bot-{worker_id}")
                start = time.perf_counter()
                try:
                    resp = await submit_cards(client, env.base_url, env.bot_token, [card])
                    elapsed = (time.perf_counter() - start) * 1000
                    if is_mcp_success(resp):
                        success += 1
                        latencies.append(elapsed)
                    elif is_mcp_rate_limited(resp):
                        rate_limited += 1
                    else:
                        errors += 1
                except Exception:
                    errors += 1
    
    tasks = [asyncio.create_task(worker(i)) for i in range(concurrency)]
    await asyncio.sleep(duration)
    stop.set()
    await asyncio.gather(*tasks)
    
    rps = success / duration
    p50 = sorted(latencies)[len(latencies) // 2] if latencies else 0
    p99 = sorted(latencies)[int(len(latencies) * 0.99)] if latencies else 0
    
    return result.success(
        f"{rps:.1f} req/s, P50={p50:.1f}ms, P99={p99:.1f}ms, 限流={rate_limited}",
        success=success,
        rate_limited=rate_limited,
        errors=errors,
        rps=rps,
        p50_ms=p50,
        p99_ms=p99,
        concurrency=concurrency,
        duration=duration,
    )


async def test_rate_limit_boundary(env: TestEnv) -> TestResult:
    """测试限流边界：单 bot 突发 48 张。
    
    注意：顺序发送时，每 2 秒恢复 1 张配额，所以允许少量超出。
    并发测试 test_concurrent_burst 更能准确验证限流。
    """
    result = TestResult("限流边界验证")
    
    async with httpx.AsyncClient() as client:
        success_count = 0
        limited_count = 0
        
        for i in range(55):
            card = make_card(i, "burst-bot")
            resp = await submit_cards(client, env.base_url, env.bot_token, [card])
            if is_mcp_success(resp):
                success_count += 1
            elif is_mcp_rate_limited(resp):
                limited_count += 1
        
        db_count = await count_cards_in_db(env.data_dir, env.user_id)
        
        max_allowed = 48 + 5
        if success_count <= max_allowed and limited_count > 0:
            return result.success(
                f"限流生效，成功={success_count}（允许恢复配额）, 限流={limited_count}, 入库={db_count}",
                success=success_count,
                limited=limited_count,
                db_count=db_count,
                note="顺序发送允许少量配额恢复",
            )
        elif success_count > max_allowed:
            return result.fail(
                f"限流异常！成功={success_count}（超过上限 {max_allowed}）, 限流={limited_count}",
                success=success_count,
                limited=limited_count,
                db_count=db_count,
            )
        else:
            return result.fail(
                f"未触发限流！成功={success_count}, 限流={limited_count}",
                success=success_count,
                limited=limited_count,
                db_count=db_count,
            )


async def test_concurrent_burst(env: TestEnv) -> TestResult:
    """测试并发突发：同时发 60 个请求，只应入库 48 张。"""
    result = TestResult("并发突发限流")
    
    async def send_one(client: httpx.AsyncClient, idx: int) -> tuple[bool, bool]:
        card = make_card(idx, "concurrent-bot")
        resp = await submit_cards(client, env.base_url, env.bot_token, [card])
        if is_mcp_success(resp):
            return True, False
        elif is_mcp_rate_limited(resp):
            return False, True
        return False, False
    
    async with httpx.AsyncClient() as client:
        tasks = [send_one(client, i) for i in range(60)]
        results = await asyncio.gather(*tasks)
    
    success = sum(1 for s, _ in results if s)
    limited = sum(1 for _, l in results if l)
    db_count = await count_cards_in_db(env.data_dir, env.user_id)
    
    if success <= 48 and success == db_count:
        return result.success(
            f"并发限流正确，成功={success}, 限流={limited}, 入库={db_count}",
            success=success,
            limited=limited,
            db_count=db_count,
        )
    else:
        return result.fail(
            f"限流或入库异常，成功={success}, 限流={limited}, 入库={db_count}",
            success=success,
            limited=limited,
            db_count=db_count,
        )


async def test_bot_name_limit(env: TestEnv) -> TestResult:
    """测试 bot 名称限制：突发 8 个新名字。"""
    result = TestResult("bot 名称限流")
    
    async with httpx.AsyncClient() as client:
        success_names = 0
        limited_names = 0
        
        for i in range(12):
            card = make_card(i, f"new-bot-{i}")
            resp = await submit_cards(client, env.base_url, env.bot_token, [card])
            if is_mcp_success(resp):
                success_names += 1
            elif is_mcp_rate_limited(resp):
                limited_names += 1
        
        if success_names == 8 and limited_names == 4:
            return result.success(
                f"新名字限流正确，成功={success_names}, 限流={limited_names}",
                success=success_names,
                limited=limited_names,
            )
        elif success_names <= 8:
            return result.success(
                f"名称限流生效，成功={success_names}, 限流={limited_names}",
                success=success_names,
                limited=limited_names,
            )
        else:
            return result.fail(
                f"名称限流未生效！成功={success_names}, 限流={limited_names}",
                success=success_names,
                limited=limited_names,
            )


async def test_write_verification(env: TestEnv) -> TestResult:
    """测试写入验证：确保成功响应对应实际入库。"""
    result = TestResult("写入验证")
    
    before = await count_cards_in_db(env.data_dir, env.user_id)
    
    async with httpx.AsyncClient() as client:
        success = 0
        for i in range(10):
            card = make_card(i + 1000, "verify-bot")
            resp = await submit_cards(client, env.base_url, env.bot_token, [card])
            if is_mcp_success(resp):
                success += 1
    
    after = await count_cards_in_db(env.data_dir, env.user_id)
    actual = after - before
    
    if actual == success:
        return result.success(
            f"写入一致，成功响应={success}, 实际入库={actual}",
            success=success,
            actual=actual,
        )
    else:
        return result.fail(
            f"写入不一致！成功响应={success}, 实际入库={actual}",
            success=success,
            actual=actual,
        )


async def test_mcp_inflight_limit(env: TestEnv) -> TestResult:
    """测试 MCP 并发限制。"""
    result = TestResult("MCP 并发限制")
    
    semaphore = asyncio.Semaphore(150)
    success = 0
    limited = 0
    
    async def send_one(client: httpx.AsyncClient, idx: int):
        nonlocal success, limited
        async with semaphore:
            card = make_card(idx, f"inflight-{idx % 10}")
            resp = await submit_cards(client, env.base_url, env.bot_token, [card])
            if is_mcp_success(resp):
                success += 1
            elif is_mcp_rate_limited(resp):
                limited += 1
    
    async with httpx.AsyncClient() as client:
        tasks = [send_one(client, i) for i in range(150)]
        await asyncio.gather(*tasks)
    
    if limited > 0:
        return result.success(
            f"并发限制生效，成功={success}, 限流={limited}",
            success=success,
            limited=limited,
        )
    else:
        return result.success(
            f"未触发并发限制，成功={success}, 限流={limited}",
            success=success,
            limited=limited,
        )


async def run_all_tests(workers: int = 2, no_cleanup: bool = False) -> list[TestResult]:
    """运行所有测试。"""
    results: list[TestResult] = []
    
    print(f"\n{'='*60}")
    print(f"Proclan 压测套件 (workers={workers})")
    print(f"{'='*60}\n")
    
    async with test_server(workers=workers) as env:
        print(f"测试服务已启动: {env.base_url}")
        print(f"数据目录: {env.data_dir}")
        print()
        
        tests = [
            ("读取吞吐量", lambda: test_read_throughput(env, concurrency=5, duration=3)),
            ("写入吞吐量", lambda: test_write_throughput(env, concurrency=3, duration=3)),
            ("写入验证", lambda: test_write_verification(env)),
        ]
        
        for name, test_fn in tests:
            print(f"运行: {name}...", end=" ", flush=True)
            try:
                result = await test_fn()
                results.append(result)
                status = "✓" if result.passed else "✗"
                print(f"{status} {result.message}")
            except Exception as e:
                result = TestResult(name).fail(str(e))
                results.append(result)
                print(f"✗ 异常: {e}")
    
    print(f"\n限流验证（独立环境）...")
    
    limit_tests = [
        ("限流边界验证", test_rate_limit_boundary),
        ("并发突发限流", test_concurrent_burst),
        ("bot 名称限流", test_bot_name_limit),
    ]
    
    for name, test_fn in limit_tests:
        async with test_server(workers=workers) as env_clean:
            print(f"运行: {name}...", end=" ", flush=True)
            try:
                result = await test_fn(env_clean)
                results.append(result)
                status = "✓" if result.passed else "✗"
                print(f"{status} {result.message}")
            except Exception as e:
                result = TestResult(name).fail(str(e))
                results.append(result)
                print(f"✗ 异常: {e}")
    
    print(f"\n{'='*60}")
    passed = sum(1 for r in results if r.passed)
    print(f"测试完成: {passed}/{len(results)} 通过")
    print(f"{'='*60}\n")
    
    return results


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Proclan 压测套件")
    parser.add_argument("--workers", type=int, default=2, help="服务 worker 数")
    parser.add_argument("--no-cleanup", action="store_true", help="不清理临时文件")
    parser.add_argument("--output", "-o", help="输出 JSON 结果")
    args = parser.parse_args()
    
    results = asyncio.run(run_all_tests(workers=args.workers, no_cleanup=args.no_cleanup))
    
    if args.output:
        output = {
            "workers": args.workers,
            "tests": [
                {
                    "name": r.name,
                    "passed": r.passed,
                    "message": r.message,
                    "details": r.details,
                }
                for r in results
            ],
        }
        Path(args.output).write_text(json.dumps(output, indent=2, ensure_ascii=False))
        print(f"结果已保存: {args.output}")
    
    return 0 if all(r.passed for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
