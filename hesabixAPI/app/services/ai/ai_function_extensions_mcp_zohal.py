"""MCP tools for Zohal inquiries. Charges the business wallet; execute always confirms."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

LIST_SCHEMA = mcp_schema({"category": {"type": "string", "maxLength": 80}})
EXECUTE_SCHEMA = mcp_schema(
    {
        "service_code": {"type": "string", "minLength": 1, "maxLength": 80},
        "request_data": {"type": "object", "additionalProperties": True},
    },
    ["service_code"],
)
LOGS_SCHEMA = mcp_schema(
    {
        "service_id": {"type": "integer", "minimum": 1},
        "start_date": {"type": "string"},
        "end_date": {"type": "string"},
        "limit": {"type": "integer", "minimum": 1, "maximum": 100},
        "skip": {"type": "integer", "minimum": 0},
    }
)
LOG_ID_SCHEMA = mcp_schema({"log_id": {"type": "integer", "minimum": 1}}, ["log_id"])


def list_zohal_services_handler(args, context):
    from app.services.system_settings_service import get_zohal_settings
    from app.services.wallet_service import get_wallet_overview
    from app.services.zohal_service import list_zohal_services

    db = mcp_db(context)
    bid = mcp_bid(context)
    services = mcp_run(list_zohal_services, db, category=args.get("category"), only_active=True)
    wallet = mcp_run(get_wallet_overview, db, bid)
    settings = mcp_run(get_zohal_settings, db)
    threshold = settings.get("low_balance_threshold", 10000)
    balance = wallet.get("available_balance", 0)
    return mcp_jsonable(
        {
            "services": services,
            "wallet_balance": balance,
            "wallet_currency": wallet.get("base_currency_code"),
            "low_balance_warning": balance < threshold,
            "low_balance_threshold": threshold,
        }
    )


def execute_zohal_inquiry_handler(args, context):
    from app.services.zohal_service import execute_zohal_inquiry

    return mcp_jsonable(
        mcp_run(
            execute_zohal_inquiry,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            str(args["service_code"]),
            args.get("request_data") or {},
        )
    )


def list_zohal_inquiry_logs_handler(args, context):
    from app.services.zohal_service import list_zohal_service_logs

    return mcp_jsonable(
        mcp_run(
            list_zohal_service_logs,
            mcp_db(context),
            mcp_bid(context),
            service_id=args.get("service_id"),
            start_date=args.get("start_date"),
            end_date=args.get("end_date"),
            limit=int(args.get("limit") or 50),
            skip=int(args.get("skip") or 0),
        )
    )


def get_zohal_inquiry_log_handler(args, context):
    from app.services.zohal_service import get_zohal_service_log

    return mcp_jsonable(mcp_run(get_zohal_service_log, mcp_db(context), int(args["log_id"]), mcp_bid(context)))


def register_mcp_zohal_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="list_zohal_services",
        description="فهرست سرویس‌های فعال استعلام زحل به‌همراه موجودی کیف‌پول کسب‌وکار متصل. قبل از اجرای استعلام از این ابزار schema هر سرویس را بخوان.",
        parameters_schema=LIST_SCHEMA,
        handler=list_zohal_services_handler,
        allowed_roles=roles,
        required_permissions=["zohal.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="execute_zohal_inquiry",
        description="اجرای استعلام زحل با service_code و request_data مطابق schema سرویس. از کیف‌پول کسب‌وکار کسر و سند حسابداری می‌سازد. نیازمند تأیید.",
        parameters_schema=EXECUTE_SCHEMA,
        handler=execute_zohal_inquiry_handler,
        allowed_roles=roles,
        required_permissions=["zohal.execute"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_zohal_inquiry_logs",
        description="تاریخچه استعلام‌های زحل کسب‌وکار متصل، حداکثر ۱۰۰ مورد در صفحه.",
        parameters_schema=LOGS_SCHEMA,
        handler=list_zohal_inquiry_logs_handler,
        allowed_roles=roles,
        required_permissions=["zohal.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="get_zohal_inquiry_log",
        description="جزئیات یک لاگ استعلام زحل متعلق به کسب‌وکار متصل.",
        parameters_schema=LOG_ID_SCHEMA,
        handler=get_zohal_inquiry_log_handler,
        allowed_roles=roles,
        required_permissions=["zohal.view"],
        category="integration",
        is_readonly=True,
    ))
