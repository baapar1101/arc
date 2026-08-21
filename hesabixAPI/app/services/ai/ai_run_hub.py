"""Hub اجرای زندهٔ ایجنت — مستقل از اتصال SSE کلاینت.

الگوی ChatGPT/Claude/Cursor: producer روی سرور ادامه می‌یابد؛ مرورگر فقط
مشترک رویدادهاست. قطع SSE تولید را متوقف نمی‌کند؛ توقف صریح با cancel است.

بافر رویداد در حافظه و Redis است. اگر run روی worker دیگری زنده باشد،
subscribe ابتدا بافر را replay می‌کند و بعد وضعیت DB را poll می‌کند.
"""
from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Awaitable, Callable, Optional

from app.services.ai.ai_constants import LIVE_RUN_STALE_SEC
from app.services.ai.ai_sse_event_buffer import events_after
from app.services.ai.ai_stream_helpers import SseEventSequencer, format_sse_payload


def replay_buffered_events(
    run_id: str, last_event_id: int
) -> tuple[list[tuple[int, dict[str, Any]]], int, bool]:
    """رویدادهای بافر پس از last_event_id؛ برای worker دیگر بدون hub زنده."""
    events = events_after(run_id, int(last_event_id or 0))
    cursor = int(last_event_id or 0)
    terminal = False
    out: list[tuple[int, dict[str, Any]]] = []
    for event_id, payload in events:
        eid = int(event_id)
        out.append((eid, dict(payload)))
        if eid > cursor:
            cursor = eid
        if _is_terminal_payload(payload):
            terminal = True
            break
    return out, cursor, terminal

logger = logging.getLogger(__name__)

ProducerFn = Callable[["LiveAgentRun"], Awaitable[None]]


@dataclass
class LiveAgentRun:
    run_id: str
    session_id: int
    user_id: int
    sequencer: SseEventSequencer
    subscribers: set[asyncio.Queue] = field(default_factory=set)
    task: Optional[asyncio.Task] = None
    cancel_requested: bool = False
    finished: bool = False
    started_at: float = field(default_factory=time.monotonic)

    def publish(self, data: dict[str, Any]) -> tuple[int, dict[str, Any]]:
        event_id, payload = self.sequencer.push(data)
        for queue in list(self.subscribers):
            try:
                queue.put_nowait((event_id, payload))
            except asyncio.QueueFull:
                logger.warning(
                    "SSE subscriber queue full run_id=%s; client can reconnect",
                    self.run_id,
                )
        return event_id, payload

    def notify_finished(self) -> None:
        self.finished = True
        for queue in list(self.subscribers):
            try:
                queue.put_nowait(None)
            except asyncio.QueueFull:
                pass


class AgentRunHub:
    def __init__(self) -> None:
        self._runs: dict[str, LiveAgentRun] = {}
        self._lock = asyncio.Lock()

    def get(self, run_id: str) -> Optional[LiveAgentRun]:
        return self._runs.get(str(run_id))

    def is_live(self, run_id: Optional[str]) -> bool:
        if not run_id:
            return False
        live = self._runs.get(str(run_id))
        return live is not None and not live.finished

    def request_cancel(self, run_id: str) -> bool:
        live = self.get(run_id)
        if live is None or live.finished:
            return False
        live.cancel_requested = True
        if live.task is not None and not live.task.done():
            live.task.cancel()
        return True

    async def attach_or_start(
        self,
        *,
        run_id: str,
        session_id: int,
        user_id: int,
        producer: ProducerFn,
        start_id: int = 0,
    ) -> LiveAgentRun:
        """اگر producer زنده است همان را برگردان؛ وگرنه یکی بساز و شروع کن."""
        async with self._lock:
            existing = self._runs.get(run_id)
            if existing is not None and not existing.finished:
                return existing
            live = LiveAgentRun(
                run_id=run_id,
                session_id=session_id,
                user_id=user_id,
                sequencer=SseEventSequencer(run_id=run_id, start_id=int(start_id or 0)),
            )
            self._runs[run_id] = live

        async def _runner() -> None:
            try:
                await producer(live)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("agent run producer crashed run_id=%s", run_id)
            finally:
                live.notify_finished()
                await asyncio.sleep(1.5)
                async with self._lock:
                    if self._runs.get(run_id) is live:
                        self._runs.pop(run_id, None)

        live.task = asyncio.create_task(_runner(), name=f"ai-run-{run_id}")
        return live

    async def iter_formatted(
        self,
        run_id: str,
        last_event_id: int = 0,
    ) -> AsyncIterator[str]:
        """بازپخش بافر + رویدادهای زنده. قطع این iterator روی producer اثر ندارد."""
        live = self.get(run_id)
        queue: Optional[asyncio.Queue] = None
        if live is not None:
            queue = asyncio.Queue(maxsize=500)
            live.subscribers.add(queue)

        seen: set[int] = set()
        try:
            for event_id, payload in events_after(run_id, int(last_event_id or 0)):
                seen.add(int(event_id))
                yield format_sse_payload(payload, event_id=event_id)
                if _is_terminal_payload(payload):
                    return

            if live is None or live.finished:
                return

            assert queue is not None
            while True:
                item = await queue.get()
                if item is None:
                    return
                event_id, payload = item
                if int(event_id) <= int(last_event_id or 0) or int(event_id) in seen:
                    if _is_terminal_payload(payload):
                        return
                    continue
                seen.add(int(event_id))
                yield format_sse_payload(payload, event_id=event_id)
                if _is_terminal_payload(payload):
                    return
        finally:
            if live is not None and queue is not None:
                live.subscribers.discard(queue)


def _is_terminal_payload(payload: dict[str, Any]) -> bool:
    if payload.get("done") is True:
        return True
    return payload.get("type") == "error"


def is_running_row_fresh(updated_at: Optional[Any], *, now: Optional[float] = None) -> bool:
    if updated_at is None:
        return False
    try:
        if hasattr(updated_at, "timestamp"):
            from datetime import timezone

            dt = updated_at
            if getattr(dt, "tzinfo", None) is None:
                dt = dt.replace(tzinfo=timezone.utc)
            ts = dt.timestamp()
        else:
            ts = float(updated_at)
    except (TypeError, ValueError, OSError):
        return False
    current = now if now is not None else time.time()
    return (current - ts) < LIVE_RUN_STALE_SEC


agent_run_hub = AgentRunHub()
