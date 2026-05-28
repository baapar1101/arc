"""
سیاست retry برای فراخوانی LLM — خطاهای گذرا و rate limit.
"""
from __future__ import annotations

import asyncio
import logging
import random
from typing import Any, Awaitable, Callable, Optional, Set, TypeVar

from app.core.responses import ApiError

logger = logging.getLogger(__name__)

T = TypeVar("T")

# کدهای ApiError قابل تلاش مجدد
RETRYABLE_API_CODES: Set[str] = frozenset({
    "RATE_LIMIT_EXCEEDED",
    "AI_PROVIDER_ERROR",
})

RETRYABLE_HTTP_STATUS: Set[int] = frozenset({429, 502, 503, 504})

MAX_LLM_RETRIES = 3
BACKOFF_SECONDS = (1.0, 2.5, 5.0)


def is_retryable_error(exc: BaseException) -> bool:
    if isinstance(exc, ApiError):
        code = getattr(exc, "code", None) or ""
        if code in RETRYABLE_API_CODES:
            return True
        status = getattr(exc, "http_status", None)
        if status in RETRYABLE_HTTP_STATUS:
            return True
        return False
    msg = str(exc).lower()
    for token in (
        "rate_limit",
        "rate limit",
        "timeout",
        "timed out",
        "connection reset",
        "connection error",
        "503",
        "502",
        "504",
        "429",
        "overloaded",
        "temporarily unavailable",
    ):
        if token in msg:
            return True
    return False


def _backoff_delay(attempt: int) -> float:
    idx = min(attempt, len(BACKOFF_SECONDS) - 1)
    base = BACKOFF_SECONDS[idx]
    return base + random.uniform(0, base * 0.25)


async def async_retry_llm(
    operation: Callable[[], Awaitable[T]],
    *,
    max_retries: int = MAX_LLM_RETRIES,
    on_retry: Optional[Callable[[int, BaseException], None]] = None,
) -> T:
    last_exc: Optional[BaseException] = None
    for attempt in range(max_retries):
        try:
            return await operation()
        except Exception as exc:
            last_exc = exc
            if attempt >= max_retries - 1 or not is_retryable_error(exc):
                raise
            if on_retry:
                on_retry(attempt + 1, exc)
            delay = _backoff_delay(attempt)
            logger.warning(
                "LLM retry attempt %s/%s after %s: %s",
                attempt + 1,
                max_retries - 1,
                type(exc).__name__,
                exc,
            )
            await asyncio.sleep(delay)
    assert last_exc is not None
    raise last_exc


def sync_retry_llm(
    operation: Callable[[], T],
    *,
    max_retries: int = MAX_LLM_RETRIES,
    on_retry: Optional[Callable[[int, BaseException], None]] = None,
) -> T:
    import time

    last_exc: Optional[BaseException] = None
    for attempt in range(max_retries):
        try:
            return operation()
        except Exception as exc:
            last_exc = exc
            if attempt >= max_retries - 1 or not is_retryable_error(exc):
                raise
            if on_retry:
                on_retry(attempt + 1, exc)
            delay = _backoff_delay(attempt)
            logger.warning(
                "LLM sync retry attempt %s/%s: %s",
                attempt + 1,
                max_retries - 1,
                exc,
            )
            time.sleep(delay)
    assert last_exc is not None
    raise last_exc
