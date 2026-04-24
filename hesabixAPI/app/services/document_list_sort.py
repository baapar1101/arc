from __future__ import annotations

from typing import Any, Dict, List, Tuple

from sqlalchemy import Integer, Numeric, and_, cast, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Query

from adapters.api.v1.schemas import QueryInfo
from adapters.db.models.document import Document
from adapters.db.models.person import Person
from app.services.sort_resolution import effective_sort_specs

# فیلدهای مجاز برای لیست/جستجوی فاکتورها (UI: طرف حساب / مبلغ کل و ستون‌های سند)
INVOICE_DOCUMENT_SORT_ALLOWED = frozenset(
	{
		"document_date",
		"code",
		"created_at",
		"registered_at",
		"counterparty",
		"total_amount",
	}
)


def _invoice_sort_column(sort_key: str):
	if sort_key == "code" and hasattr(Document, "code"):
		return Document.code
	if sort_key == "created_at" and hasattr(Document, "created_at"):
		return Document.created_at
	if sort_key == "registered_at" and hasattr(Document, "registered_at"):
		return Document.registered_at
	return Document.document_date


def invoice_search_sort_specs(query_info: QueryInfo) -> List[Tuple[str, bool]]:
	return effective_sort_specs(
		query_info,
		allowed=INVOICE_DOCUMENT_SORT_ALLOWED,
		default_when_empty=("document_date", True),
	)


def apply_invoice_search_ordering(q: Query, query_info: QueryInfo) -> Query:
	specs = invoice_search_sort_specs(query_info)
	_extra_info_jb = cast(Document.extra_info, JSONB)
	person_id_expr = cast(_extra_info_jb["person_id"].astext, Integer)

	needs_person = any(name == "counterparty" for name, _ in specs)
	if needs_person:
		q = q.outerjoin(
			Person,
			and_(Person.id == person_id_expr, Person.business_id == Document.business_id),
		)

	clauses: List[Any] = []
	for name, desc in specs:
		if name == "counterparty":
			# نزدیک به ترتیب نمایش _add_counterparty_to_invoice_item (شرکت / نام / نام مستعار)
			full_name = func.nullif(func.trim(func.concat_ws(" ", Person.first_name, Person.last_name)), "")
			expr = func.coalesce(
				func.nullif(func.trim(Person.company_name), ""),
				full_name,
				Person.alias_name,
			)
			ord_expr = expr.desc() if desc else expr.asc()
			clauses.append(ord_expr.nulls_last())
		elif name == "total_amount":
			# همان مبدأ غالب total_amount در خروجی لیست: extra_info.totals.net
			net_txt = _extra_info_jb["totals"]["net"].astext
			expr = cast(net_txt, Numeric(24, 8))
			ord_expr = expr.desc() if desc else expr.asc()
			clauses.append(ord_expr.nulls_last())
		else:
			col = _invoice_sort_column(name)
			clauses.append(col.desc() if desc else col.asc())
	clauses.append(Document.id.desc())
	return q.order_by(*clauses)


def query_info_from_body_for_sort(body: Dict[str, Any]) -> QueryInfo:
	"""برای اندپوینت‌هایی که فقط dict بدنه دارند (مثلاً خروجی)."""
	return QueryInfo.model_validate({
		"take": body.get("take", 20),
		"skip": body.get("skip", 0),
		"sort_by": body.get("sort_by"),
		"sort_desc": body.get("sort_desc", True),
		"sort": body.get("sort"),
	})


def apply_invoice_search_ordering_from_body(q: Query, body: Dict[str, Any]) -> Query:
	return apply_invoice_search_ordering(q, query_info_from_body_for_sort(body))


def apply_document_dynamic_ordering(q: Query, query_info: QueryInfo) -> Query:
	"""
	مرتب‌سازی سند با نام ستون‌های دینامیک روی مدل Document (مثل transfer / receipt list).
	فقط ستونی که روی مدل وجود دارد اعمال می‌شود؛ در انتها id نزولی برای پایداری صفحه‌بندی.
	"""
	specs = effective_sort_specs(
		query_info,
		allowed=None,
		default_when_empty=("document_date", True),
	)
	clauses: List[Any] = []
	for name, desc in specs:
		if not hasattr(Document, name):
			continue
		col = getattr(Document, name)
		clauses.append(col.desc() if desc else col.asc())
	if not clauses:
		clauses.append(Document.document_date.desc())
	clauses.append(Document.id.desc())
	return q.order_by(*clauses)


def apply_document_dynamic_ordering_from_dict(q: Query, d: Dict[str, Any]) -> Query:
	qi = QueryInfo.model_validate({
		"take": d.get("take", 20),
		"skip": d.get("skip", 0),
		"sort_by": d.get("sort_by"),
		"sort_desc": d.get("sort_desc", True),
		"sort": d.get("sort"),
	})
	return apply_document_dynamic_ordering(q, qi)


# لیست اسناد حسابداری (documents list) — شامل document_type
DOCUMENT_ACCOUNTING_LIST_ALLOWED = frozenset(
	{"document_date", "code", "document_type", "created_at", "registered_at"}
)


def _accounting_document_sort_column(sort_key: str):
	if sort_key == "document_type" and hasattr(Document, "document_type"):
		return Document.document_type
	return _invoice_sort_column(sort_key)


def apply_document_accounting_list_ordering(q: Query, query_info: QueryInfo) -> Query:
	specs = effective_sort_specs(
		query_info,
		allowed=DOCUMENT_ACCOUNTING_LIST_ALLOWED,
		default_when_empty=("document_date", True),
	)
	clauses = [
		_accounting_document_sort_column(name).desc() if desc else _accounting_document_sort_column(name).asc()
		for name, desc in specs
	]
	clauses.append(Document.id.desc())
	return q.order_by(*clauses)
