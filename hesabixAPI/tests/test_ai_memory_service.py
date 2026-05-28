"""تست سرویس حافظه AI."""
from __future__ import annotations

from app.services.ai.ai_memory_service import (
    MAX_MEMORY_CHARS,
    extract_facts_from_messages,
    merge_memory_content,
)


def test_extract_facts_from_preference_message():
    messages = [
        {"role": "user", "content": "ترجیح می‌دم گزارش‌ها را به تومان بدهی"},
        {"role": "assistant", "content": "باشه"},
        {"role": "user", "content": "سلام"},
    ]
    facts = extract_facts_from_messages(messages)
    assert len(facts) >= 1
    assert "تومان" in facts[0]


def test_merge_memory_dedupes():
    current = "# ترجیحات کاربر (خودکار):\n- ترجیح می‌دم گزارش‌ها را به تومان بدهی"
    facts = ["ترجیح می‌دم گزارش‌ها را به تومان بدهی"]
    merged = merge_memory_content(current, facts)
    assert merged == current


def test_merge_memory_appends_new_fact():
    merged = merge_memory_content("", ["هدف فروش ماه ۵۰۰ میلیون است"])
    assert "هدف فروش" in merged
    assert len(merged) <= MAX_MEMORY_CHARS
