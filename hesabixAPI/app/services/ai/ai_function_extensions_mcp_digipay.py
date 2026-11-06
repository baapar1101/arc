"""MCP tools for DigiPay credit. Plugin-gated. Secrets are never returned."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
UPDATE_SETTINGS_SCHEMA = mcp_schema(
    {
        "environment": {"type": "string", "enum": ["sandbox", "live"]},
        "person_id": {"type": "integer", "minimum": 1},
        "settlement_bank_account_id": {"type": ["integer", "null"], "minimum": 0},
        "commission_percent": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
        "vat_on_commission_percent": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
        "seller_id": {"type": ["string", "null"], "maxLength": 80},
        "auto_deliver_in_store": {"type": "boolean"},
    }
)
CREATE_TICKET_SCHEMA = mcp_schema(
    {
        "amount": {"type": "number", "exclusiveMinimum": 0},
        "cell_number": {"type": "string", "minLength": 10, "maxLength": 15},
        "callback_url": {"type": "string", "minLength": 12, "maxLength": 500, "description": "HTTPS callback برای بازگشت از درگاه"},
        "invoice_id": {"type": ["integer", "null"], "minimum": 1},
        "source": {"type": "string", "maxLength": 40},
        "basket_items": {"type": "array", "maxItems": 50, "items": {"type": "object"}},
    },
    ["amount", "cell_number", "callback_url"],
)
LIST_PURCHASES_SCHEMA = mcp_schema(
    {
        "status": {"type": "string", "maxLength": 32},
        "date_from": {"type": "string"},
        "date_to": {"type": "string"},
        "limit": {"type": "integer", "minimum": 1, "maximum": 200},
        "offset": {"type": "integer", "minimum": 0},
    }
)
PURCHASE_ID = mcp_schema({"purchase_id": {"type": "integer", "minimum": 1}}, ["purchase_id"])
RECORD_MANUAL_SCHEMA = mcp_schema(
    {
        "amount": {"type": "number", "exclusiveMinimum": 0},
        "cell_number": {"type": ["string", "null"], "maxLength": 15},
        "tracking_code": {"type": ["string", "null"], "maxLength": 80},
        "provider_id": {"type": ["string", "null"], "maxLength": 80},
        "source": {"type": "string", "maxLength": 40},
    },
    ["amount"],
)
REFUND_SCHEMA = mcp_schema(
    {
        "purchase_id": {"type": "integer", "minimum": 1},
        "amount": {"type": ["number", "null"], "exclusiveMinimum": 0},
        "reason": {"type": ["string", "null"], "maxLength": 500},
    },
    ["purchase_id"],
)
SETTLE_SCHEMA = mcp_schema(
    {
        "purchase_ids": {"type": "array", "minItems": 1, "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
        "bank_account_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["purchase_ids"],
)
_SETTING_KEYS = (
    "environment",
    "person_id",
    "settlement_bank_account_id",
    "commission_percent",
    "vat_on_commission_percent",
    "seller_id",
    "auto_deliver_in_store",
)


def get_digipay_settings_handler(args, context):
    from app.services.digipay_service import get_settings

    return mcp_jsonable(mcp_run(get_settings, mcp_db(context), mcp_bid(context), locale="fa"))


def update_digipay_settings_handler(args, context):
    from app.services.digipay_service import update_settings

    payload = {k: args[k] for k in _SETTING_KEYS if k in args}
    return mcp_jsonable(mcp_run(update_settings, mcp_db(context), mcp_bid(context), payload, locale="fa"))


def test_digipay_connection_handler(args, context):
    from app.services.digipay_service import test_connection

    return mcp_jsonable(mcp_run(test_connection, mcp_db(context), mcp_bid(context), locale="fa"))


def create_digipay_ticket_handler(args, context):
    from app.services.digipay_service import create_ticket

    callback = str(args["callback_url"]).strip()
    if not callback.lower().startswith("https://"):
        raise ValueError("callback_url باید HTTPS باشد.")
    payload = {
        "amount": args["amount"],
        "cell_number": args["cell_number"],
        "invoice_id": args.get("invoice_id"),
        "source": args.get("source") or "mcp",
    }
    if args.get("basket_items"):
        payload["basket_items"] = args["basket_items"]
    return mcp_jsonable(
        mcp_run(
            create_ticket,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            payload,
            locale="fa",
            callback_url=callback,
        )
    )


def list_digipay_purchases_handler(args, context):
    from app.services.digipay_service import list_purchases

    return mcp_jsonable(
        mcp_run(
            list_purchases,
            mcp_db(context),
            mcp_bid(context),
            locale="fa",
            status=args.get("status"),
            date_from=args.get("date_from"),
            date_to=args.get("date_to"),
            limit=int(args.get("limit") or 50),
            offset=int(args.get("offset") or 0),
        )
    )


def get_digipay_purchase_handler(args, context):
    from app.services.digipay_service import get_purchase

    return mcp_jsonable(
        mcp_run(get_purchase, mcp_db(context), mcp_bid(context), int(args["purchase_id"]), locale="fa")
    )


def record_digipay_manual_purchase_handler(args, context):
    from app.services.digipay_service import record_manual_purchase

    payload = {k: args[k] for k in ("amount", "cell_number", "tracking_code", "provider_id", "source") if k in args}
    return mcp_jsonable(
        mcp_run(record_manual_purchase, mcp_db(context), mcp_bid(context), mcp_uid(context), payload, locale="fa")
    )


def deliver_digipay_purchase_handler(args, context):
    from app.services.digipay_service import deliver_purchase

    return mcp_jsonable(
        mcp_run(deliver_purchase, mcp_db(context), mcp_bid(context), int(args["purchase_id"]), locale="fa")
    )


def refund_digipay_purchase_handler(args, context):
    from app.services.digipay_service import refund_purchase

    payload = {k: args[k] for k in ("amount", "reason") if k in args}
    return mcp_jsonable(
        mcp_run(
            refund_purchase,
            mcp_db(context),
            mcp_bid(context),
            int(args["purchase_id"]),
            payload,
            locale="fa",
        )
    )


def preview_digipay_settlement_handler(args, context):
    from app.services.digipay_service import preview_settlement

    payload = {"purchase_ids": args["purchase_ids"], "bank_account_id": args.get("bank_account_id")}
    return mcp_jsonable(mcp_run(preview_settlement, mcp_db(context), mcp_bid(context), payload, locale="fa"))


def register_digipay_settlement_handler(args, context):
    from app.services.digipay_service import register_settlement

    payload = {"purchase_ids": args["purchase_ids"], "bank_account_id": args.get("bank_account_id")}
    return mcp_jsonable(
        mcp_run(
            register_settlement,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            payload,
            locale="fa",
        )
    )


def register_mcp_digipay_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_digipay_settings",
        description="تنظیمات دیجی‌پی کسب‌وکار متصل با فیلدهای محرمانه ماسک‌شده. افزونه digipay_credit باید فعال باشد.",
        parameters_schema=EMPTY,
        handler=get_digipay_settings_handler,
        allowed_roles=roles,
        required_permissions=["digipay.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="update_digipay_settings",
        description="ویرایش محیط، شخص تسویه، بانک، کارمزد و تحویل خودکار دیجی‌پی. نام کاربری و رمز از MCP قابل تنظیم نیست. نیازمند تأیید.",
        parameters_schema=UPDATE_SETTINGS_SCHEMA,
        handler=update_digipay_settings_handler,
        allowed_roles=roles,
        required_permissions=["digipay.manage"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="test_digipay_connection",
        description="آزمون اتصال به API دیجی‌پی با اعتبار ذخیره‌شده کسب‌وکار. رمز برنمی‌گردد.",
        parameters_schema=EMPTY,
        handler=test_digipay_connection_handler,
        allowed_roles=roles,
        required_permissions=["digipay.manage"],
        category="integration",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="create_digipay_ticket",
        description="صدور تیکت پرداخت اعتباری دیجی‌پی و لینک هدایت مشتری. callback_url باید HTTPS باشد. نیازمند تأیید.",
        parameters_schema=CREATE_TICKET_SCHEMA,
        handler=create_digipay_ticket_handler,
        allowed_roles=roles,
        required_permissions=["digipay.write"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_digipay_purchases",
        description="فهرست خریدهای دیجی‌پی کسب‌وکار متصل، حداکثر ۲۰۰ مورد.",
        parameters_schema=LIST_PURCHASES_SCHEMA,
        handler=list_digipay_purchases_handler,
        allowed_roles=roles,
        required_permissions=["digipay.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="get_digipay_purchase",
        description="جزئیات یک خرید دیجی‌پی متعلق به کسب‌وکار متصل.",
        parameters_schema=PURCHASE_ID,
        handler=get_digipay_purchase_handler,
        allowed_roles=roles,
        required_permissions=["digipay.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="record_digipay_manual_purchase",
        description="ثبت دستی خرید QR/پوز دیجی‌پی برای سند حسابداری بعدی. نیازمند تأیید.",
        parameters_schema=RECORD_MANUAL_SCHEMA,
        handler=record_digipay_manual_purchase_handler,
        allowed_roles=roles,
        required_permissions=["digipay.write"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="deliver_digipay_purchase",
        description="اعلام تحویل خرید دیجی‌پی به درگاه. نیازمند تأیید.",
        parameters_schema=PURCHASE_ID,
        handler=deliver_digipay_purchase_handler,
        allowed_roles=roles,
        required_permissions=["digipay.write"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="refund_digipay_purchase",
        description="استرداد کل یا بخشی از خرید دیجی‌پی. نیازمند تأیید.",
        parameters_schema=REFUND_SCHEMA,
        handler=refund_digipay_purchase_handler,
        allowed_roles=roles,
        required_permissions=["digipay.write"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="preview_digipay_settlement",
        description="پیش‌نمایش تسهیم و کارمزد تسویه خریدهای دیجی‌پی انتخاب‌شده.",
        parameters_schema=SETTLE_SCHEMA,
        handler=preview_digipay_settlement_handler,
        allowed_roles=roles,
        required_permissions=["digipay.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="register_digipay_settlement",
        description="ثبت سند تسویه خریدهای دیجی‌پی انتخاب‌شده. نیازمند تأیید.",
        parameters_schema=SETTLE_SCHEMA,
        handler=register_digipay_settlement_handler,
        allowed_roles=roles,
        required_permissions=["digipay.write"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
