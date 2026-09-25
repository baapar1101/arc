"""Phase 10 — inverted candidate index, security, incremental updates."""
from __future__ import annotations

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_RETRIEVAL,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
    VECTOR_CANDIDATE_RETRIEVAL,
)
from app.services.ai.ai_tool_candidates import retrieve_candidates
from app.services.ai.ai_tool_discovery import discover_tools
from app.services.ai.ai_tool_retrieval_index import ToolRetrievalIndex
from app.services.ai.ai_tool_spec import ToolManifestEntry
from app.services.ai.ai_tool_text import normalize_search_text, tokenize_search_text


def test_production_index_flags_stay_off():
    assert INDEXED_CANDIDATE_RETRIEVAL is False
    assert VECTOR_CANDIDATE_RETRIEVAL is False
    assert HYBRID_TOOL_DISCOVERY is False
    assert ADAPTIVE_DISCOVERY_K is False
    assert ADAPTIVE_K_ROLLOUT_PERCENT == 0
    assert PROGRESSIVE_SCHEMA_LOADING is False
    assert MAX_TOOLS_PER_REQUEST == 48
    assert MAX_TOOLS_AUTONOMOUS == 128


def test_persian_normalization_folds_ye_ke_and_zwnj():
    assert normalize_search_text("طرف‌حساب") == normalize_search_text("طرف حساب")
    assert "ی" in normalize_search_text("پيگيري")
    assert "ک" in normalize_search_text("شركت")
    tokens = tokenize_search_text("فاکتور فروش")
    assert "فاکتور" in tokens
    assert "فروش" in tokens


def test_index_finds_tool_from_alias_terms():
    index = ToolRetrievalIndex()
    index.upsert("search_invoices")
    rec = index.get("search_invoices")
    assert rec is not None
    assert rec.search_text_hash
    hits = index.lookup_token("فاکتور")
    assert "search_invoices" in hits


def test_incremental_update_and_disable():
    index = ToolRetrievalIndex()
    entry = ToolManifestEntry(
        domains=("financial",),
        capability="financial.invoice",
        namespace="financial",
        aliases=("فاکتور آزمایشی",),
        enabled=True,
        version="1",
        schema_version="1",
    )
    index.upsert("demo_invoice_tool", entry=entry)
    assert "demo_invoice_tool" in index.lookup_token("آزمایشی")
    updated = ToolManifestEntry(
        domains=("financial",),
        capability="financial.invoice",
        namespace="financial",
        aliases=("صورتحساب آزمایشی",),
        enabled=True,
        version="2",
        schema_version="1",
    )
    index.upsert("demo_invoice_tool", entry=updated)
    assert "demo_invoice_tool" not in index.lookup_token("فاکتور")
    assert "demo_invoice_tool" in index.lookup_token("صورتحساب")
    assert index.get("demo_invoice_tool").version == "2"
    index.disable("demo_invoice_tool")
    assert "demo_invoice_tool" not in index.lookup_token("صورتحساب")
    index.remove("demo_invoice_tool")
    assert index.get("demo_invoice_tool") is None


def test_unauthorized_tool_never_becomes_candidate():
    index = ToolRetrievalIndex()
    index.rebuild_from_manifest()
    offer = retrieve_candidates(
        "فاکتور فروش را پیدا کن",
        ["list_accounts"],
        n=50,
        fallback_on_empty=False,
        include_vector=False,
        index=index,
        expects_tools=True,
    )
    assert "search_invoices" not in offer.as_set()
    assert offer.as_set() <= {"list_accounts"}


def test_expected_tool_enters_candidate_set():
    index = ToolRetrievalIndex()
    index.rebuild_from_manifest()
    offer = retrieve_candidates(
        "فاکتورهای فروش این ماه را نشان بده",
        list(index.names()),
        n=50,
        fallback_on_empty=False,
        include_vector=False,
        index=index,
        expects_tools=True,
    )
    assert "search_invoices" in offer.as_set()


def test_no_match_weather_is_empty_or_tiny():
    index = ToolRetrievalIndex()
    index.rebuild_from_manifest()
    offer = retrieve_candidates(
        "هوا امروز چطوره؟",
        list(index.names()),
        n=50,
        fallback_on_empty=False,
        include_vector=False,
        index=index,
        expects_tools=False,
    )
    assert offer.empty or len(offer.names) <= 5


def test_capability_and_domain_indexes_are_direct():
    index = ToolRetrievalIndex()
    index.rebuild_from_manifest()
    invoices = index.lookup_capability("financial.invoice")
    assert "search_invoices" in invoices
    financial = index.lookup_domain("financial")
    assert "search_invoices" in financial
    assert invoices <= financial


def test_production_discover_still_ranks_without_index_flag():
    offer = discover_tools(
        "فاکتور فروش این ماه را پیدا کن",
        permissioned_names=["search_invoices", "list_accounts", "get_sales_report"],
        execution_mode="analyzer",
    )
    assert INDEXED_CANDIDATE_RETRIEVAL is False
    assert "search_invoices" in offer.names()
    assert offer.adaptive_enabled is False
