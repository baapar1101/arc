"""تست حافظه ساخت‌یافته."""
from __future__ import annotations

from app.services.ai.ai_memory_structured import (
    extract_structured_from_text,
    merge_structured_patch,
    parse_structured,
    structured_to_prompt_block,
)


def test_parse_structured_defaults():
    s = parse_structured(None)
    assert s["currency_display"] == "toman"
    assert s["report_style"] == "summary"


def test_merge_structured_terms():
    base = parse_structured({"internal_terms": [{"term": "کالا", "meaning": "محصول"}]})
    merged = merge_structured_patch(
        base,
        {"internal_terms": [{"term": "فاکتور", "meaning": "سند فروش"}]},
    )
    terms = {t["term"] for t in merged["internal_terms"]}
    assert "کالا" in terms and "فاکتور" in terms


def test_structured_to_prompt_block():
    block = structured_to_prompt_block(
        {"sales_goal_monthly": 500_000_000, "currency_display": "toman"}
    )
    assert "هدف فروش" in block
    assert "toman" in block


def test_extract_structured_from_text_goal():
    patch = extract_structured_from_text("هدف فروش ماهانه ۵۰۰ میلیون تومان")
    assert patch.get("sales_goal_monthly") == 500_000_000
