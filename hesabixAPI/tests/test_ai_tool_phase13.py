"""Phase 13 — production evidence gate. Does not invent live traffic."""
from __future__ import annotations

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    CANDIDATE_RETRIEVAL_N,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_CANARY_SALT,
    INDEXED_CANDIDATE_FALLBACK,
    INDEXED_CANDIDATE_KILL_SWITCH,
    INDEXED_CANDIDATE_RETRIEVAL,
    INDEXED_CANDIDATE_ROLLOUT_PERCENT,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_ops_metrics import reset_metrics_for_tests
from app.services.ai.ai_tool_canary import (
    INDEXED_ROLLOUT_LADDER,
    indexed_kill_switch_on,
    propose_indexed_rollout,
    recommend_indexed_promotion,
    resolve_indexed_assignment,
    stable_canary_bucket,
    wilson_ci,
)
from app.services.ai.ai_tool_discovery import discover_tools
from app.services.ai.ai_tool_discovery_telemetry import (
    EVENT_INDEXED_EXPOSURE,
    EVENT_INDEXED_RETRIEVAL_EMPTY,
    EVENT_INDEXED_RETRIEVAL_HIT,
    EVENT_INDEXED_RETRIEVAL_MISS,
    EVENT_RETRIEVAL_MISS,
    classify_unoffered_tool,
    mark_first_pass,
    observe_discovery_request,
    observe_indexed_exposure,
    observe_tool_call_result,
    record_counter,
    reset_discovery_telemetry_for_tests,
    telemetry_snapshot,
)
from app.services.ai.ai_tool_index_health import (
    FALLBACK_EMPTY,
    FALLBACK_ERROR,
    FALLBACK_LOW,
    FALLBACK_REASONS,
    canonical_fallback_reason,
    tool_index_health,
)
from app.services.ai.ai_tool_indexed_evidence import (
    SOURCE_PRODUCTION_LIVE,
    live_indexed_evidence,
    production_event,
    strip_privacy,
)


def test_phase13_flags_stay_on_five_percent_canary():
    assert INDEXED_CANDIDATE_RETRIEVAL is False
    assert INDEXED_CANDIDATE_ROLLOUT_PERCENT == 5
    assert INDEXED_CANDIDATE_FALLBACK is True
    assert INDEXED_CANDIDATE_KILL_SWITCH is False
    assert ADAPTIVE_DISCOVERY_K is False
    assert ADAPTIVE_K_ROLLOUT_PERCENT == 0
    assert HYBRID_TOOL_DISCOVERY is False
    assert PROGRESSIVE_SCHEMA_LOADING is False
    assert MAX_TOOLS_PER_REQUEST == 48
    assert MAX_TOOLS_AUTONOMOUS == 128
    assert CANDIDATE_RETRIEVAL_N == 100
    assert INDEXED_ROLLOUT_LADDER == (5, 10, 25, 50, 100)


def test_assignment_stable_and_salt_starts_new_experiment():
    first = resolve_indexed_assignment(business_id=42, user_id=7)
    second = resolve_indexed_assignment(business_id=42, user_id=7)
    assert first.arm == second.arm
    assert first.bucket == second.bucket
    v1 = stable_canary_bucket(
        business_id=42, user_id=7, salt=INDEXED_CANDIDATE_CANARY_SALT
    )
    v2 = stable_canary_bucket(
        business_id=42, user_id=7, salt="indexed-retrieval-v2"
    )
    assert v1 == first.bucket
    changed = 0
    for bid in range(1, 80):
        a = stable_canary_bucket(
            business_id=bid, user_id=3, salt=INDEXED_CANDIDATE_CANARY_SALT
        )
        b = stable_canary_bucket(
            business_id=bid, user_id=3, salt="indexed-retrieval-v2"
        )
        if a != b:
            changed += 1
    assert changed > 20
    blob = str(first.to_log_dict())
    assert "42" not in blob
    assert "user_id" not in blob


def _first_experiment_business() -> int:
    for bid in range(1, 400):
        assigned = resolve_indexed_assignment(business_id=bid, user_id=1)
        if assigned.enabled:
            return bid
    raise AssertionError("no experiment bucket in 1..399")


def test_kill_switch_turns_canary_into_control_without_restart(monkeypatch):
    bid = _first_experiment_business()
    live = resolve_indexed_assignment(business_id=bid, user_id=1)
    assert live.enabled is True
    assert live.arm == "experiment"
    monkeypatch.setenv("HESABIX_INDEXED_CANDIDATE_KILL", "1")
    assert indexed_kill_switch_on() is True
    killed = resolve_indexed_assignment(business_id=bid, user_id=1)
    assert killed.enabled is False
    assert killed.arm == "control"
    assert killed.killed is True
    monkeypatch.delenv("HESABIX_INDEXED_CANDIDATE_KILL")
    restored = resolve_indexed_assignment(business_id=bid, user_id=1)
    assert restored.enabled is True


def test_rollout_controller_does_not_auto_promote():
    proposal = propose_indexed_rollout(10)
    assert proposal["applied"] is False
    assert proposal["auto_promotion"] is False
    assert INDEXED_CANDIDATE_ROLLOUT_PERCENT == 5
    assert proposal["current_percent"] == 5
    assert proposal["requested_percent"] == 10


def test_exposure_event_is_privacy_safe():
    reset_metrics_for_tests()
    reset_discovery_telemetry_for_tests()
    observe_indexed_exposure(
        arm="experiment",
        channel="chat",
        mode="analyzer",
        effective_candidate_retrieval="indexed",
    )
    snap = telemetry_snapshot()
    assert snap["indexed_candidate_exposure"] >= 1
    payload = str(snap)
    assert "user_id" not in payload
    assert "business_id" not in payload
    event = production_event(
        arm="experiment",
        channel="chat",
        mode="analyzer",
        user_id=99,
        business_id=12,
        query="مانده علی",
        candidate_count=40,
        fallback=False,
        index_success=True,
        task_success=None,
    )
    assert "user_id" not in event
    assert "query" not in event
    assert event["arm"] == "experiment"
    assert event["task_success"] is None
    assert strip_privacy({"user_id": 1, "arm": "control"}) == {"arm": "control"}


def test_arm_counters_and_hit_empty_split():
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
        effective_candidate_retrieval="full_authorized",
    )
    observe_discovery_request(
        arm="control",
        channel="workflow",
        mutation="write",
        adaptive_enabled=False,
        recommended_k=128,
        effective_k=128,
        schema_count=128,
        indexed_arm="experiment",
        indexed_enabled=True,
        indexed_fallback=True,
        indexed_fallback_reason=FALLBACK_EMPTY,
        candidate_count=100,
        final_tool_count=48,
        index_success=False,
        execution_mode="supervised",
        effective_candidate_retrieval="full_authorized",
    )
    record_counter(EVENT_INDEXED_RETRIEVAL_HIT, {"channel": "chat"})
    record_counter(EVENT_INDEXED_RETRIEVAL_EMPTY, {"channel": "chat"})
    record_counter(EVENT_INDEXED_RETRIEVAL_MISS, {"channel": "chat"})
    snap = telemetry_snapshot()
    assert snap["control_requests"] == 1
    assert snap["experiment_requests"] == 1
    assert snap["experiment_enabled_requests"] == 1
    assert snap["experiment_fallback_requests"] == 1
    assert snap["indexed_retrieval_hit"] >= 1
    assert snap["indexed_retrieval_empty"] >= 1
    assert snap["indexed_retrieval_miss"] >= 1
    assert EVENT_INDEXED_RETRIEVAL_MISS != EVENT_RETRIEVAL_MISS


def test_fallback_taxonomy_is_canonical():
    assert FALLBACK_EMPTY == "empty"
    assert FALLBACK_LOW == "low_candidate_quality"
    assert FALLBACK_ERROR == "index_error"
    assert canonical_fallback_reason("empty_index") == "empty"
    assert canonical_fallback_reason("low_candidate_recall_signal") == "low_candidate_quality"
    assert set(FALLBACK_REASONS) == {
        "empty",
        "low_candidate_quality",
        "stale_index",
        "index_error",
        "index_inconsistency",
        "unknown",
    }


def test_index_miss_is_not_adaptive_retrieval_miss():
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
    assert classify_unoffered_tool(
        name="search_invoices",
        in_registry=True,
        authorized=True,
        in_ranked_candidates=False,
        in_offered_schemas=False,
        indexed_enabled=False,
        in_candidate_pool=True,
    ) == EVENT_RETRIEVAL_MISS


def test_fallback_success_is_not_index_success():
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
        indexed_fallback_reason=FALLBACK_EMPTY,
        index_success=False,
        execution_mode="analyzer",
    )
    mark_first_pass("control", True, indexed_arm="experiment")
    live = live_indexed_evidence()
    assert live["source"] == SOURCE_PRODUCTION_LIVE
    assert live["index_success"] == 0.0
    assert live["task_success"] is None
    assert live["first_pass_without_rediscovery"] == 1.0
    assert live["task_success_source"] is None


def test_live_evidence_does_not_use_gold_or_fabricate_empty_rates():
    reset_discovery_telemetry_for_tests()
    live = live_indexed_evidence()
    blob = str(live)
    assert live["source"] == SOURCE_PRODUCTION_LIVE
    assert live["offline_gold_mixed"] is False
    assert "candidate_recall" not in live
    assert "Recall@" not in blob
    assert live.get("offline_gold") is None
    assert live["control_requests"] == 0
    assert live["experiment_requests"] == 0
    assert live["task_success"] is None
    assert live["indexed_hit_rate"] is None
    assert live["latency"]["p50"] is None
    assert live["latency"]["p95"] is None
    assert live["latency"]["p99"] is None
    assert live["promotion"]["decision"] == "HOLD"
    assert live["promotion"]["auto_promotion"] is False


def test_empty_index_still_falls_back_inside_authorized():
    reset_metrics_for_tests()
    reset_discovery_telemetry_for_tests()
    offer = discover_tools(
        "هوا امروز چطوره؟",
        permissioned_names=["list_accounts", "search_invoices"],
        execution_mode="analyzer",
        apply_indexed=True,
        channel="ticket",
    )
    assert offer.indexed_enabled is True
    assert offer.indexed_fallback is True
    assert offer.indexed_fallback_reason == FALLBACK_EMPTY
    assert offer.index_success is False
    assert offer.effective_candidate_retrieval == "full_authorized"
    assert offer.names() <= {"list_accounts", "search_invoices"}
    assert offer.index_latency_ms >= 0
    assert offer.rank_latency_ms >= 0


def test_index_health_reports_manifest_counts():
    health = tool_index_health()
    assert health["active_tool_count"] >= 1
    assert health["indexed_tool_count"] >= 1
    assert "stale_tool_count" in health
    assert "disabled_tool_count" in health
    assert "last_refresh" in health
    assert "healthy" in health


def test_high_risk_outcomes_are_split_by_arm():
    reset_discovery_telemetry_for_tests()
    observe_tool_call_result(
        "create_invoice",
        {"ok": True},
        indexed_arm="experiment",
        mutation="write",
    )
    observe_tool_call_result(
        "delete_invoice",
        {"error": "APPROVAL_REQUIRED"},
        indexed_arm="control",
        mutation="destructive",
    )
    observe_tool_call_result(
        "delete_invoice",
        {"error": "APPROVAL_MISMATCH"},
        indexed_arm="experiment",
        mutation="destructive",
    )
    snap = telemetry_snapshot()
    ops = snap["high_risk_operations"]
    assert ops["write"]["experiment"]["success"] >= 1
    assert ops["delete"]["control"]["approval"] >= 1
    assert ops["delete"]["experiment"]["unexpected_rejection"] >= 1


def test_promotion_holds_without_live_traffic():
    reset_discovery_telemetry_for_tests()
    decision = recommend_indexed_promotion(telemetry_snapshot())
    assert decision["decision"] == "HOLD"
    assert decision["allow_operator_promote"] is False
    lo, hi = wilson_ci(0, 0)
    assert lo is None and hi is None


def test_exposure_event_name():
    assert EVENT_INDEXED_EXPOSURE == "indexed_candidate_exposure"
