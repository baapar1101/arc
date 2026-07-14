"""تست سرویس Exploration (Exploring / Explored / Thought)."""
from __future__ import annotations

from app.services.ai.ai_budget import build_agent_budget
from app.services.ai.ai_exploration_service import (
    EXPLORATION_MODE_AUTO,
    EXPLORATION_MODE_EXPLORE,
    EXPLORATION_MODE_OFF,
    ExplorationBundle,
    ObservationStore,
    ToolObservation,
    build_explored_body_markdown,
    build_thought_markdown_rule_based,
    explore_target_for_call,
    mask_sensitive_text,
    resolve_exploration_enabled,
    should_continue_exploring,
    assess_tool_round_productivity,
)
from app.services.ai.ai_goal_assessment import (
    AgentGoalTracker,
    should_agent_continue_after_text_round,
)
from app.services.ai.ai_trace import trace_step


def test_resolve_exploration_enabled_modes():
    assert resolve_exploration_enabled(EXPLORATION_MODE_OFF, "مقایسه فروش دو ماه") is False
    assert resolve_exploration_enabled(EXPLORATION_MODE_EXPLORE, "سلام") is True
    assert resolve_exploration_enabled(
        EXPLORATION_MODE_AUTO, "گزارش جامع فروش و موجودی انبار"
    ) is True


def test_explore_target_for_call():
    label = explore_target_for_call(
        "search_invoices",
        {"business_id": 92, "query": "INV-0026"},
    )
    assert "فاکتور" in label or "invoice" in label.lower() or "92" in label


def test_build_thought_and_explored_bundle():
    bundle = ExplorationBundle(
        bundle_id="b1",
        iteration=1,
        title="تنظیمات مالیات",
        explore_targets=["tax"],
        observations=[
            ToolObservation(
                tool_name="get_tax_settings",
                arguments={"business_id": 92},
                result={
                    "tax_memory_id": "A114FA",
                    "economic_code": "33200552670004",
                    "sandbox": False,
                    "certificate": "",
                },
                success=True,
            ),
        ],
    )
    explored = build_explored_body_markdown(bundle)
    assert "A114FA" in explored or "tax_memory" in explored

    body, hypothesis, confidence, open_qs = build_thought_markdown_rule_based(
        bundle, "خطای fiscalId"
    )
    assert "یافته‌های مهم" in body
    assert hypothesis
    assert confidence in ("low", "medium", "high")


def test_mask_sensitive_text():
    raw = "**private_key**: `abcdefghijklmnop` (1703 chars)"
    masked = mask_sensitive_text(raw)
    assert "abcdefghijklmnop" not in masked


def test_trace_step_exploration_fields():
    event = trace_step(
        "t1",
        "thought",
        "done",
        title_key="aiTraceThought",
        bundle_id="bundle_1",
        findings_count=3,
        hypothesis="test",
        confidence="high",
    )
    assert event["bundle_id"] == "bundle_1"
    assert event["findings_count"] == 3


def test_observation_store_context():
    store = ObservationStore()
    bundle = ExplorationBundle(
        bundle_id="b1",
        iteration=1,
        title="x",
        explore_targets=[],
        observations=[],
    )
    store.add_bundle(bundle)
    body, hyp, conf, oq = build_thought_markdown_rule_based(bundle, "q")
    from app.services.ai.ai_exploration_service import ThoughtRecord

    store.add_thought(
        ThoughtRecord(
            thought_id="th1",
            bundle_id="b1",
            iteration=1,
            body_markdown=body,
            hypothesis=hyp,
            confidence=conf,
            open_questions=oq,
        )
    )
    ctx = store.context_for_llm()
    assert ctx is not None
    assert "[agent_thought]" in ctx


def test_should_continue_exploring():
    store = ObservationStore()
    from app.services.ai.ai_exploration_service import ThoughtRecord

    store.add_thought(
        ThoughtRecord(
            thought_id="t",
            bundle_id="b",
            iteration=1,
            body_markdown="x",
            confidence="high",
            open_questions=[],
        )
    )
    assert should_continue_exploring(store, 2, 8) is False


def test_should_not_continue_on_substantive_text_without_evidence():
    store = ObservationStore()
    long_answer = "سلام! " + ("این یک پاسخ بلند است. " * 30)
    assert should_continue_exploring(store, 1, 4, round_text=long_answer) is False


def test_should_continue_on_empty_evidence_and_short_text():
    store = ObservationStore()
    assert should_continue_exploring(store, 1, 4, round_text="سلام") is True


def test_assess_tool_round_productivity():
    calls = [{"name": "search_invoices", "arguments": {}}]
    results = {
        "call_1": {"items": [{"id": 1}], "pagination": {"total": 1}},
    }

    def lookup(results_map, call):
        return results_map.get("call_1")

    assert assess_tool_round_productivity(calls, results, lookup) is True
    assert assess_tool_round_productivity(
        calls,
        {"call_1": {"error": "NOT_FOUND"}},
        lookup,
    ) is False


def test_should_agent_continue_after_text_respects_budget():
    budget = build_agent_budget("medium", max_iterations=2)
    store = ObservationStore()
    assert should_agent_continue_after_text_round(
        goal_tracker=AgentGoalTracker(),
        observation_store=store,
        exploration_enabled=True,
        iteration=2,
        budget=budget,
    ) is False
