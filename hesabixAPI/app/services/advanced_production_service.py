"""سرویس افزونه تولید پیشرفته.

گزارش‌های این لایه از سفارش، فاکتور و بهای موجود هسته خوانده می‌شوند.
روش بها فقط ارزش گزارش را انتخاب می‌کند و سند دفتر کل را بازنویسی نمی‌کند.
"""
from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Optional

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.advanced_production import AdvancedProductionSettings
from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.production_order import (
	ProductionOrder,
	ProductionOrderMaterial,
	ProductionOrderOutput,
)
from app.core.advanced_production_plugin_dependency import check_advanced_production_plugin_active
from app.core.business_calendar import business_day_utc_bounds, business_today
from app.core.responses import ApiError
from app.services.advanced_production_calc import (
	CLOSED_STATUSES,
	COSTING_METHODS,
	OPEN_STATUSES,
	OVERHEAD_MODES,
	acceptance_rate,
	break_even_quantity,
	calendar_period,
	conversion_percent,
	unused_quantity,
	yield_percent,
	cost_share,
	cost_variance,
	material_rate_split,
	cycle_hours,
	is_overdue,
	money,
	progress_percent,
	product_margin,
	qty,
	quantity_variance,
	remaining_quantity,
	valued_order_cost,
	weighted_average_unit,
)
from app.services.production_order_service import get_production_material_plan

REPORT_KEYS = (
	"orders",
	"progress",
	"overdue",
	"schedule",
	"plan_achievement",
	"open_orders",
	"cycle_time",
	"order_costing",
	"material_requirements",
	"material_shortage",
	"material_variance",
	"scrap",
	"scrap_by_product",
	"scrap_rate",
	"finished_goods",
	"finished_by_product",
	"unplanned_production",
	"oee",
	"downtime",
	"inspections",
	"maintenance",
	"reliability",
	"product_profit",
	"cost_share",
	"qc_pass_rate",
	"production_daily",
	"line_output",
	"shift_output",
	"wip_age",
	"work_center_output",
	"capacity_usage",
	"qc_rejects",
	"period_cost",
	"operator_output",
	"setup_time",
	"lot_trace",
	"yield_rate",
	"unused_capacity",
	"break_even",
	"monthly_comparison",
	"material_flow",
	"production_by_lot",
	"conversion_efficiency",
	"low_yield",
	"line_maintenance_cost",
	"material_price_variance",
	"product_cost",
	"wip_balance",
	"operation_variance",
	"scrap_by_reason",
	"recyclable_scrap",
	"nonrecyclable_scrap",
	"qc_causes",
	"machine_output",
	"downtime_cost",
	"held_orders",
	"material_consumption",
	"capacity_required",
	"wip_count",
	"rework",
	"line_returns",
	"wip_by_center",
	"material_scrap",
	"idle_materials",
	"stage_transfers",
	"wage_variance",
)
_ACCOUNT_FIELDS = (
	"wip_account_id",
	"finished_goods_account_id",
	"scrap_expense_account_id",
	"cost_variance_account_id",
)


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_advanced_production_plugin_active(db, business_id):
		raise ApiError(
			"ADVANCED_PRODUCTION_PLUGIN_NOT_ACTIVE",
			"ADVANCED_PRODUCTION_PLUGIN_NOT_ACTIVE",
			http_status=403,
			details={"plugin_code": "advanced_production"},
		)


def _parse_date(value: Any) -> Optional[date]:
	if value in (None, ""):
		return None
	if isinstance(value, datetime):
		return value.date()
	if isinstance(value, date):
		return value
	try:
		return date.fromisoformat(str(value)[:10])
	except ValueError as exc:
		raise ApiError("INVALID_DATE", "INVALID_DATE", http_status=400) from exc


def _num(value: Decimal) -> float:
	return float(value)


def _iso(value: Any) -> Optional[str]:
	if value is None:
		return None
	if isinstance(value, datetime):
		return value.isoformat()
	if isinstance(value, date):
		return value.isoformat()
	return str(value)


def _aware(value: Optional[datetime]) -> Optional[datetime]:
	if value is None:
		return None
	if value.tzinfo is None:
		return value.replace(tzinfo=timezone.utc)
	return value


def _ledger_mode(row: AdvancedProductionSettings) -> str:
	mapped = any(
		getattr(row, name, None) is not None
		for name in (
			"wip_account_id",
			"finished_goods_account_id",
			"cost_variance_account_id",
		)
	)
	if mapped or (row.costing_method != "actual" and row.cost_variance_account_id is not None):
		return "next_production_invoice"
	return "unchanged"


def _settings_dict(row: AdvancedProductionSettings) -> Dict[str, Any]:
	return {
		"business_id": row.business_id,
		"costing_method": row.costing_method,
		"overhead_mode": row.overhead_mode,
		"wip_account_id": row.wip_account_id,
		"finished_goods_account_id": row.finished_goods_account_id,
		"scrap_expense_account_id": row.scrap_expense_account_id,
		"cost_variance_account_id": row.cost_variance_account_id,
		"valuation_scope": "plugin_report",
		"general_ledger_posting": _ledger_mode(row),
		"updated_at": _iso(row.updated_at),
	}


def _require_account(db: Session, business_id: int, account_id: Optional[int]) -> Optional[int]:
	if account_id in (None, "", 0):
		return None
	account = db.query(Account).filter(Account.id == int(account_id)).first()
	if account is None or int(account.business_id or 0) != int(business_id):
		raise ApiError("AP_ACCOUNT_NOT_IN_BUSINESS", "AP_ACCOUNT_NOT_IN_BUSINESS", http_status=400)
	return int(account.id)


def get_settings(db: Session, business_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = db.query(AdvancedProductionSettings).filter(
		AdvancedProductionSettings.business_id == int(business_id)
	).first()
	if row is None:
		row = AdvancedProductionSettings(
			business_id=int(business_id),
			costing_method="actual",
			overhead_mode="bom_operations",
		)
		db.add(row)
		db.flush()
	return _settings_dict(row)


def update_settings(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = db.query(AdvancedProductionSettings).filter(
		AdvancedProductionSettings.business_id == int(business_id)
	).first()
	if row is None:
		row = AdvancedProductionSettings(business_id=int(business_id))
		db.add(row)
		db.flush()
	method = str(payload.get("costing_method") or row.costing_method or "actual")
	if method not in COSTING_METHODS:
		raise ApiError("AP_INVALID_COSTING_METHOD", "AP_INVALID_COSTING_METHOD", http_status=400)
	overhead = str(payload.get("overhead_mode") or row.overhead_mode or "bom_operations")
	if overhead not in OVERHEAD_MODES:
		raise ApiError("AP_OVERHEAD_MODE_UNSUPPORTED", "AP_OVERHEAD_MODE_UNSUPPORTED", http_status=400)
	row.costing_method = method
	row.overhead_mode = overhead
	for field in _ACCOUNT_FIELDS:
		if field in payload:
			setattr(row, field, _require_account(db, business_id, payload.get(field)))
	row.updated_at = datetime.now(timezone.utc)
	db.flush()
	return _settings_dict(row)


def _pagination(total: int, skip: int, take: int) -> Dict[str, int]:
	page = (skip // take) + 1 if take else 1
	return {"total": total, "page": page, "per_page": take, "skip": skip}


def _bounds(skip: int, take: int) -> tuple[int, int]:
	safe_take = max(1, min(int(take or 50), 5000))
	safe_skip = max(0, int(skip or 0))
	return safe_skip, safe_take


def _optional_id(value: Any, code: str) -> Optional[int]:
	if value in (None, ""):
		return None
	try:
		number = int(value)
	except (TypeError, ValueError) as exc:
		raise ApiError(code, code, http_status=400) from exc
	if number <= 0:
		raise ApiError(code, code, http_status=400)
	return number


def _order_in_warehouse(order, args: Dict[str, Any]) -> bool:
	wid = _optional_id(args.get("warehouse_id"), "AP_WAREHOUSE_NOT_FOUND")
	if wid is None:
		return True
	return int(order.warehouse_id) == wid or int(order.output_warehouse_id) == wid


def _line_warehouse_id(document, line) -> Optional[int]:
	info = line.extra_info or {}
	header = document.extra_info or {}
	raw = info.get("warehouse_id") if info.get("warehouse_id") not in (None, "") else header.get("warehouse_id")
	try:
		return int(raw) if raw not in (None, "") else None
	except (TypeError, ValueError):
		return None


def _document_matches(document, line, args: Dict[str, Any]) -> bool:
	wid = _optional_id(args.get("warehouse_id"), "AP_WAREHOUSE_NOT_FOUND")
	cid = _optional_id(args.get("currency_id"), "AP_CURRENCY_NOT_FOUND")
	if cid is not None and int(document.currency_id) != cid:
		return False
	if wid is not None and _line_warehouse_id(document, line) != wid:
		return False
	return True


def _apply_fiscal_year(db: Session, business_id: int, payload: Dict[str, Any]) -> bool:
	fy_id = _optional_id(payload.get("fiscal_year_id"), "AP_FISCAL_YEAR_NOT_FOUND")
	if fy_id is None:
		return False
	from adapters.db.models.fiscal_year import FiscalYear
	from app.services.advanced_production_calc import intersect_date_range

	year = db.query(FiscalYear).filter(
		FiscalYear.id == fy_id,
		FiscalYear.business_id == int(business_id),
	).first()
	if year is None:
		raise ApiError("AP_FISCAL_YEAR_NOT_FOUND", "AP_FISCAL_YEAR_NOT_FOUND", http_status=404)
	start, end, empty = intersect_date_range(
		_parse_date(payload.get("date_from")),
		_parse_date(payload.get("date_to")),
		year.start_date,
		year.end_date,
	)
	payload["date_from"] = start.isoformat() if start else None
	payload["date_to"] = end.isoformat() if end else None
	return empty


def _date_args(args: Dict[str, Any]) -> tuple[Optional[date], Optional[date]]:
	start = _parse_date(args.get("date_from") or args.get("from_date"))
	end = _parse_date(args.get("date_to") or args.get("to_date"))
	if start and end and start > end:
		raise ApiError("INVALID_DATE_RANGE", "INVALID_DATE_RANGE", http_status=400)
	return start, end


def _base_orders(db: Session, business_id: int):
	return db.query(ProductionOrder, Product).join(
		Product, Product.id == ProductionOrder.product_id
	).filter(
		ProductionOrder.business_id == int(business_id),
		Product.business_id == int(business_id),
	)


def _apply_common(query, args: Dict[str, Any], *, date_column):
	start, end = _date_args(args)
	product_id = args.get("product_id")
	status = args.get("status")
	search = (args.get("search") or "").strip()
	if product_id:
		query = query.filter(ProductionOrder.product_id == int(product_id))
	if status:
		if status not in (*OPEN_STATUSES, *CLOSED_STATUSES):
			raise ApiError("INVALID_PRODUCTION_ORDER_STATUS", "INVALID_PRODUCTION_ORDER_STATUS", http_status=400)
		query = query.filter(ProductionOrder.status == status)
	if start is not None:
		query = query.filter(date_column >= start)
	if end is not None:
		query = query.filter(date_column <= end)
	if search:
		like = f"%{search}%"
		query = query.filter(or_(ProductionOrder.code.ilike(like), Product.name.ilike(like), Product.code.ilike(like)))
	wid = _optional_id(args.get("warehouse_id"), "AP_WAREHOUSE_NOT_FOUND")
	if wid is not None:
		query = query.filter(or_(ProductionOrder.warehouse_id == wid, ProductionOrder.output_warehouse_id == wid))
	return query


def _order_row(order: ProductionOrder, product: Product, today: date, method: str, average_unit) -> Dict[str, Any]:
	planned = order.planned_quantity
	produced = order.produced_quantity
	standard_materials = money(order.standard_materials_cost)
	actual_materials = money(order.actual_materials_cost)
	standard_operations = money(order.standard_operations_cost)
	actual_operations = money(order.actual_operations_cost)
	standard_total = standard_materials + standard_operations
	actual_total = actual_materials + actual_operations
	valued = valued_order_cost(method, standard_total, actual_total, produced, average_unit)
	produced_qty = D(produced)
	unit_cost = None if produced_qty <= 0 else (valued / produced_qty).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)
	return {
		"production_order_id": order.id,
		"code": order.code,
		"product_id": order.product_id,
		"product_code": product.code,
		"product_name": product.name,
		"status": order.status,
		"planned_quantity": _num(qty(planned)),
		"produced_quantity": _num(qty(produced)),
		"remaining_quantity": _num(remaining_quantity(planned, produced)),
		"progress_percent": _num(progress_percent(planned, produced)),
		"planned_start_date": _iso(order.planned_start_date),
		"due_date": _iso(order.due_date),
		"started_at": _iso(order.started_at),
		"completed_at": _iso(order.completed_at),
		"is_overdue": is_overdue(order.due_date, today, order.status),
		"cycle_hours": None if cycle_hours(order.started_at, order.completed_at) is None else _num(cycle_hours(order.started_at, order.completed_at)),
		"standard_materials": _num(standard_materials),
		"actual_materials": _num(actual_materials),
		"standard_operations": _num(standard_operations),
		"actual_operations": _num(actual_operations),
		"standard_total": _num(standard_total),
		"actual_total": _num(actual_total),
		"valued_total": _num(valued),
		"unit_cost": None if unit_cost is None else float(unit_cost),
		"cost_variance": _num(cost_variance(actual_total, standard_total)),
		"costing_method": method,
		"quantity_variance": _num(quantity_variance(produced, planned)),
	}


def _averages(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[int, Optional[Decimal]]:
	query = db.query(
		ProductionOrder.product_id,
		func.coalesce(func.sum(ProductionOrder.actual_materials_cost + ProductionOrder.actual_operations_cost), 0),
		func.coalesce(func.sum(ProductionOrder.produced_quantity), 0),
	).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrder.status == "completed",
		ProductionOrder.produced_quantity > 0,
	)
	start, end = _date_args(args)
	if start is not None:
		query = query.filter(ProductionOrder.due_date >= start)
	if end is not None:
		query = query.filter(ProductionOrder.due_date <= end)
	if args.get("product_id"):
		query = query.filter(ProductionOrder.product_id == int(args["product_id"]))
	out: Dict[int, Optional[Decimal]] = {}
	for product_id, total_cost, total_qty in query.group_by(ProductionOrder.product_id).all():
		out[int(product_id)] = weighted_average_unit(total_cost, total_qty)
	return out


def _order_report(db: Session, business_id: int, report_key: str, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	method = settings["costing_method"]
	today = business_today(business_id)
	skip, take = _bounds(args.get("skip", 0), args.get("take") or args.get("limit") or 50)
	query = _base_orders(db, business_id)
	date_column = ProductionOrder.planned_start_date if report_key == "schedule" else ProductionOrder.due_date
	query = _apply_common(query, args, date_column=date_column)
	if report_key == "open_orders":
		query = query.filter(ProductionOrder.status.in_(OPEN_STATUSES))
	elif report_key == "overdue":
		query = query.filter(
			ProductionOrder.due_date.isnot(None),
			ProductionOrder.due_date < today,
			ProductionOrder.status.notin_(CLOSED_STATUSES),
		)
	elif report_key == "cycle_time":
		query = query.filter(ProductionOrder.started_at.isnot(None), ProductionOrder.completed_at.isnot(None))
	total = query.count()
	rows = query.order_by(ProductionOrder.due_date.asc().nullslast(), ProductionOrder.id.desc()).offset(skip).limit(take).all()
	averages = _averages(db, business_id, args) if method == "weighted_average" else {}
	items = [
		_order_row(order, product, today, method, averages.get(int(order.product_id)))
		for order, product in rows
	]
	agg = query.order_by(None).with_entities(
		func.count(ProductionOrder.id),
		func.coalesce(func.sum(ProductionOrder.planned_quantity), 0),
		func.coalesce(func.sum(ProductionOrder.produced_quantity), 0),
		func.coalesce(func.sum(ProductionOrder.standard_materials_cost + ProductionOrder.standard_operations_cost), 0),
		func.coalesce(func.sum(ProductionOrder.actual_materials_cost + ProductionOrder.actual_operations_cost), 0),
	).one()
	summary = {
		"count": int(agg[0] or 0),
		"planned_quantity": _num(qty(agg[1])),
		"produced_quantity": _num(qty(agg[2])),
		"standard_total": _num(money(agg[3])),
		"actual_total": _num(money(agg[4])),
		"cost_variance": _num(cost_variance(agg[4], agg[3])),
	}
	result = _envelope(report_key, items, summary, total, skip, take, method)
	if report_key == "order_costing":
		result["meta"]["components"] = "order_materials_and_operations"
		result["meta"]["unit_cost"] = "valued_total_divided_by_produced_quantity_blank_when_none_produced"
		result["meta"]["general_ledger_posting"] = "not_this_report"
	return result


def D(value) -> Decimal:
	from app.services.advanced_production_calc import D as _D
	return _D(value)


def _material_rows(db: Session, business_id: int, args: Dict[str, Any], *, shortage_only: bool) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	start, end = _date_args(args)
	plan = get_production_material_plan(db, business_id, due_from=start, due_to=end)
	items = list(plan.get("items") or [])
	product_id = args.get("product_id")
	if product_id:
		items = [row for row in items if int(row["product_id"]) == int(product_id)]
	warehouse_id = _optional_id(args.get("warehouse_id"), "AP_WAREHOUSE_NOT_FOUND")
	if warehouse_id is not None:
		items = [row for row in items if int(row.get("warehouse_id") or 0) == warehouse_id]
	search = (args.get("search") or "").strip().casefold()
	if search:
		items = [
			row for row in items
			if search in str(row.get("product_name") or "").casefold()
			or search in str(row.get("product_code") or "").casefold()
			or search in str(row.get("warehouse_name") or "").casefold()
		]
	if shortage_only:
		items = [row for row in items if D(row.get("shortage_quantity")) > 0]
	skip, take = _bounds(args.get("skip", 0), args.get("take") or args.get("limit") or 50)
	total = len(items)
	page = items[skip:skip + take]
	shortage_sum = sum((D(row.get("shortage_quantity")) for row in items), Decimal("0"))
	required_sum = sum((D(row.get("required_quantity")) for row in items), Decimal("0"))
	summary = {
		"count": total,
		"required_quantity": _num(qty(required_sum)),
		"shortage_quantity": _num(qty(shortage_sum)),
		"as_of_date": plan.get("as_of_date"),
	}
	return _envelope(
		"material_shortage" if shortage_only else "material_requirements",
		page,
		summary,
		total,
		skip,
		take,
		get_settings(db, business_id)["costing_method"],
	)


def _variance_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	skip, take = _bounds(args.get("skip", 0), args.get("take") or args.get("limit") or 50)
	query = db.query(ProductionOrderMaterial, ProductionOrder, Product).join(
		ProductionOrder, ProductionOrder.id == ProductionOrderMaterial.production_order_id
	).join(Product, Product.id == ProductionOrderMaterial.product_id).filter(
		ProductionOrder.business_id == int(business_id),
		Product.business_id == int(business_id),
	)
	start, end = _date_args(args)
	if args.get("product_id"):
		query = query.filter(ProductionOrderMaterial.product_id == int(args["product_id"]))
	if args.get("production_order_id"):
		query = query.filter(ProductionOrder.id == int(args["production_order_id"]))
	if start is not None:
		query = query.filter(ProductionOrder.due_date >= start)
	if end is not None:
		query = query.filter(ProductionOrder.due_date <= end)
	wid = _optional_id(args.get("warehouse_id"), "AP_WAREHOUSE_NOT_FOUND")
	if wid is not None:
		query = query.filter(or_(ProductionOrder.warehouse_id == wid, ProductionOrder.output_warehouse_id == wid))
	search = (args.get("search") or "").strip()
	if search:
		like = f"%{search}%"
		query = query.filter(or_(ProductionOrder.code.ilike(like), Product.name.ilike(like), Product.code.ilike(like)))
	total = query.count()
	rows = query.order_by(ProductionOrder.id.desc(), ProductionOrderMaterial.line_no.asc()).offset(skip).limit(take).all()
	items = []
	for material, order, product in rows:
		q_var = quantity_variance(material.issued_quantity, material.planned_quantity)
		c_var = cost_variance(material.actual_total_cost, material.standard_total_cost)
		items.append({
			"production_order_id": order.id,
			"order_code": order.code,
			"line_no": material.line_no,
			"product_id": product.id,
			"product_code": product.code,
			"product_name": product.name,
			"planned_quantity": _num(qty(material.planned_quantity)),
			"issued_quantity": _num(qty(material.issued_quantity)),
			"quantity_variance": _num(q_var),
			"standard_total": _num(money(material.standard_total_cost)),
			"actual_total": _num(money(material.actual_total_cost)),
			"cost_variance": _num(c_var),
			"lot_code": material.lot_code,
		})
	agg = query.order_by(None).with_entities(
		func.count(ProductionOrderMaterial.id),
		func.coalesce(func.sum(ProductionOrderMaterial.planned_quantity), 0),
		func.coalesce(func.sum(ProductionOrderMaterial.issued_quantity), 0),
		func.coalesce(func.sum(ProductionOrderMaterial.standard_total_cost), 0),
		func.coalesce(func.sum(ProductionOrderMaterial.actual_total_cost), 0),
	).one()
	summary = {
		"count": int(agg[0] or 0),
		"planned_quantity": _num(qty(agg[1])),
		"issued_quantity": _num(qty(agg[2])),
		"quantity_variance": _num(quantity_variance(agg[2], agg[1])),
		"standard_total": _num(money(agg[3])),
		"actual_total": _num(money(agg[4])),
		"cost_variance": _num(cost_variance(agg[4], agg[3])),
	}
	return _envelope("material_variance", items, summary, total, skip, take, settings["costing_method"])


def _envelope(report_key: str, items, summary, total, skip, take, method: str) -> Dict[str, Any]:
	return {
		"report_key": report_key,
		"items": items,
		"summary": summary,
		"pagination": _pagination(total, skip, take),
		"meta": {
			"costing_method": method,
			"valuation_scope": "plugin_report",
		"general_ledger_posting": "not_this_report",
		"variance_sign": "positive_unfavorable",
		},
	}


def _line_cost(line: InvoiceItemLine) -> Decimal:
	info = line.extra_info or {}
	quantity = D(line.quantity)
	if info.get("cogs_amount") is not None:
		return money(info.get("cogs_amount"))
	if info.get("cost_price") is not None:
		return money(D(info.get("cost_price")) * quantity)
	return money(D(info.get("unit_price")) * quantity)


def _movement_report(db: Session, business_id: int, report_key: str, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	doc_type = "invoice_waste" if report_key.startswith("scrap") else "invoice_production"
	query = db.query(InvoiceItemLine, Document, Product).join(
		Document, Document.id == InvoiceItemLine.document_id
	).join(Product, Product.id == InvoiceItemLine.product_id).filter(
		Document.business_id == int(business_id),
		Document.document_type == doc_type,
		Document.is_proforma.is_(False),
		Product.business_id == int(business_id),
	)
	if start is not None:
		query = query.filter(Document.document_date >= start)
	if end is not None:
		query = query.filter(Document.document_date <= end)
	if args.get("product_id"):
		query = query.filter(Product.id == int(args["product_id"]))
	search = (args.get("search") or "").strip()
	if search:
		like = f"%{search}%"
		query = query.filter(or_(Product.name.ilike(like), Product.code.ilike(like), Document.code.ilike(like)))
	rows = []
	for line, document, product in query.all():
		if not _document_matches(document, line, args):
			continue
		info = line.extra_info or {}
		movement = info.get("movement")
		if doc_type == "invoice_production" and movement != "in":
			continue
		header = document.extra_info or {}
		has_order = header.get("production_order_id") is not None or info.get("production_order_id") is not None
		if report_key == "unplanned_production" and has_order:
			continue
		rows.append({
			"document_id": document.id,
			"document_code": document.code,
			"document_date": _iso(document.document_date),
			"product_id": product.id,
			"product_code": product.code,
			"product_name": product.name,
			"quantity": _num(qty(line.quantity)),
			"amount": _num(_line_cost(line)),
			"production_order_id": header.get("production_order_id") or info.get("production_order_id"),
		})
	if report_key in ("scrap_by_product", "finished_by_product", "scrap_rate"):
		grouped: Dict[int, Dict[str, Any]] = {}
		for row in rows:
			item = grouped.setdefault(int(row["product_id"]), {
				"product_id": row["product_id"],
				"product_code": row["product_code"],
				"product_name": row["product_name"],
				"quantity": 0.0,
				"amount": 0.0,
			})
			item["quantity"] = _num(qty(D(item["quantity"]) + D(row["quantity"])))
			item["amount"] = _num(money(D(item["amount"]) + D(row["amount"])))
		rows = list(grouped.values())
		if report_key == "scrap_rate":
			produced_rows = _movement_report(db, business_id, "finished_by_product", {**args, "skip": 0, "take": 5000})["items"]
			produced_by_id = {int(row["product_id"]): D(row["quantity"]) for row in produced_rows}
			for row in rows:
				made = produced_by_id.get(int(row["product_id"]), Decimal("0"))
				base = made + D(row["quantity"])
				row["produced_quantity"] = _num(qty(made))
				row["scrap_percent"] = _num(progress_percent(base, row["quantity"])) if base > 0 else 0.0
	skip, take = _bounds(args.get("skip", 0), args.get("take") or args.get("limit") or 50)
	total = len(rows)
	page = rows[skip:skip + take]
	summary = {
		"count": total,
		"quantity": _num(qty(sum((D(row.get("quantity")) for row in rows), Decimal("0")))),
		"amount": _num(money(sum((D(row.get("amount")) for row in rows), Decimal("0")))),
	}
	result = _envelope(report_key, page, summary, total, skip, take, settings["costing_method"])
	result["meta"]["amounts"] = "document_line_cost_not_converted_between_currencies"
	return result


def _signed_amount(line: InvoiceItemLine, sign: int) -> tuple[Decimal, Decimal]:
	info = line.extra_info or {}
	quantity = D(line.quantity)
	if info.get("net") is not None:
		amount = money(info.get("net"))
	else:
		discount = D(info.get("discount_amount") or info.get("discount") or 0)
		amount = money(D(info.get("unit_price")) * quantity - discount)
	return quantity * sign, amount * sign


def _product_profit_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	query = db.query(InvoiceItemLine, Document, Product).join(
		Document, Document.id == InvoiceItemLine.document_id
	).join(Product, Product.id == InvoiceItemLine.product_id).filter(
		Document.business_id == int(business_id),
		Document.is_proforma.is_(False),
		Document.document_type.in_(("invoice_sales", "invoice_sales_return", "invoice_production")),
		Product.business_id == int(business_id),
	)
	if start is not None:
		query = query.filter(Document.document_date >= start)
	if end is not None:
		query = query.filter(Document.document_date <= end)
	if args.get("product_id"):
		query = query.filter(Product.id == int(args["product_id"]))
	grouped: Dict[int, Dict[str, Any]] = {}
	for line, document, product in query.all():
		if not _document_matches(document, line, args):
			continue
		item = grouped.setdefault(int(product.id), {
			"product_id": product.id,
			"product_code": product.code,
			"product_name": product.name,
			"sales_quantity": Decimal("0"),
			"sales_amount": Decimal("0"),
			"produced_quantity": Decimal("0"),
			"production_cost": Decimal("0"),
		})
		if document.document_type == "invoice_production":
			if (line.extra_info or {}).get("movement") != "in":
				continue
			item["produced_quantity"] += D(line.quantity)
			item["production_cost"] += _line_cost(line)
			continue
		sign = -1 if document.document_type == "invoice_sales_return" else 1
		quantity, amount = _signed_amount(line, sign)
		item["sales_quantity"] += quantity
		item["sales_amount"] += amount
	rows = []
	for item in grouped.values():
		margin = product_margin(item["sales_amount"], item["sales_quantity"], item["production_cost"], item["produced_quantity"])
		rows.append({
			"product_id": item["product_id"],
			"product_code": item["product_code"],
			"product_name": item["product_name"],
			"sales_quantity": float(qty(item["sales_quantity"])),
			"sales_amount": float(money(item["sales_amount"])),
			"produced_quantity": float(qty(item["produced_quantity"])),
			"production_cost": float(money(item["production_cost"])),
			"unit_cost": None if margin is None else float(margin["unit_cost"]),
			"estimated_cogs": None if margin is None else float(margin["estimated_cogs"]),
			"margin": None if margin is None else float(margin["margin"]),
			"margin_percent": None if margin is None or margin["margin_percent"] is None else float(margin["margin_percent"]),
		})
	rows.sort(key=lambda row: (row["margin"] is None, -(row["margin"] or 0)))
	skip, take = _bounds(args.get("skip", 0), args.get("take") or args.get("limit") or 50)
	total = len(rows)
	result = _envelope(
		"product_profit",
		rows[skip:skip + take],
		{
			"count": total,
			"sales_amount": float(money(sum((D(row["sales_amount"]) for row in rows), Decimal("0")))),
			"products_with_margin": sum(1 for row in rows if row["margin"] is not None),
		},
		total,
		skip,
		take,
		settings["costing_method"],
	)
	result["meta"]["margin_basis"] = "period_production_unit_cost_times_sales_quantity"
	result["meta"]["amounts"] = "document_currency_not_converted"
	result["meta"]["general_ledger_posting"] = "not_this_report"
	return result


def _cost_share_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	query = db.query(ProductionOrder).filter(ProductionOrder.business_id == int(business_id))
	if start is not None:
		query = query.filter(ProductionOrder.due_date >= start)
	if end is not None:
		query = query.filter(ProductionOrder.due_date <= end)
	wid = _optional_id(args.get("warehouse_id"), "AP_WAREHOUSE_NOT_FOUND")
	if wid is not None:
		query = query.filter(or_(ProductionOrder.warehouse_id == wid, ProductionOrder.output_warehouse_id == wid))
	if args.get("product_id"):
		query = query.filter(ProductionOrder.product_id == int(args["product_id"]))
	orders = query.all()
	actual = cost_share(
		sum((D(order.actual_materials_cost) for order in orders), Decimal("0")),
		sum((D(order.actual_operations_cost) for order in orders), Decimal("0")),
	)
	standard = cost_share(
		sum((D(order.standard_materials_cost) for order in orders), Decimal("0")),
		sum((D(order.standard_operations_cost) for order in orders), Decimal("0")),
	)
	items = []
	for label, share in (("actual", actual), ("standard", standard)):
		if share is None:
			continue
		items.append({
			"basis": label,
			"materials": float(share["materials"]),
			"operations": float(share["operations"]),
			"total": float(share["total"]),
			"materials_percent": float(share["materials_percent"]),
			"operations_percent": float(share["operations_percent"]),
		})
	return _envelope("cost_share", items, {"count": len(items), "order_count": len(orders)}, len(items), 0, max(len(items), 1), settings["costing_method"])


def _qc_pass_rate_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	from app.services.advanced_production_master import list_master

	get_settings(db, business_id)
	data = list_master(db, business_id, "inspections")
	start, end = _date_args(args)
	grouped: Dict[tuple, Dict[str, Any]] = {}
	for row in data["items"]:
		inspected = _parse_date(row.get("inspected_on"))
		if start and inspected and inspected < start:
			continue
		if end and inspected and inspected > end:
			continue
		if args.get("product_id") and int(row.get("product_id") or 0) != int(args["product_id"]):
			continue
		key = (row.get("product_id"), row.get("stage"))
		item = grouped.setdefault(key, {
			"product_id": row.get("product_id"),
			"stage": row.get("stage"),
			"quantity_checked": Decimal("0"),
			"quantity_rejected": Decimal("0"),
		})
		item["quantity_checked"] += D(row.get("quantity_checked"))
		item["quantity_rejected"] += D(row.get("quantity_rejected"))
	items = []
	for item in grouped.values():
		rate = acceptance_rate(item["quantity_checked"], item["quantity_rejected"])
		items.append({
			"product_id": item["product_id"],
			"stage": item["stage"],
			"quantity_checked": float(qty(item["quantity_checked"])),
			"quantity_rejected": float(qty(item["quantity_rejected"])),
			"acceptance_percent": None if rate is None else float(rate),
		})
	return _envelope("qc_pass_rate", items, {"count": len(items)}, len(items), 0, max(len(items), 1), "actual")


def _production_daily_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	finished = _movement_report(db, business_id, "finished_goods", {**args, "skip": 0, "take": 5000})
	grouped: Dict[str, Decimal] = {}
	for row in finished["items"]:
		day = str(row.get("document_date") or "")
		grouped[day] = grouped.get(day, Decimal("0")) + D(row.get("quantity"))
	items = [
		{"document_date": day, "quantity": float(qty(amount))}
		for day, amount in sorted(grouped.items())
	]
	return _envelope("production_daily", items, {"count": len(items)}, len(items), 0, max(len(items), 1), finished["meta"]["costing_method"])


def _monthly_comparison_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	finished = _movement_report(db, business_id, "finished_goods", {**args, "skip": 0, "take": 5000})
	calendar_type = "jalali" if args.get("calendar_type") == "jalali" else "gregorian"
	grouped: Dict[str, Dict[str, Decimal]] = {}
	for row in finished["items"]:
		period = calendar_period(row.get("document_date"), calendar_type)
		if period is None:
			continue
		item = grouped.setdefault(period, {"quantity": Decimal("0"), "amount": Decimal("0")})
		item["quantity"] += D(row.get("quantity"))
		item["amount"] += D(row.get("amount"))
	items = [
		{"period": period, "quantity": float(qty(values["quantity"])), "amount": float(money(values["amount"]))}
		for period, values in sorted(grouped.items())
	]
	result = _envelope("monthly_comparison", items, {"count": len(items)}, len(items), 0, max(len(items), 1), finished["meta"]["costing_method"])
	result["meta"]["calendar_type"] = calendar_type
	result["meta"]["row_cap"] = 5000
	return result


def _yield_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	from app.services.advanced_production_master import output_group_report
	get_settings(db, business_id)
	data = output_group_report(db, business_id, "line_output", date_from=args.get("date_from"), date_to=args.get("date_to"))
	items = []
	for row in data["items"]:
		rate = yield_percent(row.get("quantity_good"), row.get("quantity_scrap"))
		items.append({**row, "yield_percent": None if rate is None else float(rate)})
	return _envelope("yield_rate", items, data["summary"], len(items), 0, max(len(items), 1), "actual")


def _unused_capacity_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	from app.services.advanced_production_master import output_group_report
	get_settings(db, business_id)
	data = output_group_report(db, business_id, "capacity_usage", date_from=args.get("date_from"), date_to=args.get("date_to"))
	items = []
	for row in data["items"]:
		idle = unused_quantity(row.get("ideal_quantity"), D(row.get("quantity_good")) + D(row.get("quantity_scrap")))
		if idle is None:
			continue
		items.append({**row, "unused_quantity": float(idle)})
	return _envelope("unused_capacity", items, {"count": len(items)}, len(items), 0, max(len(items), 1), "actual")


def _break_even_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	if not args.get("product_id") or args.get("fixed_cost") in (None, ""):
		raise ApiError("AP_BREAK_EVEN_INPUTS_REQUIRED", "AP_BREAK_EVEN_INPUTS_REQUIRED", http_status=400)
	profit = _product_profit_report(db, business_id, args)
	fixed = D(args.get("fixed_cost"))
	items = []
	for row in profit["items"]:
		qty = break_even_quantity(fixed, row.get("sales_amount"), row.get("sales_quantity"), row.get("unit_cost"))
		items.append({**row, "fixed_cost": float(money(fixed)), "break_even_quantity": None if qty is None else float(qty)})
	result = _envelope("break_even", items, {"count": len(items)}, len(items), 0, max(len(items), 1), profit["meta"]["costing_method"])
	result["meta"]["break_even"] = "fixed_cost_divided_by_price_minus_period_unit_cost"
	return result


def _lot_trace_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	get_settings(db, business_id)
	lot_code = str(args.get("lot_code") or args.get("search") or "").strip()
	if not lot_code:
		raise ApiError("AP_LOT_CODE_REQUIRED", "AP_LOT_CODE_REQUIRED", http_status=400)
	from app.services.production_order_service import list_production_orders_by_lot
	data = list_production_orders_by_lot(db, business_id, lot_code)
	items = [*data.get("material_matches", []), *data.get("output_matches", [])]
	for row in items:
		row["lot_code"] = data.get("lot_code")
	return _envelope("lot_trace", items, {"count": len(items), "lot_code": lot_code}, len(items), 0, max(len(items), 1), "actual")


def _qc_rejects_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	from app.services.advanced_production_master import list_master
	get_settings(db, business_id)
	rows = []
	for row in list_master(db, business_id, "inspections")["items"]:
		if str(row.get("result")) != "fail" and D(row.get("quantity_rejected")) <= 0:
			continue
		inspected = _parse_date(row.get("inspected_on"))
		start, end = _date_args(args)
		if start and inspected and inspected < start:
			continue
		if end and inspected and inspected > end:
			continue
		rows.append(row)
	return _envelope("qc_rejects", rows, {"count": len(rows)}, len(rows), 0, max(len(rows), 1), "actual")


def _period_cost_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	orders = db.query(ProductionOrder, Product).join(Product, Product.id == ProductionOrder.product_id).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrder.completed_at.isnot(None),
	).all()
	grouped: Dict[int, Dict[str, Any]] = {}
	for order, product in orders:
		if not _order_in_warehouse(order, args):
			continue
		completed = order.completed_at.date()
		if start and completed < start:
			continue
		if end and completed > end:
			continue
		item = grouped.setdefault(product.id, {
			"product_id": product.id,
			"product_code": product.code,
			"product_name": product.name,
			"materials": Decimal("0"),
			"operations": Decimal("0"),
			"order_count": 0,
		})
		item["materials"] += D(order.actual_materials_cost)
		item["operations"] += D(order.actual_operations_cost)
		item["order_count"] += 1
	items = []
	for item in grouped.values():
		total = money(item["materials"] + item["operations"])
		items.append({
			"product_id": item["product_id"],
			"product_code": item["product_code"],
			"product_name": item["product_name"],
			"order_count": item["order_count"],
			"materials": float(money(item["materials"])),
			"operations": float(money(item["operations"])),
			"total": float(total),
		})
	return _envelope("period_cost", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])


def _wip_age_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	today = business_today(business_id)
	rows = db.query(ProductionOrder, Product).join(Product, Product.id == ProductionOrder.product_id).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrder.status.in_(OPEN_STATUSES),
		ProductionOrder.started_at.isnot(None),
	).all()
	items = []
	for order, product in rows:
		if not _order_in_warehouse(order, args):
			continue
		started = order.started_at.date() if hasattr(order.started_at, "date") else order.started_at
		age = (today - started).days
		items.append({
			"production_order_id": order.id,
			"code": order.code,
			"product_name": product.name,
			"status": order.status,
			"started_at": _iso(order.started_at),
			"age_days": age,
			"actual_total": float(money(D(order.actual_materials_cost) + D(order.actual_operations_cost))),
		})
	items.sort(key=lambda row: row["age_days"], reverse=True)
	return _envelope("wip_age", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])


def _flow_bucket() -> Dict[str, Decimal]:
	return {
		"purchased": Decimal("0"),
		"returned": Decimal("0"),
		"consumed": Decimal("0"),
		"scrapped": Decimal("0"),
	}


def _material_consumption_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	"""خروج مواد فاکتور تولید. گزارش مصرف هسته را حذف نمی‌کند."""
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	query = db.query(InvoiceItemLine, Document, Product).join(
		Document, Document.id == InvoiceItemLine.document_id
	).join(Product, Product.id == InvoiceItemLine.product_id).filter(
		Document.business_id == int(business_id),
		Document.document_type == "invoice_production",
		Document.is_proforma.is_(False),
		Product.business_id == int(business_id),
	)
	if start is not None:
		query = query.filter(Document.document_date >= start)
	if end is not None:
		query = query.filter(Document.document_date <= end)
	if args.get("product_id"):
		query = query.filter(Product.id == int(args["product_id"]))
	items = []
	for line, document, product in query.all():
		if not _document_matches(document, line, args):
			continue
		if (line.extra_info or {}).get("movement") != "out":
			continue
		items.append({
			"document_id": document.id,
			"document_date": _iso(document.document_date),
			"document_code": document.code,
			"product_code": product.code,
			"product_name": product.name,
			"quantity": float(qty(line.quantity)),
			"amount": float(_line_cost(line)),
			"production_order_id": _linked_order_id(document, line),
		})
	result = _envelope("material_consumption", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])
	result["meta"]["core_materials_report"] = "unchanged"
	return result


def _material_flow_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	"""گردش دوره. مانده این گزارش موجودی انبار نیست."""
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	kinds = {
		"invoice_purchase": "purchased",
		"invoice_purchase_return": "returned",
		"invoice_production": "consumed",
		"invoice_waste": "scrapped",
	}
	query = db.query(InvoiceItemLine, Document, Product).join(
		Document, Document.id == InvoiceItemLine.document_id
	).join(Product, Product.id == InvoiceItemLine.product_id).filter(
		Document.business_id == int(business_id),
		Document.document_type.in_(tuple(kinds)),
		Document.is_proforma.is_(False),
		Product.business_id == int(business_id),
	)
	if start is not None:
		query = query.filter(Document.document_date >= start)
	if end is not None:
		query = query.filter(Document.document_date <= end)
	if args.get("product_id"):
		query = query.filter(Product.id == int(args["product_id"]))
	grouped: Dict[int, Dict[str, Any]] = {}
	for line, document, product in query.all():
		kind = kinds[document.document_type]
		if kind == "consumed" and (line.extra_info or {}).get("movement") != "out":
			continue
		item = grouped.setdefault(product.id, {
			"product_id": product.id,
			"product_code": product.code,
			"product_name": product.name,
			**_flow_bucket(),
		})
		item[kind] += D(line.quantity)
	items = []
	for item in grouped.values():
		net = item["purchased"] - item["returned"] - item["consumed"] - item["scrapped"]
		items.append({
			"product_id": item["product_id"],
			"product_code": item["product_code"],
			"product_name": item["product_name"],
			"purchased_quantity": float(qty(item["purchased"])),
			"returned_quantity": float(qty(item["returned"])),
			"consumed_quantity": float(qty(item["consumed"])),
			"scrapped_quantity": float(qty(item["scrapped"])),
			"period_net_quantity": float(qty(net)),
		})
	items.sort(key=lambda row: row["product_code"] or "")
	result = _envelope("material_flow", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])
	result["meta"]["period_net"] = "purchases_minus_returns_consumption_and_waste_not_warehouse_balance"
	return result


def _production_by_lot_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	query = db.query(ProductionOrderOutput, Product).join(
		ProductionOrder, ProductionOrder.id == ProductionOrderOutput.production_order_id
	).join(Product, Product.id == ProductionOrderOutput.product_id).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrderOutput.lot_code.isnot(None),
		ProductionOrderOutput.lot_code != "",
	)
	if args.get("product_id"):
		query = query.filter(Product.id == int(args["product_id"]))
	grouped: Dict[tuple, Dict[str, Any]] = {}
	for output, product in query.all():
		made_on = output.manufacturing_date
		if start and (made_on is None or made_on < start):
			continue
		if end and (made_on is None or made_on > end):
			continue
		key = (output.lot_code, product.id)
		item = grouped.setdefault(key, {
			"lot_code": output.lot_code,
			"product_id": product.id,
			"product_code": product.code,
			"product_name": product.name,
			"produced_quantity": Decimal("0"),
			"scrap_quantity": Decimal("0"),
			"manufacturing_date": made_on,
		})
		item["produced_quantity"] += D(output.produced_quantity)
		item["scrap_quantity"] += D(output.scrap_quantity)
		if item["manufacturing_date"] != made_on:
			item["manufacturing_date"] = None
	items = []
	for item in grouped.values():
		items.append({
			**{k: v for k, v in item.items() if k not in ("produced_quantity", "scrap_quantity", "manufacturing_date")},
			"produced_quantity": float(qty(item["produced_quantity"])),
			"scrap_quantity": float(qty(item["scrap_quantity"])),
			"manufacturing_date": _iso(item["manufacturing_date"]),
		})
	items.sort(key=lambda row: (row["lot_code"] or "", row["product_code"] or ""))
	result = _envelope("production_by_lot", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])
	result["meta"]["blank_lot_excluded"] = True
	return result


def _conversion_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	orders = db.query(ProductionOrder, Product).join(Product, Product.id == ProductionOrder.product_id).filter(
		ProductionOrder.business_id == int(business_id),
	).all()
	order_ids = [order.id for order, _product in orders]
	materials: Dict[int, list] = {}
	if order_ids:
		for material in db.query(ProductionOrderMaterial, Product).join(
			Product, Product.id == ProductionOrderMaterial.product_id
		).filter(ProductionOrderMaterial.production_order_id.in_(order_ids)).all():
			materials.setdefault(material[0].production_order_id, []).append(material)
	items = []
	for order, product in orders:
		if not _order_in_warehouse(order, args):
			continue
		completed = order.completed_at.date() if order.completed_at is not None and hasattr(order.completed_at, "date") else None
		if start and (completed is None or completed < start):
			continue
		if end and (completed is None or completed > end):
			continue
		issued = [row for row in materials.get(order.id, []) if D(row[0].issued_quantity) > 0]
		single = issued[0] if len(issued) == 1 else None
		rate = conversion_percent(order.produced_quantity, single[0].issued_quantity) if single else None
		items.append({
			"production_order_id": order.id,
			"code": order.code,
			"product_name": product.name,
			"produced_quantity": float(qty(order.produced_quantity)),
			"material_count": len(issued),
			"material_name": single[1].name if single else None,
			"issued_quantity": None if single is None else float(qty(single[0].issued_quantity)),
			"conversion_percent": None if rate is None else float(rate),
		})
	result = _envelope("conversion_efficiency", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])
	result["meta"]["conversion"] = "produced_over_issued_only_when_one_material"
	return result


def _low_yield_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	from adapters.db.models.advanced_production import AdvancedProductionOutputLog
	get_settings(db, business_id)
	start, end = _date_args(args)
	query = db.query(AdvancedProductionOutputLog, Product).join(
		Product, Product.id == AdvancedProductionOutputLog.product_id
	).filter(AdvancedProductionOutputLog.business_id == int(business_id))
	if start is not None:
		query = query.filter(AdvancedProductionOutputLog.produced_on >= start)
	if end is not None:
		query = query.filter(AdvancedProductionOutputLog.produced_on <= end)
	grouped: Dict[int, Dict[str, Any]] = {}
	for log, product in query.all():
		item = grouped.setdefault(product.id, {
			"product_id": product.id,
			"product_code": product.code,
			"product_name": product.name,
			"quantity_good": Decimal("0"),
			"quantity_scrap": Decimal("0"),
		})
		item["quantity_good"] += D(log.quantity_good)
		item["quantity_scrap"] += D(log.quantity_scrap)
	items = []
	for item in grouped.values():
		rate = yield_percent(item["quantity_good"], item["quantity_scrap"])
		items.append({
			"product_id": item["product_id"],
			"product_code": item["product_code"],
			"product_name": item["product_name"],
			"quantity_good": float(qty(item["quantity_good"])),
			"quantity_scrap": float(qty(item["quantity_scrap"])),
			"yield_percent": None if rate is None else float(rate),
		})
	items.sort(key=lambda row: (row["yield_percent"] is None, row["yield_percent"] if row["yield_percent"] is not None else 0))
	result = _envelope("low_yield", items, {"count": len(items)}, len(items), 0, max(len(items), 1), "actual")
	result["meta"]["ranking"] = "ascending_yield_without_cutoff"
	return result


def _line_maintenance_cost_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	from adapters.db.models.advanced_production import (
		AdvancedProductionLine,
		AdvancedProductionMachine,
		AdvancedProductionMaintenance,
	)
	get_settings(db, business_id)
	start, end = _date_args(args)
	query = db.query(AdvancedProductionMaintenance, AdvancedProductionMachine, AdvancedProductionLine).join(
		AdvancedProductionMachine, AdvancedProductionMachine.id == AdvancedProductionMaintenance.machine_id
	).outerjoin(
		AdvancedProductionLine,
		AdvancedProductionLine.id == func.coalesce(AdvancedProductionMaintenance.line_id, AdvancedProductionMachine.line_id),
	).filter(AdvancedProductionMaintenance.business_id == int(business_id))
	if start is not None:
		query = query.filter(AdvancedProductionMaintenance.opened_on >= start)
	if end is not None:
		query = query.filter(AdvancedProductionMaintenance.opened_on <= end)
	grouped: Dict[int, Dict[str, Any]] = {}
	for order, _machine, line in query.all():
		line_id = int(line.id) if line is not None else 0
		item = grouped.setdefault(line_id, {
			"line_id": None if line is None else line.id,
			"line_code": None if line is None else line.code,
			"line_name": None if line is None else line.name,
			"cost_amount": Decimal("0"),
			"repair_minutes": 0,
			"record_count": 0,
		})
		item["cost_amount"] += D(order.cost_amount)
		item["repair_minutes"] += int(order.repair_minutes or 0)
		item["record_count"] += 1
	items = [
		{**item, "cost_amount": float(money(item["cost_amount"]))}
		for item in grouped.values()
	]
	result = _envelope("line_maintenance_cost", items, {"count": len(items)}, len(items), 0, max(len(items), 1), "actual")
	result["meta"]["general_ledger_posting"] = "not_this_report"
	return result


def _linked_order_id(document: Document, line: InvoiceItemLine) -> Optional[int]:
	info = line.extra_info or {}
	header = document.extra_info or {}
	raw = info.get("production_order_id") or header.get("production_order_id")
	try:
		return int(raw) if raw not in (None, "") else None
	except (TypeError, ValueError):
		return None


def _material_price_variance_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	query = db.query(ProductionOrderMaterial, ProductionOrder, Product).join(
		ProductionOrder, ProductionOrder.id == ProductionOrderMaterial.production_order_id
	).join(Product, Product.id == ProductionOrderMaterial.product_id).filter(
		ProductionOrder.business_id == int(business_id),
		Product.business_id == int(business_id),
	)
	start, end = _date_args(args)
	if args.get("product_id"):
		query = query.filter(ProductionOrderMaterial.product_id == int(args["product_id"]))
	if start is not None:
		query = query.filter(ProductionOrder.due_date >= start)
	if end is not None:
		query = query.filter(ProductionOrder.due_date <= end)
	wid = _optional_id(args.get("warehouse_id"), "AP_WAREHOUSE_NOT_FOUND")
	if wid is not None:
		query = query.filter(or_(ProductionOrder.warehouse_id == wid, ProductionOrder.output_warehouse_id == wid))
	items = []
	for material, order, product in query.all():
		split = material_rate_split(
			material.planned_quantity,
			material.issued_quantity,
			material.standard_unit_cost,
			material.actual_total_cost,
		)
		items.append({
			"order_code": order.code,
			"product_code": product.code,
			"product_name": product.name,
			"planned_quantity": float(qty(material.planned_quantity)),
			"issued_quantity": float(qty(material.issued_quantity)),
			"standard_unit_cost": None if split is None else float(D(material.standard_unit_cost).quantize(Decimal("0.000001"))),
			"usage_variance": None if split is None else float(split["usage_variance"]),
			"price_variance": None if split is None or split["price_variance"] is None else float(split["price_variance"]),
		})
	result = _envelope("material_price_variance", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])
	result["meta"]["standard_rate"] = "order_line_standard_unit_cost_not_a_purchase_price_list"
	result["meta"]["positive_variance"] = "unfavorable"
	return result


def _product_cost_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	method = settings["costing_method"]
	start, end = _date_args(args)
	orders = db.query(ProductionOrder, Product).join(Product, Product.id == ProductionOrder.product_id).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrder.status == "completed",
		Product.business_id == int(business_id),
	).all()
	averages = _averages(db, business_id, args) if method == "weighted_average" else {}
	grouped: Dict[int, Dict[str, Any]] = {}
	for order, product in orders:
		if not _order_in_warehouse(order, args):
			continue
		completed = order.completed_at.date() if order.completed_at is not None else None
		if start and (completed is None or completed < start):
			continue
		if end and (completed is None or completed > end):
			continue
		standard_total = money(order.standard_materials_cost) + money(order.standard_operations_cost)
		actual_total = money(order.actual_materials_cost) + money(order.actual_operations_cost)
		valued = valued_order_cost(method, standard_total, actual_total, order.produced_quantity, averages.get(int(product.id)))
		item = grouped.setdefault(product.id, {
			"product_id": product.id,
			"product_code": product.code,
			"product_name": product.name,
			"produced_quantity": Decimal("0"),
			"standard_total": Decimal("0"),
			"actual_total": Decimal("0"),
			"valued_total": Decimal("0"),
			"order_count": 0,
		})
		item["produced_quantity"] += D(order.produced_quantity)
		item["standard_total"] += standard_total
		item["actual_total"] += actual_total
		item["valued_total"] += valued
		item["order_count"] += 1
	items = []
	for item in grouped.values():
		produced = item["produced_quantity"]
		unit = None if produced <= 0 else (item["valued_total"] / produced).quantize(Decimal("0.000001"))
		items.append({
			"product_id": item["product_id"],
			"product_code": item["product_code"],
			"product_name": item["product_name"],
			"order_count": item["order_count"],
			"produced_quantity": float(qty(produced)),
			"standard_total": float(money(item["standard_total"])),
			"actual_total": float(money(item["actual_total"])),
			"valued_total": float(money(item["valued_total"])),
			"unit_cost": None if unit is None else float(unit),
		})
	result = _envelope("product_cost", items, {"count": len(items)}, len(items), 0, max(len(items), 1), method)
	result["meta"]["valuation"] = "selected_costing_method_on_completed_orders"
	result["meta"]["general_ledger_posting"] = "not_this_report"
	return result


def _wip_balance_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	receipts: Dict[int, Decimal] = {}
	query = db.query(InvoiceItemLine, Document).join(Document, Document.id == InvoiceItemLine.document_id).filter(
		Document.business_id == int(business_id),
		Document.document_type == "invoice_production",
		Document.is_proforma.is_(False),
	)
	for line, document in query.all():
		if not _document_matches(document, line, args):
			continue
		if (line.extra_info or {}).get("movement") != "in":
			continue
		order_id = _linked_order_id(document, line)
		if order_id is None:
			continue
		receipts[order_id] = receipts.get(order_id, Decimal("0")) + _line_cost(line)
	rows = db.query(ProductionOrder, Product).join(Product, Product.id == ProductionOrder.product_id).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrder.status.in_(OPEN_STATUSES),
	).all()
	items = []
	for order, product in rows:
		if not _order_in_warehouse(order, args):
			continue
		actual = money(D(order.actual_materials_cost) + D(order.actual_operations_cost))
		transferred = money(receipts.get(order.id, Decimal("0")))
		items.append({
			"production_order_id": order.id,
			"code": order.code,
			"product_code": product.code,
			"product_name": product.name,
			"status": order.status,
			"actual_total": float(actual),
			"transferred_amount": float(transferred),
			"remaining_wip": float(money(actual - transferred)),
		})
	result = _envelope("wip_balance", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])
	result["meta"]["remaining_wip"] = "open_order_actual_minus_linked_finished_receipts_not_gl_account"
	result["meta"]["as_of_date"] = business_today(business_id).isoformat()
	return result


def _wip_by_center_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	from adapters.db.models.advanced_production import (
		AdvancedProductionLine,
		AdvancedProductionOrderLine,
		AdvancedProductionWorkCenter,
	)
	balance = _wip_balance_report(db, business_id, args)
	links = db.query(AdvancedProductionOrderLine, AdvancedProductionLine, AdvancedProductionWorkCenter).join(
		AdvancedProductionLine, AdvancedProductionLine.id == AdvancedProductionOrderLine.line_id
	).outerjoin(
		AdvancedProductionWorkCenter, AdvancedProductionWorkCenter.id == AdvancedProductionLine.work_center_id
	).filter(AdvancedProductionOrderLine.business_id == int(business_id)).all()
	center_by_order = {}
	for link, _line, center in links:
		if center is None:
			continue
		center_by_order[link.production_order_id] = center
	grouped: Dict[int, Dict[str, Any]] = {}
	for row in balance["items"]:
		center = center_by_order.get(row["production_order_id"])
		if center is None:
			continue
		item = grouped.setdefault(center.id, {
			"work_center_name": center.name,
			"order_count": 0,
			"remaining_wip": Decimal("0"),
		})
		item["order_count"] += 1
		item["remaining_wip"] += D(row["remaining_wip"])
	items = [{**item, "remaining_wip": float(money(item["remaining_wip"]))} for item in grouped.values()]
	result = _envelope("wip_by_center", items, {"count": len(items)}, len(items), 0, max(len(items), 1), balance["meta"]["costing_method"])
	result["meta"]["unassigned_orders_excluded"] = True
	result["meta"]["remaining_wip"] = balance["meta"]["remaining_wip"]
	return result


def _production_material_ids(db: Session, business_id: int) -> set:
	rows = db.query(ProductionOrderMaterial.product_id).join(
		ProductionOrder, ProductionOrder.id == ProductionOrderMaterial.production_order_id
	).filter(ProductionOrder.business_id == int(business_id)).distinct().all()
	return {int(row[0]) for row in rows}


def _material_scrap_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	material_ids = _production_material_ids(db, business_id)
	start, end = _date_args(args)
	items = []
	if material_ids:
		query = db.query(InvoiceItemLine, Document, Product).join(
			Document, Document.id == InvoiceItemLine.document_id
		).join(Product, Product.id == InvoiceItemLine.product_id).filter(
			Document.business_id == int(business_id),
			Document.document_type == "invoice_waste",
			Document.is_proforma.is_(False),
			Product.id.in_(material_ids),
		)
		if start is not None:
			query = query.filter(Document.document_date >= start)
		if end is not None:
			query = query.filter(Document.document_date <= end)
		for line, document, product in query.all():
			if not _document_matches(document, line, args):
				continue
			items.append({
				"document_id": document.id,
				"document_date": _iso(document.document_date),
				"document_code": document.code,
				"product_code": product.code,
				"product_name": product.name,
				"quantity": float(qty(line.quantity)),
				"amount": float(_line_cost(line)),
			})
	result = _envelope("material_scrap", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])
	result["meta"]["scope"] = "waste_invoices_for_products_used_as_production_materials"
	result["meta"]["reason"] = "not_recorded_on_waste_invoice"
	return result


def _idle_materials_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	from datetime import timedelta
	from adapters.db.models.warehouse_document import WarehouseDocument
	from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
	from app.services.warehouse_reports_service import _operational_stock

	get_settings(db, business_id)
	try:
		days = int(args.get("days_without_movement") or 90)
	except (TypeError, ValueError) as exc:
		raise ApiError("AP_IDLE_DAYS_INVALID", "AP_IDLE_DAYS_INVALID", http_status=400) from exc
	if days < 1:
		raise ApiError("AP_IDLE_DAYS_INVALID", "AP_IDLE_DAYS_INVALID", http_status=400)
	material_ids = _production_material_ids(db, business_id)
	today = business_today(business_id)
	cutoff = today - timedelta(days=days)
	moved = set()
	if material_ids:
		rows = db.query(WarehouseDocumentLine.product_id).join(
			WarehouseDocument, WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id
		).filter(
			WarehouseDocument.business_id == int(business_id),
			WarehouseDocument.status == "posted",
			WarehouseDocument.document_date >= cutoff,
			WarehouseDocumentLine.product_id.in_(material_ids),
		).distinct().all()
		moved = {int(row[0]) for row in rows}
	idle_ids = material_ids - moved
	products = []
	if idle_ids:
		products = db.query(Product).filter(Product.business_id == int(business_id), Product.id.in_(idle_ids)).all()
	items = []
	for product in products:
		stock = _operational_stock(db, business_id, product, None, today)
		items.append({
			"product_code": product.code,
			"product_name": product.name,
			"current_stock": float(stock),
			"days_without_movement": days,
		})
	result = _envelope("idle_materials", items, {"count": len(items)}, len(items), 0, max(len(items), 1), "actual")
	result["meta"]["cutoff_date"] = cutoff.isoformat()
	result["meta"]["default_days"] = 90
	result["meta"]["scope"] = "products_that_appear_on_production_order_materials"
	return result


def _operation_variance_report(db: Session, business_id: int, args: Dict[str, Any]) -> Dict[str, Any]:
	settings = get_settings(db, business_id)
	start, end = _date_args(args)
	rows = db.query(ProductionOrder, Product).join(Product, Product.id == ProductionOrder.product_id).filter(
		ProductionOrder.business_id == int(business_id),
	).all()
	items = []
	for order, product in rows:
		if not _order_in_warehouse(order, args):
			continue
		completed = order.completed_at.date() if order.completed_at is not None else None
		if start and (completed is None or completed < start):
			continue
		if end and (completed is None or completed > end):
			continue
		standard = money(order.standard_operations_cost)
		actual = money(order.actual_operations_cost)
		items.append({
			"code": order.code,
			"product_name": product.name,
			"standard_operations": float(standard),
			"actual_operations": float(actual),
			"operation_variance": float(cost_variance(actual, standard)),
		})
	result = _envelope("operation_variance", items, {"count": len(items)}, len(items), 0, max(len(items), 1), settings["costing_method"])
	result["meta"]["overhead"] = "bom_operation_amounts_not_a_separate_absorption_rate"
	result["meta"]["positive_variance"] = "unfavorable"
	return result


def run_named_report(db: Session, business_id: int, report_key: str, args: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
	key = (report_key or "").strip().removeprefix("advprod_")
	if key not in REPORT_KEYS:
		raise ApiError("AP_REPORT_UNKNOWN", "AP_REPORT_UNKNOWN", http_status=404)
	payload = dict(args or {})
	warehouse_id = _optional_id(payload.get("warehouse_id"), "AP_WAREHOUSE_NOT_FOUND")
	if warehouse_id is not None:
		from adapters.db.models.warehouse import Warehouse
		found = db.query(Warehouse.id).filter(
			Warehouse.id == warehouse_id,
			Warehouse.business_id == int(business_id),
		).first()
		if found is None:
			raise ApiError("AP_WAREHOUSE_NOT_FOUND", "AP_WAREHOUSE_NOT_FOUND", http_status=404)
		payload["warehouse_id"] = warehouse_id
	currency_id = _optional_id(payload.get("currency_id"), "AP_CURRENCY_NOT_FOUND")
	if currency_id is not None:
		payload["currency_id"] = currency_id
	if _apply_fiscal_year(db, business_id, payload):
		settings = get_settings(db, business_id)
		skip, take = _bounds(payload.get("skip", 0), payload.get("take") or payload.get("limit") or 50)
		result = _envelope(key, [], {"count": 0}, 0, skip, take, settings["costing_method"])
		result["meta"]["date_range"] = "outside_fiscal_year"
		return result
	if key in ("material_requirements", "material_shortage"):
		return _material_rows(db, business_id, payload, shortage_only=key == "material_shortage")
	if key == "material_variance":
		return _variance_report(db, business_id, payload)
	if key in ("scrap", "scrap_by_product", "scrap_rate", "finished_goods", "finished_by_product", "unplanned_production"):
		return _movement_report(db, business_id, key, payload)
	if key == "product_profit":
		return _product_profit_report(db, business_id, payload)
	if key == "cost_share":
		return _cost_share_report(db, business_id, payload)
	if key == "qc_pass_rate":
		return _qc_pass_rate_report(db, business_id, payload)
	if key == "production_daily":
		return _production_daily_report(db, business_id, payload)
	if key == "setup_time":
		from app.services.advanced_production_master import setup_time_report
		return setup_time_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "lot_trace":
		return _lot_trace_report(db, business_id, payload)
	if key == "yield_rate":
		return _yield_report(db, business_id, payload)
	if key == "unused_capacity":
		return _unused_capacity_report(db, business_id, payload)
	if key == "break_even":
		return _break_even_report(db, business_id, payload)
	if key == "monthly_comparison":
		return _monthly_comparison_report(db, business_id, payload)
	if key == "material_flow":
		return _material_flow_report(db, business_id, payload)
	if key == "production_by_lot":
		return _production_by_lot_report(db, business_id, payload)
	if key == "conversion_efficiency":
		return _conversion_report(db, business_id, payload)
	if key == "low_yield":
		return _low_yield_report(db, business_id, payload)
	if key == "line_maintenance_cost":
		return _line_maintenance_cost_report(db, business_id, payload)
	if key == "material_price_variance":
		return _material_price_variance_report(db, business_id, payload)
	if key == "product_cost":
		return _product_cost_report(db, business_id, payload)
	if key == "wip_balance":
		return _wip_balance_report(db, business_id, payload)
	if key == "operation_variance":
		return _operation_variance_report(db, business_id, payload)
	if key in ("scrap_by_reason", "recyclable_scrap", "nonrecyclable_scrap"):
		from app.services.advanced_production_master import scrap_classified_report
		mode = "all" if key == "scrap_by_reason" else ("recyclable" if key == "recyclable_scrap" else "nonrecyclable")
		return scrap_classified_report(db, business_id, mode, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "qc_causes":
		from app.services.advanced_production_master import qc_cause_report
		return qc_cause_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "machine_output":
		from app.services.advanced_production_master import machine_output_report
		return machine_output_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "downtime_cost":
		from app.services.advanced_production_master import downtime_cost_report
		return downtime_cost_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "held_orders":
		from app.services.advanced_production_master import held_orders_report
		return held_orders_report(db, business_id)
	if key == "material_consumption":
		return _material_consumption_report(db, business_id, payload)
	if key == "capacity_required":
		from app.services.advanced_production_master import capacity_report
		return capacity_report(db, business_id)
	if key == "wip_count":
		from app.services.advanced_production_master import wip_count_report
		return wip_count_report(db, business_id)
	if key == "rework":
		from app.services.advanced_production_master import rework_report
		return rework_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "line_returns":
		from app.services.advanced_production_master import line_return_report
		return line_return_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "wip_by_center":
		return _wip_by_center_report(db, business_id, payload)
	if key == "material_scrap":
		return _material_scrap_report(db, business_id, payload)
	if key == "idle_materials":
		return _idle_materials_report(db, business_id, payload)
	if key == "stage_transfers":
		from app.services.advanced_production_master import stage_transfer_report
		return stage_transfer_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "wage_variance":
		from app.services.advanced_production_master import wage_variance_report
		return wage_variance_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key in ("line_output", "shift_output", "work_center_output", "capacity_usage", "operator_output"):
		from app.services.advanced_production_master import output_group_report
		return output_group_report(db, business_id, key, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key == "qc_rejects":
		return _qc_rejects_report(db, business_id, payload)
	if key == "period_cost":
		return _period_cost_report(db, business_id, payload)
	if key == "wip_age":
		return _wip_age_report(db, business_id, payload)
	if key == "reliability":
		from app.services.advanced_production_master import reliability_report
		return reliability_report(db, business_id)
	if key == "maintenance":
		from app.services.advanced_production_master import list_master
		data = list_master(db, business_id, "maintenance")
		items = data["items"]
		return _envelope(key, items, {"count": len(items)}, len(items), 0, max(len(items), 1), "actual")
	if key == "oee":
		from app.services.advanced_production_master import oee_report
		return oee_report(db, business_id, date_from=payload.get("date_from"), date_to=payload.get("date_to"))
	if key in ("downtime", "inspections"):
		from app.services.advanced_production_master import list_master
		data = list_master(db, business_id, "downtime" if key == "downtime" else "inspections")
		items = data["items"]
		return _envelope(key, items, {"count": len(items)}, len(items), 0, max(len(items), 1), "actual")
	return _order_report(db, business_id, key, payload)


def _report_summary(db: Session, business_id: int, key: str, args: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
	data = run_named_report(db, business_id, key, {"skip": 0, "take": 1, **(args or {})})
	summary = data.get("summary") or {}
	return summary if isinstance(summary, dict) else {}


def get_dashboard(db: Session, business_id: int) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	today = business_today(business_id)
	today_iso = today.isoformat()
	open_summary = _report_summary(db, business_id, "open_orders")
	progress_summary = _report_summary(db, business_id, "orders", {"status": "in_progress"})
	overdue_summary = _report_summary(db, business_id, "overdue")
	finished_summary = _report_summary(db, business_id, "finished_goods", {"date_from": today_iso, "date_to": today_iso})
	week_start = today.fromordinal(today.toordinal() - 6)
	daily = run_named_report(db, business_id, "production_daily", {
		"date_from": week_start.isoformat(),
		"date_to": today_iso,
		"skip": 0,
		"take": 20,
	})
	by_day = {
		str(row.get("document_date") or "")[:10]: row.get("quantity") or 0
		for row in (daily.get("items") or [])
		if isinstance(row, dict)
	}
	week = []
	for offset in range(7):
		day = week_start.fromordinal(week_start.toordinal() + offset)
		week.append({"document_date": day.isoformat(), "quantity": by_day.get(day.isoformat(), 0)})
	shortage_summary = _report_summary(db, business_id, "material_shortage")
	plan_summary = _report_summary(db, business_id, "plan_achievement")
	planned_qty = D(plan_summary.get("planned_quantity"))
	plan_percent = None if planned_qty <= 0 else float(progress_percent(planned_qty, plan_summary.get("produced_quantity")))
	scrap_summary = _report_summary(db, business_id, "scrap")
	finished_all = _report_summary(db, business_id, "finished_goods")
	scrap_base = D(scrap_summary.get("quantity")) + D(finished_all.get("quantity"))
	scrap_percent = None if scrap_base <= 0 else float(progress_percent(scrap_base, scrap_summary.get("quantity")))
	period = run_named_report(db, business_id, "period_cost", {
		"date_from": week_start.isoformat(),
		"date_to": today_iso,
		"skip": 0,
		"take": 1,
	})
	period_total = money(sum((D(row.get("total")) for row in (period.get("items") or []) if isinstance(row, dict)), Decimal("0")))
	start, end = business_day_utc_bounds(business_id, today)
	completed_today = db.query(ProductionOrder).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrder.completed_at.isnot(None),
		ProductionOrder.completed_at >= start.replace(tzinfo=timezone.utc),
		ProductionOrder.completed_at <= end.replace(tzinfo=timezone.utc),
	).count()
	settings = get_settings(db, business_id)
	return {
		"as_of_date": today_iso,
		"timezone": "business",
		"open_orders": int(open_summary.get("count") or 0),
		"in_progress_orders": int(progress_summary.get("count") or 0),
		"overdue_orders": int(overdue_summary.get("count") or 0),
		"completed_today": completed_today,
		"output_quantity_today": finished_summary.get("quantity") or 0,
		"week_output": week,
		"plan_achievement_percent": plan_percent,
		"scrap_percent": scrap_percent,
		"period_cost_week": float(period_total),
		"period_cost_from": week_start.isoformat(),
		"period_cost_to": today_iso,
		"shortage_lines": int(shortage_summary.get("count") or 0),
		"shortage_quantity": shortage_summary.get("shortage_quantity") or 0,
		"costing_method": settings["costing_method"],
		"general_ledger_posting": settings["general_ledger_posting"],
		"links": {
			"open_orders": "open_orders",
			"in_progress_orders": "orders",
			"overdue_orders": "overdue",
			"completed_today": "orders",
			"output_quantity_today": "finished_goods",
			"shortage_lines": "material_shortage",
			"plan_achievement_percent": "plan_achievement",
			"scrap_percent": "scrap_rate",
			"period_cost_week": "period_cost",
		},
	}


def export_rows(db: Session, business_id: int, report_key: str, args: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
	payload = dict(args or {})
	payload["skip"] = 0
	payload["take"] = 5000
	return run_named_report(db, business_id, report_key, payload)
