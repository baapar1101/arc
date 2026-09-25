"""تست wall-clock روی stream LLM."""
from __future__ import annotations

import asyncio
import time

import pytest

from app.services.ai.ai_budget import AgentBudget, STOP_REASON_WALL_CLOCK
from app.services.ai.ai_stream_budget import WallClockExceeded, iter_stream_with_wall_clock


async def _slow_stream():
    yield "a"
    await asyncio.sleep(0.05)
    yield "b"


async def _very_slow_stream():
    yield "a"
    await asyncio.sleep(2.0)
    yield "b"


@pytest.mark.asyncio
async def test_stream_completes_within_wall_clock():
    budget = AgentBudget(wall_clock_sec=5.0)
    out = []
    async for item in iter_stream_with_wall_clock(_slow_stream(), budget):
        out.append(item)
    assert out == ["a", "b"]


@pytest.mark.asyncio
async def test_stream_raises_when_wall_clock_exceeded():
    budget = AgentBudget(wall_clock_sec=0.05)
    budget.started_at = time.monotonic() - 0.1
    with pytest.raises(WallClockExceeded) as exc:
        async for _ in iter_stream_with_wall_clock(_very_slow_stream(), budget):
            pass
    assert exc.value.reason == STOP_REASON_WALL_CLOCK
