"""
برگشت از سال مالی جاری: حذف سال مالی is_last و بازگرداندن سال قبل به عنوان جاری،
همراه با حذف اسناد سال جاری و اسناد اختتامیهٔ سال قبل.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import time
from datetime import date, datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.wallet import WalletTransaction
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from app.core.i18n import Translator, apply_format
from app.core.responses import ApiError
from app.core.settings import get_settings
from app.services.invoice_service import SUPPORTED_INVOICE_TYPES, delete_invoice

logger = logging.getLogger(__name__)

SYSTEM_EXTRA_INFO_SOURCES = frozenset({"document_monetization", "storage_invoice"})

_TOKEN_TTL_SEC = 600


def _tr(tr: Translator, key: str, default: str, **fmt: Any) -> str:
    template = tr.t(key, default=default)
    return apply_format(template, **fmt)


def _source_label(tr: Translator, src: str) -> str:
    if src == "document_monetization":
        return tr.t(
            "ROLLBACK_SOURCE_DOCUMENT_MONETIZATION",
            default="document services charge (system)",
        )
    if src == "storage_invoice":
        return tr.t(
            "ROLLBACK_SOURCE_STORAGE_INVOICE",
            default="storage invoice (system)",
        )
    return str(src)


def _b64url_decode_padded(data: str) -> bytes:
    pad = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + pad)


def issue_rollback_confirmation_token(
    *,
    business_id: int,
    user_id: int,
    remove_fiscal_year_id: int,
    previous_fiscal_year_id: int,
) -> str:
    settings = get_settings()
    secret = getattr(settings, "share_link_secret", None) or "change_me_share_link"
    payload = {
        "bid": business_id,
        "uid": user_id,
        "rfy": remove_fiscal_year_id,
        "pfy": previous_fiscal_year_id,
        "exp": int(time.time()) + _TOKEN_TTL_SEC,
    }
    body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    b = base64.urlsafe_b64encode(body).decode("ascii").rstrip("=")
    sig = hmac.new(str(secret).encode("utf-8"), body, hashlib.sha256).digest()
    s = base64.urlsafe_b64encode(sig).decode("ascii").rstrip("=")
    return f"{b}.{s}"


def verify_rollback_confirmation_token(
    token: str,
    *,
    business_id: int,
    user_id: int,
    tr: Translator,
) -> Tuple[int, int]:
    """برمی‌گرداند (remove_fiscal_year_id, previous_fiscal_year_id)"""
    if not token or not str(token).strip():
        raise ApiError(
            "ROLLBACK_INVALID_TOKEN",
            _tr(
                tr,
                "ROLLBACK_TOKEN_EMPTY",
                "Confirmation token is empty. Use Run from the preview page or refresh the preview.",
            ),
            http_status=400,
        )
    try:
        parts = str(token).strip().split(".", 1)
        if len(parts) != 2:
            raise ApiError(
                "ROLLBACK_INVALID_TOKEN",
                _tr(
                    tr,
                    "ROLLBACK_TOKEN_MALFORMED",
                    "Confirmation token is incomplete or invalid. Close this page, sign in again, and take a new preview.",
                ),
                http_status=400,
            )
        body_raw, sig_raw = parts
        body = _b64url_decode_padded(body_raw)
        sig = _b64url_decode_padded(sig_raw)
        settings = get_settings()
        secret = getattr(settings, "share_link_secret", None) or "change_me_share_link"
        expected = hmac.new(str(secret).encode("utf-8"), body, hashlib.sha256).digest()
        if not hmac.compare_digest(sig, expected):
            raise ApiError(
                "ROLLBACK_INVALID_TOKEN",
                _tr(
                    tr,
                    "ROLLBACK_TOKEN_BAD_SIGNATURE",
                    "Confirmation token signature is invalid. Server settings may have changed; take a new preview.",
                ),
                http_status=400,
            )
        payload = json.loads(body.decode("utf-8"))
        if int(payload.get("bid", 0)) != int(business_id):
            raise ApiError(
                "ROLLBACK_INVALID_TOKEN",
                _tr(
                    tr,
                    "ROLLBACK_TOKEN_WRONG_BUSINESS",
                    "This confirmation token is not for the current business. Use the same business where you opened the preview.",
                ),
                http_status=400,
            )
        if int(payload.get("uid", 0)) != int(user_id):
            raise ApiError(
                "ROLLBACK_INVALID_TOKEN",
                _tr(
                    tr,
                    "ROLLBACK_TOKEN_WRONG_USER",
                    "This confirmation token belongs to another user or your session changed. Sign in again and refresh the preview.",
                ),
                http_status=400,
            )
        exp = int(payload.get("exp", 0))
        if exp <= 0:
            raise ApiError(
                "ROLLBACK_INVALID_TOKEN",
                _tr(
                    tr,
                    "ROLLBACK_TOKEN_INVALID_EXP",
                    "Confirmation token is invalid. Take a new preview.",
                ),
                http_status=400,
            )
        if int(time.time()) > exp:
            raise ApiError(
                "ROLLBACK_TOKEN_EXPIRED",
                _tr(
                    tr,
                    "ROLLBACK_TOKEN_EXPIRED",
                    "The confirmation period ({minutes} minutes) has expired. Take a new preview to continue.",
                    minutes=_TOKEN_TTL_SEC // 60,
                ),
                http_status=400,
            )
        return int(payload["rfy"]), int(payload["pfy"])
    except ApiError:
        raise
    except (json.JSONDecodeError, TypeError, ValueError, KeyError):
        logger.warning("rollback_token_parse_failed", exc_info=True)
        raise ApiError(
            "ROLLBACK_INVALID_TOKEN",
            _tr(
                tr,
                "ROLLBACK_TOKEN_PARSE_FAILED",
                "Could not read the confirmation token. Take a new preview and run immediately.",
            ),
            http_status=400,
        ) from None


def _resolve_current_and_previous(
    db: Session, business_id: int, tr: Translator
) -> Tuple[FiscalYear, FiscalYear]:
    repo = FiscalYearRepository(db)
    all_years = repo.list_by_business(business_id)
    if len(all_years) < 2:
        raise ApiError(
            "ROLLBACK_NOT_ENOUGH_FISCAL_YEARS",
            _tr(
                tr,
                "ROLLBACK_NOT_ENOUGH_FISCAL_YEARS",
                "At least two fiscal years are required to remove the current year and go back. If you only have one year, this action is not available.",
            ),
            http_status=400,
        )
    current = repo.get_current_for_business(business_id)
    if not current:
        raise ApiError(
            "NO_CURRENT_FISCAL_YEAR",
            _tr(
                tr,
                "NO_CURRENT_FISCAL_YEAR",
                "No fiscal year is marked as current. Fix fiscal years in settings or contact support.",
            ),
            http_status=400,
        )
    if int(current.business_id) != int(business_id):
        raise ApiError(
            "FISCAL_YEAR_MISMATCH",
            _tr(
                tr,
                "FISCAL_YEAR_MISMATCH",
                "The fiscal year does not belong to this business. Check access or business id.",
            ),
            http_status=400,
        )

    ordered = sorted(all_years, key=lambda fy: fy.start_date, reverse=True)
    if ordered[0].id != current.id:
        logger.warning(
            "fiscal_year_is_last_mismatch",
            extra={"business_id": business_id, "newest_id": ordered[0].id, "is_last_id": current.id},
        )
    try:
        idx = next(i for i, fy in enumerate(ordered) if fy.id == current.id)
    except StopIteration:
        raise ApiError(
            "FISCAL_YEAR_NOT_IN_LIST",
            _tr(
                tr,
                "FISCAL_YEAR_NOT_IN_LIST",
                "Current fiscal year is missing from this business list; data may be inconsistent. Contact support.",
            ),
            http_status=500,
        )
    if idx + 1 >= len(ordered):
        raise ApiError(
            "ROLLBACK_NO_PREVIOUS_YEAR",
            _tr(
                tr,
                "ROLLBACK_NO_PREVIOUS_YEAR",
                "No older fiscal year was found to roll back to. An older year than the current one must exist.",
            ),
            http_status=400,
        )
    previous = ordered[idx + 1]
    return current, previous


def _collect_document_block_reasons(db: Session, document: Document, tr: Translator) -> List[str]:
    reasons: List[str] = []
    extra = document.extra_info if isinstance(document.extra_info, dict) else {}
    src = extra.get("source")
    if src in SYSTEM_EXTRA_INFO_SOURCES:
        label = _source_label(tr, str(src))
        reasons.append(
            _tr(
                tr,
                "ROLLBACK_REASON_SYSTEM_DOC",
                "This document is a system-internal record ({label}). Removing it may break wallet or billing consistency.",
                label=label,
            )
        )

    if extra.get("tax_workspace"):
        reasons.append(
            _tr(
                tr,
                "ROLLBACK_REASON_TAX_WORKSPACE",
                "This document is in the tax workspace; fiscal rollback is blocked until it is cleared from the workspace.",
            )
        )

    locked_flags = []
    if isinstance(document.extra_info, dict):
        locked_flags.append(bool(document.extra_info.get("locked")))
        locked_flags.append(bool(document.extra_info.get("is_locked")))
    if isinstance(document.developer_settings, dict):
        locked_flags.append(bool(document.developer_settings.get("locked")))
        locked_flags.append(bool(document.developer_settings.get("is_locked")))
    if any(locked_flags):
        reasons.append(
            _tr(
                tr,
                "ROLLBACK_REASON_LOCKED",
                "Document is locked; remove the lock or void it through the proper workflow.",
            )
        )

    from app.services.wallet_service import check_document_has_wallet_transactions

    w = check_document_has_wallet_transactions(db, document.id)
    if w.get("has_wallet_transactions") and w.get("has_protected_transactions"):
        wm = w.get("message")
        if wm:
            reasons.append(str(wm))
        else:
            reasons.append(
                _tr(
                    tr,
                    "ROLLBACK_REASON_WALLET_PROTECTED_FALLBACK",
                    "This document has protected system wallet transactions; removing the fiscal year is not allowed to preserve financial integrity.",
                )
            )

    if db.query(DocumentLine).filter(
        DocumentLine.document_id == document.id,
        DocumentLine.check_id.isnot(None),
    ).first():
        reasons.append(
            _tr(
                tr,
                "ROLLBACK_REASON_CHECK_LINES",
                "This document has lines linked to checks; fix check status first.",
            )
        )

    try:
        from adapters.db.models.ai_invoice import AIInvoice

        if (
            db.query(AIInvoice)
            .filter(AIInvoice.document_id == document.id)
            .first()
        ):
            reasons.append(
                _tr(
                    tr,
                    "ROLLBACK_REASON_AI_INVOICE",
                    "This document is linked to AI billing; contact support before rolling back the fiscal year.",
                )
            )
    except Exception:
        pass

    return reasons


def _plugin_purchase_blocks_rollback(
    db: Session, business_id: int, fy_start: date, fy_end: date, tr: Translator
) -> Optional[str]:
    start_dt = datetime.combine(fy_start, datetime.min.time())
    end_dt = datetime.combine(fy_end, datetime.max.time())
    q = (
        db.query(WalletTransaction)
        .filter(
            WalletTransaction.business_id == int(business_id),
            WalletTransaction.type == "plugin_purchase",
            WalletTransaction.status == "succeeded",
            WalletTransaction.created_at >= start_dt,
            WalletTransaction.created_at <= end_dt,
        )
        .first()
    )
    if q:
        return _tr(
            tr,
            "ROLLBACK_PLUGIN_PURCHASE_BLOCK",
            "A successful add-on purchase from the wallet exists in this fiscal year. Removing the current year may break reports or licenses; contact support.",
        )
    return None


def preview_current_fiscal_year_rollback(
    db: Session, business_id: int, user_id: int, tr: Translator
) -> Dict[str, Any]:
    current, previous = _resolve_current_and_previous(db, business_id, tr)

    docs = (
        db.query(Document)
        .filter(
            Document.business_id == int(business_id),
            Document.fiscal_year_id == current.id,
        )
        .order_by(Document.id.asc())
        .all()
    )

    block_reasons: List[str] = []
    counts_by_type: Dict[str, int] = {}
    for d in docs:
        counts_by_type[d.document_type] = counts_by_type.get(d.document_type, 0) + 1
        for r in _collect_document_block_reasons(db, d, tr):
            msg = _tr(
                tr,
                "ROLLBACK_BLOCK_DOC_LINE",
                "Document {code} (type: {doc_type}) — {reason}",
                code=d.code,
                doc_type=d.document_type,
                reason=r,
            )
            if msg not in block_reasons:
                block_reasons.append(msg)

    pp = _plugin_purchase_blocks_rollback(db, business_id, current.start_date, current.end_date, tr)
    if pp:
        block_reasons.append(pp)

    closing_on_previous = (
        db.query(Document)
        .filter(
            Document.business_id == int(business_id),
            Document.fiscal_year_id == previous.id,
            Document.document_type.in_(("year_end_closing", "person_balance")),
        )
        .all()
    )
    closing_ids = [d.id for d in closing_on_previous]

    for d in closing_on_previous:
        for r in _collect_document_block_reasons(db, d, tr):
            kind_key = (
                "ROLLBACK_DOC_KIND_YEAR_END_CLOSING"
                if d.document_type == "year_end_closing"
                else "ROLLBACK_DOC_KIND_PERSON_BALANCE"
            )
            kind_default = (
                "year-end closing" if d.document_type == "year_end_closing" else "person balance"
            )
            kind = tr.t(kind_key, default=kind_default)
            msg = _tr(
                tr,
                "ROLLBACK_BLOCK_PREV_YEAR_LINE",
                "Previous year — {kind} document ({code}) — {reason}",
                kind=kind,
                code=d.code,
                reason=r,
            )
            if msg not in block_reasons:
                block_reasons.append(msg)

    can_execute = len(block_reasons) == 0

    token = None
    if can_execute:
        token = issue_rollback_confirmation_token(
            business_id=int(business_id),
            user_id=int(user_id),
            remove_fiscal_year_id=int(current.id),
            previous_fiscal_year_id=int(previous.id),
        )

    return {
        "can_execute": can_execute,
        "block_reasons": block_reasons,
        "current_fiscal_year": {
            "id": current.id,
            "title": current.title,
            "start_date": current.start_date,
            "end_date": current.end_date,
        },
        "previous_fiscal_year": {
            "id": previous.id,
            "title": previous.title,
            "start_date": previous.start_date,
            "end_date": previous.end_date,
        },
        "documents_in_current_year_count": len(docs),
        "documents_by_type": counts_by_type,
        "closing_documents_on_previous_year_ids": closing_ids,
        "confirmation_token": token,
        "confirmation_token_expires_in_seconds": _TOKEN_TTL_SEC,
    }


def _unlink_repair_invoices(db: Session, document_ids: List[int]) -> None:
    if not document_ids:
        return
    try:
        from adapters.db.models.repair_shop import RepairInvoice

        db.query(RepairInvoice).filter(RepairInvoice.document_id.in_(document_ids)).delete(
            synchronize_session=False
        )
    except Exception as exc:
        logger.warning("unlink_repair_invoices_failed", extra={"error": str(exc)})


def _purge_warehouse_documents_for_fiscal_year(
    db: Session, business_id: int, fiscal_year_id: int, tr: Translator
) -> None:
    try:
        from adapters.db.models.warehouse_document import WarehouseDocument
        from adapters.db.models.warehouse_document_line import WarehouseDocumentLine

        wds = (
            db.query(WarehouseDocument)
            .filter(
                WarehouseDocument.business_id == int(business_id),
                WarehouseDocument.fiscal_year_id == int(fiscal_year_id),
            )
            .all()
        )
        for wd in wds:
            db.query(WarehouseDocumentLine).filter(
                WarehouseDocumentLine.warehouse_document_id == wd.id
            ).delete(synchronize_session=False)
            db.delete(wd)
    except Exception as exc:
        logger.error("purge_warehouse_documents_failed", extra={"error": str(exc)})
        raise ApiError(
            "ROLLBACK_WAREHOUSE_PURGE_FAILED",
            _tr(
                tr,
                "ROLLBACK_WAREHOUSE_PURGE_FAILED",
                "Could not delete warehouse documents for this fiscal year. Check database connection or locks. Details: {detail}",
                detail=str(exc),
            ),
            http_status=500,
        ) from exc


def _purge_repair_orders_for_fiscal_year(
    db: Session, business_id: int, fiscal_year_id: int, tr: Translator
) -> None:
    try:
        from adapters.db.models.repair_shop import RepairOrder

        orders = (
            db.query(RepairOrder)
            .filter(
                RepairOrder.business_id == int(business_id),
                RepairOrder.fiscal_year_id == int(fiscal_year_id),
            )
            .all()
        )
        for o in orders:
            db.delete(o)
    except Exception as exc:
        logger.error("purge_repair_orders_failed", extra={"error": str(exc)})
        raise ApiError(
            "ROLLBACK_REPAIR_PURGE_FAILED",
            _tr(
                tr,
                "ROLLBACK_REPAIR_PURGE_FAILED",
                "Could not delete repair-shop orders for this fiscal year. Fix linked documents first. Details: {detail}",
                detail=str(exc),
            ),
            http_status=500,
        ) from exc


def _hard_delete_document(db: Session, document_id: int) -> None:
    db.query(DocumentLine).filter(DocumentLine.document_id == document_id).delete(synchronize_session=False)
    db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == document_id).delete(synchronize_session=False)
    doc = db.query(Document).filter(Document.id == document_id).first()
    if doc:
        db.delete(doc)


def _delete_documents_for_fiscal_year(
    db: Session, business_id: int, fiscal_year_id: int, tr: Translator
) -> None:
    docs = (
        db.query(Document)
        .filter(
            Document.business_id == int(business_id),
            Document.fiscal_year_id == int(fiscal_year_id),
        )
        .order_by(Document.id.asc())
        .all()
    )
    doc_ids = [d.id for d in docs]
    _unlink_repair_invoices(db, doc_ids)

    invoices = [d for d in docs if d.document_type in SUPPORTED_INVOICE_TYPES]
    others = [d for d in docs if d.document_type not in SUPPORTED_INVOICE_TYPES]

    for d in invoices:
        delete_invoice(db, d.id, commit=False)

    from app.services.transfer_service import delete_transfer
    from app.services.receipt_payment_service import delete_receipt_payment
    from app.services.expense_income_service import delete_expense_income
    from app.services.document_service import delete_document

    for d in others:
        dtype = d.document_type
        if dtype == "transfer":
            delete_transfer(db, d.id, commit=False)
        elif dtype in ("receipt", "payment"):
            ok = delete_receipt_payment(db, d.id, commit=False)
            if not ok:
                raise ApiError(
                    "ROLLBACK_DELETE_RECEIPT_PAYMENT_FAILED",
                    _tr(
                        tr,
                        "ROLLBACK_DELETE_RECEIPT_PAYMENT_FAILED",
                        'Receipt/payment document "{code}" could not be deleted. Contact support.',
                        code=d.code,
                    ),
                    http_status=500,
                )
        elif dtype in ("expense", "income"):
            ok = delete_expense_income(db, d.id, commit=False)
            if not ok:
                raise ApiError(
                    "ROLLBACK_DELETE_EXPENSE_INCOME_FAILED",
                    _tr(
                        tr,
                        "ROLLBACK_DELETE_EXPENSE_INCOME_FAILED",
                        'Expense/income document "{code}" could not be deleted. Check database constraints.',
                        code=d.code,
                    ),
                    http_status=500,
                )
        elif dtype == "manual":
            delete_document(db, d.id, commit=False)
        elif dtype in (
            "opening_balance",
            "year_end_closing",
            "person_balance",
            "inventory_transfer",
        ):
            _hard_delete_document(db, d.id)
        else:
            logger.warning("rollback_unknown_document_type", extra={"type": dtype, "id": d.id})
            _hard_delete_document(db, d.id)

    # Session با autoflush=False است؛ _hard_delete_document فقط db.delete می‌زند و flush نمی‌کند.
    # بدون flush، پرس و جوی count آخر روی دیتابیس رکوردهای «در انتظار حذف» را هنوز می‌بیند.
    db.flush()

    remaining = (
        db.query(Document)
        .filter(
            Document.business_id == int(business_id),
            Document.fiscal_year_id == int(fiscal_year_id),
        )
        .count()
    )
    if remaining:
        # برای تشخیص نوع(های) باقی‌مانده در لاگ/پشتیبانی
        rem_docs = (
            db.query(Document)
            .filter(
                Document.business_id == int(business_id),
                Document.fiscal_year_id == int(fiscal_year_id),
            )
            .limit(30)
            .all()
        )
        rem_samples = [
            {"id": d.id, "code": d.code, "document_type": d.document_type} for d in rem_docs
        ]
        logger.error(
            "rollback_documents_still_remaining",
            extra={
                "business_id": business_id,
                "fiscal_year_id": fiscal_year_id,
                "sample": rem_samples,
            },
        )
        raise ApiError(
            "ROLLBACK_DOCUMENTS_REMAINING",
            _tr(
                tr,
                "ROLLBACK_DOCUMENTS_REMAINING",
                "After deletion attempts, {count} document(s) still remain in this fiscal year. An unsupported document type may exist; contact support with the fiscal year id.",
                count=remaining,
            ),
            http_status=500,
        )


def execute_current_fiscal_year_rollback(
    db: Session,
    business_id: int,
    user_id: int,
    confirmation_token: str,
    tr: Translator,
    request: Any = None,
) -> Dict[str, Any]:
    preview = preview_current_fiscal_year_rollback(db, business_id, user_id, tr)
    if not preview["can_execute"]:
        raise ApiError(
            "ROLLBACK_BLOCKED",
            _tr(
                tr,
                "ROLLBACK_BLOCKED",
                "The current fiscal year cannot be removed due to safety or system dependencies. Resolve the items shown in the preview block list, then refresh the preview.",
            ),
            http_status=409,
        )

    remove_id, prev_id = verify_rollback_confirmation_token(
        confirmation_token,
        business_id=int(business_id),
        user_id=int(user_id),
        tr=tr,
    )

    current, previous = _resolve_current_and_previous(db, business_id, tr)
    if int(remove_id) != int(current.id) or int(prev_id) != int(previous.id):
        raise ApiError(
            "ROLLBACK_STALE_TOKEN",
            _tr(
                tr,
                "ROLLBACK_STALE_TOKEN",
                "The current or previous fiscal year changed between preview and confirm. Take a fresh preview and run immediately.",
            ),
            http_status=409,
        )

    try:
        _purge_warehouse_documents_for_fiscal_year(db, business_id, current.id, tr)
        _delete_documents_for_fiscal_year(db, business_id, current.id, tr)
        _purge_repair_orders_for_fiscal_year(db, business_id, current.id, tr)

        closing_docs = (
            db.query(Document)
            .filter(
                Document.business_id == int(business_id),
                Document.fiscal_year_id == previous.id,
                Document.document_type.in_(("year_end_closing", "person_balance")),
            )
            .all()
        )
        for d in closing_docs:
            _hard_delete_document(db, d.id)

        db.query(FiscalYear).filter(FiscalYear.id == current.id).delete(synchronize_session=False)

        all_remaining = db.query(FiscalYear).filter(FiscalYear.business_id == int(business_id)).all()
        for fy in all_remaining:
            fy.is_last = fy.id == previous.id
        db.flush()

        try:
            from app.services.activity_log_service import log_activity

            log_activity(
                db,
                user_id=int(user_id),
                category="settings",
                action="fiscal_year_rollback",
                description=_tr(
                    tr,
                    "ROLLBACK_ACTIVITY_LOG",
                    "Removed fiscal year {removed} and set current to {current}",
                    removed=str(current.title),
                    current=str(previous.title),
                ),
                business_id=int(business_id),
                entity_type="fiscal_year",
                entity_id=previous.id,
                before_data={"removed_fiscal_year_id": current.id},
                after_data={"current_fiscal_year_id": previous.id},
                request=request,
            )
        except Exception as exc:
            logger.warning("rollback_activity_log_failed", extra={"error": str(exc)})

        db.commit()
    except ApiError:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        logger.exception("fiscal_year_rollback_failed")
        raise ApiError(
            "ROLLBACK_FAILED",
            _tr(
                tr,
                "ROLLBACK_FAILED",
                "Fiscal rollback did not complete; no changes were saved. Check network, server load, or database errors and try again. Details: {detail}",
                detail=str(exc),
            ),
            http_status=500,
        ) from exc

    try:
        from app.core.cache import get_cache

        cache = get_cache()
        if cache.enabled:
            cache.delete(f"fiscal_years:{business_id}")
    except Exception:
        pass

    try:
        from app.services.document_service import invalidate_documents_cache
        from app.services.invoice_service import invalidate_invoices_cache

        invalidate_documents_cache(business_id=int(business_id), fiscal_year_id=int(previous.id))
        invalidate_invoices_cache(business_id=int(business_id), fiscal_year_id=int(previous.id))
    except Exception as exc:
        logger.warning("rollback_cache_invalidate_failed", extra={"error": str(exc)})

    return {
        "removed_fiscal_year_id": int(current.id),
        "current_fiscal_year_id": int(previous.id),
        "message": _tr(
            tr,
            "ROLLBACK_SUCCESS_MESSAGE",
            "Current fiscal year was removed; the previous year is now current. You can register or edit documents in that year subject to its rules.",
        ),
    }
