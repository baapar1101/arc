"""بافر حلقوی درون‌پردازه‌ای رویدادهای SSE برای reconnect کوتاه‌عمر.

بدون Redis / AGT-02 این بافر فقط تا TTL روی همان worker زنده است.
ادامهٔ واقعی اجرا از checkpoint جدول ai_agent_runs است.
"""
from __future__ import annotations

import threading
import time
from collections import deque
from typing import Any

from app.services.ai.ai_constants import (
    SSE_EVENT_BUFFER_MAX,
    SSE_EVENT_BUFFER_TTL_SEC,
)

_lock = threading.Lock()
_buffers: dict[str, "_RunBuffer"] = {}


class _RunBuffer:
    __slots__ = ("events", "expires_at")

    def __init__(self) -> None:
        self.events: deque[tuple[int, dict[str, Any]]] = deque(
            maxlen=SSE_EVENT_BUFFER_MAX
        )
        self.expires_at = time.monotonic() + SSE_EVENT_BUFFER_TTL_SEC

    def touch(self) -> None:
        self.expires_at = time.monotonic() + SSE_EVENT_BUFFER_TTL_SEC


def _gc_locked(now: float) -> None:
    stale = [key for key, buf in _buffers.items() if buf.expires_at <= now]
    for key in stale:
        _buffers.pop(key, None)


def append_sse_event(run_id: str, event_id: int, data: dict[str, Any]) -> None:
    if not run_id:
        return
    with _lock:
        _gc_locked(time.monotonic())
        buf = _buffers.get(run_id)
        if buf is None:
            buf = _RunBuffer()
            _buffers[run_id] = buf
        buf.events.append((int(event_id), dict(data)))
        buf.touch()


def events_after(run_id: str, last_event_id: int) -> list[tuple[int, dict[str, Any]]]:
    if not run_id:
        return []
    with _lock:
        _gc_locked(time.monotonic())
        buf = _buffers.get(run_id)
        if buf is None:
            return []
        buf.touch()
        return [
            (eid, dict(payload))
            for eid, payload in buf.events
            if eid > int(last_event_id)
        ]


def drop_sse_events(run_id: str) -> None:
    if not run_id:
        return
    with _lock:
        _buffers.pop(run_id, None)


def buffered_run_ids() -> frozenset[str]:
    with _lock:
        _gc_locked(time.monotonic())
        return frozenset(_buffers)
