"""فاز تجاری پخش مویرگی: Pre-sell، پروموشن، تحویل، بارگیری، پورسانت، پیشنهاد سفارش، ممیزی، دارایی."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.distribution import (
	DistributionCommissionRule,
	DistributionCommissionRun,
	DistributionCustomerAsset,
	DistributionDeliveryStop,
	DistributionDeliveryTrip,
	DistributionFieldVisit,
	DistributionLoadPlan,
	DistributionShelfAudit,
	DistributionTradePromotion,
	DistributionVan,
	DistributionVisitHeartbeat,
	DistributionVisitOrder,
	DistributionUserLiveLocation,
)
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.document import Document
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from app.core.auth_dependency import AuthContext
from app.core.business_calendar import business_day_utc_bounds, business_today
from app.core.responses import ApiError
from app.services import distribution_service as dist_svc
from app.services.distribution_geo import haversine_meters
from app.services.distribution_documents import create_distribution_invoice, document_net_amount, person_label, user_label


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _money(v: Any) -> float:
	try:
		return round(float(v or 0), 2)
	except (TypeError, ValueError):
		return 0.0


def _parse_date(value: Any, field: str = "date") -> date:
	if isinstance(value, date) and not isinstance(value, datetime):
		return value
	try:
		return date.fromisoformat(str(value).strip()[:10])
	except Exception as e:
		raise ApiError("VALIDATION_ERROR", f"Invalid {field}; use YYYY-MM-DD", http_status=400) from e


def _settings(db: Session, business_id: int):
	return dist_svc.get_or_create_distribution_settings(db, business_id)


def _resolve_delivery_warehouse(
	db: Session,
	business_id: int,
	*,
	payload: Optional[Dict[str, Any]] = None,
	trip: Optional[DistributionDeliveryTrip] = None,
) -> Optional[int]:
	"""انبار خروج کالا هنگام تحویل: payload → انبار ون مسیر → تنظیمات پخش → انبار پیش‌فرض/مرکزی."""
	payload = payload or {}
	raw = payload.get("warehouse_id")
	if raw:
		try:
			wid = int(raw)
			if wid > 0:
				return wid
		except (TypeError, ValueError):
			pass

	van_id = int(trip.van_id) if trip and trip.van_id else None
	if van_id:
		van = (
			db.query(DistributionVan)
			.filter(DistributionVan.id == van_id, DistributionVan.business_id == business_id)
			.first()
		)
		if van and van.warehouse_id:
			return int(van.warehouse_id)

	settings = _settings(db, business_id)
	default_src = getattr(settings, "default_source_warehouse_id", None)
	if default_src:
		return int(default_src)

	default_wh = (
		db.query(Warehouse)
		.filter(Warehouse.business_id == business_id, Warehouse.is_default.is_(True))
		.order_by(Warehouse.id.asc())
		.first()
	)
	if default_wh:
		return int(default_wh.id)

	van_wh_ids = [
		row[0]
		for row in db.query(DistributionVan.warehouse_id)
		.filter(DistributionVan.business_id == business_id)
		.all()
		if row[0]
	]
	q = db.query(Warehouse).filter(Warehouse.business_id == business_id)
	if van_wh_ids:
		central = q.filter(~Warehouse.id.in_(van_wh_ids)).order_by(Warehouse.id.asc()).first()
		if central:
			return int(central.id)
	any_wh = q.order_by(Warehouse.id.asc()).first()
	return int(any_wh.id) if any_wh else None


# ---------------------------------------------------------------------------
# promotions
# ---------------------------------------------------------------------------

def promo_to_dict(p: DistributionTradePromotion) -> Dict[str, Any]:
	return {
		"id": p.id,
		"code": p.code,
		"name": p.name,
		"mechanic": p.mechanic,
		"config": p.config or {},
		"valid_from": p.valid_from.isoformat() if p.valid_from else None,
		"valid_to": p.valid_to.isoformat() if p.valid_to else None,
		"territory_id": p.territory_id,
		"route_id": p.route_id,
		"product_ids": p.product_ids or [],
		"is_active": bool(p.is_active),
		"notes": p.notes,
	}


def list_promotions(db: Session, business_id: int, *, active_only: bool = True) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionTradePromotion).filter(DistributionTradePromotion.business_id == business_id)
	if active_only:
		today = business_today(business_id)
		q = q.filter(DistributionTradePromotion.is_active.is_(True))
		q = q.filter(DistributionTradePromotion.valid_from <= today)
		q = q.filter(
			(DistributionTradePromotion.valid_to.is_(None)) | (DistributionTradePromotion.valid_to >= today)
		)
	rows = q.order_by(DistributionTradePromotion.id.desc()).all()
	return [promo_to_dict(r) for r in rows]


def upsert_promotion(db: Session, business_id: int, payload: Dict[str, Any], promo_id: Optional[int] = None) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	mechanic = str(payload.get("mechanic") or "percent_off").strip()
	if mechanic not in ("percent_off", "amount_off", "bxgy", "foc"):
		raise ApiError("VALIDATION_ERROR", "Invalid mechanic", http_status=400)
	if not code or not name:
		raise ApiError("VALIDATION_ERROR", "code and name required", http_status=400)
	config = payload.get("config") if isinstance(payload.get("config"), dict) else {}
	if promo_id:
		row = (
			db.query(DistributionTradePromotion)
			.filter(DistributionTradePromotion.id == promo_id, DistributionTradePromotion.business_id == business_id)
			.first()
		)
		if not row:
			raise ApiError("NOT_FOUND", "Promotion not found", http_status=404)
	else:
		row = DistributionTradePromotion(business_id=business_id, code=code)
		db.add(row)
	row.code = code
	row.name = name
	row.mechanic = mechanic
	row.config = config
	row.valid_from = _parse_date(payload.get("valid_from") or business_today(business_id), "valid_from")
	row.valid_to = _parse_date(payload["valid_to"], "valid_to") if payload.get("valid_to") else None
	row.territory_id = int(payload["territory_id"]) if payload.get("territory_id") else None
	row.route_id = int(payload["route_id"]) if payload.get("route_id") else None
	row.product_ids = payload.get("product_ids") if isinstance(payload.get("product_ids"), list) else None
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	row.notes = (str(payload.get("notes") or "").strip() or None)
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return promo_to_dict(row)


def delete_promotion(db: Session, business_id: int, promo_id: int) -> None:
	dist_svc._ensure_plugin(db, business_id)
	row = (
		db.query(DistributionTradePromotion)
		.filter(DistributionTradePromotion.id == promo_id, DistributionTradePromotion.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Promotion not found", http_status=404)
	db.delete(row)
	db.commit()


def apply_promotions_to_lines(
	db: Session,
	business_id: int,
	raw_lines: List[Dict[str, Any]],
	*,
	promotion_ids: Optional[List[int]] = None,
	visitor_max_discount_percent: float = 0,
) -> Tuple[List[Dict[str, Any]], float, List[int]]:
	"""اعمال پروموشن + سقف تخفیف ویزیتور روی خطوط. خروجی: خطوط، مجموع تخفیف، idهای اعمال‌شده."""
	settings = _settings(db, business_id)
	max_pct = float(getattr(settings, "visitor_max_discount_percent", 0) or 0)
	if visitor_max_discount_percent > 0:
		max_pct = min(max_pct, visitor_max_discount_percent) if max_pct > 0 else visitor_max_discount_percent

	promos: List[DistributionTradePromotion] = []
	if getattr(settings, "enable_promotions", False) and promotion_ids:
		promos = (
			db.query(DistributionTradePromotion)
			.filter(
				DistributionTradePromotion.business_id == business_id,
				DistributionTradePromotion.id.in_([int(x) for x in promotion_ids]),
				DistributionTradePromotion.is_active.is_(True),
			)
			.all()
		)

	out: List[Dict[str, Any]] = []
	discount_total = 0.0
	applied: List[int] = []

	for ln in raw_lines:
		if not isinstance(ln, dict):
			continue
		line = dict(ln)
		pid = int(line.get("product_id") or 0)
		qty = float(line.get("quantity") or 0)
		unit = _money(line.get("unit_price"))
		manual_disc = _money(line.get("line_discount"))
		promo_disc = 0.0

		for p in promos:
			allowed = p.product_ids
			if allowed and isinstance(allowed, list) and pid not in [int(x) for x in allowed if str(x).isdigit() or isinstance(x, int)]:
				continue
			cfg = p.config or {}
			if p.mechanic == "percent_off":
				pct = float(cfg.get("percent") or 0)
				promo_disc += round(qty * unit * pct / 100.0, 2)
				applied.append(p.id)
			elif p.mechanic == "amount_off":
				promo_disc += round(float(cfg.get("amount") or 0) * qty, 2)
				applied.append(p.id)
			elif p.mechanic == "foc":
				# خرید X جایزه Y رایگان روی همان کالا
				buy_q = float(cfg.get("buy_qty") or 0)
				get_q = float(cfg.get("get_qty") or 0)
				if buy_q > 0 and get_q > 0 and qty >= buy_q:
					sets = int(qty // buy_q)
					free = sets * get_q
					promo_disc += round(free * unit, 2)
					applied.append(p.id)
			elif p.mechanic == "bxgy":
				# Buy X Get Y — روی همان SKU مثل foc؛ در غیر این صورت تخفیف معادل get_qty × unit
				buy_q = float(cfg.get("buy_qty") or cfg.get("buy") or 0)
				get_q = float(cfg.get("get_qty") or cfg.get("get") or 0)
				buy_pid = int(cfg.get("buy_product_id") or 0)
				get_pid = int(cfg.get("get_product_id") or 0)
				if buy_pid and buy_pid != pid:
					continue
				if buy_q > 0 and get_q > 0 and qty >= buy_q:
					sets = int(qty // buy_q)
					free = sets * get_q
					if get_pid and get_pid != pid:
						gp = db.query(Product).filter(Product.id == get_pid, Product.business_id == business_id).first()
						from app.services.distribution_documents import _resolve_unit_price
						gunit = _resolve_unit_price(db, business_id, gp, None) if gp else unit
						promo_disc += round(free * gunit, 2)
					else:
						promo_disc += round(free * unit, 2)
					applied.append(p.id)

		# سقف تخفیف دستی ویزیتور
		gross = round(qty * unit, 2)
		if max_pct > 0 and manual_disc > 0:
			cap = round(gross * max_pct / 100.0, 2)
			if manual_disc > cap:
				raise ApiError(
					"DISCOUNT_LIMIT",
					f"line_discount exceeds visitor max {max_pct}%",
					http_status=400,
					details={"max_percent": max_pct, "cap": cap, "requested": manual_disc},
				)

		total_disc = round(manual_disc + promo_disc, 2)
		if total_disc > gross:
			total_disc = gross
		line["line_discount"] = total_disc
		discount_total += total_disc
		out.append(line)

	return out, round(discount_total, 2), sorted(set(applied))


# ---------------------------------------------------------------------------
# pre-sell orders
# ---------------------------------------------------------------------------

ORDER_STATUSES = ("draft", "confirmed", "picking", "loaded", "out_for_delivery", "delivered", "cancelled")


def order_to_dict(o: DistributionVisitOrder, db: Optional[Session] = None) -> Dict[str, Any]:
	d: Dict[str, Any] = {
		"id": o.id,
		"business_id": o.business_id,
		"visit_id": o.visit_id,
		"person_id": o.person_id,
		"user_id": o.user_id,
		"route_id": o.route_id,
		"status": o.status,
		"lines": o.lines or [],
		"document_id": o.document_id,
		"delivery_trip_id": o.delivery_trip_id,
		"requested_delivery_date": o.requested_delivery_date.isoformat() if o.requested_delivery_date else None,
		"promotion_ids": o.promotion_ids or [],
		"discount_total": _money(o.discount_total),
		"net_total": _money(o.net_total),
		"notes": o.notes,
		"extra_info": o.extra_info or {},
		"created_at": o.created_at.isoformat() + "Z" if o.created_at else None,
		"updated_at": o.updated_at.isoformat() + "Z" if o.updated_at else None,
	}
	if db is not None:
		d["person_name"] = person_label(db, o.person_id)
		d["user_name"] = user_label(db, o.user_id)
	return d


def create_visit_order(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
	*,
	auto_confirm: bool = False,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	settings = _settings(db, business_id)
	if not getattr(settings, "enable_presell", False):
		raise ApiError("VALIDATION_ERROR", "Pre-sell is disabled for this business", http_status=400)

	person_id = int(payload.get("person_id") or 0)
	if person_id <= 0:
		raise ApiError("VALIDATION_ERROR", "person_id required", http_status=400)
	person = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
	if not person:
		raise ApiError("NOT_FOUND", "Person not found", http_status=404)

	raw_lines = payload.get("lines") if isinstance(payload.get("lines"), list) else []
	if not raw_lines:
		raise ApiError("VALIDATION_ERROR", "lines required", http_status=400)

	# resolve prices if missing
	from app.services.distribution_documents import _resolve_unit_price

	priced: List[Dict[str, Any]] = []
	for ln in raw_lines:
		if not isinstance(ln, dict):
			continue
		pid = int(ln.get("product_id") or 0)
		qty = float(ln.get("quantity") or 0)
		if pid <= 0 or qty <= 0:
			continue
		product = db.query(Product).filter(Product.id == pid, Product.business_id == business_id).first()
		if not product:
			raise ApiError("NOT_FOUND", f"Product {pid} not found", http_status=404)
		unit = _resolve_unit_price(db, business_id, product, ln.get("unit_price"))
		priced.append({
			"product_id": pid,
			"product_name": product.name,
			"quantity": qty,
			"unit_price": unit,
			"line_discount": _money(ln.get("line_discount")),
			"tax_rate": ln.get("tax_rate"),
		})

	promo_ids = payload.get("promotion_ids") if isinstance(payload.get("promotion_ids"), list) else []
	priced, discount_total, applied = apply_promotions_to_lines(
		db, business_id, priced, promotion_ids=[int(x) for x in promo_ids],
	)

	net = 0.0
	for ln in priced:
		gross = _money(ln["quantity"]) * _money(ln["unit_price"])
		net += max(0.0, gross - _money(ln.get("line_discount")))
	net = round(net, 2)

	visit_id = int(payload["visit_id"]) if payload.get("visit_id") else None
	if visit_id:
		v = db.query(DistributionFieldVisit).filter(
			DistributionFieldVisit.id == visit_id, DistributionFieldVisit.business_id == business_id,
		).first()
		if not v:
			raise ApiError("NOT_FOUND", "Visit not found", http_status=404)

	row = DistributionVisitOrder(
		business_id=business_id,
		visit_id=visit_id,
		person_id=person_id,
		user_id=user_id,
		route_id=int(payload["route_id"]) if payload.get("route_id") else None,
		status="draft",
		lines=priced,
		requested_delivery_date=_parse_date(payload["requested_delivery_date"]) if payload.get("requested_delivery_date") else None,
		promotion_ids=applied,
		discount_total=discount_total,
		net_total=net,
		notes=(str(payload.get("notes") or "").strip() or None),
		extra_info=payload.get("extra_info") if isinstance(payload.get("extra_info"), dict) else None,
	)
	db.add(row)
	db.flush()

	if auto_confirm or bool(payload.get("confirm")):
		_confirm_order_internal(db, business_id, user_id, row)

	db.commit()
	db.refresh(row)
	return order_to_dict(row, db)


def _confirm_order_internal(db: Session, business_id: int, user_id: int, row: DistributionVisitOrder) -> None:
	from app.services.invoice_service import INVOICE_SALES

	if row.status not in ("draft",):
		raise ApiError("VALIDATION_ERROR", f"Cannot confirm order in status {row.status}", http_status=400)

	# از ابتدا پیش‌فاکتور بدون حرکت انبار — نه فاکتور قطعی و flip بعدی
	inv = create_distribution_invoice(
		db,
		business_id,
		user_id,
		invoice_type=INVOICE_SALES,
		person_id=int(row.person_id),
		raw_lines=list(row.lines or []),
		warehouse_id=None,
		description=f"سفارش پیش‌فروش پخش #{row.id}",
		meta={"distribution_visit_order_id": row.id, "presell": True, "visit_id": row.visit_id},
		is_proforma=True,
		post_inventory=False,
	)
	row.document_id = int(inv["id"])
	row.status = "confirmed"
	row.net_total = _money(inv.get("net"))
	row.updated_at = datetime.utcnow()


def confirm_visit_order(db: Session, business_id: int, user_id: int, order_id: int) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	row = db.query(DistributionVisitOrder).filter(
		DistributionVisitOrder.id == order_id, DistributionVisitOrder.business_id == business_id,
	).first()
	if not row:
		raise ApiError("NOT_FOUND", "Order not found", http_status=404)
	_confirm_order_internal(db, business_id, user_id, row)
	db.commit()
	db.refresh(row)
	return order_to_dict(row, db)


def update_order_status(
	db: Session, business_id: int, order_id: int, status: str, *, actor_user_id: int,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	if status not in ORDER_STATUSES:
		raise ApiError("VALIDATION_ERROR", "Invalid status", http_status=400)
	row = db.query(DistributionVisitOrder).filter(
		DistributionVisitOrder.id == order_id, DistributionVisitOrder.business_id == business_id,
	).first()
	if not row:
		raise ApiError("NOT_FOUND", "Order not found", http_status=404)
	row.status = status
	row.updated_at = datetime.utcnow()
	ex = dict(row.extra_info or {})
	ex["status_history"] = list(ex.get("status_history") or []) + [
		{"status": status, "at": datetime.utcnow().isoformat() + "Z", "by": actor_user_id}
	]
	row.extra_info = ex
	db.commit()
	db.refresh(row)
	return order_to_dict(row, db)


def list_visit_orders(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	*,
	status: Optional[str] = None,
	from_date: Optional[date] = None,
	to_date: Optional[date] = None,
	person_id: Optional[int] = None,
) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionVisitOrder).filter(DistributionVisitOrder.business_id == business_id)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	if scope is not None:
		q = q.filter(DistributionVisitOrder.user_id == scope)
	if status:
		q = q.filter(DistributionVisitOrder.status == status)
	if person_id:
		q = q.filter(DistributionVisitOrder.person_id == int(person_id))
	if from_date:
		q = q.filter(func.date(DistributionVisitOrder.created_at) >= from_date)
	if to_date:
		q = q.filter(func.date(DistributionVisitOrder.created_at) <= to_date)
	rows = q.order_by(DistributionVisitOrder.id.desc()).limit(200).all()
	return [order_to_dict(r, db) for r in rows]


# ---------------------------------------------------------------------------
# suggested order
# ---------------------------------------------------------------------------

def suggested_order_for_person(
	db: Session,
	business_id: int,
	person_id: int,
	*,
	lookback_days: int = 60,
	visit_count: int = 4,
) -> Dict[str, Any]:
	"""پیشنهاد سفارش از میانگین InvoiceItemLine فاکتورهای فروش قطعی همان مشتری."""
	dist_svc._ensure_plugin(db, business_id)
	settings = _settings(db, business_id)
	if not getattr(settings, "enable_suggested_order", True):
		return {"person_id": person_id, "lines": [], "disabled": True}

	from adapters.db.models.document_line import DocumentLine
	from adapters.db.models.invoice_item_line import InvoiceItemLine

	since = business_today(business_id) - timedelta(days=max(7, lookback_days))

	doc_id_rows = (
		db.query(DocumentLine.document_id)
		.join(Document, Document.id == DocumentLine.document_id)
		.filter(
			Document.business_id == business_id,
			Document.document_type == "invoice_sales",
			Document.is_proforma.is_(False),
			Document.document_date >= since,
			DocumentLine.person_id == int(person_id),
		)
		.distinct()
		.order_by(DocumentLine.document_id.desc())
		.limit(max(visit_count * 5, 20))
		.all()
	)
	doc_ids = [int(r[0]) for r in doc_id_rows]

	if len(doc_ids) < visit_count:
		extra_docs = (
			db.query(Document)
			.filter(
				Document.business_id == business_id,
				Document.document_type == "invoice_sales",
				Document.is_proforma.is_(False),
				Document.document_date >= since,
			)
			.order_by(Document.document_date.desc(), Document.id.desc())
			.limit(80)
			.all()
		)
		for d in extra_docs:
			ex = d.extra_info or {}
			if int(ex.get("person_id") or 0) == int(person_id) and int(d.id) not in doc_ids:
				doc_ids.append(int(d.id))
			if len(doc_ids) >= visit_count * 3:
				break

	doc_ids = doc_ids[:visit_count]
	if not doc_ids:
		return {
			"person_id": person_id,
			"based_on_invoices": 0,
			"lookback_days": lookback_days,
			"lines": [],
		}

	agg: Dict[int, Dict[str, Any]] = {}
	seen_per_doc: Dict[int, set] = {did: set() for did in doc_ids}
	items = db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id.in_(doc_ids)).all()
	for ln in items:
		pid = int(ln.product_id or 0)
		qty = float(ln.quantity or 0)
		if pid <= 0 or qty <= 0:
			continue
		slot = agg.setdefault(pid, {"product_id": pid, "qty_sum": 0.0, "invoice_count": 0})
		slot["qty_sum"] += qty
		did = int(ln.document_id)
		if pid not in seen_per_doc[did]:
			slot["invoice_count"] += 1
			seen_per_doc[did].add(pid)

	suggested: List[Dict[str, Any]] = []
	n_invoices = len(doc_ids)
	for pid, slot in agg.items():
		product = db.query(Product).filter(Product.id == pid).first()
		den = max(1, int(slot["invoice_count"]))
		avg = round(float(slot["qty_sum"]) / den, 2)
		if avg <= 0:
			continue
		suggested.append({
			"product_id": pid,
			"product_name": (product.name if product else None) or str(pid),
			"suggested_qty": avg,
			"based_on_invoices": den,
			"total_invoices_scoped": n_invoices,
		})
	suggested.sort(key=lambda x: -float(x["suggested_qty"]))
	return {
		"person_id": person_id,
		"based_on_invoices": n_invoices,
		"lookback_days": lookback_days,
		"lines": suggested[:40],
	}



# ---------------------------------------------------------------------------
# delivery trips + POD
# ---------------------------------------------------------------------------

def trip_to_dict(t: DistributionDeliveryTrip, db: Optional[Session] = None, *, include_stops: bool = True) -> Dict[str, Any]:
	d: Dict[str, Any] = {
		"id": t.id,
		"driver_user_id": t.driver_user_id,
		"van_id": t.van_id,
		"trip_date": t.trip_date.isoformat(),
		"status": t.status,
		"notes": t.notes,
		"started_at": t.started_at.isoformat() + "Z" if t.started_at else None,
		"completed_at": t.completed_at.isoformat() + "Z" if t.completed_at else None,
	}
	if db is not None:
		d["driver_name"] = user_label(db, t.driver_user_id)
	if include_stops:
		stops = sorted(t.stops or [], key=lambda s: s.sort_order)
		d["stops"] = [stop_to_dict(s, db) for s in stops]
	return d


def stop_to_dict(s: DistributionDeliveryStop, db: Optional[Session] = None) -> Dict[str, Any]:
	d = {
		"id": s.id,
		"trip_id": s.trip_id,
		"order_id": s.order_id,
		"person_id": s.person_id,
		"sort_order": s.sort_order,
		"status": s.status,
		"pod_confirmed": bool(s.pod_confirmed),
		"pod_signer_name": s.pod_signer_name,
		"pod_note": s.pod_note,
		"pod_photo_file_id": s.pod_photo_file_id,
		"pod_latitude": float(s.pod_latitude) if s.pod_latitude is not None else None,
		"pod_longitude": float(s.pod_longitude) if s.pod_longitude is not None else None,
		"failure_reason": s.failure_reason,
		"completed_at": s.completed_at.isoformat() + "Z" if s.completed_at else None,
	}
	if db is not None:
		d["person_name"] = person_label(db, s.person_id)
	return d


def create_delivery_trip(db: Session, business_id: int, actor_user_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	driver_id = int(payload.get("driver_user_id") or actor_user_id)
	trip_date = _parse_date(payload.get("trip_date") or business_today(business_id))
	order_ids = payload.get("order_ids") if isinstance(payload.get("order_ids"), list) else []
	van_id = int(payload["van_id"]) if payload.get("van_id") else None
	if not van_id:
		driver_van = (
			db.query(DistributionVan)
			.filter(
				DistributionVan.business_id == business_id,
				DistributionVan.user_id == driver_id,
				DistributionVan.is_active.is_(True),
			)
			.first()
		)
		if driver_van:
			van_id = int(driver_van.id)
	trip = DistributionDeliveryTrip(
		business_id=business_id,
		driver_user_id=driver_id,
		van_id=van_id,
		trip_date=trip_date,
		status="draft",
		notes=(str(payload.get("notes") or "").strip() or None),
		created_by_user_id=actor_user_id,
	)
	db.add(trip)
	db.flush()

	sort = 0
	for oid in order_ids:
		order = db.query(DistributionVisitOrder).filter(
			DistributionVisitOrder.id == int(oid), DistributionVisitOrder.business_id == business_id,
		).first()
		if not order:
			continue
		if order.status not in ("confirmed", "picking", "loaded"):
			continue
		stop = DistributionDeliveryStop(
			trip_id=trip.id,
			order_id=order.id,
			person_id=order.person_id,
			sort_order=sort,
			status="pending",
		)
		db.add(stop)
		order.delivery_trip_id = trip.id
		# تا شروع مسیر در وضعیت loaded/confirmed می‌ماند؛ با start_trip → out_for_delivery
		if order.status in ("confirmed", "picking"):
			order.status = "loaded"
		sort += 1

	db.commit()
	db.refresh(trip)
	return trip_to_dict(trip, db)


def list_delivery_trips(
	db: Session, business_id: int, ctx: AuthContext, *, trip_date: Optional[date] = None,
) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionDeliveryTrip).filter(DistributionDeliveryTrip.business_id == business_id)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	if scope is not None and not dist_svc._can_see_full_distribution_catalog(ctx, business_id):
		q = q.filter(DistributionDeliveryTrip.driver_user_id == scope)
	if trip_date:
		q = q.filter(DistributionDeliveryTrip.trip_date == trip_date)
	rows = q.order_by(DistributionDeliveryTrip.trip_date.desc(), DistributionDeliveryTrip.id.desc()).limit(50).all()
	return [trip_to_dict(r, db) for r in rows]


def start_delivery_trip(db: Session, business_id: int, trip_id: int, user_id: int, *, allow_manage: bool = False) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	trip = db.query(DistributionDeliveryTrip).filter(
		DistributionDeliveryTrip.id == trip_id, DistributionDeliveryTrip.business_id == business_id,
	).first()
	if not trip:
		raise ApiError("NOT_FOUND", "Trip not found", http_status=404)
	if int(trip.driver_user_id) != int(user_id) and not allow_manage:
		raise ApiError("FORBIDDEN", "Only assigned driver or manager can start trip", http_status=403)
	if trip.status not in ("draft", "in_progress"):
		raise ApiError("VALIDATION_ERROR", f"Cannot start trip in status {trip.status}", http_status=400)
	trip.status = "in_progress"
	trip.started_at = trip.started_at or datetime.utcnow()
	trip.updated_at = datetime.utcnow()
	for stop in trip.stops or []:
		if stop.order_id:
			order = db.query(DistributionVisitOrder).filter(DistributionVisitOrder.id == stop.order_id).first()
			if order and order.status in ("confirmed", "picking", "loaded"):
				order.status = "out_for_delivery"
				order.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(trip)
	return trip_to_dict(trip, db)


def complete_delivery_stop(
	db: Session, business_id: int, stop_id: int, user_id: int, payload: Dict[str, Any],
) -> Dict[str, Any]:
	from app.services.distribution_documents import finalize_distribution_proforma_invoice

	dist_svc._ensure_plugin(db, business_id)
	stop = (
		db.query(DistributionDeliveryStop)
		.join(DistributionDeliveryTrip)
		.filter(
			DistributionDeliveryStop.id == stop_id,
			DistributionDeliveryTrip.business_id == business_id,
		)
		.first()
	)
	if not stop:
		raise ApiError("NOT_FOUND", "Stop not found", http_status=404)
	if stop.status != "pending":
		raise ApiError("VALIDATION_ERROR", "این توقف قبلاً تکمیل شده است.", http_status=400)
	status = str(payload.get("status") or "delivered").strip()
	if status not in ("delivered", "partial", "failed"):
		raise ApiError("VALIDATION_ERROR", "وضعیت تحویل باید delivered یا partial یا failed باشد.", http_status=400)

	signer = ""
	delivered_lines = payload.get("delivered_lines")
	order = None
	if stop.order_id:
		order = db.query(DistributionVisitOrder).filter(DistributionVisitOrder.id == stop.order_id).first()

	if status in ("delivered", "partial"):
		if not payload.get("pod_confirmed"):
			raise ApiError("VALIDATION_ERROR", "تأیید تحویل (POD) الزامی است.", http_status=400)
		signer = str(payload.get("pod_signer_name") or "").strip()
		if len(signer) < 2:
			raise ApiError("VALIDATION_ERROR", "نام گیرنده برای تأیید تحویل الزامی است.", http_status=400)
		if order and order.document_id:
			wh_id = _resolve_delivery_warehouse(db, business_id, payload=payload, trip=stop.trip)
			if not wh_id:
				raise ApiError(
					"VALIDATION_ERROR",
					"برای ثبت تحویل انبار مشخص نیست. ون مسیر را انتخاب کنید یا انبار پیش‌فرض پخش را در تنظیمات بگذارید.",
					http_status=400,
				)
			raw = None
			if isinstance(delivered_lines, list) and delivered_lines:
				raw = delivered_lines
			elif status == "delivered":
				raw = list(order.lines or [])
			finalize_distribution_proforma_invoice(
				db,
				business_id,
				user_id,
				document_id=int(order.document_id),
				warehouse_id=int(wh_id),
				raw_lines=raw,
				meta={
					"delivery_stop_id": stop.id,
					"pod_signer": signer,
					"delivery_status": status,
				},
			)

	stop.status = status
	stop.completed_at = datetime.utcnow()
	stop.updated_at = datetime.utcnow()
	if status in ("delivered", "partial"):
		stop.pod_confirmed = True
		stop.pod_signer_name = signer[:255]
		stop.pod_note = (str(payload.get("pod_note") or "").strip() or None)
		if payload.get("pod_photo_file_id"):
			stop.pod_photo_file_id = int(payload["pod_photo_file_id"])
		if payload.get("latitude") is not None:
			stop.pod_latitude = float(payload["latitude"])
		if payload.get("longitude") is not None:
			stop.pod_longitude = float(payload["longitude"])
		stop.delivered_qty_snapshot = delivered_lines
		if order:
			order.status = "delivered" if status == "delivered" else "out_for_delivery"
			order.updated_at = datetime.utcnow()
	else:
		stop.failure_reason = (str(payload.get("failure_reason") or "").strip()[:255] or "failed")
		stop.pod_confirmed = False

	# auto-complete trip if all stops done
	trip = stop.trip
	pending = [s for s in (trip.stops or []) if s.status == "pending"]
	if not pending:
		trip.status = "completed"
		trip.completed_at = datetime.utcnow()
		trip.updated_at = datetime.utcnow()

	db.commit()
	db.refresh(stop)
	return stop_to_dict(stop, db)


# ---------------------------------------------------------------------------
# load plans
# ---------------------------------------------------------------------------

def build_load_plan_from_orders(
	db: Session, business_id: int, actor_user_id: int, payload: Dict[str, Any],
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	plan_date = _parse_date(payload.get("plan_date") or business_today(business_id))
	orders = (
		db.query(DistributionVisitOrder)
		.filter(
			DistributionVisitOrder.business_id == business_id,
			DistributionVisitOrder.status.in_(["confirmed", "picking"]),
		)
		.all()
	)
	if payload.get("order_ids"):
		wanted = {int(x) for x in payload["order_ids"]}
		orders = [o for o in orders if o.id in wanted]

	agg: Dict[int, Dict[str, Any]] = {}
	oids: List[int] = []
	for o in orders:
		oids.append(o.id)
		for ln in o.lines or []:
			if not isinstance(ln, dict):
				continue
			pid = int(ln.get("product_id") or 0)
			qty = float(ln.get("quantity") or 0)
			if pid <= 0 or qty <= 0:
				continue
			slot = agg.setdefault(pid, {
				"product_id": pid,
				"product_name": ln.get("product_name"),
				"quantity": 0.0,
			})
			slot["quantity"] = round(slot["quantity"] + qty, 2)
			if not slot.get("product_name"):
				prod = db.query(Product).filter(Product.id == pid).first()
				slot["product_name"] = prod.name if prod else str(pid)

	lines = list(agg.values())
	plan = DistributionLoadPlan(
		business_id=business_id,
		plan_date=plan_date,
		warehouse_id=int(payload["warehouse_id"]) if payload.get("warehouse_id") else None,
		van_id=int(payload["van_id"]) if payload.get("van_id") else None,
		status="draft",
		lines=lines,
		order_ids=oids,
		notes=(str(payload.get("notes") or "").strip() or None),
		created_by_user_id=actor_user_id,
	)
	db.add(plan)
	for o in orders:
		o.status = "picking"
	db.commit()
	db.refresh(plan)
	return load_plan_to_dict(plan)


def load_plan_to_dict(p: DistributionLoadPlan) -> Dict[str, Any]:
	return {
		"id": p.id,
		"plan_date": p.plan_date.isoformat(),
		"warehouse_id": p.warehouse_id,
		"van_id": p.van_id,
		"status": p.status,
		"lines": p.lines or [],
		"order_ids": p.order_ids or [],
		"notes": p.notes,
		"confirmed_at": p.confirmed_at.isoformat() + "Z" if p.confirmed_at else None,
	}


def confirm_load_plan(db: Session, business_id: int, plan_id: int, user_id: int) -> Dict[str, Any]:
	"""تأیید موج بارگیری و بار زدن به ون در صورت وجود van_id."""
	dist_svc._ensure_plugin(db, business_id)
	from app.services.distribution_phase3_service import load_van

	plan = db.query(DistributionLoadPlan).filter(
		DistributionLoadPlan.id == plan_id, DistributionLoadPlan.business_id == business_id,
	).first()
	if not plan:
		raise ApiError("NOT_FOUND", "Load plan not found", http_status=404)
	if plan.status != "draft":
		raise ApiError("VALIDATION_ERROR", "Load plan already confirmed", http_status=400)

	if plan.van_id and plan.lines:
		load_van(
			db,
			business_id,
			user_id,
			int(plan.van_id),
			[
				{"product_id": ln["product_id"], "quantity": ln["quantity"]}
				for ln in plan.lines
				if isinstance(ln, dict)
			],
			source_warehouse_id=plan.warehouse_id,
		)
		for oid in plan.order_ids or []:
			order = db.query(DistributionVisitOrder).filter(DistributionVisitOrder.id == int(oid)).first()
			if order and order.status == "picking":
				order.status = "loaded"

	plan.status = "confirmed"
	plan.confirmed_at = datetime.utcnow()
	plan.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(plan)
	return load_plan_to_dict(plan)


def list_load_plans(db: Session, business_id: int, *, plan_date: Optional[date] = None) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionLoadPlan).filter(DistributionLoadPlan.business_id == business_id)
	if plan_date:
		q = q.filter(DistributionLoadPlan.plan_date == plan_date)
	rows = q.order_by(DistributionLoadPlan.id.desc()).limit(50).all()
	return [load_plan_to_dict(r) for r in rows]


# ---------------------------------------------------------------------------
# GPS trail + live location
# ---------------------------------------------------------------------------

def _live_location_enabled(db: Session, business_id: int) -> bool:
	settings = _settings(db, business_id)
	return bool(getattr(settings, "share_live_location", True))


def upsert_live_location(
	db: Session,
	business_id: int,
	user_id: int,
	latitude: float,
	longitude: float,
	*,
	visit_id: Optional[int] = None,
	commit: bool = False,
) -> Dict[str, Any]:
	"""آخرین نقطه ویزیتور را به‌روز می‌کند و در صورت جابه‌جایی معنادار به trail اضافه می‌کند."""
	now = datetime.utcnow()
	lat = float(latitude)
	lng = float(longitude)
	row = (
		db.query(DistributionUserLiveLocation)
		.filter(
			DistributionUserLiveLocation.business_id == business_id,
			DistributionUserLiveLocation.user_id == user_id,
		)
		.first()
	)
	if row:
		row.latitude = lat
		row.longitude = lng
		row.recorded_at = now
		row.updated_at = now
		if visit_id:
			row.visit_id = int(visit_id)
	else:
		row = DistributionUserLiveLocation(
			business_id=business_id,
			user_id=user_id,
			visit_id=int(visit_id) if visit_id else None,
			latitude=lat,
			longitude=lng,
			recorded_at=now,
			updated_at=now,
		)
		db.add(row)

	last = (
		db.query(DistributionVisitHeartbeat)
		.filter(
			DistributionVisitHeartbeat.business_id == business_id,
			DistributionVisitHeartbeat.user_id == user_id,
		)
		.order_by(DistributionVisitHeartbeat.recorded_at.desc())
		.first()
	)
	should_trail = True
	if last is not None:
		dist_m = haversine_meters(float(last.latitude), float(last.longitude), lat, lng)
		age = (now - last.recorded_at).total_seconds() if last.recorded_at else 999
		if dist_m is not None and dist_m < 20 and age < 90:
			should_trail = False
	if should_trail:
		db.add(
			DistributionVisitHeartbeat(
				business_id=business_id,
				visit_id=int(visit_id) if visit_id else None,
				user_id=user_id,
				latitude=lat,
				longitude=lng,
				recorded_at=now,
			)
		)
	if commit:
		db.commit()
		db.refresh(row)
	return {
		"user_id": user_id,
		"latitude": lat,
		"longitude": lng,
		"visit_id": int(visit_id) if visit_id else (int(row.visit_id) if row.visit_id else None),
		"updated_at": now.isoformat() + "Z",
	}


def report_live_location(
	db: Session,
	business_id: int,
	user_id: int,
	latitude: float,
	longitude: float,
	visit_id: Optional[int] = None,
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	if not _live_location_enabled(db, business_id):
		return {"skipped": True, "reason": "disabled"}
	active_visit_id = int(visit_id) if visit_id else None
	if active_visit_id:
		v = (
			db.query(DistributionFieldVisit)
			.filter(
				DistributionFieldVisit.id == active_visit_id,
				DistributionFieldVisit.business_id == business_id,
			)
			.first()
		)
		if not v or int(v.user_id) != int(user_id) or v.status != "in_progress":
			active_visit_id = None
		else:
			extra = dict(v.extra_info or {})
			extra["live_location"] = {
				"latitude": float(latitude),
				"longitude": float(longitude),
				"updated_at": datetime.utcnow().isoformat() + "Z",
			}
			v.extra_info = extra
			v.start_latitude = float(latitude)
			v.start_longitude = float(longitude)
			v.updated_at = datetime.utcnow()
	data = upsert_live_location(
		db, business_id, user_id, latitude, longitude, visit_id=active_visit_id, commit=True,
	)
	data["skipped"] = False
	return data


def record_heartbeat_trail(
	db: Session,
	business_id: int,
	user_id: int,
	visit_id: Optional[int],
	latitude: float,
	longitude: float,
) -> None:
	upsert_live_location(db, business_id, user_id, latitude, longitude, visit_id=visit_id, commit=False)


def get_visit_trail(db: Session, business_id: int, visit_id: int) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	points = (
		db.query(DistributionVisitHeartbeat)
		.filter(
			DistributionVisitHeartbeat.business_id == business_id,
			DistributionVisitHeartbeat.visit_id == visit_id,
		)
		.order_by(DistributionVisitHeartbeat.recorded_at.asc())
		.limit(2000)
		.all()
	)
	return {
		"visit_id": visit_id,
		"points": [
			{
				"latitude": float(p.latitude),
				"longitude": float(p.longitude),
				"recorded_at": p.recorded_at.isoformat() + "Z",
			}
			for p in points
		],
	}


def get_user_day_trail(db: Session, business_id: int, user_id: int, day: date) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	start, end = business_day_utc_bounds(business_id, day)
	points = (
		db.query(DistributionVisitHeartbeat)
		.filter(
			DistributionVisitHeartbeat.business_id == business_id,
			DistributionVisitHeartbeat.user_id == user_id,
			DistributionVisitHeartbeat.recorded_at >= start,
			DistributionVisitHeartbeat.recorded_at <= end,
		)
		.order_by(DistributionVisitHeartbeat.recorded_at.asc())
		.limit(5000)
		.all()
	)
	return {
		"user_id": user_id,
		"date": day.isoformat(),
		"points": [
			{
				"visit_id": p.visit_id,
				"latitude": float(p.latitude),
				"longitude": float(p.longitude),
				"recorded_at": p.recorded_at.isoformat() + "Z",
			}
			for p in points
		],
	}


# ---------------------------------------------------------------------------
# commission
# ---------------------------------------------------------------------------

def list_commission_rules(db: Session, business_id: int) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	rows = (
		db.query(DistributionCommissionRule)
		.filter(DistributionCommissionRule.business_id == business_id)
		.order_by(DistributionCommissionRule.id.desc())
		.all()
	)
	return [
		{
			"id": r.id,
			"name": r.name,
			"rule_type": r.rule_type,
			"config": r.config or {},
			"is_active": bool(r.is_active),
			"valid_from": r.valid_from.isoformat() if r.valid_from else None,
			"valid_to": r.valid_to.isoformat() if r.valid_to else None,
		}
		for r in rows
	]


def upsert_commission_rule(db: Session, business_id: int, payload: Dict[str, Any], rule_id: Optional[int] = None) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "name required", http_status=400)
	if rule_id:
		row = db.query(DistributionCommissionRule).filter(
			DistributionCommissionRule.id == rule_id, DistributionCommissionRule.business_id == business_id,
		).first()
		if not row:
			raise ApiError("NOT_FOUND", "Rule not found", http_status=404)
	else:
		row = DistributionCommissionRule(business_id=business_id, name=name, config={})
		db.add(row)
	row.name = name
	row.rule_type = str(payload.get("rule_type") or "percent_of_sales")
	row.config = payload.get("config") if isinstance(payload.get("config"), dict) else {"percent": 1}
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	row.valid_from = _parse_date(payload["valid_from"]) if payload.get("valid_from") else None
	row.valid_to = _parse_date(payload["valid_to"]) if payload.get("valid_to") else None
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"name": row.name,
		"rule_type": row.rule_type,
		"config": row.config or {},
		"is_active": bool(row.is_active),
		"valid_from": row.valid_from.isoformat() if row.valid_from else None,
		"valid_to": row.valid_to.isoformat() if row.valid_to else None,
	}


def compute_commission_run(
	db: Session, business_id: int, actor_user_id: int, payload: Dict[str, Any],
) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	user_id = int(payload.get("user_id") or 0)
	if user_id <= 0:
		raise ApiError("VALIDATION_ERROR", "user_id required", http_status=400)
	period_start = _parse_date(payload.get("period_start"))
	period_end = _parse_date(payload.get("period_end") or period_start)
	rule_id = int(payload["rule_id"]) if payload.get("rule_id") else None

	rule = None
	if rule_id:
		rule = db.query(DistributionCommissionRule).filter(
			DistributionCommissionRule.id == rule_id, DistributionCommissionRule.business_id == business_id,
		).first()
	if not rule:
		rule = (
			db.query(DistributionCommissionRule)
			.filter(
				DistributionCommissionRule.business_id == business_id,
				DistributionCommissionRule.is_active.is_(True),
			)
			.order_by(DistributionCommissionRule.id.desc())
			.first()
		)
	if not rule:
		raise ApiError("VALIDATION_ERROR", "No commission rule configured", http_status=400)

	visits = (
		db.query(DistributionFieldVisit)
		.filter(
			DistributionFieldVisit.business_id == business_id,
			DistributionFieldVisit.user_id == user_id,
			DistributionFieldVisit.status == "completed",
			func.date(DistributionFieldVisit.started_at) >= period_start,
			func.date(DistributionFieldVisit.started_at) <= period_end,
		)
		.all()
	)
	sales = 0.0
	counted_doc_ids: set[int] = set()
	for v in visits:
		if v.document_id:
			did = int(v.document_id)
			if did in counted_doc_ids:
				continue
			amt = document_net_amount(db, did)
			if amt is not None:
				sales += float(amt)
				counted_doc_ids.add(did)
	# پیش‌فروش تحویل‌شده: فقط اگر document جداگانه شمرده نشده
	orders = (
		db.query(DistributionVisitOrder)
		.filter(
			DistributionVisitOrder.business_id == business_id,
			DistributionVisitOrder.user_id == user_id,
			DistributionVisitOrder.status == "delivered",
			func.date(DistributionVisitOrder.created_at) >= period_start,
			func.date(DistributionVisitOrder.created_at) <= period_end,
		)
		.all()
	)
	for o in orders:
		if o.document_id and int(o.document_id) in counted_doc_ids:
			continue
		if o.document_id:
			amt = document_net_amount(db, int(o.document_id))
			if amt is not None:
				sales += float(amt)
				counted_doc_ids.add(int(o.document_id))
				continue
		sales += _money(o.net_total)

	cfg = rule.config or {}
	pct = float(cfg.get("percent") or 0)
	commission = round(sales * pct / 100.0, 2)
	# tiered
	tiers = cfg.get("tiers") if isinstance(cfg.get("tiers"), list) else None
	if tiers:
		commission = 0.0
		for t in sorted(tiers, key=lambda x: float(x.get("min_sales") or 0)):
			if sales >= float(t.get("min_sales") or 0):
				commission = round(sales * float(t.get("percent") or 0) / 100.0, 2)

	run = DistributionCommissionRun(
		business_id=business_id,
		user_id=user_id,
		period_start=period_start,
		period_end=period_end,
		rule_id=rule.id,
		sales_amount=round(sales, 2),
		commission_amount=commission,
		status="draft",
		breakdown={
			"visits": len(visits),
			"orders_delivered": len(orders),
			"rule_type": rule.rule_type,
			"percent_applied": pct,
		},
		created_by_user_id=actor_user_id,
	)
	db.add(run)
	db.commit()
	db.refresh(run)
	return {
		"id": run.id,
		"user_id": user_id,
		"user_name": user_label(db, user_id),
		"period_start": period_start.isoformat(),
		"period_end": period_end.isoformat(),
		"sales_amount": _money(run.sales_amount),
		"commission_amount": _money(run.commission_amount),
		"status": run.status,
		"breakdown": run.breakdown,
	}


def list_commission_runs(db: Session, business_id: int) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	rows = (
		db.query(DistributionCommissionRun)
		.filter(DistributionCommissionRun.business_id == business_id)
		.order_by(DistributionCommissionRun.id.desc())
		.limit(100)
		.all()
	)
	return [
		{
			"id": r.id,
			"user_id": r.user_id,
			"user_name": user_label(db, r.user_id),
			"period_start": r.period_start.isoformat(),
			"period_end": r.period_end.isoformat(),
			"sales_amount": _money(r.sales_amount),
			"commission_amount": _money(r.commission_amount),
			"status": r.status,
			"breakdown": r.breakdown,
		}
		for r in rows
	]


# ---------------------------------------------------------------------------
# shelf audit + assets
# ---------------------------------------------------------------------------

def create_shelf_audit(db: Session, business_id: int, user_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	person_id = int(payload.get("person_id") or 0)
	answers = payload.get("answers")
	if person_id <= 0 or not isinstance(answers, (dict, list)):
		raise ApiError("VALIDATION_ERROR", "person_id and answers required", http_status=400)

	# simple score: percent of true/yes answers
	score = None
	flat: List[Any] = []
	if isinstance(answers, dict):
		flat = list(answers.values())
	else:
		flat = answers
	bools = [a for a in flat if isinstance(a, bool)]
	if bools:
		score = round(100.0 * sum(1 for a in bools if a) / len(bools), 1)

	row = DistributionShelfAudit(
		business_id=business_id,
		visit_id=int(payload["visit_id"]) if payload.get("visit_id") else None,
		person_id=person_id,
		user_id=user_id,
		answers=answers,
		score=score,
		photo_file_ids=payload.get("photo_file_ids") if isinstance(payload.get("photo_file_ids"), list) else None,
		notes=(str(payload.get("notes") or "").strip() or None),
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"person_id": row.person_id,
		"visit_id": row.visit_id,
		"score": float(row.score) if row.score is not None else None,
		"answers": row.answers,
		"created_at": row.created_at.isoformat() + "Z",
	}


def list_shelf_audits(
	db: Session,
	business_id: int,
	*,
	person_id: Optional[int] = None,
	visit_id: Optional[int] = None,
	limit: int = 100,
) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionShelfAudit).filter(DistributionShelfAudit.business_id == business_id)
	if person_id:
		q = q.filter(DistributionShelfAudit.person_id == int(person_id))
	if visit_id:
		q = q.filter(DistributionShelfAudit.visit_id == int(visit_id))
	rows = q.order_by(DistributionShelfAudit.id.desc()).limit(max(1, min(limit, 500))).all()
	return [
		{
			"id": r.id,
			"person_id": r.person_id,
			"person_name": person_label(db, r.person_id),
			"visit_id": r.visit_id,
			"user_id": r.user_id,
			"score": float(r.score) if r.score is not None else None,
			"answers": r.answers,
			"notes": r.notes,
			"created_at": r.created_at.isoformat() + "Z" if r.created_at else None,
		}
		for r in rows
	]


def list_customer_assets(db: Session, business_id: int, person_id: Optional[int] = None) -> List[Dict[str, Any]]:
	dist_svc._ensure_plugin(db, business_id)
	q = db.query(DistributionCustomerAsset).filter(DistributionCustomerAsset.business_id == business_id)
	if person_id:
		q = q.filter(DistributionCustomerAsset.person_id == int(person_id))
	rows = q.order_by(DistributionCustomerAsset.id.desc()).limit(200).all()
	return [
		{
			"id": r.id,
			"person_id": r.person_id,
			"person_name": person_label(db, r.person_id),
			"asset_code": r.asset_code,
			"asset_type": r.asset_type,
			"name": r.name,
			"status": r.status,
			"placed_at": r.placed_at.isoformat() if r.placed_at else None,
			"last_checked_at": r.last_checked_at.isoformat() + "Z" if r.last_checked_at else None,
			"notes": r.notes,
		}
		for r in rows
	]


def upsert_customer_asset(db: Session, business_id: int, payload: Dict[str, Any], asset_id: Optional[int] = None) -> Dict[str, Any]:
	dist_svc._ensure_plugin(db, business_id)
	if asset_id:
		row = db.query(DistributionCustomerAsset).filter(
			DistributionCustomerAsset.id == asset_id, DistributionCustomerAsset.business_id == business_id,
		).first()
		if not row:
			raise ApiError("NOT_FOUND", "Asset not found", http_status=404)
	else:
		code = str(payload.get("asset_code") or "").strip()
		if not code:
			raise ApiError("VALIDATION_ERROR", "asset_code required", http_status=400)
		row = DistributionCustomerAsset(
			business_id=business_id,
			person_id=int(payload.get("person_id") or 0),
			asset_code=code,
			asset_type=str(payload.get("asset_type") or "other"),
			name=str(payload.get("name") or code),
		)
		if row.person_id <= 0:
			raise ApiError("VALIDATION_ERROR", "person_id required", http_status=400)
		db.add(row)
	if payload.get("name"):
		row.name = str(payload["name"]).strip()
	if payload.get("asset_type"):
		row.asset_type = str(payload["asset_type"]).strip()
	if payload.get("status"):
		row.status = str(payload["status"]).strip()
	if payload.get("placed_at"):
		row.placed_at = _parse_date(payload["placed_at"])
	if payload.get("notes") is not None:
		row.notes = str(payload.get("notes") or "").strip() or None
	if payload.get("check_now"):
		row.last_checked_at = datetime.utcnow()
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"person_id": row.person_id,
		"person_name": person_label(db, row.person_id),
		"asset_code": row.asset_code,
		"asset_type": row.asset_type,
		"name": row.name,
		"status": row.status,
		"placed_at": row.placed_at.isoformat() if row.placed_at else None,
		"last_checked_at": row.last_checked_at.isoformat() + "Z" if row.last_checked_at else None,
		"notes": row.notes,
	}


# ---------------------------------------------------------------------------
# KPI pack
# ---------------------------------------------------------------------------

def get_commercial_kpi_pack(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	from_date: date,
	to_date: date,
	target_user_id: Optional[int] = None,
) -> Dict[str, Any]:
	"""بسته KPI استاندارد پخش برای داشبورد تجاری."""
	base = dist_svc.get_distribution_reports_dashboard(
		db, business_id, ctx, from_date, to_date, target_user_id,
	)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	uid = target_user_id if target_user_id is not None else scope

	oq = db.query(DistributionVisitOrder).filter(DistributionVisitOrder.business_id == business_id)
	oq = oq.filter(func.date(DistributionVisitOrder.created_at) >= from_date)
	oq = oq.filter(func.date(DistributionVisitOrder.created_at) <= to_date)
	if uid is not None:
		oq = oq.filter(DistributionVisitOrder.user_id == int(uid))
	orders = oq.all()
	presell_count = len(orders)
	presell_net = sum(_money(o.net_total) for o in orders)
	delivered = sum(1 for o in orders if o.status == "delivered")

	completed = int((base.get("visits") or {}).get("completed") or 0)
	orders_outcome = int(((base.get("visits") or {}).get("by_outcome") or {}).get("order") or 0)
	sales = float((base.get("visits") or {}).get("sales_linked_net_total") or 0)
	drop_size = round(sales / orders_outcome, 2) if orders_outcome else None

	audits = (
		db.query(DistributionShelfAudit)
		.filter(
			DistributionShelfAudit.business_id == business_id,
			func.date(DistributionShelfAudit.created_at) >= from_date,
			func.date(DistributionShelfAudit.created_at) <= to_date,
		)
		.all()
	)
	avg_shelf = None
	scored = [float(a.score) for a in audits if a.score is not None]
	if scored:
		avg_shelf = round(sum(scored) / len(scored), 1)

	return {
		**base,
		"kpi": {
			"coverage_percent": (base.get("visits") or {}).get("coverage_percent"),
			"strike_rate_percent": (base.get("visits") or {}).get("order_rate_percent"),
			"drop_size": drop_size,
			"sales_linked_net_total": sales,
			"completed_visits": completed,
			"presell_orders": presell_count,
			"presell_net_total": round(presell_net, 2),
			"presell_delivered": delivered,
			"settlement_collected_total": (base.get("settlements") or {}).get("collected_total"),
			"settlement_variance_abs": (base.get("settlements") or {}).get("variance_abs_total"),
			"shelf_audit_avg_score": avg_shelf,
			"shelf_audit_count": len(audits),
		},
	}
