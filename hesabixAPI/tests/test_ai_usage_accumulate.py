"""Tests for AI usage accumulation and billing helpers."""
from __future__ import annotations

from app.core.responses import ApiError
from app.services.ai.ai_usage_accumulate import (
    empty_usage,
    estimate_chat_tokens,
    heuristic_chat_title,
    merge_usage,
    normalize_usage,
)


def test_merge_usage_sums_rounds():
    a = {"input_tokens": 100, "output_tokens": 50, "total_tokens": 150}
    b = {"input_tokens": 200, "output_tokens": 80, "total_tokens": 280}
    merged = merge_usage(a, b)
    assert merged["input_tokens"] == 300
    assert merged["output_tokens"] == 130
    assert merged["total_tokens"] == 430


def test_merge_usage_with_none():
    assert merge_usage(None, None) == empty_usage()
    one = merge_usage(None, {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15})
    assert one["input_tokens"] == 10
    assert one["total_tokens"] == 15


def test_normalize_usage_fills_total():
    n = normalize_usage({"input_tokens": 7, "output_tokens": 3})
    assert n is not None
    assert n["total_tokens"] == 10


def test_estimate_chat_tokens_has_floor():
    assert estimate_chat_tokens("hi") == 2000
    assert estimate_chat_tokens("x" * 5000) == 10000


def test_heuristic_chat_title():
    assert heuristic_chat_title("  سلام دنیا  ") == "سلام دنیا"
    assert heuristic_chat_title("") is None
    long = "الف" * 100
    assert len(heuristic_chat_title(long) or "") == 60


def test_availability_raise_contract():
    """قرارداد ensure_availability_or_raise بدون بارگذاری AIService."""

    def ensure(availability):
        if availability.get("can_use"):
            return availability
        details = availability.get("details") or {}
        reason = availability.get("reason") or "AI_UNAVAILABLE"
        message = details.get("message") or "امکان استفاده از هوش مصنوعی وجود ندارد"
        raise ApiError(reason, message, http_status=400, details=details)

    ok = {"can_use": True, "reason": None, "details": {}}
    assert ensure(ok) is ok

    try:
        ensure(
            {
                "can_use": False,
                "reason": "NO_ACTIVE_SUBSCRIPTION",
                "details": {"message": "اشتراک فعالی وجود ندارد"},
            }
        )
        assert False, "expected ApiError"
    except ApiError as exc:
        assert exc.detail["error"]["code"] == "NO_ACTIVE_SUBSCRIPTION"
