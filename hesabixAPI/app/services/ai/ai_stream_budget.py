"""
محدودیت wall-clock روی stream LLM (الگوی Cursor/Anthropic).

سقف زمان فقط بین نوبت‌های agent کافی نیست؛ درخواست در حال stream نیز باید
قابل لغو باشد تا UI در سکوت طولانی گیر نکند.
"""
from __future__ import annotations

import asyncio
from typing import AsyncIterator, TypeVar

from app.services.ai.ai_budget import AgentBudget, STOP_REASON_WALL_CLOCK

T = TypeVar("T")


class WallClockExceeded(Exception):
    """زمان مجاز تحلیل در میانهٔ stream تمام شد."""

    def __init__(self, message_fa: str, *, reason: str = STOP_REASON_WALL_CLOCK) -> None:
        self.message_fa = message_fa
        self.reason = reason
        super().__init__(message_fa)


def remaining_wall_clock_sec(budget: AgentBudget) -> float | None:
    if budget.wall_clock_sec is None:
        return None
    return max(0.0, budget.wall_clock_sec - budget.elapsed_sec)


async def iter_stream_with_wall_clock(
    source: AsyncIterator[T],
    budget: AgentBudget,
) -> AsyncIterator[T]:
    """هر chunk بعدی را با timeout باقی‌ماندهٔ wall-clock می‌خواند."""
    aiter = source.__aiter__()
    while True:
        remaining = remaining_wall_clock_sec(budget)
        if remaining is not None and remaining <= 0:
            raise WallClockExceeded(
                "زمان مجاز برای تحلیل این پاسخ به پایان رسید؛ "
                "با داده‌های جمع‌آوری‌شده ادامه می‌دهم."
            )
        try:
            if remaining is not None:
                item = await asyncio.wait_for(aiter.__anext__(), timeout=remaining)
            else:
                item = await aiter.__anext__()
        except StopAsyncIteration:
            break
        except asyncio.TimeoutError as exc:
            raise WallClockExceeded(
                "زمان مجاز برای تحلیل این پاسخ به پایان رسید؛ "
                "با داده‌های جمع‌آوری‌شده ادامه می‌دهم."
            ) from exc
        yield item
