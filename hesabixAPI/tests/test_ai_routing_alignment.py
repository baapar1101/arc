"""Phase 0 — همراستایی routing (`_routing_needs_tools`) با موارد واقعی DB.

باگ اصلی: `_routing_needs_tools` قبلاً فقط بر مبنای پیچیدگی (medium/complex)
تصمیم می‌گرفت؛ سوال‌های ساده اما داده‌محور (مثل «یه گزارش از هزینه‌ها بهم
بگو») هیچ‌وقت tools نمی‌گرفتند. این تست‌ها تضمین می‌کنند که برای تمام
پیام‌های واقعی DB که narrative بدون evidence بوده‌اند، `query_expects_tool_use`
(هستهٔ منطقی `_routing_needs_tools`) اکنون True برمی‌گرداند — یعنی همان مسیری
که goal_tracker/tools را در ai_service.py فعال می‌کند.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.services.ai.ai_agent_continuation import resolve_needs_tools
from app.services.ai.ai_exploration_service import resolve_exploration_enabled
from app.services.ai.ai_tool_intent import query_expects_tool_use

_FIXTURES = Path(__file__).parent / "fixtures" / "agent_regression_db.json"
_CASES = json.loads(_FIXTURES.read_text(encoding="utf-8"))

# مواردی که صراحتاً needs_tools_override=False دارند (پاسخ کامل از تور ابزار
# آمده) از این آزمون routing کنار گذاشته می‌شوند — آن‌ها موضوع تست continuation
# هستند نه routing.
_ROUTING_CASES = [c for c in _CASES if c.get("needs_tools_override") is None]


@pytest.mark.parametrize("case", _ROUTING_CASES, ids=lambda c: c["id"])
def test_routing_needs_tools_true_for_db_status_narratives(case):
    """هستهٔ `_routing_needs_tools`: این سوال‌ها باید tools=True بگیرند."""
    history = case.get("history_messages")
    assert query_expects_tool_use(case["user_query"], history) is True, (
        f"{case['id']}: query_expects_tool_use باید True باشد — در غیر این "
        "صورت tools/goal_tracker غیرفعال می‌ماند و narrative قفل می‌شود "
        f"({case.get('note')})"
    )


@pytest.mark.parametrize("case", _ROUTING_CASES, ids=lambda c: c["id"])
def test_resolve_needs_tools_matches_query_expects_tool_use(case):
    """`resolve_needs_tools` (استفاده‌شده در تست‌های continuation) باید با
    منطق routing واقعی (`query_expects_tool_use`) هم‌راستا باشد."""
    history = case.get("history_messages")
    assert resolve_needs_tools(case["user_query"], history) == query_expects_tool_use(
        case["user_query"], history
    )


@pytest.mark.parametrize("case", _ROUTING_CASES, ids=lambda c: c["id"])
def test_exploration_auto_enabled_for_db_status_narratives(case):
    """Phase 3: exploration در حالت auto هم باید برای این سوال‌ها فعال شود،
    نه فقط بر اساس پیچیدگی medium/complex."""
    history = case.get("history_messages")
    assert (
        resolve_exploration_enabled("auto", case["user_query"], history) is True
    ), f"{case['id']}: exploration auto باید برای سوال داده‌محور فعال باشد"


def test_routing_false_for_pure_greeting():
    """سلامتی: سوال صرفاً خوش‌وبش نباید tools بگیرد (سیگنال منفی برای تست)."""
    assert query_expects_tool_use("سلام") is False


def test_routing_false_for_generic_chit_chat_without_history():
    assert query_expects_tool_use("ممنون، خیلی لطف کردی") is False
