"""تست سرویس Exploration (Exploring / Explored / Thought)."""
from __future__ import annotations

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
    assert "Important findings" in body
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
