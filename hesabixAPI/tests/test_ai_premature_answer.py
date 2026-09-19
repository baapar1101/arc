"""تست تشخیص narrative وضعیت — فقط برای eval/logging (Phase 3)."""
from __future__ import annotations

from app.services.ai.ai_premature_answer import looks_like_status_narrative


def test_detects_persian_status_in_progress():
    assert looks_like_status_narrative(
        "در حال دریافت لیست گزارش‌های موجود برای شناسایی گزارش هزینه‌ها هستم."
    )


def test_detects_english_will_call():
    assert looks_like_status_narrative(
        "We will call resolve_date_range then get_financial_summary."
    )


def test_detects_date_range_intent_announcement():
    assert looks_like_status_narrative(
        "در حال محاسبه بازهٔ تاریخ «۳ ماه گذشته» بر حسب تقویم جلالی است. "
        "برای این کار ابتدا تابع resolve_date_range را صدا می‌زنیم."
    )


def test_real_answer_not_flagged():
    assert not looks_like_status_narrative(
        "**خلاصه سود و زیان ۳ ماه گذشته**\n\n"
        "| شاخص | مقدار |\n|------|-------|\n"
        "| درآمد کل | ‎1 221 161 500 ریال |"
    )


def test_greeting_not_flagged():
    assert not looks_like_status_narrative(
        "سلام! چه کمکی از اطلاعات حسابیکس می‌توانم براتون انجام بدم؟"
    )


def test_empty_not_flagged():
    assert not looks_like_status_narrative("")
    assert not looks_like_status_narrative("   ")
