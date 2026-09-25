"""قرارداد رویداد done استریم — فیلدهای متادیتا نباید حذف شوند."""
from __future__ import annotations

from app.services.ai.ai_stream_helpers import (
    attach_stream_done_metadata,
    build_chat_done_sse_data,
    chunk_to_sse_data,
)


def test_build_chat_done_keeps_budget_approval_citations_and_model():
    extra = {
        "agent_trace": [{"step_id": "1", "kind": "answer"}],
        "agent_budget": {
            "iteration": 3,
            "max_iterations": 8,
            "extensions_granted": 1,
            "max_extensions": 2,
            "base_max_iterations": 6,
        },
        "agent_run": {"run_id": "abc", "phase": "done"},
        "awaiting_approval": True,
        "citations_context": "منبع: فاکتور ۱۲",
        "citations": [{"id": 12, "name": "فاکتور ۱۲", "entity": "invoice"}],
        "requested_model": "auto",
        "resolved_model": "gpt-4.1",
        "execution_mode": "supervised",
        "can_continue": True,
        "run_id": "abc",
        "final_content": "پاسخ نهایی persist شده",
        "stop_reason": "max_iterations",
        "stop_message_fa": "به سقف مراحل رسیدم.",
    }
    payload = build_chat_done_sse_data(
        message_id=42,
        usage={"total_tokens": 10},
        function_calls=[{"name": "create_invoice"}],
        function_results={"tc1": {"error": "APPROVAL_REQUIRED"}},
        extra=extra,
    )
    assert payload["done"] is True
    assert payload["message_id"] == 42
    assert payload["awaiting_approval"] is True
    assert payload["citations_context"] == "منبع: فاکتور ۱۲"
    assert payload["citations"][0]["id"] == 12
    assert payload["resolved_model"] == "gpt-4.1"
    assert payload["requested_model"] == "auto"
    assert payload["execution_mode"] == "supervised"
    assert payload["agent_budget"]["extensions_granted"] == 1
    assert payload["agent_run"]["run_id"] == "abc"
    assert payload["can_continue"] is True
    assert payload["run_id"] == "abc"
    assert payload["final_content"] == "پاسخ نهایی persist شده"
    assert payload["stop_reason"] == "max_iterations"
    assert payload["stop_message_fa"] == "به سقف مراحل رسیدم."
    assert "warning" not in payload


def test_awaiting_approval_false_is_preserved():
    payload = build_chat_done_sse_data(
        message_id=1,
        usage=None,
        extra={"awaiting_approval": False},
    )
    assert payload["awaiting_approval"] is False
    assert payload["warning"]


def test_chunk_to_sse_maps_extension_budget_fields():
    events = chunk_to_sse_data(
        {
            "event": "agent_budget",
            "iteration": 2,
            "max_iterations": 10,
            "extensions_granted": 1,
            "max_extensions": 2,
            "base_max_iterations": 8,
        }
    )
    assert len(events) == 1
    assert events[0]["extensions_granted"] == 1
    assert events[0]["max_extensions"] == 2
    assert events[0]["base_max_iterations"] == 8


def test_chunk_to_sse_done_keeps_citations_and_approval():
    events = chunk_to_sse_data(
        {
            "delta": {"content": ""},
            "done": True,
            "usage": {"total_tokens": 4},
            "awaiting_approval": True,
            "citations_context": "cite",
            "citations": [{"id": 1, "name": "فاکتور"}],
            "execution_mode": "analyzer",
            "agent_budget": {"iteration": 1},
        }
    )
    done = [e for e in events if e.get("done")]
    assert done
    assert done[0]["awaiting_approval"] is True
    assert done[0]["citations_context"] == "cite"
    assert done[0]["citations"][0]["id"] == 1
    assert done[0]["execution_mode"] == "analyzer"


def test_attach_skips_missing_keys():
    payload = attach_stream_done_metadata({"done": True}, {"unrelated": 1})
    assert payload == {"done": True}
