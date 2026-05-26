from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from app.services.invoice_service import (
    INVOICE_PURCHASE,
    INVOICE_PURCHASE_RETURN,
    SUPPORTED_INVOICE_TYPES,
    _create_warehouse_documents_for_invoice,
    _normalize_document_extra_info_for_storage,
    _persisted_invoice_lines_for_warehouse,
    _remove_old_invoice_warehouse_documents,
)

def _invoice_lines_for_product(
    db: Session,
    *,
    business_id: int,
    product_id: int,
) -> List[tuple[InvoiceItemLine, Document]]:
    return (
        db.query(InvoiceItemLine, Document)
        .join(Document, Document.id == InvoiceItemLine.document_id)
        .filter(
            InvoiceItemLine.product_id == int(product_id),
            Document.business_id == int(business_id),
            Document.is_proforma == False,  # noqa: E712
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
        .order_by(Document.id.asc(), InvoiceItemLine.id.asc())
        .all()
    )


def _set_line_inventory_tracked(line: InvoiceItemLine, tracked: bool) -> bool:
    info = dict(line.extra_info or {})
    new_val = bool(tracked)
    if info.get("inventory_tracked") is new_val:
        return False
    info["inventory_tracked"] = new_val
    line.extra_info = info
    flag_modified(line, "extra_info")
    return True


def product_has_stale_inventory_tracking_lines(
    db: Session,
    *,
    business_id: int,
    product_id: int,
    expected_tracked: bool,
) -> bool:
    """خطوط فاکتور قطعی که inventory_tracked با وضعیت فعلی کالا ناسازگار است."""
    rows = _invoice_lines_for_product(db, business_id=business_id, product_id=product_id)
    expected = bool(expected_tracked)
    for line, _document in rows:
        info = line.extra_info or {}
        current = info.get("inventory_tracked")
        if current is None:
            if not expected:
                continue
            return True
        if bool(current) != expected:
            return True
    return False


def _sync_invoice_warehouse_documents(
    db: Session,
    *,
    business_id: int,
    document: Document,
    user_id: Optional[int],
) -> None:
    if bool(getattr(document, "is_proforma", False)):
        return
    if not bool((document.extra_info or {}).get("post_inventory", True)):
        return

    extra = dict(document.extra_info or {})
    links = dict(extra.get("links") or {})
    old_wh_ids = [int(x) for x in (links.get("warehouse_document_ids") or []) if x is not None]
    effective_user_id = int(user_id or document.created_by_user_id)

    if old_wh_ids:
        _remove_old_invoice_warehouse_documents(
            db,
            int(business_id),
            int(document.id),
            old_wh_ids,
            effective_user_id,
        )

    links.pop("warehouse_document_ids", None)
    extra["links"] = links
    document.extra_info = _normalize_document_extra_info_for_storage(extra)
    flag_modified(document, "extra_info")
    db.flush()

    lines_for_wh = _persisted_invoice_lines_for_warehouse(db, int(document.id))
    _create_warehouse_documents_for_invoice(
        db,
        int(business_id),
        document,
        effective_user_id,
        lines_for_wh,
        str(document.document_type or ""),
        stock_exclude_warehouse_document_ids=old_wh_ids or None,
    )


def _refresh_invoice_ledgers_after_tracking_change(
    db: Session,
    *,
    business_id: int,
    product_id: int,
    document: Document,
) -> None:
    if bool(getattr(document, "is_proforma", False)):
        return

    doc_type = str(document.document_type or "")
    try:
        from app.services.invoice_profit_ledger_service import on_sales_invoice_document_finalized

        on_sales_invoice_document_finalized(db, int(document.id))
    except Exception as ex:
        logger.warning(
            "product inventory tracking sync: ledger refresh failed doc_id=%s product_id=%s err=%s",
            document.id,
            product_id,
            ex,
            exc_info=True,
        )

    if doc_type not in (INVOICE_PURCHASE, INVOICE_PURCHASE_RETURN):
        return

    try:
        from app.services.invoice_profit_ledger_service import (
            refresh_sales_ledgers_after_inventory_invoice_change,
        )

        refresh_sales_ledgers_after_inventory_invoice_change(
            db,
            int(business_id),
            [int(product_id)],
            fiscal_year_id=int(document.fiscal_year_id),
        )
    except Exception as ex:
        logger.warning(
            "product inventory tracking sync: purchase-chain ledger refresh failed doc_id=%s product_id=%s err=%s",
            document.id,
            product_id,
            ex,
            exc_info=True,
        )


def sync_product_inventory_tracking_change(
    db: Session,
    *,
    business_id: int,
    product_id: int,
    old_track_inventory: bool,
    new_track_inventory: bool,
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    """
    همگام‌سازی پس‌گیر پس از تغییر کنترل موجودی کالا:
    - به‌روزرسانی inventory_tracked روی خطوط فاکتورهای قطعی
    - بازسازی حواله‌های انبار وابسته (در صورت post_inventory)
    - به‌روزرسانی ledger سود/COGS
    """
    if bool(old_track_inventory) == bool(new_track_inventory):
        rows = _invoice_lines_for_product(db, business_id=business_id, product_id=product_id)
        stale = any(
            bool((line.extra_info or {}).get("inventory_tracked", True)) != bool(new_track_inventory)
            for line, _doc in rows
        )
        if not stale:
            return {
                "changed": False,
                "lines_updated": 0,
                "documents_synced": 0,
            }

    rows = _invoice_lines_for_product(db, business_id=business_id, product_id=product_id)
    if not rows:
        return {
            "changed": True,
            "lines_updated": 0,
            "documents_synced": 0,
        }

    lines_updated = 0
    documents_by_id: Dict[int, Document] = {}
    for line, document in rows:
        if _set_line_inventory_tracked(line, new_track_inventory):
            lines_updated += 1
        documents_by_id[int(document.id)] = document

    if lines_updated:
        db.flush()

    documents_synced = 0
    for document in documents_by_id.values():
        try:
            _sync_invoice_warehouse_documents(
                db,
                business_id=business_id,
                document=document,
                user_id=user_id,
            )
            _refresh_invoice_ledgers_after_tracking_change(
                db,
                business_id=business_id,
                product_id=product_id,
                document=document,
            )
            documents_synced += 1
        except Exception as ex:
            logger.exception(
                "product inventory tracking sync failed for document_id=%s product_id=%s",
                document.id,
                product_id,
            )
            raise

    return {
        "changed": True,
        "lines_updated": lines_updated,
        "documents_synced": documents_synced,
        "document_ids": sorted(documents_by_id.keys()),
    }
