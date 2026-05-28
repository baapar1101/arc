"""قابلیت‌های فاز ۳ افزونه پخش مویرگی."""

from __future__ import annotations

import math
import uuid
from datetime import date, datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.distribution import (
	DistributionFieldVisit,
	DistributionOfflineSyncBatch,
	DistributionRoute,
	DistributionRouteStop,
	DistributionVan,
)
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from app.core.auth_dependency import AuthContext
from app.core.business_calendar import business_today
from app.core.responses import ApiError
from app.services import distribution_service as dist_svc
from app.services.distribution_geo import check_geofence, haversine_meters, person_coords
from app.services.warehouse_service import create_manual_warehouse_document, get_physical_stock, post_warehouse_document


def extend_settings_dict(row: Any) -> Dict[str, Any]:
	base = dist_svc.settings_to_dict(row) if row else {}
	if not row:
		return {
			**base,
			"geofence_radius_meters": 0,
			"require_geofence": False,
			"visit_checklist_template": [],
			"enable_van_sales": False,
			"default_source_warehouse_id": None,
		}
	return {
		**base,
		"geofence_radius_meters": int(getattr(row, "geofence_radius_meters", 0) or 0),
		"require_geofence": bool(getattr(row, "require_geofence", False)),
		"visit_checklist_template": getattr(row, "visit_checklist_template", None) or [],
		"enable_van_sales": bool(getattr(row, "enable_van_sales", False)),
		"default_source_warehouse_id": getattr(row, "default_source_warehouse_id", None),
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
				"is_active": v.is_active,
			}
		)
	return out


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
	products = db.query(Product).filter(Product.business_id == business_id, Product.track_inventory == True).all()  # noqa: E712
	items = []
	for p in products:
		qty = get_physical_stock(db, business_id, p.id, van.warehouse_id, business_today(business_id))
		if qty and float(qty) > 0:
			items.append({"product_id": p.id, "product_name": p.name, "quantity": float(qty)})
	return {"van_id": van_id, "warehouse_id": van.warehouse_id, "items": items}


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
	db.commit()
	return {"van_id": van_id, "warehouse_document_id": wh_doc.id, "status": "posted"}


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


def get_team_map(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	plan_date: Optional[date] = None,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	if not dist_svc._can_see_full_distribution_catalog(ctx, business_id):
		raise ApiError("FORBIDDEN", "Team map requires manage or reports_team", http_status=403)
	d = plan_date or business_today(business_id)
	start = datetime.combine(d, datetime.min.time())
	end = datetime.combine(d, datetime.max.time())
	rows = (
		db.query(DistributionFieldVisit)
		.filter(
			DistributionFieldVisit.business_id == business_id,
			DistributionFieldVisit.started_at >= start,
			DistributionFieldVisit.started_at <= end,
		)
		.order_by(DistributionFieldVisit.user_id.asc(), DistributionFieldVisit.started_at.desc())
		.all()
	)
	by_user: Dict[int, Dict[str, Any]] = {}
	for v in rows:
		if v.user_id in by_user:
			continue
		lat = float(v.start_latitude) if v.start_latitude is not None else None
		lng = float(v.start_longitude) if v.start_longitude is not None else None
		person = db.query(Person).filter(Person.id == v.person_id).first()
		plats = person_coords(person) if person else (None, None)
		by_user[v.user_id] = {
			"user_id": v.user_id,
			"visit_id": v.id,
			"status": v.status,
			"person_id": v.person_id,
			"person_name": (person.alias_name or "").strip() if person else None,
			"visit_latitude": lat,
			"visit_longitude": lng,
			"customer_latitude": plats[0],
			"customer_longitude": plats[1],
			"started_at": v.started_at.isoformat() if v.started_at else None,
		}
	return {"plan_date": d.isoformat(), "markers": list(by_user.values())}


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
