"""تجمیع استریم به پاسخ غیر استریم (STR-02)."""
from __future__ import annotations

import pytest

from app.services.ai.ai_stream_aggregate import aggregate_chat_completion_stream


async def _fake_stream(chunks):
    for chunk in chunks:
        yield chunk


@pytest.mark.asyncio
async def test_aggregate_joins_deltas_and_done_metadata():
    chunks = [
        {"event": "agent_run", "run_id": "abc"},
        {"delta": {"content": "سلام "}, "done": False},
        {"delta": {"content": "دنیا"}, "done": False},
        {
            "delta": {"content": ""},
            "done": True,
            "usage": {"total_tokens": 9, "input_tokens": 4, "output_tokens": 5},
            "function_calls": [{"name": "search_invoices"}],
            "function_results": {"tc1": {"ok": True}},
            "awaiting_approval": False,
            "run_id": "abc",
            "can_continue": False,
        },
    ]
    response = await aggregate_chat_completion_stream(_fake_stream(chunks))
    assert response["message"]["content"] == "سلام دنیا"
    assert response["message"]["role"] == "assistant"
    assert response["usage"]["total_tokens"] == 9
    assert response["_function_calls"][0]["name"] == "search_invoices"
    assert response["_function_results"]["tc1"]["ok"] is True
    assert response["run_id"] == "abc"
    assert response["awaiting_approval"] is False


@pytest.mark.asyncio
async def test_aggregate_prefers_final_content_over_deltas():
    chunks = [
        {"delta": {"content": "فاکتوری در این ماه نیست."}, "done": False},
        {
            "delta": {"content": ""},
            "done": True,
            "final_content": "برای پاسخ دقیق به این سوال باید داده‌های کسب‌وکار را از سیستم بخوانم.",
            "usage": {"total_tokens": 3},
        },
    ]
    response = await aggregate_chat_completion_stream(_fake_stream(chunks))
    assert "فاکتوری" not in response["message"]["content"]
    assert "سیستم بخوانم" in response["message"]["content"]


@pytest.mark.asyncio
async def test_aggregate_empty_stream_has_empty_message():
    response = await aggregate_chat_completion_stream(_fake_stream([]))
    assert response["message"]["content"] == ""
    assert response["usage"] == {}
    assert "_function_calls" not in response
