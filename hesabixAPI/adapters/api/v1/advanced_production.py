"""API افزونه تولید پیشرفته."""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.advanced_production_plugin_dependency import require_advanced_production_plugin_active
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.datetime_utils import export_filename_timestamp, format_generated_at_for_pdf, resolve_calendar_type_for_request
from app.core.i18n import get_request_translator, locale_dependency
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import advanced_production_service as svc
from app.services.advanced_production_calc import export_code_message
from app.services.list_report_export_service import ListReportColumn, list_excel_response, list_pdf_response
from app.services.pdf.template_renderer import load_farsi_font_data_uris

router = APIRouter(prefix="/advanced-production", tags=["advanced-production"])
_require_plugin = require_advanced_production_plugin_active()

_EXPORT_COLUMNS = {
	"orders": ("code", "product_code", "product_name", "status", "planned_quantity", "produced_quantity", "remaining_quantity", "due_date"),
	"progress": ("code", "product_name", "planned_quantity", "produced_quantity", "remaining_quantity", "progress_percent", "status"),
	"overdue": ("code", "product_name", "due_date", "planned_quantity", "produced_quantity", "remaining_quantity", "status"),
	"schedule": ("code", "product_name", "planned_start_date", "due_date", "planned_quantity", "status"),
	"plan_achievement": ("code", "product_name", "planned_quantity", "produced_quantity", "quantity_variance", "progress_percent"),
	"open_orders": ("code", "product_name", "status", "planned_quantity", "produced_quantity", "remaining_quantity", "due_date"),
	"cycle_time": ("code", "product_name", "started_at", "completed_at", "cycle_hours", "status"),
	"order_costing": ("code", "product_name", "costing_method", "standard_materials", "actual_materials", "standard_operations", "actual_operations", "standard_total", "actual_total", "valued_total", "unit_cost", "cost_variance"),
	"material_requirements": ("product_code", "product_name", "warehouse_name", "required_quantity", "reserved_quantity", "free_quantity", "shortage_quantity"),
	"material_shortage": ("product_code", "product_name", "warehouse_name", "required_quantity", "free_quantity", "shortage_quantity"),
	"material_variance": ("order_code", "product_code", "product_name", "planned_quantity", "issued_quantity", "quantity_variance", "standard_total", "actual_total", "cost_variance"),
	"scrap": ("document_date", "document_code", "product_code", "product_name", "quantity", "amount"),
	"scrap_by_product": ("product_code", "product_name", "quantity", "amount"),
	"scrap_rate": ("product_code", "product_name", "quantity", "produced_quantity", "scrap_percent", "amount"),
	"finished_goods": ("document_date", "document_code", "product_code", "product_name", "quantity", "amount"),
	"finished_by_product": ("product_code", "product_name", "quantity", "amount"),
	"unplanned_production": ("document_date", "document_code", "product_code", "product_name", "quantity", "amount"),
	"oee": ("line_code", "line_name", "run_minutes", "downtime_minutes", "quantity_good", "quantity_scrap", "availability", "performance", "quality", "oee"),
	"downtime": ("started_on", "ended_on", "minutes", "reason_code", "line_id"),
	"inspections": ("inspected_on", "stage", "result", "quantity_checked", "quantity_rejected", "product_id"),
	"maintenance": ("opened_on", "closed_on", "kind", "repair_minutes", "cost_amount", "machine_id"),
	"reliability": ("machine_code", "machine_name", "breakdown_count", "preventive_count", "mtbf_days", "mttr_minutes", "cost_amount"),
	"product_profit": ("product_code", "product_name", "sales_quantity", "sales_amount", "produced_quantity", "production_cost", "unit_cost", "estimated_cogs", "margin", "margin_percent"),
	"cost_share": ("basis", "materials", "operations", "total", "materials_percent", "operations_percent"),
	"qc_pass_rate": ("product_id", "stage", "quantity_checked", "quantity_rejected", "acceptance_percent"),
	"production_daily": ("document_date", "quantity"),
	"line_output": ("line_code", "line_name", "quantity_good", "quantity_scrap", "run_minutes", "good_percent"),
	"shift_output": ("shift_code", "shift_name", "quantity_good", "quantity_scrap", "run_minutes", "good_percent"),
	"wip_age": ("code", "product_name", "status", "started_at", "age_days", "actual_total"),
	"work_center_output": ("work_center_name", "quantity_good", "quantity_scrap", "run_minutes", "good_percent"),
	"capacity_usage": ("line_code", "line_name", "run_minutes", "ideal_quantity", "quantity_good", "quantity_scrap", "utilization_percent"),
	"qc_rejects": ("inspected_on", "stage", "result", "quantity_checked", "quantity_rejected", "product_id"),
	"period_cost": ("product_code", "product_name", "order_count", "materials", "operations", "total"),
	"operator_output": ("operator_name", "quantity_good", "quantity_scrap", "run_minutes", "good_percent"),
	"setup_time": ("started_on", "ended_on", "minutes", "reason_code", "line_id"),
	"lot_trace": ("lot_code", "production_order_id", "product_id", "role"),
	"yield_rate": ("line_code", "line_name", "quantity_good", "quantity_scrap", "yield_percent"),
	"unused_capacity": ("line_code", "line_name", "ideal_quantity", "unused_quantity", "utilization_percent"),
	"break_even": ("product_code", "product_name", "fixed_cost", "unit_cost", "sales_amount", "break_even_quantity"),
	"monthly_comparison": ("period", "quantity", "amount"),
	"material_flow": ("product_code", "product_name", "purchased_quantity", "returned_quantity", "consumed_quantity", "scrapped_quantity", "period_net_quantity"),
	"production_by_lot": ("lot_code", "product_code", "product_name", "produced_quantity", "scrap_quantity", "manufacturing_date"),
	"conversion_efficiency": ("code", "product_name", "produced_quantity", "material_name", "issued_quantity", "material_count", "conversion_percent"),
	"low_yield": ("product_code", "product_name", "quantity_good", "quantity_scrap", "yield_percent"),
	"line_maintenance_cost": ("line_code", "line_name", "record_count", "repair_minutes", "cost_amount"),
	"material_price_variance": ("order_code", "product_code", "product_name", "planned_quantity", "issued_quantity", "standard_unit_cost", "usage_variance", "price_variance"),
	"product_cost": ("product_code", "product_name", "order_count", "produced_quantity", "standard_total", "actual_total", "valued_total", "unit_cost"),
	"wip_balance": ("code", "product_code", "product_name", "status", "actual_total", "transferred_amount", "remaining_wip"),
	"operation_variance": ("code", "product_name", "standard_operations", "actual_operations", "operation_variance"),
	"scrap_by_reason": ("reason_code", "reason_name", "recyclable", "product_code", "product_name", "quantity"),
	"recyclable_scrap": ("reason_code", "reason_name", "product_code", "product_name", "quantity"),
	"nonrecyclable_scrap": ("reason_code", "reason_name", "product_code", "product_name", "quantity"),
	"qc_causes": ("reason_code", "inspection_count", "quantity_rejected"),
	"machine_output": ("machine_code", "machine_name", "quantity_good", "quantity_scrap", "run_minutes", "good_per_hour", "yield_percent"),
	"downtime_cost": ("line_code", "line_name", "minutes", "cost_amount"),
	"held_orders": ("code", "product_name", "status", "held_on", "reason"),
	"material_consumption": ("document_date", "document_code", "product_code", "product_name", "quantity", "amount", "production_order_id"),
	"capacity_required": ("code", "product_name", "line_name", "remaining_quantity", "nominal_units_per_hour", "required_hours"),
	"wip_count": ("code", "product_name", "counted_on", "counted_quantity", "book_remaining", "quantity_variance"),
	"rework": ("product_code", "product_name", "occurred_on", "quantity", "production_order_id"),
	"line_returns": ("product_code", "product_name", "occurred_on", "quantity", "line_id"),
	"wip_by_center": ("work_center_name", "order_count", "remaining_wip"),
	"material_scrap": ("document_date", "document_code", "product_code", "product_name", "quantity", "amount"),
	"idle_materials": ("product_code", "product_name", "current_stock", "days_without_movement"),
	"stage_transfers": ("transferred_on", "from_line_name", "to_line_name", "product_name", "quantity"),
	"wage_variance": ("worked_on", "production_order_id", "person_id", "actual_hours", "standard_hours", "standard_hourly_rate", "actual_hourly_rate", "rate_variance", "efficiency_variance"),
}
_NUMBER_KEYS = {
	"planned_quantity", "produced_quantity", "remaining_quantity", "progress_percent", "quantity_variance",
	"cycle_hours", "standard_total", "actual_total", "valued_total", "cost_variance", "required_quantity",
	"reserved_quantity", "free_quantity", "shortage_quantity", "issued_quantity",
	"quantity", "amount", "produced_quantity", "scrap_percent",
	"quantity_good", "quantity_scrap", "yield_percent", "ideal_quantity", "unused_quantity",
	"utilization_percent", "fixed_cost", "unit_cost", "sales_amount", "break_even_quantity",
	"purchased_quantity", "returned_quantity", "consumed_quantity", "scrapped_quantity", "period_net_quantity",
	"material_count", "conversion_percent", "record_count", "repair_minutes", "cost_amount",
	"standard_unit_cost", "usage_variance", "price_variance", "unit_cost", "transferred_amount", "remaining_wip",
	"standard_operations", "actual_operations", "operation_variance",
	"current_stock", "days_without_movement", "order_count", "required_hours",
	"actual_hours", "standard_hours", "standard_hourly_rate", "actual_hourly_rate", "rate_variance", "efficiency_variance",
	"standard_materials", "actual_materials", "standard_operations", "actual_operations",
}
_DATE_KEYS = {"due_date", "planned_start_date", "started_at", "completed_at", "document_date", "manufacturing_date", "started_on", "opened_on", "inspected_on", "held_on", "counted_on", "occurred_on", "transferred_on", "worked_on"}


def _ok(data: Any, request: Request) -> dict:
	return success_response(format_datetime_fields(data, request), request)


def _filters(
	date_from: Optional[str],
	date_to: Optional[str],
	product_id: Optional[int],
	status: Optional[str],
	search: Optional[str],
	lot_code: Optional[str],
	fixed_cost: Optional[str],
	production_order_id: Optional[int],
	days_without_movement: Optional[int],
	fiscal_year_id: Optional[int],
	warehouse_id: Optional[int],
	currency_id: Optional[int],
	skip: int,
	limit: int,
) -> Dict[str, Any]:
	return {
		"date_from": date_from,
		"date_to": date_to,
		"product_id": product_id,
		"status": status,
		"search": search,
		"lot_code": lot_code,
		"fixed_cost": fixed_cost,
		"production_order_id": production_order_id,
		"days_without_movement": days_without_movement,
		"fiscal_year_id": fiscal_year_id,
		"warehouse_id": warehouse_id,
		"currency_id": currency_id,
		"skip": skip,
		"take": limit,
	}


@router.get(
	"/business/{business_id}/settings",
	summary="تنظیمات تولید پیشرفته",
	description="ابزار MCP: `get_advanced_production_settings`. افزونه باید فعال باشد.",
)
def get_settings_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("advanced_production", "view")),
	____: None = Depends(_require_plugin),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.get_settings(db, business_id)
	db.commit()
	return _ok(data, request)


@router.put(
	"/business/{business_id}/settings",
	summary="ویرایش تنظیمات تولید پیشرفته",
	description="ابزار MCP: `update_advanced_production_settings` (نیازمند تأیید).",
)
def update_settings_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("advanced_production", "manage")),
	____: None = Depends(_require_plugin),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.update_settings(db, business_id, payload)
	db.commit()
	return _ok(data, request)


@router.get(
	"/business/{business_id}/dashboard",
	summary="داشبورد تولید پیشرفته",
	description="ابزار MCP: `get_advanced_production_dashboard`.",
)
def dashboard_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("advanced_production", "view")),
	____: None = Depends(_require_plugin),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = svc.get_dashboard(db, business_id)
	db.commit()
	return _ok(data, request)


@router.get(
	"/business/{business_id}/reports/{report_key}",
	summary="گزارش نام‌دار تولید پیشرفته",
	description="خروجی JSON یک کلید گزارش. ابزار MCP: `get_advanced_production_report`. خروجی اکسل/PDF در MCP نیست.",
)
def report_endpoint(
	request: Request,
	business_id: int,
	report_key: str,
	date_from: Optional[str] = Query(default=None),
	date_to: Optional[str] = Query(default=None),
	product_id: Optional[int] = Query(default=None),
	status: Optional[str] = Query(default=None),
	search: Optional[str] = Query(default=None),
	lot_code: Optional[str] = Query(default=None),
	fixed_cost: Optional[str] = Query(default=None),
	production_order_id: Optional[int] = Query(default=None),
	days_without_movement: Optional[int] = Query(default=None, ge=1, le=3650),
	fiscal_year_id: Optional[int] = Query(default=None, ge=1),
	warehouse_id: Optional[int] = Query(default=None, ge=1),
	currency_id: Optional[int] = Query(default=None, ge=1),
	skip: int = Query(default=0, ge=0),
	limit: int = Query(default=50, ge=1, le=200),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("advanced_production", "view")),
	____: None = Depends(_require_plugin),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	filters = _filters(date_from, date_to, product_id, status, search, lot_code, fixed_cost, production_order_id, days_without_movement, fiscal_year_id, warehouse_id, currency_id, skip, limit)
	translator = get_request_translator(request)
	filters["calendar_type"] = resolve_calendar_type_for_request(request, translator.locale == "fa")
	data = svc.run_named_report(
		db,
		business_id,
		report_key,
		filters,
	)
	db.commit()
	return _ok(data, request)


def _export(db: Session, business_id: int, report_key: str, body: Dict[str, Any], request: Request, kind: str) -> Response:
	translator = get_request_translator(request)
	is_fa = translator.locale == "fa"
	body = dict(body or {})
	body.setdefault("calendar_type", resolve_calendar_type_for_request(request, is_fa))
	normalized = report_key.removeprefix("advprod_")
	if normalized not in _EXPORT_COLUMNS:
		raise ApiError("AP_REPORT_UNKNOWN", "AP_REPORT_UNKNOWN", http_status=404)
	data = svc.export_rows(db, business_id, normalized, body or {})
	db.commit()
	items = []
	for row in data["items"]:
		copied = dict(row)
		for key, value in list(copied.items()):
			message_id = export_code_message(key, value)
			if message_id:
				copied[key] = translator.t(message_id, default=str(value))
		items.append(copied)
	title = translator.t(f"AP_REPORT_{normalized.upper()}", default=normalized)
	columns = []
	for key in _EXPORT_COLUMNS[normalized]:
		label = translator.t(f"AP_COL_{key.upper()}", default=key)
		columns.append(ListReportColumn(
			key,
			label,
			label,
			"number" if key in _NUMBER_KEYS else "date" if key in _DATE_KEYS else "text",
		))
	common = dict(
		items=items,
		columns=columns,
		db=db,
		business_id=business_id,
		filename_prefix=f"advanced-production-{report_key}",
		is_fa=is_fa,
		title=title,
		summary={k: v for k, v in (data.get("summary") or {}).items() if isinstance(v, (int, float, str))},
		export_filename_timestamp=export_filename_timestamp,
	)
	if kind == "pdf":
		return list_pdf_response(
			**common,
			generated_at=format_generated_at_for_pdf(
				business_id,
				resolve_calendar_type_for_request(request, is_fa),
			),
			load_farsi_font_data_uris=load_farsi_font_data_uris,
		)
	return list_excel_response(**common)


@router.post(
	"/business/{business_id}/reports/{report_key}/export/excel",
	summary="خروجی Excel گزارش تولید پیشرفته",
	description="خروجی باینری Excel است و در MCP ثبت نشده. JSON: `get_advanced_production_report`.",
)
def export_excel_endpoint(
	request: Request,
	business_id: int,
	report_key: str,
	body: Dict[str, Any] = Body(default_factory=dict),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("advanced_production", "view")),
	____: None = Depends(_require_plugin),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> Response:
	return _export(db, business_id, report_key, body, request, "excel")


@router.post(
	"/business/{business_id}/reports/{report_key}/export/pdf",
	summary="خروجی PDF گزارش تولید پیشرفته",
	description="خروجی باینری PDF است و در MCP ثبت نشده. JSON: `get_advanced_production_report`.",
)
def export_pdf_endpoint(
	request: Request,
	business_id: int,
	report_key: str,
	body: Dict[str, Any] = Body(default_factory=dict),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("advanced_production", "view")),
	____: None = Depends(_require_plugin),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> Response:
	return _export(db, business_id, report_key, body, request, "pdf")


@router.get(
	"/business/{business_id}/masters/{kind}",
	summary="فهرست داده‌های پایه تولید پیشرفته",
	description="ابزار MCP: `list_advanced_production_master`.",
)
def list_master_endpoint(
	request: Request,
	business_id: int,
	kind: str,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("advanced_production", "view")),
	____: None = Depends(_require_plugin),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.advanced_production_master import list_master
	return _ok(list_master(db, business_id, kind), request)


@router.post(
	"/business/{business_id}/masters/{kind}",
	summary="ایجاد داده پایه تولید پیشرفته",
	description="ابزار MCP: `create_advanced_production_master` (نیازمند تأیید).",
)
def create_master_endpoint(
	request: Request,
	business_id: int,
	kind: str,
	payload: Dict[str, Any] = Body(default_factory=dict),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("advanced_production", "operate")),
	____: None = Depends(_require_plugin),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.advanced_production_master import create_master
	data = create_master(db, business_id, kind, payload)
	db.commit()
	return _ok(data, request)
