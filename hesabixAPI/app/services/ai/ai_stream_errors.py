"""طبقه‌بندی خطای استریم AI برای راهنمایی کاربر (کد پایدار + متن فارسی)."""
from __future__ import annotations

from typing import Any, Optional

from app.core.responses import ApiError
from app.services.ai.ai_retry_policy import is_retryable_error

STREAM_ERROR_STALL = "STREAM_STALL"
STREAM_ERROR_EMPTY = "EMPTY_STREAM"
STREAM_ERROR_PROVIDER_TIMEOUT = "PROVIDER_TIMEOUT"
STREAM_ERROR_PROVIDER_OVERLOADED = "PROVIDER_OVERLOADED"
STREAM_ERROR_RATE_LIMIT = "RATE_LIMIT"
STREAM_ERROR_NETWORK = "NETWORK"
STREAM_ERROR_CREDIT = "CREDIT"
STREAM_ERROR_CANCELLED = "RUN_CANCELLED"
STREAM_ERROR_IDLE = "RUN_IDLE"
STREAM_ERROR_INTERNAL = "INTERNAL"

_FA: dict[str, str] = {
    STREAM_ERROR_STALL: "ارتباط لحظه‌ای قطع شد. پاسخ تا اینجا ذخیره شده است.",
    STREAM_ERROR_EMPTY: "پاسخ کامل نرسید؛ اتصال قبل از اتمام بسته شد.",
    STREAM_ERROR_PROVIDER_TIMEOUT: "مدل پاسخ نداد. می‌توانید از همان نقطه ادامه دهید.",
    STREAM_ERROR_PROVIDER_OVERLOADED: "سرویس مدل موقتاً شلوغ است. کمی بعد دوباره تلاش کنید.",
    STREAM_ERROR_RATE_LIMIT: "محدودیت تعداد درخواست. کمی صبر کنید و دوباره بفرستید.",
    STREAM_ERROR_NETWORK: "ارتباط با سرویس برقرار نشد.",
    STREAM_ERROR_CREDIT: "امکان ارسال نیست؛ اعتبار یا دسترسی را بررسی کنید.",
    STREAM_ERROR_CANCELLED: "تولید پاسخ متوقف شد.",
    STREAM_ERROR_IDLE: "تحلیل ناتمام ماند. می‌توانید از همان نقطه ادامه دهید.",
    STREAM_ERROR_INTERNAL: "خطای داخلی در تولید پاسخ. می‌توانید دوباره تلاش کنید.",
}

_CREDIT_CODES = frozenset({
    "AI_QUOTA_EXCEEDED",
    "INSUFFICIENT_CREDIT",
    "AI_UNAVAILABLE",
    "SUBSCRIPTION_REQUIRED",
})


def message_fa_for_code(code: str) -> str:
    return _FA.get(code, _FA[STREAM_ERROR_INTERNAL])


def classify_stream_exception(exc: BaseException) -> str:
    if isinstance(exc, asyncio_cancelled()):
        return STREAM_ERROR_CANCELLED
    if isinstance(exc, ApiError):
        code = (getattr(exc, "code", None) or "").upper()
        if code in _CREDIT_CODES:
            return STREAM_ERROR_CREDIT
        if code in {"RATE_LIMIT_EXCEEDED"}:
            return STREAM_ERROR_RATE_LIMIT
        if code in {"AI_PROVIDER_ERROR"}:
            return STREAM_ERROR_PROVIDER_OVERLOADED
        status = getattr(exc, "http_status", None)
        if status in (429,):
            return STREAM_ERROR_RATE_LIMIT
        if status in (502, 503, 504):
            return STREAM_ERROR_PROVIDER_OVERLOADED
    text = str(exc).lower()
    if "timeout" in text or "timed out" in text:
        return STREAM_ERROR_PROVIDER_TIMEOUT
    if "overloaded" in text or "temporarily unavailable" in text:
        return STREAM_ERROR_PROVIDER_OVERLOADED
    if "rate limit" in text or "rate_limit" in text or "429" in text:
        return STREAM_ERROR_RATE_LIMIT
    if "connection" in text or "network" in text:
        return STREAM_ERROR_NETWORK
    if is_retryable_error(exc):
        return STREAM_ERROR_NETWORK
    return STREAM_ERROR_INTERNAL


def asyncio_cancelled() -> type[BaseException]:
    import asyncio

    return asyncio.CancelledError


def suggested_action_for(code: str, *, can_continue: bool) -> str:
    if code == STREAM_ERROR_CANCELLED:
        return "dismiss"
    if code == STREAM_ERROR_CREDIT:
        return "dismiss"
    if can_continue or code in {
        STREAM_ERROR_IDLE,
        STREAM_ERROR_STALL,
        STREAM_ERROR_EMPTY,
        STREAM_ERROR_PROVIDER_TIMEOUT,
    }:
        return "continue" if can_continue else "reconnect"
    if code in {STREAM_ERROR_NETWORK, STREAM_ERROR_PROVIDER_OVERLOADED, STREAM_ERROR_RATE_LIMIT}:
        return "retry"
    return "retry"


def stream_error_payload(
    exc: Optional[BaseException] = None,
    *,
    code: Optional[str] = None,
    run_id: Optional[str] = None,
    can_continue: bool = False,
    extra: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    resolved = code or (classify_stream_exception(exc) if exc is not None else STREAM_ERROR_INTERNAL)
    recoverable = resolved not in {STREAM_ERROR_CANCELLED, STREAM_ERROR_CREDIT}
    payload: dict[str, Any] = {
        "type": "error",
        "error_code": resolved,
        "error": message_fa_for_code(resolved),
        "recoverable": recoverable,
        "suggested_action": suggested_action_for(resolved, can_continue=can_continue),
        "done": True,
        "can_continue": bool(can_continue),
        "run_id": run_id,
    }
    if extra:
        payload.update(extra)
    return payload
