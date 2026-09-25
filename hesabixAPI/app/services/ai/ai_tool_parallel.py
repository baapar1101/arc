"""اجرای ابزارهای یک نوبت با سقف موازی برای read و سریال برای write.

ترتیب مدل حفظ می‌شود: دسته‌های متوالی read موازی‌اند (با semaphore)،
هر write یک سد است و تنها اجرا می‌شود.
"""
from __future__ import annotations

import asyncio
from typing import Any, Awaitable, Callable, Sequence

from app.services.ai.ai_constants import MAX_PARALLEL_READ_TOOLS

CallFn = Callable[[dict[str, Any], int], Awaitable[Any]]
IsWriteFn = Callable[[dict[str, Any]], bool]


def partition_tool_batches(
    calls: Sequence[dict[str, Any]],
    is_write: IsWriteFn,
) -> list[tuple[str, list[int]]]:
    """دسته‌بندی پایدار: ('read', [i, j, ...]) یا ('write', [i])."""
    batches: list[tuple[str, list[int]]] = []
    current_reads: list[int] = []

    def flush_reads() -> None:
        nonlocal current_reads
        if current_reads:
            batches.append(("read", current_reads))
            current_reads = []

    for index, call in enumerate(calls):
        if is_write(call):
            flush_reads()
            batches.append(("write", [index]))
        else:
            current_reads.append(index)
    flush_reads()
    return batches


def parallel_round_stats(
    calls: Sequence[dict[str, Any]],
    is_write: IsWriteFn,
) -> dict[str, int]:
    """شمارش ابزارهای یک نوبت برای متریک TOOL-06."""
    write_count = 0
    parallel_read_count = 0
    max_read_batch = 0
    for kind, indices in partition_tool_batches(calls, is_write):
        if kind == "write":
            write_count += len(indices)
            continue
        max_read_batch = max(max_read_batch, len(indices))
        if len(indices) > 1:
            parallel_read_count += len(indices)
    return {
        "tool_calls_in_round": len(calls),
        "write_count": write_count,
        "max_read_batch": max_read_batch,
        "parallel_read_count": parallel_read_count,
    }


async def run_tool_calls_partitioned(
    calls: Sequence[dict[str, Any]],
    call_fn: CallFn,
    *,
    is_write: IsWriteFn,
    max_parallel_reads: int = MAX_PARALLEL_READ_TOOLS,
) -> list[Any]:
    """اجرای call_fn روی هر ابزار با سقف موازی read و write سریال."""
    results: list[Any] = [None] * len(calls)
    limit = max(1, int(max_parallel_reads))
    semaphore = asyncio.Semaphore(limit)

    async def limited(index: int) -> Any:
        async with semaphore:
            return await call_fn(calls[index], index)

    for kind, indices in partition_tool_batches(calls, is_write):
        if kind == "write":
            for index in indices:
                results[index] = await call_fn(calls[index], index)
            continue
        gathered = await asyncio.gather(*(limited(i) for i in indices))
        for index, value in zip(indices, gathered):
            results[index] = value
    return results
