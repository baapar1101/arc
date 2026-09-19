"""تست سرویس حافظه AI — دستورات + یادگیری بی‌صدا."""
from __future__ import annotations

from app.services.ai.ai_memory_service import (
    MAX_MEMORY_CHARS,
    extract_facts_from_messages,
    extract_learned_candidates,
    merge_memory_content,
    strip_auto_sections,
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


def test_extract_learned_candidates_remember_and_project():
    messages = [
        {
            "role": "user",
            "content": "یادت باشه اسم پروژه ما نسیم‌کالا است",
        },
        {"role": "assistant", "content": "یادداشت شد"},
        {
            "role": "user",
            "content": "اسم کسب‌وکار: فروشگاه آفتاب",
        },
    ]
    cands = extract_learned_candidates(messages)
    assert len(cands) >= 1
    joined = " ".join(c["content"] for c in cands)
    assert "نسیم" in joined or "آفتاب" in joined or "پروژه" in joined or "کسب" in joined


def test_strip_auto_sections_keeps_instructions():
    raw = (
        "مبالغ را تومان بگو\n\n"
        "# به‌روزرسانی اخیر:\n"
        "- ترجیح می‌دم گزارش‌ها را به تومان بدهی"
    )
    cleaned = strip_auto_sections(raw)
    assert "مبالغ را تومان بگو" in cleaned
    assert "به‌روزرسانی اخیر" not in cleaned


def test_merge_memory_dedupes():
    current = "# ترجیحات کاربر (خودکار):\n- ترجیح می‌دم گزارش‌ها را به تومان بدهی"
    facts = ["ترجیح می‌دم گزارش‌ها را به تومان بدهی"]
    merged = merge_memory_content(current, facts)
    assert merged == current


def test_merge_memory_appends_new_fact():
    merged = merge_memory_content("", ["هدف فروش ماه ۵۰۰ میلیون است"])
    assert "هدف فروش" in merged
    assert len(merged) <= MAX_MEMORY_CHARS
