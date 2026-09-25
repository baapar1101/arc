"""ساخت اسناد مالی/انبار برای جریان‌های پخش مویرگی."""

from __future__ import annotations

import logging
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.product import Product
from app.core.business_calendar import business_today
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


def _money(v: Any) -> float:
	try:
		return float(Decimal(str(v or 0)))
	except Exception:
		return 0.0


def _round2(v: float) -> float:
	return float(Decimal(str(v)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def _user_display_name(user: Any) -> str:
	if user is None:
		return ""
	parts = [getattr(user, "first_name", None) or "", getattr(user, "last_name", None) or ""]
	name = " ".join(p for p in parts if p).strip()
	if name:
		return name
	return (getattr(user, "email", None) or getattr(user, "mobile", None) or str(getattr(user, "id", ""))).strip()


def user_label(db: Session, user_id: Optional[int]) -> Optional[str]:
	if not user_id:
		return None
	from adapters.db.models.user import User

	u = db.query(User).filter(User.id == int(user_id)).first()
	return _user_display_name(u) if u else str(user_id)


def person_label(db: Session, person_id: Optional[int]) -> Optional[str]:
	if not person_id:
		return None
	from adapters.db.models.person import Person

	p = db.query(Person).filter(Person.id == int(person_id)).first()
	if not p:
		return str(person_id)
	return (p.alias_name or "").strip() or str(person_id)


def _resolve_unit_price(db: Session, business_id: int, product: Product, override: Any) -> float:
	if override is not None:
		return float(override)
	# لیست قیمت پیش‌فرض کسب‌وکار (در صورت وجود)
	try:
		from app.services.product_fx_price_service import resolve_default_price_list_id
		from app.services.price_list_service import list_price_items

		pl_id = resolve_default_price_list_id(db, business_id)
		if pl_id:
			items = list_price_items(db, business_id, int(pl_id), take=1, skip=0, product_id=int(product.id))
			rows = items.get("items") if isinstance(items, dict) else None
			if isinstance(rows, list) and rows:
				price = rows[0].get("price") if isinstance(rows[0], dict) else None
				if price is not None:
					return float(price)
	except Exception:
		logger.debug("price list resolve skipped product=%s", product.id, exc_info=True)
	return float(product.base_sales_price or 0)


def build_invoice_lines(
	db: Session,
	business_id: int,
	raw_lines: List[Dict[str, Any]],
	warehouse_id: Optional[int],
) -> List[Dict[str, Any]]:
	out: List[Dict[str, Any]] = []
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
		unit_price = _resolve_unit_price(db, business_id, product, ln.get("unit_price"))
		line_discount = _money(ln.get("line_discount"))
		gross = _round2(qty * unit_price)
		net_before_tax = _round2(max(0.0, gross - line_discount))
		tax_rate = 0.0
		if bool(getattr(product, "is_sales_taxable", False)):
			tax_rate = float(getattr(product, "sales_tax_rate", None) or 0)
		if ln.get("tax_rate") is not None:
			tax_rate = float(ln.get("tax_rate") or 0)
		tax_amount = _money(ln.get("tax_amount")) if ln.get("tax_amount") is not None else _round2(net_before_tax * tax_rate / 100.0)
		line_total = _round2(net_before_tax + tax_amount)
		extra: Dict[str, Any] = {
			"unit_price": unit_price,
			"line_discount": line_discount,
			"tax_amount": tax_amount,
			"tax_rate": tax_rate,
			"line_total": line_total,
		}
		if warehouse_id:
			extra["warehouse_id"] = int(warehouse_id)
		out.append(
			{
				"product_id": pid,
				"quantity": qty,
				"description": (product.name or "")[:255],
				"extra_info": extra,
			}
		)
	if not out:
		raise ApiError("VALIDATION_ERROR", "lines required", http_status=400)
	return out


def _extract_invoice_id(result: Any) -> Optional[int]:
	if not isinstance(result, dict):
		return None
	data = result.get("data") if isinstance(result.get("data"), dict) else result
	doc_id = data.get("id") if isinstance(data, dict) else None
	if doc_id is None and isinstance(result.get("document"), dict):
		doc_id = result["document"].get("id")
	return int(doc_id) if doc_id is not None else None


def create_distribution_invoice(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	invoice_type: str,
	person_id: int,
	raw_lines: List[Dict[str, Any]],
	warehouse_id: Optional[int],
	description: str,
	meta: Optional[Dict[str, Any]] = None,
	source_document_id: Optional[int] = None,
	is_proforma: bool = False,
	post_inventory: Optional[bool] = None,
) -> Dict[str, Any]:
	"""ایجاد فاکتور فروش/برگشت — در صورت خطا ApiError پرتاب می‌کند (fail-closed).

	برای پیش‌فروش: is_proforma=True و post_inventory=False تا بدون حرکت انبار/AR قطعی ثبت شود.
	"""
	from app.services.invoice_service import create_invoice

	business = db.query(Business).filter(Business.id == business_id).first()
	if not business or not business.default_currency_id:
		raise ApiError("VALIDATION_ERROR", "Business default currency is required for invoice", http_status=400)

	inv_lines = build_invoice_lines(db, business_id, raw_lines, warehouse_id)
	gross = sum(_money((ln.get("extra_info") or {}).get("unit_price")) * float(ln.get("quantity") or 0) for ln in inv_lines)
	discount = sum(_money((ln.get("extra_info") or {}).get("line_discount")) for ln in inv_lines)
	tax = sum(_money((ln.get("extra_info") or {}).get("tax_amount")) for ln in inv_lines)
	net = sum(_money((ln.get("extra_info") or {}).get("line_total")) for ln in inv_lines)

	do_post = (not is_proforma) if post_inventory is None else bool(post_inventory)
	if is_proforma:
		do_post = False

	extra: Dict[str, Any] = {
		"person_id": int(person_id),
		"post_inventory": do_post,
		"auto_post_warehouse": do_post,
		"distribution": meta or {},
		"totals": {
			"gross": _round2(gross),
			"discount": _round2(discount),
			"tax": _round2(tax),
			"net": _round2(net),
		},
	}
	if is_proforma:
		extra["distribution_presell"] = True
	if warehouse_id:
		extra["warehouse_id"] = int(warehouse_id)
	if source_document_id:
		extra["source_document_id"] = int(source_document_id)
		extra["related_document_id"] = int(source_document_id)

	payload: Dict[str, Any] = {
		"invoice_type": invoice_type,
		"document_date": business_today(business_id).isoformat(),
		"currency_id": int(business.default_currency_id),
		"person_id": int(person_id),
		"description": (description or "")[:500],
		"is_proforma": bool(is_proforma),
		"lines": inv_lines,
		"extra_info": extra,
	}
	with db.begin_nested():
		result = create_invoice(db, business_id, user_id, payload, commit=False)
		doc_id = _extract_invoice_id(result)
		if not doc_id:
			raise ApiError("VALIDATION_ERROR", "invoice id missing after create", http_status=400)
		return {"id": int(doc_id), "raw": result, "net": _round2(net), "is_proforma": bool(is_proforma)}


def finalize_distribution_proforma_invoice(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	document_id: int,
	warehouse_id: Optional[int] = None,
	raw_lines: Optional[List[Dict[str, Any]]] = None,
	meta: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	"""تبدیل پیش‌فاکتور پخش به فاکتور قطعی با پست انبار از طریق update_invoice."""
	from adapters.db.models.invoice_item_line import InvoiceItemLine
	from app.services.invoice_service import update_invoice

	doc = db.query(Document).filter(Document.id == int(document_id), Document.business_id == business_id).first()
	if not doc:
		raise ApiError("NOT_FOUND", "Invoice not found", http_status=404)
	if not doc.is_proforma:
		return {"id": int(doc.id), "already_final": True}

	lines_payload: List[Dict[str, Any]] = []
	if raw_lines:
		wh = warehouse_id or (doc.extra_info or {}).get("warehouse_id")
		lines_payload = build_invoice_lines(db, business_id, raw_lines, int(wh) if wh else None)
	else:
		item_rows = db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == doc.id).all()
		wh = warehouse_id or (doc.extra_info or {}).get("warehouse_id")
		for it in item_rows:
			ex = dict(it.extra_info or {})
			if wh and not ex.get("warehouse_id"):
				ex["warehouse_id"] = int(wh)
			lines_payload.append(
				{
					"product_id": int(it.product_id),
					"quantity": float(it.quantity or 0),
					"description": it.description,
					"extra_info": ex,
				}
			)
	if not lines_payload:
		raise ApiError("VALIDATION_ERROR", "Cannot finalize invoice without lines", http_status=400)

	ex = dict(doc.extra_info or {})
	ex["post_inventory"] = True
	ex["auto_post_warehouse"] = True
	ex["delivered_at"] = datetime.utcnow().isoformat() + "Z"
	if warehouse_id:
		ex["warehouse_id"] = int(warehouse_id)
	if meta:
		dist = dict(ex.get("distribution") or {})
		dist.update(meta)
		ex["distribution"] = dist

	payload: Dict[str, Any] = {
		"invoice_type": doc.document_type,
		"document_date": doc.document_date.isoformat() if doc.document_date else business_today(business_id).isoformat(),
		"currency_id": int(doc.currency_id),
		"description": doc.description,
		"is_proforma": False,
		"lines": lines_payload,
		"extra_info": ex,
		"person_id": ex.get("person_id"),
	}
	with db.begin_nested():
		result = update_invoice(db, int(document_id), user_id, payload)
	return {"id": int(document_id), "finalized": True, "raw": result}


def try_create_distribution_invoice(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	invoice_type: str,
	person_id: int,
	raw_lines: List[Dict[str, Any]],
	warehouse_id: Optional[int],
	description: str,
	meta: Optional[Dict[str, Any]] = None,
	source_document_id: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
	"""سازگاری عقب‌رو — ترجیحاً از create_distribution_invoice استفاده کنید."""
	try:
		return create_distribution_invoice(
			db,
			business_id,
			user_id,
			invoice_type=invoice_type,
			person_id=person_id,
			raw_lines=raw_lines,
			warehouse_id=warehouse_id,
			description=description,
			meta=meta,
			source_document_id=source_document_id,
		)
	except ApiError as e:
		logger.warning("distribution invoice ApiError: %s", e)
		return None
	except Exception:
		logger.exception("distribution invoice failed")
		return None


def create_return_warehouse_receipt(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	warehouse_id: int,
	lines: List[Dict[str, Any]],
	description: str,
	meta: Optional[Dict[str, Any]] = None,
) -> int:
	from app.services.warehouse_service import create_manual_warehouse_document, post_warehouse_document

	wh_lines = []
	for ln in lines:
		pid = int(ln.get("product_id") or 0)
		qty = float(ln.get("quantity") or 0)
		if pid <= 0 or qty <= 0:
			continue
		wh_lines.append({"product_id": pid, "quantity": qty})
	if not wh_lines:
		raise ApiError("VALIDATION_ERROR", "return lines empty", http_status=400)
	wh_doc = create_manual_warehouse_document(
		db,
		business_id,
		user_id,
		{
			"doc_type": "receipt",
			"document_date": business_today(business_id).isoformat(),
			"warehouse_id_to": int(warehouse_id),
			"description": description[:500],
			"lines": wh_lines,
			"extra_info": meta or {},
		},
	)
	post_warehouse_document(db, wh_doc.id)
	return int(wh_doc.id)


def document_net_amount(db: Session, document_id: int) -> Optional[Decimal]:
	doc = db.query(Document).filter(Document.id == document_id).first()
	if not doc:
		return None
	extra = doc.extra_info or {}
	totals = extra.get("totals") if isinstance(extra, dict) else None
	if isinstance(totals, dict) and totals.get("net") is not None:
		try:
			return Decimal(str(totals["net"]))
		except Exception:
			return None
	return None


def list_person_open_invoices(
	db: Session,
	business_id: int,
	person_id: int,
	*,
	limit: int = 20,
) -> List[Dict[str, Any]]:
	"""فاکتورهای فروش اخیر شخص برای لینک به ویزیت / مرجوعی."""
	from app.services.invoice_service import INVOICE_SALES, calculate_invoice_remaining

	q = (
		db.query(Document)
		.filter(
			Document.business_id == business_id,
			Document.document_type == INVOICE_SALES,
			Document.is_proforma.is_(False),
		)
		.order_by(Document.id.desc())
		.limit(max(1, min(int(limit), 50)))
	)
	out: List[Dict[str, Any]] = []
	for doc in q.all():
		extra = doc.extra_info or {}
		if not isinstance(extra, dict):
			continue
		pid = extra.get("person_id")
		if pid is None:
			continue
		if int(pid) != int(person_id):
			continue
		net = None
		totals = extra.get("totals")
		if isinstance(totals, dict) and totals.get("net") is not None:
			net = _money(totals.get("net"))
		remaining = None
		try:
			remaining = float(calculate_invoice_remaining(db, business_id, int(doc.id)))
		except Exception:
			remaining = net
		out.append(
			{
				"id": doc.id,
				"code": doc.code,
				"document_date": doc.document_date.isoformat() if doc.document_date else None,
				"net": net,
				"remaining": remaining,
				"description": (doc.description or "")[:200],
			}
		)
	return out
