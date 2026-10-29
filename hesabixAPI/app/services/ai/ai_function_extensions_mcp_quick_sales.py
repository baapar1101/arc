"""MCP tools for quick sales: enqueue invoice, settings, payment buttons, stock correction."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import (
    mcp_bid,
    mcp_can,
    mcp_db,
    mcp_jsonable,
    mcp_run,
    mcp_schema,
    mcp_uid,
)

ENQUEUE_QUICK_SALE_SCHEMA: Dict[str, Any] = {}
UPDATE_QUICK_SALES_SETTINGS_SCHEMA: Dict[str, Any] = {}
CREATE_QUICK_SALES_PAYMENT_BUTTON_SCHEMA: Dict[str, Any] = {}

_LINE = {
    "type": "object",
    "additionalProperties": False,
    "required": ["product_id", "quantity"],
    "properties": {
        "product_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "number", "exclusiveMinimum": 0},
        "unit_price": {"type": "number", "minimum": 0},
        "warehouse_id": {"type": "integer", "minimum": 1},
        "description": {"type": ["string", "null"], "maxLength": 500},
    },
}
_PAY = {
    "type": "object",
    "additionalProperties": False,
    "required": ["type", "account_id", "amount"],
    "properties": {
        "type": {"type": "string", "enum": ["bank", "cash_register", "petty_cash"]},
        "account_id": {"type": "integer", "minimum": 1},
        "amount": {"type": "number", "exclusiveMinimum": 0},
    },
}
ENQUEUE_QUICK_SALE_SCHEMA = mcp_schema(
    {
        "request_id": {
            "type": "string",
            "minLength": 16,
            "maxLength": 160,
            "description": "شناسه یکتای درخواست فروش سریع",
        },
        "person_id": {"type": "integer", "minimum": 1},
        "warehouse_id": {"type": "integer", "minimum": 1},
        "document_date": {"type": "string"},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "lines": {"type": "array", "minItems": 1, "maxItems": 200, "items": _LINE},
        "payments": {"type": "array", "maxItems": 20, "items": _PAY},
        "stock_override_reason_code": {"type": "string", "enum": ["physical_stock_exists", "urgent_sale", "other"]},
        "stock_override_reason_note": {"type": ["string", "null"], "maxLength": 500},
        "stock_override_request_token": {"type": "string", "maxLength": 80},
    },
    ["request_id", "lines"],
)
_REQUEST = mcp_schema({"request_id": {"type": "string", "minLength": 16, "maxLength": 160}}, ["request_id"])
_SETTING_KEYS = (
    "default_anonymous_customer_id",
    "auto_create_anonymous_customer",
    "anonymous_customer_name",
    "quick_customer_group_id",
    "default_warehouse_id",
    "default_cash_register_id",
    "default_currency_id",
    "default_price_list_id",
    "auto_print",
    "print_paper_size",
    "enable_warehouse_document",
    "warehouse_document_type",
    "auto_post_warehouse",
    "show_inventory",
    "enable_stock_shortage_override",
    "auto_create_payment_document",
    "show_purchase_price",
)
UPDATE_QUICK_SALES_SETTINGS_SCHEMA = mcp_schema(
    {
        "default_anonymous_customer_id": {"type": ["integer", "null"], "minimum": 1},
        "auto_create_anonymous_customer": {"type": "boolean"},
        "anonymous_customer_name": {"type": ["string", "null"], "maxLength": 255},
        "quick_customer_group_id": {"type": ["integer", "null"], "minimum": 1},
        "default_warehouse_id": {"type": ["integer", "null"], "minimum": 1},
        "default_cash_register_id": {"type": ["integer", "null"], "minimum": 1},
        "default_currency_id": {"type": ["integer", "null"], "minimum": 1},
        "default_price_list_id": {"type": ["integer", "null"], "minimum": 1},
        "auto_print": {"type": "boolean"},
        "print_paper_size": {"type": "string", "enum": ["A4", "A5", "A6", "80mm"]},
        "enable_warehouse_document": {"type": "boolean"},
        "warehouse_document_type": {"type": "string", "enum": ["draft", "posted"]},
        "auto_post_warehouse": {"type": "boolean"},
        "show_inventory": {"type": "boolean"},
        "enable_stock_shortage_override": {"type": "boolean"},
        "auto_create_payment_document": {"type": "boolean"},
        "show_purchase_price": {"type": "boolean"},
    }
)
CREATE_QUICK_SALES_PAYMENT_BUTTON_SCHEMA = mcp_schema(
    {
        "scope": {"type": "string", "enum": ["user", "business"]},
        "target_type": {"type": "string", "enum": ["cash_register", "bank", "person"]},
        "target_id": {"type": "integer", "minimum": 1},
        "label": {"type": ["string", "null"], "maxLength": 120},
        "shortcut": {"type": ["string", "null"], "maxLength": 8},
    },
    ["target_type", "target_id"],
)
_BUTTON_UPDATE = mcp_schema(
    {
        "button_id": {"type": "integer", "minimum": 1},
        "scope": {"type": "string", "enum": ["user", "business"]},
        "target_type": {"type": "string", "enum": ["cash_register", "bank", "person"]},
        "target_id": {"type": "integer", "minimum": 1},
        "label": {"type": ["string", "null"], "maxLength": 120},
        "shortcut": {"type": ["string", "null"], "maxLength": 8},
        "is_active": {"type": "boolean"},
    },
    ["button_id"],
)
_BUTTON_ID = mcp_schema({"button_id": {"type": "integer", "minimum": 1}}, ["button_id"])
_REORDER = mcp_schema(
    {
        "button_ids": {
            "type": "array",
            "minItems": 1,
            "maxItems": 50,
            "items": {"type": "integer", "minimum": 1},
        }
    },
    ["button_ids"],
)
_DISC = mcp_schema({"status": {"type": "string", "maxLength": 32}})
_CORR_LINE = {
    "type": "object",
    "additionalProperties": False,
    "required": ["product_id", "warehouse_id", "quantity"],
    "properties": {
        "product_id": {"type": "integer", "minimum": 1},
        "warehouse_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "number", "exclusiveMinimum": 0},
        "description": {"type": ["string", "null"], "maxLength": 500},
    },
}
CREATE_STOCK_CORRECTION_SCHEMA = mcp_schema(
    {
        "request_token": {"type": "string", "minLength": 1, "maxLength": 80},
        "document_date": {"type": "string"},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "confirm_unexplained_physical_surplus": {"type": "boolean"},
        "lines": {"type": "array", "minItems": 1, "maxItems": 100, "items": _CORR_LINE},
    },
    ["request_token", "lines", "confirm_unexplained_physical_surplus"],
)


def enqueue_quick_sale_handler(args, context):
    import re

    from app.core.permissions import user_can_change_invoice_unit_price
    from app.services.quick_sale_invoice_job_service import enqueue_quick_sale_invoice, serialize_quick_sale_job

    request_id = str(args["request_id"]).strip()
    if not re.fullmatch(r"[A-Za-z0-9._:-]{16,160}", request_id):
        raise ValueError("شناسه یکتای درخواست فروش سریع نامعتبر است")
    extra: Dict[str, Any] = {"quick_sale": True, "quick_sale_request_id": request_id}
    payload: Dict[str, Any] = {
        "invoice_type": "invoice_sales",
        "person_id": args.get("person_id"),
        "warehouse_id": args.get("warehouse_id"),
        "document_date": args.get("document_date"),
        "description": args.get("description"),
        "lines": args.get("lines") or [],
        "payments": args.get("payments") or [],
        "extra_info": extra,
    }
    if args.get("stock_override_reason_code"):
        payload["stock_override"] = {
            "reason_code": args["stock_override_reason_code"],
            "reason_note": args.get("stock_override_reason_note"),
            "request_token": args.get("stock_override_request_token") or request_id[:80],
        }
    user = context.get("user_context")
    can_fx = False
    try:
        from adapters.api.v1.invoices import _user_can_select_fx_rate_for_business

        can_fx = bool(_user_can_select_fx_rate_for_business(mcp_db(context), user, mcp_bid(context)))
    except Exception:
        can_fx = False
    job = mcp_run(
        enqueue_quick_sale_invoice,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        request_id=request_id,
        payload=payload,
        user_can_select_fx_rate=can_fx,
        user_can_change_invoice_unit_price=bool(
            user_can_change_invoice_unit_price(user, mcp_db(context), mcp_bid(context))
        )
        if user
        else False,
    )
    return mcp_jsonable(serialize_quick_sale_job(job))


def get_quick_sale_job_handler(args, context):
    from app.services.quick_sale_invoice_job_service import get_quick_sale_invoice_job, serialize_quick_sale_job

    job = mcp_run(
        get_quick_sale_invoice_job,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        request_id=str(args["request_id"]),
    )
    if not job:
        raise ValueError("درخواست فروش سریع یافت نشد")
    return mcp_jsonable(serialize_quick_sale_job(job))


def update_quick_sales_settings_handler(args, context):
    from app.services.quick_sales_service import update_quick_sales_settings

    payload = {k: v for k, v in args.items() if k in _SETTING_KEYS}
    return mcp_jsonable(
        mcp_run(update_quick_sales_settings, mcp_db(context), mcp_bid(context), payload, mcp_uid(context))
    )


def list_quick_sales_payment_buttons_handler(args, context):
    from app.services.quick_sales_service import list_quick_sales_payment_buttons

    return {"items": mcp_jsonable(mcp_run(list_quick_sales_payment_buttons, mcp_db(context), mcp_bid(context), mcp_uid(context)))}


def create_quick_sales_payment_button_handler(args, context):
    from app.services.quick_sales_service import create_quick_sales_payment_button

    return mcp_jsonable(
        mcp_run(
            create_quick_sales_payment_button,
            mcp_db(context),
            business_id=mcp_bid(context),
            user_id=mcp_uid(context),
            payload=args,
            can_manage_business=mcp_can(context, "settings", "business"),
        )
    )


def update_quick_sales_payment_button_handler(args, context):
    from app.services.quick_sales_service import update_quick_sales_payment_button

    payload = {k: v for k, v in args.items() if k != "button_id"}
    return mcp_jsonable(
        mcp_run(
            update_quick_sales_payment_button,
            mcp_db(context),
            business_id=mcp_bid(context),
            button_id=int(args["button_id"]),
            user_id=mcp_uid(context),
            payload=payload,
            can_manage_business=mcp_can(context, "settings", "business"),
        )
    )


def delete_quick_sales_payment_button_handler(args, context):
    from app.services.quick_sales_service import delete_quick_sales_payment_button

    mcp_run(
        delete_quick_sales_payment_button,
        mcp_db(context),
        business_id=mcp_bid(context),
        button_id=int(args["button_id"]),
        user_id=mcp_uid(context),
        can_manage_business=mcp_can(context, "settings", "business"),
    )
    return {"deleted": True, "id": int(args["button_id"])}


def reorder_quick_sales_payment_buttons_handler(args, context):
    from app.services.quick_sales_service import reorder_quick_sales_payment_buttons

    return mcp_jsonable(
        mcp_run(
            reorder_quick_sales_payment_buttons,
            mcp_db(context),
            business_id=mcp_bid(context),
            user_id=mcp_uid(context),
            button_ids=list(args["button_ids"]),
            can_manage_business=mcp_can(context, "settings", "business"),
        )
    )


def list_quick_sales_stock_discrepancies_handler(args, context):
    from app.services.inventory_discrepancy_service import list_cases

    return mcp_jsonable(mcp_run(list_cases, mcp_db(context), mcp_bid(context), args.get("status")))


def create_quick_sales_stock_correction_handler(args, context):
    from datetime import date, datetime

    from app.services.inventory_discrepancy_service import create_goods_income_correction

    if args.get("confirm_unexplained_physical_surplus") is not True:
        raise ValueError("باید تأیید کنید که کالا واقعاً موجود است و منشأ ثبت‌نشده دیگری ندارد")
    raw = args.get("document_date")
    if raw:
        document_date = date.fromisoformat(str(raw)[:10])
    else:
        document_date = datetime.utcnow().date()
    result = mcp_run(
        create_goods_income_correction,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        document_date=document_date,
        lines=list(args.get("lines") or []),
        description=str(args.get("description") or "اصلاح کسری کشف‌شده در فروش سریع"),
        user_can_allocate=mcp_can(context, "goods_expense_income", "allocate"),
        user_can_post=mcp_can(context, "goods_expense_income", "post"),
        user_can_change_unit_cost=mcp_can(context, "goods_expense_income", "change_unit_cost"),
        request_token=str(args["request_token"]),
    )
    mcp_db(context).commit()
    return mcp_jsonable(result)


def register_mcp_quick_sales_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="enqueue_quick_sale",
        description="صف ثبت فاکتور فروش سریع. extra_info توسط سرور ساخته می‌شود. نیازمند تأیید.",
        parameters_schema=ENQUEUE_QUICK_SALE_SCHEMA,
        handler=enqueue_quick_sale_handler,
        allowed_roles=roles,
        required_permissions=["invoices.write"],
        category="invoices",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="get_quick_sale_job",
        description="وضعیت درخواست فروش سریع همین کاربر در کسب‌وکار متصل.",
        parameters_schema=_REQUEST,
        handler=get_quick_sale_job_handler,
        allowed_roles=roles,
        required_permissions=["invoices.read"],
        category="invoices",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="update_quick_sales_settings",
        description="ویرایش تنظیمات فروش سریع کسب‌وکار متصل (انبار، صندوق، مشتری ناشناس).",
        parameters_schema=UPDATE_QUICK_SALES_SETTINGS_SCHEMA,
        handler=update_quick_sales_settings_handler,
        allowed_roles=roles,
        required_permissions=["settings.business"],
        category="invoices",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_quick_sales_payment_buttons",
        description="دکمه‌های پرداخت فروش سریع کاربر و کسب‌وکار متصل.",
        parameters_schema=mcp_schema({}),
        handler=list_quick_sales_payment_buttons_handler,
        allowed_roles=roles,
        required_permissions=["invoices.write"],
        category="invoices",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_quick_sales_payment_button",
        description="ثبت دکمه پرداخت فروش سریع به صندوق، بانک یا شخص همین کسب‌وکار.",
        parameters_schema=CREATE_QUICK_SALES_PAYMENT_BUTTON_SCHEMA,
        handler=create_quick_sales_payment_button_handler,
        allowed_roles=roles,
        required_permissions=["invoices.write"],
        category="invoices",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_quick_sales_payment_button",
        description="ویرایش دکمه پرداخت فروش سریع متعلق به همین کاربر یا کسب‌وکار.",
        parameters_schema=_BUTTON_UPDATE,
        handler=update_quick_sales_payment_button_handler,
        allowed_roles=roles,
        required_permissions=["invoices.write"],
        category="invoices",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_quick_sales_payment_button",
        description="حذف دکمه پرداخت فروش سریع. نیازمند تأیید.",
        parameters_schema=_BUTTON_ID,
        handler=delete_quick_sales_payment_button_handler,
        allowed_roles=roles,
        required_permissions=["invoices.write"],
        category="invoices",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="reorder_quick_sales_payment_buttons",
        description="تغییر ترتیب دکمه‌های پرداخت فروش سریع.",
        parameters_schema=_REORDER,
        handler=reorder_quick_sales_payment_buttons_handler,
        allowed_roles=roles,
        required_permissions=["invoices.write"],
        category="invoices",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_quick_sales_stock_discrepancies",
        description="فهرست مغایرت‌های موجودی کشف‌شده در فروش سریع کسب‌وکار متصل.",
        parameters_schema=_DISC,
        handler=list_quick_sales_stock_discrepancies_handler,
        allowed_roles=roles,
        required_permissions=["inventory.read"],
        category="warehouse",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_quick_sales_stock_correction",
        description="اصلاح کسری موجودی با کالای درآمدشده پیش از فروش سریع. نیازمند تأیید surplus.",
        parameters_schema=CREATE_STOCK_CORRECTION_SCHEMA,
        handler=create_quick_sales_stock_correction_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
