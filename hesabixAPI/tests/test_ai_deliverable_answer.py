"""تست gate پاسخ تحویلی (deliverable) — regression session 756."""
from __future__ import annotations

from app.services.ai.ai_deliverable_answer import (
    is_deliverable_answer,
    looks_like_planning_narrative,
)

_SESSION_756_PLANNING = """\
برای تهیهٔ گزارش مالی سه ماه گذشته ابتدا بازهٔ تاریخی «۳ ماه اخیر» (بر مبنای تقویم جلالی) را به تاریخ میلادی تبدیل می‌کنم. سپس به‌صورت موازی داده‌های فروش، خرید، خلاصهٔ مالی، وضعیت بدهکاران/بستانکاران و گردش نقدی این بازه را دریافت می‌کنم.

```json
{
  "relative": "last_3_months"
}
```"""

_COMPOSED_REPORT = (
    "**خلاصهٔ فروش ۳ ماه اخیر**\n\n"
    "- تعداد فاکتور: ۱۱\n"
    "- مجموع مبلغ: ۴۱۴ میلیون ریال"
)


def test_session_756_planning_is_not_deliverable():
    assert looks_like_planning_narrative(_SESSION_756_PLANNING)
    assert not is_deliverable_answer(
        _SESSION_756_PLANNING,
        needs_tools=True,
        has_tool_evidence=True,
    )


def test_composed_report_is_deliverable_with_evidence():
    assert is_deliverable_answer(
        _COMPOSED_REPORT,
        needs_tools=True,
        has_tool_evidence=True,
    )


def test_greeting_without_tools_is_deliverable():
    assert is_deliverable_answer(
        "سلام! چطور می‌توانم کمک کنم؟",
        needs_tools=False,
        has_tool_evidence=False,
    )


def test_absence_claim_without_tools_is_not_deliverable():
    from app.services.ai.ai_deliverable_answer import looks_like_ungrounded_business_claim

    text = "فاکتوری در این ماه ثبت نشده است."
    assert looks_like_ungrounded_business_claim(text)
    assert not is_deliverable_answer(
        text,
        needs_tools=True,
        has_tool_evidence=False,
    )


def test_numbered_report_without_tools_is_not_deliverable():
    assert not is_deliverable_answer(
        _COMPOSED_REPORT,
        needs_tools=True,
        has_tool_evidence=False,
    )


def test_clarifying_question_without_tools_is_deliverable():
    assert is_deliverable_answer(
        "کدام بازهٔ زمانی را می‌خواهید بررسی کنم؟",
        needs_tools=True,
        has_tool_evidence=False,
    )


def test_gate_replaces_ungrounded_invoice_claim():
    from app.services.ai.ai_deliverable_answer import (
        UNGROUNDED_TOOL_REQUIRED_MESSAGE_FA,
        gate_ungrounded_assistant_content,
    )

    gated = gate_ungrounded_assistant_content(
        "فاکتوری در این بازه وجود ندارد.",
        user_query="فاکتورهای فروش ماه گذشته را بگو",
        function_calls=None,
        function_results={"_agent_run": {"run_id": "x"}},
    )
    assert gated == UNGROUNDED_TOOL_REQUIRED_MESSAGE_FA


def test_gate_keeps_claim_when_tool_evidence_exists():
    from app.services.ai.ai_deliverable_answer import gate_ungrounded_assistant_content

    text = "فاکتوری در این بازه وجود ندارد."
    gated = gate_ungrounded_assistant_content(
        text,
        user_query="فاکتورهای فروش ماه گذشته را بگو",
        function_calls=[{"name": "search_invoices"}],
        function_results={"tc1": {"items": []}},
    )
    assert gated == text


def test_gate_keeps_greeting_when_query_does_not_need_tools():
    from app.services.ai.ai_deliverable_answer import gate_ungrounded_assistant_content

    text = "سلام! چطور می‌توانم کمک کنم؟"
    gated = gate_ungrounded_assistant_content(
        text,
        user_query="سلام",
    )
    assert gated == text
