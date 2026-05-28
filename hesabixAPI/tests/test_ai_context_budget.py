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
