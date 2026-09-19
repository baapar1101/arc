"""Phase 8 Adaptive K + Hybrid evaluation on Gold 2026-08-19.v1."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

from app.services.ai.ai_tool_adaptive_k import (
    AdaptiveKPolicy,
    DEFAULT_ADAPTIVE_POLICY,
    recommended_k_for_scores,
    truncate_ranked,
)
from app.services.ai.ai_tool_discovery import HybridStrategy, discover_tools
from app.services.ai.ai_tool_discovery_eval import (
    discover_ranked,
    estimate_tools_schema_tokens,
    ndcg_at_k,
    permissioned_catalog,
    ranked_candidates,
)
from app.services.ai.ai_tool_discovery_gold import (
    GOLD_DATASET_VERSION,
    GoldQuery,
    load_gold_queries,
)
from app.services.ai.ai_tool_hybrid import (
    WEIGHT_BALANCED,
    WEIGHT_LEXICAL_DOMINANT,
    WEIGHT_SEMANTIC_DOMINANT,
)
from app.services.ai.ai_tool_intent import iterations_for_query

ADAPTIVE_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/tool-adaptive-k")
HYBRID_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/tool-hybrid")
PHASE8_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/phase-8")

TARGET_RECALL = 0.95


def _hit(row: GoldQuery, names: Sequence[str]) -> bool:
    primary = row.primary_expected_tools
    return bool(primary) and any(n in names for n in primary)


def _mrr(row: GoldQuery, names: Sequence[str]) -> float:
    wanted = set(row.primary_expected_tools)
    for i, name in enumerate(names, start=1):
        if name in wanted:
            return 1.0 / i
    return 0.0


def _summarize(rows: List[GoldQuery], picks: List[List[str]], ks: List[int]) -> Dict[str, Any]:
    n = max(1, len(rows))
    hits = sum(1 for row, names in zip(rows, picks) if _hit(row, names))
    mrr = sum(_mrr(row, names) for row, names in zip(rows, picks)) / n
    ndcg = sum(
        ndcg_at_k(names, row.relevance_map(), max(1, len(names) or 1))
        for row, names in zip(rows, picks)
    ) / n
    prec = []
    for row, names in zip(rows, picks):
        success = set(row.success_tools())
        if not names:
            prec.append(0.0)
            continue
        prec.append(sum(1 for n in names if n in success) / len(names))
    tokens = [estimate_tools_schema_tokens(names) for names in picks]
    iters = [
        max(1, iterations_for_query(row.query, list(row.history) or None))
        for row in rows
    ]
    wire = [t * i for t, i in zip(tokens, iters)]
    return {
        "queries": len(rows),
        "recall": round(hits / n, 4),
        "mrr": round(mrr, 4),
        "ndcg": round(ndcg, 4),
        "precision": round(sum(prec) / n, 4),
        "avg_k": round(sum(ks) / n, 2),
        "avg_initial_schema_tokens": round(sum(tokens) / n),
        "avg_schema_tokens_per_request": round(sum(wire) / n),
    }


def evaluate_fixed_k(k: int, rows: List[GoldQuery], catalog: Sequence[str]) -> Dict[str, Any]:
    match = [row for row in rows if not row.no_match]
    picks = []
    ks = []
    for row in match:
        offer = discover_ranked(row, k=k, catalog=catalog)
        names = [item.name for item in ranked_candidates(offer)]
        picks.append(names)
        ks.append(len(names))
    summary = _summarize(match, picks, ks)
    summary["k"] = k
    summary["mode"] = f"fixed_{k}"
    return summary


def evaluate_adaptive_policy(
    policy: AdaptiveKPolicy,
    rows: List[GoldQuery],
    catalog: Sequence[str],
    *,
    wide_k: int = 48,
) -> Dict[str, Any]:
    match = [row for row in rows if not row.no_match]
    picks = []
    ks = []
    levels: Dict[str, int] = {}
    for row in match:
        offer = discover_ranked(row, k=wide_k, catalog=catalog)
        ranked = ranked_candidates(offer)
        conf, rec_k = recommended_k_for_scores(
            top_score=offer.top_score,
            second_score=offer.second_score,
            candidate_count=len(ranked),
            query=row.query,
            history_messages=list(row.history) if row.history else None,
            policy=policy,
        )
        truncated = truncate_ranked(ranked, rec_k)
        names = [item.name for item in truncated]
        picks.append(names)
        ks.append(len(names))
        levels[conf.level] = levels.get(conf.level, 0) + 1
    summary = _summarize(match, picks, ks)
    summary["mode"] = f"adaptive_{policy.name}"
    summary["policy"] = policy.name
    summary["levels"] = levels
    summary["recall_ok"] = summary["recall"] >= TARGET_RECALL
    return summary


def evaluate_hybrid_weight(
    weights: dict,
    k: int,
    rows: List[GoldQuery],
    catalog: Sequence[str],
) -> Dict[str, Any]:
    match = [row for row in rows if not row.no_match]
    strategy = HybridStrategy()
    picks = []
    ks = []
    family_fp = 0
    family_n = 0
    for row in match:
        offer = discover_tools(
            row.query,
            permissioned_names=list(catalog),
            execution_mode="supervised"
            if row.intent in {"write", "delete", "export", "execute"}
            else "analyzer",
            limit=k,
            history_messages=list(row.history) if row.history else None,
            channel="eval",
            strategy=strategy,
        )
        names = [item.name for item in ranked_candidates(offer)]
        picks.append(names)
        ks.append(len(names))
        expected = row.primary_expected_tools
        if expected and any(n.startswith("delete_") for n in expected):
            family_n += 1
            top = names[0] if names else ""
            if top.startswith("delete_") and top not in expected:
                family_fp += 1
    # Re-score with explicit weights by temporarily using hybrid_select via strategy
    # HybridStrategy uses DEFAULT weights; for other sets, patch ranker via discover limit
    # only default. Callers pass distinct strategy subclasses when needed.
    summary = _summarize(match, picks, ks)
    summary["k"] = k
    summary["weights"] = weights.get("name")
    summary["delete_family_false_positives"] = family_fp
    summary["delete_family_queries"] = family_n
    return summary


class _WeightedHybrid(HybridStrategy):
    def __init__(self, weights: dict) -> None:
        self._weights = weights
        self.name = f"hybrid:{weights.get('name')}"

    def select(self, authorized, query, **kwargs):
        from app.services.ai.ai_tool_hybrid import hybrid_select_names

        kwargs = dict(kwargs)
        return hybrid_select_names(
            authorized,
            query,
            limit=kwargs.get("limit", 15),
            prefer_names=kwargs.get("prefer_names") or set(),
            protected_names=kwargs.get("protected_names") or set(),
            history_messages=kwargs.get("history_messages"),
            weights=self._weights,
        )


def run_phase8_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    gold = load_gold_queries()
    catalog = permissioned_catalog()
    fixed = {
        "k10": evaluate_fixed_k(10, gold, catalog),
        "k15": evaluate_fixed_k(15, gold, catalog),
        "k20": evaluate_fixed_k(20, gold, catalog),
    }
    policies = [
        DEFAULT_ADAPTIVE_POLICY,
        AdaptiveKPolicy(name="tight", high_k=10, normal_k=10, low_k=15, expand_k=20, max_k=20),
        AdaptiveKPolicy(name="wide", high_k=10, normal_k=15, low_k=24, expand_k=30, max_k=30),
    ]
    adaptive = [evaluate_adaptive_policy(p, gold, catalog) for p in policies]
    viable = [item for item in adaptive if item["recall"] >= TARGET_RECALL]
    best = min(viable or adaptive, key=lambda item: (item["avg_k"], -item["recall"]))
    hybrid = []
    for weights in (WEIGHT_LEXICAL_DOMINANT, WEIGHT_BALANCED, WEIGHT_SEMANTIC_DOMINANT):
        for k in (10, 15):
            hybrid.append(
                evaluate_hybrid_weight_with_strategy(weights, k, gold, catalog)
            )
    best_hybrid = max(hybrid, key=lambda item: (item["recall"], item["ndcg"], item["mrr"]))
    report = {
        "dataset_version": GOLD_DATASET_VERSION,
        "target_recall": TARGET_RECALL,
        "fixed": fixed,
        "adaptive": adaptive,
        "best_adaptive": best,
        "hybrid": hybrid,
        "best_hybrid": {
            "weights": best_hybrid.get("weights"),
            "k": best_hybrid.get("k"),
            "recall": best_hybrid.get("recall"),
            "mrr": best_hybrid.get("mrr"),
            "ndcg": best_hybrid.get("ndcg"),
        },
        "hybrid_vs_fixed_k10": round(
            best_hybrid["recall"] - fixed["k10"]["recall"], 4
        )
        if best_hybrid.get("k") == 10
        else None,
    }
    if write_files:
        for folder in (ADAPTIVE_DIR, HYBRID_DIR, PHASE8_DIR):
            folder.mkdir(parents=True, exist_ok=True)
        (ADAPTIVE_DIR / "latest.json").write_text(
            json.dumps(
                {"fixed": fixed, "adaptive": adaptive, "best": best},
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        (HYBRID_DIR / "latest.json").write_text(
            json.dumps(
                {"hybrid": hybrid, "best": report["best_hybrid"]},
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        (PHASE8_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    return report


def evaluate_hybrid_weight_with_strategy(
    weights: dict,
    k: int,
    rows: List[GoldQuery],
    catalog: Sequence[str],
) -> Dict[str, Any]:
    match = [row for row in rows if not row.no_match]
    strategy = _WeightedHybrid(weights)
    picks: List[List[str]] = []
    ks: List[int] = []
    family_fp = 0
    family_n = 0
    from app.services.ai.ai_tool_discovery_eval import mode_for_query

    for row in match:
        offer = discover_tools(
            row.query,
            permissioned_names=list(catalog),
            execution_mode=mode_for_query(row),
            limit=k,
            history_messages=list(row.history) if row.history else None,
            channel="eval",
            strategy=strategy,
        )
        names = [item.name for item in ranked_candidates(offer)]
        picks.append(names)
        ks.append(len(names))
        expected = row.primary_expected_tools
        if expected and any(str(n).startswith("delete_") for n in expected):
            family_n += 1
            top = names[0] if names else ""
            if str(top).startswith("delete_") and top not in expected:
                family_fp += 1
    summary = _summarize(match, picks, ks)
    summary["k"] = k
    summary["weights"] = weights.get("name")
    summary["delete_family_false_positives"] = family_fp
    summary["delete_family_queries"] = family_n
    return summary


def main() -> None:
    report = run_phase8_evaluation(write_files=True)
    print(json.dumps({
        "best_adaptive": report["best_adaptive"],
        "fixed_k10": report["fixed"]["k10"]["recall"],
        "fixed_k15": report["fixed"]["k15"]["recall"],
        "best_hybrid": report["best_hybrid"],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
