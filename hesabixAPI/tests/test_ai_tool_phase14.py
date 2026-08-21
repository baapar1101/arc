"""Phase 14 — live indexed-retrieval canary validation. No new retrieval engine."""
from __future__ import annotations

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    CANDIDATE_RETRIEVAL_N,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_CHANNEL_HOLD,
    INDEXED_CANDIDATE_FALLBACK,
    INDEXED_CANDIDATE_RETRIEVAL,
    INDEXED_CANDIDATE_ROLLOUT_PERCENT,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_ops_metrics import reset_metrics_for_tests
from app.services.ai.ai_tool_canary import (
    indexed_kill_switch_on,
    propose_indexed_rollout,
    recommend_indexed_promotion,
    resolve_indexed_assignment,
)
from app.services.ai.ai_tool_discovery import discover_tools
from app.services.ai.ai_tool_discovery_telemetry import (
    EVENT_DISCOVERY_MISS,
    EVENT_INDEXED_EXPOSURE,
    EVENT_INDEXED_RETRIEVAL_ERROR,
    EVENT_INDEXED_RETRIEVAL_MISS,
    EVENT_RETRIEVAL_MISS,
    classify_unoffered_tool,
    mark_first_pass,
    observe_discovery_request,
    observe_indexed_exposure,
    observe_task_completion,
    observe_tool_call_result,
    record_indexed_fallback,
    record_indexed_stage_outcome,
    reset_discovery_telemetry_for_tests,
    telemetry_snapshot,
)
from app.services.ai.ai_tool_index_health import FALLBACK_EMPTY, FALLBACK_ERROR, tool_index_health
from app.services.ai.ai_tool_indexed_evidence import (
    SOURCE_PRODUCTION_CONTROL,
    SOURCE_PRODUCTION_EXPERIMENT,
    SOURCE_PRODUCTION_LIVE,
    live_indexed_evidence,
)


def test_phase14_flags_unchanged():
    assert INDEXED_CANDIDATE_RETRIEVAL is False
    assert INDEXED_CANDIDATE_ROLLOUT_PERCENT == 5
    assert INDEXED_CANDIDATE_FALLBACK is True
    assert INDEXED_CANDIDATE_CHANNEL_HOLD == ()
    assert ADAPTIVE_DISCOVERY_K is False
    assert HYBRID_TOOL_DISCOVERY is False
    assert PROGRESSIVE_SCHEMA_LOADING is False
    assert MAX_TOOLS_PER_REQUEST == 48
    assert MAX_TOOLS_AUTONOMOUS == 128
    assert CANDIDATE_RETRIEVAL_N == 100


def test_live_counters_and_three_way_split():
    reset_metrics_for_tests()
    reset_discovery_telemetry_for_tests()
    observe_discovery_request(
        arm="control",
        channel="chat",
        mutation="read",
        adaptive_enabled=False,
        recommended_k=48,
        effective_k=48,
        schema_count=48,
        indexed_arm="control",
        indexed_enabled=False,
        execution_mode="analyzer",
        expects_tools=True,
    )
    observe_discovery_request(
        arm="control",
        channel="crm",
        mutation="read",
        adaptive_enabled=False,
        recommended_k=48,
        effective_k=48,
        schema_count=48,
        indexed_arm="experiment",
        indexed_enabled=True,
        execution_mode="analyzer",
        index_success=True,
        expects_tools=True,
        effective_candidate_retrieval="indexed",
    )
    live = live_indexed_evidence()
    assert live["source"] == SOURCE_PRODUCTION_LIVE
    assert live["production_control"]["source"] == SOURCE_PRODUCTION_CONTROL
    assert live["production_experiment"]["source"] == SOURCE_PRODUCTION_EXPERIMENT
    assert live["live_control_requests"] == 1
    assert live["live_experiment_requests"] == 1
    assert "candidate_recall" not in live
    assert live.get("offline_gold") is None


def test_exposure_includes_candidate_retrieval_enabled():
    reset_metrics_for_tests()
    reset_discovery_telemetry_for_tests()
    observe_indexed_exposure(
        arm="experiment",
        channel="ticket",
        mode="analyzer",
        effective_candidate_retrieval="indexed",
        candidate_retrieval_enabled=True,
    )
    snap = telemetry_snapshot()
    assert snap["indexed_candidate_exposure"] >= 1
    assert EVENT_INDEXED_EXPOSURE == "indexed_candidate_exposure"
    blob = str(snap)
    assert "user_id" not in blob
    assert "business_id" not in blob


def test_indexed_error_and_fallback_taxonomy_are_separate_from_miss():
    reset_metrics_for_tests()
    reset_discovery_telemetry_for_tests()
    record_indexed_stage_outcome(reason=FALLBACK_ERROR, channel="chat", mode="analyzer")
    record_indexed_fallback(
        channel="chat",
        mode="analyzer",
        reason=FALLBACK_EMPTY,
        candidate_count=10,
        latency_ms=1.0,
    )
    snap = telemetry_snapshot()
    assert snap["indexed_retrieval_error"] >= 1
    assert snap["fallback_total"] >= 1
    assert snap["fallback_empty"] >= 1
    assert snap["indexed_retrieval_miss"] == 0
    assert EVENT_INDEXED_RETRIEVAL_MISS != EVENT_DISCOVERY_MISS
    assert EVENT_INDEXED_RETRIEVAL_MISS != EVENT_RETRIEVAL_MISS
    assert EVENT_INDEXED_RETRIEVAL_ERROR == "indexed_retrieval_error"


def test_task_success_not_inferred_from_tool_execution_or_first_pass():
    reset_discovery_telemetry_for_tests()
    observe_discovery_request(
        arm="control",
        channel="chat",
        mutation="read",
        adaptive_enabled=False,
        recommended_k=48,
        effective_k=48,
        schema_count=48,
        indexed_arm="experiment",
        indexed_enabled=True,
        indexed_fallback=True,
        index_success=False,
        execution_mode="analyzer",
    )
    mark_first_pass("control", True, indexed_arm="experiment")
    observe_tool_call_result(
        "search_invoices",
        {"ok": True},
        indexed_arm="experiment",
        mutation="read",
    )
    live = live_indexed_evidence()
    assert live["index_success"] == 0.0
    assert live["task_success"] is None
    assert live["tool_execution_success"] == 1.0
    assert live["first_pass_without_rediscovery"] == 1.0


def test_explicit_task_success_can_coexist_with_index_failure():
    reset_discovery_telemetry_for_tests()
    observe_discovery_request(
        arm="control",
        channel="chat",
        mutation="read",
        adaptive_enabled=False,
        recommended_k=48,
        effective_k=48,
        schema_count=48,
        indexed_arm="experiment",
        indexed_enabled=True,
        indexed_fallback=True,
        index_success=False,
        execution_mode="analyzer",
    )
    observe_task_completion(
        indexed_arm="experiment",
        success=True,
        source="explicit_agent_success",
    )
    live = live_indexed_evidence()
    assert live["index_success"] == 0.0
    assert live["task_success"] == 1.0


def test_no_match_is_counted_separately():
    reset_discovery_telemetry_for_tests()
    observe_discovery_request(
        arm="control",
        channel="chat",
        mutation="read",
        adaptive_enabled=False,
        recommended_k=48,
        effective_k=8,
        schema_count=8,
        indexed_arm="experiment",
        indexed_enabled=True,
        top_score=12,
        execution_mode="analyzer",
        expects_tools=False,
    )
    live = live_indexed_evidence()
    assert live["no_match_requests"] == 1
    assert live["no_match_false_tool_selection"] == 1


def test_tool_execution_split_by_class_and_high_risk_authorization():
    reset_discovery_telemetry_for_tests()
    observe_tool_call_result(
        "search_invoices",
        {"ok": True},
        indexed_arm="control",
        mutation="read",
    )
    observe_tool_call_result(
        "delete_invoice",
        {"error": "READ_ONLY_MODE"},
        indexed_arm="experiment",
        mutation="destructive",
    )
    snap = telemetry_snapshot()
    assert snap["tool_execution_by_class"]["read"]["control"]["success"] >= 1
    assert snap["high_risk_operations"]["delete"]["experiment"]["authorization_failure"] >= 1


def test_channel_hold_forces_control_without_global_kill(monkeypatch):
    monkeypatch.setenv("HESABIX_INDEXED_CANDIDATE_CHANNEL_HOLD", "ticket")
    bid = None
    for i in range(1, 400):
        assigned = resolve_indexed_assignment(business_id=i, user_id=1, channel="chat")
        if assigned.enabled:
            bid = i
            break
    assert bid is not None
    held = resolve_indexed_assignment(business_id=bid, user_id=1, channel="ticket")
    assert held.enabled is False
    assert held.arm == "control"
    assert held.channel_held is True
    assert held.killed is False
    chat = resolve_indexed_assignment(business_id=bid, user_id=1, channel="chat")
    assert chat.enabled is True
    assert indexed_kill_switch_on() is False


def test_kill_switch_still_stops_experiment_without_restart(monkeypatch):
    monkeypatch.setenv("HESABIX_INDEXED_CANDIDATE_KILL", "1")
    assigned = resolve_indexed_assignment(business_id=1, user_id=1, channel="chat")
    assert assigned.enabled is False
    assert assigned.killed is True
    monkeypatch.delenv("HESABIX_INDEXED_CANDIDATE_KILL")
    monkeypatch.setenv("HESABIX_INDEXED_CANDIDATE_RETRIEVAL", "0")
    assigned = resolve_indexed_assignment(business_id=1, user_id=1, channel="chat")
    assert assigned.enabled is False
    assert assigned.killed is True


def test_no_auto_promote_and_zero_traffic_is_hold():
    reset_discovery_telemetry_for_tests()
    proposal = propose_indexed_rollout(10)
    assert proposal["applied"] is False
    assert INDEXED_CANDIDATE_ROLLOUT_PERCENT == 5
    decision = recommend_indexed_promotion(telemetry_snapshot())
    assert decision["decision"] == "HOLD"
    live = live_indexed_evidence()
    assert live["live_control_requests"] == 0
    assert live["live_experiment_requests"] == 0
    assert live["task_success"] is None
    assert live["latency"]["p50"] is None
    assert live["promotion"]["decision"] == "HOLD"


def test_index_health_aliases_and_unoffered_miss_split():
    health = tool_index_health()
    assert health["active_tools"] == health["active_tool_count"]
    assert health["indexed_tools"] == health["indexed_tool_count"]
    assert "index_refresh_age" in health
    assert health["index_health"] in {"healthy", "unhealthy"}
    assert classify_unoffered_tool(
        name="search_invoices",
        in_registry=True,
        authorized=True,
        in_ranked_candidates=True,
        in_offered_schemas=True,
        indexed_enabled=True,
        in_candidate_pool=False,
        indexed_fallback=False,
    ) == EVENT_INDEXED_RETRIEVAL_MISS


def test_empty_index_still_falls_back():
    reset_metrics_for_tests()
    reset_discovery_telemetry_for_tests()
    offer = discover_tools(
        "هوا امروز چطوره؟",
        permissioned_names=["list_accounts", "search_invoices"],
        execution_mode="analyzer",
        apply_indexed=True,
        channel="workflow",
    )
    assert offer.indexed_fallback is True
    assert offer.index_success is False
    assert offer.expects_tools is False
    snap = telemetry_snapshot()
    assert snap["fallback_total"] >= 1 or offer.indexed_fallback_reason == FALLBACK_EMPTY
