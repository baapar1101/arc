from app.services.ai.ai_trace import (
    extract_final_content_from_trace,
    merge_accumulated_and_trace_content,
)


def test_extract_prefers_answer_over_thought():
    trace = [
        {"kind": "thought", "body_markdown": "### Important findings\n1. ten debtors"},
        {"kind": "answer", "body_markdown": "**خلاصه**\n- 10 بدهکار"},
    ]
    assert extract_final_content_from_trace(trace) == "**خلاصه**\n- 10 بدهکار"


def test_extract_falls_back_to_thought():
    trace = [
        {"kind": "tool", "body_markdown": ""},
        {
            "kind": "thought",
            "body_markdown": "### Important findings\n1. گزارش بدهکاران: **10** مورد",
        },
    ]
    assert "10" in extract_final_content_from_trace(trace)


def test_extract_short_observation():
    trace = [{"kind": "observation", "body_markdown": "**10** مورد"}]
    assert extract_final_content_from_trace(trace) == "**10** مورد"


def test_merge_keeps_stream_content():
    trace = [{"kind": "thought", "body_markdown": "from trace"}]
    assert merge_accumulated_and_trace_content("stream text", trace) == "stream text"


def test_merge_uses_trace_when_stream_empty():
    trace = [{"kind": "explored", "body_markdown": "#### ✓ گزارش بدهکاران\n**10** مورد"}]
    assert merge_accumulated_and_trace_content("", trace).startswith("####")
