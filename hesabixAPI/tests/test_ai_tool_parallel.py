"""سقف موازی ابزارهای read و سریال بودن write."""
from __future__ import annotations

import asyncio

from app.services.ai.ai_tool_parallel import (
    partition_tool_batches,
    run_tool_calls_partitioned,
)


def test_partition_read_then_write_then_read():
    calls = [
        {"name": "search_invoices"},
        {"name": "get_sales_report"},
        {"name": "create_invoice"},
        {"name": "get_invoice_details"},
    ]
    writes = {"create_invoice"}
    batches = partition_tool_batches(
        calls, lambda c: c["name"] in writes
    )
    assert batches == [
        ("read", [0, 1]),
        ("write", [2]),
        ("read", [3]),
    ]


def test_all_reads_one_batch():
    calls = [{"name": "a"}, {"name": "b"}, {"name": "c"}]
    batches = partition_tool_batches(calls, lambda _c: False)
    assert batches == [("read", [0, 1, 2])]


def test_all_writes_serial_batches():
    calls = [{"name": "w1"}, {"name": "w2"}]
    batches = partition_tool_batches(calls, lambda _c: True)
    assert batches == [("write", [0]), ("write", [1])]


async def test_parallel_reads_capped_and_order_preserved():
    current = 0
    peak = 0
    lock = asyncio.Lock()

    async def call_fn(call, index):
        nonlocal current, peak
        async with lock:
            current += 1
            peak = max(peak, current)
        await asyncio.sleep(0.02)
        async with lock:
            current -= 1
        return call["name"], index

    calls = [{"name": f"r{i}"} for i in range(6)]
    results = await run_tool_calls_partitioned(
        calls,
        call_fn,
        is_write=lambda _c: False,
        max_parallel_reads=2,
    )
    assert [r[1] for r in results] == list(range(6))
    assert peak <= 2


async def test_write_waits_for_preceding_reads():
    order: list[str] = []

    async def call_fn(call, index):
        order.append(f"start:{call['name']}")
        await asyncio.sleep(0.01)
        order.append(f"end:{call['name']}")
        return call["name"]

    calls = [
        {"name": "read_a"},
        {"name": "write_x"},
        {"name": "read_b"},
    ]
    results = await run_tool_calls_partitioned(
        calls,
        call_fn,
        is_write=lambda c: c["name"].startswith("write"),
        max_parallel_reads=4,
    )
    assert results == ["read_a", "write_x", "read_b"]
    assert order.index("end:read_a") < order.index("start:write_x")
    assert order.index("end:write_x") < order.index("start:read_b")


def test_parallel_round_stats_counts_reads_and_writes():
    from app.services.ai.ai_tool_parallel import parallel_round_stats

    calls = [
        {"name": "search_invoices"},
        {"name": "get_sales_report"},
        {"name": "create_invoice"},
        {"name": "get_invoice_details"},
    ]
    stats = parallel_round_stats(calls, lambda c: c["name"] == "create_invoice")
    assert stats["tool_calls_in_round"] == 4
    assert stats["write_count"] == 1
    assert stats["parallel_read_count"] == 2
    assert stats["max_read_batch"] == 2
