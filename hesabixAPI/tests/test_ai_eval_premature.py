"""تست متریک premature-final (Phase 3)."""
from __future__ import annotations

from app.services.ai.ai_eval_premature import (
    is_premature_final_answer,
    score_premature_rate,
)


def test_known_bug_1367_is_premature():
    assert is_premature_final_answer(
        assistant_content="در حال دریافت لیست گزارش‌های موجود برای شناسایی گزارش هزینه‌ها هستم.",
        user_query="یه گزارش از هزینه ها بهم بگو",
        function_calls=None,
        function_results={"_agent_trace": []},
    )


def test_real_answer_not_premature():
    assert not is_premature_final_answer(
        assistant_content="**خلاصه:** هزینه کل دوره ۱٬۵۷۱٬۰۰۰ ریال است.",
        user_query="یه گزارش از هزینه ها بهم بگو",
    )


def test_greeting_reply_not_premature():
    assert not is_premature_final_answer(
        assistant_content="سلام! چطور می‌توانم کمک کنم؟",
        user_query="سلام",
    )


def test_score_rate():
    cases = [
        {
            "assistant_content": "در حال جستجوی فاکتورها هستم.",
            "user_query": "فاکتورهای فروش را بررسی کن",
        },
        {
            "assistant_content": "۴ فاکتور یافت شد به مجموع ۴۱۴ میلیون ریال.",
            "user_query": "فاکتورهای فروش را بررسی کن",
        },
    ]
    score = score_premature_rate(cases)
    assert score["total"] == 2
    assert score["premature"] == 1
    assert score["rate"] == 0.5
