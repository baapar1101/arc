"""تست بودجه context."""
from __future__ import annotations

from app.services.ai.ai_context_budget import (
    compress_history_messages,
    compute_context_usage,
    is_context_overflow_error,
    prepare_messages_for_context,
)


class _FakeProvider:
    def estimate_tokens(self, text: str) -> int:
        return max(1, len(text) // 4)


def test_compute_context_usage_ratio():
    msgs = [{"role": "user", "content": "x" * 4000}]
    usage = compute_context_usage(msgs, _FakeProvider(), budget_tokens=1000)
    assert usage["usage_ratio"] > 0.5
    assert usage["should_summarize"] is True


def test_compress_history_inserts_summary():
    rest = [{"role": "user", "content": f"msg {i}"} for i in range(50)]
    messages = [{"role": "system", "content": "sys"}] + rest
    compressed, flag = compress_history_messages(messages)
    assert flag is True
    contents = [m.get("content", "") for m in compressed if m.get("role") == "user"]
    assert any("خلاصه" in c for c in contents)


def test_prepare_messages_trims_when_large():
    messages = [{"role": "user", "content": "a" * 20000} for _ in range(3)]
    prepared, meta = prepare_messages_for_context(
        "system " * 100,
        messages,
        _FakeProvider(),
        budget_tokens=500,
        force_summarize=True,
    )
    assert meta["history_summarized"] is True
    assert len(prepared) >= 2


def test_is_context_overflow_error_detects_phrase():
    assert is_context_overflow_error(Exception("context length exceeded"))
    assert not is_context_overflow_error(Exception("other error"))


def test_is_strict_tool_pairing_error_detects_phrase():
    from app.services.ai.ai_context_budget import is_strict_tool_pairing_error

    err = Exception(
        "Message has tool role, but there was no previous assistant message with a tool call!"
    )
    assert is_strict_tool_pairing_error(err)
    assert not is_strict_tool_pairing_error(Exception("other error"))


def test_prepare_messages_includes_section_token_breakdown():
    from app.services.ai.ai_system_prompt import compose_structured_system_prompt

    structured = compose_structured_system_prompt(
        static_core="S" * 40,
        business_anchor="B",
        semi_static_sections=("insights-block",),
        insights_section="insights-block",
        runtime_sections=("now",),
        role="user",
        business_id=1,
    )
    _msgs, meta = prepare_messages_for_context(
        structured,
        [{"role": "user", "content": "hi"}],
        _FakeProvider(),
        budget_tokens=5000,
    )
    assert meta["static_tokens"] > 0
    assert meta["semi_static_tokens"] > 0
    assert meta["insights_tokens"] > 0
    assert meta["runtime_tokens"] > 0
