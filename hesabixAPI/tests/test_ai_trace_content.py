from app.services.ai.ai_trace import (
    extract_explored_context_for_synthesis,
    extract_final_content_from_trace,
    merge_accumulated_and_trace_content,
    trace_has_unanswered_evidence,
)


def test_extract_prefers_answer_over_explored():
    trace = [
        {"kind": "explored", "body_markdown": "#### draft"},
        {"kind": "answer", "body_markdown": "**خلاصه**\n- 10 بدهکار"},
    ]
    assert extract_final_content_from_trace(trace) == "**خلاصه**\n- 10 بدهکار"


def test_extract_does_not_fall_back_to_explored():
    """Phase 1: explored به‌تنهایی نباید پاسخ نهایی شود (فقط answer)."""
    trace = [
        {"kind": "narrative", "body_markdown": "در حال جستجو..."},
        {
            "kind": "explored",
            "body_markdown": "#### ✓ گزارش بدهکاران\n**10** مورد",
        },
    ]
    assert extract_final_content_from_trace(trace) == ""


def test_extract_skips_narrative_only():
    trace = [
        {
            "kind": "narrative",
            "body_markdown": "در حال جستجوی فاکتورهای فروش برای بازهٔ مشخص.",
        },
    ]
    assert extract_final_content_from_trace(trace) == ""


def test_merge_keeps_deliverable_stream_content():
    trace = [{"kind": "thought", "body_markdown": "from trace"}]
    stream = "**خلاصه**\n- ۱۰ مورد"
    assert merge_accumulated_and_trace_content(stream, trace) == stream


def test_merge_replaces_planning_stream_with_trace_answer():
    planning = (
        "ابتدا بازه را مشخص می‌کنم سپس داده‌های فروش را دریافت می‌کنم."
    )
    trace = [{"kind": "answer", "body_markdown": "**خلاصه**\n- 10 بدهکار"}]
    assert merge_accumulated_and_trace_content(planning, trace) == "**خلاصه**\n- 10 بدهکار"


def test_merge_does_not_use_explored_when_stream_empty():
    """Phase 1: explored دیگر fallback پاسخ نیست؛ merge باید خالی برگردد."""
    trace = [{"kind": "explored", "body_markdown": "#### ✓ گزارش بدهکاران\n**10** مورد"}]
    assert merge_accumulated_and_trace_content("", trace) == ""


def test_merge_still_uses_answer_when_stream_empty():
    trace = [{"kind": "answer", "body_markdown": "**خلاصه**\n- 10 بدهکار"}]
    assert merge_accumulated_and_trace_content("", trace) == "**خلاصه**\n- 10 بدهکار"


def test_extract_explored_context_for_synthesis():
    trace = [
        {"kind": "narrative", "body_markdown": "در حال جستجو..."},
        {"kind": "explored", "body_markdown": "#### ✓ گزارش بدهکاران\n**10** مورد"},
        {"kind": "thought", "body_markdown": "به نظر می‌رسد ۱۰ بدهکار وجود دارد."},
    ]
    ctx = extract_explored_context_for_synthesis(trace)
    assert "10" in ctx or "۱۰" in ctx
    assert "در حال جستجو" not in ctx


def test_extract_usable_narrative_for_answer_skips_status():
    from app.services.ai.ai_trace import extract_usable_narrative_for_answer

    trace = [
        {"kind": "narrative", "body_markdown": "در حال دریافت گزارش فروش هستم."},
        {
            "kind": "narrative",
            "body_markdown": (
                "**خلاصهٔ فروش ۳ ماه اخیر**\n\n"
                "- تعداد فاکتور: ۱۱\n"
                "- مجموع: ۴۱۴ میلیون"
            ),
        },
    ]
    body = extract_usable_narrative_for_answer(trace)
    assert "خلاصهٔ فروش" in body
    assert "در حال" not in body


def test_extract_usable_narrative_ignores_short_status_only():
    from app.services.ai.ai_trace import extract_usable_narrative_for_answer

    trace = [
        {"kind": "narrative", "body_markdown": "در حال جستجو..."},
    ]
    assert extract_usable_narrative_for_answer(trace) == ""


def test_trace_has_unanswered_evidence_true_without_answer():
    trace = [
        {"kind": "explored", "body_markdown": "#### ✓ گزارش بدهکاران\n**10** مورد"},
    ]
    assert trace_has_unanswered_evidence(trace) is True


def test_trace_has_unanswered_evidence_false_when_answer_present():
    trace = [
        {"kind": "explored", "body_markdown": "#### ✓ گزارش بدهکاران\n**10** مورد"},
        {"kind": "answer", "body_markdown": "**خلاصه**"},
    ]
    assert trace_has_unanswered_evidence(trace) is False


def test_trace_has_unanswered_evidence_false_when_empty():
    assert trace_has_unanswered_evidence([]) is False
    assert trace_has_unanswered_evidence(None) is False
