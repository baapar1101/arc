"""Hub اجرای زنده — قطع subscriber نباید producer را بکشد."""
from __future__ import annotations

import asyncio

import pytest

from app.services.ai.ai_run_hub import AgentRunHub
from app.services.ai.ai_sse_event_buffer import drop_sse_events, events_after
from app.services.ai.ai_stream_helpers import SseEventSequencer


@pytest.mark.asyncio
async def test_subscriber_cancel_does_not_stop_producer():
    drop_sse_events("hubrun000000001")
    hub = AgentRunHub()
    started = asyncio.Event()
    finished = asyncio.Event()

    async def producer(live):
        started.set()
        live.publish({"type": "status", "phase": "thinking", "done": False})
        await asyncio.sleep(0.15)
        live.publish({"type": "status", "phase": "writing", "done": False})
        live.publish({"content": "", "done": True})
        finished.set()

    await hub.attach_or_start(
        run_id="hubrun000000001",
        session_id=1,
        user_id=1,
        producer=producer,
    )
    await started.wait()

    async def take_two():
        n = 0
        async for _ in hub.iter_formatted("hubrun000000001", 0):
            n += 1
            if n >= 1:
                break

    await take_two()
    assert hub.is_live("hubrun000000001")
    await asyncio.wait_for(finished.wait(), timeout=1.0)
    drop_sse_events("hubrun000000001")


@pytest.mark.asyncio
async def test_cancelling_request_task_does_not_stop_producer():
    drop_sse_events("hubrun000000005")
    hub = AgentRunHub()
    hub.start_supervisor()
    started = asyncio.Event()
    finished = asyncio.Event()

    async def producer(live):
        started.set()
        await asyncio.sleep(0.2)
        live.publish({"content": "ok", "done": True})
        finished.set()

    async def fake_sse_request():
        await hub.attach_or_start(
            run_id="hubrun000000005",
            session_id=1,
            user_id=1,
            producer=producer,
        )
        async for _ in hub.iter_formatted("hubrun000000005", 0):
            break

    request_task = asyncio.create_task(fake_sse_request())
    await started.wait()
    request_task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await request_task
    assert hub.is_live("hubrun000000005")
    await asyncio.wait_for(finished.wait(), timeout=1.0)
    drop_sse_events("hubrun000000005")


@pytest.mark.asyncio
async def test_late_subscriber_replays_buffered_events():
    drop_sse_events("hubrun000000002")
    hub = AgentRunHub()

    async def producer(live):
        live.publish({"type": "status", "phase": "thinking", "done": False})
        live.publish({"type": "status", "phase": "writing", "done": False})
        live.publish({"content": "hi", "done": True})

    await hub.attach_or_start(
        run_id="hubrun000000002",
        session_id=1,
        user_id=1,
        producer=producer,
    )
    await asyncio.sleep(0.05)
    payloads = []
    async for raw in hub.iter_formatted("hubrun000000002", 0):
        payloads.append(raw)
        if "\"done\": true" in raw or '"done":true' in raw:
            break
    assert any("thinking" in p for p in payloads)
    drop_sse_events("hubrun000000002")


def test_heartbeat_not_buffered():
    drop_sse_events("hubrun000000003")
    seq = SseEventSequencer(run_id="hubrun000000003", start_id=0)
    seq.format({"type": "status", "phase": "thinking", "done": False})
    seq.format({"type": "heartbeat", "elapsed_ms": 3, "done": False})
    seq.format({"type": "status", "phase": "writing", "done": False})
    replayed = events_after("hubrun000000003", 0)
    types = [p["type"] for _, p in replayed]
    assert "heartbeat" not in types
    assert types == ["status", "status"]
    drop_sse_events("hubrun000000003")


@pytest.mark.asyncio
async def test_request_cancel_stops_producer():
    drop_sse_events("hubrun000000004")
    hub = AgentRunHub()
    cancelled = asyncio.Event()

    async def producer(live):
        live.publish({"type": "status", "phase": "thinking", "done": False})
        try:
            await asyncio.sleep(5)
        except asyncio.CancelledError:
            cancelled.set()
            raise

    await hub.attach_or_start(
        run_id="hubrun000000004",
        session_id=1,
        user_id=1,
        producer=producer,
    )
    await asyncio.sleep(0.02)
    assert hub.request_cancel("hubrun000000004") is True
    await asyncio.wait_for(cancelled.wait(), timeout=1.0)
    drop_sse_events("hubrun000000004")
