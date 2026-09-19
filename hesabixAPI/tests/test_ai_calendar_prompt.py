"""تست بلوک تقویم و زمان جاری در prompt AI."""
from __future__ import annotations

from app.services.ai.ai_calendar_prompt import (
    build_calendar_context_prompt_block,
    build_datetime_now_prompt_block,
)


def test_calendar_rules_reference_runtime_datetime_block():
    block = build_calendar_context_prompt_block("jalali")
    assert "زمان جاری" in block
    assert "امروز (نمایشی)" not in block


def test_datetime_now_includes_both_calendars():
    block = build_datetime_now_prompt_block("gregorian")
    assert "شمسی (جلالی)" in block
    assert "میلادی (Gregorian)" in block
    assert "منطقهٔ زمانی" in block
    assert ":" in block  # ساعت
