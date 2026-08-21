"""Production evidence contract for indexed candidate retrieval.

Offline Gold and Production Live are never mixed. Gold Recall is not
Production Recall. Task success is not index success.
"""
from __future__ import annotations

import time
from typing import Any, Dict, Optional

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_FALLBACK,
    INDEXED_CANDIDATE_KILL_SWITCH,
    INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
    INDEXED_CANDIDATE_RETRIEVAL,
    INDEXED_CANDIDATE_ROLLOUT_PERCENT,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_tool_canary import (
    INDEXED_ROLLOUT_LADDER,
    indexed_rollout_status,
    recommend_indexed_promotion,
)

SOURCE_OFFLINE_GOLD = "offline_gold"
SOURCE_PRODUCTION_LIVE = "production_live"
SOURCE_PRODUCTION_CONTROL = "production_control"
SOURCE_PRODUCTION_EXPERIMENT = "production_experiment"
SOURCE_OFFLINE_PERFORMANCE = "offline_performance_evidence"

# Preserved Phase 10/11 synthetic bench. Not production latency.
OFFLINE_10K_INDEXED_MS = 6
OFFLINE_10K_FULL_RANK_MS = 110

EVENT_EXPOSURE = "indexed_candidate_exposure"

PRODUCTION_EVENT_FIELDS = (
    "timestamp",
    "arm",
    "channel",
    "mode",
    "candidate_count",
    "final_tool_count",
    "index_hit",
    "index_miss",
    "fallback",
    "fallback_reason",
    "discovery_miss",
    "schema_miss",
    "tool_execution_success",
    "task_success",
    "index_success",
    "latency",
    "effective_candidate_retrieval",
    "candidate_retrieval_enabled",
)

_PRIVACY_KEYS = {
    "user_id",
    "business_id",
    "session_id",
    "query",
    "text",
    "content",
    "prompt",
    "amount",
    "invoice_id",
    "person_id",
    "email",
    "phone",
    "national_id",
}


def strip_privacy(payload: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    clean: Dict[str, Any] = {}
    for key, value in dict(payload or {}).items():
        if key in _PRIVACY_KEYS:
            continue
        lowered = str(key).lower()
        if any(part in lowered for part in ("user", "business", "query", "email", "phone")):
            continue
        clean[key] = value
    return clean


def production_event(**fields: Any) -> Dict[str, Any]:
    """Privacy-safe request event. Unknown / PII keys are dropped."""
    raw = strip_privacy(fields)
    event = {name: raw.get(name) for name in PRODUCTION_EVENT_FIELDS}
    event["timestamp"] = raw.get("timestamp") or time.time()
    return event


def empty_live_rates() -> Dict[str, Any]:
    return {
        "source": SOURCE_PRODUCTION_LIVE,
        "control_requests": 0,
        "experiment_requests": 0,
        "experiment_enabled_requests": 0,
        "experiment_fallback_requests": 0,
        "indexed_hit_rate": None,
        "indexed_miss_rate": None,
        "fallback_rate": None,
        "task_success": None,
        "task_success_source": None,
        "index_success": None,
        "tool_execution_success": None,
        "p50": None,
        "p95": None,
        "p99": None,
        "note": "No live production samples in this process. Do not substitute Gold.",
    }


def live_indexed_evidence() -> Dict[str, Any]:
    """Live counters only. Never copies Gold Recall or fabricated task success."""
    from app.services.ai.ai_tool_discovery_telemetry import (
        EVENT_INDEXED_RETRIEVAL_EMPTY,
        EVENT_INDEXED_RETRIEVAL_ERROR,
        EVENT_INDEXED_RETRIEVAL_HIT,
        EVENT_INDEXED_RETRIEVAL_MISS,
        EVENT_INDEXED_RETRIEVAL_STALE,
        EVENT_INDEX_HIT,
        telemetry_snapshot,
    )
    from app.services.ai.ai_tool_index_health import tool_index_health

    snap = telemetry_snapshot()
    counts = dict(snap.get("counters") or {})
    control = dict(snap.get("indexed_control") or {})
    experiment = dict(snap.get("indexed_experiment") or {})
    control_n = int(control.get("requests") or 0)
    experiment_n = int(experiment.get("requests") or 0)
    enabled_n = int(
        counts.get("experiment_enabled_requests")
        or experiment.get("indexed_requests")
        or 0
    )
    fallback_n = int(
        counts.get("experiment_fallback_requests")
        or experiment.get("fallback_requests")
        or 0
    )
    hits = int(counts.get(EVENT_INDEXED_RETRIEVAL_HIT) or counts.get(EVENT_INDEX_HIT) or 0)
    misses = int(counts.get(EVENT_INDEXED_RETRIEVAL_MISS) or 0)
    empty = int(counts.get(EVENT_INDEXED_RETRIEVAL_EMPTY) or 0)
    stale = int(counts.get(EVENT_INDEXED_RETRIEVAL_STALE) or 0)
    errors = int(counts.get(EVENT_INDEXED_RETRIEVAL_ERROR) or 0)
    denom = enabled_n or hits + misses + empty + stale + errors
    hit_rate = round(hits / denom, 4) if denom else None
    miss_rate = round(misses / denom, 4) if denom else None
    fallback_rate = experiment.get("fallback_rate")
    if fallback_rate is None and experiment_n:
        fallback_rate = round(fallback_n / experiment_n, 4)

    first_n = int(counts.get("indexed_first_pass.experiment.total") or 0) + int(
        counts.get("indexed_first_pass.control.total") or 0
    )
    first_ok = int(counts.get("indexed_first_pass.experiment.success") or 0) + int(
        counts.get("indexed_first_pass.control.success") or 0
    )
    task_n = int(counts.get("indexed_task.total") or 0)
    task_ok = int(counts.get("indexed_task.success") or 0)
    task_rate = round(task_ok / task_n, 4) if task_n else None
    tool_ok = int(counts.get("indexed.control.tool_success") or 0) + int(
        counts.get("indexed.experiment.tool_success") or 0
    )
    tool_fail = int(counts.get("indexed.control.tool_failure") or 0) + int(
        counts.get("indexed.experiment.tool_failure") or 0
    )
    tool_n = tool_ok + tool_fail
    index_ok_n = int(counts.get("index_success_true") or 0)
    index_fail_n = int(counts.get("index_success_false") or 0)
    index_n = index_ok_n + index_fail_n
    lat = dict(experiment.get("request_latency") or {}) or dict(
        experiment.get("discovery_latency") or {}
    )
    control_lat = dict(control.get("request_latency") or {}) or dict(
        control.get("discovery_latency") or {}
    )
    live_n = control_n + experiment_n
    p50 = lat.get("p50") if experiment_n else (control_lat.get("p50") if control_n else None)
    p95 = lat.get("p95") if experiment_n else (control_lat.get("p95") if control_n else None)
    p99 = lat.get("p99") if experiment_n else (control_lat.get("p99") if control_n else None)
    if not live_n:
        p50 = p95 = p99 = None

    health = tool_index_health()
    health["index_consistency_failures"] = int(
        counts.get("index_consistency_failure") or snap.get("index_consistency_failure") or 0
    )
    promotion = recommend_indexed_promotion(snap)
    payload = {
        "source": SOURCE_PRODUCTION_LIVE,
        "offline_gold_mixed": False,
        "production_control": {
            "source": SOURCE_PRODUCTION_CONTROL,
            "requests": control_n,
        },
        "production_experiment": {
            "source": SOURCE_PRODUCTION_EXPERIMENT,
            "requests": experiment_n,
        },
        "control_requests": control_n,
        "experiment_requests": experiment_n,
        "live_control_requests": int(counts.get("live_control_requests") or control_n),
        "live_experiment_requests": int(counts.get("live_experiment_requests") or experiment_n),
        "experiment_enabled_requests": enabled_n,
        "experiment_fallback_requests": fallback_n,
        "exposure": int(counts.get(EVENT_EXPOSURE) or counts.get("indexed_candidate_exposure") or 0),
        "indexed_retrieval_hit": hits,
        "indexed_retrieval_miss": misses,
        "indexed_retrieval_empty": empty,
        "indexed_retrieval_stale": stale,
        "indexed_retrieval_error": errors,
        "indexed_hit_rate": hit_rate,
        "indexed_miss_rate": miss_rate,
        "fallback_rate": fallback_rate,
        "fallback_total": int(counts.get("fallback_total") or 0),
        "fallback_empty": int(counts.get("fallback_empty") or 0),
        "fallback_low_candidate_quality": int(counts.get("fallback_low_candidate_quality") or 0),
        "fallback_stale_index": int(counts.get("fallback_stale_index") or 0),
        "fallback_index_error": int(counts.get("fallback_index_error") or 0),
        "fallback_index_inconsistency": int(counts.get("fallback_index_inconsistency") or 0),
        "fallback_reasons": dict(experiment.get("fallback_reasons") or {}),
        "task_success": task_rate,
        "task_success_source": None if not task_n else "explicit_task_completion",
        "first_pass_without_rediscovery": (
            round(first_ok / first_n, 4) if first_n else None
        ),
        "index_success": round(index_ok_n / index_n, 4) if index_n else None,
        "tool_execution_success": round(tool_ok / tool_n, 4) if tool_n else None,
        "tool_execution": dict(snap.get("tool_execution_by_class") or {}),
        "no_match_requests": int(counts.get("no_match_requests") or 0),
        "no_match_false_tool_selection": int(
            counts.get("no_match_false_tool_selection") or 0
        ),
        "security": {
            "authorization_bypass": int(counts.get("unauthorized_candidate") or 0)
            + int(counts.get("unauthorized_rediscovery") or 0),
            "tenant_leakage": int(counts.get("tenant_leakage") or 0),
            "permission_violation": int(counts.get("permission_violation") or 0),
        },
        "latency": {
            "retrieval": {
                "control": control.get("index_latency") or control.get("discovery_latency"),
                "experiment": experiment.get("index_latency")
                or experiment.get("discovery_latency"),
            },
            "end_to_end": {
                "control": control.get("request_latency") or control.get("discovery_latency"),
                "experiment": experiment.get("request_latency")
                or experiment.get("discovery_latency"),
            },
            "discovery": {
                "control": control.get("discovery_latency"),
                "experiment": experiment.get("discovery_latency"),
            },
            "index": {
                "control": control.get("index_latency"),
                "experiment": experiment.get("index_latency"),
            },
            "rank": {
                "control": control.get("rank_latency"),
                "experiment": experiment.get("rank_latency"),
            },
            "total_ai_request": {
                "control": control.get("request_latency"),
                "experiment": experiment.get("request_latency"),
            },
            "p50": p50 if live_n else None,
            "p95": p95 if live_n else None,
            "p99": p99 if live_n else None,
        },
        "by_channel": {
            "control": dict(control.get("by_channel") or {}),
            "experiment": dict(experiment.get("by_channel") or {}),
            "channels": ("chat", "subagent", "crm", "ticket", "workflow"),
        },
        "high_risk": dict(snap.get("high_risk_operations") or {}),
        "index_health": health,
        "comparison": dict(snap.get("comparison") or {}),
        "promotion": promotion,
        "rollout": indexed_rollout_status(),
        "flags": {
            "INDEXED_CANDIDATE_RETRIEVAL": INDEXED_CANDIDATE_RETRIEVAL,
            "INDEXED_CANDIDATE_ROLLOUT_PERCENT": INDEXED_CANDIDATE_ROLLOUT_PERCENT,
            "INDEXED_CANDIDATE_FALLBACK": INDEXED_CANDIDATE_FALLBACK,
            "INDEXED_CANDIDATE_KILL_SWITCH": INDEXED_CANDIDATE_KILL_SWITCH,
            "ADAPTIVE_DISCOVERY_K": ADAPTIVE_DISCOVERY_K,
            "HYBRID_TOOL_DISCOVERY": HYBRID_TOOL_DISCOVERY,
            "PROGRESSIVE_SCHEMA_LOADING": PROGRESSIVE_SCHEMA_LOADING,
            "min_live_samples": INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
            "rollout_ladder": list(INDEXED_ROLLOUT_LADDER),
        },
        "note": (
            "Production Live only. Offline gold metrics are not included. "
            "Empty rates mean no live traffic — HOLD, do not fabricate. "
            "task_success is never inferred from tool_execution_success."
        ),
    }
    if not live_n:
        payload.update(
            {
                "indexed_hit_rate": None,
                "indexed_miss_rate": None,
                "fallback_rate": None,
                "task_success": None,
                "index_success": None,
                "tool_execution_success": None,
            }
        )
    return payload


def offline_performance_evidence() -> Dict[str, Any]:
    return {
        "source": SOURCE_OFFLINE_PERFORMANCE,
        "not_production": True,
        "indexed_10k_ms": OFFLINE_10K_INDEXED_MS,
        "full_rank_10k_ms": OFFLINE_10K_FULL_RANK_MS,
        "note": "Synthetic catalog bench from Phase 10/11. Measure production latency separately.",
    }
