"""Tests for Harmony token sanitization and trace finalization."""
from app.services.ai.ai_content_sanitize import (
    extract_leaked_function_calls,
    prepare_assistant_content_for_persist,
    sanitize_assistant_content,
)
from app.services.ai.ai_trace import finalize_trace_steps_for_persist


_HARMONY_SAMPLE = (
    "در ابتدا بازهٔ زمانی «۳ ماه گذشته» را مشخص می‌کنم."
    "<|start|>assistant<|channel|>commentary to=functions.resolve_date_range "
    "<|constrain|>json<|message|>{"
    '  "relative": "last_3_months",'
    '  "calendar_type": "jalali"'
    "}<|call|>"
)


def test_sanitize_removes_harmony_tool_leak():
    cleaned = sanitize_assistant_content(_HARMONY_SAMPLE)
    assert "<|start|>" not in cleaned
    assert "<|channel|>" not in cleaned
    assert "resolve_date_range" not in cleaned
    assert "۳ ماه گذشته" in cleaned


def test_extract_leaked_function_calls():
    calls = extract_leaked_function_calls(_HARMONY_SAMPLE)
    assert len(calls) == 1
    assert calls[0]["name"] == "resolve_date_range"
    assert calls[0]["arguments"]["relative"] == "last_3_months"
    assert calls[0]["arguments"]["calendar_type"] == "jalali"


def test_finalize_trace_closes_active_steps():
    trace = [
        {
            "step_id": "ctx_thinking",
            "kind": "context",
            "state": "active",
            "body_markdown": _HARMONY_SAMPLE,
        },
        {"step_id": "answer_1", "kind": "answer", "state": "done", "body_markdown": "ok"},
    ]
    finalized = finalize_trace_steps_for_persist(trace)
    assert finalized[0]["state"] == "done"
    assert "<|start|>" not in finalized[0]["body_markdown"]
    assert finalized[1]["state"] == "done"


def test_prepare_assistant_content_for_persist_uses_sanitized_trace():
    trace = [
        {
            "kind": "answer",
            "body_markdown": _HARMONY_SAMPLE,
        }
    ]
    content = prepare_assistant_content_for_persist("", trace)
    assert "<|start|>" not in content
    assert "۳ ماه گذشته" in content


def test_infer_tool_from_reasoning_when_harmony_absent():
    """مدل گاهی فقط در reasoning نام ابزار را می‌گوید (بدون Harmony)."""
    text = "Need to call resolve_date_range for last 3 months relative to today."
    assert extract_leaked_function_calls(text) == []


def test_merge_trace_into_function_results_finalizes_active():
    from app.services.ai.ai_trace import merge_trace_into_function_results

    trace = [{"step_id": "ctx_thinking", "kind": "context", "state": "active"}]
    merged = merge_trace_into_function_results({}, trace)
    stored = merged["_agent_trace"][0]
    assert stored["state"] == "done"
