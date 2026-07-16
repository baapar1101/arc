"""
ثبت بهای تمام‌شده فروش (COGS) در دفتر کل حسابداری.

سطرهای Dr 40001 / Cr موجودی (یا معکوس در برگشت از فروش) روی همان سند فاکتور ثبت می‌شوند
تا در گزارش سود و زیان و بستن سال مالی لحاظ شوند.

زمان شناسایی هم‌راستا با invoice_profit_ledger_recognition_basis:
  - sales_invoice_document: با ثبت فاکتور قطعی
  - warehouse_document_posting: پس از قطعی شدن حواله انبار مرتبط
"""
from __future__ import annotations

import logging
from decimal import Decimal
from typing import Any, Dict, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from app.services.invoice_profit_ledger_service import (
    LEDGER_BASIS_SALES_INVOICE_DOCUMENT,
    LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING,
    document_has_any_posted_warehouse,
    normalize_invoice_profit_ledger_basis,
)

logger = logging.getLogger(__name__)

COGS_GL_SIDE = "gl_cogs"
INVENTORY_COGS_GL_SIDE = "gl_inventory_cogs"

COGS_GL_DOCUMENT_TYPES = frozenset({
    "invoice_sales",
    "invoice_sales_return",
})


def _is_cogs_gl_line(line: DocumentLine) -> bool:
    extra = line.extra_info or {}
    if not isinstance(extra, dict):
        return False
    return extra.get("side") in (COGS_GL_SIDE, INVENTORY_COGS_GL_SIDE)


def _existing_cogs_gl_amount(lines: list[DocumentLine]) -> Decimal:
    """مبلغ COGS ثبت‌شده در دفتر (بدهکار حساب ۴۰۰۰۱)."""
    total = Decimal(0)
    for ln in lines:
        if not _is_cogs_gl_line(ln):
            continue
        extra = ln.extra_info or {}
        if extra.get("side") == COGS_GL_SIDE:
            total += Decimal(str(ln.debit or 0)) - Decimal(str(ln.credit or 0))
    return total


def remove_invoice_cogs_gl_lines(db: Session, document_id: int) -> int:
    """حذف سطرهای COGS/موجودی مرتبط با شناسایی دفتر کل."""
    lines = db.query(DocumentLine).filter(DocumentLine.document_id == int(document_id)).all()
    removed = 0
    for ln in lines:
        if _is_cogs_gl_line(ln):
            db.delete(ln)
            removed += 1
    if removed:
        db.flush()
    return removed


def _evaluate_should_have_cogs_gl(db: Session, document: Document) -> bool:
    if bool(getattr(document, "is_proforma", False)):
        return False
    if str(document.document_type or "") not in COGS_GL_DOCUMENT_TYPES:
        return False

    from adapters.db.models.business import Business

    biz = db.query(Business).filter(Business.id == int(document.business_id)).first()
    if not biz:
        return False

    basis = normalize_invoice_profit_ledger_basis(
        getattr(biz, "invoice_profit_ledger_recognition_basis", None)
    )
    if basis == LEDGER_BASIS_SALES_INVOICE_DOCUMENT:
        return True
    if basis == LEDGER_BASIS_WAREHOUSE_DOCUMENT_POSTING:
        if document_has_any_posted_warehouse(db, document_id=int(document.id)):
            return True
        # اگر ثبت انبار از فاکتور غیرفعال است، حواله‌ای برای شناسایی وجود ندارد؛
        # COGS باید هم‌زمان با ثبت فاکتور قطعی در دفتر کل بیاید.
        extra_info = document.extra_info if isinstance(document.extra_info, dict) else {}
        return not bool(extra_info.get("post_inventory", True))
    return False


def _total_cost_from_profit_data(profit_data: Dict[str, Any]) -> Decimal:
    """استخراج بهای تمام‌شده کل از خروجی محاسبه سود (با fallback به جمع خطوط)."""
    raw_total = profit_data.get("total_cost")
    if raw_total is not None:
        total_cost = Decimal(str(raw_total or 0))
    else:
        total_cost = Decimal(0)
        for line in profit_data.get("line_profits") or []:
            total_cost += Decimal(str(line.get("total_cost", 0) or 0))
    if total_cost < 0:
        total_cost = abs(total_cost)
    return total_cost


def _recognized_ledger_cogs_total_from_document(db: Session, document_id: int) -> Decimal:
    """
    جمع بهای تمام‌شده شناسایی‌شده روی خطوط فاکتور (ستون ledger_line_cogs).

    وقتی محاسبهٔ زندهٔ سود (مثلاً fifo_jbfn) مقدار صفر برمی‌گرداند ولی شناسایی قطعی
    قبلاً روی خطوط ذخیره شده، مبنای ثبت COGS در دفتر کل همان مقادیر شناسایی‌شده است.
    """
    from adapters.db.models.invoice_item_line import InvoiceItemLine

    rows = (
        db.query(InvoiceItemLine)
        .filter(InvoiceItemLine.document_id == int(document_id))
        .all()
    )
    total = Decimal(0)
    for row in rows:
        if getattr(row, "ledger_recognized_at", None) is None:
            continue
        if row.ledger_line_cogs is None:
            continue
        total += abs(Decimal(str(row.ledger_line_cogs)))
    return total


def _calculate_invoice_cogs_amount_for_gl(
    db: Session,
    business_id: int,
    document_id: int,
) -> Decimal:
    """محاسبه بهای تمام‌شده فروش برای ثبت دفتر کل (مستقل از غیرفعال بودن نمایش سود تحلیلی)."""
    from adapters.db.models.business import Business
    from app.services.invoice_service import _calculate_invoice_profit

    biz = db.query(Business).filter(Business.id == int(business_id)).first()
    if not biz:
        return Decimal(0)

    method = getattr(biz, "invoice_profit_calculation_method", None) or "automatic"
    if str(method).strip().lower() == "disabled":
        method = "automatic"

    profit_data = _calculate_invoice_profit(
        db,
        int(business_id),
        int(document_id),
        method,
        getattr(biz, "invoice_profit_calculation_basis", None) or "purchase_price",
        bool(getattr(biz, "invoice_profit_include_overhead", False)),
        getattr(biz, "invoice_profit_overhead_type", None) or "none",
        (
            Decimal(str(getattr(biz, "invoice_profit_overhead_percent", 0) or 0))
            if getattr(biz, "invoice_profit_overhead_percent", None) is not None
            else None
        ),
        getattr(biz, "invoice_profit_calculation_type", None) or "gross",
        fifo_shortage_mode=getattr(biz, "invoice_profit_fifo_shortage_mode", None),
    )

    calculated = _total_cost_from_profit_data(profit_data)
    if calculated > 0:
        return calculated
    return _recognized_ledger_cogs_total_from_document(db, int(document_id))


def _resolve_cogs_gl_accounts(db: Session, document: Document) -> Tuple[Account, Account]:
    from app.services.invoice_service import _resolve_accounts_for_invoice

    data: Dict[str, Any] = {
        "invoice_type": document.document_type,
        "business_id": document.business_id,
        "extra_info": document.extra_info or {},
    }
    accounts = _resolve_accounts_for_invoice(db, data)
    return accounts["cogs"], accounts["inventory"]


def _amounts_close(a: Decimal, b: Decimal, tolerance: Decimal = Decimal("0.01")) -> bool:
    return abs(a - b) <= tolerance


def _post_cogs_gl_lines(
    db: Session,
    document: Document,
    cogs_amount: Decimal,
    cogs_account: Account,
    inventory_account: Account,
) -> None:
    if cogs_amount <= 0:
        return

    amount_f = float(cogs_amount)
    is_return = str(document.document_type or "") == "invoice_sales_return"

    if is_return:
        db.add(
            DocumentLine(
                document_id=document.id,
                account_id=inventory_account.id,
                debit=amount_f,
                credit=0.0,
                description="بهای تمام‌شده برگشت از فروش — ورود به موجودی",
                extra_info={"side": INVENTORY_COGS_GL_SIDE, "source": "invoice_cogs_gl"},
            )
        )
        db.add(
            DocumentLine(
                document_id=document.id,
                account_id=cogs_account.id,
                debit=0.0,
                credit=amount_f,
                description="بهای تمام‌شده برگشت از فروش",
                extra_info={"side": COGS_GL_SIDE, "source": "invoice_cogs_gl"},
            )
        )
    else:
        db.add(
            DocumentLine(
                document_id=document.id,
                account_id=cogs_account.id,
                debit=amount_f,
                credit=0.0,
                description="بهای تمام‌شده کالای فروخته‌شده",
                extra_info={"side": COGS_GL_SIDE, "source": "invoice_cogs_gl"},
            )
        )
        db.add(
            DocumentLine(
                document_id=document.id,
                account_id=inventory_account.id,
                debit=0.0,
                credit=amount_f,
                description="خروج کالا از موجودی (فروش)",
                extra_info={"side": INVENTORY_COGS_GL_SIDE, "source": "invoice_cogs_gl"},
            )
        )
    db.flush()


def resync_invoice_cogs_gl_lines(db: Session, document_id: int) -> bool:
    """
    هم‌رسانی سطرهای COGS دفتر کل با محاسبهٔ جاری و مبنای شناسایی کسب‌وکار.

    Returns:
        True اگر پس از هم‌رسانی سطر COGS با مبلغ مثبت روی سند باشد.
    """
    document = db.query(Document).filter(Document.id == int(document_id)).first()
    if not document:
        return False

    existing_lines = (
        db.query(DocumentLine).filter(DocumentLine.document_id == int(document_id)).all()
    )
    existing_amount = _existing_cogs_gl_amount(existing_lines)

    if not _evaluate_should_have_cogs_gl(db, document):
        if existing_amount > 0:
            remove_invoice_cogs_gl_lines(db, int(document_id))
        return False

    new_amount = _calculate_invoice_cogs_amount_for_gl(
        db, int(document.business_id), int(document.id)
    )

    if new_amount <= 0:
        if existing_amount > 0:
            remove_invoice_cogs_gl_lines(db, int(document_id))
        return False

    if _amounts_close(existing_amount, new_amount):
        return True

    remove_invoice_cogs_gl_lines(db, int(document_id))

    try:
        cogs_account, inventory_account = _resolve_cogs_gl_accounts(db, document)
    except Exception as exc:
        logger.warning(
            "invoice_cogs_gl: account resolution failed doc_id=%s err=%s",
            document_id,
            exc,
            exc_info=True,
        )
        return False

    _post_cogs_gl_lines(db, document, new_amount, cogs_account, inventory_account)

    from adapters.db.repositories.document_repository import DocumentRepository

    doc_repo = DocumentRepository(db)
    all_lines = [
        {
            "account_id": ln.account_id,
            "debit": float(ln.debit or 0),
            "credit": float(ln.credit or 0),
        }
        for ln in db.query(DocumentLine).filter(DocumentLine.document_id == int(document_id)).all()
    ]
    is_valid, balance_error = doc_repo.validate_document_balance(all_lines)
    if not is_valid:
        logger.error(
            "invoice_cogs_gl: document unbalanced after COGS sync doc_id=%s err=%s",
            document_id,
            balance_error,
        )
        remove_invoice_cogs_gl_lines(db, int(document_id))
        db.flush()
        return False

    return True


def on_sales_invoice_cogs_gl_sync(db: Session, invoice_document_id: int) -> None:
    """فراخوانی پس از ثبت/ویرایش فاکتور قطعی."""
    try:
        resync_invoice_cogs_gl_lines(db, int(invoice_document_id))
    except Exception as exc:
        logger.warning(
            "invoice_cogs_gl sync on invoice finalize failed doc_id=%s err=%s",
            invoice_document_id,
            exc,
            exc_info=True,
        )


def on_warehouse_invoice_cogs_gl_sync(db: Session, warehouse_document_id: int) -> None:
    """فراخوانی پس از قطعی شدن حواله با منبع فاکتور."""
    from adapters.db.models.warehouse_document import WarehouseDocument

    wh = (
        db.query(WarehouseDocument)
        .filter(WarehouseDocument.id == int(warehouse_document_id))
        .first()
    )
    if not wh or getattr(wh, "status", None) != "posted":
        return
    src_type = str(getattr(wh, "source_type", "") or "").strip().lower()
    src_doc_id = getattr(wh, "source_document_id", None)
    if src_type != "invoice" or not src_doc_id:
        return
    try:
        resync_invoice_cogs_gl_lines(db, int(src_doc_id))
    except Exception as exc:
        logger.warning(
            "invoice_cogs_gl sync after warehouse post failed wh_id=%s invoice_id=%s err=%s",
            warehouse_document_id,
            src_doc_id,
            exc,
            exc_info=True,
        )


def on_warehouse_invoice_cogs_gl_cancel_sync(
    db: Session,
    *,
    source_type: Optional[str],
    source_document_id: Optional[int],
) -> None:
    """فراخوانی پس از لغو حوالهٔ قطعی مرتبط با فاکتور."""
    if str(source_type or "").strip().lower() != "invoice" or not source_document_id:
        return
    try:
        resync_invoice_cogs_gl_lines(db, int(source_document_id))
    except Exception as exc:
        logger.warning(
            "invoice_cogs_gl sync after warehouse cancel failed invoice_id=%s err=%s",
            source_document_id,
            exc,
            exc_info=True,
        )


def backfill_cogs_gl_for_business(
    db: Session,
    business_id: int,
    *,
    fiscal_year_id: Optional[int] = None,
    invoice_ids: Optional[list[int]] = None,
    limit: Optional[int] = None,
) -> Dict[str, Any]:
    """
    هم‌رسانی سطرهای COGS دفتر کل برای فاکتورهای فروش/برگشت قطعی قبلی.
    برای اسنادی که قبل از پیاده‌سازی این قابلیت ثبت شده‌اند استفاده می‌شود.
    """
    q = (
        db.query(Document)
        .filter(
            Document.business_id == int(business_id),
            Document.document_type.in_(tuple(COGS_GL_DOCUMENT_TYPES)),
            Document.is_proforma == False,  # noqa: E712
        )
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
    errors: list[Dict[str, Any]] = []

    for doc in docs:
        try:
            if resync_invoice_cogs_gl_lines(db, int(doc.id)):
                processed += 1
            else:
                skipped += 1
        except Exception as exc:
            errors.append({"document_id": doc.id, "code": doc.code, "error": str(exc)})
            skipped += 1

    db.commit()
    return {
        "processed": processed,
        "skipped": skipped,
        "total_candidates": len(docs),
        "errors": errors[:50],
    }
