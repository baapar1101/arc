"""Phase 12 — live indexed-retrieval canary at 5%, other planes unchanged."""
from __future__ import annotations

import os

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    HYBRID_TOOL_DISCOVERY,
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
    compare_rate,
    indexed_kill_switch_on,
    recommend_indexed_promotion,
    resolve_adaptive_assignment,
    resolve_indexed_assignment,
    wilson_ci,
)
from app.services.ai.ai_tool_discovery import discover_tools
from app.services.ai.ai_tool_discovery_telemetry import (
    EVENT_INDEX_FALLBACK,
    EVENT_UNAUTHORIZED_CANDIDATE,
    reset_discovery_telemetry_for_tests,
    telemetry_snapshot,
)
from app.services.ai.ai_tool_index_health import (
    FALLBACK_EMPTY,
    FALLBACK_STALE,
    index_consistency_ok,
    refresh_stale_authorized,
)
from app.services.ai.ai_tool_intent import _CATEGORY_TOOLS, _CORE_TOOL_NAMES, _WRITE_TOOLS
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_tool_retrieval_index import ToolRetrievalIndex
from app.services.ai.ai_tool_rollout import RediscoveryState, plan_unknown_tool_recovery
from app.services.ai.ai_tool_spec import ToolManifestEntry


def _catalog() -> set[str]:
    names = set(_CORE_TOOL_NAMES) | set(_WRITE_TOOLS)
    for group in _CATEGORY_TOOLS.values():
        names |= set(group)
    return names


def test_phase12_only_indexed_percent_moves():
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
    adaptive = resolve_adaptive_assignment(business_id=7, user_id=9)
    assert adaptive.enabled is False


def test_five_percent_assignment_is_stable_and_hides_ids():
    first = resolve_indexed_assignment(business_id=42, user_id=7)
    second = resolve_indexed_assignment(business_id=42, user_id=7)
    assert first.arm == second.arm
    assert first.bucket == second.bucket
    assert first.percent == 5
    assert first.enabled == (first.bucket < 5)
    blob = str(first.to_log_dict())
    assert "42" not in blob
    assert "user_id" not in blob
    assert "business_id" not in blob


def test_kill_switch_forces_control_without_adaptive_change(monkeypatch):
    monkeypatch.setenv("HESABIX_INDEXED_CANDIDATE_KILL", "1")
    assert indexed_kill_switch_on() is True
    assigned = resolve_indexed_assignment(business_id=1, user_id=1)
    assert assigned.enabled is False
    assert assigned.killed is True
    assert assigned.percent == 0
    adaptive = resolve_adaptive_assignment(business_id=1, user_id=1)
    assert adaptive.enabled is False
    monkeypatch.delenv("HESABIX_INDEXED_CANDIDATE_KILL")
    monkeypatch.setenv("HESABIX_INDEXED_CANDIDATE_RETRIEVAL", "0")
    assigned = resolve_indexed_assignment(business_id=1, user_id=1)
    assert assigned.enabled is False
    assert assigned.killed is True


def test_empty_index_fallbacks_inside_authorized_and_is_observable():
    reset_metrics_for_tests()
    reset_discovery_telemetry_for_tests()
    offer = discover_tools(
        "هوا امروز چطوره؟",
        permissioned_names=["list_accounts", "search_invoices"],
        execution_mode="analyzer",
        apply_indexed=True,
    )
    assert offer.indexed_enabled is True
    assert offer.indexed_fallback is True
    assert offer.indexed_fallback_reason == FALLBACK_EMPTY
    assert offer.names() <= {"list_accounts", "search_invoices"}
    snap = telemetry_snapshot()
    assert snap["indexed_candidate_fallback"] >= 1
    payload = str(snap)
    assert "user_id" not in payload
    assert "هوا" not in payload


def test_stale_manifest_refreshes_index():
    index = ToolRetrievalIndex()
    old = ToolManifestEntry(
        domains=("financial",),
        aliases=("نام قدیمی فاز دوازده",),
        version="1",
        schema_version="1",
    )
    index.upsert("search_invoices", entry=old)
    assert "search_invoices" in index.lookup_token("قدیمی")
    refreshed, err = refresh_stale_authorized(["search_invoices"], index)
    assert err is None
    assert refreshed >= 1
    current = get_manifest_entry("search_invoices")
    assert current is not None
    assert not index.is_stale(
        "search_invoices",
        search_text=current.search_text("search_invoices"),
        version=current.version,
        schema_version=current.schema_version,
    )


def test_index_consistency_detects_missing_record():
    index = ToolRetrievalIndex()
    assert index_consistency_ok(["search_invoices"], index) is False
    index.upsert("search_invoices")
    assert index_consistency_ok(["search_invoices"], index) is True


def test_inconsistent_index_falls_back_to_authorized_ranker():
    from app.services.ai.ai_tool_retrieval_index import reset_retrieval_index_for_tests
    from app.services.ai import ai_tool_retrieval_index as idxmod

    reset_retrieval_index_for_tests()
    store = idxmod.get_retrieval_index()
    store.remove("search_invoices")
    offer = discover_tools(
        "فاکتور فروش این ماه را پیدا کن",
        permissioned_names=["search_invoices", "list_accounts"],
        execution_mode="analyzer",
        apply_indexed=True,
    )
    assert offer.indexed_fallback is True
    assert offer.indexed_fallback_reason in {"index_inconsistency", FALLBACK_STALE}
    assert "search_invoices" in offer.names() or offer.candidate_pool
    reset_retrieval_index_for_tests()


def test_write_tools_remain_protected_on_indexed_path():
    catalog = _catalog()
    control = discover_tools(
        "فاکتور جدید ایجاد کن",
        permissioned_names=catalog,
        execution_mode="supervised",
        apply_indexed=False,
        protected_names={"create_invoice"},
    )
    experiment = discover_tools(
        "فاکتور جدید ایجاد کن",
        permissioned_names=catalog,
        execution_mode="supervised",
        apply_indexed=True,
        protected_names={"create_invoice"},
    )
    assert "create_invoice" in control.names()
    assert "create_invoice" in experiment.names()


def test_unauthorized_is_not_rediscovered_on_indexed_path():
    plan = plan_unknown_tool_recovery(
        "delete_invoice",
        RediscoveryState(),
        authorized_names={"search_invoices"},
        offered_names={"search_invoices"},
        ranked_names={"search_invoices"},
        in_registry=True,
        indexed_enabled=True,
        candidate_pool={"search_invoices"},
    )
    assert plan["rediscovery"] is False
    assert plan["kind"] == "authorization_failure"


def test_promotion_holds_without_500_samples():
    reset_discovery_telemetry_for_tests()
    decision = recommend_indexed_promotion(telemetry_snapshot())
    assert decision["decision"] == "HOLD"
    assert decision["case"] == "insufficient_samples"


def test_promotion_rollback_on_unauthorized_candidate():
    reset_discovery_telemetry_for_tests()
    from app.services.ai.ai_tool_discovery_telemetry import record_counter

    record_counter(EVENT_UNAUTHORIZED_CANDIDATE, {"count": 1})
    decision = recommend_indexed_promotion(telemetry_snapshot())
    assert decision["decision"] == "ROLLBACK"
    assert decision["case"] == "D"


def test_wilson_interval_and_rate_comparison_hold_without_n():
    lo, hi = wilson_ci(10, 100)
    assert lo is not None and hi is not None
    assert 0 <= lo <= hi <= 1
    cmp = compare_rate(10, 20, 12, 20)
    assert cmp["enough_for_significance"] is False
    assert cmp["delta"] is not None


def test_fallback_event_name_matches_contract():
    assert EVENT_INDEX_FALLBACK == "indexed_candidate_fallback"
