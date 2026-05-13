"""
ایجاد/ویرایش گروهی فاکتورها برای ادغام (مثل چند سفارش ووکامرس در یک تماس شبکه از سمت افزونه).
هر آیتم در تراکنش/منطق جدا؛ خطای یک آیتم بقیه را متوقف نمی‌کند.
"""

from typing import Any, Dict, List

from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from adapters.db.models.document import Document
from app.core.auth_dependency import AuthContext
from app.core.permissions import (
    has_business_permission_for_business,
    has_invoice_type_permission_for_business,
)
from app.core.responses import ApiError
from app.services.invoice_service import create_invoice, update_invoice, SUPPORTED_INVOICE_TYPES

MAX_BULK_INVOICE_ITEMS = 1000


def _api_error_parts(err: ApiError) -> Dict[str, Any]:
    d = getattr(err, "detail", None)
    if isinstance(d, dict):
        payload = d.get("error") or {}
        return {
            "code": str(payload.get("code") or "API_ERROR"),
            "message": str(payload.get("message") or str(err)),
        }
    return {"code": "API_ERROR", "message": str(err)}


def bulk_upsert_invoices_integration(
    db: Session,
    business_id: int,
    auth_context: AuthContext,
    body: Dict[str, Any],
    *,
    user_can_select_fx_rate: bool,
) -> Dict[str, Any]:
    items = body.get("items")
    if not isinstance(items, list):
        raise ApiError("INVALID_REQUEST", "items باید آرایه باشد", http_status=400)

    if len(items) > MAX_BULK_INVOICE_ITEMS:
        raise ApiError(
            "BULK_TOO_LARGE",
            f"حداکثر {MAX_BULK_INVOICE_ITEMS} آیتم در هر درخواست مجاز است",
            http_status=400,
        )

    uid = auth_context.get_user_id()

    results: List[Dict[str, Any]] = []

    for idx, raw in enumerate(items):
        base = {"index": idx}
        cref = raw.get("client_ref") if isinstance(raw, dict) else None
        if cref is not None:
            base["client_ref"] = str(cref).strip() or None
        else:
            base["client_ref"] = None

        if not isinstance(raw, dict):
            results.append(
                {
                    **base,
                    "status": "failed",
                    "invoice_id": None,
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
                    "invoice_id": None,
                    "error_code": "INVALID_PAYLOAD",
                    "message": "payload الزامی است و باید شیٔ باشد",
                }
            )
            continue

        inv_type = str(payload.get("invoice_type") or "").strip()

        raw_iid = raw.get("invoice_id")
        invoice_id_val: int | None = None
        if raw_iid not in (None, ""):
            try:
                invoice_id_val = int(raw_iid)
            except (ValueError, TypeError):
                invoice_id_val = None
        if invoice_id_val is not None and invoice_id_val <= 0:
            invoice_id_val = None

        # --- ایجاد ---
        if invoice_id_val is None:
            if not has_business_permission_for_business(auth_context, db, business_id, "invoices", "add"):
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": None,
                        "error_code": "FORBIDDEN",
                        "message": "مجوز افزودن فاکتور وجود ندارد",
                    }
                )
                continue
            if inv_type not in SUPPORTED_INVOICE_TYPES:
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": None,
                        "error_code": "INVALID_INVOICE_TYPE",
                        "message": f"نوع فاکتور نامعتبر: {inv_type!r}",
                    }
                )
                continue
            if not has_invoice_type_permission_for_business(
                auth_context, db, business_id, inv_type, "add"
            ):
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": None,
                        "error_code": "FORBIDDEN",
                        "message": f"مجوز ثبت برای نوع سند ({inv_type}) وجود ندارد",
                    }
                )
                continue
            try:
                doc_dict = create_invoice(
                    db=db,
                    business_id=business_id,
                    user_id=int(uid),
                    data=payload,
                    user_can_select_fx_rate=user_can_select_fx_rate,
                )
                nid = doc_dict.get("id") if isinstance(doc_dict, dict) else None
                results.append(
                    {
                        **base,
                        "status": "created",
                        "invoice_id": int(nid) if nid is not None else None,
                    }
                )
            except ApiError as ae:
                p = _api_error_parts(ae)
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": None,
                        "error_code": p["code"],
                        "message": p["message"],
                    }
                )
            except IntegrityError as e:
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": None,
                        "error_code": "INTEGRITY_ERROR",
                        "message": str(getattr(e, "orig", e) or e),
                    }
                )

        else:
            # --- ویرایش ---
            if not has_business_permission_for_business(auth_context, db, business_id, "invoices", "edit"):
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": invoice_id_val,
                        "error_code": "FORBIDDEN",
                        "message": "مجوز ویرایش فاکتور وجود ندارد",
                    }
                )
                continue

            doc = db.query(Document).filter(Document.id == invoice_id_val).first()
            if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": invoice_id_val,
                        "error_code": "DOCUMENT_NOT_FOUND",
                        "message": "فاکتور یافت نشد یا نامعتبر است",
                    }
                )
                continue

            if not has_invoice_type_permission_for_business(
                auth_context, db, business_id, doc.document_type, "edit"
            ):
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": invoice_id_val,
                        "error_code": "FORBIDDEN",
                        "message": f"مجوز ویرایش برای نوع سند ({doc.document_type}) وجود ندارد",
                    }
                )
                continue

            try:
                doc_dict = update_invoice(
                    db=db,
                    document_id=invoice_id_val,
                    user_id=int(uid),
                    data=payload,
                    user_can_select_fx_rate=user_can_select_fx_rate,
                )
                nid = doc_dict.get("id") if isinstance(doc_dict, dict) else None
                results.append(
                    {
                        **base,
                        "status": "updated",
                        "invoice_id": int(nid) if nid is not None else invoice_id_val,
                    }
                )
            except ApiError as ae:
                p = _api_error_parts(ae)
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": invoice_id_val,
                        "error_code": p["code"],
                        "message": p["message"],
                    }
                )
            except IntegrityError as e:
                results.append(
                    {
                        **base,
                        "status": "failed",
                        "invoice_id": invoice_id_val,
                        "error_code": "INTEGRITY_ERROR",
                        "message": str(getattr(e, "orig", e) or e),
                    }
                )

    summary = {
        "total": len(items),
        "created": sum(1 for r in results if r.get("status") == "created"),
        "updated": sum(1 for r in results if r.get("status") == "updated"),
        "failed": sum(1 for r in results if r.get("status") == "failed"),
    }

    return {"results": results, "summary": summary}
