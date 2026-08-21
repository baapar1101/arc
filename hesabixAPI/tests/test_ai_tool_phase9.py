"""Phase 9 — Adaptive K canary, typed misses, production flags stay off."""
from __future__ import annotations

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_MIN_LIVE_SAMPLES,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    HYBRID_TOOL_DISCOVERY,
    MAX_DISCOVERY_RETRIES,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_ops_metrics import metric_snapshot, reset_metrics_for_tests
from app.services.ai.ai_tool_canary import (
    clamp_rollout_percent,
    recommend_canary_decision,
    resolve_adaptive_assignment,
    stable_canary_bucket,
)
from app.services.ai.ai_tool_discovery import discover_tools
from app.services.ai.ai_tool_discovery_telemetry import (
    EVENT_AUTHORIZATION_FAILURE,
    EVENT_RETRIEVAL_MISS,
    EVENT_SCHEMA_MISS,
    EVENT_UNKNOWN_TOOL,
    classify_unoffered_tool,
    observe_discovery_request,
    record_unoffered_tool,
    reset_discovery_telemetry_for_tests,
    telemetry_snapshot,
)
from app.services.ai.ai_tool_intent import _CATEGORY_TOOLS, _CORE_TOOL_NAMES, _WRITE_TOOLS
from app.services.ai.ai_tool_rollout import (
    RediscoveryState,
    plan_unknown_tool_recovery,
    progressive_rollout_allows,
)


def _catalog() -> set[str]:
    names = set(_CORE_TOOL_NAMES) | set(_WRITE_TOOLS)
    for group in _CATEGORY_TOOLS.values():
        names |= set(group)
    return names


def test_production_canary_starts_at_zero():
    assert MAX_TOOLS_PER_REQUEST == 48
    assert MAX_TOOLS_AUTONOMOUS == 128
    assert PROGRESSIVE_SCHEMA_LOADING is False
    assert ADAPTIVE_DISCOVERY_K is False
    assert ADAPTIVE_K_ROLLOUT_PERCENT == 0
    assert HYBRID_TOOL_DISCOVERY is False
    assert MAX_DISCOVERY_RETRIES == 1
    assert progressive_rollout_allows(1) is False
    assigned = resolve_adaptive_assignment(business_id=7, user_id=9)
    assert assigned.enabled is False
    assert assigned.arm == "control"
    assert assigned.percent == 0


def test_canary_bucket_is_stable_and_hides_ids():
    a = stable_canary_bucket(business_id=42, user_id=7)
    b = stable_canary_bucket(business_id=42, user_id=7)
    c = stable_canary_bucket(business_id=42, user_id=8)
    assert a == b
    assert 0 <= a <= 99
    assert a != c
    payload = resolve_adaptive_assignment(
        business_id=42, user_id=7, percent=5
    ).to_log_dict()
    blob = str(payload)
    assert "42" not in blob
    assert "user_id" not in blob
    assert "business_id" not in blob


def test_rollout_percent_only_allowed_steps_and_rounds_down():
    assert clamp_rollout_percent(0) == 0
    assert clamp_rollout_percent(5) == 5
    assert clamp_rollout_percent(7) == 5
    assert clamp_rollout_percent(10) == 10
    assert clamp_rollout_percent(25) == 25
    assert clamp_rollout_percent(50) == 50
    assert clamp_rollout_percent(100) == 100
    assert clamp_rollout_percent(3) == 0


def test_percent_zero_never_enables_experiment():
    for biz, user in ((1, 1), (99, 12), (1000, 4)):
        assigned = resolve_adaptive_assignment(
            business_id=biz, user_id=user, percent=0
        )
        assert assigned.enabled is False
        assert assigned.arm == "control"


def test_same_tenant_user_stays_on_same_arm():
    first = resolve_adaptive_assignment(business_id=18, user_id=3, percent=25)
    second = resolve_adaptive_assignment(business_id=18, user_id=3, percent=25)
    assert first.arm == second.arm
    assert first.bucket == second.bucket
    assert first.enabled == second.enabled


def test_apply_adaptive_truncates_without_global_flag():
    catalog = _catalog()
    control = discover_tools(
        "فاکتور فروش این ماه را پیدا کن",
        permissioned_names=catalog,
        execution_mode="analyzer",
        apply_adaptive=False,
    )
    experiment = discover_tools(
        "فاکتور فروش این ماه را پیدا کن",
        permissioned_names=catalog,
        execution_mode="analyzer",
        apply_adaptive=True,
    )
    assert ADAPTIVE_DISCOVERY_K is False
    assert len(control.candidates) > len(experiment.candidates)
    assert len(experiment.candidates) <= experiment.recommended_k + 2
    assert experiment.adaptive_enabled is True
    assert control.adaptive_enabled is False


def test_miss_classes_are_separate_events():
    assert classify_unoffered_tool(
        name="ghost_tool",
        in_registry=False,
        authorized=False,
        in_ranked_candidates=False,
        in_offered_schemas=False,
    ) == EVENT_UNKNOWN_TOOL
    assert classify_unoffered_tool(
        name="delete_invoice",
        in_registry=True,
        authorized=False,
        in_ranked_candidates=False,
        in_offered_schemas=False,
    ) == EVENT_AUTHORIZATION_FAILURE
    assert classify_unoffered_tool(
        name="search_invoices",
        in_registry=True,
        authorized=True,
        in_ranked_candidates=False,
        in_offered_schemas=False,
    ) == EVENT_RETRIEVAL_MISS
    assert classify_unoffered_tool(
        name="search_invoices",
        in_registry=True,
        authorized=True,
        in_ranked_candidates=True,
        in_offered_schemas=False,
    ) == EVENT_SCHEMA_MISS


def test_unauthorized_is_not_rediscovered():
    state = RediscoveryState()
    plan = plan_unknown_tool_recovery(
        "delete_invoice",
        state,
        authorized_names={"search_invoices"},
        offered_names={"search_invoices"},
        ranked_names={"search_invoices"},
        in_registry=True,
    )
    assert plan["rediscovery"] is False
    assert plan["reason"] == "unauthorized_or_unknown"
    assert plan["kind"] == EVENT_AUTHORIZATION_FAILURE
    assert state.force_names == set()


def test_authorized_unoffered_is_retrieval_miss_not_security():
    reset_metrics_for_tests()
    reset_discovery_telemetry_for_tests()
    state = RediscoveryState()
    plan = plan_unknown_tool_recovery(
        "search_invoices",
        state,
        authorized_names={"search_invoices", "list_accounts"},
        offered_names={"list_accounts"},
        ranked_names={"list_accounts"},
        in_registry=True,
    )
    assert plan["rediscovery"] is True
    assert plan["kind"] == EVENT_RETRIEVAL_MISS
    snap = metric_snapshot()
    assert snap.get(EVENT_RETRIEVAL_MISS, 0) >= 1
    assert snap.get(EVENT_AUTHORIZATION_FAILURE, 0) == 0


def test_schema_miss_when_ranked_but_not_loaded():
    state = RediscoveryState()
    plan = plan_unknown_tool_recovery(
        "search_invoices",
        state,
        authorized_names={"search_invoices"},
        offered_names=set(),
        ranked_names={"search_invoices"},
        in_registry=True,
    )
    assert plan["kind"] == EVENT_SCHEMA_MISS
    assert plan["rediscovery"] is True


def test_rediscovery_max_one_then_failed():
    state = RediscoveryState()
    first = plan_unknown_tool_recovery(
        "search_invoices",
        state,
        authorized_names={"search_invoices"},
        offered_names=set(),
        ranked_names=set(),
        in_registry=True,
    )
    second = plan_unknown_tool_recovery(
        "search_invoices",
        state,
        authorized_names={"search_invoices"},
        offered_names=set(),
        ranked_names=set(),
        in_registry=True,
    )
    assert first["rediscovery"] is True
    assert second["rediscovery"] is False
    assert second["reason"] == "retry_exhausted"


def test_live_decision_holds_without_samples():
    reset_discovery_telemetry_for_tests()
    snap = telemetry_snapshot()
    assert snap["live_requests"] == 0
    assert snap["decision"] == "HOLD"
    assert recommend_canary_decision(
        live_control=10,
        live_experiment=10,
        min_samples=ADAPTIVE_K_MIN_LIVE_SAMPLES,
    ) == "HOLD"
    assert recommend_canary_decision(
        live_control=ADAPTIVE_K_MIN_LIVE_SAMPLES,
        live_experiment=ADAPTIVE_K_MIN_LIVE_SAMPLES,
        min_samples=ADAPTIVE_K_MIN_LIVE_SAMPLES,
    ) == "REVIEW"


def test_telemetry_strips_sensitive_fields_and_records_k():
    reset_discovery_telemetry_for_tests()
    observe_discovery_request(
        arm="experiment",
        channel="chat",
        mutation="read",
        adaptive_enabled=True,
        recommended_k=10,
        effective_k=10,
        schema_count=10,
        schema_tokens=1500,
        query_hash="abc",
        capability="financial.invoice",
    )
    record_unoffered_tool("search_invoices", kind=EVENT_RETRIEVAL_MISS, arm="experiment")
    snap = telemetry_snapshot()
    assert snap["experiment"]["requests"] == 1
    assert snap["experiment"]["average_k"] == 10
    assert snap["k_histogram"]["10"] == 1
    assert "query" not in str(snap)
    assert "user_id" not in str(snap)


def test_chat_crm_ticket_workflow_channels_still_use_get_available_functions():
    from pathlib import Path

    root = Path(__file__).resolve().parents[1]
    service = (root / "app" / "services" / "ai" / "ai_service.py").read_text(
        encoding="utf-8"
    )
    assert "apply_adaptive=assignment.enabled" in service
    assert "observe_discovery_request(" in service
