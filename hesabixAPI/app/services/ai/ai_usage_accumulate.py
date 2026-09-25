"""
جمع‌آوری usage چند نوبت LLM برای صورتحساب دقیق.

در حلقهٔ agent هر نوبت جداگانه به provider می‌زند؛ اگر فقط usage آخرین
پاسخ شارژ شود، توکن‌های نوبت‌های میانی روی حساب آروان می‌سوزد ولی از
سهمیه/کیف پول کسب‌وکار کم نمی‌شود.
"""
from __future__ import annotations

from typing import Any, Dict, Optional

_USAGE_INT_KEYS = (
    "input_tokens",
    "output_tokens",
    "total_tokens",
    "cached_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
)


def empty_usage() -> Dict[str, int]:
    return {key: 0 for key in _USAGE_INT_KEYS}


def _as_int(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError):
        return 0


def normalize_usage(usage: Optional[Dict[str, Any]]) -> Optional[Dict[str, int]]:
    if not usage or not isinstance(usage, dict):
        return None
    normalized = empty_usage()
    for key in _USAGE_INT_KEYS:
        normalized[key] = _as_int(usage.get(key))
    if normalized["total_tokens"] <= 0:
        normalized["total_tokens"] = normalized["input_tokens"] + normalized["output_tokens"]
    if (
        normalized["input_tokens"] <= 0
        and normalized["output_tokens"] <= 0
        and normalized["total_tokens"] <= 0
    ):
        return None
    return normalized


def merge_usage(
    accumulated: Optional[Dict[str, Any]],
    addition: Optional[Dict[str, Any]],
) -> Dict[str, int]:
    """جمع دو usage؛ کلیدهای ناشناختهٔ عددی هم در صورت وجود جمع می‌شوند."""
    base = normalize_usage(accumulated) or empty_usage()
    extra = normalize_usage(addition)
    if not extra:
        return base
    merged = dict(base)
    for key in _USAGE_INT_KEYS:
        merged[key] = _as_int(base.get(key)) + _as_int(extra.get(key))
    if merged["total_tokens"] < merged["input_tokens"] + merged["output_tokens"]:
        merged["total_tokens"] = merged["input_tokens"] + merged["output_tokens"]
    return merged


def estimate_chat_tokens(user_text: str, *, minimum: int = 2000) -> int:
    """تخمین محافظه‌کارانه برای پیش‌چک؛ agent معمولاً چند نوبت می‌زند."""
    text_est = max(0, len(user_text or "") * 2)
    return max(minimum, text_est)


def heuristic_chat_title(user_message: str, *, max_len: int = 60) -> Optional[str]:
    """عنوان بدون LLM؛ برای جلوگیری از مصرف provider وقتی سهمیه نیست."""
    text = (user_message or "").strip().replace("\n", " ")
    if not text:
        return None
    return text[:max_len]
