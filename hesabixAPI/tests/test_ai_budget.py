"""تست کنترل‌گر بودجهٔ یکپارچهٔ agent."""
from __future__ import annotations

from app.services.ai.ai_budget import (
    STOP_REASON_ITERATIONS,
    STOP_REASON_TOKENS,
    STOP_REASON_UNPRODUCTIVE,
    STOP_REASON_WALL_CLOCK,
    AgentBudget,
    build_agent_budget,
)


def test_build_agent_budget_by_complexity():
    simple = build_agent_budget("simple", max_iterations=3)
    assert simple.max_iterations == 3
    assert simple.max_total_tokens == 24_000
    assert simple.wall_clock_sec == 45.0

    complex_budget = build_agent_budget("complex", max_iterations=12)
    assert complex_budget.max_total_tokens == 220_000
    assert complex_budget.wall_clock_sec == 300.0


def test_budget_stops_at_max_iterations():
    budget = AgentBudget(max_iterations=2, max_unproductive_rounds=0)
    assert budget.check(0).stop is False
    assert budget.check(1).stop is False
    status = budget.check(2)
    assert status.stop is True
    assert status.reason == STOP_REASON_ITERATIONS


def test_budget_stops_on_token_limit():
    budget = AgentBudget(max_iterations=10, max_total_tokens=1000)
    budget.add_tokens(999)
    assert budget.check(0).stop is False
    budget.add_tokens(1)
    status = budget.check(0)
    assert status.stop is True
    assert status.reason == STOP_REASON_TOKENS


def test_budget_stops_on_unproductive_rounds():
    budget = AgentBudget(max_iterations=10, max_unproductive_rounds=2)
    budget.note_round(productive=False)
    assert budget.check(1).stop is False
    budget.note_round(productive=False)
    status = budget.check(2)
    assert status.stop is True
    assert status.reason == STOP_REASON_UNPRODUCTIVE


def test_productive_round_resets_unproductive_counter():
    budget = AgentBudget(max_iterations=10, max_unproductive_rounds=2)
    budget.note_round(productive=False)
    budget.note_round(productive=True)
    budget.note_round(productive=False)
    assert budget.check(3).stop is False


def test_budget_stops_on_wall_clock(monkeypatch):
    budget = AgentBudget(max_iterations=10, wall_clock_sec=1.0)
    budget.started_at = 0.0

    monkeypatch.setattr(
        "app.services.ai.ai_budget.time.monotonic",
        lambda: 2.0,
    )
    status = budget.check(1)
    assert status.stop is True
    assert status.reason == STOP_REASON_WALL_CLOCK
