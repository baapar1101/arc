"""
ایجاد/ویرایش گروهی اسناد دریافت و پرداخت برای مهاجرت و ادغام خارجی.
هر آیتم جداگانه؛ خطای یک آیتم بقیه را متوقف نمی‌کند.
"""

from __future__ import annotations

from typing import Any, Dict, List

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from app.core.auth_dependency import AuthContext
from app.core.permissions import has_business_permission_for_business
from app.core.responses import ApiError
from app.services.receipt_payment_service import (
    DOCUMENT_TYPE_PAYMENT,
    DOCUMENT_TYPE_RECEIPT,
    create_receipt_payment,
    update_receipt_payment,
)

MAX_BULK_RECEIPT_PAYMENT_ITEMS = 200
_ALLOWED_TYPES = {DOCUMENT_TYPE_RECEIPT, DOCUMENT_TYPE_PAYMENT}


def _api_error_parts(err: ApiError) -> Dict[str, Any]:
    d = getattr(err, "detail", None)
    if isinstance(d, dict):
        payload = d.get("error") or {}
        return {
            "code": str(payload.get("code") or "API_ERROR"),
            "message": str(payload.get("message") or str(err)),
        }
    return {"code": "API_ERROR", "message": str(err)}


def bulk_upsert_receipts_payments_integration(
    db: Session,
    business_id: int,
    auth_context: AuthContext,
    body: Dict[str, Any],
) -> Dict[str, Any]:
    items = body.get("items")
    if not isinstance(items, list):
        raise ApiError("INVALID_REQUEST", "items باید آرایه باشد", http_status=400)

    if len(items) > MAX_BULK_RECEIPT_PAYMENT_ITEMS:
        raise ApiError(
            "BULK_TOO_LARGE",
            f"حداکثر {MAX_BULK_RECEIPT_PAYMENT_ITEMS} آیتم در هر درخواست مجاز است",
            http_status=400,
        )

    migration_mode = bool(body.get("migration_mode"))
    token = None
    if migration_mode:
        if not has_business_permission_for_business(
            auth_context, db, business_id, "people_transactions", "add"
        ):
            raise ApiError("FORBIDDEN", "مجوز مهاجرت دریافت/پرداخت وجود ندارد", http_status=403)
        from app.services.legacy_import.context import set_legacy_import_active

        token = set_legacy_import_active(True)

    uid = auth_context.get_user_id()
    results: List[Dict[str, Any]] = []

    try:
        for idx, raw in enumerate(items):
            base: Dict[str, Any] = {"index": idx, "client_ref": None}
            if isinstance(raw, dict) and raw.get("client_ref") is not None:
                base["client_ref"] = str(raw.get("client_ref")).strip() or None

            if not isinstance(raw, dict):
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "document_id": None,
                        "error_code": "INVALID_ITEM",
                        "message": "آیتم باید شیٔ JSON باشد",
                    }
                )
                continue

            payload = raw.get("payload")
            if not isinstance(payload, dict):
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "document_id": None,
                        "error_code": "INVALID_PAYLOAD",
                        "message": "payload الزامی است و باید شیٔ باشد",
                    }
                )
                continue

            raw_id = raw.get("document_id")
            document_id_val: int | None = None
            if raw_id not in (None, ""):
                try:
                    document_id_val = int(raw_id)
                except (ValueError, TypeError):
                    document_id_val = None
            if document_id_val is not None and document_id_val <= 0:
                document_id_val = None

            if document_id_val is None:
                if not has_business_permission_for_business(
                    auth_context, db, business_id, "people_transactions", "add"
                ):
                    results.append(
                        {
                            **base,
                            "status": "failed",
                            "document_id": None,
                            "error_code": "FORBIDDEN",
                            "message": "مجوز افزودن دریافت/پرداخت وجود ندارد",
                        }
                    )
                    continue
                doc_type = str(payload.get("document_type") or "").strip()
                if doc_type not in _ALLOWED_TYPES:
                    results.append(
                        {
                            **base,
                            "status": "failed",
                            "document_id": None,
                            "error_code": "INVALID_DOCUMENT_TYPE",
                            "message": f"نوع سند نامعتبر: {doc_type!r}",
                        }
                    )
                    continue
                try:
                    created = create_receipt_payment(db, business_id, int(uid), payload)
                    nid = created.get("id") if isinstance(created, dict) else None
                    results.append(
                        {
                            **base,
                            "status": "created",
                            "document_id": int(nid) if nid is not None else None,
                        }
                    )
                except ApiError as ae:
                    p = _api_error_parts(ae)
                    results.append(
                        {
                            **base,
                            "status": "failed",
                            "document_id": None,
                            "error_code": p["code"],
                            "message": p["message"],
                        }
                    )
                except IntegrityError as e:
                    results.append(
                        {
                            **base,
                            "status": "failed",
                            "document_id": None,
                            "error_code": "INTEGRITY_ERROR",
                            "message": str(getattr(e, "orig", e) or e),
                        }
                    )
            else:
                if not has_business_permission_for_business(
                    auth_context, db, business_id, "people_transactions", "edit"
                ):
                    results.append(
                        {
                            **base,
                            "status": "failed",
                            "document_id": document_id_val,
                            "error_code": "FORBIDDEN",
                            "message": "مجوز ویرایش دریافت/پرداخت وجود ندارد",
                        }
                    )
                    continue
                doc = db.query(Document).filter(Document.id == document_id_val).first()
                if (
                    not doc
                    or int(doc.business_id) != int(business_id)
                    or doc.document_type not in _ALLOWED_TYPES
                ):
                    results.append(
                        {
                            **base,
                            "status": "failed",
                            "document_id": document_id_val,
                            "error_code": "DOCUMENT_NOT_FOUND",
                            "message": "سند دریافت/پرداخت یافت نشد",
                        }
                    )
                    continue
                try:
                    updated = update_receipt_payment(db, document_id_val, int(uid), payload)
                    nid = updated.get("id") if isinstance(updated, dict) else None
                    results.append(
                        {
                            **base,
                            "status": "updated",
                            "document_id": int(nid) if nid is not None else document_id_val,
                        }
                    )
                except ApiError as ae:
                    p = _api_error_parts(ae)
                    results.append(
                        {
                            **base,
                            "status": "failed",
                            "document_id": document_id_val,
                            "error_code": p["code"],
                            "message": p["message"],
                        }
                    )
                except IntegrityError as e:
                    results.append(
                        {
                            **base,
                            "status": "failed",
                            "document_id": document_id_val,
                            "error_code": "INTEGRITY_ERROR",
                            "message": str(getattr(e, "orig", e) or e),
                        }
                    )
    finally:
        if token is not None:
            from app.services.legacy_import.context import reset_legacy_import_active

            reset_legacy_import_active(token)

    summary = {
        "total": len(items),
        "created": sum(1 for r in results if r.get("status") == "created"),
        "updated": sum(1 for r in results if r.get("status") == "updated"),
        "failed": sum(1 for r in results if r.get("status") == "failed"),
    }
    return {"results": results, "summary": summary}
