"""MCP extensions for invoice installments, share links, tags, and balances."""
from __future__ import annotations

from copy import deepcopy
from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _schema(properties: Dict[str, Any], required: list[str]) -> Dict[str, Any]:
    return {"type": "object", "properties": properties, "required": required, "additionalProperties": False}


def _register(registry, name, description, properties, required, handler, *, write=False, high=False):
    registry.register(AIFunction(
        name=name,
        description=description,
        parameters_schema=_schema(properties, required),
        handler=handler,
        allowed_roles=_ROLES,
        required_permissions=["invoices.delete" if name == "bulk_delete_invoices" else ("invoices.write" if write else "invoices.read")],
        category="invoices",
        requires_approval=bool(write),
        risk_level="high" if high else ("medium" if write else "safe"),
        is_readonly=not write,
    ))


def _authorized_document(db, ctx, business_id: int, invoice_id: int, action: str):
    from adapters.db.models.document import Document
    from app.core.permissions import has_invoice_type_permission_for_business
    from app.services.invoice_service import SUPPORTED_INVOICE_TYPES

    doc = db.query(Document).filter(Document.id == invoice_id, Document.business_id == business_id).first()
    if not doc or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        raise ValueError("فاکتور در کسب‌وکار متصل پیدا نشد")
    if not has_invoice_type_permission_for_business(ctx, db, business_id, doc.document_type, action):
        raise ValueError(f"دسترسی {action} برای نوع {doc.document_type} مجاز نیست")
    return doc


def _name_link(link, db):
    from app.services.document_share_link_service import serialize_document_share_link
    return {"link": serialize_document_share_link(link, db=db)}


def register_mcp_invoice_extra_functions(registry) -> None:
    from app.services.ai.ai_tool_payloads import _INVOICE_WRITE_FIELDS_SCHEMA
    invoice_fields = deepcopy(_INVOICE_WRITE_FIELDS_SCHEMA)
    for key, limit in (("lines", 200), ("payments", 100), ("tag_ids", 100), ("invoice_adjustments", 100)):
        if isinstance(invoice_fields.get(key), dict) and invoice_fields[key].get("type") == "array":
            invoice_fields[key]["maxItems"] = limit
    _register(registry, "get_invoice_installments", "دریافت برنامه اقساط یک فاکتور و مبالغ باقی‌مانده هر قسط.",
        {"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"], _get_installments)

    _register(registry, "search_invoice_installments", "جستجوی اقساط با فیلتر سررسید/وضعیت/شخص/فاکتور و صفحه‌بندی؛ حداکثر ۲۰۰ ردیف در هر صفحه.",
        {"fiscal_year_id": {"type": "integer", "minimum": 1}, "due_from": {"type": "string", "format": "date"},
         "due_to": {"type": "string", "format": "date"}, "status": {"type": "string", "enum": ["pending", "partial", "paid", "overdue"]},
         "status_in": {"type": ["array", "string"], "items": {"type": "string", "enum": ["pending", "partial", "paid", "overdue"]}},
         "bucket": {"type": "string", "enum": ["unpaid", "upcoming", "overdue_only"]}, "min_overdue_days": {"type": "integer", "minimum": 0},
         "group_by": {"type": "string", "enum": ["invoice"]}, "person_id": {"type": "integer", "minimum": 1},
         "invoice_id": {"type": "integer", "minimum": 1}, "currency_id": {"type": "integer", "minimum": 1},
         "take": {"type": "integer", "minimum": 1, "maximum": 200}, "skip": {"type": "integer", "minimum": 0}}, [], _search_installments)

    _register(registry, "calculate_invoice_balances", "محاسبه مبلغ کل، پرداخت‌شده و مانده برای حداکثر ۱۰۰ فاکتور متعلق به کسب‌وکار متصل.",
        {"invoice_ids": {"type": "array", "minItems": 1, "maxItems": 100, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}}}, ["invoice_ids"], _calculate_balances)

    _register(registry, "list_invoice_tags", "فهرست برچسب‌های فعال فاکتور؛ با include_inactive=true برچسب‌های غیرفعال هم برمی‌گردند.",
        {"include_inactive": {"type": "boolean"}}, [], _list_invoice_tags)
    _register(registry, "create_invoice_tag", "ایجاد برچسب فاکتور برای کسب‌وکار متصل.",
        {"name": {"type": "string", "minLength": 1, "maxLength": 120}, "color": {"type": ["string", "null"], "maxLength": 32}}, ["name"], _create_invoice_tag, write=True)
    _register(registry, "update_invoice_tag", "ویرایش نام، رنگ، وضعیت یا ترتیب برچسب غیرسیستمی فاکتور.",
        {"tag_id": {"type": "integer", "minimum": 1}, "name": {"type": "string", "minLength": 1, "maxLength": 120},
         "color": {"type": ["string", "null"], "maxLength": 32}, "is_active": {"type": "boolean"}, "sort_order": {"type": "integer", "minimum": 0}},
        ["tag_id"], _update_invoice_tag, write=True)

    _register(registry, "get_invoice_share_link", "دریافت وضعیت لینک عمومی فعال فاکتور؛ خروجی می‌تواند شامل URL قابل دسترسی عمومی باشد.",
        {"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"], _get_share_link)
    _register(registry, "create_invoice_share_link", "ایجاد یا جایگزینی لینک عمومی فاکتور. ایجاد لینک، URL عمومی قابل اشتراک می‌سازد و نیازمند تأیید است.",
        {"invoice_id": {"type": "integer", "minimum": 1}, "expires_in_hours": {"type": ["integer", "null"], "minimum": 1, "maximum": 720},
         "max_view_count": {"type": ["integer", "null"], "minimum": 1, "maximum": 1000}, "replace_existing": {"type": "boolean"},
         "online_payment_enabled": {"type": ["boolean", "null"]}, "online_payment_gateway_id": {"type": ["integer", "null"], "minimum": 1}},
        ["invoice_id"], _create_share_link, write=True, high=True)
    _register(registry, "revoke_invoice_share_link", "لغو لینک عمومی فعال فاکتور و از دسترس خارج کردن URL قبلی.",
        {"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"], _revoke_share_link, write=True, high=True)
    _register(registry, "update_invoice_share_link_payment", "تغییر تنظیم پرداخت آنلاین و درگاه روی لینک عمومی فعال فاکتور.",
        {"invoice_id": {"type": "integer", "minimum": 1}, "online_payment_enabled": {"type": "boolean"},
         "online_payment_gateway_id": {"type": ["integer", "null"], "minimum": 1}}, ["invoice_id"], _update_share_link_payment, write=True, high=True)

    _register(registry, "get_invoice_delete_impact", "پیش‌نمایش اقساط، دریافت/پرداخت، حواله انبار و وضعیت کارپوشه پیش از حذف فاکتور.",
        {"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"], _delete_impact)
    _register(registry, "bulk_delete_invoices", "حذف حداکثر ۱۰۰ فاکتور انتخاب‌شده؛ موارد وابسته/غیرقابل‌حذف به‌عنوان skipped برمی‌گردند. نیازمند تأیید صریح است.",
        {"invoice_ids": {"type": "array", "maxItems": 100, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}}}, ["invoice_ids"], _bulk_delete, write=True, high=True)
    _register(registry, "bulk_upsert_invoices", "ایجاد/ویرایش حداکثر ۲۵ فاکتور در یک تماس. هر payload همان فیلدهای create_invoice/update_invoice را دارد؛ برای ایجاد invoice_type و lines لازم است. خطای هر مورد مستقل برگردانده می‌شود؛ عملیات نیازمند تأیید است.",
        {"items": {"type": "array", "minItems": 1, "maxItems": 25, "items": {"type": "object", "properties": {
            "client_ref": {"type": ["string", "null"], "maxLength": 255}, "invoice_id": {"type": ["integer", "null"], "minimum": 1},
            "payload": {"type": "object", "properties": invoice_fields, "additionalProperties": False}},
            "required": ["payload"], "additionalProperties": False}}}, ["items"], _bulk_upsert, write=True, high=True)


def _get_installments(args, context):
    from app.services.invoice_service import get_invoice_installment_plan
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    invoice_id = int(args["invoice_id"])
    _authorized_document(db, ctx, bid, invoice_id, "view")
    return get_invoice_installment_plan(db, bid, invoice_id)


def _search_installments(args, context):
    from app.services.invoice_service import search_installments
    query = dict(args)
    query.setdefault("take", 100)
    query.setdefault("skip", 0)
    if query.get("take", 100) > 200:
        raise ValueError("حداکثر ۲۰۰ قسط در هر صفحه قابل دریافت است")
    return search_installments(context["db"], int(context["business_id"]), query)


def _calculate_balances(args, context):
    from app.services.invoice_service import calculate_invoice_remaining
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    results, errors = {}, {}
    for raw_id in args["invoice_ids"]:
        invoice_id = int(raw_id)
        try:
            _authorized_document(db, ctx, bid, invoice_id, "view")
            results[str(invoice_id)] = calculate_invoice_remaining(db, bid, invoice_id)
        except Exception as exc:
            from app.core.responses import ApiError
            db.rollback()
            errors[str(invoice_id)] = exc.message if isinstance(exc, ApiError) else "محاسبه مانده این فاکتور ناموفق بود"
    return {"results": results, "errors": errors}


def _list_invoice_tags(args, context):
    from app.services.invoice_tag_service import list_invoice_tags
    items = list_invoice_tags(context["db"], int(context["business_id"]), bool(args.get("include_inactive", False)))
    context["db"].commit()
    return {"items": items}


def _create_invoice_tag(args, context):
    from app.services.invoice_tag_service import create_invoice_tag
    return {"item": create_invoice_tag(context["db"], int(context["business_id"]), args["name"], args.get("color"))}


def _update_invoice_tag(args, context):
    from app.services.invoice_tag_service import update_invoice_tag
    db, bid = context["db"], int(context["business_id"])
    data = {k: v for k, v in args.items() if k != "tag_id"}
    if not data:
        raise ValueError("حداقل یک فیلد برای تغییر برچسب ارسال کنید")
    item = update_invoice_tag(db, bid, int(args["tag_id"]), data)
    db.commit()
    return {"item": item}


def _get_share_link(args, context):
    from app.services.document_share_link_service import get_active_share_link_for_document
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    invoice_id = int(args["invoice_id"])
    _authorized_document(db, ctx, bid, invoice_id, "view")
    return _name_link(get_active_share_link_for_document(db, bid, invoice_id), db)


def _create_share_link(args, context):
    from app.services.document_share_link_service import create_share_link
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    invoice_id = int(args["invoice_id"])
    _authorized_document(db, ctx, bid, invoice_id, "edit")
    link = create_share_link(db, business_id=bid, document_id=invoice_id, user_id=ctx.get_user_id(),
        expires_in_hours=args.get("expires_in_hours"), max_view_count=args.get("max_view_count"),
        replace_existing=bool(args.get("replace_existing", True)),
        online_payment_enabled=args.get("online_payment_enabled"), online_payment_gateway_id=args.get("online_payment_gateway_id"))
    db.commit()
    return _name_link(link, db)


def _revoke_share_link(args, context):
    from app.services.document_share_link_service import revoke_share_link
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    invoice_id = int(args["invoice_id"])
    _authorized_document(db, ctx, bid, invoice_id, "edit")
    if not revoke_share_link(db, business_id=bid, document_id=invoice_id, user_id=ctx.get_user_id()):
        raise ValueError("لینک فعالی برای لغو وجود ندارد")
    return {"invoice_id": invoice_id, "revoked": True}


def _update_share_link_payment(args, context):
    from app.services.document_share_link_service import update_document_share_link_payment_options
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    invoice_id = int(args["invoice_id"])
    _authorized_document(db, ctx, bid, invoice_id, "edit")
    patch = {k: args[k] for k in ("online_payment_enabled", "online_payment_gateway_id") if k in args}
    if not patch:
        raise ValueError("حداقل یک تنظیم پرداخت آنلاین را مشخص کنید")
    link = update_document_share_link_payment_options(db, business_id=bid, document_id=invoice_id, user_id=ctx.get_user_id(), patch=patch)
    return _name_link(link, db)


def _delete_impact(args, context):
    from adapters.db.models.document import Document
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    invoice_id = int(args["invoice_id"])
    doc = _authorized_document(db, ctx, bid, invoice_id, "view")
    extra = doc.extra_info if isinstance(doc.extra_info, dict) else {}
    plan = extra.get("installment_plan") if isinstance(extra.get("installment_plan"), dict) else None
    schedule = plan.get("schedule") if plan else []
    links = extra.get("links") if isinstance(extra.get("links"), dict) else {}
    return {"invoice_id": invoice_id, "invoice_code": doc.code, "document_type": doc.document_type,
        "has_installments": bool(plan), "installment_info": {"count": len(schedule or []), "total_amount": plan.get("principal_total", 0)} if plan else None,
        "in_tax_workspace": bool(extra.get("tax_workspace")), "tax_status": extra.get("tax_status"),
        "receipt_payment_link_count": len(links.get("receipt_payment_document_ids") or []),
        "has_quick_sale_change_payment": bool(links.get("quick_sale_change_payment_document_id")),
        "has_warehouse_document_link": bool(links.get("warehouse_document_id"))}


def _bulk_delete(args, context):
    from adapters.db.models.document import Document
    from app.services.invoice_service import bulk_delete_invoices
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    from app.core.permissions import has_invoice_type_permission_for_business
    allowed, rejected = [], []
    for raw_id in args["invoice_ids"]:
        invoice_id = int(raw_id)
        doc = db.query(Document).filter(Document.id == invoice_id, Document.business_id == bid).first()
        if not doc:
            rejected.append({"id": invoice_id, "reason": "فاکتور در کسب‌وکار متصل پیدا نشد"})
        elif not has_invoice_type_permission_for_business(ctx, db, bid, doc.document_type, "delete"):
            rejected.append({"id": invoice_id, "reason": "مجوز حذف این نوع فاکتور وجود ندارد"})
        else:
            allowed.append(invoice_id)
    result = bulk_delete_invoices(db, bid, allowed) if allowed else {"deleted": [], "skipped": []}
    result["skipped"] = rejected + result.get("skipped", [])
    return result


def _bulk_upsert(args, context):
    from app.services.ai.ai_tool_payloads import build_create_invoice_payload, build_update_invoice_payload
    from app.services.invoice_bulk_upsert_service import bulk_upsert_invoices_integration
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    normalized, source_indexes, prefailed = [], [], []
    for index, raw in enumerate(args["items"]):
        item = {k: v for k, v in raw.items() if k != "payload"}
        try:
            payload = dict(raw["payload"])
            if raw.get("invoice_id"):
                item["invoice_id"] = int(raw["invoice_id"])
                payload_has_lines = "lines" in payload
                payload = build_update_invoice_payload(payload, db=db, invoice_id=item["invoice_id"])
                if not payload_has_lines:
                    payload.pop("lines", None)
            else:
                payload = build_create_invoice_payload(payload, db=db, business_id=bid)
            item["payload"] = payload
            normalized.append(item)
            source_indexes.append(index)
        except Exception as exc:
            prefailed.append({"index": index, "client_ref": item.get("client_ref"),
                "status": "failed", "invoice_id": item.get("invoice_id"),
                "error_code": "INVALID_PAYLOAD", "message": str(exc)[:500]})
    service_result = bulk_upsert_invoices_integration(db, bid, ctx, {"items": normalized}, user_can_select_fx_rate=_user_can_select_fx_rate(db, ctx, bid)) if normalized else {"results": [], "summary": {"total": 0, "created": 0, "updated": 0, "failed": 0}}
    for row, original_index in zip(service_result.get("results", []), source_indexes):
        row["index"] = original_index
    rows = prefailed + service_result.get("results", [])
    rows.sort(key=lambda row: int(row.get("index", 0)))
    return {"results": rows, "summary": {
        "total": len(args["items"]),
        "created": sum(1 for r in rows if r.get("status") == "created"),
        "updated": sum(1 for r in rows if r.get("status") == "updated"),
        "failed": sum(1 for r in rows if r.get("status") == "failed"),
    }}


def _user_can_select_fx_rate(db, ctx, business_id: int) -> bool:
    if ctx.is_superadmin() or ctx.is_business_owner(business_id):
        return True
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
    membership = BusinessPermissionRepository(db).get_by_user_and_business(ctx.get_user_id(), business_id)
    if not membership or not membership.business_permissions:
        return False
    permissions = ctx._normalize_permissions_value(membership.business_permissions) or {}
    section = permissions.get("currency_revaluation") or {}
    return bool(section.get("view") or section.get("read"))
