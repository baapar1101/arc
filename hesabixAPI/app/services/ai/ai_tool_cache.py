"""
کش نتایج ابزارهای read-only در محدوده یک session.

هدف: جلوگیری از کوئری تکراری DB وقتی agent در یک مکالمه
چند بار ابزار یکسانی را با آرگومان‌های یکسان فراخوانی می‌کند.

ویژگی‌ها:
  - TTL قابل تنظیم (پیش‌فرض: 60 ثانیه)
  - محدودیت تعداد رکورد per session
  - فقط برای توابع is_readonly
  - thread-safe با lock ساده
"""
from __future__ import annotations

import hashlib
import json
import logging
import threading
import time
from typing import Any, Dict, Optional, Tuple

from app.services.ai.ai_constants import TOOL_CACHE_MAX_ENTRIES, TOOL_CACHE_TTL_SEC

logger = logging.getLogger(__name__)

# (business_id, session_id) → {cache_key: (result, expire_at)}
_cache: Dict[Tuple, Dict[str, Tuple[Any, float]]] = {}
_lock = threading.Lock()


def _make_key(function_name: str, arguments: Dict[str, Any]) -> str:
    """ساخت کلید یکتا از نام function و آرگومان‌ها."""
    try:
        canonical = json.dumps(
            {"fn": function_name, "args": arguments},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            default=str,
        )
    except Exception:
        canonical = f"{function_name}:{str(arguments)}"
    return hashlib.sha1(canonical.encode()).hexdigest()  # noqa: S324


def get_cached(
    business_id: int,
    session_id: Optional[int],
    function_name: str,
    arguments: Dict[str, Any],
) -> Tuple[bool, Any]:
    """
    Returns (hit, result).
    اگر رکورد موجود باشد و TTL نگذشته: (True, result)
    در غیر این صورت: (False, None)
    """
    if not session_id:
        return False, None

    scope = (business_id, session_id)
    key = _make_key(function_name, arguments)

    with _lock:
        bucket = _cache.get(scope)
        if not bucket:
            return False, None
        entry = bucket.get(key)
        if not entry:
            return False, None
        result, expire_at = entry
        if time.monotonic() > expire_at:
            del bucket[key]
            return False, None
        return True, result


def set_cached(
    business_id: int,
    session_id: Optional[int],
    function_name: str,
    arguments: Dict[str, Any],
    result: Any,
    ttl: float = TOOL_CACHE_TTL_SEC,
) -> None:
    """ذخیره نتیجه در کش session."""
    if not session_id:
        return

    scope = (business_id, session_id)
    key = _make_key(function_name, arguments)
    expire_at = time.monotonic() + ttl

    with _lock:
        bucket = _cache.setdefault(scope, {})
        # پاک‌سازی منقضی‌شده‌ها وقتی bucket بزرگ شد
        if len(bucket) >= TOOL_CACHE_MAX_ENTRIES:
            now = time.monotonic()
            expired_keys = [k for k, (_, exp) in bucket.items() if exp <= now]
            for k in expired_keys:
                del bucket[k]
            # اگر هنوز پر است، قدیمی‌ترین را حذف کن
            if len(bucket) >= TOOL_CACHE_MAX_ENTRIES:
                oldest = min(bucket.items(), key=lambda x: x[1][1])
                del bucket[oldest[0]]
        bucket[key] = (result, expire_at)


def invalidate_session(business_id: int, session_id: Optional[int]) -> None:
    """پاک‌سازی تمام کش یک session (مثلاً بعد از عملیات نوشتنی)."""
    if not session_id:
        return
    scope = (business_id, session_id)
    with _lock:
        _cache.pop(scope, None)


def cache_stats() -> Dict[str, Any]:
    """آمار کش برای debug."""
    with _lock:
        total_sessions = len(_cache)
        total_entries = sum(len(b) for b in _cache.values())
        now = time.monotonic()
        alive = sum(
            1
            for b in _cache.values()
            for (_, exp) in b.values()
            if exp > now
        )
    return {
        "sessions": total_sessions,
        "total_entries": total_entries,
        "alive_entries": alive,
    }
