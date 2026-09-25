"""عملیات میدانی پیشرفته پخش: چرخه ویزیت، مشتری ۳۶۰، لات ون، آفلاین، راه‌اندازی."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from adapters.db.models.distribution import (
	DistributionAssortment,
	DistributionCustomerAsset,
	DistributionCustomerProfile,
	DistributionFieldVisit,
	DistributionRoute,
	DistributionRouteAssignment,
	DistributionRouteStop,
	DistributionShelfAudit,
	DistributionTerritory,
	DistributionVan,
	DistributionVanLot,
	DistributionVisitOrder,
)
from adapters.db.models.document import Document
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.product_general_barcode_alias import ProductGeneralBarcodeAlias
from adapters.db.models.price_list import PriceItem, PriceList
from app.core.auth_dependency import AuthContext
from app.core.business_calendar import business_today
from app.core.responses import ApiError
from app.services import distribution_service as dist_svc
from app.services.distribution_documents import person_label, user_label, _money, _resolve_unit_price
from app.services.distribution_geo import person_coords

NO_EXPIRY = date(9999, 12, 31)

FREQUENCIES = ("weekly", "biweekly", "monthly")
CUSTOMER_CLASSES = ("A", "B", "C")
OUTLET_TYPES = ("grocery", "supermarket", "horeca", "kiosk", "wholesale", "other")
NAV_PROVIDERS = ("neshan", "google", "waze")

CLASS_DEFAULT_FREQUENCY = {"A": "weekly", "B": "biweekly", "C": "monthly"}

NO_ORDER_REASONS = [
	{"code": "closed", "fa": "فروشگاه بسته بود", "en": "Outlet closed"},
	{"code": "no_need", "fa": "نیازی به کالا نبود", "en": "No stock need"},
	{"code": "competitor", "fa": "رقیب تخفیف داد", "en": "Competitor offer"},
	{"code": "credit", "fa": "نسیه / اعتبار", "en": "Credit issue"},
	{"code": "no_decision", "fa": "تصمیم نگرفت", "en": "No decision"},
	{"code": "other", "fa": "سایر", "en": "Other"},
]
RETURN_REASONS = [
	{"code": "expired", "fa": "منقضی", "en": "Expired"},
	{"code": "damaged", "fa": "آسیب‌دیده", "en": "Damaged"},
	{"code": "commercial", "fa": "مرجوعی تجاری", "en": "Commercial return"},
	{"code": "wrong_item", "fa": "کالای اشتباه", "en": "Wrong item"},
	{"code": "near_expiry", "fa": "نزدیک انقضا", "en": "Near expiry"},
	{"code": "other", "fa": "سایر", "en": "Other"},
]
DELIVERY_FAIL_REASONS = [
	{"code": "closed", "fa": "بسته بود", "en": "Closed"},
	{"code": "refused", "fa": "تحویل رد شد", "en": "Refused"},
	{"code": "address", "fa": "آدرس نادرست", "en": "Wrong address"},
	{"code": "shortage", "fa": "کسری بار", "en": "Shortage"},
	{"code": "other", "fa": "سایر", "en": "Other"},
]


def reason_catalog() -> Dict[str, Any]:
	return {
		"no_order": NO_ORDER_REASONS,
		"return": RETURN_REASONS,
		"delivery_fail": DELIVERY_FAIL_REASONS,
		"frequencies": list(FREQUENCIES),
		"customer_classes": list(CUSTOMER_CLASSES),
		"outlet_types": list(OUTLET_TYPES),
		"nav_providers": list(NAV_PROVIDERS),
	}


def _int_ids(raw: Any) -> List[int]:
	if not isinstance(raw, list):
		return []
	out: List[int] = []
	for x in raw:
		try:
			n = int(x)
		except (TypeError, ValueError):
			continue
		if n > 0:
			out.append(n)
	return out


def iso_week_parity(d: date) -> int:
	return int(d.isocalendar()[1]) % 2


def week_of_month(d: date) -> int:
	return (int(d.day) - 1) // 7


def normalize_frequency(value: Any, customer_class: Optional[str] = None) -> str:
	raw = str(value or "").strip().lower()
	if raw in FREQUENCIES:
		return raw
	cls = (customer_class or "").strip().upper()
	return CLASS_DEFAULT_FREQUENCY.get(cls, "weekly")


def stop_due_on(
	plan_date: date,
	*,
	weekday: Optional[int],
	frequency: Optional[str],
	cycle_offset: int = 0,
) -> bool:
	if weekday is not None and int(plan_date.weekday()) != int(weekday):
		return False
	freq = normalize_frequency(frequency)
	off = int(cycle_offset or 0)
	if freq == "weekly":
		return True
	if freq == "biweekly":
		return iso_week_parity(plan_date) == (off % 2)
	return week_of_month(plan_date) == (off % 5)


def previous_due_dates(plan_date: date, *, weekday: Optional[int], frequency: Optional[str], cycle_offset: int, lookback_days: int) -> List[date]:
	out: List[date] = []
	for i in range(1, max(1, lookback_days) + 1):
		d = plan_date - timedelta(days=i)
		if stop_due_on(d, weekday=weekday, frequency=frequency, cycle_offset=cycle_offset):
			out.append(d)
	return out


def profile_to_dict(p: DistributionCustomerProfile) -> Dict[str, Any]:
	return {
		"id": p.id,
		"person_id": p.person_id,
		"customer_class": p.customer_class,
		"visit_frequency": p.visit_frequency,
		"cycle_offset": int(p.cycle_offset or 0),
		"price_list_id": p.price_list_id,
		"outlet_type": p.outlet_type,
		"assortment_id": p.assortment_id,
		"storefront_photo_file_id": p.storefront_photo_file_id,
		"onboarded_at": p.onboarded_at.isoformat() + "Z" if p.onboarded_at else None,
		"notes": p.notes,
	}


def get_profile(db: Session, business_id: int, person_id: int) -> Optional[DistributionCustomerProfile]:
	return (
		db.query(DistributionCustomerProfile)
		.filter(
			DistributionCustomerProfile.business_id == business_id,
			DistributionCustomerProfile.person_id == int(person_id),
		)
		.first()
	)


def upsert_customer_profile(
	db: Session, business_id: int, person_id: int, payload: Dict[str, Any],
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	person = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
	if not person:
		raise ApiError("NOT_FOUND", "Person not found", http_status=404)
	row = get_profile(db, business_id, person_id)
	if not row:
		row = DistributionCustomerProfile(business_id=business_id, person_id=person_id)
		db.add(row)
	if "customer_class" in payload:
		cls = str(payload.get("customer_class") or "").strip().upper() or None
		if cls and cls not in CUSTOMER_CLASSES:
			raise ApiError("VALIDATION_ERROR", "customer_class must be A|B|C", http_status=400)
		row.customer_class = cls
		if cls and not payload.get("visit_frequency"):
			row.visit_frequency = CLASS_DEFAULT_FREQUENCY.get(cls, row.visit_frequency or "weekly")
	if "visit_frequency" in payload:
		row.visit_frequency = normalize_frequency(payload.get("visit_frequency"), row.customer_class)
	if "cycle_offset" in payload:
		row.cycle_offset = max(0, int(payload.get("cycle_offset") or 0))
	if "price_list_id" in payload:
		raw = payload.get("price_list_id")
		row.price_list_id = int(raw) if raw else None
		if row.price_list_id:
			pl = db.query(PriceList).filter(PriceList.id == row.price_list_id, PriceList.business_id == business_id).first()
			if not pl:
				raise ApiError("NOT_FOUND", "Price list not found", http_status=404)
	if "outlet_type" in payload:
		ot = str(payload.get("outlet_type") or "").strip().lower() or None
		if ot and ot not in OUTLET_TYPES:
			raise ApiError("VALIDATION_ERROR", "invalid outlet_type", http_status=400)
		row.outlet_type = ot
	if "assortment_id" in payload:
		raw = payload.get("assortment_id")
		row.assortment_id = int(raw) if raw else None
	if "storefront_photo_file_id" in payload:
		raw = payload.get("storefront_photo_file_id")
		row.storefront_photo_file_id = int(raw) if raw else None
	if "notes" in payload:
		row.notes = (str(payload.get("notes") or "").strip() or None)
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	d = profile_to_dict(row)
	d["person_name"] = person_label(db, person_id)
	return d


def list_customer_profiles(db: Session, business_id: int, *, person_id: Optional[int] = None) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionCustomerProfile).filter(DistributionCustomerProfile.business_id == business_id)
	if person_id:
		q = q.filter(DistributionCustomerProfile.person_id == int(person_id))
	rows = q.order_by(DistributionCustomerProfile.id.desc()).limit(500).all()
	return [{**profile_to_dict(r), "person_name": person_label(db, r.person_id)} for r in rows]


def assortment_to_dict(a: DistributionAssortment) -> Dict[str, Any]:
	return {
		"id": a.id,
		"code": a.code,
		"name": a.name,
		"outlet_type": a.outlet_type,
		"product_ids": a.product_ids or [],
		"must_sell_product_ids": a.must_sell_product_ids or [],
		"is_active": bool(a.is_active),
		"notes": a.notes,
	}


def list_assortments(db: Session, business_id: int) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	rows = (
		db.query(DistributionAssortment)
		.filter(DistributionAssortment.business_id == business_id)
		.order_by(DistributionAssortment.code.asc())
		.all()
	)
	return [assortment_to_dict(r) for r in rows]


def upsert_assortment(db: Session, business_id: int, payload: Dict[str, Any], assortment_id: Optional[int] = None) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()[:50]
	name = str(payload.get("name") or "").strip()[:255]
	if assortment_id:
		row = (
			db.query(DistributionAssortment)
			.filter(DistributionAssortment.id == assortment_id, DistributionAssortment.business_id == business_id)
			.first()
		)
		if not row:
			raise ApiError("NOT_FOUND", "Assortment not found", http_status=404)
	else:
		if not code or not name:
			raise ApiError("VALIDATION_ERROR", "code and name required", http_status=400)
		exists = (
			db.query(DistributionAssortment)
			.filter(DistributionAssortment.business_id == business_id, DistributionAssortment.code == code)
			.first()
		)
		if exists:
			raise ApiError("DUPLICATE", "Assortment code exists", http_status=400)
		row = DistributionAssortment(business_id=business_id, code=code, name=name)
		db.add(row)
	if code:
		row.code = code
	if name:
		row.name = name
	if "outlet_type" in payload:
		row.outlet_type = str(payload.get("outlet_type") or "").strip().lower() or None
	if "product_ids" in payload:
		row.product_ids = _int_ids(payload.get("product_ids"))
	if "must_sell_product_ids" in payload:
		row.must_sell_product_ids = _int_ids(payload.get("must_sell_product_ids"))
	if "is_active" in payload:
		row.is_active = bool(payload.get("is_active"))
	if "notes" in payload:
		row.notes = str(payload.get("notes") or "").strip() or None
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return assortment_to_dict(row)


def delete_assortment(db: Session, business_id: int, assortment_id: int) -> None:
	row = (
		db.query(DistributionAssortment)
		.filter(DistributionAssortment.id == assortment_id, DistributionAssortment.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Assortment not found", http_status=404)
	db.delete(row)
	db.commit()


def must_sell_product_ids_for_person(db: Session, business_id: int, person_id: int) -> List[int]:
	profile = get_profile(db, business_id, person_id)
	if not profile or not profile.assortment_id:
		return []
	asst = (
		db.query(DistributionAssortment)
		.filter(
			DistributionAssortment.id == profile.assortment_id,
			DistributionAssortment.business_id == business_id,
			DistributionAssortment.is_active.is_(True),
		)
		.first()
	)
	if not asst:
		return []
	return _int_ids(asst.must_sell_product_ids)


def resolve_person_price_list_id(db: Session, business_id: int, person_id: Optional[int]) -> Optional[int]:
	if person_id:
		profile = get_profile(db, business_id, int(person_id))
		if profile and profile.price_list_id:
			return int(profile.price_list_id)
	try:
		from app.services.product_fx_price_service import resolve_default_price_list_id

		return resolve_default_price_list_id(db, business_id)
	except Exception:
		return None


def resolve_person_unit_price(db: Session, business_id: int, product: Product, override: Any, person_id: Optional[int] = None) -> float:
	if override is not None:
		try:
			return float(override)
		except (TypeError, ValueError):
			pass
	pl_id = resolve_person_price_list_id(db, business_id, person_id)
	if pl_id:
		item = (
			db.query(PriceItem)
			.filter(PriceItem.price_list_id == int(pl_id), PriceItem.product_id == int(product.id))
			.order_by(PriceItem.min_qty.asc())
			.first()
		)
		if item is not None:
			return float(item.price)
	return _resolve_unit_price(db, business_id, product, None)


def lookup_product_by_barcode(db: Session, business_id: int, barcode: str, *, person_id: Optional[int] = None) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	token = str(barcode or "").strip().lower()
	if not token:
		raise ApiError("VALIDATION_ERROR", "barcode required", http_status=400)
	alias = (
		db.query(ProductGeneralBarcodeAlias)
		.filter(
			ProductGeneralBarcodeAlias.business_id == business_id,
			ProductGeneralBarcodeAlias.token_normalized == token,
		)
		.first()
	)
	product = None
	if alias:
		product = db.query(Product).filter(Product.id == alias.product_id, Product.business_id == business_id).first()
	if product is None:
		product = (
			db.query(Product)
			.filter(
				Product.business_id == business_id,
				func.lower(Product.code) == token,
			)
			.first()
		)
	if product is None:
		raise ApiError("NOT_FOUND", "کالا با این بارکد یافت نشد", http_status=404)
	unit = resolve_person_unit_price(db, business_id, product, None, person_id)
	tax_rate = float(product.sales_tax_rate or 0) if bool(getattr(product, "is_sales_taxable", False)) else 0.0
	return {
		"product_id": product.id,
		"product_name": product.name,
		"code": product.code,
		"barcode": barcode,
		"unit_price": unit,
		"tax_rate": tax_rate,
		"is_sales_taxable": bool(getattr(product, "is_sales_taxable", False)),
		"general_barcodes": getattr(product, "general_barcodes", None),
	}


def _completed_person_days(db: Session, business_id: int, user_id: int, from_date: date, to_date: date) -> set[Tuple[int, date]]:
	rows = (
		db.query(DistributionFieldVisit.person_id, func.date(DistributionFieldVisit.started_at))
		.filter(
			DistributionFieldVisit.business_id == business_id,
			DistributionFieldVisit.user_id == user_id,
			DistributionFieldVisit.status == "completed",
			func.date(DistributionFieldVisit.started_at) >= from_date,
			func.date(DistributionFieldVisit.started_at) <= to_date,
		)
		.all()
	)
	out: set[Tuple[int, date]] = set()
	for pid, d in rows:
		if pid is None or d is None:
			continue
		if isinstance(d, datetime):
			d = d.date()
		out.add((int(pid), d))
	return out


def enrich_daily_plan(
	db: Session,
	business_id: int,
	target_user_id: int,
	plan_date: date,
	items: List[Dict[str, Any]],
) -> Dict[str, Any]:
	settings = dist_svc.get_or_create_distribution_settings(db, business_id)
	carry = bool(getattr(settings, "carry_over_missed_visits", True))
	lookback = max(1, int(getattr(settings, "carry_over_days", 7) or 7))

	assignments = (
		db.query(DistributionRouteAssignment)
		.filter(
			DistributionRouteAssignment.business_id == business_id,
			DistributionRouteAssignment.user_id == target_user_id,
			DistributionRouteAssignment.valid_from <= plan_date,
			or_(DistributionRouteAssignment.valid_to.is_(None), DistributionRouteAssignment.valid_to >= plan_date),
		)
		.all()
	)
	scheduled: List[Dict[str, Any]] = []
	seen_persons: set[int] = set()
	stop_meta: Dict[int, DistributionRouteStop] = {}

	for asn in assignments:
		route = db.query(DistributionRoute).filter(DistributionRoute.id == asn.route_id).first()
		if not route or not route.is_active:
			continue
		stops = db.query(DistributionRouteStop).filter(DistributionRouteStop.route_id == route.id).all()
		for s in stops:
			stop_meta[int(s.id)] = s
			profile = get_profile(db, business_id, int(s.person_id))
			freq = getattr(s, "frequency", None) or (profile.visit_frequency if profile else "weekly")
			offset = int(getattr(s, "cycle_offset", 0) or 0)
			if profile and not getattr(s, "frequency", None):
				offset = int(profile.cycle_offset or 0)
			cls = getattr(s, "customer_class", None) or (profile.customer_class if profile else None)
			due = stop_due_on(plan_date, weekday=s.weekday, frequency=freq, cycle_offset=offset)
			if not due:
				continue
			seen_persons.add(int(s.person_id))
			scheduled.append(_stop_plan_item(db, route, s, plan_date, carried_over=False, customer_class=cls, frequency=freq))

	carried: List[Dict[str, Any]] = []
	if carry:
		done = _completed_person_days(db, business_id, target_user_id, plan_date - timedelta(days=lookback), plan_date)
		for asn in assignments:
			route = db.query(DistributionRoute).filter(DistributionRoute.id == asn.route_id).first()
			if not route or not route.is_active:
				continue
			stops = db.query(DistributionRouteStop).filter(DistributionRouteStop.route_id == route.id).all()
			for s in stops:
				pid = int(s.person_id)
				if pid in seen_persons:
					continue
				profile = get_profile(db, business_id, pid)
				freq = getattr(s, "frequency", None) or (profile.visit_frequency if profile else "weekly")
				offset = int(getattr(s, "cycle_offset", 0) or 0)
				past_dues = previous_due_dates(
					plan_date, weekday=s.weekday, frequency=freq, cycle_offset=offset, lookback_days=lookback,
				)
				missed = False
				for d in past_dues:
					if (pid, d) not in done:
						missed = True
						break
				if not missed:
					continue
				seen_persons.add(pid)
				cls = getattr(s, "customer_class", None) or (profile.customer_class if profile else None)
				carried.append(_stop_plan_item(db, route, s, plan_date, carried_over=True, customer_class=cls, frequency=freq))

	# اگر لیست ورودی از سرویس اصلی آمده، فیلتر روز هفته را با due جایگزین می‌کنیم
	by_stop: Dict[int, Dict[str, Any]] = {}
	for it in scheduled + carried:
		sid = int(it["stop_id"])
		by_stop[sid] = it
	# merge day sort from original items
	for it in items:
		sid = int(it.get("stop_id") or 0)
		if sid in by_stop and it.get("sort_order") is not None:
			by_stop[sid]["sort_order"] = it.get("sort_order")
			by_stop[sid]["day_optimized"] = it.get("day_optimized")
	merged = list(by_stop.values())
	merged.sort(key=lambda x: (0 if not x.get("carried_over") else 1, x.get("sort_order") or 0, x.get("person_id") or 0))
	return {
		"plan_date": plan_date.isoformat(),
		"user_id": target_user_id,
		"items": merged,
		"scheduled_count": len(scheduled),
		"carried_over_count": len(carried),
	}


def _stop_plan_item(
	db: Session,
	route: DistributionRoute,
	s: DistributionRouteStop,
	plan_date: date,
	*,
	carried_over: bool,
	customer_class: Optional[str],
	frequency: Optional[str],
) -> Dict[str, Any]:
	person = db.query(Person).filter(Person.id == s.person_id).first()
	pname = (person.alias_name or "").strip() if person else None
	plats = person_coords(person) if person else (None, None)
	day_sort = s.sort_order
	overrides = getattr(route, "plan_sort_overrides", None) or {}
	day_map = overrides.get(plan_date.isoformat()) if isinstance(overrides, dict) else None
	if isinstance(day_map, dict) and str(s.id) in day_map:
		try:
			day_sort = int(day_map[str(s.id)])
		except (TypeError, ValueError):
			day_sort = s.sort_order
	mobile = None
	if person is not None:
		for cand in (getattr(person, "mobile", None), getattr(person, "phone", None), getattr(person, "mobile_2", None)):
			if cand and str(cand).strip():
				mobile = str(cand).strip()
				break
	return {
		"route_id": route.id,
		"route_code": route.code,
		"route_name": route.name,
		"stop_id": s.id,
		"sort_order": day_sort,
		"catalog_sort_order": s.sort_order,
		"person_id": s.person_id,
		"person_name": pname or str(s.person_id),
		"person_mobile": mobile,
		"weekday": s.weekday,
		"frequency": normalize_frequency(frequency),
		"customer_class": customer_class,
		"latitude": plats[0],
		"longitude": plats[1],
		"day_optimized": isinstance(day_map, dict) and str(s.id) in day_map,
		"carried_over": carried_over,
	}


def customer_360(db: Session, business_id: int, person_id: int, *, user_id: Optional[int] = None) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	person = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
	if not person:
		raise ApiError("NOT_FOUND", "Person not found", http_status=404)
	credit = dist_svc.get_person_credit_summary(db, business_id, person_id)
	try:
		from app.services.distribution_documents import list_person_open_invoices

		invoices = list_person_open_invoices(db, business_id, person_id, limit=8)
	except Exception:
		invoices = []
	visits = (
		db.query(DistributionFieldVisit)
		.filter(DistributionFieldVisit.business_id == business_id, DistributionFieldVisit.person_id == person_id)
		.order_by(DistributionFieldVisit.started_at.desc())
		.limit(8)
		.all()
	)
	last_visit = visits[0] if visits else None
	assets = (
		db.query(DistributionCustomerAsset)
		.filter(DistributionCustomerAsset.business_id == business_id, DistributionCustomerAsset.person_id == person_id)
		.limit(20)
		.all()
	)
	promos: List[Dict[str, Any]] = []
	try:
		from app.services.distribution_commercial_service import list_promotions

		promos = list_promotions(db, business_id, active_only=True)
	except Exception:
		promos = []
	suggested = {}
	try:
		from app.services.distribution_commercial_service import suggested_order_for_person

		suggested = suggested_order_for_person(db, business_id, person_id)
	except Exception:
		suggested = {"lines": []}
	profile = get_profile(db, business_id, person_id)
	must_sell = must_sell_product_ids_for_person(db, business_id, person_id)
	must_sell_named = []
	if must_sell:
		prods = db.query(Product).filter(Product.id.in_(must_sell), Product.business_id == business_id).all()
		pmap = {p.id: p.name for p in prods}
		must_sell_named = [{"product_id": pid, "product_name": pmap.get(pid, str(pid))} for pid in must_sell]
	plats = person_coords(person)
	return {
		"person_id": person_id,
		"person_name": (person.alias_name or "").strip() or str(person_id),
		"mobile": person.mobile or person.phone,
		"address": person.address,
		"latitude": plats[0],
		"longitude": plats[1],
		"credit": credit,
		"profile": profile_to_dict(profile) if profile else None,
		"recent_invoices": invoices[:8] if isinstance(invoices, list) else [],
		"last_visit": {
			"id": last_visit.id,
			"started_at": last_visit.started_at.isoformat() if last_visit.started_at else None,
			"outcome": last_visit.outcome,
			"status": last_visit.status,
			"no_order_reason_code": getattr(last_visit, "no_order_reason_code", None),
		} if last_visit else None,
		"visit_history": [
			{
				"id": v.id,
				"started_at": v.started_at.isoformat() if v.started_at else None,
				"outcome": v.outcome,
				"status": v.status,
			}
			for v in visits
		],
		"assets": [
			{"id": a.id, "name": a.name, "asset_type": a.asset_type, "status": a.status}
			for a in assets
		],
		"active_promotions": promos[:20],
		"suggested_order": suggested,
		"must_sell": must_sell_named,
	}


def enhance_suggested_order(db: Session, business_id: int, person_id: int, base: Dict[str, Any]) -> Dict[str, Any]:
	lines = list(base.get("lines") or [])
	must_ids = must_sell_product_ids_for_person(db, business_id, person_id)
	have = {int(ln.get("product_id") or 0) for ln in lines if isinstance(ln, dict)}
	for pid in must_ids:
		if pid in have:
			for ln in lines:
				if int(ln.get("product_id") or 0) == pid:
					ln["must_sell"] = True
			continue
		prod = db.query(Product).filter(Product.id == pid, Product.business_id == business_id).first()
		if not prod:
			continue
		unit = resolve_person_unit_price(db, business_id, prod, None, person_id)
		lines.append({
			"product_id": pid,
			"product_name": prod.name,
			"suggested_qty": 1,
			"must_sell": True,
			"unit_price": unit,
			"reason": "must_sell",
		})
		have.add(pid)
	# days of cover: if last invoice qty / lookback
	lookback = int(base.get("lookback_days") or 60)
	for ln in lines:
		if not isinstance(ln, dict):
			continue
		qty = float(ln.get("suggested_qty") or 0)
		if qty > 0 and lookback > 0:
			ln["days_of_cover"] = round(lookback / max(1.0, qty), 1)
		if not ln.get("unit_price") and ln.get("product_id"):
			prod = db.query(Product).filter(Product.id == int(ln["product_id"]), Product.business_id == business_id).first()
			if prod:
				ln["unit_price"] = resolve_person_unit_price(db, business_id, prod, None, person_id)
	# van stock cap
	try:
		from app.services.distribution_phase3_service import get_van_for_user, get_van_stock

		# no user here; skip unless later passed
	except Exception:
		pass
	base["lines"] = lines
	base["must_sell_count"] = sum(1 for ln in lines if ln.get("must_sell"))
	return base


def _lot_expiry(d: Optional[date]) -> date:
	return d if d else NO_EXPIRY


def add_van_lot(
	db: Session,
	business_id: int,
	van_id: int,
	product_id: int,
	qty: float,
	*,
	lot_code: Optional[str] = None,
	expiry_date: Optional[date] = None,
	unit_weight_kg: Optional[float] = None,
	unit_volume_m3: Optional[float] = None,
) -> DistributionVanLot:
	code = (str(lot_code or "-").strip() or "-")[:64]
	exp = _lot_expiry(expiry_date)
	row = (
		db.query(DistributionVanLot)
		.filter(
			DistributionVanLot.van_id == van_id,
			DistributionVanLot.product_id == product_id,
			DistributionVanLot.lot_code == code,
			DistributionVanLot.expiry_date == exp,
		)
		.first()
	)
	if row:
		row.quantity = float(row.quantity or 0) + float(qty)
		if unit_weight_kg is not None:
			row.unit_weight_kg = unit_weight_kg
		if unit_volume_m3 is not None:
			row.unit_volume_m3 = unit_volume_m3
		row.updated_at = datetime.utcnow()
		return row
	row = DistributionVanLot(
		business_id=business_id,
		van_id=van_id,
		product_id=product_id,
		lot_code=code,
		expiry_date=exp,
		quantity=float(qty),
		unit_weight_kg=unit_weight_kg,
		unit_volume_m3=unit_volume_m3,
	)
	db.add(row)
	return row


def consume_van_lots_fefo(
	db: Session, van_id: int, product_id: int, qty: float,
) -> List[Dict[str, Any]]:
	need = float(qty)
	if need <= 0:
		return []
	rows = (
		db.query(DistributionVanLot)
		.filter(
			DistributionVanLot.van_id == van_id,
			DistributionVanLot.product_id == product_id,
			DistributionVanLot.quantity > 0,
		)
		.order_by(DistributionVanLot.expiry_date.asc().nullslast(), DistributionVanLot.id.asc())
		.all()
	)
	if not rows:
		return []
	consumed: List[Dict[str, Any]] = []
	for row in rows:
		if need <= 1e-9:
			break
		avail = float(row.quantity or 0)
		take = min(avail, need)
		row.quantity = round(avail - take, 3)
		row.updated_at = datetime.utcnow()
		need -= take
		exp = row.expiry_date
		consumed.append({
			"lot_code": row.lot_code,
			"expiry_date": None if exp == NO_EXPIRY else (exp.isoformat() if exp else None),
			"quantity": take,
		})
	if need > 1e-6:
		raise ApiError(
			"INSUFFICIENT_VAN_LOT",
			f"لات کافی برای کالای {product_id} نیست (کمبود {round(need, 3)})",
			http_status=400,
		)
	return consumed


def van_capacity_snapshot(db: Session, business_id: int, van: DistributionVan) -> Dict[str, Any]:
	lots = db.query(DistributionVanLot).filter(DistributionVanLot.van_id == van.id).all()
	weight = 0.0
	volume = 0.0
	near = 0
	settings = dist_svc.get_or_create_distribution_settings(db, business_id)
	horizon = int(getattr(settings, "near_expiry_days", 14) or 14)
	today = business_today(business_id)
	cutoff = today + timedelta(days=horizon)
	lot_rows = []
	for lot in lots:
		qty = float(lot.quantity or 0)
		if qty <= 0:
			continue
		w = float(lot.unit_weight_kg or 0) * qty
		v = float(lot.unit_volume_m3 or 0) * qty
		weight += w
		volume += v
		exp = lot.expiry_date
		near_flag = bool(exp and exp != NO_EXPIRY and today <= exp <= cutoff)
		expired = bool(exp and exp != NO_EXPIRY and exp < today)
		if near_flag or expired:
			near += 1
		lot_rows.append({
			"id": lot.id,
			"product_id": lot.product_id,
			"lot_code": lot.lot_code,
			"expiry_date": None if exp == NO_EXPIRY else (exp.isoformat() if exp else None),
			"quantity": qty,
			"near_expiry": near_flag,
			"expired": expired,
			"unit_weight_kg": float(lot.unit_weight_kg) if lot.unit_weight_kg is not None else None,
			"unit_volume_m3": float(lot.unit_volume_m3) if lot.unit_volume_m3 is not None else None,
		})
	max_w = float(van.max_weight_kg) if getattr(van, "max_weight_kg", None) else None
	max_v = float(van.max_volume_m3) if getattr(van, "max_volume_m3", None) else None
	return {
		"weight_kg": round(weight, 3),
		"volume_m3": round(volume, 4),
		"max_weight_kg": max_w,
		"max_volume_m3": max_v,
		"weight_util_percent": round(100.0 * weight / max_w, 1) if max_w and max_w > 0 else None,
		"volume_util_percent": round(100.0 * volume / max_v, 1) if max_v and max_v > 0 else None,
		"over_capacity": bool((max_w and weight > max_w + 1e-6) or (max_v and volume > max_v + 1e-9)),
		"near_expiry_lots": near,
		"lots": lot_rows,
	}


def assert_van_capacity(db: Session, business_id: int, van: DistributionVan) -> None:
	snap = van_capacity_snapshot(db, business_id, van)
	if snap["over_capacity"]:
		raise ApiError(
			"VAN_OVER_CAPACITY",
			"ظرفیت وزن یا حجم ون پر شده است.",
			http_status=400,
			details=snap,
		)


def build_offline_pack(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("FORBIDDEN", "user required", http_status=403)
	today = business_today(business_id)
	plan = dist_svc.get_daily_plan(db, business_id, uid, today)
	settings = dist_svc.settings_to_dict(dist_svc.get_or_create_distribution_settings(db, business_id))
	person_ids = [int(it["person_id"]) for it in plan.get("items") or [] if it.get("person_id")]
	persons = []
	if person_ids:
		for p in db.query(Person).filter(Person.id.in_(person_ids)).all():
			persons.append({
				"id": p.id,
				"name": (p.alias_name or "").strip(),
				"mobile": p.mobile or p.phone,
				"address": p.address,
				"latitude": float(p.latitude) if p.latitude is not None else None,
				"longitude": float(p.longitude) if p.longitude is not None else None,
			})
	products = (
		db.query(Product)
		.filter(Product.business_id == business_id)
		.order_by(Product.name.asc())
		.limit(4000)
		.all()
	)
	prod_out = []
	for p in products:
		prod_out.append({
			"id": p.id,
			"name": p.name,
			"code": p.code,
			"general_barcodes": getattr(p, "general_barcodes", None),
			"base_sales_price": float(p.base_sales_price or 0),
			"track_inventory": bool(p.track_inventory),
		})
	van_stock = {}
	try:
		from app.services.distribution_phase3_service import get_van_for_user, get_van_stock

		van = get_van_for_user(db, business_id, uid)
		if van:
			van_stock = get_van_stock(db, business_id, int(van.id))
			van_stock["capacity"] = van_capacity_snapshot(db, business_id, van)
			van_stock["plate_number"] = getattr(van, "plate_number", None)
	except Exception:
		van_stock = {}
	credits = []
	for pid in person_ids[:80]:
		try:
			credits.append(dist_svc.get_person_credit_summary(db, business_id, pid))
		except Exception:
			continue
	promos = []
	try:
		from app.services.distribution_commercial_service import list_promotions

		promos = list_promotions(db, business_id, active_only=True)
	except Exception:
		promos = []
	return {
		"generated_at": datetime.utcnow().isoformat() + "Z",
		"plan_date": today.isoformat(),
		"settings": settings,
		"daily_plan": plan,
		"persons": persons,
		"products": prod_out,
		"van_stock": van_stock,
		"credits": credits,
		"promotions": promos,
		"reason_catalog": reason_catalog(),
	}


def run_setup_wizard(db: Session, business_id: int, actor_user_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	enable_van = bool(payload.get("enable_van_sales"))
	enable_presell = bool(payload.get("enable_presell", True if not enable_van else payload.get("enable_presell")))
	settings_patch = {
		"enable_van_sales": enable_van,
		"enable_presell": enable_presell,
		"enable_promotions": bool(payload.get("enable_promotions", True)),
		"enable_suggested_order": True,
		"auto_apply_promotions": True,
		"carry_over_missed_visits": True,
		"setup_completed": True,
	}
	if payload.get("default_source_warehouse_id"):
		settings_patch["default_source_warehouse_id"] = int(payload["default_source_warehouse_id"])
	if payload.get("nav_provider") in NAV_PROVIDERS:
		settings_patch["nav_provider"] = payload["nav_provider"]
	dist_svc.update_distribution_settings(db, business_id, settings_patch)

	territory = None
	if payload.get("territory_name"):
		tcode = str(payload.get("territory_code") or "T-01")[:50]
		try:
			territory = dist_svc.create_territory(db, business_id, {
				"code": tcode,
				"name": str(payload["territory_name"]).strip()[:255],
			})
		except ApiError as e:
			if int(getattr(e, "status_code", 400) or 400) not in (400, 409):
				raise
			row = (
				db.query(DistributionTerritory)
				.filter(DistributionTerritory.business_id == business_id, DistributionTerritory.code == tcode)
				.first()
			)
			territory = dist_svc.territory_to_dict(row) if row else None

	route = None
	if payload.get("route_name"):
		rcode = str(payload.get("route_code") or "R-01")[:50]
		try:
			route = dist_svc.create_route(db, business_id, {
				"code": rcode,
				"name": str(payload["route_name"]).strip()[:255],
				"territory_id": (territory or {}).get("id") if isinstance(territory, dict) else payload.get("territory_id"),
			})
		except ApiError as e:
			if int(getattr(e, "status_code", 400) or 400) not in (400, 409):
				raise
			row = (
				db.query(DistributionRoute)
				.filter(DistributionRoute.business_id == business_id, DistributionRoute.code == rcode)
				.first()
			)
			route = dist_svc.route_to_dict(row) if row else None

	stops_created = 0
	route_id = (route or {}).get("id") if isinstance(route, dict) else payload.get("route_id")
	person_ids = _int_ids(payload.get("person_ids"))
	weekday = payload.get("weekday")
	freq = normalize_frequency(payload.get("frequency"), payload.get("customer_class"))
	if route_id and person_ids:
		for i, pid in enumerate(person_ids):
			dist_svc.upsert_route_stop(db, business_id, int(route_id), {
				"person_id": pid,
				"sort_order": i + 1,
				"weekday": weekday,
				"frequency": freq,
				"cycle_offset": int(payload.get("cycle_offset") or 0),
				"customer_class": payload.get("customer_class"),
			})
			cls = str(payload.get("customer_class") or "").upper() or None
			if cls:
				upsert_customer_profile(db, business_id, pid, {
					"customer_class": cls,
					"visit_frequency": freq,
				})
			stops_created += 1

	assignment = None
	visitor_id = int(payload.get("visitor_user_id") or 0)
	if route_id and visitor_id:
		assignment = dist_svc.create_assignment(db, business_id, {
			"route_id": int(route_id),
			"user_id": visitor_id,
			"valid_from": (payload.get("valid_from") or business_today(business_id).isoformat()),
		})

	return {
		"ok": True,
		"settings": dist_svc.settings_for_read(db, business_id),
		"territory": territory,
		"route": route,
		"stops_created": stops_created,
		"assignment": assignment,
	}


def onboard_new_outlet(
	db: Session, business_id: int, actor_user_id: int, payload: Dict[str, Any],
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	name = str(payload.get("name") or payload.get("alias_name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "name required", http_status=400)
	from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonType
	from app.services.person_service import create_person

	req = PersonCreateRequest(
		alias_name=name,
		person_types=[PersonType.CUSTOMER],
		mobile=payload.get("mobile"),
		phone=payload.get("phone"),
		address=payload.get("address"),
		city=payload.get("city"),
	)
	created = create_person(db, business_id, req)
	person_id = int(created.get("id") or created.get("person_id") or 0)
	if person_id <= 0:
		raise ApiError("VALIDATION_ERROR", "person create failed", http_status=400)
	lat = payload.get("latitude")
	lng = payload.get("longitude")
	if lat is not None and lng is not None:
		from app.services.distribution_phase3_service import update_person_location

		update_person_location(db, business_id, person_id, float(lat), float(lng))
	profile = upsert_customer_profile(db, business_id, person_id, {
		"customer_class": payload.get("customer_class"),
		"visit_frequency": payload.get("frequency") or payload.get("visit_frequency"),
		"outlet_type": payload.get("outlet_type"),
		"price_list_id": payload.get("price_list_id"),
		"assortment_id": payload.get("assortment_id"),
		"storefront_photo_file_id": payload.get("storefront_photo_file_id"),
		"notes": payload.get("notes"),
	})
	person = db.query(Person).filter(Person.id == person_id).first()
	if person:
		person.updated_at = datetime.utcnow()
		if not getattr(person, "onboarded_at", None):
			pass
	get_profile(db, business_id, person_id)
	prof_row = get_profile(db, business_id, person_id)
	if prof_row:
		prof_row.onboarded_at = datetime.utcnow()
		db.commit()
	stop = None
	route_id = int(payload.get("route_id") or 0)
	if route_id:
		stop = dist_svc.upsert_route_stop(db, business_id, route_id, {
			"person_id": person_id,
			"sort_order": int(payload.get("sort_order") or 99),
			"weekday": payload.get("weekday"),
			"frequency": payload.get("frequency") or profile.get("visit_frequency"),
			"customer_class": payload.get("customer_class"),
		})
	return {
		"person": created,
		"person_id": person_id,
		"profile": profile_to_dict(get_profile(db, business_id, person_id)) if get_profile(db, business_id, person_id) else profile,
		"stop": stop,
	}


def perfect_store_score(answers: Any) -> Optional[float]:
	if not isinstance(answers, dict):
		return None
	weights = {
		"osa": 35.0,
		"shelf_facing": 20.0,
		"price_tag": 15.0,
		"planogram": 15.0,
		"share_of_shelf": 15.0,
	}
	total_w = 0.0
	got = 0.0
	for key, w in weights.items():
		if key not in answers:
			continue
		total_w += w
		val = answers[key]
		if isinstance(val, bool):
			got += w if val else 0.0
		else:
			try:
				pct = max(0.0, min(100.0, float(val)))
				got += w * (pct / 100.0)
			except (TypeError, ValueError):
				pass
	if total_w <= 0:
		return None
	return round(100.0 * got / total_w, 1)


def visitor_scorecard(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	from_date: date,
	to_date: date,
	target_user_id: Optional[int] = None,
) -> Dict[str, Any]:
	from app.services.distribution_commercial_service import get_commercial_kpi_pack

	pack = get_commercial_kpi_pack(db, business_id, ctx, from_date, to_date, target_user_id)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	uid = target_user_id if target_user_id is not None else scope
	vq = db.query(DistributionFieldVisit).filter(DistributionFieldVisit.business_id == business_id)
	if uid is not None:
		vq = vq.filter(DistributionFieldVisit.user_id == int(uid))
	vq = vq.filter(func.date(DistributionFieldVisit.started_at) >= from_date)
	vq = vq.filter(func.date(DistributionFieldVisit.started_at) <= to_date)
	visits = vq.all()
	durations = []
	lines_total = 0
	invoice_count = 0
	for v in visits:
		if v.started_at and v.ended_at:
			durations.append(max(0.0, (v.ended_at - v.started_at).total_seconds()))
		ex = v.extra_info or {}
		nlines = ex.get("lines_count")
		if nlines:
			try:
				lines_total += int(nlines)
				invoice_count += 1
			except (TypeError, ValueError):
				pass
	avg_tis = round(sum(durations) / len(durations) / 60.0, 1) if durations else None
	lpi = round(lines_total / invoice_count, 2) if invoice_count else None
	plan_items = 0
	if uid is not None:
		# پوشش نسبت به برنامهٔ بازه — تقریبی: میانگین اقلام برنامه روزهای بازه
		day = from_date
		n_days = 0
		while day <= to_date and n_days < 14:
			plan = dist_svc.get_daily_plan(db, business_id, int(uid), day)
			plan_items += len(plan.get("items") or [])
			day += timedelta(days=1)
			n_days += 1
	completed = int((pack.get("visits") or {}).get("completed") or 0)
	missed = max(0, plan_items - completed) if plan_items else 0
	kpi = dict(pack.get("kpi") or {})
	kpi.update({
		"time_in_store_avg_minutes": avg_tis,
		"lines_per_invoice": lpi,
		"planned_stops": plan_items,
		"missed_visits": missed,
		"perfect_store_avg": kpi.get("shelf_audit_avg_score"),
	})
	# امتیاز روزانه ساده ۰–۱۰۰
	score = 0.0
	parts = 0
	for key, weight in (("coverage_percent", 30), ("strike_rate_percent", 30), ("perfect_store_avg", 20)):
		val = kpi.get(key)
		if val is not None:
			score += min(100.0, float(val)) * (weight / 100.0)
			parts += weight
	if kpi.get("drop_size"):
		score += min(100.0, float(kpi["drop_size"]) / 10.0) * 0.2
		parts += 20
	kpi["scorecard_score"] = round(100.0 * score / parts, 1) if parts else None
	pack["kpi"] = kpi
	pack["scorecard"] = kpi
	return pack


def apply_auto_promotions_if_needed(
	db: Session,
	business_id: int,
	promotion_ids: Optional[List[int]],
) -> Optional[List[int]]:
	settings = dist_svc.get_or_create_distribution_settings(db, business_id)
	if promotion_ids:
		return promotion_ids
	if not getattr(settings, "auto_apply_promotions", True):
		return promotion_ids
	if not getattr(settings, "enable_promotions", False):
		return promotion_ids
	from app.services.distribution_commercial_service import list_promotions

	items = list_promotions(db, business_id, active_only=True)
	ids = [int(p["id"]) for p in items if p.get("id")]
	return ids or None
