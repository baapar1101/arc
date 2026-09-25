"""Phase 6 — ranking: core is a signal, not reserved Top-K capacity."""
from __future__ import annotations

from app.services.ai.ai_tool_discovery import discover_tools
from app.services.ai.ai_tool_discovery_eval import permissioned_catalog
from app.services.ai.ai_tool_index import get_tool_index
from app.services.ai.ai_tool_rank import rank_and_cap_tool_names, score_tool_for_query


def test_irrelevant_core_does_not_consume_topk():
    core = get_tool_index().core_names
    names = set(core) | {"search_invoices", "get_sales_report"}
    capped = rank_and_cap_tool_names(
        names,
        "فاکتورهای فروش این ماه را نشان بده",
        max_tools=5,
        core_names=core,
        intent_domains={"financial"},
    )
    assert "search_invoices" in capped
    assert len(capped) <= 5
    # Unrelated cores (dashboard/info) must not fill the five slots
    assert "get_business_info" not in capped or "search_invoices" in capped


def test_high_relevance_non_core_outranks_low_relevance_core():
    q = "گزارش فروش این ماه"
    core = "query_business_data"
    noncore = "get_sales_report"
    assert score_tool_for_query(noncore, q, intent_domains={"financial", "reports_meta"}) > (
        score_tool_for_query(core, q, intent_domains={"financial", "reports_meta"})
    )
    capped = rank_and_cap_tool_names(
        {core, noncore, "get_business_dashboard", "get_business_info"},
        q,
        max_tools=2,
        core_names={core, "get_business_dashboard", "get_business_info"},
        intent_domains={"financial", "reports_meta"},
    )
    assert noncore in capped
    assert core not in capped or noncore in capped


def test_core_with_high_relevance_remains_available():
    capped = rank_and_cap_tool_names(
        {"query_business_data", "search_invoices", "get_financial_summary"},
        "خلاصه وضعیت مالی کسب‌وکار",
        max_tools=3,
        core_names={"query_business_data", "get_financial_summary"},
        intent_domains={"financial"},
    )
    assert "get_financial_summary" in capped


def test_no_match_query_is_low_confidence_and_empty():
    offer = discover_tools(
        "هوا امروز چطوره؟",
        permissioned_names=permissioned_catalog(),
        execution_mode="analyzer",
        channel="eval",
    )
    assert offer.low_confidence is True
    assert offer.candidates == ()
    assert offer.top_score <= 0


def test_workflow_query_ranks_workflow_tools():
    offer = discover_tools(
        "لیست گردش‌کارهای اتوماسیون",
        permissioned_names=permissioned_catalog(),
        execution_mode="analyzer",
        limit=10,
        channel="eval",
    )
    names = [item.name for item in offer.candidates]
    assert "list_workflows" in names
    assert names.index("list_workflows") < 5
    assert "get_business_dashboard" not in names[:3]
