"""Phase 11 — metadata-fixed candidate recall, final recall, indexed vs control latency.

Does not enable production flags. Adaptive K and Hybrid stay off.
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Dict, List, Sequence

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    CANDIDATE_RETRIEVAL_N,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_FALLBACK,
    INDEXED_CANDIDATE_RETRIEVAL,
    INDEXED_CANDIDATE_ROLLOUT_PERCENT,
    PROGRESSIVE_SCHEMA_LOADING,
    VECTOR_CANDIDATE_RETRIEVAL,
)
from app.services.ai.ai_tool_candidates import retrieve_candidates
from app.services.ai.ai_tool_discovery_eval import (
    permissioned_catalog,
)
from app.services.ai.ai_tool_discovery_gold import (
    GOLD_DATASET_VERSION,
    GoldQuery,
    load_gold_queries,
)
from app.services.ai.ai_tool_intent import query_expects_tool_use, ranking_intent_domains
from app.services.ai.ai_tool_phase10_eval import (
    CANDIDATE_NS,
    TARGET_CANDIDATE_RECALL,
    _hit,
    _mrr,
    evaluate_baseline_k,
    evaluate_candidate_n,
    evaluate_final_k,
    evaluate_no_match,
)
from app.services.ai.ai_tool_rank import score_tool_for_query
from app.services.ai.ai_tool_retrieval_index import ToolRetrievalIndex
from app.services.ai.ai_tool_scale_bench import QUERY, SIZES, _build_index, _catalog

PHASE11_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/phase-11")
FINAL_KS = (10, 15, 20, 48)
PHASE6_BASELINE = {
    10: 0.9549,
    15: 0.9752,
    20: 0.9819,
    48: 0.9819,
}
MISS_IDS = ("ppl-05", "acc-21", "hard-gen-01", "plat-01", "exp-158")
LATENCY_SIZES = (180, 1200, 5000, 10000)
LATENCY_RUNS = 8


def _list_misses(
    n: int,
    rows: List[GoldQuery],
    catalog: Sequence[str],
    index: ToolRetrievalIndex,
) -> List[Dict[str, Any]]:
    misses: List[Dict[str, Any]] = []
    for row in rows:
        if row.no_match:
            continue
        hist = list(row.history) if row.history else None
        offer = retrieve_candidates(
            row.query,
            catalog,
            n=n,
            intent_domains=ranking_intent_domains(row.query, hist),
            expects_tools=query_expects_tool_use(row.query, hist),
            fallback_on_empty=False,
            include_vector=False,
            index=index,
        )
        if _hit(row, offer.names):
            continue
        misses.append(
            {
                "id": row.id,
                "query": row.query,
                "expected": list(row.primary_expected_tools),
                "candidate_count": len(offer.names),
            }
        )
    return misses


def _percentile(values: List[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = int(round((p / 100.0) * (len(ordered) - 1)))
    idx = max(0, min(len(ordered) - 1, idx))
    return round(ordered[idx], 3)


def _posting_map(index: ToolRetrievalIndex) -> Dict[str, List[str]]:
    out: Dict[str, List[str]] = {}
    for name in sorted(index.names()):
        rec = index.get(name)
        if rec is None or not rec.is_searchable():
            continue
        for token in rec.tokens:
            out.setdefault(token, []).append(name)
    return {token: sorted(names) for token, names in out.items()}


def evaluate_incremental_consistency() -> Dict[str, Any]:
    names = [
        "search_invoices",
        "list_accounts",
        "get_person_balance",
        "list_currencies",
        "get_business_dashboard",
        "get_business_info",
    ]
    full = ToolRetrievalIndex()
    full.load_many((name, "") for name in names)
    incremental = ToolRetrievalIndex()
    for name in names:
        incremental.upsert(name)
    bounced = ToolRetrievalIndex()
    for name in names:
        bounced.upsert(name)
        bounced.disable(name)
        bounced.enable(name)
    full_map = _posting_map(full)
    ok = full_map == _posting_map(incremental) == _posting_map(bounced)
    return {
        "pass": ok,
        "tools": len(names),
        "posting_keys": len(full_map),
    }


def evaluate_latency() -> List[Dict[str, Any]]:
    rows = []
    for size in LATENCY_SIZES:
        if size not in SIZES and size not in (180, 1200, 5000, 10000):
            continue
        names = _catalog(size)
        index = _build_index(names)
        control: List[float] = []
        indexed: List[float] = []
        for _ in range(LATENCY_RUNS):
            t0 = time.perf_counter()
            for name in names:
                score_tool_for_query(name, QUERY)
            control.append((time.perf_counter() - t0) * 1000.0)

            t1 = time.perf_counter()
            offer = retrieve_candidates(
                QUERY,
                names,
                n=CANDIDATE_RETRIEVAL_N,
                fallback_on_empty=False,
                include_vector=False,
                index=index,
                expects_tools=True,
            )
            for name in offer.names:
                score_tool_for_query(name, QUERY)
            indexed.append((time.perf_counter() - t1) * 1000.0)
        rows.append(
            {
                "size": size,
                "control_p50_ms": _percentile(control, 50),
                "control_p95_ms": _percentile(control, 95),
                "indexed_p50_ms": _percentile(indexed, 50),
                "indexed_p95_ms": _percentile(indexed, 95),
            }
        )
    return rows


def run_phase11_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    gold = load_gold_queries()
    catalog = permissioned_catalog()
    index = ToolRetrievalIndex()
    stats = index.rebuild_from_manifest(catalog)
    candidate = [evaluate_candidate_n(n, gold, catalog, index) for n in CANDIDATE_NS]
    recall100 = next(row["candidate_recall"] for row in candidate if row["n"] == 100)
    misses100 = _list_misses(100, gold, catalog, index)
    indexed_final = [
        evaluate_final_k(k, gold, catalog, index, candidate_n=CANDIDATE_RETRIEVAL_N)
        for k in FINAL_KS
    ]
    baseline = [evaluate_baseline_k(k, gold, catalog) for k in FINAL_KS]
    none = evaluate_no_match(gold, catalog, index, n=CANDIDATE_RETRIEVAL_N)
    consistency = evaluate_incremental_consistency()
    latency = evaluate_latency()
    five = []
    by_id = {row.id: row for row in gold}
    for qid in MISS_IDS:
        row = by_id[qid]
        offer = retrieve_candidates(
            row.query,
            catalog,
            n=100,
            intent_domains=ranking_intent_domains(row.query),
            expects_tools=query_expects_tool_use(row.query),
            fallback_on_empty=False,
            include_vector=False,
            index=index,
        )
        five.append(
            {
                "id": qid,
                "query": row.query,
                "expected": list(row.primary_expected_tools),
                "hit": _hit(row, offer.names),
                "rank": next(
                    (
                        i
                        for i, name in enumerate(offer.names, start=1)
                        if name in row.primary_expected_tools
                    ),
                    None,
                ),
            }
        )
    report = {
        "dataset_version": GOLD_DATASET_VERSION,
        "index": {
            "kind": "inverted_keyword_v1",
            "tools": stats.tools,
            "postings": stats.postings,
            "build_ms": stats.build_ms,
            "memory_bytes_est": stats.memory_bytes_est,
        },
        "five_metadata_misses": five,
        "candidate_recall": candidate,
        "remaining_misses_at_100": misses100,
        "target_candidate_recall": TARGET_CANDIDATE_RECALL,
        "candidate_recall_100_met": recall100 >= TARGET_CANDIDATE_RECALL,
        "indexed_final": indexed_final,
        "baseline_final": baseline,
        "phase6_baseline": PHASE6_BASELINE,
        "no_match": none,
        "incremental_consistency": consistency,
        "latency": latency,
        "flags": {
            "INDEXED_CANDIDATE_RETRIEVAL": INDEXED_CANDIDATE_RETRIEVAL,
            "INDEXED_CANDIDATE_ROLLOUT_PERCENT": INDEXED_CANDIDATE_ROLLOUT_PERCENT,
            "INDEXED_CANDIDATE_FALLBACK": INDEXED_CANDIDATE_FALLBACK,
            "VECTOR_CANDIDATE_RETRIEVAL": VECTOR_CANDIDATE_RETRIEVAL,
            "CANDIDATE_RETRIEVAL_N": CANDIDATE_RETRIEVAL_N,
            "HYBRID_TOOL_DISCOVERY": HYBRID_TOOL_DISCOVERY,
            "ADAPTIVE_DISCOVERY_K": ADAPTIVE_DISCOVERY_K,
            "ADAPTIVE_K_ROLLOUT_PERCENT": ADAPTIVE_K_ROLLOUT_PERCENT,
            "PROGRESSIVE_SCHEMA_LOADING": PROGRESSIVE_SCHEMA_LOADING,
        },
        "note": (
            "Indexed retrieval is canary-ready at 0%. Production still ranks "
            "the full authorized set. Adaptive K HOLD. Hybrid OFF."
        ),
    }
    if write_files:
        PHASE11_DIR.mkdir(parents=True, exist_ok=True)
        (PHASE11_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        (PHASE11_DIR / "README.md").write_text(
            "\n".join(
                [
                    "# Phase 11 evaluation outputs",
                    "",
                    "- [`latest.json`](latest.json) — metadata-fixed Candidate Recall, Final Recall, latency",
                    "",
                    "```bash",
                    "cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_phase11_eval",
                    "```",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return report


def main() -> None:
    report = run_phase11_evaluation(write_files=True)
    print(
        json.dumps(
            {
                "five_metadata_misses": report["five_metadata_misses"],
                "candidate_recall": report["candidate_recall"],
                "remaining_misses_at_100": report["remaining_misses_at_100"],
                "indexed_final": report["indexed_final"],
                "baseline_final": report["baseline_final"],
                "incremental_consistency": report["incremental_consistency"],
                "latency": report["latency"],
                "flags": report["flags"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
