"""قابلیت‌های فاز ۳ افزونه پخش مویرگی."""

from __future__ import annotations

import math
import uuid
from datetime import date, datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session
from sqlalchemy import or_

from adapters.db.models.distribution import (
	DistributionFieldVisit,
	DistributionOfflineSyncBatch,
	DistributionRoute,
	DistributionRouteAssignment,
	DistributionRouteStop,
	DistributionUserLiveLocation,
	DistributionVan,
)
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from app.core.auth_dependency import AuthContext
from app.core.business_calendar import business_day_utc_bounds, business_today
from app.core.responses import ApiError
from app.services import distribution_service as dist_svc
from app.services.distribution_geo import check_geofence, haversine_meters, person_coords
from app.services.warehouse_service import create_manual_warehouse_document, get_physical_stock, post_warehouse_document


_MAP_TILE_SOURCES = frozenset({"osm", "memaps"})


def normalize_map_tile_source(value: Any) -> str:
	source = str(value or "osm").strip().lower()
	return source if source in _MAP_TILE_SOURCES else "osm"


def extend_settings_dict(row: Any) -> Dict[str, Any]:
	if not row:
		return {
			"shared_routing_catalog": False,
			"require_visit_in_daily_plan": False,
			"geofence_radius_meters": 0,
			"require_geofence": False,
			"visit_checklist_template": [],
			"enable_van_sales": False,
			"default_source_warehouse_id": None,
			"enable_presell": False,
			"enable_promotions": False,
			"visitor_max_discount_percent": 0,
			"enable_suggested_order": True,
			"map_tile_source": "osm",
			"memaps_api_key": None,
			"share_live_location": True,
			"carry_over_missed_visits": True,
			"carry_over_days": 7,
			"require_pod_signature": False,
			"require_pod_photo": False,
			"nav_provider": "neshan",
			"setup_completed": False,
			"auto_apply_promotions": True,
			"enable_perfect_store": True,
			"near_expiry_days": 14,
		}
	key = getattr(row, "memaps_api_key", None)
	key_s = str(key).strip() if key else None
	return {
		"shared_routing_catalog": bool(row.shared_routing_catalog),
		"require_visit_in_daily_plan": bool(row.require_visit_in_daily_plan),
		"geofence_radius_meters": int(getattr(row, "geofence_radius_meters", 0) or 0),
		"require_geofence": bool(getattr(row, "require_geofence", False)),
		"visit_checklist_template": getattr(row, "visit_checklist_template", None) or [],
		"enable_van_sales": bool(getattr(row, "enable_van_sales", False)),
		"default_source_warehouse_id": getattr(row, "default_source_warehouse_id", None),
		"enable_presell": bool(getattr(row, "enable_presell", False)),
		"enable_promotions": bool(getattr(row, "enable_promotions", False)),
		"visitor_max_discount_percent": float(getattr(row, "visitor_max_discount_percent", 0) or 0),
		"enable_suggested_order": bool(getattr(row, "enable_suggested_order", True)),
		"map_tile_source": normalize_map_tile_source(getattr(row, "map_tile_source", "osm")),
		"memaps_api_key": key_s or None,
		"share_live_location": bool(getattr(row, "share_live_location", True)),
		"carry_over_missed_visits": bool(getattr(row, "carry_over_missed_visits", True)),
		"carry_over_days": int(getattr(row, "carry_over_days", 7) or 7),
		"require_pod_signature": bool(getattr(row, "require_pod_signature", False)),
		"require_pod_photo": bool(getattr(row, "require_pod_photo", False)),
		"nav_provider": str(getattr(row, "nav_provider", None) or "neshan"),
		"setup_completed": bool(getattr(row, "setup_completed", False)),
		"auto_apply_promotions": bool(getattr(row, "auto_apply_promotions", True)),
		"enable_perfect_store": bool(getattr(row, "enable_perfect_store", True)),
		"near_expiry_days": int(getattr(row, "near_expiry_days", 14) or 14),
	}


def validate_geofence_on_start(
	db: Session,
	business_id: int,
	person_id: int,
	start_lat: Optional[float],
	start_lng: Optional[float],
	allow_override: bool = False,
) -> Dict[str, Any]:
	settings = dist_svc.get_or_create_distribution_settings(db, business_id)
	radius = int(getattr(settings, "geofence_radius_meters", 0) or 0)
	require = bool(getattr(settings, "require_geofence", False))
	if radius <= 0 or not require:
		return {"ok": True, "distance_meters": None}
	person = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
	if not person:
		raise ApiError("NOT_FOUND", "Person not found", http_status=404)
	plats = person_coords(person)
	ok, dist, msg = check_geofence(plats[0], plats[1], start_lat, start_lng, radius, True)
	if ok:
		return {"ok": True, "distance_meters": dist}
	if allow_override:
		return {"ok": True, "distance_meters": dist, "geofence_warning": msg}
	raise ApiError("GEOFENCE_VIOLATION", msg, http_status=400, details={"distance_meters": dist})


def update_person_location(db: Session, business_id: int, person_id: int, lat: float, lng: float) -> Dict[str, Any]:
	person = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
	if not person:
		raise ApiError("NOT_FOUND", "Person not found", http_status=404)
	person.latitude = lat
	person.longitude = lng
	person.updated_at = datetime.utcnow()
	db.commit()
	return {"person_id": person_id, "latitude": lat, "longitude": lng}


def list_vans(db: Session, business_id: int, ctx: AuthContext) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	from app.services.distribution_documents import user_label

	q = db.query(DistributionVan).filter(DistributionVan.business_id == business_id)
	if not dist_svc._can_see_full_distribution_catalog(ctx, business_id):
		uid = ctx.get_user_id()
		if uid is None:
			return []
		q = q.filter(DistributionVan.user_id == uid)
	rows = q.order_by(DistributionVan.code.asc()).all()
	out = []
	for v in rows:
		out.append(
			{
				"id": v.id,
				"code": v.code,
				"name": v.name,
				"warehouse_id": v.warehouse_id,
				"user_id": v.user_id,
				"user_name": user_label(db, v.user_id),
				"is_active": v.is_active,
				"plate_number": getattr(v, "plate_number", None),
				"max_weight_kg": float(v.max_weight_kg) if getattr(v, "max_weight_kg", None) else None,
				"max_volume_m3": float(v.max_volume_m3) if getattr(v, "max_volume_m3", None) else None,
			}
		)
	return out


def update_van(db: Session, business_id: int, van_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	van = db.query(DistributionVan).filter(DistributionVan.id == van_id, DistributionVan.business_id == business_id).first()
	if not van:
		raise ApiError("NOT_FOUND", "Van not found", http_status=404)
	if "name" in payload and payload["name"]:
		van.name = str(payload["name"]).strip()[:255]
	if "user_id" in payload:
		van.user_id = int(payload["user_id"]) if payload.get("user_id") else None
	if "is_active" in payload:
		van.is_active = bool(payload["is_active"])
	if "plate_number" in payload:
		raw = str(payload.get("plate_number") or "").strip()
		van.plate_number = raw[:32] or None
	if "max_weight_kg" in payload:
		van.max_weight_kg = float(payload["max_weight_kg"]) if payload.get("max_weight_kg") else None
	if "max_volume_m3" in payload:
		van.max_volume_m3 = float(payload["max_volume_m3"]) if payload.get("max_volume_m3") else None
	van.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(van)
	return {
		"id": van.id,
		"code": van.code,
		"name": van.name,
		"warehouse_id": van.warehouse_id,
		"user_id": van.user_id,
		"is_active": van.is_active,
		"plate_number": getattr(van, "plate_number", None),
		"max_weight_kg": float(van.max_weight_kg) if getattr(van, "max_weight_kg", None) else None,
		"max_volume_m3": float(van.max_volume_m3) if getattr(van, "max_volume_m3", None) else None,
	}


def create_van(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	if not code or not name:
		raise ApiError("VALIDATION_ERROR", "code and name required", http_status=400)
	if db.query(DistributionVan).filter(DistributionVan.business_id == business_id, DistributionVan.code == code).first():
		raise ApiError("DUPLICATE", "Van code exists", http_status=400)
	wh_code = f"VAN-{code}"[:64]
	wh = Warehouse(
		business_id=business_id,
		code=wh_code,
		name=f"ون {name}"[:255],
		description="انبار اختصاصی ون توزیع",
		is_default=False,
		created_at=datetime.utcnow(),
		updated_at=datetime.utcnow(),
	)
	db.add(wh)
	db.flush()
	van = DistributionVan(
		business_id=business_id,
		warehouse_id=wh.id,
		user_id=int(payload["user_id"]) if payload.get("user_id") else None,
		code=code[:50],
		name=name[:255],
		is_active=bool(payload.get("is_active", True)),
		plate_number=(str(payload.get("plate_number") or "").strip()[:32] or None),
		max_weight_kg=float(payload["max_weight_kg"]) if payload.get("max_weight_kg") else None,
		max_volume_m3=float(payload["max_volume_m3"]) if payload.get("max_volume_m3") else None,
	)
	db.add(van)
	db.commit()
	db.refresh(van)
	return {"id": van.id, "warehouse_id": van.warehouse_id, "code": van.code, "name": van.name}


def get_van_for_user(db: Session, business_id: int, user_id: int) -> Optional[DistributionVan]:
	return (
		db.query(DistributionVan)
		.filter(
			DistributionVan.business_id == business_id,
			DistributionVan.user_id == user_id,
			DistributionVan.is_active == True,  # noqa: E712
		)
		.first()
	)


def get_van_stock(db: Session, business_id: int, van_id: int) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	van = db.query(DistributionVan).filter(DistributionVan.id == van_id, DistributionVan.business_id == business_id).first()
	if not van:
		raise ApiError("NOT_FOUND", "Van not found", http_status=404)
	from app.services.distribution_documents import _resolve_unit_price

	products = db.query(Product).filter(Product.business_id == business_id, Product.track_inventory == True).all()  # noqa: E712
	items = []
	for p in products:
		qty = get_physical_stock(db, business_id, p.id, van.warehouse_id, business_today(business_id))
		if qty and float(qty) > 0:
			unit_price = _resolve_unit_price(db, business_id, p, None)
			tax_rate = float(p.sales_tax_rate or 0) if bool(getattr(p, "is_sales_taxable", False)) else 0.0
			items.append(
				{
					"product_id": p.id,
					"product_name": p.name,
					"quantity": float(qty),
					"unit_price": unit_price,
					"tax_rate": tax_rate,
					"is_sales_taxable": bool(getattr(p, "is_sales_taxable", False)),
					"general_barcodes": getattr(p, "general_barcodes", None),
					"code": p.code,
				}
			)
	from app.services.distribution_field_ops_service import van_capacity_snapshot

	cap = van_capacity_snapshot(db, business_id, van)
	lot_by_pid: Dict[int, list] = {}
	for lot in cap.get("lots") or []:
		lot_by_pid.setdefault(int(lot["product_id"]), []).append(lot)
	for it in items:
		it["lots"] = lot_by_pid.get(int(it["product_id"]), [])
		it["near_expiry"] = any(x.get("near_expiry") or x.get("expired") for x in it["lots"])
		lot_qty = sum(float(x.get("quantity") or 0) for x in it["lots"])
		it["lot_quantity"] = round(lot_qty, 3)
		it["lot_variance"] = round(float(it["quantity"]) - lot_qty, 3)
	return {
		"van_id": van_id,
		"warehouse_id": van.warehouse_id,
		"items": items,
		"capacity": cap,
		"plate_number": getattr(van, "plate_number", None),
		"max_weight_kg": float(van.max_weight_kg) if getattr(van, "max_weight_kg", None) else None,
		"max_volume_m3": float(van.max_volume_m3) if getattr(van, "max_volume_m3", None) else None,
	}


def load_van(
	db: Session,
	business_id: int,
	user_id: int,
	van_id: int,
	lines: List[Dict[str, Any]],
	source_warehouse_id: Optional[int] = None,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	van = db.query(DistributionVan).filter(DistributionVan.id == van_id, DistributionVan.business_id == business_id).first()
	if not van:
		raise ApiError("NOT_FOUND", "Van not found", http_status=404)
	settings = dist_svc.get_or_create_distribution_settings(db, business_id)
	src = source_warehouse_id or getattr(settings, "default_source_warehouse_id", None)
	if not src:
		raise ApiError("VALIDATION_ERROR", "source_warehouse_id required", http_status=400)
	if not lines:
		raise ApiError("VALIDATION_ERROR", "lines required", http_status=400)
	wh_lines = []
	for i, ln in enumerate(lines):
		if not isinstance(ln, dict):
			raise ApiError("VALIDATION_ERROR", f"lines[{i}] invalid", http_status=400)
		pid = int(ln.get("product_id") or 0)
		qty = float(ln.get("quantity") or 0)
		if pid <= 0 or qty <= 0:
			raise ApiError("VALIDATION_ERROR", f"lines[{i}] product_id and quantity required", http_status=400)
		wh_lines.append({"product_id": pid, "quantity": qty})
	today = business_today(business_id)
	# پیش‌بررسی موجودی مبدأ
	for ln in wh_lines:
		avail = float(get_physical_stock(db, business_id, int(ln["product_id"]), int(src), today) or 0)
		if avail + 1e-9 < float(ln["quantity"]):
			raise ApiError(
				"INSUFFICIENT_STOCK",
				f"Insufficient stock for product {ln['product_id']}: available {avail}, requested {ln['quantity']}",
				http_status=400,
				details={"product_id": ln["product_id"], "available": avail, "requested": ln["quantity"]},
			)
	wh_doc = create_manual_warehouse_document(
		db,
		business_id,
		user_id,
		{
			"doc_type": "transfer",
			"document_date": today.isoformat(),
			"warehouse_id_from": int(src),
			"warehouse_id_to": int(van.warehouse_id),
			"description": f"بارگیری ون {van.code}",
			"lines": wh_lines,
		},
	)
	post_warehouse_document(db, wh_doc.id)
	from datetime import date as _date

	from app.services.distribution_field_ops_service import add_van_lot, assert_van_capacity

	for ln in lines:
		if not isinstance(ln, dict):
			continue
		exp = None
		raw_exp = ln.get("expiry_date")
		if raw_exp:
			try:
				exp = _date.fromisoformat(str(raw_exp)[:10])
			except ValueError:
				exp = None
		add_van_lot(
			db,
			business_id,
			int(van.id),
			int(ln.get("product_id") or 0),
			float(ln.get("quantity") or 0),
			lot_code=ln.get("lot_code"),
			expiry_date=exp,
			unit_weight_kg=float(ln["unit_weight_kg"]) if ln.get("unit_weight_kg") else None,
			unit_volume_m3=float(ln["unit_volume_m3"]) if ln.get("unit_volume_m3") else None,
		)
	try:
		assert_van_capacity(db, business_id, van)
	except ApiError:
		db.rollback()
		raise
	db.commit()
	return {"van_id": van_id, "warehouse_document_id": wh_doc.id, "status": "posted"}


def unload_van(
	db: Session,
	business_id: int,
	user_id: int,
	van_id: int,
	lines: List[Dict[str, Any]],
	dest_warehouse_id: Optional[int] = None,
) -> Dict[str, Any]:
	"""تخلیهٔ موجودی ون به انبار مرکزی."""
	dist_svc._ensure_plugin(db, business_id)
	van = db.query(DistributionVan).filter(DistributionVan.id == van_id, DistributionVan.business_id == business_id).first()
	if not van:
		raise ApiError("NOT_FOUND", "Van not found", http_status=404)
	settings = dist_svc.get_or_create_distribution_settings(db, business_id)
	dest = dest_warehouse_id or getattr(settings, "default_source_warehouse_id", None)
	if not dest:
		raise ApiError("VALIDATION_ERROR", "dest_warehouse_id required", http_status=400)
	if int(dest) == int(van.warehouse_id):
		raise ApiError("VALIDATION_ERROR", "destination must differ from van warehouse", http_status=400)
	if not lines:
		raise ApiError("VALIDATION_ERROR", "lines required", http_status=400)
	wh_lines = []
	for i, ln in enumerate(lines):
		if not isinstance(ln, dict):
			raise ApiError("VALIDATION_ERROR", f"lines[{i}] invalid", http_status=400)
		pid = int(ln.get("product_id") or 0)
		qty = float(ln.get("quantity") or 0)
		if pid <= 0 or qty <= 0:
			raise ApiError("VALIDATION_ERROR", f"lines[{i}] product_id and quantity required", http_status=400)
		avail = get_physical_stock(db, business_id, pid, van.warehouse_id, business_today(business_id))
		if float(avail or 0) < qty:
			raise ApiError("INSUFFICIENT_VAN_STOCK", f"Insufficient stock for product {pid}", http_status=400)
		wh_lines.append({"product_id": pid, "quantity": qty})
	wh_doc = create_manual_warehouse_document(
		db,
		business_id,
		user_id,
		{
			"doc_type": "transfer",
			"document_date": business_today(business_id).isoformat(),
			"warehouse_id_from": int(van.warehouse_id),
			"warehouse_id_to": int(dest),
			"description": f"تخلیه ون {van.code}",
			"lines": wh_lines,
		},
	)
	post_warehouse_document(db, wh_doc.id)
	from app.services.distribution_field_ops_service import consume_van_lots_fefo

	for ln in wh_lines:
		consume_van_lots_fefo(db, int(van.id), int(ln["product_id"]), float(ln["quantity"]))
	db.commit()
	return {"van_id": van_id, "warehouse_document_id": wh_doc.id, "status": "posted"}


def apply_route_optimize(
	db: Session,
	business_id: int,
	route_id: int,
	plan_date: date,
	start_lat: Optional[float] = None,
	start_lng: Optional[float] = None,
) -> Dict[str, Any]:
	"""بهینه‌سازی و ذخیرهٔ ترتیب فقط برای همان روز (بدون بازنویسی sort_order کاتالوگ)."""
	result = optimize_route_plan(db, business_id, route_id, plan_date, start_lat, start_lng)
	items = result.get("items") or []
	if not result.get("optimized"):
		return {**result, "persisted": False, "persist_mode": "day_override"}
	route = db.query(DistributionRoute).filter(
		DistributionRoute.id == route_id,
		DistributionRoute.business_id == business_id,
	).first()
	if not route:
		raise ApiError("NOT_FOUND", "Route not found", http_status=404)
	overrides = dict(route.plan_sort_overrides or {})
	day_key = plan_date.isoformat()
	day_map: Dict[str, int] = {}
	for it in items:
		sid = it.get("stop_id")
		new_sort = it.get("optimized_sort")
		if sid is None or new_sort is None:
			continue
		day_map[str(int(sid))] = int(new_sort)
	overrides[day_key] = day_map
	# پاکسازی کلیدهای قدیمی‌تر از ۹۰ روز برای جلوگیری از رشد بی‌نهایت
	try:
		from datetime import timedelta

		cutoff = (plan_date - timedelta(days=90)).isoformat()
		overrides = {k: v for k, v in overrides.items() if isinstance(k, str) and k >= cutoff}
		overrides[day_key] = day_map
	except Exception:
		pass
	route.plan_sort_overrides = overrides
	route.updated_at = datetime.utcnow()
	db.commit()
	return {**result, "persisted": True, "persist_mode": "day_override", "day": day_key}


def record_van_sale_issue(
	db: Session,
	business_id: int,
	user_id: int,
	visit: DistributionFieldVisit,
	van_lines: List[Dict[str, Any]],
) -> Optional[int]:
	if not van_lines:
		return None
	van = get_van_for_user(db, business_id, user_id)
	if not van:
		raise ApiError("VALIDATION_ERROR", "No van assigned to this user", http_status=400)
	wh_lines = []
	for ln in van_lines:
		pid = int(ln.get("product_id") or 0)
		qty = float(ln.get("quantity") or 0)
		if pid <= 0 or qty <= 0:
			continue
		avail = get_physical_stock(db, business_id, pid, van.warehouse_id, business_today(business_id))
		if float(avail or 0) < qty:
			raise ApiError("INSUFFICIENT_VAN_STOCK", f"Insufficient stock for product {pid}", http_status=400)
		wh_lines.append({"product_id": pid, "quantity": qty})
	if not wh_lines:
		return None
	wh_doc = create_manual_warehouse_document(
		db,
		business_id,
		user_id,
		{
			"doc_type": "issue",
			"document_date": business_today(business_id).isoformat(),
			"warehouse_id_from": int(van.warehouse_id),
			"description": f"فروش ون — ویزیت #{visit.id}",
			"lines": wh_lines,
			"extra_info": {"distribution_visit_id": visit.id},
		},
	)
	post_warehouse_document(db, wh_doc.id)
	return int(wh_doc.id)


def optimize_route_plan(
	db: Session,
	business_id: int,
	route_id: int,
	plan_date: date,
	start_lat: Optional[float] = None,
	start_lng: Optional[float] = None,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	route = db.query(DistributionRoute).filter(DistributionRoute.id == route_id, DistributionRoute.business_id == business_id).first()
	if not route:
		raise ApiError("NOT_FOUND", "Route not found", http_status=404)
	stops = (
		db.query(DistributionRouteStop)
		.filter(DistributionRouteStop.route_id == route_id)
		.all()
	)
	items: List[Dict[str, Any]] = []
	for s in stops:
		if not dist_svc._weekday_matches(plan_date, s.weekday):
			continue
		person = db.query(Person).filter(Person.id == s.person_id).first()
		lat, lng = person_coords(person) if person else (None, None)
		items.append(
			{
				"stop_id": s.id,
				"person_id": s.person_id,
				"person_name": (person.alias_name or "").strip() if person else str(s.person_id),
				"sort_order": s.sort_order,
				"latitude": lat,
				"longitude": lng,
			}
		)
	if len(items) < 2:
		return {"route_id": route_id, "plan_date": plan_date.isoformat(), "items": items, "optimized": False}
	cur_lat, cur_lng = start_lat, start_lng
	if cur_lat is None or cur_lng is None:
		first_with_coords = next((x for x in items if x["latitude"] is not None), None)
		if first_with_coords:
			cur_lat, cur_lng = first_with_coords["latitude"], first_with_coords["longitude"]
		else:
			items.sort(key=lambda x: (x["sort_order"], x["person_id"]))
			return {"route_id": route_id, "plan_date": plan_date.isoformat(), "items": items, "optimized": False}
	remaining = items[:]
	ordered: List[Dict[str, Any]] = []
	while remaining:
		best_i = 0
		best_d = math.inf
		for i, it in enumerate(remaining):
			lat, lng = it.get("latitude"), it.get("longitude")
			if lat is None or lng is None or cur_lat is None or cur_lng is None:
				d = float(it["sort_order"])
			else:
				d = haversine_meters(cur_lat, cur_lng, lat, lng)
			if d < best_d:
				best_d = d
				best_i = i
		pick = remaining.pop(best_i)
		pick["optimized_sort"] = len(ordered) + 1
		ordered.append(pick)
		if pick.get("latitude") is not None:
			cur_lat, cur_lng = pick["latitude"], pick["longitude"]
	return {"route_id": route_id, "plan_date": plan_date.isoformat(), "items": ordered, "optimized": True}


def _parse_utc_ts(value: Any) -> Optional[datetime]:
	if isinstance(value, datetime):
		return value.replace(tzinfo=None) if value.tzinfo else value
	if not value:
		return None
	raw = str(value).strip().replace("Z", "+00:00")
	try:
		dt = datetime.fromisoformat(raw)
		return dt.replace(tzinfo=None) if dt.tzinfo else dt
	except ValueError:
		return None


def _presence_from_age(updated_at: Optional[datetime]) -> str:
	if updated_at is None:
		return "none"
	age = (datetime.utcnow() - updated_at).total_seconds()
	if age <= 120:
		return "online"
	if age <= 15 * 60:
		return "recent"
	if age <= 24 * 3600:
		return "stale"
	return "offline"


def get_team_map(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	plan_date: Optional[date] = None,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	if not dist_svc._can_see_full_distribution_catalog(ctx, business_id):
		raise ApiError("FORBIDDEN", "Team map requires manage or reports_team", http_status=403)
	from app.services.distribution_documents import user_label

	d = plan_date or business_today(business_id)
	start_utc, end_utc = business_day_utc_bounds(business_id, d)
	settings = dist_svc.get_or_create_distribution_settings(db, business_id)
	share_live = bool(getattr(settings, "share_live_location", True))

	user_ids: set[int] = set()
	assigns = (
		db.query(DistributionRouteAssignment.user_id)
		.filter(
			DistributionRouteAssignment.business_id == business_id,
			DistributionRouteAssignment.valid_from <= d,
			or_(
				DistributionRouteAssignment.valid_to.is_(None),
				DistributionRouteAssignment.valid_to >= d,
			),
		)
		.distinct()
		.all()
	)
	user_ids.update(int(r[0]) for r in assigns if r[0])
	van_users = (
		db.query(DistributionVan.user_id)
		.filter(DistributionVan.business_id == business_id, DistributionVan.is_active.is_(True))
		.all()
	)
	user_ids.update(int(r[0]) for r in van_users if r[0])

	visits = (
		db.query(DistributionFieldVisit)
		.filter(
			DistributionFieldVisit.business_id == business_id,
			DistributionFieldVisit.started_at >= start_utc,
			DistributionFieldVisit.started_at <= end_utc,
		)
		.order_by(DistributionFieldVisit.started_at.desc())
		.all()
	)
	latest_visit: Dict[int, DistributionFieldVisit] = {}
	in_progress: Dict[int, DistributionFieldVisit] = {}
	for v in visits:
		uid = int(v.user_id)
		user_ids.add(uid)
		if uid not in latest_visit:
			latest_visit[uid] = v
		if v.status == "in_progress" and uid not in in_progress:
			in_progress[uid] = v

	live_rows = (
		db.query(DistributionUserLiveLocation)
		.filter(DistributionUserLiveLocation.business_id == business_id)
		.all()
	)
	live_by_user = {int(r.user_id): r for r in live_rows}
	user_ids.update(live_by_user.keys())

	visitors: List[Dict[str, Any]] = []
	customers: List[Dict[str, Any]] = []
	seen_customers: set[int] = set()

	for uid in sorted(user_ids):
		visit = in_progress.get(uid) or latest_visit.get(uid)
		person = None
		plats: Tuple[Optional[float], Optional[float]] = (None, None)
		if visit:
			person = db.query(Person).filter(Person.id == visit.person_id).first()
			plats = person_coords(person) if person else (None, None)
			if plats[0] is not None and plats[1] is not None and visit.person_id not in seen_customers:
				seen_customers.add(int(visit.person_id))
				customers.append(
					{
						"person_id": visit.person_id,
						"person_name": (person.alias_name or "").strip() if person else None,
						"latitude": plats[0],
						"longitude": plats[1],
						"user_id": uid,
					}
				)

		live = live_by_user.get(uid)
		lat = lng = None
		loc_source = None
		updated_at = None
		if share_live and live is not None:
			lat = float(live.latitude)
			lng = float(live.longitude)
			updated_at = live.recorded_at
			loc_source = "live"
		elif visit:
			extra = visit.extra_info if isinstance(visit.extra_info, dict) else {}
			live_ex = extra.get("live_location") if isinstance(extra.get("live_location"), dict) else {}
			if share_live and live_ex.get("latitude") is not None and live_ex.get("longitude") is not None:
				lat = float(live_ex["latitude"])
				lng = float(live_ex["longitude"])
				updated_at = _parse_utc_ts(live_ex.get("updated_at"))
				loc_source = "live"
			elif visit.status == "completed" and visit.end_latitude is not None:
				lat = float(visit.end_latitude)
				lng = float(visit.end_longitude) if visit.end_longitude is not None else None
				loc_source = "end"
				updated_at = visit.ended_at or visit.updated_at
			elif visit.start_latitude is not None:
				lat = float(visit.start_latitude)
				lng = float(visit.start_longitude) if visit.start_longitude is not None else None
				loc_source = "start"
				updated_at = visit.started_at

		current = in_progress.get(uid)
		started = current.started_at if current else (visit.started_at if visit else None)
		visitors.append(
			{
				"user_id": uid,
				"user_name": user_label(db, uid),
				"latitude": lat,
				"longitude": lng,
				"location_source": loc_source,
				"presence": _presence_from_age(updated_at),
				"live_updated_at": updated_at.isoformat() + "Z" if updated_at else None,
				"visit_id": current.id if current else (visit.id if visit else None),
				"status": current.status if current else (visit.status if visit else None),
				"person_id": (current.person_id if current else (visit.person_id if visit else None)),
				"person_name": (person.alias_name or "").strip() if person else None,
				"customer_latitude": plats[0],
				"customer_longitude": plats[1],
				"started_at": started.isoformat() + "Z" if started else None,
			}
		)

	visitors.sort(
		key=lambda x: (
			{"online": 0, "recent": 1, "stale": 2, "offline": 3, "none": 4}.get(str(x["presence"]), 9),
			(x["user_name"] or "").lower(),
		)
	)
	markers = [
		{
			"user_id": v["user_id"],
			"user_name": v["user_name"],
			"visit_id": v["visit_id"],
			"status": v["status"],
			"person_id": v["person_id"],
			"person_name": v["person_name"],
			"visit_latitude": v["latitude"],
			"visit_longitude": v["longitude"],
			"location_source": v["location_source"],
			"live_updated_at": v["live_updated_at"],
			"customer_latitude": v["customer_latitude"],
			"customer_longitude": v["customer_longitude"],
			"started_at": v["started_at"],
			"presence": v["presence"],
		}
		for v in visitors
		if v["latitude"] is not None and v["longitude"] is not None
	]
	return {
		"plan_date": d.isoformat(),
		"share_live_location": share_live,
		"visitors": visitors,
		"customers": customers,
		"markers": markers,
		"generated_at": datetime.utcnow().isoformat() + "Z",
	}


def process_offline_sync(
	db: Session,
	business_id: int,
	user_id: int,
	client_batch_id: str,
	actions: List[Dict[str, Any]],
	ctx: AuthContext,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	batch_id = (client_batch_id or "").strip() or str(uuid.uuid4())
	existing = (
		db.query(DistributionOfflineSyncBatch)
		.filter(
			DistributionOfflineSyncBatch.business_id == business_id,
			DistributionOfflineSyncBatch.client_batch_id == batch_id,
		)
		.first()
	)
	if existing and existing.results:
		return {"client_batch_id": batch_id, "results": existing.results, "idempotent": True}
	results: List[Dict[str, Any]] = []
	for i, act in enumerate(actions):
		op = str(act.get("op") or "").strip()
		client_ref = act.get("client_ref") or f"{i}"
		payload = act.get("payload") if isinstance(act.get("payload"), dict) else {}
		try:
			if op == "start_visit":
				data = dist_svc.start_visit(db, business_id, user_id, payload, ctx=ctx)
				results.append({"client_ref": client_ref, "ok": True, "visit_id": data.get("id")})
			elif op == "complete_visit":
				vid = int(payload.get("visit_id") or 0)
				data = dist_svc.complete_visit(
					db,
					business_id,
					user_id,
					vid,
					payload,
					allow_manage_override=ctx.has_business_permission("distribution", "manage"),
				)
				results.append({"client_ref": client_ref, "ok": True, "visit_id": data.get("id")})
			elif op == "cancel_visit":
				vid = int(payload.get("visit_id") or 0)
				data = dist_svc.cancel_visit(
					db,
					business_id,
					user_id,
					vid,
					payload.get("reason"),
					allow_manage_override=ctx.has_business_permission("distribution", "manage"),
				)
				results.append({"client_ref": client_ref, "ok": True, "visit_id": data.get("id")})
			elif op == "create_return":
				data = dist_svc.create_return_request(db, business_id, user_id, payload)
				results.append({"client_ref": client_ref, "ok": True, "return_request_id": data.get("id")})
			elif op == "create_presell_order":
				from app.services import distribution_commercial_service as dist_c

				data = dist_c.create_visit_order(db, business_id, user_id, payload, auto_confirm=bool(payload.get("confirm")))
				results.append({"client_ref": client_ref, "ok": True, "order_id": data.get("id"), "document_id": data.get("document_id")})
			elif op == "complete_visit_with_presell":
				# سفارش پیش‌فروش + تکمیل ویزیت در یک عمل آفلاین
				from app.services import distribution_commercial_service as dist_c

				order_payload = payload.get("order") if isinstance(payload.get("order"), dict) else {}
				visit_payload = payload.get("visit") if isinstance(payload.get("visit"), dict) else {}
				vid = int(visit_payload.get("visit_id") or payload.get("visit_id") or 0)
				order_data = dist_c.create_visit_order(
					db, business_id, user_id, order_payload, auto_confirm=bool(order_payload.get("confirm", True)),
				)
				if order_data.get("document_id") and not visit_payload.get("document_id"):
					visit_payload = dict(visit_payload)
					visit_payload["document_id"] = order_data["document_id"]
				ex = dict(visit_payload.get("extra_info") or {})
				ex["presell_order_id"] = order_data.get("id")
				visit_payload["extra_info"] = ex
				data = dist_svc.complete_visit(
					db,
					business_id,
					user_id,
					vid,
					visit_payload,
					allow_manage_override=ctx.has_business_permission("distribution", "manage"),
				)
				results.append({
					"client_ref": client_ref,
					"ok": True,
					"visit_id": data.get("id"),
					"order_id": order_data.get("id"),
				})
			else:
				results.append({"client_ref": client_ref, "ok": False, "error": f"unknown op {op}"})
		except ApiError as e:
			detail = e.detail if isinstance(e.detail, dict) else {}
			results.append(
				{
					"client_ref": client_ref,
					"ok": False,
					"error": detail.get("message", str(e)),
					"code": detail.get("code"),
				}
			)
		except Exception as e:
			results.append({"client_ref": client_ref, "ok": False, "error": str(e)})
	row = DistributionOfflineSyncBatch(
		business_id=business_id,
		user_id=user_id,
		client_batch_id=batch_id,
		actions=actions,
		results=results,
		status="completed",
	)
	db.add(row)
	db.commit()
	return {"client_batch_id": batch_id, "results": results}
