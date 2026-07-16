"""تست ارزیابی هدف agent و تمدید پویا بودجه."""
from __future__ import annotations

import pytest
from app.services.ai.ai_budget import (
    AgentBudget,
    STOP_REASON_ITERATIONS,
    STOP_REASON_UNPRODUCTIVE,
    build_agent_budget,
)
from app.services.ai.ai_exploration_service import ObservationStore
from app.services.ai.ai_goal_assessment import (
    AgentGoalTracker,
    ToolCallTracker,
    resolve_budget_gate,
    should_agent_continue_after_text_round,
    try_extend_budget_for_goal,
)


def _lookup(results_map, call):
    return results_map.get("call_1")


def test_tool_call_tracker_detects_repeat():
    tracker = ToolCallTracker()
    call = [{"name": "search_invoices", "arguments": {"business_id": 1}}]
    tracker.record(call)
    assert tracker.has_loop() is False
    tracker.record(call)
    assert tracker.has_loop() is True


def test_assess_after_productive_round():
    tracker = AgentGoalTracker()
    calls = [{"name": "search_invoices", "arguments": {}}]
    results = {
        "call_1": {
            "items": [{"id": 1}, {"id": 2}, {"id": 3}],
            "pagination": {"total": 3},
        },
    }
    assessment = tracker.assess_after_tool_round(calls, results, _lookup)
    assert assessment.should_continue is False
    assert assessment.confidence in ("high", "medium")


def test_assess_after_failed_round_should_continue():
    tracker = AgentGoalTracker()
    calls = [{"name": "search_invoices", "arguments": {}}]
    results = {"call_1": {"error": "NOT_FOUND"}}
    assessment = tracker.assess_after_tool_round(calls, results, _lookup)
    assert assessment.should_continue is True
    assert assessment.goal_reached is False


def test_budget_try_extend_respects_absolute_cap():
    budget = AgentBudget(
        max_iterations=3,
        max_extensions=5,
        extension_iterations=4,
        absolute_max_iterations=7,
    )
    assert budget.try_extend() is True
    assert budget.max_iterations == 7
    assert budget.try_extend() is False


def test_resolve_budget_gate_extends_when_goal_not_reached():
    budget = build_agent_budget("simple", max_iterations=3)
    tracker = AgentGoalTracker()
    calls = [{"name": "search_invoices", "arguments": {}}]
    results = {"call_1": {"error": "NOT_FOUND"}}
    tracker.assess_after_tool_round(calls, results, _lookup)

    status = budget.check(3)
    assert status.stop is True
    assert status.reason == STOP_REASON_ITERATIONS

    status = resolve_budget_gate(budget, 3, tracker)
    assert status.stop is False
    assert budget.max_iterations == 5


def test_resolve_budget_gate_extends_on_unproductive_when_goal_open():
    budget = build_agent_budget("simple", max_iterations=3)
    budget.unproductive_rounds = 2
    tracker = AgentGoalTracker()
    tracker.assess_after_text_round(
        "در حال جستجوی فاکتورها.",
        user_query="فاکتورها را بررسی کن",
    )

    status = budget.check(1)
    assert status.stop is True
    assert status.reason == STOP_REASON_UNPRODUCTIVE

    status = resolve_budget_gate(budget, 1, tracker)
    assert status.stop is False
    assert budget.unproductive_rounds == 0


def test_try_extend_blocked_on_loop():
    budget = build_agent_budget("simple", max_iterations=3)
    tracker = AgentGoalTracker()
    call = [{"name": "search_invoices", "arguments": {"q": "x"}}]
    tracker.assess_after_tool_round(call, {"call_1": {"error": "x"}}, _lookup)
    tracker.assess_after_tool_round(call, {"call_1": {"error": "x"}}, _lookup)
    assert tracker.last_assessment is not None
    assert tracker.last_assessment.loop_detected is True
    assert try_extend_budget_for_goal(budget, tracker.last_assessment) is False


@pytest.mark.asyncio
async def test_should_continue_after_text_with_goal_tracker():
    budget = build_agent_budget("simple", max_iterations=6)
    tracker = AgentGoalTracker()
    tracker.assess_after_tool_round(
        [{"name": "search_invoices", "arguments": {}}],
        {"call_1": {"error": "NOT_FOUND"}},
        _lookup,
    )

    result = await should_agent_continue_after_text_round(
        goal_tracker=tracker,
        observation_store=None,
        exploration_enabled=False,
        iteration=2,
        budget=budget,
        round_text="",
        use_llm=False,
    )
    assert result is True


@pytest.mark.asyncio
async def test_text_round_substantive_answer_stops_exploration():
    budget = build_agent_budget("simple", max_iterations=6)
    store = ObservationStore()
    long_answer = "### ابزارها\n\n" + ("| a | b |\n" * 5)

    result = await should_agent_continue_after_text_round(
        goal_tracker=AgentGoalTracker(),
        observation_store=store,
        exploration_enabled=True,
        iteration=1,
        budget=budget,
        round_text=long_answer,
        user_query="چه ابزارهایی داری؟",
        use_llm=False,
    )
    assert result is False


def test_assess_after_text_round_tool_discovery():
    tracker = AgentGoalTracker()
    assessment = tracker.assess_after_text_round(
        "### Tools\n\n| `get_tax_settings` | ok |",
        user_query="چه ابزارهایی برای مودیان داری؟",
    )
    assert assessment.goal_reached is True
    assert assessment.should_continue is False
