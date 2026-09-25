"""تست استخراج و persist استناد (RAG-02)."""
from __future__ import annotations

from app.services.ai.ai_citation_service import (
    CITATIONS_STORAGE_KEY,
    build_citation_context,
    content_has_moneyish_claim,
    extract_citation_sources,
    infer_citation_entity,
    merge_citations_into_function_results,
    ungrounded_numeric_warning,
)
from app.services.ai.ai_trace import extract_citations_from_result


def test_extract_prefers_envelope_and_infers_invoice_entity() -> None:
    results = {
        "tc1": {
            "name": "search_invoices",
            "result": {
                "_envelope": 1,
                "citations": [{"id": 44, "name": "فاکتور بهار", "amount": 120000}],
                "items": [{"id": 44, "name": "فاکتور بهار"}],
            },
        }
    }
    sources = extract_citation_sources(results)
    assert len(sources) == 1
    assert sources[0]["id"] == 44
    assert sources[0]["entity"] == "invoice"
    assert sources[0]["source"] == "search_invoices"
    text = build_citation_context(results)
    assert "فاکتور بهار" in text
    assert "عدد قطعی نگو" in text


def test_merge_citations_roundtrip() -> None:
    sources = [{"id": 9, "name": "مشتری الف", "entity": "person"}]
    merged = merge_citations_into_function_results({"tc": {"ok": True}}, sources)
    assert merged[CITATIONS_STORAGE_KEY][0]["id"] == 9


def test_ungrounded_numeric_warning_only_without_sources() -> None:
    content = "جمع فروش ۱۲٬۰۰۰٬۰۰۰ ریال است."
    assert content_has_moneyish_claim(content)
    assert ungrounded_numeric_warning(content, []) is not None
    assert ungrounded_numeric_warning(content, [{"id": 1}]) is None
    assert ungrounded_numeric_warning("سلام، چطور کمک کنم؟", []) is None


def test_infer_entity_from_tool_name() -> None:
    assert infer_citation_entity("search_persons", {}) == "person"
    assert infer_citation_entity("get_deal", {"type": "opportunity"}) == "deal"


def test_trace_citations_use_envelope() -> None:
    lines = extract_citations_from_result(
        {
            "citations": [{"id": 3, "name": "کالا", "amount": 10}],
            "records": [{"id": 3, "name": "کالا"}],
        }
    )
    assert any("کالا" in line for line in lines)
    assert any("#3" in line for line in lines)
