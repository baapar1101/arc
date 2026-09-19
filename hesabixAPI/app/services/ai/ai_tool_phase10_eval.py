"""Phase 10 — candidate recall, index vs linear, Gold final recall.

Does not enable production flags. Adaptive K and Hybrid stay off.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Sequence

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    CANDIDATE_RETRIEVAL_N,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_RETRIEVAL,
    PROGRESSIVE_SCHEMA_LOADING,
    VECTOR_CANDIDATE_RETRIEVAL,
)
from app.services.ai.ai_tool_candidates import retrieve_candidates
from app.services.ai.ai_tool_discovery_eval import (
    discover_ranked,
    ndcg_at_k,
    permissioned_catalog,
    ranked_candidates,
)
from app.services.ai.ai_tool_discovery_gold import (
    GOLD_DATASET_VERSION,
    GoldQuery,
    load_gold_queries,
)
from app.services.ai.ai_tool_intent import query_expects_tool_use, ranking_intent_domains
from app.services.ai.ai_tool_retrieval_index import ToolRetrievalIndex

PHASE10_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/phase-10")
CANDIDATE_NS = (20, 50, 100, 200)
FINAL_KS = (10, 15, 20)
TARGET_CANDIDATE_RECALL = 0.99


def _hit(row: GoldQuery, names: Sequence[str]) -> bool:
    primary = row.primary_expected_tools
    return bool(primary) and any(n in names for n in primary)


def _mrr(row: GoldQuery, names: Sequence[str]) -> float:
    wanted = set(row.primary_expected_tools)
    for i, name in enumerate(names, start=1):
        if name in wanted:
            return 1.0 / i
    return 0.0


def evaluate_candidate_n(
    n: int,
    rows: List[GoldQuery],
    catalog: Sequence[str],
    index: ToolRetrievalIndex,
) -> Dict[str, Any]:
    match = [row for row in rows if not row.no_match]
    hits = 0
    latencies: List[float] = []
    for row in match:
        offer = retrieve_candidates(
            row.query,
            catalog,
            n=n,
            intent_domains=ranking_intent_domains(
                row.query, list(row.history) if row.history else None
            ),
            expects_tools=query_expects_tool_use(
                row.query, list(row.history) if row.history else None
            ),
            fallback_on_empty=False,
            include_vector=False,
            index=index,
        )
        latencies.append(offer.latency_ms)
        if _hit(row, offer.names):
            hits += 1
    total = max(1, len(match))
    ordered = sorted(latencies)
    p50 = ordered[len(ordered) // 2] if ordered else 0.0
    p95 = ordered[int(round(0.95 * (len(ordered) - 1)))] if ordered else 0.0
    return {
        "n": n,
        "queries": len(match),
        "candidate_recall": round(hits / total, 4),
        "latency_p50_ms": round(p50, 3),
        "latency_p95_ms": round(p95, 3),
        "avg_latency_ms": round(sum(latencies) / total, 3) if match else 0.0,
    }


def evaluate_final_k(
    k: int,
    rows: List[GoldQuery],
    catalog: Sequence[str],
    index: ToolRetrievalIndex,
    *,
    candidate_n: int,
) -> Dict[str, Any]:
    from app.services.ai.ai_tool_discovery import discover_tools
    from app.services.ai.ai_tool_discovery_eval import mode_for_query

    match = [row for row in rows if not row.no_match]
    hits = 0
    mrr = 0.0
    ndcg = 0.0
    for row in match:
        hist = list(row.history) if row.history else None
        offer = retrieve_candidates(
            row.query,
            catalog,
            n=candidate_n,
            intent_domains=ranking_intent_domains(row.query, hist),
            expects_tools=query_expects_tool_use(row.query, hist),
            fallback_on_empty=False,
            include_vector=False,
            index=index,
        )
        pool = list(offer.as_set() or catalog)
        disc = discover_tools(
            row.query,
            permissioned_names=pool,
            execution_mode=mode_for_query(row),
            limit=k,
            history_messages=hist,
            channel="eval",
        )
        names = [item.name for item in ranked_candidates(disc)]
        if _hit(row, names):
            hits += 1
        mrr += _mrr(row, names)
        ndcg += ndcg_at_k(names, row.relevance_map(), k)
    total = max(1, len(match))
    return {
        "k": k,
        "candidate_n": candidate_n,
        "recall": round(hits / total, 4),
        "mrr": round(mrr / total, 4),
        "ndcg": round(ndcg / total, 4),
    }


def evaluate_baseline_k(k: int, rows: List[GoldQuery], catalog: Sequence[str]) -> Dict[str, Any]:
    match = [row for row in rows if not row.no_match]
    hits = 0
    for row in match:
        offer = discover_ranked(row, k=k, catalog=catalog)
        names = [item.name for item in ranked_candidates(offer)]
        if _hit(row, names):
            hits += 1
    return {"k": k, "recall": round(hits / max(1, len(match)), 4)}


def evaluate_no_match(
    rows: List[GoldQuery],
    catalog: Sequence[str],
    index: ToolRetrievalIndex,
    *,
    n: int,
) -> Dict[str, Any]:
    none = [row for row in rows if row.no_match]
    empty = 0
    for row in none:
        offer = retrieve_candidates(
            row.query,
            catalog,
            n=n,
            fallback_on_empty=False,
            include_vector=False,
            index=index,
            expects_tools=False,
        )
        if offer.empty or not offer.names:
            empty += 1
    return {
        "queries": len(none),
        "empty_candidate_set": empty,
        "empty_rate": round(empty / max(1, len(none)), 4),
    }


def run_phase10_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    gold = load_gold_queries()
    catalog = permissioned_catalog()
    index = ToolRetrievalIndex()
    stats = index.rebuild_from_manifest(catalog)
    candidate = [evaluate_candidate_n(n, gold, catalog, index) for n in CANDIDATE_NS]
    viable = [row for row in candidate if row["candidate_recall"] >= TARGET_CANDIDATE_RECALL]
    chosen = min(viable, key=lambda row: row["n"]) if viable else max(
        candidate, key=lambda row: (row["candidate_recall"], -row["n"])
    )
    chosen_n = int(chosen["n"])
    indexed_final = [
        evaluate_final_k(k, gold, catalog, index, candidate_n=chosen_n) for k in FINAL_KS
    ]
    baseline = [evaluate_baseline_k(k, gold, catalog) for k in FINAL_KS]
    none = evaluate_no_match(gold, catalog, index, n=chosen_n)
    report = {
        "dataset_version": GOLD_DATASET_VERSION,
        "index": {
            "kind": "inverted_keyword_v1",
            "tools": stats.tools,
            "postings": stats.postings,
            "build_ms": stats.build_ms,
            "memory_bytes_est": stats.memory_bytes_est,
        },
        "candidate_recall": candidate,
        "chosen_candidate_n": chosen_n,
        "target_candidate_recall": TARGET_CANDIDATE_RECALL,
        "indexed_final": indexed_final,
        "baseline_final": baseline,
        "no_match": none,
        "flags": {
            "INDEXED_CANDIDATE_RETRIEVAL": INDEXED_CANDIDATE_RETRIEVAL,
            "VECTOR_CANDIDATE_RETRIEVAL": VECTOR_CANDIDATE_RETRIEVAL,
            "CANDIDATE_RETRIEVAL_N": CANDIDATE_RETRIEVAL_N,
            "HYBRID_TOOL_DISCOVERY": HYBRID_TOOL_DISCOVERY,
            "ADAPTIVE_DISCOVERY_K": ADAPTIVE_DISCOVERY_K,
            "ADAPTIVE_K_ROLLOUT_PERCENT": ADAPTIVE_K_ROLLOUT_PERCENT,
            "PROGRESSIVE_SCHEMA_LOADING": PROGRESSIVE_SCHEMA_LOADING,
        },
        "note": (
            "Candidate retrieval is opt-in. Production still ranks the full "
            "authorized set at K=48/128. Vector ANN is not production."
        ),
    }
    if write_files:
        PHASE10_DIR.mkdir(parents=True, exist_ok=True)
        (PHASE10_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        (PHASE10_DIR / "README.md").write_text(
            "\n".join(
                [
                    "# Phase 10 evaluation outputs",
                    "",
                    "- [`latest.json`](latest.json) — Candidate Recall@N and indexed vs baseline final recall",
                    "",
                    "```bash",
                    "cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_phase10_eval",
                    "cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_scale_bench",
                    "```",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return report


def main() -> None:
    report = run_phase10_evaluation(write_files=True)
    print(
        json.dumps(
            {
                "chosen_n": report["chosen_candidate_n"],
                "candidate_recall": report["candidate_recall"],
                "indexed_final": report["indexed_final"],
                "baseline_final": report["baseline_final"],
                "no_match": report["no_match"],
                "index": report["index"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
