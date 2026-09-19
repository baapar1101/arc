"""تست پاسخ قطعی از شواهد ابزار (بدون LLM)."""
from __future__ import annotations

from app.services.ai.ai_answer_from_evidence import (
    build_deterministic_answer_from_trace,
    redact_final_answer_from_reasoning_trace,
)


def test_deterministic_answer_from_explored_like_session_751():
    trace = [
        {
            "kind": "narrative",
            "body_markdown": "در حال دریافت گزارش فروش برای دورهٔ آخرین ۳ ماه هستیم.",
        },
        {
            "kind": "explored",
            "body_markdown": (
                "#### ✓ گزارش فروش\n"
                "**11** مورد یافت شد.\n\n"
                "- بستنی شکلاتی\n"
                "- سفارشی سازی موردی"
            ),
        },
        {
            "kind": "thought",
            "body_markdown": "### یافته‌های مهم\n1. گزارش فروش: **11** مورد",
        },
    ]
    answer = build_deterministic_answer_from_trace(
        trace,
        user_query="گزارشی از فروش ۳ ماه گذشته بهم بده",
        budget_note=True,
    )
    assert "11" in answer
    assert "زمان مجاز" not in answer
    assert "داده‌های جمع‌آوری‌شده" in answer
    assert "در حال دریافت" not in answer


def test_prefers_composed_narrative_over_explored():
    trace = [
        {
            "kind": "explored",
            "body_markdown": "#### ✓ گزارش فروش\n**11** مورد",
        },
        {
            "kind": "narrative",
            "body_markdown": (
                "**خلاصهٔ فروش ۳ ماه اخیر**\n\n"
                "- تعداد فاکتور: ۱۱\n"
                "- مجموع: ۴۱۴ میلیون ریال"
            ),
        },
    ]
    answer = build_deterministic_answer_from_trace(trace)
    assert "خلاصهٔ فروش" in answer
    assert "۴۱۴" in answer


def test_empty_when_only_status_narrative():
    trace = [
        {"kind": "narrative", "body_markdown": "در حال جستجو..."},
    ]
    assert build_deterministic_answer_from_trace(trace) == ""


def test_redact_final_answer_from_reasoning_trace():
    final = (
        "**خلاصهٔ فروش ۳ ماه اخیر**\n\n"
        "- تعداد فاکتور: ۱۱\n"
        "- مجموع: ۴۱۴ میلیون ریال"
    )
    trace = [
        {"kind": "narrative", "body_markdown": final, "visibility": "user"},
        {"kind": "explored", "body_markdown": "#### raw"},
    ]
    redact_final_answer_from_reasoning_trace(trace, final)
    assert trace[0].get("body_markdown") in (None, "")
    assert trace[0].get("visibility") == "internal"
    assert trace[1].get("body_markdown") == "#### raw"
