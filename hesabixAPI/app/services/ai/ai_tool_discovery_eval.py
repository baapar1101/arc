"""Provider-independent retrieval evaluation for discover_tools().

Measures Keyword/Intent ranking at Tight Top-K. No embeddings.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from app.services.ai.ai_constants import (
    CONTEXT_INPUT_TOKEN_BUDGET,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    QUERY_COMPLEXITY_ITERATIONS,
)
from app.services.ai.ai_context_budget import estimate_text_tokens
from app.services.ai.ai_execution_policy import EXECUTION_MODE_ANALYZER
from app.services.ai.ai_tool_discovery import DiscoveryOffer, ToolCandidate, discover_tools
from app.services.ai.ai_tool_discovery_gold import (
    GOLD_DATASET_VERSION,
    INTENT_DELETE,
    INTENT_EXECUTE,
    INTENT_EXPORT,
    INTENT_NONE,
    INTENT_WRITE,
    TOOL_CATALOG_VERSION,
    GoldQuery,
    gold_stats,
    load_gold_queries,
)
from app.services.ai.ai_tool_intent import iterations_for_query, query_expects_tool_use
from app.services.ai.ai_tool_manifest import get_manifest_entry, iter_manifest_names

K_SWEEP: Tuple[int, ...] = (3, 5, 8, 10, 12, 15, 20, 30, 48, 64, 128)
PRIMARY_KS: Tuple[int, ...] = (5, 10, 15, 20, 48)
EVAL_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/tool-discovery")

# Floors set after measuring the v1 baseline (see phase-5 doc). Slightly
# below observed values so CI catches regressions, not noise.
CI_RECALL_AT_10_MIN = 0.30
CI_RECALL_AT_20_MIN = 0.75
CI_RECALL_AT_48_MIN = 0.85
CI_LEGACY_RECALL_AT_48_MIN = 0.95
CI_RETRIEVAL_SUCCESS_AT_15_MIN = 0.65


def permissioned_catalog() -> List[str]:
    return sorted(iter_manifest_names())


def mode_for_query(row: GoldQuery) -> str:
    if row.intent in {INTENT_WRITE, INTENT_DELETE, INTENT_EXPORT, INTENT_EXECUTE}:
        return "supervised"
    return EXECUTION_MODE_ANALYZER


def ranked_candidates(offer: DiscoveryOffer) -> List[ToolCandidate]:
    return sorted(offer.candidates, key=lambda item: (-int(item.score), item.name))


def score_gap(ranked: Sequence[ToolCandidate]) -> Dict[str, int]:
    top = int(ranked[0].score) if ranked else 0
    second = int(ranked[1].score) if len(ranked) > 1 else 0
    return {
        "top_score": top,
        "second_score": second,
        "score_gap": top - second,
    }


def adaptive_k(ranked: Sequence[ToolCandidate], *, expects_tools: bool) -> int:
    """Evaluate-only prototype. Not wired into production discovery."""
    gap = score_gap(ranked)
    if not expects_tools and gap["top_score"] <= 4:
        return 5
    if gap["top_score"] >= 14 and gap["score_gap"] >= 8:
        return 5
    if gap["top_score"] >= 8 and gap["score_gap"] >= 4:
        return 10
    return 20


def dcg(relevances: Sequence[int]) -> float:
    total = 0.0
    for i, rel in enumerate(relevances, start=1):
        if rel <= 0:
            continue
        total += (2**rel - 1) / math.log2(i + 1)
    return total


def ndcg_at_k(returned: Sequence[str], relevance: Dict[str, int], k: int) -> float:
    gained = [relevance.get(name, 0) for name in returned[:k]]
    ideal = sorted(relevance.values(), reverse=True)[:k]
    denom = dcg(ideal)
    if denom <= 0:
        return 1.0 if not any(gained) else 0.0
    return dcg(gained) / denom


def first_rank(returned: Sequence[str], wanted: Iterable[str]) -> Optional[int]:
    wanted_set = set(wanted)
    for i, name in enumerate(returned, start=1):
        if name in wanted_set:
            return i
    return None


@dataclass
class QueryOutcome:
    query_id: str
    query: str
    k: int
    mode: str
    primary: Tuple[str, ...]
    returned: Tuple[str, ...]
    ranks: Dict[str, Optional[int]]
    scores: Dict[str, int]
    hit: bool
    multi_hit: bool
    retrieval_success: bool
    precision: float
    ndcg: float
    mrr: float
    category: str
    difficulty: str
    hard_case: str
    no_match: bool
    low_confidence: bool
    no_match_ok: bool
    top_score: int
    second_score: int
    score_gap: int
    schema_tokens: int
    iterations: int
    iteration_schema_tokens: int
    failure_reason: str = ""


_SCHEMA_CHAR_CACHE: Optional[Dict[str, int]] = None


def _schema_char_map() -> Dict[str, int]:
    global _SCHEMA_CHAR_CACHE
    if _SCHEMA_CHAR_CACHE is not None:
        return _SCHEMA_CHAR_CACHE
    from app.services.ai import ai_tool_payloads as payloads

    schema_by_prefix: Dict[str, int] = {}
    for key, val in vars(payloads).items():
        if not key.endswith("_PARAMETERS_SCHEMA") or not isinstance(val, dict):
            continue
        stem = key[: -len("_PARAMETERS_SCHEMA")].lower()
        schema_by_prefix[stem] = len(json.dumps(val, ensure_ascii=False))
    desc_by_prefix: Dict[str, int] = {}
    for key, val in vars(payloads).items():
        if key.endswith("_DESCRIPTION") and isinstance(val, str):
            desc_by_prefix[key[: -len("_DESCRIPTION")].lower()] = len(val)
    out: Dict[str, int] = {}
    for name in iter_manifest_names():
        entry = get_manifest_entry(name)
        desc = ""
        if entry:
            desc = entry.search_text(name, "")
        extra = schema_by_prefix.get(name, 800)
        out[name] = len(name) + len(desc) + extra
    _SCHEMA_CHAR_CACHE = out
    return out


def estimate_tools_schema_tokens(names: Sequence[str]) -> int:
    sizes = _schema_char_map()
    text_len = sum(sizes.get(name, 900) for name in names)
    return estimate_text_tokens(None, "x" * text_len) if text_len else 0


def discover_ranked(
    row: GoldQuery,
    *,
    k: int,
    catalog: Optional[Sequence[str]] = None,
) -> DiscoveryOffer:
    names = list(catalog or permissioned_catalog())
    return discover_tools(
        row.query,
        permissioned_names=names,
        execution_mode=mode_for_query(row),
        limit=k,
        history_messages=list(row.history) if row.history else None,
        channel="eval",
    )


def _failure_reason(row: GoldQuery, ranked: Sequence[ToolCandidate], hit: bool) -> str:
    if row.no_match or hit:
        return ""
    names = [item.name for item in ranked[:12]]
    missing = [t for t in row.primary_expected_tools if t not in set(names)]
    top = ranked[0].name if ranked else ""
    reasons = []
    if missing:
        reasons.append("missing_primary:" + ",".join(missing))
    if top and top not in row.success_tools():
        reasons.append(f"wrong_top:{top}")
    q = row.query.lower()
    for tool in missing:
        entry = get_manifest_entry(tool)
        aliases = " ".join(entry.aliases).lower() if entry else ""
        if aliases and not any(a and a in q for a in aliases.split()):
            reasons.append(f"alias_gap:{tool}")
        cap = entry.capability if entry else ""
        if cap and cap not in q and row.required_capability and row.required_capability != cap:
            reasons.append(f"capability_mismatch:{tool}")
    if not reasons:
        reasons.append("intent_or_keyword")
    return ";".join(reasons[:6])


def evaluate_query(row: GoldQuery, *, k: int, catalog: Sequence[str]) -> QueryOutcome:
    offer = discover_ranked(row, k=k, catalog=catalog)
    ranked = ranked_candidates(offer)
    returned = tuple(item.name for item in ranked)
    scores = {item.name: int(item.score) for item in ranked}
    gap = score_gap(ranked)
    expects = query_expects_tool_use(row.query, list(row.history) or None)
    low_conf = (not expects and gap["top_score"] <= 4) or gap["top_score"] <= 0
    primary = row.primary_expected_tools
    success = row.success_tools()
    ranks = {name: first_rank(returned, [name]) for name in primary}
    hit = bool(primary) and any(name in returned for name in primary)
    multi_hit = (not primary) or all(name in returned for name in primary)
    retrieval_success = hit if not row.require_all_primary else multi_hit
    if not primary and not row.no_match:
        retrieval_success = False
    if row.no_match:
        retrieval_success = low_conf or len(returned) == 0 or gap["top_score"] <= 4
        hit = retrieval_success
        multi_hit = retrieval_success
    relevant_hits = sum(1 for name in returned[:k] if name in success)
    precision = relevant_hits / max(1, min(k, len(returned)))
    ndcg = 1.0 if row.no_match else ndcg_at_k(returned, row.relevance_map(), k)
    rank = first_rank(returned, primary) if primary else None
    mrr = 0.0 if rank is None else 1.0 / rank
    tokens = estimate_tools_schema_tokens(returned)
    iters = iterations_for_query(row.query, list(row.history) or None)
    no_match_ok = True
    if row.no_match:
        no_match_ok = retrieval_success
    return QueryOutcome(
        query_id=row.id,
        query=row.query,
        k=k,
        mode=mode_for_query(row),
        primary=primary,
        returned=returned,
        ranks=ranks,
        scores=scores,
        hit=hit,
        multi_hit=multi_hit,
        retrieval_success=retrieval_success,
        precision=precision,
        ndcg=ndcg,
        mrr=mrr,
        category=row.category,
        difficulty=row.difficulty,
        hard_case=row.hard_case,
        no_match=row.no_match,
        low_confidence=low_conf,
        no_match_ok=no_match_ok,
        top_score=gap["top_score"],
        second_score=gap["second_score"],
        score_gap=gap["score_gap"],
        schema_tokens=tokens,
        iterations=iters,
        iteration_schema_tokens=tokens * iters,
        failure_reason=_failure_reason(row, ranked, hit if not row.no_match else True),
    )


def _mean(values: Sequence[float]) -> float:
    if not values:
        return 0.0
    return round(sum(values) / len(values), 4)


def summarize_outcomes(outcomes: Sequence[QueryOutcome]) -> Dict[str, Any]:
    match = [o for o in outcomes if not o.no_match]
    none = [o for o in outcomes if o.no_match]
    k = outcomes[0].k if outcomes else 0
    by_cat: Dict[str, List[QueryOutcome]] = {}
    by_diff: Dict[str, List[QueryOutcome]] = {}
    by_hard: Dict[str, List[QueryOutcome]] = {}
    for item in match:
        by_cat.setdefault(item.category or "other", []).append(item)
        by_diff.setdefault(item.difficulty or "easy", []).append(item)
        if item.hard_case:
            by_hard.setdefault(item.hard_case, []).append(item)

    def recall(items: Sequence[QueryOutcome]) -> float:
        if not items:
            return 0.0
        return round(sum(1 for o in items if o.hit) / len(items), 4)

    def multi(items: Sequence[QueryOutcome]) -> float:
        needed = [o for o in items if len(o.primary) > 1]
        if not needed:
            return 1.0
        return round(sum(1 for o in needed if o.multi_hit) / len(needed), 4)

    return {
        "k": k,
        "queries": len(match),
        "recall": recall(match),
        "multi_tool_recall": multi(match),
        "retrieval_success": recall([o for o in match]),  # hit uses primary
        "retrieval_success_rate": round(
            sum(1 for o in match if o.retrieval_success) / len(match), 4
        ) if match else 0.0,
        "mrr": _mean([o.mrr for o in match]),
        "precision": _mean([o.precision for o in match]),
        "ndcg": _mean([o.ndcg for o in match]),
        "avg_schema_tokens": round(_mean([float(o.schema_tokens) for o in match])),
        "avg_iteration_schema_tokens": round(
            _mean([float(o.iteration_schema_tokens) for o in match])
        ),
        "context_share": round(
            (_mean([float(o.schema_tokens) for o in match]) / CONTEXT_INPUT_TOKEN_BUDGET),
            4,
        ) if match else 0.0,
        "avg_top_score": _mean([float(o.top_score) for o in match]),
        "avg_score_gap": _mean([float(o.score_gap) for o in match]),
        "low_confidence_share": round(
            sum(1 for o in match if o.low_confidence) / len(match), 4
        ) if match else 0.0,
        "no_match_queries": len(none),
        "no_match_success": round(
            sum(1 for o in none if o.no_match_ok) / len(none), 4
        ) if none else 1.0,
        "per_category_recall": {
            cat: recall(items) for cat, items in sorted(by_cat.items())
        },
        "per_difficulty_recall": {
            diff: recall(items) for diff, items in sorted(by_diff.items())
        },
        "per_hard_case_recall": {
            tag: recall(items) for tag, items in sorted(by_hard.items())
        },
    }


def evaluate_at_k(
    k: int,
    *,
    rows: Optional[List[GoldQuery]] = None,
    catalog: Optional[Sequence[str]] = None,
) -> Tuple[Dict[str, Any], List[QueryOutcome]]:
    gold = rows if rows is not None else load_gold_queries()
    names = list(catalog or permissioned_catalog())
    outcomes = [evaluate_query(row, k=k, catalog=names) for row in gold]
    summary = summarize_outcomes(outcomes)
    summary["dataset_version"] = GOLD_DATASET_VERSION
    summary["tool_catalog_version"] = TOOL_CATALOG_VERSION
    return summary, outcomes


def sweep_k(
    ks: Sequence[int] = K_SWEEP,
    *,
    rows: Optional[List[GoldQuery]] = None,
    catalog: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    gold = rows if rows is not None else load_gold_queries()
    names = list(catalog or permissioned_catalog())
    by_k = {}
    for k in ks:
        summary, _ = evaluate_at_k(k, rows=gold, catalog=names)
        by_k[str(k)] = summary
    return {
        "dataset_version": GOLD_DATASET_VERSION,
        "tool_catalog_version": TOOL_CATALOG_VERSION,
        "dataset": gold_stats(gold),
        "baseline_analyzer_k": MAX_TOOLS_PER_REQUEST,
        "baseline_supervised_k": MAX_TOOLS_AUTONOMOUS,
        "by_k": by_k,
    }


def recommend_k(by_k: Dict[str, Any]) -> Dict[str, Any]:
    """Choose analyzer K from measured recall — not intuition."""
    def rec(k: int) -> float:
        return float((by_k.get(str(k)) or {}).get("recall") or 0.0)

    r10, r15, r20, r48 = rec(10), rec(15), rec(20), rec(48)
    if r20 < 0.90:
        decision = "C"
        k = MAX_TOOLS_PER_REQUEST
        note = "Even K=20 recall is below 90%. Do not deploy Tight Top-K."
    elif r10 >= 0.95 and r15 >= 0.97:
        decision = "A"
        k = 10
        note = "K=10 holds high recall; Tight Top-K is justified."
    elif r15 >= 0.95 or (r15 >= 0.93 and r20 >= 0.95):
        decision = "A"
        k = 15
        note = "K=15 is the smallest K with acceptable recall."
    elif r20 >= 0.94:
        decision = "A"
        k = 20
        note = "Need K=20 to keep recall acceptable."
    else:
        decision = "B"
        k = MAX_TOOLS_PER_REQUEST
        note = "Keyword/Intent is weak on some categories; improve metadata before cutting K."
    if decision == "A" and r48 - r20 > 0.05:
        decision = "B"
        note += " Gap versus K=48 is still large on some queries."
    return {
        "decision": decision,
        "recommended_analyzer_k": k,
        "recall_at_10": r10,
        "recall_at_15": r15,
        "recall_at_20": r20,
        "recall_at_48": r48,
        "note": note,
        "keep_autonomous_k": MAX_TOOLS_AUTONOMOUS,
    }


def failure_rows(outcomes: Sequence[QueryOutcome], *, limit: int = 50) -> List[Dict[str, Any]]:
    failed = [o for o in outcomes if (not o.no_match and not o.retrieval_success)]
    failed.sort(key=lambda o: (o.difficulty != "hard", o.mrr, o.query_id))
    out = []
    for item in failed[:limit]:
        out.append({
            "id": item.query_id,
            "query": item.query,
            "expected": list(item.primary),
            "returned_top": list(item.returned[:12]),
            "wrong_top": item.returned[0] if item.returned else "",
            "reason": item.failure_reason,
            "category": item.category,
            "difficulty": item.difficulty,
            "hard_case": item.hard_case,
            "top_score": item.top_score,
            "score_gap": item.score_gap,
        })
    return out


def evaluate_adaptive(rows: Optional[List[GoldQuery]] = None) -> Dict[str, Any]:
    gold = rows if rows is not None else load_gold_queries()
    catalog = permissioned_catalog()
    hits = 0
    match = [row for row in gold if not row.no_match]
    ks: List[int] = []
    for row in match:
        wide = discover_ranked(row, k=20, catalog=catalog)
        ranked = ranked_candidates(wide)
        k = adaptive_k(
            ranked,
            expects_tools=query_expects_tool_use(row.query, list(row.history) or None),
        )
        ks.append(k)
        outcome = evaluate_query(row, k=k, catalog=catalog)
        if outcome.retrieval_success:
            hits += 1
    return {
        "queries": len(match),
        "retrieval_success": round(hits / len(match), 4) if match else 0.0,
        "avg_k": round(sum(ks) / len(ks), 2) if ks else 0.0,
        "k_histogram": {
            str(val): ks.count(val) for val in sorted(set(ks))
        },
    }


def run_full_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    gold = load_gold_queries()
    catalog = permissioned_catalog()
    sweep = sweep_k(PRIMARY_KS + (3, 8, 12, 30, 64, 128), rows=gold, catalog=catalog)
    rec = recommend_k(sweep["by_k"])
    summary15, outcomes15 = evaluate_at_k(15, rows=gold, catalog=catalog)
    summary48, outcomes48 = evaluate_at_k(48, rows=gold, catalog=catalog)
    legacy = [row for row in gold if row.source == "legacy"]
    legacy48, _ = evaluate_at_k(48, rows=legacy, catalog=catalog)
    adaptive = evaluate_adaptive(gold)
    failures = failure_rows(outcomes15, limit=50)
    failed_n = sum(1 for o in outcomes15 if not o.no_match and not o.retrieval_success)
    report = {
        "dataset_version": GOLD_DATASET_VERSION,
        "tool_catalog_version": TOOL_CATALOG_VERSION,
        "dataset": gold_stats(gold),
        "baseline_k48": {
            "k": 48,
            "recall": summary48["recall"],
            "mrr": summary48["mrr"],
            "precision": summary48["precision"],
            "ndcg": summary48["ndcg"],
            "retrieval_success_rate": summary48["retrieval_success_rate"],
        },
        "legacy_k48": {
            "k": 48,
            "recall": legacy48["recall"],
            "queries": legacy48["queries"],
        },
        "by_k": sweep["by_k"],
        "k15": summary15,
        "recommended": rec,
        "adaptive": adaptive,
        "failure_count_at_15": failed_n,
        "failures_at_15": failures,
        "iteration": {
            "schema_resent_every_iteration": True,
            "complexity_iterations": QUERY_COMPLEXITY_ITERATIONS,
            "avg_iterations_at_k15": round(
                sum(o.iterations for o in outcomes15 if not o.no_match)
                / max(1, sum(1 for o in outcomes15 if not o.no_match)),
                2,
            ),
            "avg_schema_tokens_per_iteration_k15": summary15["avg_schema_tokens"],
            "avg_total_schema_tokens_per_request_k15": summary15["avg_iteration_schema_tokens"],
            "avg_total_schema_tokens_per_request_k48": summary48["avg_iteration_schema_tokens"],
        },
        "ci_gates": {
            "recall_at_10_min": CI_RECALL_AT_10_MIN,
            "recall_at_20_min": CI_RECALL_AT_20_MIN,
            "recall_at_48_min": CI_RECALL_AT_48_MIN,
            "legacy_recall_at_48_min": CI_LEGACY_RECALL_AT_48_MIN,
            "retrieval_success_at_15_min": CI_RETRIEVAL_SUCCESS_AT_15_MIN,
        },
    }
    if write_files:
        write_eval_artifacts(report, gold)
    return report


def write_eval_artifacts(report: Dict[str, Any], gold: List[GoldQuery]) -> None:
    EVAL_DIR.mkdir(parents=True, exist_ok=True)
    (EVAL_DIR / "gold_queries.v1.json").write_text(
        json.dumps(
            {
                "dataset_version": GOLD_DATASET_VERSION,
                "tool_catalog_version": TOOL_CATALOG_VERSION,
                "queries": [row.to_dict() for row in gold],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    compact = {
        "dataset_version": report["dataset_version"],
        "tool_catalog_version": report["tool_catalog_version"],
        "dataset": report["dataset"],
        "baseline_k48": report["baseline_k48"],
        "legacy_k48": report["legacy_k48"],
        "by_k": {
            k: {
                "k": v["k"],
                "recall": v["recall"],
                "multi_tool_recall": v["multi_tool_recall"],
                "mrr": v["mrr"],
                "precision": v["precision"],
                "ndcg": v["ndcg"],
                "retrieval_success_rate": v["retrieval_success_rate"],
                "avg_schema_tokens": v["avg_schema_tokens"],
                "context_share": v["context_share"],
                "no_match_success": v["no_match_success"],
                "per_category_recall": v["per_category_recall"],
                "per_difficulty_recall": v["per_difficulty_recall"],
                "per_hard_case_recall": v["per_hard_case_recall"],
            }
            for k, v in report["by_k"].items()
        },
        "recommended": report["recommended"],
        "adaptive": report["adaptive"],
        "iteration": report["iteration"],
        "ci_gates": report["ci_gates"],
        "failure_count_at_15": report["failure_count_at_15"],
        "failures_at_15": report["failures_at_15"][:50],
    }
    (EVAL_DIR / "latest.json").write_text(
        json.dumps(compact, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    for k in ("10", "15", "20", "48"):
        if k in compact["by_k"]:
            (EVAL_DIR / f"k{k}.json").write_text(
                json.dumps(compact["by_k"][k], ensure_ascii=False, indent=2),
                encoding="utf-8",
            )


def main() -> None:
    report = run_full_evaluation(write_files=True)
    rec = report["recommended"]
    print(json.dumps({
        "queries": report["dataset"]["queries"],
        "recall@10": rec["recall_at_10"],
        "recall@15": rec["recall_at_15"],
        "recall@20": rec["recall_at_20"],
        "recall@48": rec["recall_at_48"],
        "decision": rec["decision"],
        "recommended_k": rec["recommended_analyzer_k"],
        "legacy@48": report["legacy_k48"]["recall"],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
