"""Read-only and preflight MCP tools for tax workspace operations."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction


def register_tax_extra_functions(registry: Any) -> None:
    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}

    def _invoice(context: Dict[str, Any], invoice_id: Any, *, lock: bool = False):
        from adapters.db.models.document import Document
        from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active

        business_id = int(context["business_id"])
        ensure_moadian_plugin_active(context["db"], business_id)
        try:
            invoice_id = int(invoice_id)
        except (TypeError, ValueError) as exc:
            raise ValueError("invoice_id باید شناسهٔ عددی باشد") from exc
        query = context["db"].query(Document).filter(
            Document.id == invoice_id, Document.business_id == business_id,
            Document.document_type.in_(["invoice_sales", "invoice_sales_return"]),
        )
        if lock:
            query = query.with_for_update()
        doc = query.first()
        if not doc:
            raise ValueError("فاکتور فروش در کسب‌وکار متصل پیدا نشد")
        return doc

    def tax_reference_candidates(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy import Boolean, cast
        from sqlalchemy.dialects.postgresql import JSONB
        from adapters.db.models.document import Document
        from adapters.db.models.tax_setting import TaxSetting
        from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active
        from app.services.tax_reference_service import compute_taxid_for_document

        db = context["db"]
        business_id = int(context["business_id"])
        ensure_moadian_plugin_active(db, business_id)
        limit = min(max(int(args.get("limit", 50)), 1), 200)
        query_text = str(args.get("query") or "").strip()
        extra = cast(Document.extra_info, JSONB)
        query = db.query(Document).filter(
            Document.business_id == business_id,
            Document.document_type == "invoice_sales",
            cast(extra["tax_workspace"], Boolean).is_(True),
            extra["tax_status"].astext.in_(["sent", "finalized"]),
        )
        if query_text:
            query = query.filter(Document.code.ilike(f"%{query_text}%"))
        settings = db.query(TaxSetting).filter(TaxSetting.business_id == business_id).first()
        docs = query.order_by(Document.document_date.desc()).limit(limit).all()
        items = []
        for doc in docs:
            info = dict(doc.extra_info or {})
            items.append({
                "invoice_id": doc.id,
                "code": doc.code,
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "tax_status": info.get("tax_status"),
                "tracking_code": info.get("tax_tracking_code"),
                "tax_id": info.get("tax_moadian_taxid") or (compute_taxid_for_document(doc, settings) if settings else None),
            })
        return {"items": items, "limit": limit}

    registry.register(AIFunction(
        name="search_tax_reference_candidates",
        description="فاکتورهای فروش ارسال‌شده/نهایی در همین کسب‌وکار را برای اتصال به برگشت یا اصلاح پیدا می‌کند.",
        parameters_schema={"type": "object", "properties": {
            "query": {"type": "string", "maxLength": 100},
            "limit": {"type": "integer", "minimum": 1, "maximum": 200},
        }}, handler=tax_reference_candidates, allowed_roles=roles,
        required_permissions=["invoices.read"], category="tax", is_readonly=True,
    ))

    def get_tax_timeline(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.tax_submission_service import build_tax_status_fields_for_api, enrich_tax_timeline_event
        from app.services.tax_dead_letter_queue import get_failed_invoices

        db = context["db"]
        business_id = int(context["business_id"])
        doc = _invoice(context, args["invoice_id"])
        info = dict(doc.extra_info or {})
        timeline = []
        if info.get("tax_last_send_at"):
            timeline.append(enrich_tax_timeline_event({
                "event": "send_attempt", "timestamp": info.get("tax_last_send_at"),
                "status": info.get("tax_status"), "tracking_code": info.get("tax_tracking_code"),
                "error_message": info.get("tax_error_message"),
            }, info))
        if info.get("tax_last_inquiry_at"):
            timeline.append(enrich_tax_timeline_event({
                "event": "status_inquiry", "timestamp": info.get("tax_last_inquiry_at"),
                "status": info.get("tax_status"), "error_message": info.get("tax_error_message"),
            }, info))
        for failed in get_failed_invoices(db, business_id, status=None, limit=1000, offset=0):
            if failed.invoice_id == doc.id:
                timeline.append({
                    "event": "failed", "timestamp": failed.first_failed_at.isoformat() if failed.first_failed_at else None,
                    "error_code": failed.error_code, "error_message": failed.error_message,
                    "attempt_count": failed.attempt_count,
                })
        timeline.sort(key=lambda event: event.get("timestamp") or "", reverse=True)
        return {
            "invoice_id": doc.id, "current_status": info.get("tax_status"),
            "tax_error_message": info.get("tax_error_message"),
            "tax_tracking_code": info.get("tax_tracking_code"),
            "moadian_errors": build_tax_status_fields_for_api(info).get("tax_moadian_errors"),
            "timeline": timeline,
        }

    registry.register(AIFunction(
        name="get_invoice_tax_timeline",
        description="تاریخچهٔ تلاش‌های ارسال، استعلام و خطاهای ثبت‌شدهٔ فاکتور مالیاتی را می‌خواند؛ استعلام زنده انجام نمی‌دهد.",
        parameters_schema={"type": "object", "properties": {"invoice_id": {"type": "integer", "minimum": 1}}, "required": ["invoice_id"]},
        handler=get_tax_timeline, allowed_roles=roles, required_permissions=["invoices.read"],
        category="tax", is_readonly=True,
    ))

    def validate_tax_batch(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.tax_validation_service import validate_document_for_tax

        db = context["db"]
        business_id = int(context["business_id"])
        raw_ids = args["invoice_ids"]
        if not 1 <= len(raw_ids) <= 50:
            raise ValueError("در هر پیش‌بررسی بین ۱ تا ۵۰ فاکتور بفرست")
        validated, invalid = [], []
        for raw in raw_ids:
            try:
                invoice_id = int(raw)
                doc = _invoice(context, invoice_id, lock=True)
                result = validate_document_for_tax(db, doc)
                if result.get("valid"):
                    validated.append(invoice_id)
                else:
                    invalid.append({"invoice_id": invoice_id, "issues": result.get("issues") or []})
            except Exception as exc:
                invalid.append({"invoice_id": raw, "issues": [str(exc)]})
        return {"validated": validated, "invalid": invalid, "total": len(raw_ids)}

    registry.register(AIFunction(
        name="validate_tax_invoice_batch",
        description="اعتبارسنجی بدون تغییر حداکثر ۵۰ فاکتور مالیاتی و گزارش شناسه‌های آماده و خطاهای هر فاکتور.",
        parameters_schema={"type": "object", "properties": {
            "invoice_ids": {"type": "array", "minItems": 1, "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
        }, "required": ["invoice_ids"]}, handler=validate_tax_batch,
        allowed_roles=roles, required_permissions=["invoices.read"], category="tax", is_readonly=True,
    ))

    def list_tax_failed_invoices(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active
        from app.services.tax_dead_letter_queue import get_failed_invoices

        db = context["db"]
        business_id = int(context["business_id"])
        ensure_moadian_plugin_active(db, business_id)
        limit = min(max(int(args.get("limit", 100)), 1), 200)
        offset = max(int(args.get("offset", 0)), 0)
        status = args.get("status")
        if status and status not in {"pending", "retrying", "resolved", "failed"}:
            raise ValueError("status نامعتبر است")
        rows = get_failed_invoices(db, business_id, status=status, limit=limit, offset=offset)
        return {"items": [{
            "id": row.id, "invoice_id": row.invoice_id, "tracking_code": row.tracking_code,
            "error_code": row.error_code, "error_message": row.error_message,
            "attempt_count": row.attempt_count,
            "first_failed_at": row.first_failed_at.isoformat() if row.first_failed_at else None,
            "last_attempt_at": row.last_attempt_at.isoformat() if row.last_attempt_at else None,
            "status": row.status,
        } for row in rows], "count": len(rows), "limit": limit, "offset": offset}

    registry.register(AIFunction(
        name="list_tax_failed_invoices",
        description="صف خطاهای ارسال مالیاتی همین کسب‌وکار را برای پیگیری می‌خواند؛ retry یا ارسال انجام نمی‌دهد.",
        parameters_schema={"type": "object", "properties": {
            "status": {"type": ["string", "null"], "enum": ["pending", "retrying", "resolved", "failed", None]},
            "limit": {"type": "integer", "minimum": 1, "maximum": 200},
            "offset": {"type": "integer", "minimum": 0},
        }}, handler=list_tax_failed_invoices, allowed_roles=roles,
        required_permissions=["invoices.read"], category="tax", is_readonly=True,
    ))

    def check_tax_system_health(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active
        from app.services.tax_health_check import check_tax_system_health as check_health

        db = context["db"]
        business_id = int(context["business_id"])
        ensure_moadian_plugin_active(db, business_id)
        return check_health(db, business_id)

    registry.register(AIFunction(
        name="check_tax_system_health",
        description="تنظیمات و اتصال زندهٔ سامانهٔ مالیاتی کسب‌وکار جاری را بررسی می‌کند؛ برای احراز هویت بیرونی نیازمند مجوز عملیات مالیاتی و تأیید است.",
        parameters_schema={"type": "object", "properties": {}}, handler=check_tax_system_health,
        allowed_roles=roles, required_permissions=["moadian.operate"], category="tax",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))

    def send_tax_invoice_batch(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.tax_submission_service import send_document_to_tax_system, normalize_stored_tax_status

        db = context["db"]
        raw_ids = args["invoice_ids"]
        if not 1 <= len(raw_ids) <= 20:
            raise ValueError("در هر نوبت حداکثر ۲۰ فاکتور ارسال کن")
        ids = list(dict.fromkeys(int(value) for value in raw_ids))
        results = []
        for invoice_id in ids:
            try:
                doc = _invoice(context, invoice_id, lock=True)
                info = dict(doc.extra_info or {})
                if not info.get("tax_workspace"):
                    raise ValueError("فاکتور در کارپوشهٔ مالیاتی نیست")
                if info.get("tax_cancelled_in_modian") or (
                    normalize_stored_tax_status(info) in {"sent", "finalized", "pending"}
                    and info.get("tax_tracking_code")
                ):
                    raise ValueError("وضعیت فعلی ارسال مجدد را مجاز نمی‌کند")
                submission = send_document_to_tax_system(db, doc)
                db.flush()
                after = dict(doc.extra_info or {})
                failed = after.get("tax_status") == "failed" or submission.get("status") == "failed"
                results.append({
                    "invoice_id": invoice_id, "accepted": not failed,
                    "tax_status": after.get("tax_status"),
                    "tracking_code": after.get("tax_tracking_code"),
                    "error_message": submission.get("error_message") or after.get("tax_error_message") if failed else None,
                })
                db.commit()
            except Exception as exc:
                db.rollback()
                results.append({"invoice_id": invoice_id, "accepted": False, "error_message": str(exc)})
        return {
            "results": results,
            "total": len(ids),
            "accepted_count": sum(1 for item in results if item.get("accepted")),
            "failed_count": sum(1 for item in results if not item.get("accepted")),
        }

    registry.register(AIFunction(
        name="send_tax_invoice_batch",
        description="ارسال بیرونی حداکثر ۲۰ فاکتور موجود در کارپوشه؛ پیش از اجرا فهرست دقیق را تأیید کن. نتیجهٔ هر فاکتور جداگانه برمی‌گردد.",
        parameters_schema={"type": "object", "properties": {
            "invoice_ids": {"type": "array", "minItems": 1, "maxItems": 20, "items": {"type": "integer", "minimum": 1}},
        }, "required": ["invoice_ids"]}, handler=send_tax_invoice_batch,
        allowed_roles=roles, required_permissions=["moadian.operate"], category="tax",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def retry_tax_failed_invoice(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from adapters.db.models.tax_failed_invoice import TaxFailedInvoice
        from app.services.tax_submission_service import send_document_to_tax_system

        db = context["db"]
        business_id = int(context["business_id"])
        failed_id = int(args["failed_invoice_id"])
        row = db.query(TaxFailedInvoice).filter(
            TaxFailedInvoice.id == failed_id,
            TaxFailedInvoice.business_id == business_id,
        ).first()
        if not row:
            raise ValueError("رکورد خطا در کسب‌وکار متصل پیدا نشد")
        if row.status not in {"pending", "retrying"}:
            raise ValueError("وضعیت رکورد خطا اجازهٔ تلاش مجدد نمی‌دهد")
        doc = _invoice(context, row.invoice_id, lock=True)
        row = db.query(TaxFailedInvoice).filter(
            TaxFailedInvoice.id == failed_id,
            TaxFailedInvoice.business_id == business_id,
        ).with_for_update().first()
        if not row or row.status not in {"pending", "retrying"}:
            raise ValueError("رکورد خطا تغییر کرده یا دیگر اجازهٔ تلاش مجدد نمی‌دهد")
        row.status = "retrying"
        db.flush()
        try:
            result = send_document_to_tax_system(db, doc)
            info = dict(doc.extra_info or {})
            failed = info.get("tax_status") == "failed" or result.get("status") == "failed"
            if failed:
                row.status = "pending"
                row.attempt_count = int(row.attempt_count or 0) + 1
                from datetime import datetime
                row.last_attempt_at = datetime.utcnow()
                row.error_message = result.get("error_message") or info.get("tax_error_message")
                row.error_code = info.get("tax_error_code") or row.error_code
                db.add(row)
            else:
                db.delete(row)
            db.flush()
            return {
                "failed_invoice_id": failed_id, "invoice_id": doc.id,
                "success": not failed, "tax_status": info.get("tax_status"),
                "tracking_code": info.get("tax_tracking_code"),
                "error_message": result.get("error_message") if failed else None,
            }
        except Exception as exc:
            db.rollback()
            row = db.query(TaxFailedInvoice).filter(
                TaxFailedInvoice.id == failed_id,
                TaxFailedInvoice.business_id == business_id,
            ).with_for_update().first()
            if not row:
                return {"failed_invoice_id": failed_id, "invoice_id": doc.id, "success": False, "error_message": str(exc)}
            from datetime import datetime
            row.status = "pending"
            row.attempt_count = int(row.attempt_count or 0) + 1
            row.last_attempt_at = datetime.utcnow()
            row.error_message = str(exc)
            db.add(row)
            db.flush()
            return {"failed_invoice_id": failed_id, "invoice_id": doc.id, "success": False, "error_message": str(exc)}

    registry.register(AIFunction(
        name="retry_tax_failed_invoice",
        description="ارسال مجدد یک رکورد خطای در انتظار متعلق به همین کسب‌وکار؛ اثر بیرونی دارد و نتیجه و تلاش بعدی را در صف خطا ثبت می‌کند. نیازمند تأیید صریح است.",
        parameters_schema={"type": "object", "properties": {"failed_invoice_id": {"type": "integer", "minimum": 1}}, "required": ["failed_invoice_id"]},
        handler=retry_tax_failed_invoice, allowed_roles=roles,
        required_permissions=["moadian.operate"], category="tax",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    def remove_tax_invoice_batch(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        db = context["db"]
        ids = list(dict.fromkeys(int(value) for value in args["invoice_ids"]))
        if not 1 <= len(ids) <= 50:
            raise ValueError("در هر نوبت حداکثر ۵۰ فاکتور از کارپوشه حذف کن")
        removed, failed = [], []
        for invoice_id in ids:
            try:
                with db.begin_nested():
                    doc = _invoice(context, invoice_id, lock=True)
                    info = dict(doc.extra_info or {})
                    status = info.get("tax_status")
                    if status in {"sent", "finalized"}:
                        raise ValueError("فاکتور ارسال‌شده یا نهایی‌شده قابل حذف از کارپوشه نیست")
                    info["tax_workspace"] = False
                    info["tax_status"] = status or "not_in_workspace"
                    doc.extra_info = info
                    db.add(doc)
                removed.append(invoice_id)
            except Exception as exc:
                failed.append({"invoice_id": invoice_id, "error": str(exc)})
        db.commit()
        return {"removed": removed, "failed": failed, "total": len(ids)}

    registry.register(AIFunction(
        name="remove_tax_invoice_batch",
        description="حذف از کارپوشهٔ مالیاتی برای حداکثر ۵۰ فاکتور؛ اسناد ارسال‌شده/نهایی قابل حذف نیستند. فهرست دقیق را پیش از اجرا تأیید کن.",
        parameters_schema={"type": "object", "properties": {
            "invoice_ids": {"type": "array", "minItems": 1, "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
        }, "required": ["invoice_ids"]}, handler=remove_tax_invoice_batch,
        allowed_roles=roles, required_permissions=["invoices.write"], category="tax",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))
