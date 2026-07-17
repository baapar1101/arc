"""تست بلوک زبان چت AI."""
from __future__ import annotations

from app.services.ai.ai_language_prompt import (
    build_force_synthesis_user_content,
    build_language_context_prompt_block,
    detect_message_language,
    normalize_language_code,
    reasoning_language_mismatch,
    resolve_effective_chat_language,
)


def test_normalize_language_code():
    assert normalize_language_code("fa-IR") == "fa"
    assert normalize_language_code("en-US") == "en"
    assert normalize_language_code(None) == "fa"


def test_resolve_effective_chat_language_prefers_user_message():
    assert (
        resolve_effective_chat_language(
            ctx_language="en-US",
            preferred_language="en",
            user_message="یه گزارش مالی از سه ماه گذشته بده",
        )
        == "fa"
    )
    assert (
        resolve_effective_chat_language(
            ctx_language="fa-IR",
            preferred_language="fa",
            user_message="Show me last month sales report",
        )
        == "en"
    )


def test_resolve_effective_chat_language_prefers_memory_without_message():
    assert (
        resolve_effective_chat_language(
            ctx_language="fa-IR",
            preferred_language="en",
        )
        == "en"
    )
    assert (
        resolve_effective_chat_language(
            ctx_language="en-US",
            preferred_language=None,
        )
        == "en"
    )


def test_detect_message_language():
    assert detect_message_language("سلام گزارش بده") == "fa"
    assert detect_message_language("Show sales report") == "en"
    assert detect_message_language("") is None


def test_reasoning_language_mismatch():
    assert reasoning_language_mismatch(
        "I will call resolve_date_range first",
        "fa",
    )
    assert not reasoning_language_mismatch(
        "ابتدا بازه تاریخ را مشخص می‌کنم",
        "fa",
    )


def test_force_synthesis_respects_language():
    en = build_force_synthesis_user_content("en", "data")
    fa = build_force_synthesis_user_content("fa", "data")
    assert "English" in en
    assert "فارسی" in fa


def test_build_language_context_prompt_block_fa():
    block = build_language_context_prompt_block("fa")
    assert "فارسی" in block
    assert "پنل تحلیل" in block


def test_build_language_context_prompt_block_en():
    block = build_language_context_prompt_block("en")
    assert "English" in block
    assert "analysis-panel" in block or "analysis panel" in block
