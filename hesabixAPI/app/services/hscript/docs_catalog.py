"""مانیفست مستندات HScript برای RAG و دستیار AI."""

from __future__ import annotations

from pathlib import Path
from typing import Any


# ریشهٔ docs در ریپو (/opt/hesabix/app/docs/hscript)
_DOCS_ROOT = Path(__file__).resolve().parents[4] / "docs" / "hscript"


DOC_ENTRIES: list[dict[str, Any]] = [
	{
		"doc_id": "hscript.overview",
		"path": "00-overview.md",
		"title": "معرفی HScript",
		"tags": ["overview", "intro"],
		"version": 1,
	},
	{
		"doc_id": "hscript.security",
		"path": "01-security.md",
		"title": "امنیت و محدودیت‌ها",
		"tags": ["security", "limits"],
		"version": 1,
	},
	{
		"doc_id": "hscript.limits",
		"path": "02-limits.md",
		"title": "سقف منابع اجرا",
		"tags": ["limits", "resources"],
		"version": 1,
	},
	{
		"doc_id": "hscript.tutorial.getting-started",
		"path": "tutorials/getting-started.md",
		"title": "شروع سریع",
		"tags": ["tutorial", "beginner"],
		"version": 1,
	},
	{
		"doc_id": "hscript.tutorial.charts",
		"path": "tutorials/charts.md",
		"title": "ساخت نمودار",
		"tags": ["tutorial", "charts"],
		"version": 1,
	},
	{
		"doc_id": "hscript.tutorial.pdf-export",
		"path": "tutorials/pdf-export.md",
		"title": "خروجی PDF",
		"tags": ["tutorial", "pdf"],
		"version": 1,
	},
	{
		"doc_id": "hscript.tutorial.dashboard",
		"path": "tutorials/dashboard.md",
		"title": "ساخت داشبورد",
		"tags": ["tutorial", "dashboard"],
		"version": 1,
	},
	{
		"doc_id": "hscript.tutorial.excel-export",
		"path": "tutorials/excel-export.md",
		"title": "خروجی Excel",
		"tags": ["tutorial", "excel"],
		"version": 1,
	},
	{
		"doc_id": "hscript.tutorial.plan-limits",
		"path": "tutorials/plan-limits.md",
		"title": "پلن و سقف گزارش‌ساز",
		"tags": ["tutorial", "plan", "marketplace"],
		"version": 1,
	},
	{
		"doc_id": "hscript.reference.language",
		"path": "reference/language.md",
		"title": "مرجع نحو زبان",
		"tags": ["reference", "language"],
		"version": 1,
	},
	{
		"doc_id": "hscript.api.invoices",
		"path": "reference/api/invoices.md",
		"title": "API: invoices",
		"tags": ["api", "invoices"],
		"version": 1,
	},
	{
		"doc_id": "hscript.api.customers",
		"path": "reference/api/customers.md",
		"title": "API: customers",
		"tags": ["api", "customers"],
		"version": 1,
	},
	{
		"doc_id": "hscript.api.products",
		"path": "reference/api/products.md",
		"title": "API: products",
		"tags": ["api", "products"],
		"version": 1,
	},
	{
		"doc_id": "hscript.api.payments",
		"path": "reference/api/payments.md",
		"title": "API: payments",
		"tags": ["api", "payments"],
		"version": 1,
	},
	{
		"doc_id": "hscript.reference.report-blocks",
		"path": "reference/report-blocks.md",
		"title": "بلوک‌های گزارش",
		"tags": ["reference", "report", "blocks"],
		"version": 1,
	},
	{
		"doc_id": "hscript.recipe.top-customers",
		"path": "recipes/top-customers.md",
		"title": "دستورپخت: مشتریان برتر",
		"tags": ["recipe", "example"],
		"version": 1,
	},
	{
		"doc_id": "hscript.errors.E001",
		"path": "errors/E001-syntax.md",
		"title": "خطای نحوی",
		"tags": ["error", "E001"],
		"version": 1,
	},
	{
		"doc_id": "hscript.errors.E030",
		"path": "errors/E030-security.md",
		"title": "خطای امنیتی",
		"tags": ["error", "E030", "security"],
		"version": 1,
	},
	{
		"doc_id": "hscript.errors.E050",
		"path": "errors/E050-resource-limit.md",
		"title": "سقف منابع",
		"tags": ["error", "E050", "limits"],
		"version": 1,
	},
	{
		"doc_id": "hscript.best-practices",
		"path": "best-practices.md",
		"title": "بهترین شیوه‌ها",
		"tags": ["best-practices"],
		"version": 1,
	},
]


def list_doc_manifest() -> dict[str, Any]:
	return {
		"language_version": "1.0.0",
		"docs_root": "docs/hscript",
		"entries": DOC_ENTRIES,
	}


def read_doc_by_id(doc_id: str) -> dict[str, Any] | None:
	entry = next((e for e in DOC_ENTRIES if e["doc_id"] == doc_id), None)
	if not entry:
		return None
	path = _DOCS_ROOT / entry["path"]
	if not path.is_file():
		return {**entry, "content": None, "missing": True}
	return {**entry, "content": path.read_text(encoding="utf-8"), "missing": False}


def search_docs(query: str, *, limit: int = 5) -> list[dict[str, Any]]:
	"""جستجوی کلمه‌کلیدی روی متادیتا + محتوای فایل‌ها (RAG سبک)."""
	q = (query or "").strip().lower()
	if not q:
		return DOC_ENTRIES[:limit]
	tokens = [t for t in q.replace("،", " ").split() if t]
	scored: list[tuple[int, dict[str, Any]]] = []
	for e in DOC_ENTRIES:
		hay = " ".join([e["doc_id"], e["title"], " ".join(e.get("tags") or [])]).lower()
		content = ""
		path = _DOCS_ROOT / e["path"]
		if path.is_file():
			try:
				content = path.read_text(encoding="utf-8").lower()
			except Exception:
				content = ""
		score = 0
		for token in tokens:
			if token in e["doc_id"]:
				score += 5
			if token in hay:
				score += 3
			if token and token in content:
				score += 1 + min(content.count(token), 5)
		if score:
			scored.append((score, e))
	scored.sort(key=lambda x: -x[0])
	return [e for _, e in scored[:limit]]


def retrieve_docs_for_rag(query: str, *, limit: int = 5, max_chars: int = 2500) -> list[dict[str, Any]]:
	"""بازیابی قطعات محتوا برای تزریق به context مدل."""
	hits = search_docs(query, limit=limit)
	out: list[dict[str, Any]] = []
	for hit in hits:
		full = read_doc_by_id(str(hit["doc_id"]))
		if not full or full.get("missing"):
			continue
		content = full.get("content") or ""
		if len(content) > max_chars:
			content = content[:max_chars] + "\n\n...[truncated]..."
		out.append(
			{
				"doc_id": full["doc_id"],
				"title": full["title"],
				"tags": full.get("tags") or [],
				"content": content,
			}
		)
	return out
