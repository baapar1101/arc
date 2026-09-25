"""Regression از پیام‌های واقعی DB — اعتبارسنجی Plan C روی باگ‌های شناخته‌شده."""
from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from app.services.ai.ai_agent_continuation import (
    assess_text_round_evidence,
    resolve_needs_tools,
)
from app.services.ai.ai_budget import build_agent_budget
from app.services.ai.ai_exploration_service import ObservationStore
from app.services.ai.ai_goal_assessment import (
    AgentGoalTracker,
    should_agent_continue_after_text_round,
)
from app.services.ai.ai_trace import extract_final_content_from_trace

_FIXTURES = Path(__file__).parent / "fixtures" / "agent_regression_db.json"
_CASES = json.loads(_FIXTURES.read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", _CASES, ids=lambda c: c["id"])
def test_db_regression_evidence(case):
    needs_tools = case.get("needs_tools_override")
    history = case.get("history_messages")
    if needs_tools is None:
        needs_tools = resolve_needs_tools(case["user_query"], history)

    result = assess_text_round_evidence(
        round_text=case["round_text"],
        user_query=case["user_query"],
        observation_store=ObservationStore(),
        needs_tools=needs_tools,
    )
    assert result.should_continue == case["expect_continue"], (
        f"{case['id']}: expected continue={case['expect_continue']}, "
        f"got {result.should_continue} ({result.reason_fa})"
    )
    assert result.goal_reached == case["expect_goal_reached"]


@pytest.mark.parametrize(
    "case",
    [c for c in _CASES if c["expect_continue"]],
    ids=lambda c: c["id"],
)
def test_db_regression_agent_loop_would_continue(case):
    budget = build_agent_budget("medium", max_iterations=6)
    needs_tools = case.get("needs_tools_override")
    history = case.get("history_messages")
    if needs_tools is None:
        needs_tools = resolve_needs_tools(case["user_query"], history)

    result = should_agent_continue_after_text_round(
        goal_tracker=AgentGoalTracker(),
        observation_store=ObservationStore(),
        exploration_enabled=True,
        iteration=2,
        budget=budget,
        round_text=case["round_text"],
        user_query=case["user_query"],
        history_messages=history,
        needs_tools=needs_tools,
    )
    assert result is True, f"{case['id']}: agent loop should continue, not stop"


@pytest.mark.skipif(
    not os.getenv("DB_HOST"),
    reason="DB not configured — set DB_HOST to run live trace checks",
)
def test_db_1350_trace_has_no_answer_fallback():
    """پیام budget (msg 1350) نباید از trace به answer fallback شود."""
    import json as json_mod

    from sqlalchemy import create_engine, text

    from app.core.settings import get_settings

    settings = get_settings()
    url = (
        f"postgresql://{settings.db_user}:{settings.db_password}"
        f"@{settings.db_host}:{settings.db_port}/{settings.db_name}"
    )
    engine = create_engine(url)
    with engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT content, function_results FROM ai_chat_messages "
                "WHERE id = 1350"
            ),
        ).fetchone()
    assert row is not None

    content, function_results = row
    trace_raw = json_mod.loads(function_results or "{}").get("_agent_trace", [])
    extracted = extract_final_content_from_trace(trace_raw)

    assert extracted == "", (
        "budget stop message trace must not synthesize answer from narrative/plan steps"
    )
    assert "دادهٔ تازه" in content
