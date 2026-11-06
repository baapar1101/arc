"""MCP tools for document-usage monetization (business side, not platform admin plans)."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
CHARGES = mcp_schema(
    {
        "status": {"type": "string", "maxLength": 32},
        "charge_type": {"type": "string", "maxLength": 32},
        "limit": {"type": "integer", "minimum": 1, "maximum": 200},
        "skip": {"type": "integer", "minimum": 0},
    }
)
SUBSCRIBE = mcp_schema(
    {"plan_id": {"type": "integer", "minimum": 1}, "auto_renew": {"type": "boolean"}},
    ["plan_id"],
)
CHARGE_ID = mcp_schema({"charge_id": {"type": "integer", "minimum": 1}}, ["charge_id"])
DOC_ID = mcp_schema({"document_id": {"type": "integer", "minimum": 1}}, ["document_id"])
EVAL = mcp_schema(
    {
        "document_type": {"type": "string", "minLength": 1, "maxLength": 64},
        "amount": {"type": "number", "minimum": 0},
        "document_date": {"type": "string", "description": "YYYY-MM-DD"},
    },
    ["document_type", "amount"],
)


def get_document_monetization_overview_handler(args, context):
    from app.services.document_monetization_service import list_business_policies, list_document_usage_charges

    db, bid = mcp_db(context), mcp_bid(context)
    return mcp_jsonable(
        {
            "policies": mcp_run(list_business_policies, db, bid),
            "charges": mcp_run(list_document_usage_charges, db, bid, limit=20),
        }
    )


def list_document_monetization_plans_handler(args, context):
    from app.services.document_monetization_service import get_business_subscription_status, list_document_subscription_plans

    db, bid = mcp_db(context), mcp_bid(context)
    return mcp_jsonable(
        {
            "plans": mcp_run(list_document_subscription_plans, db, only_active=True),
            "current_subscription": mcp_run(get_business_subscription_status, db, bid),
        }
    )


def activate_document_monetization_plan_handler(args, context):
    from app.services.document_monetization_service import assign_subscription_to_business

    return mcp_jsonable(
        mcp_run(
            assign_subscription_to_business,
            mcp_db(context),
            mcp_bid(context),
            int(args["plan_id"]),
            mcp_uid(context),
            auto_renew=bool(args.get("auto_renew", False)),
        )
    )


def list_document_monetization_charges_handler(args, context):
    from app.services.document_monetization_service import list_document_usage_charges

    return mcp_jsonable(
        mcp_run(
            list_document_usage_charges,
            mcp_db(context),
            mcp_bid(context),
            status=args.get("status"),
            charge_type=args.get("charge_type"),
            limit=int(args.get("limit") or 50),
            skip=int(args.get("skip") or 0),
        )
    )


def pay_document_monetization_charge_handler(args, context):
    from app.services.document_monetization_service import pay_document_usage_charge

    return mcp_jsonable(
        mcp_run(
            pay_document_usage_charge,
            mcp_db(context),
            mcp_bid(context),
            int(args["charge_id"]),
            mcp_uid(context),
        )
    )


def process_document_monetization_document_handler(args, context):
    from app.services.document_monetization_service import process_document_usage_for_document

    return mcp_jsonable(mcp_run(process_document_usage_for_document, mcp_db(context), int(args["document_id"])))


def evaluate_document_monetization_amount_handler(args, context):
    from app.services.document_monetization_service import evaluate_document_policy_for_amount

    from datetime import datetime

    return mcp_jsonable(
        mcp_run(
            evaluate_document_policy_for_amount,
            mcp_db(context),
            business_id=mcp_bid(context),
            document_type=str(args["document_type"]),
            document_date=args.get("document_date") or datetime.utcnow().date(),
            amount=args["amount"],
        )
    )


def register_mcp_doc_monetization_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_document_monetization_overview",
        description="سیاست‌ها و آخرین صورتحساب‌های درآمدزایی اسناد کسب‌وکار متصل.",
        parameters_schema=EMPTY,
        handler=get_document_monetization_overview_handler,
        allowed_roles=roles,
        required_permissions=["settings.view"],
        category="accounting",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="list_document_monetization_plans",
        description="پکیج‌های فعال درآمدزایی اسناد و اشتراک جاری کسب‌وکار.",
        parameters_schema=EMPTY,
        handler=list_document_monetization_plans_handler,
        allowed_roles=roles,
        required_permissions=["settings.view"],
        category="accounting",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="activate_document_monetization_plan",
        description="فعال‌سازی پکیج درآمدزایی اسناد برای کسب‌وکار. معمولاً فقط مالک. نیازمند تأیید.",
        parameters_schema=SUBSCRIBE,
        handler=activate_document_monetization_plan_handler,
        allowed_roles=roles,
        required_permissions=["settings.write"],
        category="accounting",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_document_monetization_charges",
        description="صورتحساب‌های استفاده از اسناد کسب‌وکار متصل.",
        parameters_schema=CHARGES,
        handler=list_document_monetization_charges_handler,
        allowed_roles=roles,
        required_permissions=["settings.view"],
        category="accounting",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="pay_document_monetization_charge",
        description="پرداخت صورتحساب درآمدزایی اسناد از کیف‌پول. نیازمند تأیید.",
        parameters_schema=CHARGE_ID,
        handler=pay_document_monetization_charge_handler,
        allowed_roles=roles,
        required_permissions=["settings.write"],
        category="accounting",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="process_document_monetization_document",
        description="پردازش دستی یک سند حسابداری برای سیاست درآمدزایی. نیازمند تأیید.",
        parameters_schema=DOC_ID,
        handler=process_document_monetization_document_handler,
        allowed_roles=roles,
        required_permissions=["settings.write"],
        category="accounting",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="evaluate_document_monetization_amount",
        description="پیش‌بینی اجازه ثبت سند با مبلغ داده‌شده طبق سیاست درآمدزایی، بدون ثبت سند.",
        parameters_schema=EVAL,
        handler=evaluate_document_monetization_amount_handler,
        allowed_roles=roles,
        required_permissions=["settings.view"],
        category="accounting",
        is_readonly=True,
    ))
