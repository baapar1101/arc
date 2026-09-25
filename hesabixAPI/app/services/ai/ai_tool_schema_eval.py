"""Phase 7 schema-loading evaluation.

Discovery recall is measured with discover_tools() (must match Phase 6).
Wire vs construction token costs are simulated without an LLM provider.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

from app.services.ai.ai_constants import (
    MAX_TOOLS_PER_REQUEST,
    QUERY_COMPLEXITY_ITERATIONS,
)
from app.services.ai.ai_tool_discovery_eval import (
    discover_ranked,
    estimate_tools_schema_tokens,
    permissioned_catalog,
    ranked_candidates,
)
from app.services.ai.ai_tool_discovery_gold import (
    GOLD_DATASET_VERSION,
    GoldQuery,
    load_gold_queries,
)
from app.services.ai.ai_tool_intent import iterations_for_query

EVAL_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/tool-schema-loading")

# Phase 6 floors — schema loading must not change retrieval.
PHASE6_RECALL_AT_10 = 0.90
PHASE6_RECALL_AT_15 = 0.92
PHASE6_RECALL_AT_20 = 0.93


def _simulate_query(
    row: GoldQuery,
    *,
    k: int,
    progressive: bool,
    catalog: Sequence[str],
) -> Dict[str, int]:
    offer = discover_ranked(row, k=k, catalog=catalog)
    names = [item.name for item in ranked_candidates(offer)]
    iters = max(1, iterations_for_query(row.query, list(row.history) or None))
    if not names:
        return {
            "iters": iters,
            "initial_tokens": 0,
            "additional_tokens": 0,
            "wire_tokens": 0,
            "construction_count": 0,
            "hit": 0,
        }
    primary = row.primary_expected_tools
    hit = int(bool(primary) and any(n in names for n in primary))
    if not progressive:
        per = estimate_tools_schema_tokens(names)
        return {
            "iters": iters,
            "initial_tokens": per,
            "additional_tokens": 0,
            "wire_tokens": per * iters,
            "construction_count": len(names),
            "hit": hit,
        }
    extra = [n for n in primary if n not in names]
    union = list(names) + extra
    initial = estimate_tools_schema_tokens(names)
    full = estimate_tools_schema_tokens(union)
    additional = max(0, full - initial)
    wire = initial + full * max(0, iters - 1)
    return {
        "iters": iters,
        "initial_tokens": initial,
        "additional_tokens": additional,
        "wire_tokens": wire,
        "construction_count": len(union),
        "hit": hit,
    }


def simulate_mode(
    *,
    k: int,
    progressive: bool,
    rows: Optional[List[GoldQuery]] = None,
    catalog: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    gold = rows if rows is not None else load_gold_queries()
    names = list(catalog or permissioned_catalog())
    match = [row for row in gold if not row.no_match]
    samples = [_simulate_query(row, k=k, progressive=progressive, catalog=names) for row in match]
    n = max(1, len(samples))
    recall = round(sum(s["hit"] for s in samples) / n, 4)
    avg_iters = round(sum(s["iters"] for s in samples) / n, 2)
    return {
        "k": k,
        "progressive": progressive,
        "queries": len(match),
        "recall": recall,
        "avg_iterations": avg_iters,
        "avg_initial_schema_tokens": round(sum(s["initial_tokens"] for s in samples) / n),
        "avg_additional_schema_tokens": round(sum(s["additional_tokens"] for s in samples) / n),
        "avg_wire_schema_tokens_per_request": round(sum(s["wire_tokens"] for s in samples) / n),
        "avg_construction_tools": round(sum(s["construction_count"] for s in samples) / n, 2),
        "total_wire_schema_tokens": sum(s["wire_tokens"] for s in samples),
    }


def run_schema_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    gold = load_gold_queries()
    catalog = permissioned_catalog()
    modes = {
        "current_k48": simulate_mode(k=48, progressive=False, rows=gold, catalog=catalog),
        "current_k20": simulate_mode(k=20, progressive=False, rows=gold, catalog=catalog),
        "progressive_k15": simulate_mode(k=15, progressive=True, rows=gold, catalog=catalog),
        "progressive_k10": simulate_mode(k=10, progressive=True, rows=gold, catalog=catalog),
    }
    # Discovery is unchanged by progressive loading; recall@K comes from the same ranking.
    s10 = modes["progressive_k10"]
    s15 = modes["progressive_k15"]
    s20 = modes["current_k20"]
    s48 = modes["current_k48"]
    baseline_wire = modes["current_k48"]["avg_wire_schema_tokens_per_request"]
    prog15_wire = modes["progressive_k15"]["avg_wire_schema_tokens_per_request"]
    reduction = 0.0
    if baseline_wire:
        reduction = round(1.0 - (prog15_wire / baseline_wire), 4)
    report = {
        "dataset_version": GOLD_DATASET_VERSION,
        "production_k": MAX_TOOLS_PER_REQUEST,
        "complexity_iterations": QUERY_COMPLEXITY_ITERATIONS,
        "discovery_recall": {
            "10": s10["recall"],
            "15": s15["recall"],
            "20": s20["recall"],
            "48": s48["recall"],
        },
        "recall_regression": {
            "at_10_ok": s10["recall"] >= PHASE6_RECALL_AT_10,
            "at_15_ok": s15["recall"] >= PHASE6_RECALL_AT_15,
            "at_20_ok": s20["recall"] >= PHASE6_RECALL_AT_20,
        },
        "modes": modes,
        "wire_token_reduction_progressive_k15_vs_current_k48": reduction,
        "honest_split": {
            "application_side_duplication": "solved",
            "llm_wire_duplication": (
                "reduced_if_smaller_k_sent_each_iteration"
                if reduction > 0
                else "not_solved_without_smaller_k_or_provider_cache"
            ),
            "provider_tool_prefix_cache": "openai_prompt_cache_key / anthropic_cache_control — not used for tools in this phase",
        },
    }
    if write_files:
        EVAL_DIR.mkdir(parents=True, exist_ok=True)
        (EVAL_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        for key, payload in modes.items():
            (EVAL_DIR / f"{key}.json").write_text(
                json.dumps(payload, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
    return report


def main() -> None:
    report = run_schema_evaluation(write_files=True)
    rec = report["discovery_recall"]
    print(json.dumps({
        "recall@10": rec["10"],
        "recall@15": rec["15"],
        "recall@20": rec["20"],
        "recall@48": rec["48"],
        "current_k48_wire": report["modes"]["current_k48"]["avg_wire_schema_tokens_per_request"],
        "progressive_k15_wire": report["modes"]["progressive_k15"]["avg_wire_schema_tokens_per_request"],
        "reduction": report["wire_token_reduction_progressive_k15_vs_current_k48"],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
