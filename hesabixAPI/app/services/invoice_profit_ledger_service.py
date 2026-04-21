"""
شناسایی بهای تمام‌شده و سود قطعی (دفتر) در مقابل محاسبه تحلیلی زنده.

مبانی (روی Business.invoice_profit_ledger_recognition_basis):
  - warehouse_document_posting: با قطعی شدن حواله انبار مرتبط با فاکتور
  - sales_invoice_document: با ثبت فاکتور قطعی (غیر پیش‌فاکتور)، بدون انتظار برای حواله
"""
from __future__ import annotations

import logging
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

# مقدار پیش‌فرض هم‌تراز با migration / مدل Business
LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING = "warehouse_document_posting"
LEDGER_BASIS_SALES_INVOICE_DOCUMENT = "sales_invoice_document"

LEDGER_EVENT_WAREHOUSE_DOCUMENT_POSTING = "warehouse_document_posting"
LEDGER_EVENT_SALES_INVOICE_DOCUMENT = "sales_invoice_document"
LEDGER_EVENT_INVENTORY_CHAIN_REFRESH = "inventory_chain_refresh"


def normalize_invoice_profit_ledger_basis(value: Optional[str]) -> str:
    s = str(value or "").strip().lower()
    if s == LEDGER_BASIS_SALES_INVOICE_DOCUMENT:
        return LEDGER_BASIS_SALES_INVOICE_DOCUMENT
    return LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING


# انواع سندی که سود فاکتور برایشان محاسبه می‌شود (هم‌راستا با invoice_service)
PROFIT_RECOGNITION_DOCUMENT_TYPES: tuple[str, ...] = (
    "invoice_sales",
    "invoice_sales_return",
    "invoice_production",
)


def document_has_any_posted_warehouse(db: Session, *, document_id: int) -> bool:
    """آیا برای این فاکتور حواله قطعی وجود دارد."""
    from adapters.db.models.document import Document
    from adapters.db.models.warehouse_document import WarehouseDocument

    doc = db.query(Document).filter(Document.id == int(document_id)).first()
    if not doc:
        return False
    links = ((doc.extra_info or {}).get("links") or {}) if doc.extra_info else {}
    wh_ids = links.get("warehouse_document_ids") or []
    if not wh_ids:
        return False
    q = db.query(WarehouseDocument).filter(
        WarehouseDocument.id.in_([int(x) for x in wh_ids]),
        WarehouseDocument.status == "posted",
    ).first()
    return q is not None


def apply_recognized_profit_to_invoice_lines(
    db: Session,
    business_id: int,
    document_id: int,
    *,
    recognition_event: str,
) -> bool:
    """
    محاسبه سود تحلیلی فعلی را به‌عنوان «قطعی دفتر» روی خطوط فاکتور ذخیره می‌کند.
    فقط زمانی اعمال می‌شود که رویداد با تنظیم کسب‌وکار هم‌خوان باشد.
    برمی‌گرداند True اگر نوشتن انجام شد.
    """
    from adapters.db.models.business import Business
    from adapters.db.models.document import Document
    from adapters.db.models.invoice_item_line import InvoiceItemLine

    biz = db.query(Business).filter(Business.id == int(business_id)).first()
    if not biz:
        return False

    if getattr(biz, "invoice_profit_calculation_method", None) == "disabled":
        return False

    basis = normalize_invoice_profit_ledger_basis(getattr(biz, "invoice_profit_ledger_recognition_basis", None))

    if recognition_event == LEDGER_EVENT_WAREHOUSE_DOCUMENT_POSTING and basis != LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING:
        return False
    if recognition_event == LEDGER_EVENT_SALES_INVOICE_DOCUMENT and basis != LEDGER_BASIS_SALES_INVOICE_DOCUMENT:
        return False

    doc = db.query(Document).filter(Document.id == int(document_id)).first()
    if not doc or doc.business_id != int(business_id):
        return False
    if doc.is_proforma:
        return False
    if doc.document_type not in PROFIT_RECOGNITION_DOCUMENT_TYPES:
        return False

    # اگر مبنا حواله است، تا قبل از قطعی بودن حواله نباید با مسیر «فاکتور» ذخیره شود؛
    # مسیر حواله خود به‌محض پست شدن فراخوانی می‌شود.
    if recognition_event == LEDGER_EVENT_WAREHOUSE_DOCUMENT_POSTING:
        pass  # فراخوان از حواله قطعی — بدون نیاز به چک اضافی
    elif recognition_event == LEDGER_EVENT_SALES_INVOICE_DOCUMENT:
        pass

    from app.services.invoice_service import _calculate_invoice_profit

    overhead_pct = Decimal(str(getattr(biz, "invoice_profit_overhead_percent", 0) or 0))

    profit_data = _calculate_invoice_profit(
        db,
        int(business_id),
        int(document_id),
        biz.invoice_profit_calculation_method or "automatic",
        biz.invoice_profit_calculation_basis or "purchase_price",
        bool(getattr(biz, "invoice_profit_include_overhead", False)),
        biz.invoice_profit_overhead_type or "none",
        overhead_pct if getattr(biz, "invoice_profit_overhead_percent", None) else None,
        biz.invoice_profit_calculation_type or "gross",
    )

    line_profits: List[Dict[str, Any]] = profit_data.get("line_profits") or []
    if not line_profits:
        return False

    recognized_at = datetime.utcnow()

    for lp in line_profits:
        lid = lp.get("line_id")
        if lid is None:
            continue
        row = db.query(InvoiceItemLine).filter(
            InvoiceItemLine.id == int(lid),
            InvoiceItemLine.document_id == int(document_id),
        ).first()
        if not row:
            continue
        row.ledger_unit_cogs = Decimal(str(lp.get("cost_per_unit", 0) or 0))
        row.ledger_line_cogs = Decimal(str(lp.get("total_cost", 0) or 0))
        row.ledger_line_gross_profit = Decimal(str(lp.get("gross_profit", 0) or 0))
        row.ledger_recognized_at = recognized_at
        row.ledger_recognition_event = recognition_event

    db.flush()
    return True


def sync_ledger_profit_from_analytical_for_document(
    db: Session,
    business_id: int,
    document_id: int,
) -> bool:
    """
    هم‌رسانی ستون‌های ledger_* با محاسبهٔ تحلیلی جاری، بدون محدودیت مبنای شناسایی اولیه.
    پس از تغییر زنجیرهٔ خرید/موجودی برای به‌روز نگه‌داشتن سود قطعی ثبت‌شده روی خطوط فروش قبلی فراخوانی می‌شود.
    """
    from adapters.db.models.business import Business
    from adapters.db.models.document import Document
    from adapters.db.models.invoice_item_line import InvoiceItemLine
    from app.services.invoice_service import _calculate_invoice_profit

    biz = db.query(Business).filter(Business.id == int(business_id)).first()
    if not biz or getattr(biz, "invoice_profit_calculation_method", None) == "disabled":
        return False

    doc = db.query(Document).filter(Document.id == int(document_id)).first()
    if not doc or doc.business_id != int(business_id):
        return False
    if doc.is_proforma:
        return False
    if doc.document_type not in PROFIT_RECOGNITION_DOCUMENT_TYPES:
        return False

    overhead_pct = Decimal(str(getattr(biz, "invoice_profit_overhead_percent", 0) or 0))

    profit_data = _calculate_invoice_profit(
        db,
        int(business_id),
        int(document_id),
        biz.invoice_profit_calculation_method or "automatic",
        biz.invoice_profit_calculation_basis or "purchase_price",
        bool(getattr(biz, "invoice_profit_include_overhead", False)),
        biz.invoice_profit_overhead_type or "none",
        overhead_pct if getattr(biz, "invoice_profit_overhead_percent", None) else None,
        biz.invoice_profit_calculation_type or "gross",
    )

    line_profits: List[Dict[str, Any]] = profit_data.get("line_profits") or []
    if not line_profits:
        return False

    recognized_at = datetime.utcnow()

    for lp in line_profits:
        lid = lp.get("line_id")
        if lid is None:
            continue
        row = db.query(InvoiceItemLine).filter(
            InvoiceItemLine.id == int(lid),
            InvoiceItemLine.document_id == int(document_id),
        ).first()
        if not row:
            continue
        row.ledger_unit_cogs = Decimal(str(lp.get("cost_per_unit", 0) or 0))
        row.ledger_line_cogs = Decimal(str(lp.get("total_cost", 0) or 0))
        row.ledger_line_gross_profit = Decimal(str(lp.get("gross_profit", 0) or 0))
        row.ledger_recognized_at = recognized_at
        row.ledger_recognition_event = LEDGER_EVENT_INVENTORY_CHAIN_REFRESH

    db.flush()
    return True


def refresh_sales_ledgers_after_inventory_invoice_change(
    db: Session,
    business_id: int,
    product_ids: List[int],
    *,
    fiscal_year_id: Optional[int] = None,
) -> int:
    """پس از ثبت یا ویرایش فاکتور خرید / برگشت از خرید، ledger اسناد فروش و تولید مرتبط را هم‌رسانی می‌کند."""
    from adapters.db.models.document import Document
    from adapters.db.models.invoice_item_line import InvoiceItemLine

    ids = sorted({int(x) for x in product_ids if x is not None})
    if not ids:
        return 0

    q = (
        db.query(Document.id)
        .join(InvoiceItemLine, InvoiceItemLine.document_id == Document.id)
        .filter(
            Document.business_id == int(business_id),
            Document.document_type.in_(PROFIT_RECOGNITION_DOCUMENT_TYPES),
            Document.is_proforma == False,  # noqa: E712
            InvoiceItemLine.product_id.in_(ids),
        )
    )
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == int(fiscal_year_id))

    doc_ids = [int(r[0]) for r in q.distinct().all()]
    updated = 0
    for did in doc_ids:
        try:
            if sync_ledger_profit_from_analytical_for_document(db, business_id, did):
                updated += 1
        except Exception as e:
            logger.warning(
                "ledger refresh failed doc_id=%s business_id=%s err=%s",
                did,
                business_id,
                e,
                exc_info=True,
            )
    return updated


def on_warehouse_document_posted(db: Session, warehouse_document_id: int) -> None:
    """پس از قطعی شدن حواله: اگر منبع فاکتور است، شناسایی قطعی را به‌روز کن."""
    from adapters.db.models.warehouse_document import WarehouseDocument

    wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == int(warehouse_document_id)).first()
    if not wh or getattr(wh, "status", None) != "posted":
        return
    src_type = str(getattr(wh, "source_type", "") or "").strip().lower()
    src_doc_id = getattr(wh, "source_document_id", None)
    if src_type != "invoice" or not src_doc_id:
        return
    try:
        apply_recognized_profit_to_invoice_lines(
            db,
            int(wh.business_id),
            int(src_doc_id),
            recognition_event=LEDGER_EVENT_WAREHOUSE_DOCUMENT_POSTING,
        )
    except Exception as e:
        logger.warning(
            "ledger recognition after warehouse failed wh_id=%s invoice_id=%s err=%s",
            warehouse_document_id,
            src_doc_id,
            e,
            exc_info=True,
        )


def on_sales_invoice_document_finalized(db: Session, invoice_document_id: int) -> None:
    """پس از ذخیرهٔ فاکتور قطعی وقتی مبنای شناسایی «فاکتور» است."""
    from adapters.db.models.document import Document

    doc = db.query(Document).filter(Document.id == int(invoice_document_id)).first()
    if not doc:
        return
    try:
        apply_recognized_profit_to_invoice_lines(
            db,
            int(doc.business_id),
            int(invoice_document_id),
            recognition_event=LEDGER_EVENT_SALES_INVOICE_DOCUMENT,
        )
    except Exception as e:
        logger.warning(
            "ledger recognition on invoice save failed doc_id=%s err=%s",
            invoice_document_id,
            e,
            exc_info=True,
        )


def build_recognized_profit_summary(db: Session, *, document_id: int) -> Optional[Dict[str, Any]]:
    """خلاصهٔ مقادیر شناسایی‌شده از روی ستون‌های خطوط (بدون بازمحاسبه)."""
    from adapters.db.models.invoice_item_line import InvoiceItemLine

    rows = (
        db.query(InvoiceItemLine)
        .filter(InvoiceItemLine.document_id == int(document_id))
        .order_by(InvoiceItemLine.id.asc())
        .all()
    )
    line_parts: List[Dict[str, Any]] = []
    total_sales = Decimal(0)
    total_gp = Decimal(0)
    total_cogs = Decimal(0)
    recognized_count = 0

    for r in rows:
        extra = r.extra_info or {}
        qty = Decimal(str(r.quantity or 0))
        unit_price = Decimal(str(extra.get("unit_price", 0) or 0))
        line_discount = Decimal(str(extra.get("line_discount", 0) or 0))
        sales_amt = qty * unit_price - line_discount
        if getattr(r, "ledger_recognized_at", None) is not None:
            recognized_count += 1
            if r.ledger_line_gross_profit is not None:
                total_gp += Decimal(str(r.ledger_line_gross_profit))
            if r.ledger_line_cogs is not None:
                total_cogs += Decimal(str(r.ledger_line_cogs))
            total_sales += sales_amt
        line_parts.append(
            {
                "line_id": r.id,
                "ledger_unit_cogs": float(r.ledger_unit_cogs) if r.ledger_unit_cogs is not None else None,
                "ledger_line_cogs": float(r.ledger_line_cogs) if r.ledger_line_cogs is not None else None,
                "ledger_line_gross_profit": float(r.ledger_line_gross_profit) if r.ledger_line_gross_profit is not None else None,
                "ledger_recognized_at": r.ledger_recognized_at.isoformat() if r.ledger_recognized_at else None,
                "ledger_recognition_event": r.ledger_recognition_event,
            }
        )

    complete = len(rows) > 0 and recognized_count == len(rows)
    pct = (total_gp / total_sales * Decimal(100)) if total_sales > 0 else Decimal(0)

    return {
        "lines": line_parts,
        "recognition_complete": complete,
        "recognized_line_count": recognized_count,
        "total_line_count": len(rows),
        "gross_profit_recognized": float(total_gp),
        "gross_profit_percent_recognized": float(pct),
        "total_cogs_recognized": float(total_cogs),
        "note": (
            "مقادیر «قطعی دفتر» از آخرین شناسایی ذخیره‌شده؛ "
            "محاسبه تحلیلی زنده در فیلدهای gross_profit بدون پیشوند ledger است."
        ),
    }


def backfill_recognized_profit_for_business(
    db: Session,
    business_id: int,
    *,
    fiscal_year_id: Optional[int] = None,
    invoice_ids: Optional[List[int]] = None,
    limit: Optional[int] = None,
) -> Dict[str, Any]:
    """
    برای اسناد قطعی قبلی شناسایی قطعی را طبق تنظیم فعلی کسب‌وکار تکمیل می‌کند.
    - مبنای حواله: فقط اگر حواله مرتبط قطعی باشد.
    - مبنای فاکتور: برای همهٔ فاکتورهای قطعی ذکرشده.
    """
    from adapters.db.models.business import Business
    from adapters.db.models.document import Document

    biz = db.query(Business).filter(Business.id == int(business_id)).first()
    if not biz or getattr(biz, "invoice_profit_calculation_method", None) == "disabled":
        return {"processed": 0, "skipped": 0, "errors": ["profit calculation disabled or business missing"]}

    basis = normalize_invoice_profit_ledger_basis(getattr(biz, "invoice_profit_ledger_recognition_basis", None))

    q = db.query(Document).filter(
        Document.business_id == int(business_id),
        Document.document_type.in_(PROFIT_RECOGNITION_DOCUMENT_TYPES),
        Document.is_proforma == False,  # noqa: E712
    )
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == int(fiscal_year_id))
    if invoice_ids:
        q = q.filter(Document.id.in_([int(x) for x in invoice_ids]))

    docs = q.order_by(Document.document_date.asc(), Document.id.asc()).all()
    if limit is not None:
        docs = docs[: max(0, int(limit))]

    processed = 0
    skipped = 0
    errors: List[Dict[str, Any]] = []

    for doc in docs:
        try:
            if basis == LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING:
                if not document_has_any_posted_warehouse(db, document_id=int(doc.id)):
                    skipped += 1
                    continue
                ok = apply_recognized_profit_to_invoice_lines(
                    db,
                    int(business_id),
                    int(doc.id),
                    recognition_event=LEDGER_EVENT_WAREHOUSE_DOCUMENT_POSTING,
                )
            else:
                ok = apply_recognized_profit_to_invoice_lines(
                    db,
                    int(business_id),
                    int(doc.id),
                    recognition_event=LEDGER_EVENT_SALES_INVOICE_DOCUMENT,
                )
            if ok:
                processed += 1
            else:
                skipped += 1
        except Exception as e:
            errors.append({"document_id": doc.id, "code": doc.code, "error": str(e)})
            skipped += 1

    db.commit()
    return {
        "processed": processed,
        "skipped": skipped,
        "total_candidates": len(docs),
        "errors": errors[:50],
        "basis_used": basis,
    }
