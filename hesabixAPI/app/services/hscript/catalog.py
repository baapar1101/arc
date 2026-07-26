"""کاتالوگ معنایی Gateway و دستورپخت‌های HScript برای Studio و AI."""

from __future__ import annotations

import re
from typing import Any

from app.services.hscript.docs_catalog import DOC_ENTRIES, read_doc_by_id


GATEWAY_CATALOG: list[dict[str, Any]] = [
	{
		"name": "invoices",
		"title": "فاکتورها و اسناد فروش/خرید",
		"description": "خواندن اسناد فاکتور با فیلتر تاریخ، شخص و نوع سند.",
		"methods": [
			{"name": "filter", "args": "status?, document_type?, from_date?, to_date?, person_id?, search?, limit?, is_proforma?"},
			{"name": "all", "args": "limit?"},
			{"name": "this_month", "args": "document_type?, limit?"},
			{"name": "last_month", "args": "document_type?, limit?"},
			{"name": "count", "args": "**filters"},
		],
		"fields": ["id", "code", "document_date", "document_type", "total_debit", "total_credit", "person_id", "description"],
	},
	{
		"name": "customers",
		"title": "مشتریان",
		"description": "اشخاص با نقش مشتری.",
		"methods": [
			{"name": "filter", "args": "search?, limit?"},
			{"name": "all", "args": "limit?"},
			{"name": "count", "args": "**filters"},
		],
		"fields": ["id", "code", "alias_name", "first_name", "last_name", "company_name", "mobile", "person_types"],
	},
	{
		"name": "persons",
		"title": "اشخاص",
		"description": "همه اشخاص کسب‌وکار (مشتری، تأمین‌کننده و …).",
		"methods": [
			{"name": "filter", "args": "search?, person_type?, limit?"},
			{"name": "all", "args": "limit?"},
			{"name": "count", "args": "**filters"},
		],
		"fields": ["id", "code", "alias_name", "company_name", "mobile", "person_types"],
	},
	{
		"name": "products",
		"title": "کالا و خدمات",
		"description": "فهرست کالا با قیمت پایه فروش.",
		"methods": [
			{"name": "filter", "args": "search?, limit?"},
			{"name": "all", "args": "limit?"},
			{"name": "top", "args": "n=10, by='sale_price'"},
		],
		"fields": ["id", "name", "code", "barcode", "sale_price", "is_active"],
	},
	{
		"name": "payments",
		"title": "دریافت و پرداخت",
		"description": "اسناد دریافت (receipt) و پرداخت (payment).",
		"methods": [
			{"name": "filter", "args": "kind='receipt'|payment, from_date?, to_date?, limit?"},
			{"name": "this_month", "args": "kind?, limit?"},
			{"name": "last_month", "args": "kind?, limit?"},
		],
		"fields": ["id", "code", "document_date", "document_type", "total_debit", "total_credit"],
	},
	{
		"name": "banks",
		"title": "حساب‌های بانکی",
		"description": "فهرست حساب‌های بانکی فعال کسب‌وکار (بدون داده‌های حساس کامل).",
		"methods": [
			{"name": "filter", "args": "search?, limit?"},
			{"name": "all", "args": "limit?"},
		],
		"fields": ["id", "code", "name", "branch", "account_number_masked", "is_active", "is_default", "balance"],
	},
	{
		"name": "warehouses",
		"title": "انبارها",
		"description": "فهرست انبارهای کسب‌وکار.",
		"methods": [
			{"name": "all", "args": "limit?"},
			{"name": "filter", "args": "search?, limit?"},
		],
		"fields": ["id", "code", "name", "is_default", "warehouse_keeper", "phone"],
	},
	{
		"name": "debtors",
		"title": "بدهکاران",
		"description": "گزارش مانده بدهکاران بر اساس سال مالی جاری.",
		"methods": [
			{"name": "filter", "args": "search?, min_balance?, from_date?, to_date?, limit?"},
			{"name": "all", "args": "limit?"},
			{"name": "top", "args": "n=10"},
		],
		"fields": ["person_id", "code", "name", "balance", "debt"],
	},
	{
		"name": "creditors",
		"title": "بستانکاران",
		"description": "گزارش مانده بستانکاران بر اساس سال مالی جاری.",
		"methods": [
			{"name": "filter", "args": "search?, min_balance?, from_date?, to_date?, limit?"},
			{"name": "all", "args": "limit?"},
			{"name": "top", "args": "n=10"},
		],
		"fields": ["person_id", "code", "name", "balance", "credit"],
	},
]

TABLE_METHODS: list[dict[str, str]] = [
	{"name": "filter", "args": "**equality kwargs"},
	{"name": "where", "args": "field, op, value  |  field__op=value"},
	{"name": "select", "args": "*columns"},
	{"name": "sort", "args": "by, desc=False"},
	{"name": "limit", "args": "n"},
	{"name": "top", "args": "n, by?, desc=True"},
	{"name": "distinct", "args": "*columns"},
	{"name": "join", "args": "other, left_on, right_on?, how='inner'|'left'"},
	{"name": "pivot", "args": "index, columns, values, agg='sum'|'count'|'avg'"},
	{"name": "rename", "args": "**mapping"},
	{"name": "sum / count / avg / group_by / group_sum", "args": "…"},
]


_CODE_FENCE_RE = re.compile(r"```hscript\s*(.*?)\s*```", re.DOTALL | re.IGNORECASE)


def list_recipes() -> list[dict[str, Any]]:
	items: list[dict[str, Any]] = []
	for entry in DOC_ENTRIES:
		tags = entry.get("tags") or []
		if "recipe" not in tags and not str(entry.get("doc_id", "")).startswith("hscript.recipe."):
			continue
		doc = read_doc_by_id(entry["doc_id"]) or {}
		content = str(doc.get("content") or "")
		m = _CODE_FENCE_RE.search(content)
		code = (m.group(1).strip() if m else "").strip()
		items.append(
			{
				"id": entry.get("example_id") or entry["doc_id"],
				"doc_id": entry["doc_id"],
				"title": entry.get("title") or entry["doc_id"],
				"tags": tags,
				"description": _first_prose(content),
				"source_code": code,
			}
		)
	return items


def _first_prose(content: str) -> str:
	lines = []
	for line in content.splitlines():
		s = line.strip()
		if not s or s.startswith("#") or s.startswith("```") or s.startswith("---"):
			continue
		lines.append(s)
		if len(" ".join(lines)) > 120:
			break
	text = " ".join(lines).strip()
	return text[:180]


def build_catalog() -> dict[str, Any]:
	return {
		"language_version": "1.1.0",
		"modules": GATEWAY_CATALOG,
		"table_methods": TABLE_METHODS,
		"recipes": list_recipes(),
		"param_hints": {
			"annotation": '# @param from_date date "از تاریخ" required\n# @param limit integer "سقف" default=50',
			"supported_types": ["string", "text", "number", "integer", "boolean", "date", "select"],
		},
	}
