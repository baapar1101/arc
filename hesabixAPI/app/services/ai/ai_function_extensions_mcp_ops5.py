"""MCP tools for marketplace orders, SMS cost, jobs cancel, branding, invoice profit."""
from __future__ import annotations

from decimal import Decimal

from app.services.ai.ai_mcp_tool_util import (
    mcp_bid,
    mcp_db,
    mcp_jsonable,
    mcp_run,
    mcp_schema,
    mcp_uid,
)

EMPTY = mcp_schema({})
PAGE = mcp_schema(
    {"skip": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}
)
PLUGIN_ID = mcp_schema({"plugin_id": {"type": "integer", "minimum": 1}}, ["plugin_id"])
TEMPLATE_ID = mcp_schema({"template_id": {"type": "integer", "minimum": 1}}, ["template_id"])
JOB_ID = mcp_schema({"job_id": {"type": "string", "minLength": 4, "maxLength": 80}}, ["job_id"])
PROFIT = mcp_schema(
    {
        "invoice_ids": {"type": "array", "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
        "document_type": {"type": "string", "enum": ["invoice_sales", "invoice_sales_return", "invoice_production"]},
        "fiscal_year_id": {"type": "integer", "minimum": 1},
    }
)


def list_marketplace_orders_handler(args, context):
    from app.services.marketplace_service import list_orders

    return mcp_jsonable(
        mcp_run(
            list_orders,
            mcp_db(context),
            business_id=mcp_bid(context),
            limit=int(args.get("limit") or 20),
            skip=int(args.get("skip") or 0),
        )
    )


def list_marketplace_invoices_handler(args, context):
    from app.services.marketplace_service import list_invoices

    return mcp_jsonable(
        mcp_run(
            list_invoices,
            mcp_db(context),
            business_id=mcp_bid(context),
            limit=int(args.get("limit") or 20),
            skip=int(args.get("skip") or 0),
        )
    )


def get_marketplace_plugin_status_handler(args, context):
    from app.services.marketplace_service import get_business_plugin_status

    data = mcp_run(
        get_business_plugin_status,
        mcp_db(context),
        business_id=mcp_bid(context),
        plugin_id=int(args["plugin_id"]),
    )
    if data is None:
        return {"active": False, "message": "این افزونه برای این کسب‌وکار فعال نیست"}
    return mcp_jsonable(data)


def estimate_sms_notification_cost_handler(args, context):
    from app.services.business_notification_service import BusinessNotificationService

    svc = BusinessNotificationService(mcp_db(context))
    return mcp_jsonable(
        mcp_run(svc.estimate_sms_template_cost, mcp_bid(context), int(args["template_id"]))
    )


def cancel_background_job_handler(args, context):
    from app.core.queue import get_queue_service

    job_id = str(args["job_id"])
    queue_service = get_queue_service()
    if not queue_service or not queue_service.enabled:
        raise ValueError("سرویس صف غیرفعال است")
    job = queue_service.get_job(job_id)
    if job is None:
        raise ValueError("کار پس‌زمینه یافت نشد")
    meta = getattr(job, "meta", None) or {}
    owner = meta.get("user_id")
    if owner is None or int(owner) != mcp_uid(context):
        raise ValueError("دسترسی به این کار پس‌زمینه مجاز نیست")
    cancelled = queue_service.cancel_job(job_id)
    if not cancelled:
        deleted = queue_service.delete_job(job_id)
        if not deleted:
            raise ValueError("لغو کار پس‌زمینه ناموفق بود")
    return {"job_id": job_id, "cancelled": True}


def get_system_branding_handler(args, context):
    from app.core.branding import branding_public_payload

    payload = branding_public_payload()
    payload.pop("logo_bytes", None)
    return mcp_jsonable(payload)


def recalculate_invoice_profits_handler(args, context):
    from adapters.db.models.business import Business
    from adapters.db.models.document import Document
    from app.services.invoice_service import SUPPORTED_INVOICE_TYPES, _calculate_invoice_profit

    db = mcp_db(context)
    bid = mcp_bid(context)
    business = db.query(Business).filter(Business.id == bid).first()
    if business is None:
        raise ValueError("کسب‌وکار یافت نشد")
    if business.invoice_profit_calculation_method == "disabled":
        return {"processed": 0, "skipped": 0, "message": "محاسبه سود برای این کسب‌وکار غیرفعال است"}
    query = db.query(Document).filter(
        Document.business_id == bid,
        Document.document_type.in_(["invoice_sales", "invoice_sales_return", "invoice_production"]),
    )
    ids = args.get("invoice_ids")
    if ids:
        query = query.filter(Document.id.in_([int(x) for x in ids]))
    if args.get("document_type"):
        dtype = str(args["document_type"])
        if dtype not in SUPPORTED_INVOICE_TYPES:
            raise ValueError("نوع فاکتور نامعتبر است")
        query = query.filter(Document.document_type == dtype)
    if args.get("fiscal_year_id"):
        query = query.filter(Document.fiscal_year_id == int(args["fiscal_year_id"]))
    invoices = query.order_by(Document.id.desc()).limit(50).all()
    processed = 0
    skipped = 0
    errors = []
    for doc in invoices:
        try:
            profit_data = _calculate_invoice_profit(
                db,
                bid,
                doc.id,
                business.invoice_profit_calculation_method or "automatic",
                business.invoice_profit_calculation_basis or "purchase_price",
                business.invoice_profit_include_overhead or False,
                business.invoice_profit_overhead_type or "none",
                Decimal(str(business.invoice_profit_overhead_percent or 0))
                if business.invoice_profit_overhead_percent
                else None,
                business.invoice_profit_calculation_type or "gross",
                fifo_shortage_mode=getattr(business, "invoice_profit_fifo_shortage_mode", None),
            )
            if profit_data and (
                profit_data.get("gross_profit") is not None or profit_data.get("net_profit") is not None
            ):
                processed += 1
            else:
                skipped += 1
                errors.append({"invoice_id": doc.id, "code": doc.code, "error": "نتیجه سود خالی بود"})
        except Exception as exc:
            skipped += 1
            errors.append({"invoice_id": doc.id, "code": doc.code, "error": str(exc)})
    return mcp_jsonable(
        {"processed": processed, "skipped": skipped, "total": len(invoices), "errors": errors[:20], "capped_at": 50}
    )


def register_mcp_ops5_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="list_marketplace_orders", description="سفارش‌های بازار افزونه همین کسب‌وکار با صفحه‌بندی حداکثر ۱۰۰.", parameters_schema=PAGE, handler=list_marketplace_orders_handler, allowed_roles=roles, required_permissions=["marketplace.view"], category="marketplace", is_readonly=True))
    registry.register(AIFunction(name="list_marketplace_invoices", description="صورتحساب‌های خرید افزونه همین کسب‌وکار.", parameters_schema=PAGE, handler=list_marketplace_invoices_handler, allowed_roles=roles, required_permissions=["marketplace.view"], category="marketplace", is_readonly=True))
    registry.register(AIFunction(name="get_marketplace_plugin_status", description="وضعیت لایسنس یا trial یک افزونه برای کسب‌وکار متصل.", parameters_schema=PLUGIN_ID, handler=get_marketplace_plugin_status_handler, allowed_roles=roles, required_permissions=["marketplace.view"], category="marketplace", is_readonly=True))
    registry.register(AIFunction(name="estimate_sms_notification_cost", description="برآورد هزینه پیامک قالب اعلان کسب‌وکار بر اساس متن ذخیره‌شده.", parameters_schema=TEMPLATE_ID, handler=estimate_sms_notification_cost_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="cancel_background_job", description="لغو کار پس‌زمینه متعلق به همین کاربر. نیازمند تأیید.", parameters_schema=JOB_ID, handler=cancel_background_job_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_system_branding", description="نام و وضعیت لوگوی سفارشی نمونه بدون بایت تصویر.", parameters_schema=EMPTY, handler=get_system_branding_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="recalculate_invoice_profits", description="محاسبه مجدد سود حداکثر ۵۰ فاکتور فروش/برگشت/تولید کسب‌وکار متصل به‌صورت همگام. نیازمند تأیید.", parameters_schema=PROFIT, handler=recalculate_invoice_profits_handler, allowed_roles=roles, required_permissions=["invoices.read"], category="invoices", requires_approval=True, risk_level="medium", is_readonly=False))
