"""همگام‌سازی قرارگیری فیزیکی کالا (جدول placements) با خطوط حوالهٔ پست‌شده."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import List, Sequence

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.product import Product
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from adapters.db.models.warehouse_location import WarehouseLocation
from adapters.db.models.warehouse_product_placement import WarehouseProductPlacement
from app.core.responses import ApiError


def validate_warehouse_location_for_line(
	db: Session,
	business_id: int,
	warehouse_id: int,
	location_id: int,
) -> None:
	loc = (
		db.query(WarehouseLocation)
		.filter(
			and_(
				WarehouseLocation.id == int(location_id),
				WarehouseLocation.business_id == int(business_id),
				WarehouseLocation.warehouse_id == int(warehouse_id),
			)
		)
		.first()
	)
	if not loc:
		raise ApiError(
			"INVALID_WAREHOUSE_LOCATION",
			"شناسه محل انبار معتبر نیست یا با این انبار هم‌خوان نیست",
			http_status=400,
		)


def _placement_delta_for_movement(movement: str, qty: Decimal, forward: bool) -> Decimal:
	"""اثر بر ماندهٔ قرارگیری در یک محل: ورود افزایش، خروج کاهش."""
	sign = Decimal(1) if forward else Decimal(-1)
	base = qty if movement == "in" else -qty
	return base * sign


def _upsert_placement_delta(
	db: Session,
	business_id: int,
	warehouse_id: int,
	location_id: int,
	product_id: int,
	delta: Decimal,
) -> None:
	if delta == 0:
		return

	row = (
		db.query(WarehouseProductPlacement)
		.filter(
			and_(
				WarehouseProductPlacement.business_id == business_id,
				WarehouseProductPlacement.warehouse_id == warehouse_id,
				WarehouseProductPlacement.warehouse_location_id == location_id,
				WarehouseProductPlacement.product_id == product_id,
			)
		)
		.first()
	)

	if row:
		new_q = Decimal(str(row.quantity)) + delta
		if new_q < 0:
			raise ApiError(
				"INSUFFICIENT_PLACEMENT_QTY",
				"مقدار ثبت‌شده در محل برای این خروج کافی نیست؛ ابتدا قرارگیری را اصلاح کنید یا محل را خالی بگذارید",
				http_status=409,
			)
		if new_q == 0:
			db.delete(row)
		else:
			row.quantity = new_q
			row.updated_at = datetime.utcnow()
	else:
		if delta < 0:
			raise ApiError(
				"INSUFFICIENT_PLACEMENT_QTY",
				"در این محل برای این کالا قرارگیری ثبت نشده است",
				http_status=409,
			)
		now = datetime.utcnow()
		pl = WarehouseProductPlacement(
			business_id=business_id,
			warehouse_id=warehouse_id,
			warehouse_location_id=location_id,
			product_id=product_id,
			quantity=delta,
			notes=None,
			created_at=now,
			updated_at=now,
		)
		db.add(pl)


def apply_placement_effects_for_lines(
	db: Session,
	business_id: int,
	lines: Sequence[WarehouseDocumentLine],
	*,
	forward: bool,
) -> None:
	"""forward=True هنگام پست حواله؛ forward=False هنگام لغو حوالهٔ اصلی (برگرداندن قرارگیری)."""
	for ln in lines:
		lid = getattr(ln, "warehouse_location_id", None)
		if lid is None:
			continue
		if not ln.warehouse_id:
			continue
		qty = Decimal(str(ln.quantity or 0))
		if qty <= 0:
			continue

		product = db.query(Product).filter(Product.id == int(ln.product_id)).first()
		if not product or not getattr(product, "track_inventory", False):
			continue

		validate_warehouse_location_for_line(db, business_id, int(ln.warehouse_id), int(lid))

		delta = _placement_delta_for_movement(str(ln.movement or ""), qty, forward)
		_upsert_placement_delta(
			db,
			business_id=business_id,
			warehouse_id=int(ln.warehouse_id),
			location_id=int(lid),
			product_id=int(ln.product_id),
			delta=delta,
		)


def should_skip_placement_sync_for_document(wh: WarehouseDocument) -> bool:
	ex = wh.extra_info or {}
	if isinstance(ex, dict) and ex.get("cancels_warehouse_document_id"):
		return True
	return False


def apply_placement_effects_for_posted_document(
	db: Session,
	business_id: int,
	wh: WarehouseDocument,
	lines: List[WarehouseDocumentLine],
) -> None:
	if should_skip_placement_sync_for_document(wh):
		return
	apply_placement_effects_for_lines(db, business_id, lines, forward=True)


def reverse_placement_effects_for_cancelled_document(
	db: Session,
	business_id: int,
	lines: List[WarehouseDocumentLine],
) -> None:
	apply_placement_effects_for_lines(db, business_id, lines, forward=False)


def placement_reconciliation_for_warehouse(
	db: Session,
	business_id: int,
	warehouse_id: int,
	as_of_date=None,
) -> dict:
	"""مجموع قرارگیری‌ها در مقابل موجودی حسابداری به ازای هر کالا در یک انبار."""
	from datetime import date as date_type
	from app.services.invoice_service import _compute_available_stock

	if as_of_date is None:
		as_of_date = datetime.utcnow().date()
	elif isinstance(as_of_date, str):
		as_of_date = date_type.fromisoformat(as_of_date)

	products_with_placement = (
		db.query(WarehouseProductPlacement.product_id)
		.filter(
			and_(
				WarehouseProductPlacement.business_id == business_id,
				WarehouseProductPlacement.warehouse_id == warehouse_id,
			)
		)
		.distinct()
		.all()
	)
	product_ids = sorted({int(r[0]) for r in products_with_placement})

	items = []
	for pid in product_ids:
		accounting = _compute_available_stock(db, business_id, pid, warehouse_id, as_of_date)
		rows = (
			db.query(WarehouseProductPlacement)
			.filter(
				and_(
					WarehouseProductPlacement.business_id == business_id,
					WarehouseProductPlacement.warehouse_id == warehouse_id,
					WarehouseProductPlacement.product_id == pid,
				)
			)
			.all()
		)
		placed_sum = sum(Decimal(str(r.quantity or 0)) for r in rows)
		diff = placed_sum - accounting
		if placed_sum > 0 or accounting != 0:
			p = db.query(Product).filter(Product.id == pid).first()
			items.append(
				{
					"product_id": pid,
					"product_code": p.code if p else "",
					"product_name": p.name if p else "",
					"accounting_quantity": float(accounting),
					"placed_quantity_sum": float(placed_sum),
					"difference": float(diff),
				}
			)

	items.sort(key=lambda x: abs(x["difference"]), reverse=True)
	return {
		"warehouse_id": warehouse_id,
		"as_of_date": as_of_date.isoformat(),
		"items": items,
		"mismatch_count": len([i for i in items if abs(i["difference"]) > 1e-9]),
	}
