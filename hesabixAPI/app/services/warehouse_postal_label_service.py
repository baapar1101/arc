from __future__ import annotations

import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.person import Person
from adapters.db.models.warehouse_document import WarehouseDocument
from app.core.calendar import CalendarConverter
from app.services.invoice_service import (
	INVOICE_PURCHASE,
	INVOICE_PURCHASE_RETURN,
	INVOICE_SALES,
	INVOICE_SALES_RETURN,
)
from app.services.pdf.template_renderer import load_farsi_font_data_uris
from app.services.warehouse_service import warehouse_document_to_dict

WAREHOUSE_POSTAL_LABEL_MODULE_KEY = "warehouse_documents"
WAREHOUSE_POSTAL_LABEL_SUBTYPE = "postal_label"

_INBOUND_TYPES = frozenset({"receipt", "production_in"})
_OUTBOUND_TYPES = frozenset({"issue", "production_out"})


def postal_label_direction(doc_type: Optional[str]) -> str:
	dt = (doc_type or "").strip().lower()
	if dt in _INBOUND_TYPES:
		return "in"
	if dt in _OUTBOUND_TYPES:
		return "out"
	return "other"


def _page_size_css(paper_size: str, orientation: str) -> str:
	ps = (paper_size or "A6").strip() or "A6"
	ori = (orientation or "portrait").strip().lower()
	if ori not in ("portrait", "landscape"):
		ori = "portrait"
	# ابعاد کاملاً سفارشی (دو مقدار mm) — جهت را جدا نمی‌چسبانیم
	if "mm" in ps and ps.count("mm") >= 2:
		return ps
	return f"{ps} {ori}"


def parse_label_field_flags(query_params: Any) -> Dict[str, bool]:
	def qbool(key: str, default: bool = True) -> bool:
		try:
			v = query_params.get(key)
		except Exception:
			v = None
		if v is None:
			return default
		s = str(v).strip().lower()
		if s in ("0", "false", "no", "off"):
			return False
		if s in ("1", "true", "yes", "on"):
			return True
		return default

	return {
		"show_sender": qbool("show_sender", True),
		"show_receiver": qbool("show_receiver", True),
		"show_warehouse": qbool("show_warehouse", True),
		"show_lines": qbool("show_lines", True),
		"show_delivery": qbool("show_delivery", True),
		"show_tracking": qbool("show_tracking", True),
		"show_source": qbool("show_source", True),
	}


def _person_display_name(p: Person) -> str:
	if p.company_name and str(p.company_name).strip():
		return str(p.company_name).strip()
	parts = [p.first_name or "", p.last_name or ""]
	name = " ".join(x for x in parts if x).strip()
	return name or (p.alias_name or "")


def _person_to_party(p: Person) -> Dict[str, Any]:
	return {
		"name": _person_display_name(p),
		"alias_name": p.alias_name,
		"phone": (p.mobile or p.phone or "") or "",
		"address": (p.address or "") or "",
		"postal_code": (p.postal_code or "") or "",
		"city": (p.city or "") or "",
	}


def _business_party(b: Business) -> Dict[str, Any]:
	addr_lines: List[str] = []
	if b.address:
		addr_lines.append(str(b.address))
	loc = " ".join(x for x in (b.city or "", b.province or "") if x).strip()
	if loc:
		addr_lines.append(loc)
	return {
		"name": (b.name or "") or "",
		"phone": (b.phone or b.mobile or "") or "",
		"address": "\n".join(addr_lines) if addr_lines else "",
		"postal_code": (b.postal_code or "") or "",
		"city": (b.city or "") or "",
	}


def _delivery_party_from_doc(doc_data: Dict[str, Any]) -> Dict[str, Any]:
	return {
		"name": (doc_data.get("recipient_name") or "") or "",
		"phone": (doc_data.get("recipient_phone") or "") or "",
		"address": "",
		"postal_code": "",
		"city": "",
	}


def _lines_summary(doc_data: Dict[str, Any], max_lines: int = 6) -> str:
	lines = doc_data.get("lines") or []
	if not isinstance(lines, list):
		return ""
	parts: List[str] = []
	for ln in lines[:max_lines]:
		if not isinstance(ln, dict):
			continue
		qty = ln.get("quantity", "")
		pname = ln.get("product_name") or str(ln.get("product_id", ""))
		parts.append(f"{pname} × {qty}")
	if len(lines) > max_lines:
		parts.append("…")
	return "، ".join(parts) if parts else ""


def _document_date_display(doc_data: Dict[str, Any], calendar_type: Optional[str]) -> str:
	raw = doc_data.get("document_date")
	if not raw:
		return ""
	try:
		dt = datetime.datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
		ct = (calendar_type or "gregorian").strip().lower()
		if ct == "jalali":
			fd = CalendarConverter.format_datetime(dt, "jalali")
		else:
			fd = CalendarConverter.format_datetime(dt, "gregorian")
		if isinstance(fd, dict):
			return str(fd.get("formatted") or fd.get("date_only") or raw)
		return str(fd or raw)
	except Exception:
		return str(raw)


def _load_invoice_person(
	db: Session,
	business_id: int,
	wh: WarehouseDocument,
) -> tuple[Optional[Person], Optional[str]]:
	if wh.source_type != "invoice" or not wh.source_document_id:
		return None, None
	idoc = (
		db.query(Document)
		.filter(
			and_(
				Document.id == int(wh.source_document_id),
				Document.business_id == int(business_id),
			)
		)
		.first()
	)
	if idoc is None:
		return None, None
	extra = idoc.extra_info or {}
	pid = None
	if isinstance(extra, dict):
		pid = extra.get("person_id")
	if not pid:
		return None, idoc.document_type
	try:
		person = (
			db.query(Person)
			.filter(and_(Person.id == int(pid), Person.business_id == int(business_id)))
			.first()
		)
		return person, idoc.document_type
	except Exception:
		return None, idoc.document_type


def build_warehouse_postal_label_context(
	db: Session,
	*,
	business_id: int,
	wh: WarehouseDocument,
	calendar_type: Optional[str],
	is_fa: bool,
	field_flags: Dict[str, bool],
	paper_size: str,
	orientation: str,
) -> Dict[str, Any]:
	b = db.query(Business).filter(Business.id == int(business_id)).first()
	if b is None:
		raise ValueError("business not found")

	doc_data = dict(warehouse_document_to_dict(db, wh))
	direction = postal_label_direction(wh.doc_type)

	_delivery_method_labels = {
		"warehouse_door": ("تحویل درب انبار", "Warehouse door"),
		"post_regular": ("پست عادی", "Regular post"),
		"post_express": ("پست پیشتاز", "Express post"),
		"freight": ("باربری", "Freight"),
		"bus": ("اتوبوس", "Bus"),
		"tipax": ("تیپاکس", "Tipax"),
		"courier": ("پیک", "Courier"),
	}
	try:
		dm = doc_data.get("delivery_method")
		if dm:
			pair = _delivery_method_labels.get(str(dm), (str(dm), str(dm)))
			doc_data["delivery_method_display"] = pair[0] if is_fa else pair[1]
	except Exception:
		doc_data["delivery_method_display"] = doc_data.get("delivery_method")
	src_person, inv_doc_type = _load_invoice_person(db, business_id, wh)

	sender: Dict[str, Any]
	receiver: Dict[str, Any]

	if direction == "out":
		sender = _business_party(b)
		manual = _delivery_party_from_doc(doc_data)
		if src_person is not None:
			receiver = {
				"name": manual["name"] or _person_display_name(src_person),
				"phone": manual["phone"]
				or (src_person.mobile or src_person.mobile_2 or src_person.mobile_3 or src_person.phone or "")
				or "",
				"address": (src_person.address or "") or "",
				"postal_code": (src_person.postal_code or "") or "",
				"city": (src_person.city or "") or "",
			}
		else:
			receiver = {
				"name": manual["name"] or "",
				"phone": manual["phone"] or "",
				"address": manual.get("address") or "",
				"postal_code": manual.get("postal_code") or "",
				"city": manual.get("city") or "",
			}
	elif direction == "in":
		receiver = _business_party(b)
		wh_name = doc_data.get("warehouse_name_to") or doc_data.get("warehouse_name_from")
		if wh_name:
			receiver["warehouse_name"] = wh_name
		if src_person is not None and inv_doc_type in (
			INVOICE_PURCHASE,
			INVOICE_PURCHASE_RETURN,
			INVOICE_SALES_RETURN,
		):
			sender = _person_to_party(src_person)
		elif src_person is not None and inv_doc_type == INVOICE_SALES:
			sender = _person_to_party(src_person)
		else:
			cname = (doc_data.get("carrier_name") or "").strip()
			sender = {
				"name": cname or ("—" if is_fa else "—"),
				"phone": "",
				"address": "",
				"postal_code": "",
				"city": "",
			}
	else:
		sender = {
			"name": (doc_data.get("warehouse_name_from") or "") or ("—" if is_fa else "—"),
			"phone": "",
			"address": "",
			"postal_code": "",
			"city": "",
		}
		receiver = {
			"name": (doc_data.get("warehouse_name_to") or "") or ("—" if is_fa else "—"),
			"phone": "",
			"address": "",
			"postal_code": "",
			"city": "",
		}

	document_date_display = _document_date_display(doc_data, calendar_type)
	lines_summary = _lines_summary(doc_data)

	if is_fa:
		direction_label = {"in": "ورود به انبار", "out": "خروج از انبار", "other": "سایر حواله‌ها"}.get(direction, direction)
		label_title = "برگه مرسوله پستی"
		sender_caption = "فرستنده"
		receiver_caption = "گیرنده"
	else:
		direction_label = {"in": "Inbound", "out": "Outbound", "other": "Other"}.get(direction, direction)
		label_title = "Postal consignment label"
		sender_caption = "Sender"
		receiver_caption = "Recipient"

	fa_font_url_regular, fa_font_url_bold = load_farsi_font_data_uris()

	ps = (paper_size or "A6").strip() or "A6"
	ori = (orientation or "portrait").strip() or "portrait"

	ctx: Dict[str, Any] = {
		"business_id": business_id,
		"business": _business_party(b),
		"sender": sender,
		"receiver": receiver,
		"sender_caption": sender_caption,
		"receiver_caption": receiver_caption,
		"document": doc_data,
		"direction": direction,
		"direction_label": direction_label,
		"label_title": label_title,
		"document_date_display": document_date_display,
		"lines_summary": lines_summary,
		"generated_at": datetime.datetime.now(),
		"is_fa": is_fa,
		"paper_size": ps,
		"orientation": ori if ori in ("portrait", "landscape") else "portrait",
		"page_size_css": _page_size_css(ps, ori),
		"invoice_document_type": inv_doc_type,
		"fa_font_url_regular": fa_font_url_regular,
		"fa_font_url_bold": fa_font_url_bold,
	}
	ctx.update(field_flags)
	return ctx


def sample_postal_label_context() -> Dict[str, Any]:
	"""نمونه برای schema و پیش‌نمایش قالب."""
	return {
		"business_id": 1,
		"business": {
			"name": "فروشگاه نمونه",
			"phone": "02100000000",
			"address": "تهران، خیابان نمونه",
			"postal_code": "1234567890",
			"city": "تهران",
		},
		"sender": {
			"name": "شرکت الف",
			"phone": "09120000000",
			"address": "تبریز، پلاک ۱",
			"postal_code": "5155555555",
			"city": "تبریز",
		},
		"receiver": {
			"name": "خانم/آقای نمونه",
			"phone": "09121111111",
			"address": "اصفهان، کوچه نمونه",
			"postal_code": "8199999999",
			"city": "اصفهان",
			"warehouse_name": "انبار مرکزی",
		},
		"sender_caption": "فرستنده",
		"receiver_caption": "گیرنده",
		"document": {
			"code": "WH-20260101-00001",
			"doc_type": "issue",
			"status": "posted",
			"document_date": "2026-01-15",
			"warehouse_name_from": "انبار الف",
			"warehouse_name_to": None,
			"source_document_code": "INV-100",
			"delivery_method": "post_express",
			"carrier_name": "پست پیشتاز",
			"description": "شکننده",
			"tracking_number": "123456789",
			"lines": [{"product_name": "کالای نمونه", "quantity": 2}],
		},
		"direction": "out",
		"direction_label": "خروج از انبار",
		"label_title": "برگه مرسوله پستی",
		"document_date_display": "1404/10/25",
		"lines_summary": "کالای نمونه × 2",
		"generated_at": datetime.datetime.now(),
		"is_fa": True,
		"paper_size": "A6",
		"orientation": "portrait",
		"page_size_css": "A6 portrait",
		"invoice_document_type": "invoice_sales",
		"fa_font_url_regular": None,
		"fa_font_url_bold": None,
		"show_sender": True,
		"show_receiver": True,
		"show_warehouse": True,
		"show_lines": True,
		"show_delivery": True,
		"show_tracking": True,
		"show_source": True,
	}
