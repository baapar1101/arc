"""
بافر رویدادهای SSE مربوط به todoهای جلسه — بین handler ابزار و حلقهٔ استریم.
"""
from __future__ import annotations

from contextvars import ContextVar
from typing import Any, Dict, List

_pending_sse: ContextVar[List[Dict[str, Any]]] = ContextVar("session_todo_sse", default=[])


def reset_session_todo_sse_buffer() -> None:
    _pending_sse.set([])


def emit_session_todo_sse(event: Dict[str, Any]) -> None:
    buf = list(_pending_sse.get())
    buf.append(dict(event))
    _pending_sse.set(buf)


def drain_session_todo_sse() -> List[Dict[str, Any]]:
    events = list(_pending_sse.get())
    _pending_sse.set([])
    return events
