"""MCP tools for workflow marketplace extras, AI usage logs, storage export info, notification events."""
from __future__ import annotations

from datetime import datetime

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
PAGE = mcp_schema(
    {
        "skip": {"type": "integer", "minimum": 0},
        "take": {"type": "integer", "minimum": 1, "maximum": 100},
        "search": {"type": "string", "maxLength": 80},
        "tag": {"type": "string", "maxLength": 40},
    }
)
PKG_ID = mcp_schema({"package_id": {"type": "integer", "minimum": 1}}, ["package_id"])
AI_INV_ID = mcp_schema({"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"])
USAGE_LOGS = mcp_schema(
    {
        "limit": {"type": "integer", "minimum": 1, "maximum": 100},
        "skip": {"type": "integer", "minimum": 0},
        "start_date": {"type": "string"},
        "end_date": {"type": "string"},
    }
)
EXPORT_INFO = mcp_schema(
    {
        "module_context": {"type": ["string", "null"], "maxLength": 80},
        "from_date": {"type": ["string", "null"]},
        "to_date": {"type": ["string", "null"]},
    }
)
EVENT_CAT = mcp_schema({"category": {"type": "string", "maxLength": 80}})


class _NoFmt:
    pass


def _pkg_public(db, pkg) -> dict:
    from app.services.workflow.workflow_marketplace_service import package_to_public_dict

    return mcp_jsonable(package_to_public_dict(db, pkg, _NoFmt()))


def _pkg_detail(db, pkg) -> dict:
    from app.services.workflow.workflow_marketplace_service import package_detail_dict

    return mcp_jsonable(package_detail_dict(db, pkg, _NoFmt(), True))


def _parse_dt(value):
    if not value:
        return None
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def get_workflow_marketplace_package_handler(args, context):
    from app.services.workflow.workflow_marketplace_service import get_published_package

    pkg = mcp_run(get_published_package, mcp_db(context), int(args["package_id"]))
    if pkg is None:
        raise ValueError("بسته یافت نشد یا منتشر نیست")
    return _pkg_detail(mcp_db(context), pkg)


def list_my_workflow_marketplace_packages_handler(args, context):
    from app.services.workflow.workflow_marketplace_service import list_my_packages

    rows, total = mcp_run(
        list_my_packages,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        skip=int(args.get("skip") or 0),
        take=int(args.get("take") or 20),
    )
    return {"items": [_pkg_public(mcp_db(context), p) for p in rows], "total": total}


def get_my_workflow_marketplace_package_handler(args, context):
    from app.services.workflow.workflow_marketplace_service import get_package_for_owner

    pkg = mcp_run(
        get_package_for_owner,
        mcp_db(context),
        int(args["package_id"]),
        mcp_bid(context),
        mcp_uid(context),
    )
    if pkg is None:
        raise ValueError("بسته یافت نشد")
    return _pkg_detail(mcp_db(context), pkg)


def republish_workflow_marketplace_package_handler(args, context):
    from app.services.workflow.workflow_marketplace_service import republish_package

    pkg = mcp_run(
        republish_package,
        mcp_db(context),
        package_id=int(args["package_id"]),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
    )
    return _pkg_public(mcp_db(context), pkg)


def list_ai_usage_logs_handler(args, context):
    from adapters.db.repositories.ai_usage_log_repository import AIUsageLogRepository

    logs = AIUsageLogRepository(mcp_db(context)).get_business_logs(
        business_id=mcp_bid(context),
        start_date=_parse_dt(args.get("start_date")),
        end_date=_parse_dt(args.get("end_date")),
        limit=int(args.get("limit") or 50),
        skip=int(args.get("skip") or 0),
    )
    return mcp_jsonable(
        {
            "items": [
                {
                    "id": log.id,
                    "provider": log.provider,
                    "model": log.model,
                    "input_tokens": log.input_tokens,
                    "output_tokens": log.output_tokens,
                    "total_tokens": (log.input_tokens or 0) + (log.output_tokens or 0),
                    "cost": float(log.cost or 0),
                    "payment_method": log.payment_method,
                    "document_id": log.document_id,
                    "created_at": log.created_at.isoformat() if log.created_at else None,
                }
                for log in logs
            ]
        }
    )


def get_storage_export_info_handler(args, context):
    from app.services.storage_export_service import get_export_info

    return mcp_jsonable(
        mcp_run(
            get_export_info,
            mcp_db(context),
            mcp_bid(context),
            module_context=args.get("module_context"),
            from_date=_parse_dt(args.get("from_date")),
            to_date=_parse_dt(args.get("to_date")),
        )
    )


def list_available_ai_models_handler(args, context):
    from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
    from app.services.ai.ai_model_service import get_plan_default_model_code, list_models_for_user

    bid = mcp_bid(context)
    db = mcp_db(context)
    sub = AISubscriptionRepository(db).get_active_subscription(user_id=mcp_uid(context), business_id=bid)
    plan = sub.plan if sub else None
    preferred = getattr(sub, "preferred_model_code", None) if sub else None
    models = list_models_for_user(db, plan, include_pricing=True, business_id=bid)
    if plan and getattr(plan, "plan_type", None) == "byok":
        from app.services.ai.business_ai_provider_service import get_byok_default_model

        plan_default = get_byok_default_model(db, bid)
    else:
        plan_default = get_plan_default_model_code(plan)
    return mcp_jsonable(
        {"models": models, "preferred_model_code": preferred, "plan_default_model": plan_default}
    )


def get_ai_invoice_handler(args, context):
    from adapters.db.repositories.ai_invoice_repository import AIInvoiceRepository

    invoice = AIInvoiceRepository(mcp_db(context)).get_by_id(int(args["invoice_id"]))
    if invoice is None or int(invoice.business_id) != mcp_bid(context):
        raise ValueError("فاکتور یافت نشد")
    return mcp_jsonable(
        {
            "id": invoice.id,
            "invoice_type": invoice.invoice_type,
            "amount": float(invoice.amount),
            "currency": invoice.currency,
            "status": invoice.status,
            "wallet_transaction_id": invoice.wallet_transaction_id,
            "document_id": invoice.document_id,
            "plan_id": invoice.plan_id,
            "subscription_id": invoice.subscription_id,
            "created_at": invoice.created_at.isoformat() if invoice.created_at else None,
            "paid_at": invoice.paid_at.isoformat() if invoice.paid_at else None,
        }
    )


def get_business_delete_info_handler(args, context):
    from app.services.business_service import get_business_delete_info

    return mcp_jsonable(mcp_run(get_business_delete_info, mcp_db(context), mcp_bid(context), mcp_uid(context)))


def list_notification_event_types_handler(args, context):
    from adapters.db.repositories.business_notification_repo import NotificationEventTypeRepository

    rows = NotificationEventTypeRepository(mcp_db(context)).list_all(category=args.get("category"), is_active=True)
    return mcp_jsonable(
        {
            "items": [
                {
                    "id": et.id,
                    "code": et.code,
                    "name": et.name,
                    "description": et.description,
                    "category": et.category,
                    "available_variables": et.available_variables or [],
                    "requires_approval": et.requires_approval,
                }
                for et in rows
            ],
            "total": len(rows),
        }
    )


def register_mcp_ops7_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="get_workflow_marketplace_package", description="جزئیات و گراف یک بسته منتشرشده مخزن ورک‌فلو.", parameters_schema=PKG_ID, handler=get_workflow_marketplace_package_handler, allowed_roles=roles, required_permissions=["workflows.view"], category="workflow", is_readonly=True))
    registry.register(AIFunction(name="list_my_workflow_marketplace_packages", description="بسته‌های مخزن ورک‌فلو که همین کاربر در کسب‌وکار متصل منتشر کرده.", parameters_schema=PAGE, handler=list_my_workflow_marketplace_packages_handler, allowed_roles=roles, required_permissions=["workflows.view"], category="workflow", is_readonly=True))
    registry.register(AIFunction(name="get_my_workflow_marketplace_package", description="جزئیات بسته مخزن ورک‌فلو متعلق به ناشر همین کسب‌وکار.", parameters_schema=PKG_ID, handler=get_my_workflow_marketplace_package_handler, allowed_roles=roles, required_permissions=["workflows.view"], category="workflow", is_readonly=True))
    registry.register(AIFunction(name="republish_workflow_marketplace_package", description="انتشار مجدد بسته مخفی مخزن ورک‌فلو. نیازمند تأیید.", parameters_schema=PKG_ID, handler=republish_workflow_marketplace_package_handler, allowed_roles=roles, required_permissions=["workflows.edit"], category="workflow", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_ai_usage_logs", description="لاگ مصرف توکن هوش مصنوعی کسب‌وکار متصل بدون کلید ارائه‌دهنده.", parameters_schema=USAGE_LOGS, handler=list_ai_usage_logs_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="get_storage_export_info", description="حجم و تعداد فایل‌های قابل خروجی ZIP بدون خود فایل.", parameters_schema=EXPORT_INFO, handler=get_storage_export_info_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_notification_event_types", description="انواع رویداد قابل قالب‌بندی اعلان کسب‌وکار.", parameters_schema=EVENT_CAT, handler=list_notification_event_types_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_available_ai_models", description="مدل‌های مجاز هوش مصنوعی برای پلن کسب‌وکار متصل بدون کلید ارائه‌دهنده.", parameters_schema=EMPTY, handler=list_available_ai_models_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="get_business_delete_info", description="محدودیت‌ها و آمار حذف کسب‌وکار متصل؛ فقط برای مالک.", parameters_schema=EMPTY, handler=get_business_delete_info_handler, allowed_roles=roles, required_permissions=["settings.business"], category="business", is_readonly=True))
    registry.register(AIFunction(name="get_ai_invoice", description="جزئیات صورتحساب هوش مصنوعی متعلق به کسب‌وکار متصل بدون کلید ارائه‌دهنده.", parameters_schema=AI_INV_ID, handler=get_ai_invoice_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
