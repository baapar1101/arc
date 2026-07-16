"""Tests for Harmony token sanitization and trace finalization."""
from app.services.ai.ai_content_sanitize import (
    extract_leaked_function_calls,
    infer_announced_function_calls,
    prepare_assistant_content_for_persist,
    resolve_round_function_calls,
    sanitize_assistant_content,
    text_announces_pending_tool_use,
)
from app.services.ai.ai_exploration_service import is_substantive_text_answer
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
    calls = infer_announced_function_calls(
        text,
        known_tools=["resolve_date_range", "get_report"],
    )
    assert len(calls) == 1
    assert calls[0]["name"] == "resolve_date_range"


def test_pending_tool_search_fa():
    text = "در حال جستجوی فاکتورهای فروش برای بازهٔ «از 1405/01/23 تا 1405/04/23»."
    assert text_announces_pending_tool_use(text) is True
    assert is_substantive_text_answer(text) is False


def test_message_1313_style_plan_is_not_substantive():
    text = (
        "برای پاسخ به درخواست شما ابتدا باید تعداد افراد را استخراج کنیم.\n"
        "**اقدام:** فراخوانی ابزار `search_persons` بدون فیلتر خاص."
    )
    assert text_announces_pending_tool_use(text) is True
    assert is_substantive_text_answer(text) is False
    calls = infer_announced_function_calls(
        text,
        known_tools=["search_persons", "get_report"],
    )
    assert calls[0]["name"] == "search_persons"


def test_resolve_round_prefers_api_calls():
    api = [{"id": "x", "name": "get_report", "arguments": {}}]
    resolved = resolve_round_function_calls(
        api_function_calls=api,
        round_text="will call search_persons",
        round_reasoning="",
        known_tools=["search_persons"],
    )
    assert resolved == api


def test_merge_trace_into_function_results_finalizes_active():
    from app.services.ai.ai_trace import merge_trace_into_function_results

    trace = [{"step_id": "ctx_thinking", "kind": "context", "state": "active"}]
    merged = merge_trace_into_function_results({}, trace)
    stored = merged["_agent_trace"][0]
    assert stored["state"] == "done"
