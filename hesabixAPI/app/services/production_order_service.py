from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.product_bom import ProductBOM
from adapters.db.models.production_order import (
	ProductionOrder,
	ProductionOrderMaterial,
	ProductionOrderOperation,
	ProductionOrderOutput,
)
from adapters.db.models.warehouse import Warehouse
from app.core.responses import ApiError


ACTIVE_RESERVATION_STATUSES = ("released", "in_progress")
ALLOWED_STATUSES = ("draft", "released", "in_progress", "completed", "cancelled")
MONEY_QUANT = Decimal("0.01")
UNIT_COST_QUANT = Decimal("0.000001")


def _as_decimal(value: Any) -> Decimal:
	return Decimal(str(value or 0))


def _money(value: Decimal) -> Decimal:
	return _as_decimal(value).quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)


def _unit_cost(value: Decimal) -> Decimal:
	return _as_decimal(value).quantize(UNIT_COST_QUANT, rounding=ROUND_HALF_UP)


def _validate_warehouse(db: Session, business_id: int, warehouse_id: int, label: str) -> Warehouse:
	warehouse = db.query(Warehouse).filter(
		Warehouse.id == int(warehouse_id), Warehouse.business_id == int(business_id)
	).first()
	if not warehouse:
		raise ApiError("WAREHOUSE_NOT_FOUND", f"{label} انتخاب‌شده در این کسب‌وکار وجود ندارد", http_status=404)
	return warehouse


def _get_order(db: Session, business_id: int, order_id: int, *, for_update: bool = False) -> ProductionOrder:
	query = db.query(ProductionOrder).filter(
		ProductionOrder.id == int(order_id), ProductionOrder.business_id == int(business_id)
	)
	if for_update:
		query = query.with_for_update()
	order = query.first()
	if not order:
		raise ApiError("PRODUCTION_ORDER_NOT_FOUND", "سفارش تولید یافت نشد", http_status=404)
	return order


def _active_reserved_quantity(
	db: Session,
	business_id: int,
	product_id: int,
	warehouse_id: int,
	*,
	exclude_order_id: Optional[int] = None,
) -> Decimal:
	query = db.query(func.coalesce(func.sum(ProductionOrderMaterial.reserved_quantity), 0)).join(
		ProductionOrder, ProductionOrder.id == ProductionOrderMaterial.production_order_id
	).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrder.status.in_(ACTIVE_RESERVATION_STATUSES),
		ProductionOrderMaterial.product_id == int(product_id),
		ProductionOrderMaterial.warehouse_id == int(warehouse_id),
	)
	if exclude_order_id is not None:
		query = query.filter(ProductionOrder.id != int(exclude_order_id))
	return _as_decimal(query.scalar())


def _standard_unit_cost_for_product(db: Session, business_id: int, product_id: int, as_of: date) -> Decimal:
	product = db.query(Product).filter(Product.id == int(product_id), Product.business_id == int(business_id)).first()
	if not product:
		return Decimal("0")
	try:
		from app.services.invoice_service import _calculate_average_purchase_cost
		avg = _calculate_average_purchase_cost(db, business_id, int(product_id), as_of)
		if avg and avg > 0:
			return _unit_cost(avg)
	except Exception:
		pass
	return _unit_cost(_as_decimal(getattr(product, "base_purchase_price", 0)))


def _apply_explosion_snapshot(
	db: Session,
	business_id: int,
	order: ProductionOrder,
	explosion: Dict[str, Any],
	*,
	default_warehouse_id: int,
	as_of: date,
) -> None:
	db.query(ProductionOrderMaterial).filter(ProductionOrderMaterial.production_order_id == order.id).delete(synchronize_session=False)
	db.query(ProductionOrderOutput).filter(ProductionOrderOutput.production_order_id == order.id).delete(synchronize_session=False)
	db.query(ProductionOrderOperation).filter(ProductionOrderOperation.production_order_id == order.id).delete(synchronize_session=False)

	materials_total = Decimal("0")
	material_line = 0
	for item in explosion.get("items", []):
		qty = _as_decimal(item.get("inventory_required_qty", item.get("required_qty_main_unit", item.get("required_qty"))))
		if qty <= 0:
			continue
		material_line += 1
		warehouse_id = int(item.get("suggested_warehouse_id") or default_warehouse_id)
		_validate_warehouse(db, business_id, warehouse_id, "انبار پیشنهادی ماده")
		unit = _standard_unit_cost_for_product(db, business_id, int(item["component_product_id"]), as_of)
		total = _money(unit * qty)
		materials_total += total
		db.add(ProductionOrderMaterial(
			production_order_id=order.id,
			line_no=material_line,
			product_id=int(item["component_product_id"]),
			warehouse_id=warehouse_id,
			planned_quantity=qty,
			standard_unit_cost=unit,
			standard_total_cost=total,
			uom=item.get("main_unit") or item.get("uom"),
			bom_path=item.get("bom_path"),
			is_optional=bool(item.get("is_optional", False)),
			source_bom_id=item.get("source_bom_id"),
		))

	ops_total = Decimal("0")
	for line_no, op in enumerate(explosion.get("operations", []), start=1):
		fixed = _money(_as_decimal(op.get("cost_fixed")))
		per_unit = _unit_cost(_as_decimal(op.get("cost_per_unit")))
		total = _money(_as_decimal(op.get("total_cost")) if op.get("total_cost") is not None else fixed + per_unit * _as_decimal(order.planned_quantity))
		ops_total += total
		db.add(ProductionOrderOperation(
			production_order_id=order.id,
			line_no=line_no,
			operation_name=str(op.get("operation_name") or f"عملیات {line_no}"),
			work_center=op.get("work_center"),
			cost_uom=op.get("cost_uom"),
			standard_cost_fixed=fixed,
			standard_cost_per_unit=per_unit,
			standard_total_cost=total,
			source_bom_id=op.get("source_bom_id") or order.bom_id,
		))

	standard_total = materials_total + ops_total
	output_rows: List[Dict[str, Any]] = []
	output_allocation_weights: List[Decimal] = []
	for output in explosion.get("outputs", []):
		qty = _as_decimal(output.get("inventory_ratio", output.get("ratio_main_unit", output.get("ratio"))))
		if qty <= 0:
			continue
		output_rows.append(output)
		output_product = db.query(Product).filter(
			Product.id == int(output["output_product_id"]),
			Product.business_id == int(business_id),
		).first()
		output_allocation_weights.append(qty * _as_decimal(getattr(output_product, "base_sales_price", 0)))

	allocated = Decimal("0")
	total_nrv = sum(output_allocation_weights, Decimal("0"))
	for idx, output in enumerate(output_rows, start=1):
		qty = _as_decimal(output.get("inventory_ratio", output.get("ratio_main_unit", output.get("ratio"))))
		if idx == len(output_rows):
			line_total = _money(standard_total - allocated)
		elif total_nrv > 0:
			line_total = _money(standard_total * (output_allocation_weights[idx - 1] / total_nrv))
			allocated += line_total
		else:
			# Without a configured sales value, allocate equally per output line;
			# physical quantity is not a defensible proxy for co-product value.
			line_total = _money(standard_total / Decimal(len(output_rows)))
			allocated += line_total
		unit = _unit_cost(line_total / qty) if qty > 0 else Decimal("0")
		db.add(ProductionOrderOutput(
			production_order_id=order.id,
			line_no=idx,
			product_id=int(output["output_product_id"]),
			planned_quantity=qty,
			standard_unit_cost=unit,
			standard_total_cost=line_total,
			uom=output.get("main_unit") or output.get("uom"),
		))

	if material_line == 0:
		raise ApiError("BOM_MATERIAL_REQUIRED", "فرمول برای سفارش تولید باید حداقل یک مادهٔ مصرفی داشته باشد", http_status=409)
	if not output_rows:
		raise ApiError("BOM_OUTPUT_REQUIRED", "فرمول تأییدشده باید حداقل یک محصول خروجی داشته باشد", http_status=409)

	order.standard_materials_cost = _money(materials_total)
	order.standard_operations_cost = _money(ops_total)
	db.flush()


def _linked_production_invoices(db: Session, business_id: int, order_id: int) -> List[Document]:
	from app.services.invoice_service import INVOICE_PRODUCTION

	docs = db.query(Document).filter(
		Document.business_id == int(business_id),
		Document.document_type == INVOICE_PRODUCTION,
		Document.is_proforma.is_(False),
	).all()
	linked: List[Document] = []
	for doc in docs:
		extra = doc.extra_info or {}
		try:
			if int(extra.get("production_order_id")) == int(order_id):
				linked.append(doc)
		except (TypeError, ValueError):
			continue
	return linked


def refresh_production_order_actual_costs(db: Session, business_id: int, order_id: int) -> Dict[str, Any]:
	"""Roll up actual material/ops/finished costs from linked production invoices onto the order."""
	order = _get_order(db, business_id, order_id, for_update=True)
	materials = db.query(ProductionOrderMaterial).filter(
		ProductionOrderMaterial.production_order_id == order.id
	).order_by(ProductionOrderMaterial.line_no).with_for_update().all()
	outputs = db.query(ProductionOrderOutput).filter(
		ProductionOrderOutput.production_order_id == order.id
	).order_by(ProductionOrderOutput.line_no).with_for_update().all()
	operations = db.query(ProductionOrderOperation).filter(
		ProductionOrderOperation.production_order_id == order.id
	).order_by(ProductionOrderOperation.line_no).with_for_update().all()

	material_actual: Dict[int, Decimal] = {int(m.id): Decimal("0") for m in materials}
	output_actual: Dict[int, Decimal] = {int(o.id): Decimal("0") for o in outputs}
	material_actual_quantity: Dict[int, Decimal] = {int(m.id): Decimal("0") for m in materials}
	output_actual_quantity: Dict[int, Decimal] = {int(o.id): Decimal("0") for o in outputs}
	ops_actual = Decimal("0")

	for doc in _linked_production_invoices(db, business_id, order.id):
		extra = doc.extra_info or {}
		try:
			ops_actual += _as_decimal(extra.get("production_operations_total"))
		except Exception:
			pass
		for line in db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == doc.id).all():
			info = line.extra_info or {}
			movement = info.get("movement")
			qty = _as_decimal(line.quantity)
			if qty <= 0:
				continue
			amount = Decimal("0")
			if info.get("cogs_amount") is not None:
				amount = _as_decimal(info.get("cogs_amount"))
			elif info.get("cost_price") is not None:
				amount = _as_decimal(info.get("cost_price")) * qty
			elif line.unit_price is not None and movement == "in":
				amount = _as_decimal(line.unit_price) * qty
			pid = int(line.product_id)
			if movement not in ("out", "in"):
				continue
			rows = materials if movement == "out" else outputs
			costs = material_actual if movement == "out" else output_actual
			allocated_quantities = material_actual_quantity if movement == "out" else output_actual_quantity
			warehouse_id = info.get("warehouse_id")
			try:
				warehouse_id = int(warehouse_id) if warehouse_id is not None else None
			except (TypeError, ValueError):
				warehouse_id = None
			line_id_key = "production_order_material_id" if movement == "out" else "production_order_output_id"
			row_id = info.get(line_id_key)
			candidates = [row for row in rows if int(row.product_id) == pid]
			if movement == "out" and warehouse_id is not None:
				warehouse_matches = [row for row in candidates if int(row.warehouse_id) == warehouse_id]
				if warehouse_matches:
					candidates = warehouse_matches
			if row_id is not None:
				try:
					candidates = [row for row in candidates if int(row.id) == int(row_id)]
				except (TypeError, ValueError):
					candidates = []
			if not candidates:
				raise ApiError(
					"PRODUCTION_COST_ROW_NOT_FOUND",
					f"ردیف فاکتور تولید برای کالای #{pid} به ردیف معتبر سفارش متصل نیست",
					http_status=409,
				)
			# Keep duplicate BOM lines distinct. Aggregate lines are distributed by
			# quantity across matching rows, with the final row absorbing rounding.
			remaining_qty = qty
			remaining_amount = amount
			for row in candidates:
				if remaining_qty <= 0:
					break
				row_capacity = max(
					_as_decimal(row.planned_quantity) - allocated_quantities[int(row.id)],
					Decimal("0"),
				)
				row_qty = min(remaining_qty, row_capacity)
				if row_qty <= 0:
					continue
				if row_qty == remaining_qty:
					share = remaining_amount
				else:
					share = _money(remaining_amount * row_qty / remaining_qty)
				costs[int(row.id)] += share
				allocated_quantities[int(row.id)] += row_qty
				remaining_qty -= row_qty
				remaining_amount -= share
			if remaining_qty > 0:
				raise ApiError(
					"PRODUCTION_COST_ALLOCATION_FAILED",
					f"مقدار فاکتور تولید برای کالای #{pid} به ردیف‌های برنامه‌ریزی‌شدهٔ سفارش تخصیص‌پذیر نیست",
					http_status=409,
					details={"product_id": pid, "movement": movement, "unallocated_quantity": float(remaining_qty)},
				)

	for material in materials:
		material.actual_total_cost = _money(material_actual.get(int(material.id), Decimal("0")))
	for output in outputs:
		output.actual_total_cost = _money(output_actual.get(int(output.id), Decimal("0")))

	# Allocate actual ops across operation lines by standard weight; leftover to last line.
	std_ops = sum((_as_decimal(op.standard_total_cost) for op in operations), Decimal("0"))
	allocated_ops = Decimal("0")
	for idx, op in enumerate(operations):
		if std_ops > 0 and idx < len(operations) - 1:
			share = _money(ops_actual * (_as_decimal(op.standard_total_cost) / std_ops))
			allocated_ops += share
			op.actual_total_cost = share
		elif idx == len(operations) - 1:
			op.actual_total_cost = _money(ops_actual - allocated_ops)
		else:
			op.actual_total_cost = Decimal("0")

	order.actual_materials_cost = _money(sum((_as_decimal(m.actual_total_cost) for m in materials), Decimal("0")))
	order.actual_operations_cost = _money(ops_actual)
	order.actual_finished_cost = _money(sum((_as_decimal(o.actual_total_cost) for o in outputs), Decimal("0")))
	order.version += 1
	db.flush()
	return get_production_order_costing(db, business_id, order.id)


def get_production_order_costing(db: Session, business_id: int, order_id: int) -> Dict[str, Any]:
	order = _get_order(db, business_id, order_id)
	materials = db.query(ProductionOrderMaterial).filter(
		ProductionOrderMaterial.production_order_id == order.id
	).order_by(ProductionOrderMaterial.line_no).all()
	outputs = db.query(ProductionOrderOutput).filter(
		ProductionOrderOutput.production_order_id == order.id
	).order_by(ProductionOrderOutput.line_no).all()
	operations = db.query(ProductionOrderOperation).filter(
		ProductionOrderOperation.production_order_id == order.id
	).order_by(ProductionOrderOperation.line_no).all()

	std_mat = _as_decimal(order.standard_materials_cost)
	std_ops = _as_decimal(order.standard_operations_cost)
	act_mat = _as_decimal(order.actual_materials_cost)
	act_ops = _as_decimal(order.actual_operations_cost)
	act_fin = _as_decimal(order.actual_finished_cost)
	std_total = std_mat + std_ops
	act_total = act_mat + act_ops

	qty_var_materials = [
		{
			"product_id": m.product_id,
			"planned_quantity": m.planned_quantity,
			"issued_quantity": m.issued_quantity,
			"quantity_variance": _as_decimal(m.issued_quantity) - _as_decimal(m.planned_quantity),
			"standard_total_cost": m.standard_total_cost,
			"actual_total_cost": m.actual_total_cost,
			"cost_variance": _as_decimal(m.actual_total_cost) - _as_decimal(m.standard_total_cost),
			"lot_code": m.lot_code,
		}
		for m in materials
	]
	return {
		"production_order_id": order.id,
		"code": order.code,
		"status": order.status,
		"costing_frozen_at": order.costing_frozen_at,
		"standard": {
			"materials_cost": std_mat,
			"operations_cost": std_ops,
			"total_cost": std_total,
		},
		"actual": {
			"materials_cost": act_mat,
			"operations_cost": act_ops,
			"finished_cost": act_fin,
			"total_cost": act_total,
		},
		"variance": {
			"materials_cost": act_mat - std_mat,
			"operations_cost": act_ops - std_ops,
			"total_cost": act_total - std_total,
			"yield_quantity": _as_decimal(order.produced_quantity) - _as_decimal(order.planned_quantity),
		},
		"materials": qty_var_materials,
		"operations": [
			{
				"id": op.id,
				"line_no": op.line_no,
				"operation_name": op.operation_name,
				"work_center": op.work_center,
				"standard_total_cost": op.standard_total_cost,
				"actual_total_cost": op.actual_total_cost,
				"cost_variance": _as_decimal(op.actual_total_cost) - _as_decimal(op.standard_total_cost),
			}
			for op in operations
		],
		"outputs": [
			{
				"id": o.id,
				"product_id": o.product_id,
				"planned_quantity": o.planned_quantity,
				"produced_quantity": o.produced_quantity,
				"scrap_quantity": o.scrap_quantity,
				"standard_unit_cost": o.standard_unit_cost,
				"standard_total_cost": o.standard_total_cost,
				"actual_total_cost": o.actual_total_cost,
				"cost_variance": _as_decimal(o.actual_total_cost) - _as_decimal(o.standard_total_cost),
				"lot_code": o.lot_code,
			}
			for o in outputs
		],
		"linked_invoice_count": len(_linked_production_invoices(db, business_id, order.id)),
	}


def update_production_order_lots(
	db: Session,
	business_id: int,
	order_id: int,
	*,
	expected_version: Optional[int] = None,
	material_lots: Optional[List[Dict[str, Any]]] = None,
	output_lots: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
	order = _get_order(db, business_id, order_id, for_update=True)
	if expected_version is not None and int(expected_version) != int(order.version):
		raise ApiError("PRODUCTION_ORDER_VERSION_CONFLICT", "سفارش هم‌زمان تغییر کرده است؛ اطلاعات را تازه‌سازی کنید", http_status=409)
	if order.status in ("completed", "cancelled"):
		raise ApiError("PRODUCTION_ORDER_LOTS_LOCKED", "برای سفارش بسته‌شده امکان ویرایش بچ/لات نیست", http_status=409)
	if material_lots:
		by_id = {int(m.id): m for m in order.materials}
		for row in material_lots:
			mid = int(row["id"])
			material = by_id.get(mid)
			if not material:
				raise ApiError("PRODUCTION_MATERIAL_NOT_FOUND", f"ماده #{mid} در سفارش نیست", http_status=404)
			code = row.get("lot_code")
			new_code = None if code in (None, "") else str(code).strip()[:64]
			if _as_decimal(material.issued_quantity) > 0 and new_code != material.lot_code:
				raise ApiError("PRODUCTION_MATERIAL_LOT_LOCKED", "پس از صدور ماده از انبار، کد لات آن قابل تغییر نیست", http_status=409)
			material.lot_code = new_code
	if output_lots:
		by_id = {int(o.id): o for o in order.outputs}
		for row in output_lots:
			oid = int(row["id"])
			output = by_id.get(oid)
			if not output:
				raise ApiError("PRODUCTION_OUTPUT_NOT_FOUND", f"خروجی #{oid} در سفارش نیست", http_status=404)
			code = row.get("lot_code")
			new_code = None if code in (None, "") else str(code).strip()[:64]
			if _as_decimal(output.produced_quantity) > 0 and new_code != output.lot_code:
				raise ApiError("PRODUCTION_OUTPUT_LOT_LOCKED", "پس از ثبت ورود محصول، کد لات آن قابل تغییر نیست", http_status=409)
			output.lot_code = new_code
			if row.get("scrap_quantity") is not None:
				scrap = _as_decimal(row.get("scrap_quantity"))
				if scrap < 0:
					raise ApiError("INVALID_SCRAP_QUANTITY", "ضایعات نمی‌تواند منفی باشد", http_status=400)
				output.scrap_quantity = scrap
	order.version += 1
	db.flush()
	return _order_dict(db, order)


def list_production_orders_by_lot(db: Session, business_id: int, lot_code: str) -> Dict[str, Any]:
	code = (lot_code or "").strip()
	if not code:
		raise ApiError("LOT_CODE_REQUIRED", "کد بچ/لات الزامی است", http_status=400)
	material_hits = db.query(ProductionOrderMaterial).join(
		ProductionOrder, ProductionOrder.id == ProductionOrderMaterial.production_order_id
	).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrderMaterial.lot_code == code,
	).all()
	output_hits = db.query(ProductionOrderOutput).join(
		ProductionOrder, ProductionOrder.id == ProductionOrderOutput.production_order_id
	).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrderOutput.lot_code == code,
	).all()
	order_ids = {int(m.production_order_id) for m in material_hits} | {int(o.production_order_id) for o in output_hits}
	orders = []
	if order_ids:
		rows = db.query(ProductionOrder).filter(
			ProductionOrder.business_id == int(business_id),
			ProductionOrder.id.in_(order_ids),
		).order_by(ProductionOrder.id.desc()).all()
		orders = [_order_dict(db, order) for order in rows]
	return {
		"lot_code": code,
		"orders": orders,
		"material_matches": [
			{"production_order_id": m.production_order_id, "product_id": m.product_id, "role": "material"}
			for m in material_hits
		],
		"output_matches": [
			{"production_order_id": o.production_order_id, "product_id": o.product_id, "role": "output"}
			for o in output_hits
		],
	}


def suggested_operations_total_for_order(
	db: Session,
	business_id: int,
	order_id: int,
	production_quantity: Optional[Decimal] = None,
) -> Decimal:
	order = _get_order(db, business_id, order_id)
	remaining = _as_decimal(order.standard_operations_cost) - _as_decimal(order.actual_operations_cost)
	if production_quantity is not None:
		primary_planned = sum(
			(_as_decimal(output.planned_quantity) for output in order.outputs if int(output.product_id) == int(order.product_id)),
			Decimal("0"),
		)
		primary_produced = _as_decimal(order.produced_quantity)
		primary_remaining = max(primary_planned - primary_produced, Decimal("0"))
		if primary_remaining <= 0:
			return Decimal("0")
		share = min(max(_as_decimal(production_quantity) / primary_remaining, Decimal("0")), Decimal("1"))
		remaining = remaining * share
	return _money(max(remaining, Decimal("0")))


def _order_dict(db: Session, order: ProductionOrder) -> Dict[str, Any]:
	product = db.query(Product).filter(Product.id == order.product_id).first()
	materials = db.query(ProductionOrderMaterial).filter(
		ProductionOrderMaterial.production_order_id == order.id
	).order_by(ProductionOrderMaterial.line_no).all()
	outputs = db.query(ProductionOrderOutput).filter(
		ProductionOrderOutput.production_order_id == order.id
	).order_by(ProductionOrderOutput.line_no).all()
	operations = db.query(ProductionOrderOperation).filter(
		ProductionOrderOperation.production_order_id == order.id
	).order_by(ProductionOrderOperation.line_no).all()
	material_product_ids = {m.product_id for m in materials}
	output_product_ids = {o.product_id for o in outputs}
	products = {}
	if material_product_ids | output_product_ids:
		products = {
			int(p.id): {"name": p.name, "code": p.code, "main_unit": p.main_unit}
			for p in db.query(Product).filter(Product.id.in_(material_product_ids | output_product_ids)).all()
		}
	std_total = _as_decimal(order.standard_materials_cost) + _as_decimal(order.standard_operations_cost)
	act_total = _as_decimal(order.actual_materials_cost) + _as_decimal(order.actual_operations_cost)
	return {
		"id": order.id,
		"business_id": order.business_id,
		"code": order.code,
		"product_id": order.product_id,
		"product_name": product.name if product else None,
		"product_code": product.code if product else None,
		"bom_id": order.bom_id,
		"warehouse_id": order.warehouse_id,
		"output_warehouse_id": order.output_warehouse_id,
		"planned_quantity": order.planned_quantity,
		"produced_quantity": order.produced_quantity,
		"status": order.status,
		"priority": order.priority,
		"planned_start_date": order.planned_start_date,
		"due_date": order.due_date,
		"started_at": order.started_at,
		"completed_at": order.completed_at,
		"created_by_user_id": order.created_by_user_id,
		"version": order.version,
		"notes": order.notes,
		"close_reason": (order.extra_info or {}).get("close_reason"),
		"closed_short": bool((order.extra_info or {}).get("closed_short", False)),
		"shortfalls": (order.extra_info or {}).get("shortfalls", []),
		"created_at": order.created_at,
		"updated_at": order.updated_at,
		"costing_frozen_at": order.costing_frozen_at,
		"standard_materials_cost": order.standard_materials_cost,
		"standard_operations_cost": order.standard_operations_cost,
		"actual_materials_cost": order.actual_materials_cost,
		"actual_operations_cost": order.actual_operations_cost,
		"actual_finished_cost": order.actual_finished_cost,
		"standard_total_cost": std_total,
		"actual_total_cost": act_total,
		"total_cost_variance": act_total - std_total,
		"materials": [
			{
				"id": m.id,
				"line_no": m.line_no,
				"product_id": m.product_id,
				"product_name": products.get(m.product_id, {}).get("name"),
				"product_code": products.get(m.product_id, {}).get("code"),
				"uom": m.uom or products.get(m.product_id, {}).get("main_unit"),
				"warehouse_id": m.warehouse_id,
				"planned_quantity": m.planned_quantity,
				"reserved_quantity": m.reserved_quantity,
				"issued_quantity": m.issued_quantity,
				"standard_unit_cost": m.standard_unit_cost,
				"standard_total_cost": m.standard_total_cost,
				"actual_total_cost": m.actual_total_cost,
				"lot_code": m.lot_code,
				"bom_path": m.bom_path,
				"is_optional": m.is_optional,
				"source_bom_id": m.source_bom_id,
			}
			for m in materials
		],
		"outputs": [
			{
				"id": o.id,
				"line_no": o.line_no,
				"product_id": o.product_id,
				"product_name": products.get(o.product_id, {}).get("name"),
				"product_code": products.get(o.product_id, {}).get("code"),
				"uom": o.uom or products.get(o.product_id, {}).get("main_unit"),
				"planned_quantity": o.planned_quantity,
				"produced_quantity": o.produced_quantity,
				"scrap_quantity": o.scrap_quantity,
				"standard_unit_cost": o.standard_unit_cost,
				"standard_total_cost": o.standard_total_cost,
				"actual_total_cost": o.actual_total_cost,
				"lot_code": o.lot_code,
			}
			for o in outputs
		],
		"operations": [
			{
				"id": op.id,
				"line_no": op.line_no,
				"operation_name": op.operation_name,
				"work_center": op.work_center,
				"cost_uom": op.cost_uom,
				"standard_cost_fixed": op.standard_cost_fixed,
				"standard_cost_per_unit": op.standard_cost_per_unit,
				"standard_total_cost": op.standard_total_cost,
				"actual_total_cost": op.actual_total_cost,
				"source_bom_id": op.source_bom_id,
			}
			for op in operations
		],
	}


def create_production_order(
	db: Session,
	business_id: int,
	user_id: Optional[int],
	payload: Any,
) -> Dict[str, Any]:
	product = db.query(Product).filter(
		Product.id == payload.product_id, Product.business_id == int(business_id)
	).first()
	if not product:
		raise ApiError("PRODUCT_NOT_FOUND", "محصول تولیدی یافت نشد", http_status=404)
	bom = db.query(ProductBOM).filter(
		ProductBOM.id == payload.bom_id,
		ProductBOM.business_id == int(business_id),
		ProductBOM.product_id == int(payload.product_id),
	).first()
	if not bom:
		raise ApiError("BOM_NOT_FOUND", "فرمول تولید برای این محصول یافت نشد", http_status=404)
	if (bom.status or "").strip().lower() != "approved":
		raise ApiError("BOM_NOT_APPROVED", "برای ایجاد سفارش تولید، نسخهٔ تأییدشدهٔ BOM لازم است", http_status=409)
	as_of = payload.planned_start_date or date.today()
	if bom.effective_from and as_of < bom.effective_from:
		raise ApiError("BOM_NOT_EFFECTIVE", "تاریخ شروع سفارش پیش از تاریخ اثر فرمول است", http_status=409)
	if bom.effective_to and as_of > bom.effective_to:
		raise ApiError("BOM_EXPIRED", "فرمول در تاریخ شروع برنامه‌ریزی‌شده معتبر نیست", http_status=409)
	if payload.due_date and payload.planned_start_date and payload.due_date < payload.planned_start_date:
		raise ApiError("INVALID_PRODUCTION_DATES", "موعد سفارش نمی‌تواند قبل از تاریخ برنامه‌ریزی‌شدهٔ شروع باشد", http_status=400)
	if not payload.quantity or payload.quantity <= 0:
		raise ApiError("INVALID_PRODUCTION_QUANTITY", "مقدار تولید باید بزرگ‌تر از صفر باشد", http_status=400)
	_validate_warehouse(db, business_id, payload.warehouse_id, "انبار مصرف مواد")
	_validate_warehouse(db, business_id, payload.output_warehouse_id, "انبار محصول")

	from adapters.api.v1.schema_models.product_bom import BOMExplosionRequest
	from app.services.bom_service import explode_bom
	explosion = explode_bom(
		db,
		business_id,
		BOMExplosionRequest(bom_id=payload.bom_id, quantity=payload.quantity, date=as_of.isoformat(), recursive=True),
	)
	if not any(int(row.get("output_product_id", 0)) == int(payload.product_id) for row in explosion.get("outputs", [])):
		raise ApiError(
			"BOM_PRIMARY_OUTPUT_REQUIRED",
			"محصول اصلی سفارش باید یکی از خروجی‌های فرمول تأییدشده باشد",
			http_status=409,
		)

	from app.core.transaction_lock import acquire_transaction_lock
	acquire_transaction_lock(db, f"production_order_code:{business_id}")
	order = ProductionOrder(
		business_id=int(business_id),
		code="PENDING",
		product_id=int(payload.product_id),
		bom_id=int(payload.bom_id),
		warehouse_id=int(payload.warehouse_id),
		output_warehouse_id=int(payload.output_warehouse_id),
		planned_quantity=payload.quantity,
		status="draft",
		priority=int(payload.priority),
		planned_start_date=payload.planned_start_date,
		due_date=payload.due_date,
		created_by_user_id=int(user_id) if user_id else None,
		notes=payload.notes,
		extra_info={"bom_version": bom.version, "bom_name": bom.name, "bom_effective_date": as_of.isoformat()},
	)
	db.add(order)
	db.flush()
	order.code = f"MO-{as_of:%Y%m%d}-{order.id:08d}"
	_apply_explosion_snapshot(
		db,
		business_id,
		order,
		explosion,
		default_warehouse_id=int(payload.warehouse_id),
		as_of=as_of,
	)
	return _order_dict(db, order)


def list_production_orders(
	db: Session,
	business_id: int,
	*,
	status: Optional[str] = None,
	product_id: Optional[int] = None,
	due_from: Optional[date] = None,
	due_to: Optional[date] = None,
	skip: int = 0,
	take: int = 50,
) -> Dict[str, Any]:
	query = db.query(ProductionOrder).filter(ProductionOrder.business_id == int(business_id))
	if status:
		if status not in ALLOWED_STATUSES:
			raise ApiError("INVALID_PRODUCTION_ORDER_STATUS", "وضعیت سفارش تولید معتبر نیست", http_status=400)
		query = query.filter(ProductionOrder.status == status)
	if product_id:
		query = query.filter(ProductionOrder.product_id == int(product_id))
	if due_from:
		query = query.filter(ProductionOrder.due_date >= due_from)
	if due_to:
		query = query.filter(ProductionOrder.due_date <= due_to)
	total = query.count()
	orders = query.order_by(ProductionOrder.priority.asc(), ProductionOrder.due_date.asc().nullslast(), ProductionOrder.id.desc()).offset(skip).limit(take).all()
	return {"items": [_order_dict(db, order) for order in orders], "total": total, "skip": skip, "take": take}


def get_production_material_plan(
	db: Session,
	business_id: int,
	*,
	due_from: Optional[date] = None,
	due_to: Optional[date] = None,
) -> Dict[str, Any]:
	"""Summarize outstanding material demand for active orders without creating documents."""
	query = db.query(ProductionOrderMaterial, ProductionOrder).join(
		ProductionOrder, ProductionOrder.id == ProductionOrderMaterial.production_order_id
	).filter(
		ProductionOrder.business_id == int(business_id),
		ProductionOrder.status.in_(ACTIVE_RESERVATION_STATUSES),
		ProductionOrderMaterial.is_optional.is_(False),
	)
	if due_from is not None:
		query = query.filter((ProductionOrder.due_date.is_(None)) | (ProductionOrder.due_date >= due_from))
	if due_to is not None:
		query = query.filter((ProductionOrder.due_date.is_(None)) | (ProductionOrder.due_date <= due_to))

	groups: Dict[tuple[int, int], Dict[str, Any]] = {}
	for material, order in query.order_by(ProductionOrder.due_date.asc().nullslast(), ProductionOrder.id).all():
		key = (int(material.product_id), int(material.warehouse_id))
		row = groups.setdefault(key, {
			"product_id": key[0],
			"warehouse_id": key[1],
			"required_quantity": Decimal("0"),
			"reserved_quantity": Decimal("0"),
			"order_ids": set(),
			"earliest_due_date": None,
		})
		remaining = max(
			_as_decimal(material.planned_quantity) - _as_decimal(material.issued_quantity),
			Decimal("0"),
		)
		row["required_quantity"] += remaining
		row["reserved_quantity"] += min(_as_decimal(material.reserved_quantity), remaining)
		row["order_ids"].add(int(order.id))
		if order.due_date is not None and (
			row["earliest_due_date"] is None or order.due_date < row["earliest_due_date"]
		):
			row["earliest_due_date"] = order.due_date

	from app.services.invoice_service import _compute_available_stock

	items = []
	for (product_id, warehouse_id), row in groups.items():
		product = db.query(Product).filter(
			Product.id == product_id,
			Product.business_id == int(business_id),
		).first()
		warehouse = db.query(Warehouse).filter(
			Warehouse.id == warehouse_id,
			Warehouse.business_id == int(business_id),
		).first()
		if not product or not warehouse:
			continue
		physical = _as_decimal(_compute_available_stock(
			db, int(business_id), product_id, warehouse_id, date.today()
		))
		required = row["required_quantity"]
		active_reserved = _active_reserved_quantity(db, business_id, product_id, warehouse_id)
		free = max(physical - active_reserved, Decimal("0"))
		unreserved_demand = max(required - row["reserved_quantity"], Decimal("0"))
		shortage = max(unreserved_demand - free, Decimal("0"))
		planning_date = row["earliest_due_date"] or date.today()
		make_bom = db.query(ProductBOM.id).filter(
			ProductBOM.business_id == int(business_id),
			ProductBOM.product_id == product_id,
			ProductBOM.status == "approved",
			(ProductBOM.effective_from.is_(None)) | (ProductBOM.effective_from <= planning_date),
			(ProductBOM.effective_to.is_(None)) | (ProductBOM.effective_to >= planning_date),
		).first()
		items.append({
			"product_id": product_id,
			"product_name": product.name,
			"product_code": product.code,
			"uom": product.main_unit,
			"warehouse_id": warehouse_id,
			"warehouse_name": warehouse.name,
			"required_quantity": float(required),
			"reserved_quantity": float(row["reserved_quantity"]),
			"total_active_reserved_quantity": float(active_reserved),
			"physical_available_quantity": float(physical),
			"free_quantity": float(free),
			"shortage_quantity": float(shortage),
			"suggested_action": "manufacture" if shortage > 0 and make_bom else "purchase" if shortage > 0 else "none",
			"earliest_due_date": row["earliest_due_date"].isoformat() if row["earliest_due_date"] else None,
			"production_order_count": len(row["order_ids"]),
			"production_order_ids": sorted(row["order_ids"]),
		})
	items.sort(key=lambda item: (
		item["earliest_due_date"] or "9999-12-31",
		item["product_name"].casefold(),
		item["warehouse_id"],
	))
	return {
		"business_id": int(business_id),
		"as_of_date": date.today().isoformat(),
		"due_from": due_from.isoformat() if due_from else None,
		"due_to": due_to.isoformat() if due_to else None,
		"items": items,
	}


def get_production_order(db: Session, business_id: int, order_id: int) -> Dict[str, Any]:
	return _order_dict(db, _get_order(db, business_id, order_id))


def update_production_order(db: Session, business_id: int, order_id: int, payload: Any) -> Dict[str, Any]:
	order = _get_order(db, business_id, order_id, for_update=True)
	if order.status != "draft":
		raise ApiError("PRODUCTION_ORDER_NOT_EDITABLE", "فقط سفارش تولید پیش‌نویس قابل ویرایش است", http_status=409)
	values = payload.model_dump(exclude_unset=True)
	if int(values.get("version", -1)) != int(order.version):
		raise ApiError("PRODUCTION_ORDER_VERSION_CONFLICT", "سفارش هم‌زمان تغییر کرده است؛ اطلاعات را تازه‌سازی کنید", http_status=409)
	new_start = values.get("planned_start_date", order.planned_start_date)
	new_due = values.get("due_date", order.due_date)
	if new_due and new_start and new_due < new_start:
		raise ApiError("INVALID_PRODUCTION_DATES", "موعد سفارش نمی‌تواند قبل از تاریخ شروع باشد", http_status=400)
	needs_snapshot = any(name in values for name in ("quantity", "planned_start_date", "warehouse_id"))
	if needs_snapshot:
		bom = db.query(ProductBOM).filter(
			ProductBOM.id == int(order.bom_id),
			ProductBOM.business_id == int(business_id),
			ProductBOM.product_id == int(order.product_id),
		).first()
		if not bom or (bom.status or "").strip().lower() != "approved":
			raise ApiError("BOM_NOT_APPROVED", "نسخهٔ تأییدشدهٔ فرمول سفارش دیگر در دسترس نیست", http_status=409)
		as_of = new_start or date.today()
		if bom.effective_from and as_of < bom.effective_from:
			raise ApiError("BOM_NOT_EFFECTIVE", "تاریخ شروع سفارش پیش از تاریخ اثر فرمول است", http_status=409)
		if bom.effective_to and as_of > bom.effective_to:
			raise ApiError("BOM_EXPIRED", "فرمول در تاریخ شروع سفارش معتبر نیست", http_status=409)
	for name in ("warehouse_id", "output_warehouse_id"):
		if name in values and values[name] is not None:
			_validate_warehouse(db, business_id, values[name], name)
	for name in ("planned_start_date", "due_date", "priority", "notes", "warehouse_id", "output_warehouse_id"):
		if name in values:
			setattr(order, name, values[name])
	if needs_snapshot:
		if "quantity" in values and values["quantity"] is not None:
			if values["quantity"] <= 0:
				raise ApiError("INVALID_PRODUCTION_QUANTITY", "مقدار تولید باید بزرگ‌تر از صفر باشد", http_status=400)
			order.planned_quantity = values["quantity"]
		from adapters.api.v1.schema_models.product_bom import BOMExplosionRequest
		from app.services.bom_service import explode_bom
		as_of = new_start or date.today()
		explosion = explode_bom(
			db,
			business_id,
			BOMExplosionRequest(
				bom_id=order.bom_id,
				quantity=order.planned_quantity,
				date=as_of.isoformat(),
				recursive=True,
			),
		)
		_apply_explosion_snapshot(
			db,
			business_id,
			order,
			explosion,
			default_warehouse_id=int(order.warehouse_id),
			as_of=as_of,
		)
	order.version += 1
	db.flush()
	return _order_dict(db, order)


def release_production_order(db: Session, business_id: int, order_id: int, expected_version: int) -> Dict[str, Any]:
	order = _get_order(db, business_id, order_id, for_update=True)
	if expected_version is not None and int(expected_version) != order.version:
		raise ApiError("PRODUCTION_ORDER_VERSION_CONFLICT", "سفارش هم‌زمان تغییر کرده است؛ اطلاعات را تازه‌سازی کنید", http_status=409)
	if order.status != "draft":
		raise ApiError("INVALID_PRODUCTION_ORDER_TRANSITION", "فقط سفارش پیش‌نویس قابل آزادسازی است", http_status=409)
	if not order.materials or not order.outputs:
		raise ApiError("PRODUCTION_ORDER_INCOMPLETE", "سفارش باید مواد و خروجی‌های معتبر داشته باشد", http_status=409)
	from app.core.transaction_lock import acquire_transaction_lock
	from app.services.invoice_service import _compute_available_stock

	keys = sorted({(m.product_id, m.warehouse_id) for m in order.materials if not m.is_optional})
	for product_id, warehouse_id in keys:
		acquire_transaction_lock(db, f"inventory_stock:{business_id}:{warehouse_id}:{product_id}")
	shortages = []
	tracked_requirements: Dict[tuple[int, int], Dict[str, Any]] = {}
	for material in order.materials:
		if material.is_optional:
			material.reserved_quantity = Decimal("0")
			continue
		product = db.query(Product).filter(Product.id == material.product_id, Product.business_id == business_id).first()
		if not product:
			raise ApiError("PRODUCTION_ORDER_PRODUCT_MISSING", "یکی از مواد سفارش دیگر در این کسب‌وکار وجود ندارد", http_status=409)
		if not product.track_inventory:
			material.reserved_quantity = Decimal("0")
			continue
		key = (int(material.product_id), int(material.warehouse_id))
		requirement = tracked_requirements.setdefault(key, {"quantity": Decimal("0"), "product": product})
		requirement["quantity"] += _as_decimal(material.planned_quantity)
	for (product_id, warehouse_id), requirement in tracked_requirements.items():
		physical = _compute_available_stock(db, business_id, product_id, warehouse_id, date.today())
		reserved = _active_reserved_quantity(db, business_id, product_id, warehouse_id, exclude_order_id=order.id)
		available = physical - reserved
		if available < requirement["quantity"]:
			shortages.append({
				"product_id": product_id,
				"product_name": requirement["product"].name,
				"warehouse_id": warehouse_id,
				"physical_quantity": float(physical),
				"reserved_quantity": float(reserved),
				"available_to_reserve": float(max(available, Decimal("0"))),
				"required_quantity": float(requirement["quantity"]),
				"shortage_quantity": float(requirement["quantity"] - max(available, Decimal("0"))),
			})
	if shortages:
		raise ApiError("PRODUCTION_MATERIAL_SHORTAGE", "موجودی آزاد برای رزرو کامل مواد سفارش کافی نیست", http_status=409, details={"shortages": shortages})
	for material in order.materials:
		if not material.is_optional and (int(material.product_id), int(material.warehouse_id)) in tracked_requirements:
			material.reserved_quantity = material.planned_quantity
	# Freeze standard costing at release so later purchase-price drift cannot rewrite the baseline.
	if order.costing_frozen_at is None:
		order.costing_frozen_at = datetime.now(timezone.utc)
	order.status = "released"
	order.version += 1
	db.flush()
	return _order_dict(db, order)


def start_production_order(db: Session, business_id: int, order_id: int, expected_version: int) -> Dict[str, Any]:
	order = _get_order(db, business_id, order_id, for_update=True)
	if expected_version is not None and int(expected_version) != order.version:
		raise ApiError("PRODUCTION_ORDER_VERSION_CONFLICT", "سفارش هم‌زمان تغییر کرده است؛ اطلاعات را تازه‌سازی کنید", http_status=409)
	if order.status != "released":
		raise ApiError("INVALID_PRODUCTION_ORDER_TRANSITION", "برای شروع، سفارش باید آزادسازی شده باشد", http_status=409)
	order.status = "in_progress"
	order.started_at = datetime.now(timezone.utc)
	order.version += 1
	db.flush()
	return _order_dict(db, order)


def complete_production_order(
	db: Session,
	business_id: int,
	order_id: int,
	expected_version: int,
	close_reason: Optional[str] = None,
) -> Dict[str, Any]:
	order = _get_order(db, business_id, order_id, for_update=True)
	if expected_version is not None and int(expected_version) != order.version:
		raise ApiError("PRODUCTION_ORDER_VERSION_CONFLICT", "سفارش هم‌زمان تغییر کرده است؛ اطلاعات را تازه‌سازی کنید", http_status=409)
	if order.status != "in_progress":
		raise ApiError("INVALID_PRODUCTION_ORDER_TRANSITION", "فقط سفارش در حال اجرا قابل تکمیل است", http_status=409)
	if _as_decimal(order.produced_quantity) <= 0:
		raise ApiError("PRODUCTION_OUTPUT_REQUIRED", "پیش از تکمیل سفارش باید محصول تولیدی ثبت شده باشد", http_status=409)
	shortfalls = [
		{
			"product_id": int(output.product_id),
			"planned_quantity": float(_as_decimal(output.planned_quantity)),
			"produced_quantity": float(_as_decimal(output.produced_quantity)),
			"short_quantity": float(max(_as_decimal(output.planned_quantity) - _as_decimal(output.produced_quantity), Decimal("0"))),
		}
		for output in order.outputs
		if _as_decimal(output.produced_quantity) < _as_decimal(output.planned_quantity)
	]
	if shortfalls and not (close_reason or "").strip():
		raise ApiError(
			"PRODUCTION_ORDER_SHORT_CLOSE_REQUIRES_REASON",
			"تولید کمتر از برنامه است؛ برای بستن ناقص باید علت ثبت شود",
			http_status=409,
			details={"shortfalls": shortfalls},
		)
	if close_reason and len(close_reason.strip()) > 2000:
		raise ApiError("INVALID_PRODUCTION_ORDER_CLOSE_REASON", "علت بستن سفارش حداکثر ۲۰۰۰ نویسه است", http_status=400)
	if close_reason:
		info = dict(order.extra_info or {})
		info["close_reason"] = close_reason.strip()
		info["closed_short"] = bool(shortfalls)
		if shortfalls:
			info["shortfalls"] = shortfalls
		order.extra_info = info
	refresh_production_order_actual_costs(db, business_id, order.id)
	order = _get_order(db, business_id, order_id, for_update=True)
	order.status = "completed"
	order.completed_at = datetime.now(timezone.utc)
	for material in order.materials:
		material.reserved_quantity = Decimal("0")
	order.version += 1
	db.flush()
	return _order_dict(db, order)


def cancel_production_order(db: Session, business_id: int, order_id: int, expected_version: int) -> Dict[str, Any]:
	order = _get_order(db, business_id, order_id, for_update=True)
	if expected_version is not None and int(expected_version) != order.version:
		raise ApiError("PRODUCTION_ORDER_VERSION_CONFLICT", "سفارش هم‌زمان تغییر کرده است؛ اطلاعات را تازه‌سازی کنید", http_status=409)
	if order.status not in ("draft", "released", "in_progress"):
		raise ApiError("INVALID_PRODUCTION_ORDER_TRANSITION", "این سفارش در وضعیت فعلی قابل لغو نیست", http_status=409)
	if _as_decimal(order.produced_quantity) > 0:
		raise ApiError("PRODUCTION_ORDER_HAS_OUTPUT", "سفارشی که تولید ثبت‌شده دارد قابل لغو نیست؛ ابتدا مقدار تولید را تعیین تکلیف کنید", http_status=409)
	issued_total = sum((_as_decimal(m.issued_quantity) for m in order.materials), Decimal("0"))
	if issued_total > 0:
		raise ApiError(
			"PRODUCTION_ORDER_HAS_ISSUED_MATERIALS",
			"سفارشی که مواد از انبار برای آن صادر شده قابل لغو نیست؛ ابتدا حواله‌های مصرف را ابطال کنید",
			http_status=409,
			details={"issued_quantity": float(issued_total)},
		)
	order.status = "cancelled"
	for material in order.materials:
		material.reserved_quantity = Decimal("0")
	order.version += 1
	db.flush()
	return _order_dict(db, order)
