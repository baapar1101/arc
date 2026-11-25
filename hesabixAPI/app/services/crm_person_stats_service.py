"""عمق فروش شخص از فاکتورهای همان کسب‌وکار.

مانده را حساب نمی‌کند و سند دریافت نمی‌سازد. دریافت‌ها فقط از لینک موجود فاکتور خوانده می‌شوند.
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

from sqlalchemy import and_, cast, func, Integer, or_
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Session

from adapters.db.models.crm import CrmPersonStats
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from app.services.crm_commercial import aggregate_commercial

logger = logging.getLogger(__name__)

_DOCUMENT_CAP = 300
_RECEIPT_LIST_CAP = 12


def _attach_currency_labels(db: Session, summary: dict[str, Any]) -> None:
    rows = summary.get("currencies")
    if not isinstance(rows, list) or not rows:
        return
    ids = [int(row["currency_id"]) for row in rows if isinstance(row, dict) and row.get("currency_id")]
    if not ids:
        return
    from adapters.db.models.currency import Currency

    labels = {int(item.id): item for item in db.query(Currency).filter(Currency.id.in_(ids)).all()}
    for row in rows:
        if not isinstance(row, dict) or not row.get("currency_id"):
            continue
        currency = labels.get(int(row["currency_id"]))
        if currency is None:
            continue
        row["currency_code"] = currency.code
        row["currency_title"] = currency.title
_SALES_TYPES = ("invoice_sales", "invoice_sales_return")


def _totals_net(extra: dict | None) -> Any:
    totals = (extra or {}).get("totals")
    if isinstance(totals, dict) and totals.get("net") is not None:
        return totals.get("net")
    return None


def _receipt_ids_from_document(extra: dict | None) -> list[int]:
    links = (extra or {}).get("links") or {}
    found = []
    for raw in links.get("receipt_payment_document_ids") or []:
        try:
            found.append(int(raw))
        except (TypeError, ValueError):
            continue
    return found


def _linked_receipt_ids(db: Session, business_id: int, invoice_ids: list[int]) -> set[int]:
    if not invoice_ids:
        return set()
    line_invoice_id = cast(cast(DocumentLine.extra_info, JSONB)["invoice_id"].astext, Integer)
    rows = (
        db.query(Document.id)
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .filter(
            Document.business_id == business_id,
            Document.document_type == "receipt",
            DocumentLine.person_id.isnot(None),
            line_invoice_id.in_(invoice_ids),
        )
        .distinct()
        .all()
    )
    return {int(row[0]) for row in rows}


def build_person_commercial(db: Session, business_id: int, person_id: int, *, persist: bool = True) -> dict[str, Any]:
    rows = (
        db.query(Document)
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .filter(
            Document.business_id == business_id,
            DocumentLine.person_id == person_id,
            Document.document_type.in_(_SALES_TYPES),
            Document.is_proforma.is_(False),
        )
        .group_by(Document.id)
        .order_by(Document.document_date.desc(), Document.id.desc())
        .limit(_DOCUMENT_CAP + 1)
        .all()
    )
    truncated = len(rows) > _DOCUMENT_CAP
    documents = rows[:_DOCUMENT_CAP]
    doc_ids = [int(doc.id) for doc in documents]
    item_rows = (
        db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id.in_(doc_ids)).all() if doc_ids else []
    )
    product_ids = {int(line.product_id) for line in item_rows if line.product_id}
    names = {}
    if product_ids:
        for product in db.query(Product.id, Product.name).filter(Product.id.in_(product_ids), Product.business_id == business_id):
            names[int(product.id)] = product.name
    lines_by_doc: dict[int, list[dict[str, Any]]] = {}
    for line in item_rows:
        lines_by_doc.setdefault(int(line.document_id), []).append(
            {
                "product_id": int(line.product_id) if line.product_id else None,
                "product_name": names.get(int(line.product_id)) if line.product_id else None,
                "quantity": line.quantity,
                "extra_info": line.extra_info or {},
                "ledger_line_cogs": line.ledger_line_cogs,
            }
        )
    payloads = []
    linked_ids: set[int] = set()
    for doc in documents:
        extra = doc.extra_info or {}
        receipt_ids = _receipt_ids_from_document(extra)
        linked_ids.update(receipt_ids)
        payloads.append(
            {
                "id": int(doc.id),
                "document_type": doc.document_type,
                "is_proforma": False,
                "currency_id": doc.currency_id,
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "code": doc.code,
                "totals_net": _totals_net(extra),
                "lines": lines_by_doc.get(int(doc.id), []),
                "receipt_ids": receipt_ids,
            }
        )
    sales_docs = [doc for doc in documents if doc.document_type == "invoice_sales"]
    invoice_ids = [int(doc.id) for doc in sales_docs]
    linked_ids.update(_linked_receipt_ids(db, business_id, invoice_ids))
    summary = aggregate_commercial(payloads)
    _attach_currency_labels(db, summary)
    summary["receipt_ids"] = sorted(set(summary["receipt_ids"]) | linked_ids)

    open_documents = _open_sales_documents(db, business_id, sales_docs)
    summary["open_documents"] = open_documents[:8]
    summary["open_document_count"] = len(open_documents)
    summary["open_remaining"] = _single_currency_remaining(summary, open_documents)
    summary["documents_truncated"] = truncated
    receipt_ids = summary.pop("receipt_ids", [])
    summary["receipts"] = _receipt_rows(db, business_id, receipt_ids)
    summary["receipt_count"] = _receipt_count(db, business_id, receipt_ids)
    if persist:
        _store_snapshot(db, business_id, person_id, summary)
    return summary


def _open_sales_documents(db: Session, business_id: int, documents: list[Document]) -> list[dict[str, Any]]:
    if not documents:
        return []
    from app.services.invoice_service import batch_calculate_invoices_remaining

    remaining_map = batch_calculate_invoices_remaining(db, business_id, documents)
    open_rows = []
    for doc in documents:
        info = remaining_map.get(int(doc.id)) or {}
        remaining = float(info.get("remaining") or 0)
        if info.get("is_settled") or remaining <= 0.01:
            continue
        open_rows.append(
            {
                "id": int(doc.id),
                "code": doc.code,
                "currency_id": doc.currency_id,
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "remaining": remaining,
                "total_amount": float(info.get("total_amount") or 0),
            }
        )
    return open_rows


def _single_currency_remaining(summary: dict[str, Any], open_documents: list[dict[str, Any]]) -> float | None:
    if summary.get("mixed_currency") or not open_documents:
        return 0.0 if not open_documents and not summary.get("mixed_currency") else None
    currencies = {row.get("currency_id") for row in open_documents}
    if len(currencies) != 1:
        return None
    return round(sum(float(row["remaining"]) for row in open_documents), 2)


def _receipt_count(db: Session, business_id: int, receipt_ids: list[int]) -> int:
    if not receipt_ids:
        return 0
    return int(
        db.query(func.count(Document.id))
        .filter(
            Document.business_id == business_id,
            Document.id.in_(receipt_ids),
            Document.document_type == "receipt",
        )
        .scalar()
        or 0
    )


def _receipt_rows(db: Session, business_id: int, receipt_ids: list[int]) -> list[dict[str, Any]]:
    if not receipt_ids:
        return []
    docs = (
        db.query(Document)
        .filter(
            Document.business_id == business_id,
            Document.id.in_(receipt_ids[:_RECEIPT_LIST_CAP]),
            Document.document_type == "receipt",
        )
        .all()
    )
    rows = []
    for doc in docs:
        extra = doc.extra_info or {}
        totals = extra.get("totals") if isinstance(extra.get("totals"), dict) else {}
        rows.append(
            {
                "id": int(doc.id),
                "code": doc.code,
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "amount": totals.get("net") if totals.get("net") is not None else extra.get("amount"),
            }
        )
    rows.sort(key=lambda row: row.get("document_date") or "", reverse=True)
    return rows


def _store_snapshot(db: Session, business_id: int, person_id: int, summary: dict[str, Any]) -> None:
    row = (
        db.query(CrmPersonStats)
        .filter(CrmPersonStats.business_id == business_id, CrmPersonStats.person_id == person_id)
        .first()
    )
    if row is None:
        row = CrmPersonStats(business_id=business_id, person_id=person_id)
        db.add(row)
    row.sales_total = summary.get("sales_total") or 0
    row.returns_total = summary.get("returns_total") or 0
    row.net_sales = summary.get("net_sales")
    row.margin_amount = summary.get("margin_amount")
    row.margin_complete = bool(summary.get("margin_complete"))
    row.mixed_currency = bool(summary.get("mixed_currency"))
    row.open_document_count = int(summary.get("open_document_count") or 0)
    row.open_remaining = summary.get("open_remaining")
    row.documents_truncated = bool(summary.get("documents_truncated"))
    row.currencies = summary.get("currencies") or []
    row.repeat_products = summary.get("repeat_products") or []
    row.receipt_count = int(summary.get("receipt_count") or 0)
    row.computed_at = datetime.utcnow()
    db.commit()


def refresh_stale_person_stats(db: Session, *, limit: int = 80, now: datetime | None = None) -> dict[str, int | bool]:
    """تجمیع شبانه. بیرون از پنجره شب، دید ۳۶۰ همان شخص را هنگام باز شدن حساب می‌کند."""
    current = now or datetime.utcnow()
    if not (current.hour >= 20 or current.hour < 4):
        return {"skipped": True, "refreshed": 0, "errors": 0}
    start = datetime(current.year, current.month, current.day)
    pairs = (
        db.query(Document.business_id, DocumentLine.person_id)
        .join(DocumentLine, DocumentLine.document_id == Document.id)
        .outerjoin(
            CrmPersonStats,
            and_(
                CrmPersonStats.business_id == Document.business_id,
                CrmPersonStats.person_id == DocumentLine.person_id,
            ),
        )
        .filter(
            Document.document_type.in_(_SALES_TYPES),
            Document.is_proforma.is_(False),
            DocumentLine.person_id.isnot(None),
            or_(CrmPersonStats.id.is_(None), CrmPersonStats.computed_at < start),
        )
        .distinct()
        .limit(limit)
        .all()
    )
    refreshed = 0
    errors = 0
    for business_id, person_id in pairs:
        try:
            build_person_commercial(db, int(business_id), int(person_id))
            refreshed += 1
        except Exception:
            errors += 1
            db.rollback()
            logger.exception("crm person stats failed business=%s person=%s", business_id, person_id)
    return {"skipped": False, "refreshed": refreshed, "errors": errors}
