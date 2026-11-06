"""MCP tools for the public business pay-page (settings and received payments)."""
from __future__ import annotations

from datetime import datetime

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema

EMPTY = mcp_schema({})
USERNAME_SCHEMA = mcp_schema({"username": {"type": "string", "minLength": 3, "maxLength": 40}}, ["username"])
UPDATE_SCHEMA = mcp_schema(
    {
        "username": {"type": "string", "minLength": 3, "maxLength": 40},
        "display_title": {"type": ["string", "null"], "maxLength": 120},
        "show_logo": {"type": "boolean"},
        "intro_text": {"type": ["string", "null"], "maxLength": 500},
        "gateway_id": {"type": ["integer", "null"], "minimum": 0},
        "min_amount": {"type": ["number", "null"], "minimum": 0},
        "max_amount": {"type": ["number", "null"], "minimum": 0},
        "notify_inapp": {"type": "boolean"},
        "notify_sms": {"type": "boolean"},
        "match_customer_by_mobile": {"type": "boolean"},
        "is_enabled": {"type": "boolean"},
    }
)
PAYMENTS_SCHEMA = mcp_schema(
    {
        "search": {"type": "string", "maxLength": 80},
        "from_date": {"type": "string"},
        "to_date": {"type": "string"},
        "take": {"type": "integer", "minimum": 1, "maximum": 100},
        "skip": {"type": "integer", "minimum": 0},
    }
)
_UPDATE_KEYS = (
    "username",
    "display_title",
    "show_logo",
    "intro_text",
    "gateway_id",
    "min_amount",
    "max_amount",
    "notify_inapp",
    "notify_sms",
    "match_customer_by_mobile",
    "is_enabled",
)


def _parse_dt(raw):
    if not raw:
        return None
    return datetime.fromisoformat(str(raw).replace("Z", "+00:00"))


def get_pay_page_settings_handler(args, context):
    from app.services.business_pay_page_service import get_pay_page_settings

    return mcp_jsonable(mcp_run(get_pay_page_settings, mcp_db(context), mcp_bid(context)))


def check_pay_page_username_handler(args, context):
    from app.services.business_pay_page_service import check_username_availability

    return mcp_jsonable(
        mcp_run(check_username_availability, mcp_db(context), business_id=mcp_bid(context), username=str(args["username"]))
    )


def update_pay_page_settings_handler(args, context):
    from app.services.business_pay_page_service import update_pay_page_settings

    payload = {k: args[k] for k in _UPDATE_KEYS if k in args}
    result = mcp_jsonable(mcp_run(update_pay_page_settings, mcp_db(context), mcp_bid(context), payload))
    mcp_commit(context)
    return result


def list_pay_page_payments_handler(args, context):
    from app.services.business_pay_page_service import list_pay_page_payments

    return mcp_jsonable(
        mcp_run(
            list_pay_page_payments,
            mcp_db(context),
            mcp_bid(context),
            take=int(args.get("take") or 20),
            skip=int(args.get("skip") or 0),
            from_date=_parse_dt(args.get("from_date")),
            to_date=_parse_dt(args.get("to_date")),
            search=args.get("search"),
        )
    )


def register_mcp_pay_page_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_pay_page_settings",
        description="تنظیمات لینک واریز عمومی کسب‌وکار متصل شامل نام کاربری، درگاه، حداقل/حداکثر مبلغ و اعلان‌ها.",
        parameters_schema=EMPTY,
        handler=get_pay_page_settings_handler,
        allowed_roles=roles,
        required_permissions=["settings.view"],
        category="financial",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="check_pay_page_username",
        description="بررسی آزاد بودن نام کاربری لینک واریز عمومی (بدون ذخیره).",
        parameters_schema=USERNAME_SCHEMA,
        handler=check_pay_page_username_handler,
        allowed_roles=roles,
        required_permissions=["settings.view"],
        category="financial",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="update_pay_page_settings",
        description="ذخیره نام کاربری، متن، درگاه و محدودیت مبلغ لینک واریز عمومی. نیازمند تأیید.",
        parameters_schema=UPDATE_SCHEMA,
        handler=update_pay_page_settings_handler,
        allowed_roles=roles,
        required_permissions=["settings.write"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_pay_page_payments",
        description="واریزهای دریافتی از لینک عمومی کسب‌وکار متصل، حداکثر ۱۰۰ مورد در صفحه.",
        parameters_schema=PAYMENTS_SCHEMA,
        handler=list_pay_page_payments_handler,
        allowed_roles=roles,
        required_permissions=["settings.view"],
        category="financial",
        is_readonly=True,
    ))
