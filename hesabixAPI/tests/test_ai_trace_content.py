from app.services.ai.ai_trace import (
    extract_final_content_from_trace,
    merge_accumulated_and_trace_content,
)


def test_extract_prefers_answer_over_explored():
    trace = [
        {"kind": "explored", "body_markdown": "#### draft"},
        {"kind": "answer", "body_markdown": "**خلاصه**\n- 10 بدهکار"},
    ]
    assert extract_final_content_from_trace(trace) == "**خلاصه**\n- 10 بدهکار"


def test_extract_falls_back_to_explored():
    trace = [
        {"kind": "narrative", "body_markdown": "در حال جستجو..."},
        {
            "kind": "explored",
            "body_markdown": "#### ✓ گزارش بدهکاران\n**10** مورد",
        },
    ]
    assert "10" in extract_final_content_from_trace(trace)


def test_extract_skips_narrative_only():
    trace = [
        {
            "kind": "narrative",
            "body_markdown": "در حال جستجوی فاکتورهای فروش برای بازهٔ مشخص.",
        },
    ]
    assert extract_final_content_from_trace(trace) == ""


def test_merge_keeps_stream_content():
    trace = [{"kind": "thought", "body_markdown": "from trace"}]
    assert merge_accumulated_and_trace_content("stream text", trace) == "stream text"


def test_merge_uses_trace_when_stream_empty():
    trace = [{"kind": "explored", "body_markdown": "#### ✓ گزارش بدهکاران\n**10** مورد"}]
    assert merge_accumulated_and_trace_content("", trace).startswith("####")
