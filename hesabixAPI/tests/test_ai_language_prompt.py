"""تست بلوک زبان چت AI."""
from __future__ import annotations

from app.services.ai.ai_language_prompt import (
    build_language_context_prompt_block,
    normalize_language_code,
    resolve_effective_chat_language,
)


def test_normalize_language_code():
    assert normalize_language_code("fa-IR") == "fa"
    assert normalize_language_code("en-US") == "en"
    assert normalize_language_code(None) == "fa"


def test_resolve_effective_chat_language_prefers_memory():
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


def test_build_language_context_prompt_block_fa():
    block = build_language_context_prompt_block("fa")
    assert "فارسی" in block
    assert "پنل تحلیل" in block


def test_build_language_context_prompt_block_en():
    block = build_language_context_prompt_block("en")
    assert "English" in block
    assert "analysis-panel" in block or "analysis panel" in block
