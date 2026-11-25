"""برنامه ثبت فاکتور تولید.

بدون افزونه، یا بدون نگاشت حساب و بدون نیاز به WIP باز، خروجی None است
و مسیر فعلی دفتر کل دست نمی‌خورد.
با افزونه، جمع بدهکار و بستانکار برابر می‌ماند:
مواد + عملیات = بهای محصول + انحراف.
انحراف مثبت نامساعد است و به حساب انحراف می‌رود.
"""
from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.services.advanced_production_calc import money, weighted_average_unit

MONEY_TOLERANCE = Decimal("0.01")


def build_production_journal(
	materials_cost,
	operations_cost,
	finished_cost,
	variance_cost,
) -> List[Dict[str, Any]]:
	"""نقش هر سطر: wip, raw_inventory, overhead, finished, variance."""
	materials = money(materials_cost)
	operations = money(operations_cost)
	finished = money(finished_cost)
	variance = money(variance_cost)
	actual = materials + operations
	open_wip = finished == 0 and variance == 0
	if not open_wip and money(finished + variance) != actual:
		raise ValueError("PRODUCTION_JOURNAL_UNBALANCED")
	lines: List[Dict[str, Any]] = []
	if materials > 0:
		lines.append(_line("wip", materials, 0, "production_wip_materials"))
		lines.append(_line("raw_inventory", 0, materials, "production_raw_issue"))
	if operations > 0:
		lines.append(_line("wip", operations, 0, "production_wip_overhead"))
		lines.append(_line("overhead", 0, operations, "production_overhead"))
	if finished > 0:
		lines.append(_line("finished", finished, 0, "production_finished_in"))
		lines.append(_line("wip", 0, finished, "production_wip_relief"))
	if variance > 0:
		lines.append(_line("variance", variance, 0, "production_variance_unfavorable"))
		lines.append(_line("wip", 0, variance, "production_wip_variance"))
	elif variance < 0:
		amount = money(-variance)
		lines.append(_line("wip", amount, 0, "production_wip_variance"))
		lines.append(_line("variance", 0, amount, "production_variance_favorable"))
	_assert_balanced(lines)
	return lines


def _line(role: str, debit, credit, key: str) -> Dict[str, Any]:
	return {
		"role": role,
		"debit": money(debit),
		"credit": money(credit),
		"description_key": key,
	}


def _assert_balanced(lines: List[Dict[str, Any]]) -> None:
	debit = sum((line["debit"] for line in lines), Decimal("0"))
	credit = sum((line["credit"] for line in lines), Decimal("0"))
	if money(debit) != money(credit):
		raise ValueError("PRODUCTION_JOURNAL_UNBALANCED")


def value_finished_goods(
	method: str,
	actual_cost,
	output_quantity,
	standard_unit,
	average_unit,
) -> tuple[Decimal, Decimal]:
	"""برمی‌گرداند (بهای محصول، انحراف). انحراف = واقعی − محصول."""
	actual = money(actual_cost)
	qty = Decimal(str(output_quantity or 0))
	if qty <= 0:
		return Decimal("0.00"), Decimal("0.00")
	if method == "standard" and standard_unit is not None:
		finished = money(Decimal(str(standard_unit)) * qty)
	elif method == "weighted_average" and average_unit is not None:
		finished = money(Decimal(str(average_unit)) * qty)
	else:
		finished = actual
	return finished, money(actual - finished)


def plan_production_posting(
	db: Session,
	business_id: int,
	header_extra: Optional[Dict[str, Any]],
	materials_cost,
	operations_cost,
	output_quantity,
	*,
	product_id: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
	from app.core.advanced_production_plugin_dependency import check_advanced_production_plugin_active
	from adapters.db.models.advanced_production import AdvancedProductionSettings
	from adapters.db.models.production_order import ProductionOrder

	if not check_advanced_production_plugin_active(db, int(business_id)):
		return None
	row = db.query(AdvancedProductionSettings).filter(
		AdvancedProductionSettings.business_id == int(business_id)
	).first()
	method = (row.costing_method if row else "actual") or "actual"
	wip_id = row.wip_account_id if row else None
	finished_id = row.finished_goods_account_id if row else None
	variance_id = row.cost_variance_account_id if row else None
	actual = money(materials_cost) + money(operations_cost)
	qty = Decimal(str(output_quantity or 0))
	open_wip = qty <= 0 and actual > 0
	revalue = method in {"standard", "weighted_average"} and variance_id is not None and qty > 0
	mapped = any(value is not None for value in (wip_id, finished_id))
	if posting_requires_variance_account(method, qty, mapped, variance_id is not None):
		from app.core.responses import ApiError
		raise ApiError("AP_VARIANCE_ACCOUNT_REQUIRED", "AP_VARIANCE_ACCOUNT_REQUIRED", http_status=400)
	if not open_wip and not revalue and not mapped:
		return None

	standard_unit = None
	average_unit = None
	order_id = (header_extra or {}).get("production_order_id")
	if revalue and method == "standard" and order_id:
		order = db.query(ProductionOrder).filter(
			ProductionOrder.id == int(order_id),
			ProductionOrder.business_id == int(business_id),
		).first()
		if order is not None and Decimal(str(order.planned_quantity or 0)) > 0:
			standard_total = money(order.standard_materials_cost) + money(order.standard_operations_cost)
			standard_unit = standard_total / Decimal(str(order.planned_quantity))
	if revalue and method == "weighted_average" and product_id:
		from sqlalchemy import func
		total_cost, total_qty = db.query(
			func.coalesce(func.sum(ProductionOrder.actual_materials_cost + ProductionOrder.actual_operations_cost), 0),
			func.coalesce(func.sum(ProductionOrder.produced_quantity), 0),
		).filter(
			ProductionOrder.business_id == int(business_id),
			ProductionOrder.product_id == int(product_id),
			ProductionOrder.status == "completed",
			ProductionOrder.produced_quantity > 0,
		).one()
		average_unit = weighted_average_unit(total_cost, total_qty)

	if revalue:
		finished, variance = value_finished_goods(method, actual, qty, standard_unit, average_unit)
	elif open_wip:
		finished, variance = Decimal("0.00"), Decimal("0.00")
	else:
		finished, variance = actual, Decimal("0.00")

	journal = build_production_journal(materials_cost, operations_cost, finished, variance)
	unit = money(finished / qty) if qty > 0 else None
	return {
		"costing_method": method if revalue else "actual",
		"wip_account_id": wip_id,
		"finished_goods_account_id": finished_id,
		"variance_account_id": variance_id if variance != 0 else None,
		"finished_cost": finished,
		"variance_cost": variance,
		"unit_cost": unit,
		"open_wip": open_wip,
		"journal": journal,
		"general_ledger_posting": "plugin",
	}


def posting_requires_variance_account(method: str, output_quantity, has_mapped_account: bool, has_variance_account: bool) -> bool:
	"""روش استاندارد یا میانگین با حساب نگاشت‌شده، بدون حساب انحراف، نباید بهای واقعی را به‌جای روش انتخابی سند کند."""
	if method not in {"standard", "weighted_average"}:
		return False
	if not has_mapped_account or has_variance_account:
		return False
	return Decimal(str(output_quantity or 0)) > 0


def choose_waste_expense_account(default_account_id: int, mapped_account_id: Optional[int]) -> int:
	"""حساب هزینه ضایعات. بدون نگاشت افزونه، حساب پیش‌فرض هسته می‌ماند."""
	if mapped_account_id:
		return int(mapped_account_id)
	return int(default_account_id)


def mapped_scrap_expense_account_id(db: Session, business_id: int) -> Optional[int]:
	from adapters.db.models.advanced_production import AdvancedProductionSettings
	from app.core.advanced_production_plugin_dependency import check_advanced_production_plugin_active

	if not check_advanced_production_plugin_active(db, int(business_id)):
		return None
	row = db.query(AdvancedProductionSettings).filter(
		AdvancedProductionSettings.business_id == int(business_id)
	).first()
	if row is None or row.scrap_expense_account_id is None:
		return None
	return int(row.scrap_expense_account_id)
