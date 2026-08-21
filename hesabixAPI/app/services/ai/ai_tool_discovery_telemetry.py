"""Privacy-safe discovery telemetry for Adaptive K canary.

Never logs query text, financial payloads, user_id, or business_id.
Miss classes are separate events — not one bucket.
"""
from __future__ import annotations

import threading
from collections import defaultdict
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence

from app.services.ai.ai_ops_metrics import log_ai_event

EVENT_DISCOVERY = "tool_discovery_live"
EVENT_RETRIEVAL_MISS = "retrieval_miss"
EVENT_SCHEMA_MISS = "schema_miss"
EVENT_AUTHORIZATION_FAILURE = "authorization_failure"
EVENT_EXECUTION_FAILURE = "execution_failure"
EVENT_EXECUTION_SUCCESS = "tool_execution_success"
EVENT_UNKNOWN_TOOL = "unknown_tool"
EVENT_REDISCOVERY = "tool_rediscovery"
EVENT_REDISCOVERY_RECOVERED = "rediscovery_recovered"
EVENT_REDISCOVERY_FAILED = "rediscovery_failed"
EVENT_EMPTY = "empty_discovery"
EVENT_INDEX_HIT = "candidate_index_hit"
EVENT_INDEX_EMPTY = "candidate_index_empty"
EVENT_INDEX_FALLBACK = "indexed_candidate_fallback"
EVENT_INDEX_CONSISTENCY = "index_consistency_failure"
EVENT_UNAUTHORIZED_CANDIDATE = "unauthorized_candidate"
EVENT_UNAUTHORIZED_REDISCOVERY = "unauthorized_rediscovery"
# Authorized expected tool missing from stage-1 indexed pool (not Adaptive K).
EVENT_INDEXED_RETRIEVAL_MISS = "indexed_retrieval_miss"
EVENT_INDEXED_RETRIEVAL_HIT = "indexed_retrieval_hit"
EVENT_INDEXED_RETRIEVAL_EMPTY = "indexed_retrieval_empty"
EVENT_INDEXED_RETRIEVAL_STALE = "indexed_retrieval_stale"
EVENT_INDEXED_RETRIEVAL_ERROR = "indexed_retrieval_error"
EVENT_INDEXED_EXPOSURE = "indexed_candidate_exposure"
EVENT_TENANT_LEAKAGE = "tenant_leakage"
EVENT_PERMISSION_VIOLATION = "permission_violation"

HIGH_RISK_CLASSES = ("delete", "write", "export", "execute", "financial_mutation")
HIGH_RISK_OUTCOMES = (
    "success",
    "failure",
    "approval",
    "approval_success",
    "unexpected_rejection",
    "authorization_failure",
)
TASK_COMPLETION_SOURCES = (
    "workflow_completion",
    "explicit_agent_success",
    "user_confirmation",
)
EVIDENCE_CHANNELS = ("chat", "subagent", "crm", "ticket", "workflow")

# Umbrella counter for "needed a tool that was not in the offered set"
# but typed events above are the source of truth.
EVENT_DISCOVERY_MISS = "tool_discovery_miss"

_LOCK = threading.Lock()
_MAX_SAMPLES = 4000
_samples: List["DiscoverySample"] = []
_k_values: Dict[str, List[int]] = defaultdict(list)
_counters: Dict[str, int] = defaultdict(int)


@dataclass
class DiscoverySample:
    arm: str
    channel: str
    mutation: str
    adaptive_enabled: bool
    recommended_k: int
    effective_k: int
    schema_count: int
    schema_tokens: int
    latency_ms: float
    top_score: int
    score_gap: int
    high_risk: bool
    first_pass_success: Optional[bool] = None
    indexed_arm: str = "control"
    indexed_enabled: bool = False
    indexed_fallback: bool = False
    indexed_fallback_reason: str = ""
    candidate_count: int = 0
    request_latency_ms: float = 0.0
    execution_mode: str = ""
    index_success: Optional[bool] = None
    index_latency_ms: float = 0.0
    rank_latency_ms: float = 0.0
    final_tool_count: int = 0
    effective_candidate_retrieval: str = "full_authorized"
    expects_tools: Optional[bool] = None


def reset_discovery_telemetry_for_tests() -> None:
    with _LOCK:
        _samples.clear()
        _k_values.clear()
        _counters.clear()


def _inc(name: str, n: int = 1) -> None:
    with _LOCK:
        _counters[name] += n


def _percentile(values: Sequence[int], p: float) -> int:
    if not values:
        return 0
    ordered = sorted(int(v) for v in values)
    if len(ordered) == 1:
        return ordered[0]
    idx = int(round((p / 100.0) * (len(ordered) - 1)))
    idx = max(0, min(len(ordered) - 1, idx))
    return ordered[idx]


def record_counter(event: str, extra: Optional[Dict[str, Any]] = None) -> None:
    payload = dict(extra or {})
    for key in (
        "user_id",
        "business_id",
        "session_id",
        "query",
        "text",
        "content",
        "amount",
        "invoice_id",
        "person_id",
        "email",
        "phone",
    ):
        payload.pop(key, None)
    _inc(event)
    log_ai_event(event, extra=payload)


def observe_discovery_request(
    *,
    arm: str,
    channel: str,
    mutation: str,
    adaptive_enabled: bool,
    recommended_k: int,
    effective_k: int,
    schema_count: int,
    schema_tokens: int = 0,
    latency_ms: float = 0.0,
    top_score: int = 0,
    second_score: int = 0,
    score_gap: int = 0,
    candidate_count: int = 0,
    query_hash: str = "",
    capability: Optional[str] = None,
    confidence_level: str = "",
    strategy: str = "keyword",
    indexed_arm: str = "control",
    indexed_enabled: bool = False,
    indexed_fallback: bool = False,
    indexed_fallback_reason: str = "",
    final_tool_count: int = 0,
    request_latency_ms: float = 0.0,
    execution_mode: str = "",
    index_success: Optional[bool] = None,
    index_latency_ms: float = 0.0,
    rank_latency_ms: float = 0.0,
    effective_candidate_retrieval: str = "",
    expects_tools: Optional[bool] = None,
) -> None:
    high_risk = (mutation or "") in {"write", "destructive", "export", "execute"}
    sample = DiscoverySample(
        arm=arm or "control",
        channel=channel or "chat",
        mutation=mutation or "read",
        adaptive_enabled=bool(adaptive_enabled),
        recommended_k=int(recommended_k or 0),
        effective_k=int(effective_k or 0),
        schema_count=int(schema_count or 0),
        schema_tokens=int(schema_tokens or 0),
        latency_ms=float(latency_ms or 0.0),
        top_score=int(top_score or 0),
        score_gap=int(score_gap or 0),
        high_risk=high_risk,
        indexed_arm=indexed_arm or "control",
        indexed_enabled=bool(indexed_enabled),
        indexed_fallback=bool(indexed_fallback),
        indexed_fallback_reason=indexed_fallback_reason or "",
        candidate_count=int(candidate_count or 0),
        request_latency_ms=float(request_latency_ms or 0.0),
        execution_mode=execution_mode or "",
        index_success=index_success,
        index_latency_ms=float(index_latency_ms or 0.0),
        rank_latency_ms=float(rank_latency_ms or 0.0),
        final_tool_count=int(final_tool_count or schema_count or 0),
        effective_candidate_retrieval=effective_candidate_retrieval
        or ("indexed" if indexed_enabled and not indexed_fallback else "full_authorized"),
        expects_tools=expects_tools,
    )
    with _LOCK:
        _samples.append(sample)
        if len(_samples) > _MAX_SAMPLES:
            del _samples[: len(_samples) - _MAX_SAMPLES]
        _k_values[sample.arm].append(sample.effective_k)
        _counters["discovery_requests"] += 1
        _counters[f"arm.{sample.arm}"] += 1
        _counters[f"channel.{sample.channel}"] += 1
        if high_risk:
            _counters["high_risk_requests"] += 1
        rec = int(recommended_k or 0)
        if rec <= 10:
            _counters["k_bucket.10"] += 1
        elif rec <= 15:
            _counters["k_bucket.15"] += 1
        elif rec <= 20:
            _counters["k_bucket.20"] += 1
        else:
            _counters["k_bucket.fallback"] += 1
        _counters[f"indexed_arm.{sample.indexed_arm}"] += 1
        if sample.indexed_enabled:
            _counters["indexed_enabled"] += 1
        _k_values[f"indexed_lat.{sample.indexed_arm}"].append(
            int(round(sample.latency_ms))
        )
        if sample.request_latency_ms:
            _k_values[f"req_lat.{sample.indexed_arm}"].append(
                int(round(sample.request_latency_ms))
            )
        _counters[f"indexed.{sample.indexed_arm}.channel.{sample.channel}"] += 1
        if sample.indexed_arm == "experiment":
            _counters["experiment_requests"] += 1
            _counters["live_experiment_requests"] += 1
        else:
            _counters["control_requests"] += 1
            _counters["live_control_requests"] += 1
        if sample.indexed_enabled:
            _counters["experiment_enabled_requests"] += 1
        if sample.indexed_arm == "experiment" and sample.indexed_fallback:
            _counters["experiment_fallback_requests"] += 1
            _counters["indexed_fallback"] += 1
            if sample.indexed_fallback_reason:
                _counters[f"indexed_fallback.{sample.indexed_fallback_reason}"] += 1
        elif sample.indexed_fallback:
            _counters["indexed_fallback"] += 1
            if sample.indexed_fallback_reason:
                _counters[f"indexed_fallback.{sample.indexed_fallback_reason}"] += 1
        if sample.index_success is True:
            _counters["index_success_true"] += 1
        elif sample.index_success is False:
            _counters["index_success_false"] += 1
        if sample.index_latency_ms:
            _k_values[f"index_lat.{sample.indexed_arm}"].append(
                int(round(sample.index_latency_ms))
            )
        if sample.rank_latency_ms:
            _k_values[f"rank_lat.{sample.indexed_arm}"].append(
                int(round(sample.rank_latency_ms))
            )
        _counters[f"mutation.{sample.mutation}"] += 1
        _counters[f"indexed.{sample.indexed_arm}.mutation.{sample.mutation}"] += 1
        if sample.high_risk:
            _counters[f"high_risk.{_risk_class(sample.mutation)}.{sample.indexed_arm}"] += 1
        if sample.expects_tools is False:
            _counters["no_match_requests"] += 1
            _counters[f"no_match.{sample.indexed_arm}"] += 1
            if sample.top_score > 4 and sample.schema_count > 0:
                _counters["no_match_false_tool_selection"] += 1
                _counters[f"no_match_false_tool_selection.{sample.indexed_arm}"] += 1
    record_counter(
        EVENT_DISCOVERY,
        {
            "adaptive_enabled": bool(adaptive_enabled),
            "adaptive_arm": arm,
            "recommended_k": int(recommended_k or 0),
            "effective_k": int(effective_k or 0),
            "top_score": int(top_score or 0),
            "second_score": int(second_score or 0),
            "score_gap": int(score_gap or 0),
            "candidate_count": int(candidate_count or 0),
            "schema_count": int(schema_count or 0),
            "schema_tokens": int(schema_tokens or 0),
            "channel": channel,
            "mutation": mutation,
            "capability": capability,
            "confidence_level": confidence_level,
            "strategy": strategy,
            "query_hash": query_hash or None,
            "latency_ms": latency_ms,
            "high_risk": high_risk,
            "indexed_arm": indexed_arm or "control",
            "indexed_enabled": bool(indexed_enabled),
            "indexed_fallback": bool(indexed_fallback),
            "indexed_fallback_reason": indexed_fallback_reason or None,
            "final_tool_count": int(final_tool_count or schema_count or 0),
            "request_latency_ms": float(request_latency_ms or 0.0),
            "execution_mode": execution_mode or None,
            "index_success": index_success,
            "index_latency_ms": float(index_latency_ms or 0.0),
            "rank_latency_ms": float(rank_latency_ms or 0.0),
            "effective_candidate_retrieval": sample.effective_candidate_retrieval,
        },
    )
    observe_indexed_exposure(
        arm=sample.indexed_arm,
        channel=sample.channel,
        mode=sample.execution_mode,
        effective_candidate_retrieval=sample.effective_candidate_retrieval,
        candidate_retrieval_enabled=bool(sample.indexed_enabled),
    )


def _risk_class(mutation: str) -> str:
    mapping = {
        "destructive": "delete",
        "write": "write",
        "export": "export",
        "execute": "execute",
    }
    return mapping.get((mutation or "").strip(), "write")


def observe_indexed_exposure(
    *,
    arm: str,
    channel: str,
    mode: str,
    effective_candidate_retrieval: str,
    candidate_retrieval_enabled: Optional[bool] = None,
) -> None:
    enabled = (
        bool(candidate_retrieval_enabled)
        if candidate_retrieval_enabled is not None
        else (effective_candidate_retrieval == "indexed")
    )
    record_counter(
        EVENT_INDEXED_EXPOSURE,
        {
            "arm": arm or "control",
            "channel": channel or "chat",
            "mode": mode or None,
            "effective_candidate_retrieval": effective_candidate_retrieval
            or "full_authorized",
            "candidate_retrieval_enabled": enabled,
        },
    )


def record_indexed_stage_outcome(
    *,
    reason: str = "",
    channel: str,
    mode: str,
) -> None:
    from app.services.ai.ai_tool_index_health import (
        FALLBACK_EMPTY,
        FALLBACK_ERROR,
        FALLBACK_STALE,
        canonical_fallback_reason,
    )

    extra = {"channel": channel or "chat", "mode": mode or None}
    if not reason:
        record_counter(EVENT_INDEX_HIT, extra)
        record_counter(EVENT_INDEXED_RETRIEVAL_HIT, extra)
        return
    canon = canonical_fallback_reason(reason)
    if canon == FALLBACK_EMPTY:
        record_counter(EVENT_INDEX_EMPTY, extra)
        record_counter(EVENT_INDEXED_RETRIEVAL_EMPTY, extra)
    elif canon == FALLBACK_STALE:
        record_counter(EVENT_INDEXED_RETRIEVAL_STALE, extra)
    elif canon == FALLBACK_ERROR:
        record_counter(EVENT_INDEXED_RETRIEVAL_ERROR, extra)


def record_indexed_fallback(
    *,
    channel: str,
    mode: str,
    reason: str,
    candidate_count: int,
    latency_ms: float,
) -> None:
    from app.services.ai.ai_tool_index_health import canonical_fallback_reason

    canon = canonical_fallback_reason(reason)
    _inc("fallback_total")
    _inc(f"fallback_{canon}")
    record_counter(
        EVENT_INDEX_FALLBACK,
        {
            "channel": channel or "chat",
            "mode": mode or None,
            "reason": canon,
            "fallback_reason": canon,
            "candidate_count": int(candidate_count or 0),
            "latency": round(float(latency_ms or 0.0), 3),
        },
    )


def observe_request_latency(
    *,
    indexed_arm: str,
    latency_ms: float,
    channel: str = "",
) -> None:
    with _LOCK:
        _counters["turn_latency_samples"] += 1
        key = f"turn_latency.{indexed_arm or 'control'}"
        _k_values.setdefault(key, []).append(int(round(float(latency_ms or 0.0))))
    record_counter(
        "tool_request_latency",
        {
            "indexed_arm": indexed_arm or "control",
            "latency_ms": round(float(latency_ms or 0.0), 3),
            "channel": channel or None,
        },
    )


def classify_unoffered_tool(
    *,
    name: str,
    in_registry: bool,
    authorized: bool,
    in_ranked_candidates: bool,
    in_offered_schemas: bool,
    indexed_enabled: bool = False,
    in_candidate_pool: Optional[bool] = None,
    indexed_fallback: bool = False,
) -> str:
    if not in_registry:
        return EVENT_UNKNOWN_TOOL
    if not authorized:
        return EVENT_AUTHORIZATION_FAILURE
    if (
        indexed_enabled
        and not indexed_fallback
        and in_candidate_pool is False
    ):
        return EVENT_INDEXED_RETRIEVAL_MISS
    if not in_ranked_candidates:
        return EVENT_RETRIEVAL_MISS
    if not in_offered_schemas:
        return EVENT_SCHEMA_MISS
    return EVENT_UNKNOWN_TOOL


def record_unoffered_tool(
    name: str,
    *,
    kind: str,
    rediscovery: bool = False,
    channel: str = "",
    arm: str = "",
) -> None:
    extra = {
        "tool": name,
        "kind": kind,
        "rediscovery": bool(rediscovery),
        "channel": channel or None,
        "adaptive_arm": arm or None,
    }
    record_counter(kind, extra)
    if kind in {
        EVENT_RETRIEVAL_MISS,
        EVENT_SCHEMA_MISS,
        EVENT_INDEXED_RETRIEVAL_MISS,
    }:
        record_counter(EVENT_DISCOVERY_MISS, extra)


_SKIP_EXECUTION_ERRORS = frozenset(
    {
        "UNKNOWN_TOOL",
        "APPROVAL_REQUIRED",
        "APPROVAL_MISMATCH",
        "READ_ONLY_MODE",
    }
)


def observe_tool_call_result(
    name: str,
    result: Any,
    *,
    last_miss: str = "",
    indexed_arm: str = "",
    mutation: str = "",
) -> None:
    """Record execution success/failure. Discovery misses are separate events."""
    payload = result if isinstance(result, dict) else {}
    error = str(payload.get("error") or "")
    ok = payload.get("ok", True) is not False and not error
    record_high_risk_outcome(
        name,
        indexed_arm=indexed_arm or "control",
        mutation=mutation,
        error=error,
        ok=ok,
    )
    if error in _SKIP_EXECUTION_ERRORS:
        if last_miss and name == last_miss and error != "UNKNOWN_TOOL":
            record_rediscovery_outcome(name, recovered=True)
        return
    record_execution_outcome(
        name,
        ok=bool(ok),
        error=error,
        indexed_arm=indexed_arm,
        mutation=mutation,
    )
    if last_miss and name == last_miss:
        record_rediscovery_outcome(name, recovered=True)


def record_high_risk_outcome(
    name: str,
    *,
    indexed_arm: str,
    mutation: str,
    error: str,
    ok: bool,
) -> None:
    classes = high_risk_classes_for(name, mutation)
    if not classes:
        return
    if error == "APPROVAL_REQUIRED":
        outcome = "approval"
    elif error == "APPROVAL_MISMATCH":
        outcome = "unexpected_rejection"
    elif error in {"READ_ONLY_MODE", "AUTHORIZATION_FAILURE", "UNAUTHORIZED"}:
        outcome = "authorization_failure"
    elif ok:
        outcome = "success"
    else:
        outcome = "failure"
    arm = indexed_arm or "control"
    for cls in classes:
        _inc(f"high_risk.{cls}.{arm}.{outcome}")
        if outcome == "approval":
            _inc(f"high_risk.{cls}.{arm}.approval_success")


def high_risk_classes_for(name: str, mutation: str) -> tuple:
    from app.services.ai.ai_tool_manifest import get_manifest_entry

    found = []
    mut = (mutation or "").strip()
    side = ""
    domains: tuple = ()
    entry = get_manifest_entry(name) if name else None
    if entry is not None:
        side = entry.side_effect or ""
        domains = tuple(entry.domains or ())
    if mut == "destructive" or side == "delete" or str(name).startswith("delete_"):
        found.append("delete")
    elif mut == "export" or side == "export" or str(name).startswith("export_"):
        found.append("export")
    elif mut == "execute" or side == "execute":
        found.append("execute")
    elif mut == "write" or side == "write":
        found.append("write")
    if "financial" in domains and (
        "write" in found or "delete" in found or "execute" in found
    ):
        found.append("financial_mutation")
    return tuple(found)


def record_execution_outcome(
    name: str,
    *,
    ok: bool,
    error: str = "",
    indexed_arm: str = "",
    mutation: str = "",
) -> None:
    cls = _exec_class(mutation)
    if ok:
        record_counter(EVENT_EXECUTION_SUCCESS, {"tool": name, "mutation_class": cls})
        if indexed_arm:
            _inc(f"indexed.{indexed_arm}.tool_success")
            _inc(f"indexed.{indexed_arm}.tool_success.{cls}")
    else:
        record_counter(
            EVENT_EXECUTION_FAILURE,
            {"tool": name, "error": (error or "TOOL_ERROR")[:80], "mutation_class": cls},
        )
        if indexed_arm:
            _inc(f"indexed.{indexed_arm}.tool_failure")
            _inc(f"indexed.{indexed_arm}.tool_failure.{cls}")


def _exec_class(mutation: str) -> str:
    mapping = {
        "destructive": "delete",
        "write": "write",
        "export": "export",
        "execute": "execute",
        "read": "read",
    }
    return mapping.get((mutation or "").strip(), "read")


def record_rediscovery_queued(name: str, *, retry: int, max_retries: int) -> None:
    record_counter(
        EVENT_REDISCOVERY,
        {"tool": name, "retry": retry, "max": max_retries},
    )


def record_rediscovery_outcome(name: str, *, recovered: bool) -> None:
    event = EVENT_REDISCOVERY_RECOVERED if recovered else EVENT_REDISCOVERY_FAILED
    record_counter(event, {"tool": name})


def mark_first_pass(arm: str, success: bool, indexed_arm: str = "") -> None:
    with _LOCK:
        _counters["first_pass_total"] += 1
        if success:
            _counters["first_pass_success"] += 1
        _counters[f"first_pass.{arm}.total"] += 1
        if success:
            _counters[f"first_pass.{arm}.success"] += 1
        idx_arm = indexed_arm or "control"
        _counters[f"indexed_first_pass.{idx_arm}.total"] += 1
        if success:
            _counters[f"indexed_first_pass.{idx_arm}.success"] += 1
        _counters["task_completion_total"] += 1
        if success:
            _counters["task_completion_success"] += 1


def observe_task_completion(
    *,
    indexed_arm: str,
    success: bool,
    source: str,
) -> None:
    """Explicit task signal only. Never inferred from tool_execution_success."""
    if source not in TASK_COMPLETION_SOURCES:
        return
    arm = indexed_arm or "control"
    with _LOCK:
        _counters["indexed_task.total"] += 1
        _counters[f"indexed_task.{arm}.total"] += 1
        if success:
            _counters["indexed_task.success"] += 1
            _counters[f"indexed_task.{arm}.success"] += 1
    record_counter(
        "indexed_task_completion",
        {"indexed_arm": arm, "success": bool(success), "source": source},
    )


def telemetry_snapshot() -> Dict[str, Any]:
    with _LOCK:
        samples = list(_samples)
        k_by_arm = {arm: list(vals) for arm, vals in _k_values.items()}
        counts = dict(_counters)

    def arm_stats(arm: str) -> Dict[str, Any]:
        vals = k_by_arm.get(arm) or []
        toks = [s.schema_tokens for s in samples if s.arm == arm]
        lats = [s.latency_ms for s in samples if s.arm == arm]
        n = len(vals)
        return {
            "requests": n,
            "average_k": round(sum(vals) / n, 2) if n else 0.0,
            "p50_k": _percentile(vals, 50),
            "p95_k": _percentile(vals, 95),
            "avg_schema_tokens": round(sum(toks) / len(toks)) if toks else 0,
            "avg_latency_ms": round(sum(lats) / len(lats), 3) if lats else 0.0,
        }

    queued = counts.get(EVENT_REDISCOVERY, 0)
    recovered = counts.get(EVENT_REDISCOVERY_RECOVERED, 0)
    first_total = counts.get("first_pass_total", 0)
    first_ok = counts.get("first_pass_success", 0)
    control = arm_stats("control")
    experiment = arm_stats("experiment")
    from app.services.ai.ai_constants import (
        ADAPTIVE_K_MIN_LIVE_SAMPLES,
        INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
    )
    from app.services.ai.ai_tool_canary import recommend_canary_decision

    channels: Dict[str, int] = defaultdict(int)
    high_risk_by_arm: Dict[str, int] = defaultdict(int)
    indexed_by_arm: Dict[str, List["DiscoverySample"]] = defaultdict(list)
    for sample in samples:
        channels[sample.channel] += 1
        if sample.high_risk:
            high_risk_by_arm[sample.arm] += 1
        indexed_by_arm[sample.indexed_arm].append(sample)
    decision = recommend_canary_decision(
        live_control=control["requests"],
        live_experiment=experiment["requests"],
        min_samples=ADAPTIVE_K_MIN_LIVE_SAMPLES,
    )

    def indexed_stats(arm: str) -> Dict[str, Any]:
        rows = indexed_by_arm.get(arm) or []
        lats = [s.latency_ms for s in rows]
        req = [s.request_latency_ms for s in rows if s.request_latency_ms]
        cands = [s.candidate_count for s in rows]
        n = len(rows)
        fb = sum(1 for s in rows if s.indexed_fallback)
        first_n = counts.get(f"indexed_first_pass.{arm}.total", 0)
        first_ok_arm = counts.get(f"indexed_first_pass.{arm}.success", 0)
        reasons: Dict[str, int] = defaultdict(int)
        channels_arm: Dict[str, int] = defaultdict(int)
        mutations: Dict[str, int] = defaultdict(int)
        high_risk_n = 0
        for sample in rows:
            if sample.indexed_fallback and sample.indexed_fallback_reason:
                reasons[sample.indexed_fallback_reason] += 1
            channels_arm[sample.channel] += 1
            mutations[sample.mutation] += 1
            if sample.high_risk:
                high_risk_n += 1
        idx_lats = [s.index_latency_ms for s in rows if s.index_latency_ms]
        rank_lats = [s.rank_latency_ms for s in rows if s.rank_latency_ms]
        finals = [s.final_tool_count for s in rows if s.final_tool_count]
        index_ok = sum(1 for s in rows if s.index_success is True)
        index_fail = sum(1 for s in rows if s.index_success is False)
        enabled_n = sum(1 for s in rows if s.indexed_enabled)
        miss_n = counts.get(EVENT_INDEXED_RETRIEVAL_MISS, 0) if arm == "experiment" else 0
        miss_denom = enabled_n or n
        return {
            "requests": n,
            "indexed_requests": enabled_n,
            "fallback_requests": fb,
            "fallback_rate": round(fb / n, 4) if n else None,
            "avg_candidate_count": round(sum(cands) / n, 2) if n else 0.0,
            "avg_final_tool_count": round(sum(finals) / len(finals), 2) if finals else 0.0,
            "indexed_retrieval_miss_rate": (
                round(miss_n / miss_denom, 4) if arm == "experiment" and miss_denom else None
            ),
            "index_success_rate": (
                round(index_ok / (index_ok + index_fail), 4)
                if (index_ok + index_fail)
                else None
            ),
            "discovery_latency": {
                "p50": _percentile([int(round(v)) for v in lats], 50) if lats else 0,
                "p95": _percentile([int(round(v)) for v in lats], 95) if lats else 0,
                "p99": _percentile([int(round(v)) for v in lats], 99) if lats else 0,
                "avg_ms": round(sum(lats) / n, 3) if n else 0.0,
            },
            "index_latency": {
                "p50": _percentile([int(round(v)) for v in idx_lats], 50) if idx_lats else 0,
                "p95": _percentile([int(round(v)) for v in idx_lats], 95) if idx_lats else 0,
                "p99": _percentile([int(round(v)) for v in idx_lats], 99) if idx_lats else 0,
            },
            "rank_latency": {
                "p50": _percentile([int(round(v)) for v in rank_lats], 50) if rank_lats else 0,
                "p95": _percentile([int(round(v)) for v in rank_lats], 95) if rank_lats else 0,
                "p99": _percentile([int(round(v)) for v in rank_lats], 99) if rank_lats else 0,
            },
            "request_latency": {
                "p50": _percentile([int(round(v)) for v in req], 50) if req else 0,
                "p95": _percentile([int(round(v)) for v in req], 95) if req else 0,
                "p99": _percentile([int(round(v)) for v in req], 99) if req else 0,
            },
            "task_completion_rate": (
                round(first_ok_arm / first_n, 4) if first_n else None
            ),
            "fallback_reasons": dict(reasons),
            "by_channel": dict(channels_arm),
            "by_mutation": dict(mutations),
            "high_risk_requests": high_risk_n,
        }

    indexed_control = indexed_stats("control")
    indexed_experiment = indexed_stats("experiment")
    indexed_decision = recommend_canary_decision(
        live_control=indexed_control["requests"],
        live_experiment=indexed_experiment["requests"],
        min_samples=INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
    )
    from app.services.ai.ai_tool_canary import (
        compare_rate,
        recommend_indexed_promotion,
    )

    task_cmp = compare_rate(
        counts.get("indexed_task.control.success", 0),
        counts.get("indexed_task.control.total", 0),
        counts.get("indexed_task.experiment.success", 0),
        counts.get("indexed_task.experiment.total", 0),
    )
    first_pass_cmp = compare_rate(
        counts.get("indexed_first_pass.control.success", 0),
        counts.get("indexed_first_pass.control.total", 0),
        counts.get("indexed_first_pass.experiment.success", 0),
        counts.get("indexed_first_pass.experiment.total", 0),
    )
    miss_cmp = compare_rate(
        0,
        indexed_control["requests"],
        counts.get(EVENT_INDEXED_RETRIEVAL_MISS, 0),
        max(indexed_experiment["indexed_requests"], indexed_experiment["requests"]),
    )
    fallback_cmp = compare_rate(
        indexed_control["fallback_requests"],
        indexed_control["requests"],
        indexed_experiment["fallback_requests"],
        indexed_experiment["requests"],
    )
    tool_cmp = compare_rate(
        counts.get("indexed.control.tool_success", 0),
        counts.get("indexed.control.tool_success", 0)
        + counts.get("indexed.control.tool_failure", 0),
        counts.get("indexed.experiment.tool_success", 0),
        counts.get("indexed.experiment.tool_success", 0)
        + counts.get("indexed.experiment.tool_failure", 0),
    )
    payload = {
        "counters": counts,
        "control": control,
        "experiment": experiment,
        "indexed_control": indexed_control,
        "indexed_experiment": indexed_experiment,
        "k_histogram": {
            "10": counts.get("k_bucket.10", 0),
            "15": counts.get("k_bucket.15", 0),
            "20": counts.get("k_bucket.20", 0),
            "fallback": counts.get("k_bucket.fallback", 0),
        },
        "by_channel": dict(channels),
        "high_risk_requests": dict(high_risk_by_arm),
        "rediscovery_queued": queued,
        "rediscovery_recovered": recovered,
        "rediscovery_recovery_rate": round(recovered / queued, 4) if queued else None,
        "discovery_success_without_rediscovery": (
            round(first_ok / first_total, 4) if first_total else None
        ),
        "task_completion": (
            round(counts.get("indexed_task.success", 0) / counts["indexed_task.total"], 4)
            if counts.get("indexed_task.total")
            else None
        ),
        "live_requests": counts.get("discovery_requests", 0),
        "min_live_samples": ADAPTIVE_K_MIN_LIVE_SAMPLES,
        "decision": decision,
        "indexed_min_live_samples": INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
        "indexed_decision": indexed_decision,
        "candidate_index_hit": counts.get(EVENT_INDEX_HIT, 0),
        "candidate_index_empty": counts.get(EVENT_INDEX_EMPTY, 0),
        "indexed_candidate_fallback": counts.get(EVENT_INDEX_FALLBACK, 0),
        "candidate_index_fallback": counts.get(EVENT_INDEX_FALLBACK, 0),
        "indexed_retrieval_miss": counts.get(EVENT_INDEXED_RETRIEVAL_MISS, 0),
        "index_consistency_failure": counts.get(EVENT_INDEX_CONSISTENCY, 0),
        "unauthorized_candidate": counts.get(EVENT_UNAUTHORIZED_CANDIDATE, 0),
        "unauthorized_rediscovery": counts.get(EVENT_UNAUTHORIZED_REDISCOVERY, 0),
        "indexed_retrieval_hit": counts.get(EVENT_INDEXED_RETRIEVAL_HIT, 0),
        "indexed_retrieval_empty": counts.get(EVENT_INDEXED_RETRIEVAL_EMPTY, 0),
        "indexed_retrieval_stale": counts.get(EVENT_INDEXED_RETRIEVAL_STALE, 0),
        "indexed_retrieval_error": counts.get(EVENT_INDEXED_RETRIEVAL_ERROR, 0),
        "control_requests": counts.get("control_requests", 0),
        "experiment_requests": counts.get("experiment_requests", 0),
        "live_control_requests": counts.get("live_control_requests", counts.get("control_requests", 0)),
        "live_experiment_requests": counts.get(
            "live_experiment_requests", counts.get("experiment_requests", 0)
        ),
        "experiment_enabled_requests": counts.get("experiment_enabled_requests", 0),
        "experiment_fallback_requests": counts.get("experiment_fallback_requests", 0),
        "fallback_total": counts.get("fallback_total", 0),
        "fallback_empty": counts.get("fallback_empty", 0),
        "fallback_low_candidate_quality": counts.get("fallback_low_candidate_quality", 0),
        "fallback_stale_index": counts.get("fallback_stale_index", 0),
        "fallback_index_error": counts.get("fallback_index_error", 0),
        "fallback_index_inconsistency": counts.get("fallback_index_inconsistency", 0),
        "no_match_requests": counts.get("no_match_requests", 0),
        "no_match_false_tool_selection": counts.get("no_match_false_tool_selection", 0),
        "indexed_candidate_exposure": counts.get(EVENT_INDEXED_EXPOSURE, 0),
        "evidence_source": "production_live",
        "high_risk_operations": {
            cls: {
                arm: {
                    outcome: counts.get(f"high_risk.{cls}.{arm}.{outcome}", 0)
                    for outcome in HIGH_RISK_OUTCOMES
                }
                for arm in ("control", "experiment")
            }
            for cls in HIGH_RISK_CLASSES
        },
        "tool_execution_by_class": {
            cls: {
                arm: {
                    "success": counts.get(f"indexed.{arm}.tool_success.{cls}", 0),
                    "failure": counts.get(f"indexed.{arm}.tool_failure.{cls}", 0),
                }
                for arm in ("control", "experiment")
            }
            for cls in ("read", "write", "delete", "export", "execute")
        },
        "comparison": {
            "task_completion": task_cmp,
            "first_pass_without_rediscovery": first_pass_cmp,
            "fallback_rate": fallback_cmp,
            "indexed_retrieval_miss": miss_cmp,
            "tool_success": tool_cmp,
        },
    }
    payload["indexed_promotion"] = recommend_indexed_promotion(payload)
    return payload
