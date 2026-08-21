"""Phase 5 — tight Top-K retrieval evaluation gates."""
from __future__ import annotations

from app.services.ai.ai_constants import MAX_TOOLS_AUTONOMOUS, MAX_TOOLS_PER_REQUEST
from app.services.ai.ai_tool_discovery import discover_tools
from app.services.ai.ai_tool_discovery_eval import (
    CI_LEGACY_RECALL_AT_48_MIN,
    CI_RECALL_AT_10_MIN,
    CI_RECALL_AT_20_MIN,
    CI_RECALL_AT_48_MIN,
    CI_RETRIEVAL_SUCCESS_AT_15_MIN,
    evaluate_at_k,
    permissioned_catalog,
    recommend_k,
)
from app.services.ai.ai_tool_discovery_gold import gold_stats, load_gold_queries
from app.services.ai.ai_tool_intent import filter_function_definitions


def test_gold_dataset_is_large_enough_to_measure_retrieval():
    stats = gold_stats()
    assert stats["queries"] >= 300
    assert stats["match_queries"] >= 280
    assert stats["tools_covered"] >= 120
    assert stats["legacy_queries"] == 22
    assert stats["no_match_queries"] >= 15
    assert stats["write_queries"] >= 20
    assert stats["destructive_queries"] >= 8
    assert stats["memory_queries"] >= 6
    assert stats["report_queries"] >= 20


def test_gold_queries_are_not_just_tool_names():
    named = 0
    for row in load_gold_queries():
        if row.no_match:
            continue
        q = row.query.replace("-", "_").lower()
        if any(tool == q or tool.replace("_", " ") == q for tool in row.primary_expected_tools):
            named += 1
    assert named == 0


def test_legacy_gold_recall_at_baseline_k48():
    gold = [row for row in load_gold_queries() if row.source == "legacy"]
    summary, _ = evaluate_at_k(48, rows=gold)
    assert summary["recall"] >= CI_LEGACY_RECALL_AT_48_MIN


def test_retrieval_ci_gates_match_measured_baseline():
    gold = load_gold_queries()
    catalog = permissioned_catalog()
    s10, _ = evaluate_at_k(10, rows=gold, catalog=catalog)
    s20, _ = evaluate_at_k(20, rows=gold, catalog=catalog)
    s48, _ = evaluate_at_k(48, rows=gold, catalog=catalog)
    s15, _ = evaluate_at_k(15, rows=gold, catalog=catalog)
    assert s10["recall"] >= CI_RECALL_AT_10_MIN
    assert s20["recall"] >= CI_RECALL_AT_20_MIN
    assert s48["recall"] >= CI_RECALL_AT_48_MIN
    assert s15["retrieval_success_rate"] >= CI_RETRIEVAL_SUCCESS_AT_15_MIN
    rec = recommend_k({
        "10": s10,
        "15": s15,
        "20": s20,
        "48": s48,
    })
    # Production K stays 48 in Phase 6 regardless of eval decision.
    assert MAX_TOOLS_PER_REQUEST == 48
    assert MAX_TOOLS_AUTONOMOUS == 128
    assert rec["keep_autonomous_k"] == 128


def test_no_match_is_marked_low_confidence():
    offer = discover_tools(
        "هوا امروز چطوره؟",
        permissioned_names=permissioned_catalog(),
        execution_mode="analyzer",
        channel="eval",
    )
    assert offer.low_confidence is True
    assert offer.top_score <= 4
    assert offer.candidates == ()


def test_ranked_candidates_are_score_descending():
    offer = discover_tools(
        "گزارش فروش این ماه را بده",
        permissioned_names=permissioned_catalog(),
        execution_mode="analyzer",
        limit=48,
    )
    scores = [item.score for item in offer.candidates]
    assert scores == sorted(scores, reverse=True)
    assert offer.candidates
    assert offer.score_gap == offer.top_score - offer.second_score


def test_filter_definitions_preserves_discovery_order():
    defs = [
        {"function": {"name": "search_invoices"}},
        {"function": {"name": "get_sales_report"}},
        {"function": {"name": "query_business_data"}},
    ]
    ordered = filter_function_definitions(
        defs, ["get_sales_report", "search_invoices"]
    )
    assert [d["function"]["name"] for d in ordered] == [
        "get_sales_report",
        "search_invoices",
    ]
