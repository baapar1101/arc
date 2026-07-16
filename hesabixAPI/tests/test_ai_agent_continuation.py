"""تست ارزیابی ادامه agent — قواعد + LLM."""
from __future__ import annotations

import pytest

from app.services.ai.ai_agent_continuation import (
    ContinuationAssessment,
    assess_continuation_rule_based,
    assess_continuation_with_llm,
    resolve_agent_continuation,
    _parse_llm_continuation_json,
)
from app.services.ai.ai_goal_assessment import AgentGoalTracker


def test_parse_llm_continuation_json():
    raw = '```json\n{"should_continue": true, "goal_reached": false, "reason": "نیاز به ابزار"}\n```'
    parsed = _parse_llm_continuation_json(raw)
    assert parsed is not None
    assert parsed.should_continue is True
    assert parsed.goal_reached is False
    assert "ابزار" in (parsed.reason_fa or "")


def test_rule_based_pending_tool_fa():
    text = "در حال جستجوی فاکتورهای فروش برای بازهٔ «از 1405/01/23 تا 1405/04/23»."
    result = assess_continuation_rule_based(
        round_text=text,
        iteration=1,
        max_iterations=6,
    )
    assert result.should_continue is True
    assert result.goal_reached is False


def test_rule_based_pending_tool_en():
    text = "We will call resolve_date_range then get_financial_summary."
    result = assess_continuation_rule_based(
        round_text=text,
        iteration=1,
        max_iterations=6,
    )
    assert result.should_continue is True


def test_rule_based_substantive_answer_stops():
    text = "سلام! " + ("این یک پاسخ بلند و کامل است. " * 30)
    result = assess_continuation_rule_based(
        round_text=text,
        iteration=1,
        max_iterations=6,
    )
    assert result.should_continue is False
    assert result.goal_reached is True


def test_rule_based_at_max_iteration_pending_stops():
    text = "در حال تبدیل بازهٔ زمانی."
    result = assess_continuation_rule_based(
        round_text=text,
        iteration=6,
        max_iterations=6,
    )
    assert result.should_continue is False


@pytest.mark.asyncio
async def test_resolve_agent_continuation_uses_rules_without_provider():
    result = await resolve_agent_continuation(
        provider=None,
        model=None,
        user_query="فاکتورهای فروش را بررسی کن",
        round_text="در حال جستجوی فاکتورهای فروش.",
        goal_tracker=AgentGoalTracker(),
        iteration=1,
        max_iterations=6,
        use_llm=False,
    )
    assert result.should_continue is True


class _FakeProvider:
    def __init__(self, content: str) -> None:
        self._content = content

    def chat_completion(self, **kwargs):
        return {
            "choices": [
                {"message": {"content": self._content}},
            ]
        }


@pytest.mark.asyncio
async def test_assess_continuation_with_llm():
    provider = _FakeProvider(
        '{"should_continue": true, "goal_reached": false, "reason": "هنوز داده نیست"}'
    )
    result = await assess_continuation_with_llm(
        provider,
        "test-model",
        user_query="گزارش بده",
        round_text="Ready to call.",
        iteration=1,
        max_iterations=6,
    )
    assert result is not None
    assert result.should_continue is True
    assert result.source == "llm"
