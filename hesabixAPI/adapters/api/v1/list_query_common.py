"""
ابزارهای مشترک QueryInfo برای endpointهای لیست (فاز ۱۲).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Union

from fastapi import Body, Request
from typing_extensions import Annotated

from adapters.api.v1.schemas import DocumentListQuery, KardexListQuery, QueryInfo, WarehouseDocListQuery

QUERY_INFO_BODY_DESCRIPTION = (
	"پارامترهای جستجو، فیلتر پیشرفته (`filters[]`)، مرتب‌سازی و صفحه‌بندی. "
	"مرجع کامل: بخش «جستجو و فیلتر پیشرفته» در ابتدای مستندات OpenAPI."
)

DOCUMENT_LIST_BODY_DESCRIPTION = (
	"QueryInfo به‌همراه فیلترهای تخت (`document_type`, `from_date`, `to_date`, `person_id`, …). "
	"فیلترهای ستونی را می‌توان در `filters` یا به‌صورت تخت ارسال کرد."
)

QUERY_INFO_OPENAPI_EXAMPLE = {
	"take": 20,
	"skip": 0,
	"sort_by": "created_at",
	"sort_desc": True,
	"search": "احمد",
	"search_fields": ["alias_name", "mobile"],
	"filters": [
		{"property": "is_active", "operator": "=", "value": True},
	],
}

DOCUMENT_LIST_OPENAPI_EXAMPLE = {
	"take": 20,
	"skip": 0,
	"document_type": "receipt",
	"from_date": "2024-01-01",
	"to_date": "2024-12-31",
	"filters": [{"property": "code", "operator": "*", "value": "REC"}],
}

# فیلدهای تخت DocumentListQuery (غیر از فیلدهای QueryInfo)
DOCUMENT_LIST_EXTRA_FIELDS: tuple[str, ...] = (
	"document_type",
	"from_date",
	"to_date",
	"currency_id",
	"is_proforma",
	"fiscal_year_id",
	"project_id",
	"person_id",
	"account_id",
	"bank_account_id",
	"cash_register_id",
	"petty_cash_id",
	"tag_ids",
	"tag_match",
	"is_installment_sale",
)

KARDEX_EXTRA_FIELDS: tuple[str, ...] = (
	"from_date",
	"to_date",
	"fiscal_year_id",
	"person_ids",
	"product_ids",
	"bank_account_ids",
	"cash_register_ids",
	"petty_cash_ids",
	"account_ids",
	"check_ids",
	"warehouse_ids",
	"match_mode",
	"result_scope",
	"include_running_balance",
)

WAREHOUSE_DOC_EXTRA_FIELDS: tuple[str, ...] = (
	"doc_type",
	"status",
	"warehouse_id",
	"warehouse_ids",
	"from_date",
	"to_date",
	"fiscal_year_id",
)

QueryInfoBody = Annotated[
	QueryInfo,
	Body(..., description=QUERY_INFO_BODY_DESCRIPTION, openapi_examples={"default": {"value": QUERY_INFO_OPENAPI_EXAMPLE}}),
]

DocumentListQueryBody = Annotated[
	DocumentListQuery,
	Body(
		...,
		description=DOCUMENT_LIST_BODY_DESCRIPTION,
		openapi_examples={"default": {"value": DOCUMENT_LIST_OPENAPI_EXAMPLE}},
	),
]

KardexListQueryBody = Annotated[
	KardexListQuery,
	Body(..., description="QueryInfo + فیلترهای چندانتخابی کاردکس"),
]

WarehouseDocListQueryBody = Annotated[
	WarehouseDocListQuery,
	Body(default_factory=WarehouseDocListQuery),
]


def query_info_to_service_dict(query_info: QueryInfo) -> Dict[str, Any]:
	"""تبدیل QueryInfo به dict سرویس (با filters به‌صورت dict)."""
	out: Dict[str, Any] = {
		"take": query_info.take,
		"skip": query_info.skip,
		"sort_by": query_info.sort_by,
		"sort_desc": query_info.sort_desc,
		"sort": [s.model_dump() for s in query_info.sort] if query_info.sort else None,
		"search": query_info.search,
	}
	if query_info.search_fields:
		out["search_fields"] = list(query_info.search_fields)
	if query_info.filters:
		out["filters"] = [f.model_dump() for f in query_info.filters]
	if getattr(query_info, "category_ids", None):
		out["category_ids"] = list(query_info.category_ids)
	if getattr(query_info, "include_inventory", False):
		out["include_inventory"] = True
	if getattr(query_info, "inventory_as_of_date", None):
		out["inventory_as_of_date"] = query_info.inventory_as_of_date
	return out


def _merge_extra_fields(
	target: Dict[str, Any],
	model: Any,
	field_names: tuple[str, ...],
) -> None:
	for key in field_names:
		if not hasattr(model, key):
			continue
		val = getattr(model, key, None)
		if val is not None:
			target[key] = val


def document_list_query_to_dict(
	query: DocumentListQuery,
	*,
	request: Optional[Request] = None,
	fiscal_year_from_header: bool = True,
) -> Dict[str, Any]:
	d = query_info_to_service_dict(query)
	_merge_extra_fields(d, query, DOCUMENT_LIST_EXTRA_FIELDS)
	if fiscal_year_from_header and request is not None and d.get("fiscal_year_id") is None:
		apply_fiscal_year_from_request(request, d)
	return d


def kardex_list_query_to_dict(
	query: KardexListQuery,
	*,
	request: Optional[Request] = None,
) -> Dict[str, Any]:
	d = query_info_to_service_dict(query)
	_merge_extra_fields(d, query, KARDEX_EXTRA_FIELDS)
	if request is not None and d.get("fiscal_year_id") is None:
		apply_fiscal_year_from_request(request, d)
	return d


def warehouse_doc_list_to_dict(
	query: WarehouseDocListQuery,
	*,
	request: Optional[Request] = None,
) -> Dict[str, Any]:
	"""بدنهٔ سرویس حواله انبار (همان ساختار dict قبلی)."""
	d = query.model_dump(exclude_unset=True, exclude_none=True)
	# اطمینان از سازگاری با سرویس قدیمی
	if query.filters:
		d["filters"] = [f.model_dump() for f in query.filters]
	if request is not None and d.get("fiscal_year_id") is None:
		apply_fiscal_year_from_request(request, d)
	return d


def apply_fiscal_year_from_request(request: Request, query_dict: Dict[str, Any]) -> None:
	if query_dict.get("fiscal_year_id") is not None:
		return
	try:
		fy_header = request.headers.get("X-Fiscal-Year-ID")
		if fy_header:
			query_dict["fiscal_year_id"] = int(fy_header)
	except (TypeError, ValueError):
		pass


def model_to_legacy_body(model: Union[DocumentListQuery, QueryInfo]) -> Dict[str, Any]:
	"""برای endpointهایی که هنوز body.get(...) دارند."""
	return model.model_dump(exclude_unset=True, exclude_none=True)
