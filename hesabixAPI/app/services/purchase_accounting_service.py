"""
ثبت حسابداری فاکتور خرید و تسویه GRNI هنگام پست حواله ورود.
"""
from __future__ import annotations

import logging
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine

logger = logging.getLogger(__name__)

PURCHASE_ACCOUNTING_DIRECT = "direct_inventory"
PURCHASE_ACCOUNTING_GRNI = "grni_two_step"
PURCHASE_ACCOUNTING_LEGACY = "grni_legacy"

PURCHASE_ACCOUNTING_MODES = frozenset(
	{
		PURCHASE_ACCOUNTING_DIRECT,
		PURCHASE_ACCOUNTING_GRNI,
		PURCHASE_ACCOUNTING_LEGACY,
	}
)

GRNI_ACCOUNT_CODE_LEGACY = "30101"
GRNI_ACCOUNT_CODE_STANDARD = "10107"
INVENTORY_ACCOUNT_CODE = "10102"

GRNI_CLEARANCE_DESC = "تسویه GRNI — رسید انبار"
GRNI_CLEARANCE_REVERSAL_DESC = "برگشت تسویه GRNI — لغو رسید انبار"


def normalize_purchase_accounting_mode(value: Any) -> str:
	s = str(value or "").strip().lower()
	if s in PURCHASE_ACCOUNTING_MODES:
		return s
	if s in ("direct", "inventory", "inventory_direct"):
		return PURCHASE_ACCOUNTING_DIRECT
	if s in ("grni", "two_step", "grni_two_step"):
		return PURCHASE_ACCOUNTING_GRNI
	if s in ("legacy", "grni_legacy", "old"):
		return PURCHASE_ACCOUNTING_LEGACY
	return PURCHASE_ACCOUNTING_DIRECT


def get_business_purchase_accounting_mode(db: Session, business_id: int) -> str:
	from adapters.db.models.business import Business

	biz = db.query(Business).filter(Business.id == int(business_id)).first()
	raw = getattr(biz, "invoice_purchase_accounting_mode", None) if biz else None
	return normalize_purchase_accounting_mode(raw)


def resolve_purchase_accounting_mode(
	db: Session,
	business_id: int,
	*,
	extra_info: Optional[Dict[str, Any]] = None,
) -> str:
	ei = extra_info or {}
	snap = ei.get("purchase_accounting_mode")
	if snap is not None and str(snap).strip():
		return normalize_purchase_accounting_mode(snap)
	return get_business_purchase_accounting_mode(db, business_id)


def grni_account_code_for_mode(mode: str) -> str:
	m = normalize_purchase_accounting_mode(mode)
	if m == PURCHASE_ACCOUNTING_LEGACY:
		return GRNI_ACCOUNT_CODE_LEGACY
	if m == PURCHASE_ACCOUNTING_GRNI:
		return GRNI_ACCOUNT_CODE_STANDARD
	raise ValueError("direct_inventory has no GRNI account code")


def stamp_purchase_accounting_mode_on_extra_info(
	db: Session,
	business_id: int,
	extra_info: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
	out = dict(extra_info or {})
	if out.get("purchase_accounting_mode") is None:
		out["purchase_accounting_mode"] = get_business_purchase_accounting_mode(db, business_id)
	else:
		out["purchase_accounting_mode"] = normalize_purchase_accounting_mode(
			out.get("purchase_accounting_mode")
		)
	return out


def resolve_grni_account_for_mode(db: Session, mode: str) -> Account:
	from app.services.invoice_service import _get_fixed_account_by_code

	code = grni_account_code_for_mode(mode)
	return _get_fixed_account_by_code(db, code)


def add_purchase_invoice_debit_lines(
	db: Session,
	*,
	document_id: int,
	mode: str,
	accounts: Dict[str, Account],
	gross: Decimal,
) -> None:
	if gross <= 0:
		return
	m = normalize_purchase_accounting_mode(mode)
	if m == PURCHASE_ACCOUNTING_DIRECT:
		db.add(
			DocumentLine(
				document_id=document_id,
				account_id=accounts["inventory"].id,
				debit=gross,
				credit=Decimal(0),
				description="ثبت موجودی کالا (فاکتور خرید)",
			)
		)
		return
	db.add(
		DocumentLine(
			document_id=document_id,
			account_id=accounts["grni"].id,
			debit=gross,
			credit=Decimal(0),
			description="ثبت GRNI خرید (مبلغ ناخالص)",
		)
	)


def add_purchase_return_credit_lines(
	db: Session,
	*,
	document_id: int,
	mode: str,
	accounts: Dict[str, Account],
	gross: Decimal,
) -> None:
	if gross <= 0:
		return
	m = normalize_purchase_accounting_mode(mode)
	if m == PURCHASE_ACCOUNTING_DIRECT:
		db.add(
			DocumentLine(
				document_id=document_id,
				account_id=accounts["inventory"].id,
				debit=Decimal(0),
				credit=gross,
				description="برگشت موجودی کالا (برگشت از خرید)",
			)
		)
		return
	db.add(
		DocumentLine(
			document_id=document_id,
			account_id=accounts["grni"].id,
			debit=Decimal(0),
			credit=gross,
			description="برگشت GRNI بابت برگشت خرید (مبلغ ناخالص)",
		)
	)


def _line_unit_cost_for_purchase(extra: Dict[str, Any]) -> Decimal:
	info = extra or {}
	for key in ("cost_price", "unit_price", "base_purchase_price"):
		if info.get(key) is not None:
			return Decimal(str(info[key]))
	return Decimal(0)


def compute_warehouse_receipt_inventory_amount(
	db: Session,
	business_id: int,
	wh_lines: List[WarehouseDocumentLine],
) -> Decimal:
	total = Decimal(0)
	for ln in wh_lines:
		if str(ln.movement or "").strip().lower() != "in":
			continue
		qty = Decimal(str(ln.quantity or 0))
		if qty <= 0:
			continue
		product = (
			db.query(Product)
			.filter(Product.id == int(ln.product_id), Product.business_id == int(business_id))
			.first()
		)
		if not product or not getattr(product, "track_inventory", False):
			continue
		unit_cost = Decimal(0)
		if getattr(ln, "invoice_item_line_id", None):
			row = (
				db.query(InvoiceItemLine)
				.filter(
					InvoiceItemLine.id == int(ln.invoice_item_line_id),
					InvoiceItemLine.document_id.isnot(None),
				)
				.first()
			)
			if row:
				unit_cost = _line_unit_cost_for_purchase(dict(row.extra_info or {}))
		if unit_cost <= 0:
			unit_cost = _line_unit_cost_for_purchase(dict(ln.extra_info or {}))
		if unit_cost <= 0 and getattr(product, "base_purchase_price", None) is not None:
			unit_cost = Decimal(str(product.base_purchase_price))
		total += qty * unit_cost
	return total


def _grni_net_on_document(db: Session, document_id: int, grni_account_id: int) -> Decimal:
	rows = (
		db.query(DocumentLine)
		.filter(
			DocumentLine.document_id == int(document_id),
			DocumentLine.account_id == int(grni_account_id),
		)
		.all()
	)
	debit = sum(Decimal(str(r.debit or 0)) for r in rows)
	credit = sum(Decimal(str(r.credit or 0)) for r in rows)
	return debit - credit


def _clearance_already_recorded(extra_info: Dict[str, Any], warehouse_document_id: int) -> bool:
	links = (extra_info or {}).get("links") or {}
	items = links.get("grni_clearances") or []
	for it in items:
		try:
			if int((it or {}).get("warehouse_document_id")) == int(warehouse_document_id):
				return True
		except (TypeError, ValueError):
			continue
	return False


def _append_clearance_record(
	extra_info: Dict[str, Any],
	*,
	warehouse_document_id: int,
	amount: Decimal,
) -> Dict[str, Any]:
	out = dict(extra_info or {})
	links = dict(out.get("links") or {})
	items = list(links.get("grni_clearances") or [])
	items.append(
		{
			"warehouse_document_id": int(warehouse_document_id),
			"amount": float(amount),
		}
	)
	links["grni_clearances"] = items
	out["links"] = links
	return out


def post_purchase_grni_clearance_for_warehouse(
	db: Session,
	warehouse_document_id: int,
) -> bool:
	"""پس از قطعی حواله ورود مرتبط با فاکتور خرید: Dr موجودی / Cr GRNI."""
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == int(warehouse_document_id)).first()
	if not wh or str(wh.status or "").lower() != "posted":
		return False
	if str(wh.doc_type or "").strip().lower() != "receipt":
		return False
	if str(getattr(wh, "source_type", "") or "").strip().lower() != "invoice":
		return False
	if not wh.source_document_id:
		return False

	invoice = (
		db.query(Document)
		.filter(
			Document.id == int(wh.source_document_id),
			Document.business_id == int(wh.business_id),
		)
		.first()
	)
	if not invoice or str(invoice.document_type or "") != "invoice_purchase":
		return False

	mode = resolve_purchase_accounting_mode(
		db, int(wh.business_id), extra_info=dict(invoice.extra_info or {})
	)
	if mode != PURCHASE_ACCOUNTING_GRNI:
		return False

	extra = dict(invoice.extra_info or {})
	if _clearance_already_recorded(extra, int(wh.id)):
		return False

	wh_lines = (
		db.query(WarehouseDocumentLine)
		.filter(WarehouseDocumentLine.warehouse_document_id == int(wh.id))
		.all()
	)
	receipt_amount = compute_warehouse_receipt_inventory_amount(db, int(wh.business_id), wh_lines)
	if receipt_amount <= 0:
		logger.info(
			"grni clearance skipped wh_id=%s invoice_id=%s (zero receipt amount)",
			wh.id,
			invoice.id,
		)
		return False

	from app.services.invoice_service import _get_fixed_account_by_code

	grni_account = resolve_grni_account_for_mode(db, mode)
	inventory_account = _get_fixed_account_by_code(db, INVENTORY_ACCOUNT_CODE)
	remaining = _grni_net_on_document(db, int(invoice.id), int(grni_account.id))
	if remaining <= 0:
		return False
	amount = min(remaining, receipt_amount)
	if amount <= 0:
		return False

	db.add(
		DocumentLine(
			document_id=int(invoice.id),
			account_id=int(inventory_account.id),
			debit=amount,
			credit=Decimal(0),
			description=GRNI_CLEARANCE_DESC,
			extra_info={"warehouse_document_id": int(wh.id), "side": "grni_clearance"},
		)
	)
	db.add(
		DocumentLine(
			document_id=int(invoice.id),
			account_id=int(grni_account.id),
			debit=Decimal(0),
			credit=amount,
			description=GRNI_CLEARANCE_DESC,
			extra_info={"warehouse_document_id": int(wh.id), "side": "grni_clearance"},
		)
	)
	invoice.extra_info = _append_clearance_record(extra, warehouse_document_id=int(wh.id), amount=amount)
	db.flush()
	return True


def reverse_purchase_grni_clearance_for_warehouse(
	db: Session,
	warehouse_document_id: int,
) -> bool:
	"""هنگام لغو حواله ورود: معکوس سطرهای تسویه GRNI."""
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == int(warehouse_document_id)).first()
	if not wh or not wh.source_document_id:
		return False
	invoice = db.query(Document).filter(Document.id == int(wh.source_document_id)).first()
	if not invoice:
		return False
	extra = dict(invoice.extra_info or {})
	links = dict(extra.get("links") or {})
	items = list(links.get("grni_clearances") or [])
	match = None
	for it in items:
		try:
			if int((it or {}).get("warehouse_document_id")) == int(wh.id):
				match = it
				break
		except (TypeError, ValueError):
			continue
	if not match:
		return False

	rows = (
		db.query(DocumentLine)
		.filter(
			DocumentLine.document_id == int(invoice.id),
			DocumentLine.description == GRNI_CLEARANCE_DESC,
		)
		.all()
	)
	to_delete = [
		r
		for r in rows
		if (r.extra_info or {}).get("warehouse_document_id") == int(wh.id)
	]
	if not to_delete:
		return False
	for r in to_delete:
		db.delete(r)
	items = [
		it
		for it in items
		if int((it or {}).get("warehouse_document_id", -1)) != int(wh.id)
	]
	links["grni_clearances"] = items
	extra["links"] = links
	invoice.extra_info = extra
	db.flush()
	return True
