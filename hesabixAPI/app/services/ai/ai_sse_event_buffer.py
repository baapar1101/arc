"""بافر حلقوی رویدادهای SSE برای reconnect کوتاه‌عمر.

حافظهٔ همین فرآیند همیشه نوشته می‌شود. اگر Redis فعال باشد همان رویدادها
با TTL مشترک هم آنجا می‌روند تا worker دیگر بتواند replay کند.
ادامهٔ واقعی اجرا از checkpoint جدول ai_agent_runs است.
"""
from __future__ import annotations

import json
import logging
import threading
import time
from collections import deque
from typing import Any

from app.core.json_safe import json_dumps_safe
from app.services.ai.ai_constants import (
    SSE_EVENT_BUFFER_MAX,
    SSE_EVENT_BUFFER_TTL_SEC,
    SSE_EVENT_REDIS_KEY_PREFIX,
)

logger = logging.getLogger(__name__)

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


def _redis_key(run_id: str) -> str:
    return f"{SSE_EVENT_REDIS_KEY_PREFIX}{run_id}"


def _redis_client():
    try:
        from app.core.cache import get_redis_client

        return get_redis_client()
    except Exception:
        return None


def _append_redis(run_id: str, event_id: int, data: dict[str, Any]) -> None:
    client = _redis_client()
    if client is None:
        return
    try:
        payload = json_dumps_safe({"id": int(event_id), "data": data})
        key = _redis_key(run_id)
        pipe = client.pipeline(True)
        pipe.rpush(key, payload)
        pipe.ltrim(key, -SSE_EVENT_BUFFER_MAX, -1)
        pipe.expire(key, int(SSE_EVENT_BUFFER_TTL_SEC))
        pipe.execute()
    except Exception as exc:
        logger.debug("SSE redis append skipped run=%s: %s", run_id, exc)


def _events_after_redis(run_id: str, last_event_id: int) -> list[tuple[int, dict[str, Any]]]:
    client = _redis_client()
    if client is None:
        return []
    try:
        raw_items = client.lrange(_redis_key(run_id), 0, -1) or []
    except Exception as exc:
        logger.debug("SSE redis read skipped run=%s: %s", run_id, exc)
        return []
    out: list[tuple[int, dict[str, Any]]] = []
    for raw in raw_items:
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except (TypeError, ValueError, json.JSONDecodeError):
            continue
        if not isinstance(parsed, dict):
            continue
        try:
            eid = int(parsed.get("id") or 0)
        except (TypeError, ValueError):
            continue
        if eid <= int(last_event_id):
            continue
        payload = parsed.get("data")
        if isinstance(payload, dict):
            out.append((eid, dict(payload)))
    return out


def _drop_redis(run_id: str) -> None:
    client = _redis_client()
    if client is None:
        return
    try:
        client.delete(_redis_key(run_id))
    except Exception:
        return


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
    _append_redis(run_id, event_id, data)


def events_after(run_id: str, last_event_id: int) -> list[tuple[int, dict[str, Any]]]:
    if not run_id:
        return []
    with _lock:
        _gc_locked(time.monotonic())
        buf = _buffers.get(run_id)
        if buf is not None:
            buf.touch()
            local = [
                (eid, dict(payload))
                for eid, payload in buf.events
                if eid > int(last_event_id)
            ]
            if local:
                return local
    return _events_after_redis(run_id, last_event_id)


def drop_sse_events(run_id: str) -> None:
    if not run_id:
        return
    with _lock:
        _buffers.pop(run_id, None)
    _drop_redis(run_id)


def buffered_run_ids() -> frozenset[str]:
    with _lock:
        _gc_locked(time.monotonic())
        return frozenset(_buffers)
