"""تست‌های RAG سبک و hardening HScript."""

from __future__ import annotations

from app.services.hscript.docs_catalog import retrieve_docs_for_rag, search_docs
from app.services.hscript.hardening import sanitize_public_error, worker_limits
from app.services.hscript_report_service import build_assist_context
from app.services.hscript import validate_script


def test_search_docs_finds_invoices_content():
	hits = search_docs("invoices filter this_month", limit=5)
	assert hits
	assert any("invoice" in h["doc_id"] for h in hits)


def test_retrieve_docs_includes_content():
	docs = retrieve_docs_for_rag("نمودار bar chart", limit=3)
	assert docs
	assert docs[0].get("content")


def test_assist_context_structure():
	ctx = build_assist_context("فروش ماهانه با KPI", source_code="report.title(\"x\")")
	assert "system_guide" in ctx
	assert "docs" in ctx
	assert ctx["language_version"] == "1.0.0"


def test_sanitize_public_error():
	raw = {"code": "E050_RESOURCE_LIMIT", "message": "too long " * 100, "hint": "h", "secret": "x"}
	out = sanitize_public_error(raw)
	assert out is not None
	assert out["code"] == "E050_RESOURCE_LIMIT"
	assert "secret" not in out
	assert len(out["message"]) <= 500


def test_worker_limits_preview_harder():
	p = worker_limits(preview=True)
	f = worker_limits(preview=False)
	assert p.max_execution_ms <= f.max_execution_ms


def test_validate_sample_script():
	assert validate_script("report.title(\"t\")\n")["ok"] is True
