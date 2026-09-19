"""Phase 9 — Control (K=48) vs Adaptive K on Gold, plus live HOLD gate.

Does not enable production flags. Hybrid is not evaluated for promotion.
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Sequence

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_MIN_LIVE_SAMPLES,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    HYBRID_TOOL_DISCOVERY,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_tool_adaptive_k import (
    DEFAULT_ADAPTIVE_POLICY,
    recommended_k_for_scores,
    truncate_ranked,
)
from app.services.ai.ai_tool_canary import recommend_canary_decision
from app.services.ai.ai_tool_discovery_eval import (
    discover_ranked,
    estimate_tools_schema_tokens,
    permissioned_catalog,
    ranked_candidates,
)
from app.services.ai.ai_tool_discovery_gold import (
    GOLD_DATASET_VERSION,
    INTENT_DELETE,
    INTENT_EXECUTE,
    INTENT_EXPORT,
    INTENT_WRITE,
    GoldQuery,
    load_gold_queries,
)
from app.services.ai.ai_tool_discovery_telemetry import telemetry_snapshot
from app.services.ai.ai_tool_intent import iterations_for_query

PHASE9_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/phase-9")
HIGH_RISK = {INTENT_WRITE, INTENT_DELETE, INTENT_EXPORT, INTENT_EXECUTE}


def _hit(row: GoldQuery, names: Sequence[str]) -> bool:
    primary = row.primary_expected_tools
    return bool(primary) and any(n in names for n in primary)


def _percentile(values: Sequence[int], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(int(v) for v in values)
    if len(ordered) == 1:
        return float(ordered[0])
    idx = int(round((p / 100.0) * (len(ordered) - 1)))
    idx = max(0, min(len(ordered) - 1, idx))
    return float(ordered[idx])


def _rate(hits: List[bool]) -> float:
    n = max(1, len(hits))
    return round(sum(1 for h in hits if h) / n, 4)


def evaluate_control_vs_adaptive(
    rows: List[GoldQuery],
    catalog: Sequence[str],
    *,
    control_k: int = 48,
) -> Dict[str, Any]:
    match = [row for row in rows if not row.no_match]
    control_hits: List[bool] = []
    adaptive_hits: List[bool] = []
    ks: List[int] = []
    control_ks: List[int] = []
    rec_ks: List[int] = []
    adaptive_tokens: List[int] = []
    control_tokens: List[int] = []
    adaptive_wire: List[int] = []
    control_wire: List[int] = []
    k_hist = {"10": 0, "15": 0, "20": 0, "fallback": 0}
    by_intent: Dict[str, Dict[str, List[bool]]] = defaultdict(
        lambda: {"control": [], "adaptive": []}
    )
    by_category: Dict[str, Dict[str, List[bool]]] = defaultdict(
        lambda: {"control": [], "adaptive": []}
    )
    by_difficulty: Dict[str, Dict[str, List[bool]]] = defaultdict(
        lambda: {"control": [], "adaptive": []}
    )
    high_risk_c: List[bool] = []
    high_risk_a: List[bool] = []

    for row in match:
        offer = discover_ranked(row, k=control_k, catalog=catalog)
        ranked = ranked_candidates(offer)
        control_names = [item.name for item in ranked]
        conf, rec_k = recommended_k_for_scores(
            top_score=offer.top_score,
            second_score=offer.second_score,
            candidate_count=len(ranked),
            query=row.query,
            history_messages=list(row.history) if row.history else None,
            policy=DEFAULT_ADAPTIVE_POLICY,
        )
        truncated = truncate_ranked(ranked, rec_k)
        adaptive_names = [item.name for item in truncated]
        c_hit = _hit(row, control_names)
        a_hit = _hit(row, adaptive_names)
        control_hits.append(c_hit)
        adaptive_hits.append(a_hit)
        control_ks.append(len(control_names))
        ks.append(len(adaptive_names))
        rec_ks.append(int(rec_k))
        if rec_k <= 10:
            k_hist["10"] += 1
        elif rec_k <= 15:
            k_hist["15"] += 1
        elif rec_k <= 20:
            k_hist["20"] += 1
        else:
            k_hist["fallback"] += 1
        iters = max(1, iterations_for_query(row.query, list(row.history) or None))
        atok = estimate_tools_schema_tokens(adaptive_names)
        ctok = estimate_tools_schema_tokens(control_names)
        adaptive_tokens.append(atok)
        control_tokens.append(ctok)
        adaptive_wire.append(atok * iters)
        control_wire.append(ctok * iters)
        by_intent[row.intent]["control"].append(c_hit)
        by_intent[row.intent]["adaptive"].append(a_hit)
        by_category[row.category or "unknown"]["control"].append(c_hit)
        by_category[row.category or "unknown"]["adaptive"].append(a_hit)
        by_difficulty[row.difficulty or "unknown"]["control"].append(c_hit)
        by_difficulty[row.difficulty or "unknown"]["adaptive"].append(a_hit)
        if row.intent in HIGH_RISK:
            high_risk_c.append(c_hit)
            high_risk_a.append(a_hit)

    n = max(1, len(match))
    adaptive_misses = [not h for h in adaptive_hits]
    miss_n = sum(1 for h in adaptive_hits if not h)
    recovered_n = sum(
        1 for a, c in zip(adaptive_hits, control_hits) if (not a) and c
    )
    failed_n = sum(
        1 for a, c in zip(adaptive_hits, control_hits) if (not a) and (not c)
    )
    first_pass_n = sum(1 for h in adaptive_hits if h)

    def summarize_group(group: Dict[str, Dict[str, List[bool]]]) -> Dict[str, Any]:
        out = {}
        for key, arms in group.items():
            out[key] = {
                "n": len(arms["control"]),
                "control_recall": _rate(arms["control"]),
                "adaptive_recall": _rate(arms["adaptive"]),
            }
        return out

    live = telemetry_snapshot()
    return {
        "dataset_version": GOLD_DATASET_VERSION,
        "queries": len(match),
        "policy": DEFAULT_ADAPTIVE_POLICY.name,
        "control": {
            "k_policy": f"fixed_{control_k}",
            "recall": _rate(control_hits),
            "average_k": round(sum(control_ks) / n, 2),
            "p50_k": _percentile(control_ks, 50),
            "p95_k": _percentile(control_ks, 95),
            "avg_schema_tokens": round(sum(control_tokens) / n),
            "avg_schema_tokens_per_request": round(sum(control_wire) / n),
            "first_pass_success": _rate(control_hits),
        },
        "experiment": {
            "k_policy": f"adaptive_{DEFAULT_ADAPTIVE_POLICY.name}",
            "recall": _rate(adaptive_hits),
            "average_k": round(sum(ks) / n, 2),
            "p50_k": _percentile(ks, 50),
            "p95_k": _percentile(ks, 95),
            "avg_schema_tokens": round(sum(adaptive_tokens) / n),
            "avg_schema_tokens_per_request": round(sum(adaptive_wire) / n),
            "first_pass_success": round(first_pass_n / n, 4),
            "k_histogram": k_hist,
            "recommended_k_avg": round(sum(rec_ks) / n, 2),
        },
        "tool_discovery_miss_proxy": round(sum(adaptive_misses) / n, 4),
        "retrieval_miss_proxy": round(miss_n / n, 4),
        "schema_miss_proxy": 0.0,
        "rediscovery_rate_proxy": round(miss_n / n, 4),
        "rediscovery_recovery_proxy": (
            round(recovered_n / miss_n, 4) if miss_n else None
        ),
        "rediscovery_recovered": recovered_n,
        "rediscovery_failed_even_at_k48": failed_n,
        "unknown_tool_proxy": 0.0,
        "high_risk": {
            "n": len(high_risk_c),
            "control_recall": _rate(high_risk_c) if high_risk_c else None,
            "adaptive_recall": _rate(high_risk_a) if high_risk_a else None,
        },
        "by_intent": summarize_group(by_intent),
        "by_category": summarize_group(by_category),
        "by_difficulty": summarize_group(by_difficulty),
        "flags": {
            "PROGRESSIVE_SCHEMA_LOADING": PROGRESSIVE_SCHEMA_LOADING,
            "ADAPTIVE_DISCOVERY_K": ADAPTIVE_DISCOVERY_K,
            "ADAPTIVE_K_ROLLOUT_PERCENT": ADAPTIVE_K_ROLLOUT_PERCENT,
            "HYBRID_TOOL_DISCOVERY": HYBRID_TOOL_DISCOVERY,
            "MAX_TOOLS_PER_REQUEST": MAX_TOOLS_PER_REQUEST,
        },
        "live": {
            "requests": live.get("live_requests", 0),
            "control": live.get("control"),
            "experiment": live.get("experiment"),
            "min_samples": ADAPTIVE_K_MIN_LIVE_SAMPLES,
            "decision": recommend_canary_decision(
                live_control=int((live.get("control") or {}).get("requests") or 0),
                live_experiment=int((live.get("experiment") or {}).get("requests") or 0),
                min_samples=ADAPTIVE_K_MIN_LIVE_SAMPLES,
            ),
        },
        "note": (
            "Gold recall is a retrieval proxy, not live task completion. "
            "Do not ROLL OUT Adaptive K from this file alone."
        ),
    }


def run_phase9_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    gold = load_gold_queries()
    catalog = permissioned_catalog()
    report = evaluate_control_vs_adaptive(gold, catalog)
    if write_files:
        PHASE9_DIR.mkdir(parents=True, exist_ok=True)
        (PHASE9_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        (PHASE9_DIR / "README.md").write_text(
            "\n".join(
                [
                    "# Phase 9 evaluation outputs",
                    "",
                    "- [`latest.json`](latest.json) — Control K=48 vs Adaptive tight on Gold "
                    f"{GOLD_DATASET_VERSION}",
                    "- Live canary samples are in-process (`telemetry_snapshot`); "
                    "production remains at 0% until an operator raises "
                    "`ADAPTIVE_K_ROLLOUT_PERCENT`.",
                    "",
                    "```bash",
                    "cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_phase9_eval",
                    "cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_scale_bench",
                    "```",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return report


def main() -> None:
    report = run_phase9_evaluation(write_files=True)
    print(
        json.dumps(
            {
                "control_recall": report["control"]["recall"],
                "adaptive_recall": report["experiment"]["recall"],
                "adaptive_avg_k": report["experiment"]["average_k"],
                "p50_k": report["experiment"]["p50_k"],
                "p95_k": report["experiment"]["p95_k"],
                "first_pass": report["experiment"]["first_pass_success"],
                "rediscovery_recovery_proxy": report["rediscovery_recovery_proxy"],
                "live_decision": report["live"]["decision"],
                "hybrid": HYBRID_TOOL_DISCOVERY,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
