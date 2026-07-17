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
