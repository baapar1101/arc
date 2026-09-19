"""Regression fixtures for Plan C evidence-based agent loop."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.services.ai.ai_agent_continuation import assess_text_round_evidence
from app.services.ai.ai_exploration_service import ObservationStore, ThoughtRecord

_FIXTURES = Path(__file__).parent / "fixtures" / "agent_regression_v2.json"


@pytest.fixture(scope="module")
def regression_cases():
    return json.loads(_FIXTURES.read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", json.loads(_FIXTURES.read_text(encoding="utf-8")), ids=lambda c: c["id"])
def test_agent_regression_v2(case):
    store = ObservationStore()
    if case.get("has_high_confidence_thought"):
        store.add_thought(
            ThoughtRecord(
                thought_id="t1",
                bundle_id="b1",
                iteration=1,
                body_markdown="### یافته‌ها",
                confidence="high",
                open_questions=[],
            )
        )

    result = assess_text_round_evidence(
        round_text=case["round_text"],
        user_query=case["user_query"],
        observation_store=store,
        needs_tools=case["needs_tools"],
    )
    assert result.should_continue == case["expect_continue"]
    assert result.goal_reached == case["expect_goal_reached"]
