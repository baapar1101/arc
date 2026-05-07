"""
خلاصهٔ بازرگانی کالا بر اساس اقلام فاکتور خرید/فروش که حوالهٔ انبار تأییدشده از همان فاکتور دارند.
قیمت‌ها با همان منطق تسعیر سندها (اولویت extra_info.fx و سپس نرخ تاریخ سند نسبت به ارز پایه) به ارز پایه تبدیل می‌شوند.
"""
from __future__ import annotations

import logging
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_, exists, or_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.warehouse_document import WarehouseDocument

from app.core.responses import ApiError
from app.services.invoice_service import (
    INVOICE_PURCHASE,
    INVOICE_SALES,
    _movement_from_type,
    _person_id_from_header,
)
from app.services.person_service import _document_to_base_currency_rate

logger = logging.getLogger(__name__)

ALLOWED_BUCKETS = frozenset({"day", "week", "month"})


def _build_base_currency_payload(db: Session, b: Business) -> Optional[Dict[str, Any]]:
	bid = getattr(b, "default_currency_id", None)
	if bid is None:
		return None
	curr = db.query(Currency).filter(Currency.id == int(bid)).first()
	if curr is None:
		return {
			"id": int(bid),
			"code": "",
			"title": "",
			"symbol": "",
			"decimal_places": 2,
		}
	return {
		"id": int(bid),
		"code": getattr(curr, "code", "") or "",
		"title": getattr(curr, "title", "") or getattr(curr, "name", "") or "",
		"symbol": getattr(curr, "symbol", "") or "",
		"decimal_places": int(getattr(curr, "decimal_places", 2) or 2),
	}


def _line_passes_inventory_filters(line: InvoiceItemLine, doc: Document) -> bool:
	info = line.extra_info or {}
	doc_extra = doc.extra_info or {}
	try:
		if info.get("inventory_posted") is False:
			return False
	except Exception:
		pass
	if doc_extra.get("post_inventory") is False:
		return False
	if info.get("inventory_tracked") is False:
		return False
	return True


def _effective_movement(line: InvoiceItemLine, doc: Document) -> Optional[str]:
	info = line.extra_info or {}
	mov = info.get("movement")
	if mov in ("in", "out"):
		return str(mov)
	inv_move, _ = _movement_from_type(doc.document_type)
	return inv_move


def _commercial_lane(doc_type: str, movement: Optional[str]) -> Optional[str]:
	if movement not in ("in", "out"):
		return None
	if doc_type == INVOICE_PURCHASE and movement == "in":
		return "purchase"
	if doc_type == INVOICE_SALES and movement == "out":
		return "sale"
	return None


def _net_unit_ex_tax_doc_currency(line: InvoiceItemLine) -> Optional[Decimal]:
	info = line.extra_info or {}
	try:
		qty = Decimal(str(line.quantity or 0))
	except Exception:
		return None
	if qty <= 0:
		return None
	try:
		unit_price = Decimal(str(info.get("unit_price", 0) or 0))
		line_discount = Decimal(str(info.get("line_discount", 0) or 0))
	except Exception:
		return None
	net = qty * unit_price - line_discount
	if net <= 0 and unit_price > 0:
		return unit_price
	if net <= 0:
		return None
	q = (net / qty).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)
	return q


def _bucket_key(bucket: str, d: date) -> Tuple[str, str]:
	if bucket == "day":
		k = d.isoformat()
		return k, k
	if bucket == "week":
		iso = d.isocalendar()
		k = f"{iso.year}-W{iso.week:02d}"
		return k, k
	if bucket == "month":
		k = d.strftime("%Y-%m")
		return k, k
	raise ValueError(bucket)


def _person_display_name(p: Optional[Person]) -> Optional[str]:
	if not p:
		return None
	cn = getattr(p, "company_name", None)
	if cn and str(cn).strip():
		return str(cn).strip()
	fn = getattr(p, "first_name", None) or ""
	ln = getattr(p, "last_name", None) or ""
	part = (" ".join(x for x in (fn.strip(), ln.strip()) if x)).strip()
	if part:
		return part
	al = getattr(p, "alias_name", None)
	if al and str(al).strip():
		return str(al).strip()
	return None


def _dec_to_float(d: Optional[Decimal]) -> Optional[float]:
	if d is None:
		return None
	try:
		return float(d)
	except Exception:
		return None


@dataclass
class _Evt:
	line_id: int
	document_id: int
	document_code: str
	document_date: date
	lane: str
	person_id: Optional[int]
	person_name: Optional[str]
	quantity: Decimal
	unit_doc: Decimal
	unit_base: Decimal
	fx_rate: Decimal
	doc_currency_id: int


def _load_persons_bulk(db: Session, business_id: int, ids: List[int]) -> Dict[int, Person]:
	if not ids:
		return {}
	uniq = sorted({int(x) for x in ids if x and int(x) > 0})
	if not uniq:
		return {}
	rows = db.query(Person).filter(and_(Person.business_id == business_id, Person.id.in_(uniq))).all()
	return {int(p.id): p for p in rows}


def get_product_commercial_insights(
	db: Session,
	business_id: int,
	product_id: int,
	date_from: Optional[date],
	date_to: Optional[date],
	bucket: str,
) -> Dict[str, Any]:
	bucket = str(bucket or "month").strip().lower()
	if bucket not in ALLOWED_BUCKETS:
		raise ApiError("BAD_BUCKET", "bucket باید یکی از day|week|month باشد", http_status=422)

	proc = db.query(Product).filter(and_(Product.id == int(product_id), Product.business_id == int(business_id))).first()
	if not proc:
		raise ApiError("NOT_FOUND", "محصول یافت نشد", http_status=404)

	b = db.query(Business).filter(Business.id == int(business_id)).first()
	if not b:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)

	base_currency_payload = _build_base_currency_payload(db, b)

	if not bool(getattr(proc, "track_inventory", False)):
		out = _empty_payload(
			proc,
			business_id,
			date_from,
			date_to,
			reason_not_eligible="کالای بدون کنترل موجودی — گزارش مبتنی بر حوالهٔ انبار معنا ندارد.",
		)
		out["base_currency"] = base_currency_payload
		return out

	base_id = getattr(b, "default_currency_id", None)
	if base_id is None:
		out = _empty_payload(proc, business_id, date_from, date_to, reason_not_eligible="ارز پایه برای کسب‌وکار تنظیم نشده است.")
		out["base_currency"] = base_currency_payload
		return out

	if date_to is None:
		date_to = date.today()
	if date_from is None:
		date_from = date_to - timedelta(days=365)
	if date_from > date_to:
		raise ApiError("BAD_RANGE", "date_from نمی‌تواند بعد از date_to باشد", http_status=422)

	wh_exists = exists().where(
		and_(
			WarehouseDocument.business_id == int(business_id),
			WarehouseDocument.source_document_id == Document.id,
			WarehouseDocument.status == "posted",
			or_(WarehouseDocument.source_type.is_(None), WarehouseDocument.source_type == "invoice"),
		)
	)

	q = (
		db.query(InvoiceItemLine, Document)
		.join(Document, Document.id == InvoiceItemLine.document_id)
		.filter(
			and_(
				Document.business_id == business_id,
				Document.is_proforma == False,  # noqa: E712
				InvoiceItemLine.product_id == int(product_id),
				Document.document_type.in_({INVOICE_PURCHASE, INVOICE_SALES}),
				Document.document_date >= date_from,
				Document.document_date <= date_to,
			),
			wh_exists,
		)
		.order_by(
			Document.document_date.asc(),
			Document.registered_at.asc(),
			Document.id.asc(),
			InvoiceItemLine.id.asc(),
		)
	)

	raw_rows = q.all()

	p_ids: List[int] = []
	for line, doc in raw_rows:
		pid = _person_id_from_header({"extra_info": doc.extra_info})
		if pid:
			p_ids.append(pid)
	ps_map = _load_persons_bulk(db, business_id, p_ids)

	rate_cache: Dict[int, Decimal] = {}
	events: List[_Evt] = []

	for line, doc in raw_rows:
		if not _line_passes_inventory_filters(line, doc):
			continue
		mov = _effective_movement(line, doc)
		lane = _commercial_lane(str(doc.document_type or ""), mov)
		if lane is None:
			continue

		qty_dec = Decimal(str(line.quantity or 0))
		if qty_dec <= 0:
			continue
		unit_doc = _net_unit_ex_tax_doc_currency(line)
		if unit_doc is None:
			logger.debug(
				"product_commercial_insights: missing unit price line=%s doc=%s",
				line.id,
				doc.id,
			)
			continue
		try:
			rate = _document_to_base_currency_rate(
				db,
				int(business_id),
				int(base_id),
				doc,
				rate_cache=rate_cache,
			)
		except Exception:
			rate = Decimal(1)
		unit_base = (unit_doc * rate).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)

		pid = _person_id_from_header({"extra_info": doc.extra_info})
		pobj = ps_map.get(int(pid)) if pid else None
		pname = _person_display_name(pobj)

		events.append(
			_Evt(
				line_id=int(line.id),
				document_id=int(doc.id),
				document_code=str(doc.code or ""),
				document_date=doc.document_date,
				lane=lane,
				person_id=int(pid) if pid else None,
				person_name=pname,
				quantity=qty_dec,
				unit_doc=unit_doc,
				unit_base=unit_base,
				fx_rate=rate,
				doc_currency_id=int(doc.currency_id),
			)
		)

	if not events:
		out = _empty_payload(proc, business_id, date_from, date_to, reason_not_eligible=None)
		out["eligible"] = True
		out["meta"]["note"] = (
			"در این بازه، فاکتور خرید/فروش دارای حوالهٔ انبار تأییدشده برای این کالا یافت نشد."
		)
		out["base_currency"] = base_currency_payload
		return out

	agg: Dict[str, Dict[str, Any]] = {}
	for e in events:
		bk, bl = _bucket_key(bucket, e.document_date)
		if bk not in agg:
			agg[bk] = {
				"bucket": bk,
				"bucket_label": bl,
				"purchase_qty": Decimal(0),
				"purchase_weighted_base": Decimal(0),
				"purchase_tx": 0,
				"sale_qty": Decimal(0),
				"sale_weighted_base": Decimal(0),
				"sale_tx": 0,
			}
		a = agg[bk]
		if e.lane == "purchase":
			a["purchase_qty"] += e.quantity
			a["purchase_weighted_base"] += e.quantity * e.unit_base
			a["purchase_tx"] += 1
		else:
			a["sale_qty"] += e.quantity
			a["sale_weighted_base"] += e.quantity * e.unit_base
			a["sale_tx"] += 1

	chart = []
	for bk in sorted(agg.keys()):
		a = agg[bk]
		pq = a["purchase_qty"]
		sq = a["sale_qty"]
		chart.append(
			{
				"bucket": a["bucket"],
				"bucket_label": a["bucket_label"],
				"avg_purchase_base": _dec_to_float(
					(a["purchase_weighted_base"] / pq).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)
					if pq > 0
					else None
				),
				"avg_sale_base": _dec_to_float(
					(a["sale_weighted_base"] / sq).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)
					if sq > 0
					else None
				),
				"purchase_qty": _dec_to_float(pq),
				"sale_qty": _dec_to_float(sq),
				"purchase_transactions": int(a["purchase_tx"]),
				"sale_transactions": int(a["sale_tx"]),
			}
		)

	def _last(lane: str) -> Optional[_Evt]:
		for e in reversed(events):
			if e.lane == lane:
				return e
		return None

	def _party_stats(lane: str) -> Dict[int, Dict[str, Any]]:
		m: Dict[int, Dict[str, Any]] = defaultdict(
			lambda: {"person_id": 0, "name": "", "qty": Decimal(0), "weighted_base": Decimal(0), "last_date": None}
		)
		for e in events:
			if e.lane != lane or not e.person_id:
				continue
			row = m[int(e.person_id)]
			row["person_id"] = int(e.person_id)
			row["name"] = e.person_name or ""
			row["qty"] += e.quantity
			row["weighted_base"] += e.quantity * e.unit_base
			ld = row["last_date"]
			if ld is None or e.document_date >= ld:
				row["last_date"] = e.document_date
		return dict(m)

	def _top_parties(lane: str, n: int = 5) -> List[Dict[str, Any]]:
		stats = _party_stats(lane)
		items = list(stats.values())
		items.sort(key=lambda x: (x["qty"], x["last_date"] or date.min), reverse=True)
		outp: List[Dict[str, Any]] = []
		for it in items[:n]:
			qv = it["qty"]
			wb = it["weighted_base"]
			avg = (wb / qv).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP) if qv > 0 else None
			outp.append(
				{
					"person_id": int(it["person_id"]),
					"name": it["name"] or None,
					"total_qty": _dec_to_float(qv),
					"avg_unit_price_base": _dec_to_float(avg),
					"last_date": it["last_date"].isoformat() if it["last_date"] else None,
				}
			)
		return outp

	def _serialize_evt(e: _Evt) -> Dict[str, Any]:
		return {
			"invoice_item_line_id": e.line_id,
			"document_id": e.document_id,
			"document_code": e.document_code,
			"document_date": e.document_date.isoformat(),
			"lane": e.lane,
			"person_id": e.person_id,
			"person_name": e.person_name,
			"quantity": _dec_to_float(e.quantity),
			"unit_price_document_currency": _dec_to_float(e.unit_doc),
			"unit_price_base_currency": _dec_to_float(e.unit_base),
			"fx_rate_document_to_base": _dec_to_float(e.fx_rate),
			"document_currency_id": e.doc_currency_id,
		}

	last_p = _last("purchase")
	last_s = _last("sale")
	recent = [_serialize_evt(x) for x in reversed(events[-25:])]
	recent.reverse()

	sum_p_qty = sum((e.quantity for e in events if e.lane == "purchase"), start=Decimal(0))
	sum_s_qty = sum((e.quantity for e in events if e.lane == "sale"), start=Decimal(0))

	dc_decimals = int(base_currency_payload.get("decimal_places") or 2)

	return {
		"eligible": True,
		"product_id": int(product_id),
		"base_currency": base_currency_payload,
		"date_from": date_from.isoformat(),
		"date_to": date_to.isoformat(),
		"buckets": bucket,
		"meta": {
			"note": "فقط فاکتورهایی که حوالهٔ انبار با وضعیت «تأیید» و مبدا فاکتور دارند لحاظ شده‌اند. "
			"قیمت واحد خالص (قبل از مالیات) بر مبنای «مقدار × قیمت واحد − تخفیف ردیف» است. "
			"تبدیل به ارز پایه مطابق تسعیر ثبت‌شده روی سند و در نبود آن، نرخ تاریخ سند است.",
			"price_decimal_places": dc_decimals,
		},
		"totals": {
			"purchase_qty": _dec_to_float(sum_p_qty),
			"sale_qty": _dec_to_float(sum_s_qty),
			"purchase_lines": sum(1 for e in events if e.lane == "purchase"),
			"sale_lines": sum(1 for e in events if e.lane == "sale"),
		},
		"last_purchase": _serialize_last(last_p, base_currency_payload),
		"last_sale": _serialize_last(last_s, base_currency_payload),
		"top_suppliers": _top_parties("purchase"),
		"top_buyers": _top_parties("sale"),
		"recent_events": recent,
		"chart": chart,
	}


def _serialize_last(e: Optional[_Evt], base_currency: Dict[str, Any]) -> Optional[Dict[str, Any]]:
	if e is None:
		return None
	return {
		"document_id": e.document_id,
		"document_code": e.document_code,
		"document_date": e.document_date.isoformat(),
		"person_id": e.person_id,
		"person_name": e.person_name,
		"quantity": _dec_to_float(e.quantity),
		"unit_price_document_currency": _dec_to_float(e.unit_doc),
		"unit_price_base_currency": _dec_to_float(e.unit_base),
		"fx_rate_document_to_base": _dec_to_float(e.fx_rate),
		"document_currency_id": e.doc_currency_id,
		"base_currency": base_currency,
	}


def _empty_payload(
	proc: Product,
	business_id: int,
	date_from: Optional[date],
	date_to: Optional[date],
	*,
	reason_not_eligible: Optional[str],
) -> Dict[str, Any]:
	df = (date_from or (date.today() - timedelta(days=365))).isoformat()
	dt = (date_to or date.today()).isoformat()
	return {
		"eligible": False,
		"product_id": int(proc.id),
		"base_currency": None,
		"date_from": df,
		"date_to": dt,
		"buckets": "month",
		"meta": {
			"note": reason_not_eligible or "",
			"price_decimal_places": 2,
		},
		"totals": {
			"purchase_qty": None,
			"sale_qty": None,
			"purchase_lines": 0,
			"sale_lines": 0,
		},
		"last_purchase": None,
		"last_sale": None,
		"top_suppliers": [],
		"top_buyers": [],
		"recent_events": [],
		"chart": [],
	}
