from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from adapters.api.v1.schema_models.warehouse_location import ALLOWED_LOCATION_KINDS
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.warehouse_location import WarehouseLocation
from adapters.db.models.warehouse_product_placement import WarehouseProductPlacement
from app.core.responses import ApiError


def _normalize_kind(kind: Optional[str]) -> str:
	k = (kind or "zone").strip().lower()
	if k not in ALLOWED_LOCATION_KINDS:
		raise ApiError("VALIDATION_ERROR", f"نوع محل نامعتبر است: {kind}", http_status=400)
	return k


def _assert_warehouse(db: Session, business_id: int, warehouse_id: int) -> Warehouse:
	wh = (
		db.query(Warehouse)
		.filter(and_(Warehouse.id == warehouse_id, Warehouse.business_id == business_id))
		.first()
	)
	if not wh:
		raise ApiError("NOT_FOUND", "انبار یافت نشد", http_status=404)
	return wh


def _location_to_dict(loc: WarehouseLocation, path_codes: str) -> Dict[str, Any]:
	return {
		"id": loc.id,
		"business_id": loc.business_id,
		"warehouse_id": loc.warehouse_id,
		"parent_id": loc.parent_id,
		"code": loc.code,
		"name": loc.name,
		"location_kind": loc.location_kind,
		"sort_order": loc.sort_order,
		"is_active": loc.is_active,
		"notes": loc.notes,
		"path_codes": path_codes,
		"created_at": loc.created_at.isoformat() if loc.created_at else None,
		"updated_at": loc.updated_at.isoformat() if loc.updated_at else None,
	}


def _build_path_maps(rows: List[WarehouseLocation]) -> Dict[int, str]:
	by_id = {r.id: r for r in rows}
	paths: Dict[int, str] = {}

	def path_for(lid: int) -> str:
		if lid in paths:
			return paths[lid]
		loc = by_id.get(lid)
		if not loc:
			paths[lid] = ""
			return ""
		if loc.parent_id and loc.parent_id in by_id:
			base = path_for(loc.parent_id)
			paths[lid] = f"{base}/{loc.code}" if base else loc.code
		else:
			paths[lid] = loc.code
		return paths[lid]

	for r in rows:
		path_for(r.id)
	return paths


def list_locations_tree(db: Session, business_id: int, warehouse_id: int) -> Dict[str, Any]:
	_assert_warehouse(db, business_id, warehouse_id)
	rows = (
		db.query(WarehouseLocation)
		.filter(and_(WarehouseLocation.business_id == business_id, WarehouseLocation.warehouse_id == warehouse_id))
		.order_by(WarehouseLocation.sort_order.asc(), WarehouseLocation.code.asc())
		.all()
	)
	path_map = _build_path_maps(rows)

	id_to_node: Dict[int, Dict[str, Any]] = {}
	for loc in rows:
		d = _location_to_dict(loc, path_map.get(loc.id, loc.code))
		d["children"] = []
		id_to_node[loc.id] = d

	root_nodes: List[Dict[str, Any]] = []
	for loc in rows:
		node = id_to_node[loc.id]
		if loc.parent_id and loc.parent_id in id_to_node:
			id_to_node[loc.parent_id]["children"].append(node)
		else:
			root_nodes.append(node)

	flat = [_location_to_dict(loc, path_map.get(loc.id, loc.code)) for loc in rows]
	return {"tree": root_nodes, "flat": flat}


def create_location(
	db: Session,
	business_id: int,
	warehouse_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	_assert_warehouse(db, business_id, warehouse_id)
	name = (payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "نام محل الزامی است", http_status=400)

	parent_id = payload.get("parent_id")
	if parent_id is not None:
		parent_id = int(parent_id)
		parent = (
			db.query(WarehouseLocation)
			.filter(
				and_(
					WarehouseLocation.id == parent_id,
					WarehouseLocation.business_id == business_id,
					WarehouseLocation.warehouse_id == warehouse_id,
				)
			)
			.first()
		)
		if not parent:
			raise ApiError("VALIDATION_ERROR", "محل والد یافت نشد", http_status=400)

	auto_generate = bool(payload.get("auto_generate_code", False))
	kind = _normalize_kind(payload.get("location_kind"))

	def _finalize(loc: WarehouseLocation) -> Dict[str, Any]:
		rows = (
			db.query(WarehouseLocation)
			.filter(and_(WarehouseLocation.business_id == business_id, WarehouseLocation.warehouse_id == warehouse_id))
			.all()
		)
		path_map = _build_path_maps(rows)
		return {"item": _location_to_dict(loc, path_map.get(loc.id, loc.code))}

	if auto_generate:
		from app.services.document_numbering_service import generate_warehouse_location_code

		doc_date = datetime.utcnow().date()
		max_attempts = 5
		for attempt in range(max_attempts):
			code = generate_warehouse_location_code(db, business_id, warehouse_id, doc_date)
			now = datetime.utcnow()
			loc = WarehouseLocation(
				business_id=business_id,
				warehouse_id=warehouse_id,
				parent_id=parent_id,
				code=code,
				name=name,
				location_kind=kind,
				sort_order=int(payload.get("sort_order") or 0),
				is_active=bool(payload.get("is_active", True)),
				notes=payload.get("notes"),
				created_at=now,
				updated_at=now,
			)
			db.add(loc)
			try:
				db.commit()
				db.refresh(loc)
				return _finalize(loc)
			except IntegrityError as exc:
				db.rollback()
				msg = str(getattr(exc.orig, "args", exc))
				if "uq_warehouse_locations_wh_code" in msg or "Duplicate entry" in msg:
					continue
				raise
		raise ApiError(
			"DOCUMENT_CODE_RACE",
			"تولید کد محل پس از چند تلاش ناموفق بود. دوباره تلاش کنید.",
			http_status=409,
		)

	code = (payload.get("code") or "").strip()
	if not code:
		raise ApiError("VALIDATION_ERROR", "کد محل الزامی است", http_status=400)

	dup = (
		db.query(WarehouseLocation)
		.filter(and_(WarehouseLocation.warehouse_id == warehouse_id, WarehouseLocation.code == code))
		.first()
	)
	if dup:
		raise ApiError("DUPLICATE_CODE", "این کد محل در همین انبار قبلاً ثبت شده است", http_status=409)

	now = datetime.utcnow()
	loc = WarehouseLocation(
		business_id=business_id,
		warehouse_id=warehouse_id,
		parent_id=parent_id,
		code=code,
		name=name,
		location_kind=kind,
		sort_order=int(payload.get("sort_order") or 0),
		is_active=bool(payload.get("is_active", True)),
		notes=payload.get("notes"),
		created_at=now,
		updated_at=now,
	)
	db.add(loc)
	db.commit()
	db.refresh(loc)

	return _finalize(loc)


def update_location(
	db: Session,
	business_id: int,
	warehouse_id: int,
	location_id: int,
	payload: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
	_assert_warehouse(db, business_id, warehouse_id)
	loc = (
		db.query(WarehouseLocation)
		.filter(
			and_(
				WarehouseLocation.id == location_id,
				WarehouseLocation.business_id == business_id,
				WarehouseLocation.warehouse_id == warehouse_id,
			)
		)
		.first()
	)
	if not loc:
		return None

	if payload.get("code") is not None:
		new_code = (payload["code"] or "").strip()
		if not new_code:
			raise ApiError("VALIDATION_ERROR", "کد محل نمی‌تواند خالی باشد", http_status=400)
		exists = (
			db.query(WarehouseLocation)
			.filter(
				and_(
					WarehouseLocation.warehouse_id == warehouse_id,
					WarehouseLocation.code == new_code,
					WarehouseLocation.id != location_id,
				)
			)
			.first()
		)
		if exists:
			raise ApiError("DUPLICATE_CODE", "این کد محل در همین انبار قبلاً ثبت شده است", http_status=409)
		loc.code = new_code

	if payload.get("name") is not None:
		loc.name = (payload["name"] or "").strip()
		if not loc.name:
			raise ApiError("VALIDATION_ERROR", "نام محل نمی‌تواند خالی باشد", http_status=400)

	if "parent_id" in payload:
		new_parent = payload.get("parent_id")
		if new_parent is None:
			loc.parent_id = None
		else:
			pid = int(new_parent)
			if pid == location_id:
				raise ApiError("VALIDATION_ERROR", "محل نمی‌تواند والد خودش باشد", http_status=400)
			parent = (
				db.query(WarehouseLocation)
				.filter(
					and_(
						WarehouseLocation.id == pid,
						WarehouseLocation.business_id == business_id,
						WarehouseLocation.warehouse_id == warehouse_id,
					)
				)
				.first()
			)
			if not parent:
				raise ApiError("VALIDATION_ERROR", "محل والد یافت نشد", http_status=400)
			desc = {location_id}
			cur = pid
			for _ in range(500):
				if cur is None:
					break
				if cur in desc:
					raise ApiError("VALIDATION_ERROR", "ایجاد حلقه در سلسله‌مراتب مجاز نیست", http_status=400)
				row = db.query(WarehouseLocation).filter(WarehouseLocation.id == cur).first()
				if not row:
					break
				desc.add(cur)
				cur = row.parent_id
			loc.parent_id = pid

	if payload.get("location_kind") is not None:
		loc.location_kind = _normalize_kind(payload.get("location_kind"))

	if payload.get("sort_order") is not None:
		loc.sort_order = int(payload["sort_order"])

	if payload.get("is_active") is not None:
		loc.is_active = bool(payload["is_active"])

	if "notes" in payload:
		loc.notes = payload.get("notes")

	loc.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(loc)

	rows = (
		db.query(WarehouseLocation)
		.filter(and_(WarehouseLocation.business_id == business_id, WarehouseLocation.warehouse_id == warehouse_id))
		.all()
	)
	path_map = _build_path_maps(rows)
	return {"item": _location_to_dict(loc, path_map.get(loc.id, loc.code))}


def delete_location(db: Session, business_id: int, warehouse_id: int, location_id: int) -> bool:
	_assert_warehouse(db, business_id, warehouse_id)
	loc = (
		db.query(WarehouseLocation)
		.filter(
			and_(
				WarehouseLocation.id == location_id,
				WarehouseLocation.business_id == business_id,
				WarehouseLocation.warehouse_id == warehouse_id,
			)
		)
		.first()
	)
	if not loc:
		return False

	child_count = (
		db.query(WarehouseLocation)
		.filter(
			and_(
				WarehouseLocation.warehouse_id == warehouse_id,
				WarehouseLocation.parent_id == location_id,
			)
		)
		.count()
	)
	if child_count > 0:
		raise ApiError("HAS_CHILDREN", "ابتدا زیرمجموعه‌های این محل را حذف یا منتقل کنید", http_status=409)

	db.delete(loc)
	db.commit()
	return True


def _assert_product(db: Session, business_id: int, product_id: int) -> Product:
	p = db.query(Product).filter(and_(Product.id == product_id, Product.business_id == business_id)).first()
	if not p:
		raise ApiError("NOT_FOUND", "کالا یافت نشد", http_status=404)
	return p


def list_placements(
	db: Session,
	business_id: int,
	warehouse_id: int,
	product_id: Optional[int] = None,
	location_id: Optional[int] = None,
) -> Dict[str, Any]:
	_assert_warehouse(db, business_id, warehouse_id)
	q = (
		db.query(WarehouseProductPlacement, Product, WarehouseLocation)
		.join(Product, Product.id == WarehouseProductPlacement.product_id)
		.join(WarehouseLocation, WarehouseLocation.id == WarehouseProductPlacement.warehouse_location_id)
		.filter(
			and_(
				WarehouseProductPlacement.business_id == business_id,
				WarehouseProductPlacement.warehouse_id == warehouse_id,
			)
		)
	)
	if product_id is not None:
		q = q.filter(WarehouseProductPlacement.product_id == int(product_id))
	if location_id is not None:
		q = q.filter(WarehouseProductPlacement.warehouse_location_id == int(location_id))

	results = q.order_by(Product.name.asc()).all()
	rows_list = []
	all_locs = (
		db.query(WarehouseLocation)
		.filter(and_(WarehouseLocation.business_id == business_id, WarehouseLocation.warehouse_id == warehouse_id))
		.all()
	)
	path_map = _build_path_maps(all_locs)

	for pl, prod, loc in results:
		rows_list.append(
			{
				"id": pl.id,
				"product_id": pl.product_id,
				"product_code": prod.code,
				"product_name": prod.name,
				"main_unit": prod.main_unit or "",
				"warehouse_location_id": pl.warehouse_location_id,
				"location_code": loc.code,
				"location_name": loc.name,
				"path_codes": path_map.get(loc.id, loc.code),
				"quantity": float(pl.quantity),
				"notes": pl.notes,
				"updated_at": pl.updated_at.isoformat() if pl.updated_at else None,
			}
		)
	return {"items": rows_list}


def create_placement(db: Session, business_id: int, warehouse_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_assert_warehouse(db, business_id, warehouse_id)
	pid = int(payload["product_id"])
	lid = int(payload["warehouse_location_id"])
	_assert_product(db, business_id, pid)

	loc = (
		db.query(WarehouseLocation)
		.filter(
			and_(
				WarehouseLocation.id == lid,
				WarehouseLocation.business_id == business_id,
				WarehouseLocation.warehouse_id == warehouse_id,
			)
		)
		.first()
	)
	if not loc:
		raise ApiError("NOT_FOUND", "محل انبار یافت نشد", http_status=404)

	qty = payload.get("quantity")
	try:
		qty_dec = Decimal(str(qty if qty is not None else 0))
	except Exception:
		raise ApiError("VALIDATION_ERROR", "مقدار نامعتبر است", http_status=400)

	exists = (
		db.query(WarehouseProductPlacement)
		.filter(
			and_(
				WarehouseProductPlacement.warehouse_id == warehouse_id,
				WarehouseProductPlacement.product_id == pid,
				WarehouseProductPlacement.warehouse_location_id == lid,
			)
		)
		.first()
	)
	if exists:
		raise ApiError("DUPLICATE", "این کالا در همین محل قبلاً ثبت شده؛ از ویرایش استفاده کنید", http_status=409)

	now = datetime.utcnow()
	pl = WarehouseProductPlacement(
		business_id=business_id,
		warehouse_id=warehouse_id,
		warehouse_location_id=lid,
		product_id=pid,
		quantity=qty_dec,
		notes=payload.get("notes"),
		created_at=now,
		updated_at=now,
	)
	db.add(pl)
	db.commit()
	db.refresh(pl)

	prod = db.query(Product).filter(Product.id == pid).first()
	all_locs = (
		db.query(WarehouseLocation)
		.filter(and_(WarehouseLocation.business_id == business_id, WarehouseLocation.warehouse_id == warehouse_id))
		.all()
	)
	path_map = _build_path_maps(all_locs)
	item = {
		"id": pl.id,
		"product_id": pl.product_id,
		"product_code": prod.code if prod else "",
		"product_name": prod.name if prod else "",
		"main_unit": prod.main_unit or "",
		"warehouse_location_id": pl.warehouse_location_id,
		"location_code": loc.code,
		"location_name": loc.name,
		"path_codes": path_map.get(loc.id, loc.code),
		"quantity": float(pl.quantity),
		"notes": pl.notes,
	}
	return {"item": item}


def update_placement(
	db: Session,
	business_id: int,
	warehouse_id: int,
	placement_id: int,
	payload: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
	_assert_warehouse(db, business_id, warehouse_id)
	pl = (
		db.query(WarehouseProductPlacement)
		.filter(
			and_(
				WarehouseProductPlacement.id == placement_id,
				WarehouseProductPlacement.business_id == business_id,
				WarehouseProductPlacement.warehouse_id == warehouse_id,
			)
		)
		.first()
	)
	if not pl:
		return None

	new_loc_id = payload.get("warehouse_location_id")
	if new_loc_id is not None:
		new_loc_id = int(new_loc_id)
		loc = (
			db.query(WarehouseLocation)
			.filter(
				and_(
					WarehouseLocation.id == new_loc_id,
					WarehouseLocation.business_id == business_id,
					WarehouseLocation.warehouse_id == warehouse_id,
				)
			)
			.first()
		)
		if not loc:
			raise ApiError("NOT_FOUND", "محل انبار یافت نشد", http_status=404)
		if new_loc_id != pl.warehouse_location_id:
			dup = (
				db.query(WarehouseProductPlacement)
				.filter(
					and_(
						WarehouseProductPlacement.warehouse_id == warehouse_id,
						WarehouseProductPlacement.product_id == pl.product_id,
						WarehouseProductPlacement.warehouse_location_id == new_loc_id,
						WarehouseProductPlacement.id != placement_id,
					)
				)
				.first()
			)
			if dup:
				raise ApiError("DUPLICATE", "این کالا در مقصد قبلاً ثبت شده است", http_status=409)
		pl.warehouse_location_id = new_loc_id

	if payload.get("quantity") is not None:
		try:
			pl.quantity = Decimal(str(payload["quantity"]))
		except Exception:
			raise ApiError("VALIDATION_ERROR", "مقدار نامعتبر است", http_status=400)

	if "notes" in payload:
		pl.notes = payload.get("notes")

	pl.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(pl)

	prod = db.query(Product).filter(Product.id == pl.product_id).first()
	loc = db.query(WarehouseLocation).filter(WarehouseLocation.id == pl.warehouse_location_id).first()
	all_locs = (
		db.query(WarehouseLocation)
		.filter(and_(WarehouseLocation.business_id == business_id, WarehouseLocation.warehouse_id == warehouse_id))
		.all()
	)
	path_map = _build_path_maps(all_locs)
	item = {
		"id": pl.id,
		"product_id": pl.product_id,
		"product_code": prod.code if prod else "",
		"product_name": prod.name if prod else "",
		"main_unit": prod.main_unit or "",
		"warehouse_location_id": pl.warehouse_location_id,
		"location_code": loc.code if loc else "",
		"location_name": loc.name if loc else "",
		"path_codes": path_map.get(pl.warehouse_location_id, ""),
		"quantity": float(pl.quantity),
		"notes": pl.notes,
	}
	return {"item": item}


def delete_placement(db: Session, business_id: int, warehouse_id: int, placement_id: int) -> bool:
	_assert_warehouse(db, business_id, warehouse_id)
	pl = (
		db.query(WarehouseProductPlacement)
		.filter(
			and_(
				WarehouseProductPlacement.id == placement_id,
				WarehouseProductPlacement.business_id == business_id,
				WarehouseProductPlacement.warehouse_id == warehouse_id,
			)
		)
		.first()
	)
	if not pl:
		return False
	db.delete(pl)
	db.commit()
	return True
