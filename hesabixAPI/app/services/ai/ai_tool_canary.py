"""Deterministic Adaptive K and Indexed Retrieval canaries.

Assignment is stable for (business_id, user_id). Raw ids are never logged.
Hybrid is never enabled from this module. The two canaries use different salts.
"""
from __future__ import annotations

import hashlib
import math
import os
from dataclasses import dataclass
from typing import Any, Dict, Optional, Sequence, Tuple

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_CANARY_SALT,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_CANARY_SALT,
    INDEXED_CANDIDATE_CHANNEL_HOLD,
    INDEXED_CANDIDATE_KILL_SWITCH,
    INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
    INDEXED_CANDIDATE_RETRIEVAL,
    INDEXED_CANDIDATE_ROLLOUT_PERCENT,
)

ARM_CONTROL = "control"
ARM_EXPERIMENT = "experiment"
ARM_SHADOW = "shadow"

ALLOWED_PERCENTS = (0, 5, 10, 25, 50, 100)
INDEXED_ROLLOUT_LADDER = (5, 10, 25, 50, 100)


@dataclass(frozen=True)
class AdaptiveAssignment:
    arm: str
    enabled: bool
    bucket: int
    percent: int
    global_flag: bool

    def to_log_dict(self) -> dict:
        return {
            "adaptive_arm": self.arm,
            "adaptive_enabled": self.enabled,
            "adaptive_bucket": self.bucket,
            "adaptive_percent": self.percent,
        }


@dataclass(frozen=True)
class IndexedAssignment:
    arm: str
    enabled: bool
    bucket: int
    percent: int
    global_flag: bool
    killed: bool = False
    channel_held: bool = False

    def to_log_dict(self) -> dict:
        return {
            "indexed_arm": self.arm,
            "indexed_enabled": self.enabled,
            "indexed_bucket": self.bucket,
            "indexed_percent": self.percent,
            "indexed_killed": self.killed,
            "indexed_channel_held": self.channel_held,
        }


def _resolve_bucket_assignment(
    *,
    business_id: Optional[int],
    user_id: Optional[int],
    percent: Optional[int],
    global_flag: Optional[bool],
    default_flag: bool,
    default_percent: int,
    salt: str,
) -> tuple:
    flag = default_flag if global_flag is None else bool(global_flag)
    pct = clamp_rollout_percent(
        default_percent if percent is None else percent
    )
    bucket = stable_canary_bucket(
        business_id=business_id, user_id=user_id, salt=salt
    )
    if flag:
        return True, ARM_EXPERIMENT, bucket, 100, True
    if pct <= 0:
        return False, ARM_CONTROL, bucket, 0, False
    in_canary = bucket < pct
    return in_canary, ARM_EXPERIMENT if in_canary else ARM_CONTROL, bucket, pct, False


def stable_canary_bucket(
    *,
    business_id: Optional[int] = None,
    user_id: Optional[int] = None,
    salt: str = ADAPTIVE_K_CANARY_SALT,
) -> int:
    """0–99. Same tenant+user always lands in the same bucket."""
    material = f"{salt}:{int(business_id or 0)}:{int(user_id or 0)}"
    digest = hashlib.sha256(material.encode("utf-8")).hexdigest()
    return int(digest, 16) % 100


def clamp_rollout_percent(raw: Optional[int]) -> int:
    """Only 0 / 5 / 10 / 25 / 50 / 100. Unknown values round down, never up."""
    try:
        value = int(raw if raw is not None else 0)
    except (TypeError, ValueError):
        return 0
    if value in ALLOWED_PERCENTS:
        return value
    if value <= 0:
        return 0
    if value >= 100:
        return 100
    allowed = [step for step in ALLOWED_PERCENTS if step <= value]
    return int(allowed[-1]) if allowed else 0


def resolve_adaptive_assignment(
    *,
    business_id: Optional[int] = None,
    user_id: Optional[int] = None,
    percent: Optional[int] = None,
    global_flag: Optional[bool] = None,
) -> AdaptiveAssignment:
    """K policy only. Security and ranker stay identical across arms."""
    if HYBRID_TOOL_DISCOVERY:
        pass
    enabled, arm, bucket, pct, gflag = _resolve_bucket_assignment(
        business_id=business_id,
        user_id=user_id,
        percent=percent,
        global_flag=global_flag,
        default_flag=ADAPTIVE_DISCOVERY_K,
        default_percent=ADAPTIVE_K_ROLLOUT_PERCENT,
        salt=ADAPTIVE_K_CANARY_SALT,
    )
    return AdaptiveAssignment(
        arm=arm,
        enabled=enabled,
        bucket=bucket,
        percent=pct,
        global_flag=gflag,
    )


def _env_bool(name: str) -> Optional[bool]:
    raw = os.getenv(name)
    if raw is None or str(raw).strip() == "":
        return None
    return str(raw).strip().lower() in {"1", "true", "yes", "on"}


def indexed_kill_switch_on() -> bool:
    """Stop indexed canary without changing Adaptive K / Hybrid / Schema.

    Env `HESABIX_INDEXED_CANDIDATE_KILL=1` or
    `HESABIX_INDEXED_CANDIDATE_RETRIEVAL=0` wins over in-code percent.
    """
    if INDEXED_CANDIDATE_KILL_SWITCH:
        return True
    explicit_kill = _env_bool("HESABIX_INDEXED_CANDIDATE_KILL")
    if explicit_kill is True:
        return True
    retrieval = _env_bool("HESABIX_INDEXED_CANDIDATE_RETRIEVAL")
    if retrieval is False:
        return True
    return False


def indexed_runtime_percent(explicit: Optional[int] = None) -> int:
    if explicit is not None:
        return clamp_rollout_percent(explicit)
    env_pct = os.getenv("HESABIX_INDEXED_CANDIDATE_ROLLOUT_PERCENT")
    if env_pct is not None and str(env_pct).strip() != "":
        return clamp_rollout_percent(env_pct)
    return clamp_rollout_percent(INDEXED_CANDIDATE_ROLLOUT_PERCENT)


def indexed_channel_hold_set() -> frozenset:
    held = {str(c).strip() for c in INDEXED_CANDIDATE_CHANNEL_HOLD if str(c).strip()}
    raw = os.getenv("HESABIX_INDEXED_CANDIDATE_CHANNEL_HOLD") or ""
    for part in raw.split(","):
        name = part.strip()
        if name:
            held.add(name)
    return frozenset(held)


def resolve_indexed_assignment(
    *,
    business_id: Optional[int] = None,
    user_id: Optional[int] = None,
    percent: Optional[int] = None,
    global_flag: Optional[bool] = None,
    channel: str = "",
) -> IndexedAssignment:
    """Candidate generation only. Independent of Adaptive K and Hybrid."""
    killed = indexed_kill_switch_on()
    if killed:
        bucket = stable_canary_bucket(
            business_id=business_id,
            user_id=user_id,
            salt=INDEXED_CANDIDATE_CANARY_SALT,
        )
        return IndexedAssignment(
            arm=ARM_CONTROL,
            enabled=False,
            bucket=bucket,
            percent=0,
            global_flag=False,
            killed=True,
            channel_held=False,
        )
    runtime_flag = INDEXED_CANDIDATE_RETRIEVAL if global_flag is None else bool(global_flag)
    env_flag = _env_bool("HESABIX_INDEXED_CANDIDATE_RETRIEVAL")
    if env_flag is True:
        runtime_flag = True
    pct = indexed_runtime_percent(percent)
    enabled, arm, bucket, resolved_pct, gflag = _resolve_bucket_assignment(
        business_id=business_id,
        user_id=user_id,
        percent=pct,
        global_flag=runtime_flag,
        default_flag=False,
        default_percent=pct,
        salt=INDEXED_CANDIDATE_CANARY_SALT,
    )
    channel_held = bool((channel or "").strip() in indexed_channel_hold_set())
    if channel_held:
        enabled = False
        arm = ARM_CONTROL
    return IndexedAssignment(
        arm=arm,
        enabled=enabled,
        bucket=bucket,
        percent=resolved_pct,
        global_flag=gflag,
        killed=False,
        channel_held=channel_held,
    )


def query_hash(text: Optional[str]) -> str:
    blob = (text or "").encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:16]


def recommend_canary_decision(
    *,
    live_control: int,
    live_experiment: int,
    min_samples: int,
) -> str:
    """Never promote from Gold alone. HOLD until both arms have live traffic.

    ROLL OUT / ROLLBACK are operator decisions after REVIEW — this helper
    does not invent quality thresholds.
    """
    if int(live_control or 0) < int(min_samples) or int(live_experiment or 0) < int(
        min_samples
    ):
        return "HOLD"
    return "REVIEW"


def wilson_ci(successes: int, n: int, z: float = 1.96) -> Tuple[Optional[float], Optional[float]]:
    if n <= 0:
        return (None, None)
    k = max(0, int(successes))
    total = int(n)
    p = k / total
    z2 = z * z
    denom = 1.0 + z2 / total
    center = (p + z2 / (2.0 * total)) / denom
    half = z * math.sqrt((p * (1.0 - p) + z2 / (4.0 * total)) / total) / denom
    return (round(max(0.0, center - half), 4), round(min(1.0, center + half), 4))


def compare_rate(
    control_success: int,
    control_n: int,
    experiment_success: int,
    experiment_n: int,
) -> Dict[str, Any]:
    c_n = int(control_n or 0)
    e_n = int(experiment_n or 0)
    c_rate = (control_success / c_n) if c_n else None
    e_rate = (experiment_success / e_n) if e_n else None
    c_ci = wilson_ci(control_success, c_n)
    e_ci = wilson_ci(experiment_success, e_n)
    overlap = (
        c_ci[0] is not None
        and e_ci[0] is not None
        and not (e_ci[1] < c_ci[0] or c_ci[1] < e_ci[0])
    )
    delta = None
    if c_rate is not None and e_rate is not None:
        delta = round(e_rate - c_rate, 4)
    return {
        "control": {
            "n": c_n,
            "rate": None if c_rate is None else round(c_rate, 4),
            "ci95": list(c_ci),
        },
        "experiment": {
            "n": e_n,
            "rate": None if e_rate is None else round(e_rate, 4),
            "ci95": list(e_ci),
        },
        "delta": delta,
        "ci_overlap": overlap if c_n and e_n else None,
        "enough_for_significance": bool(c_n >= 500 and e_n >= 500),
    }


def percentile(values: Sequence[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(float(v) for v in values)
    if len(ordered) == 1:
        return round(ordered[0], 3)
    idx = int(round((p / 100.0) * (len(ordered) - 1)))
    idx = max(0, min(len(ordered) - 1, idx))
    return round(ordered[idx], 3)


def indexed_rollout_status() -> Dict[str, Any]:
    """Read-only ladder. Never writes INDEXED_CANDIDATE_ROLLOUT_PERCENT."""
    current = clamp_rollout_percent(INDEXED_CANDIDATE_ROLLOUT_PERCENT)
    nxt = None
    for step in INDEXED_ROLLOUT_LADDER:
        if step > current:
            nxt = step
            break
    return {
        "current_percent": current,
        "ladder": list(INDEXED_ROLLOUT_LADDER),
        "next_percent": nxt,
        "auto_promotion": False,
        "promotion_requires": "explicit_operator_decision",
        "global_flag": INDEXED_CANDIDATE_RETRIEVAL,
        "killed": indexed_kill_switch_on(),
    }


def propose_indexed_rollout(target_percent: int) -> Dict[str, Any]:
    """Describe a ladder step. Does not mutate constants or auto-promote."""
    target = clamp_rollout_percent(target_percent)
    status = indexed_rollout_status()
    current = int(status["current_percent"])
    allowed = target in INDEXED_ROLLOUT_LADDER or target == 0
    return {
        "current_percent": current,
        "requested_percent": target,
        "applied": False,
        "auto_promotion": False,
        "accepted": bool(allowed and target != current),
        "reason": (
            "operator_must_change_INDEXED_CANDIDATE_ROLLOUT_PERCENT"
            if allowed
            else "percent_not_on_ladder"
        ),
        "ladder": list(INDEXED_ROLLOUT_LADDER),
    }


def recommend_indexed_promotion(snapshot: Dict[str, Any]) -> Dict[str, Any]:
    """Live-only gates. Gold cannot promote. This helper never auto-promotes.

    Statistical method for two rates: Wilson score interval (95%). Material
    task regression = experiment CI entirely below control CI after n>=500/arm.
    No invented percentage drop threshold.
    """
    counts = dict(snapshot.get("counters") or {})
    control = dict(snapshot.get("indexed_control") or {})
    experiment = dict(snapshot.get("indexed_experiment") or {})
    comparison = dict(snapshot.get("comparison") or {})
    security = int(counts.get("unauthorized_candidate") or 0) + int(
        counts.get("unauthorized_rediscovery") or 0
    ) + int(counts.get("authorization_failure") or 0)
    bypass = int(counts.get("unauthorized_candidate") or 0) + int(
        counts.get("unauthorized_rediscovery") or 0
    )
    tenant = int(counts.get("tenant_leakage") or 0)
    perm = int(counts.get("permission_violation") or 0)
    control_n = int(control.get("requests") or 0)
    experiment_n = int(experiment.get("requests") or 0)
    min_n = INDEXED_CANDIDATE_MIN_LIVE_SAMPLES
    base = {
        "control_requests": control_n,
        "experiment_requests": experiment_n,
        "min_samples": min_n,
        "auto_promotion": False,
        "allow_operator_promote": False,
        "security_events": security,
        "gates": {
            "A_security": "unknown",
            "B_task": "unknown",
            "C_index_miss": "unknown",
            "D_fallback": "unknown",
            "E_latency": "unknown",
        },
    }
    if bypass > 0 or tenant > 0 or perm > 0:
        base.update(
            {
                "decision": "ROLLBACK",
                "case": "D",
                "reason": "authorization_bypass" if bypass else (
                    "tenant_leakage" if tenant else "permission_violation"
                ),
            }
        )
        base["gates"]["A_security"] = "fail"
        return base
    base["gates"]["A_security"] = "pass"
    if control_n < min_n or experiment_n < min_n:
        base.update(
            {
                "decision": "HOLD",
                "case": "insufficient_samples",
                "reason": "need_500_per_arm",
            }
        )
        return base

    task = dict(comparison.get("task_completion") or {})
    task_n = int((task.get("control") or {}).get("n") or 0) + int(
        (task.get("experiment") or {}).get("n") or 0
    )
    if task_n <= 0:
        base.update(
            {
                "decision": "HOLD",
                "case": "insufficient_samples",
                "reason": "task_completion_not_measurable",
            }
        )
        base["gates"]["B_task"] = "unmeasurable"
        return base
    if not task.get("enough_for_significance"):
        base.update(
            {
                "decision": "HOLD",
                "case": "insufficient_samples",
                "reason": "task_completion_confidence_insufficient",
            }
        )
        base["gates"]["B_task"] = "hold"
        return base
    if task.get("ci_overlap") is False:
        e_rate = (task.get("experiment") or {}).get("rate")
        c_rate = (task.get("control") or {}).get("rate")
        if e_rate is not None and c_rate is not None and e_rate < c_rate:
            base.update(
                {
                    "decision": "ROLLBACK",
                    "case": "C",
                    "reason": "task_success_regression",
                    "task_comparison": task,
                }
            )
            base["gates"]["B_task"] = "fail"
            return base
    base["gates"]["B_task"] = "pass"

    miss_rate = experiment.get("indexed_retrieval_miss_rate")
    base["gates"]["C_index_miss"] = "report"
    base["indexed_retrieval_miss_rate"] = miss_rate

    fb = dict(comparison.get("fallback_rate") or {})
    e_fb = (fb.get("experiment") or {})
    e_lo = (e_fb.get("ci95") or [None, None])[0]
    if e_lo is not None and e_lo > 0.5:
        base.update(
            {
                "decision": "HOLD",
                "case": "B",
                "reason": "high_fallback_index_benefit_insufficient",
                "fallback_comparison": fb,
            }
        )
        base["gates"]["D_fallback"] = "fail"
        return base
    base["gates"]["D_fallback"] = "pass"

    c_lat = dict(control.get("request_latency") or control.get("discovery_latency") or {})
    e_lat = dict(experiment.get("request_latency") or experiment.get("discovery_latency") or {})
    c_p95 = float(c_lat.get("p95") or 0)
    e_p95 = float(e_lat.get("p95") or 0)
    c_p99 = float(c_lat.get("p99") or 0)
    e_p99 = float(e_lat.get("p99") or 0)
    base["latency"] = {
        "control_p95": c_p95,
        "experiment_p95": e_p95,
        "control_p99": c_p99,
        "experiment_p99": e_p99,
    }
    if e_p95 > 0 and c_p99 > 0 and e_p95 > c_p99:
        base.update(
            {
                "decision": "HOLD",
                "case": "B",
                "reason": "experiment_p95_worse_than_control_p99",
            }
        )
        base["gates"]["E_latency"] = "fail"
        return base
    base["gates"]["E_latency"] = "pass"
    base.update(
        {
            "decision": "REVIEW",
            "case": "A",
            "reason": "gates_clear_operator_required",
            "allow_operator_promote": True,
        }
    )
    return base
