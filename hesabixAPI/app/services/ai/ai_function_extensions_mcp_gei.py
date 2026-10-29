"""MCP tools for goods expense/income warehouse documents. extra_info omitted; post/cancel/delete always confirm."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_can, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

CREATE_GOODS_EXPENSE_INCOME_SCHEMA: Dict[str, Any] = {}
UPDATE_GOODS_EXPENSE_INCOME_SCHEMA: Dict[str, Any] = {}

_LINE = {
    "type": "object",
    "additionalProperties": False,
    "required": ["product_id", "warehouse_id", "quantity"],
    "properties": {
        "product_id": {"type": "integer", "minimum": 1},
        "warehouse_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "number", "exclusiveMinimum": 0},
        "unit_cost": {"type": ["number", "null"], "minimum": 0},
        "description": {"type": ["string", "null"], "maxLength": 2000},
    },
}
_HEADER = {
    "document_date": {"type": "string", "description": "ISO date YYYY-MM-DD"},
    "description": {"type": ["string", "null"], "maxLength": 4000},
    "person_id": {"type": ["integer", "null"], "minimum": 1},
    "currency_id": {"type": "integer", "minimum": 1},
    "effect_account_id": {"type": ["integer", "null"], "minimum": 1},
    "effect_account_code": {"type": ["string", "null"], "maxLength": 64},
    "lines": {"type": "array", "minItems": 1, "maxItems": 200, "items": _LINE},
}
CREATE_GOODS_EXPENSE_INCOME_SCHEMA = mcp_schema(
    {
        "doc_kind": {"type": "string", "enum": ["goods_expense", "goods_income"]},
        **_HEADER,
    },
    ["doc_kind", "document_date", "lines"],
)
UPDATE_GOODS_EXPENSE_INCOME_SCHEMA = mcp_schema(
    {
        "document_id": {"type": "integer", "minimum": 1},
        **_HEADER,
    },
    ["document_id"],
)
_DOC_ID = mcp_schema({"document_id": {"type": "integer", "minimum": 1}}, ["document_id"])
_LIST = mcp_schema(
    {
        "doc_kind": {"type": "string", "enum": ["goods_expense", "goods_income"]},
        "status": {"type": "string", "maxLength": 32},
        "person_id": {"type": "integer", "minimum": 1},
        "fiscal_year_id": {"type": "integer", "minimum": 1},
        "search": {"type": "string", "maxLength": 200},
        "date_from": {"type": "string"},
        "date_to": {"type": "string"},
        "take": {"type": "integer", "minimum": 1, "maximum": 100},
        "skip": {"type": "integer", "minimum": 0},
    }
)
_ALLOCATE = mcp_schema(
    {
        "document_id": {"type": "integer", "minimum": 1},
        "effect_account_id": {"type": "integer", "minimum": 1},
        "effect_account_code": {"type": "string", "maxLength": 64},
    },
    ["document_id"],
)
_CREATE_KEYS = (
    "doc_kind",
    "document_date",
    "description",
    "person_id",
    "currency_id",
    "effect_account_id",
    "effect_account_code",
    "lines",
)


def get_goods_expense_income_settings_handler(args, context):
    from app.services.goods_expense_income_service import _get_business, get_workflow_settings

    biz = mcp_run(_get_business, mcp_db(context), mcp_bid(context))
    return mcp_jsonable(get_workflow_settings(biz))


def list_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import list_documents

    query = {k: v for k, v in args.items() if k in ("doc_kind", "status", "person_id", "fiscal_year_id", "search", "date_from", "date_to", "take", "skip")}
    take = int(query.pop("take", 20) or 20)
    skip = int(query.pop("skip", 0) or 0)
    query["page_size"] = take
    query["page"] = (skip // take) + 1
    return mcp_jsonable(mcp_run(list_documents, mcp_db(context), mcp_bid(context), query))


def get_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import get_document

    return mcp_jsonable(mcp_run(get_document, mcp_db(context), mcp_bid(context), int(args["document_id"])))


def create_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import create_document

    data = {k: v for k, v in args.items() if k in _CREATE_KEYS}
    return mcp_jsonable(
        mcp_run(
            create_document,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            data,
            user_can_allocate=mcp_can(context, "goods_expense_income", "allocate"),
            user_can_post=mcp_can(context, "goods_expense_income", "post"),
            user_can_change_unit_cost=mcp_can(context, "goods_expense_income", "change_unit_cost"),
        )
    )


def update_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import update_document

    data = {k: v for k, v in args.items() if k in _CREATE_KEYS and k != "doc_kind"}
    return mcp_jsonable(
        mcp_run(
            update_document,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            int(args["document_id"]),
            data,
            user_can_allocate=mcp_can(context, "goods_expense_income", "allocate"),
            user_can_change_unit_cost=mcp_can(context, "goods_expense_income", "change_unit_cost"),
            is_ops_edit=not mcp_can(context, "goods_expense_income", "allocate"),
        )
    )


def submit_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import submit_to_accounting

    return mcp_jsonable(
        mcp_run(submit_to_accounting, mcp_db(context), mcp_bid(context), mcp_uid(context), int(args["document_id"]))
    )


def allocate_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import allocate_account

    body = {k: v for k, v in args.items() if k in ("effect_account_id", "effect_account_code")}
    return mcp_jsonable(
        mcp_run(allocate_account, mcp_db(context), mcp_bid(context), mcp_uid(context), int(args["document_id"]), body)
    )


def post_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import post_document

    return mcp_jsonable(
        mcp_run(post_document, mcp_db(context), mcp_bid(context), mcp_uid(context), int(args["document_id"]))
    )


def cancel_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import cancel_document

    return mcp_jsonable(
        mcp_run(cancel_document, mcp_db(context), mcp_bid(context), mcp_uid(context), int(args["document_id"]))
    )


def delete_goods_expense_income_handler(args, context):
    from app.services.goods_expense_income_service import delete_document

    return mcp_jsonable(mcp_run(delete_document, mcp_db(context), mcp_bid(context), int(args["document_id"])))


def register_mcp_gei_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_goods_expense_income_settings",
        description="تنظیمات گردش‌کار کالای هزینه‌شده/درآمدشده کسب‌وکار متصل.",
        parameters_schema=mcp_schema({}),
        handler=get_goods_expense_income_settings_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.view"],
        category="warehouse",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="list_goods_expense_income",
        description="فهرست اسناد کالای هزینه/درآمد کسب‌وکار متصل. حداکثر ۱۰۰ مورد در صفحه.",
        parameters_schema=_LIST,
        handler=list_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.view"],
        category="warehouse",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="get_goods_expense_income",
        description="جزئیات سند کالای هزینه/درآمد متعلق به کسب‌وکار متصل.",
        parameters_schema=_DOC_ID,
        handler=get_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.view"],
        category="warehouse",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_goods_expense_income",
        description="ثبت سند کالای هزینه‌شده یا درآمدشده. کالا باید کنترل موجودی داشته باشد.",
        parameters_schema=CREATE_GOODS_EXPENSE_INCOME_SCHEMA,
        handler=create_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_goods_expense_income",
        description="ویرایش سند غیرقطعی کالای هزینه/درآمد متعلق به کسب‌وکار متصل.",
        parameters_schema=UPDATE_GOODS_EXPENSE_INCOME_SCHEMA,
        handler=update_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="submit_goods_expense_income",
        description="ارسال سند کالای هزینه/درآمد به حسابداری در گردش‌کار دو مرحله‌ای.",
        parameters_schema=_DOC_ID,
        handler=submit_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.submit"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="allocate_goods_expense_income",
        description="تخصیص حساب معین به سند کالای هزینه/درآمد.",
        parameters_schema=_ALLOCATE,
        handler=allocate_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.allocate"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="post_goods_expense_income",
        description="قطعی‌سازی سند: حواله انبار و سند حسابداری. نیازمند تأیید.",
        parameters_schema=_DOC_ID,
        handler=post_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.post"],
        category="warehouse",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="cancel_goods_expense_income",
        description="ابطال سند قطعی کالای هزینه/درآمد. نیازمند تأیید.",
        parameters_schema=_DOC_ID,
        handler=cancel_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.cancel"],
        category="warehouse",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_goods_expense_income",
        description="حذف سند غیرقطعی کالای هزینه/درآمد. نیازمند تأیید.",
        parameters_schema=_DOC_ID,
        handler=delete_goods_expense_income_handler,
        allowed_roles=roles,
        required_permissions=["goods_expense_income.delete"],
        category="warehouse",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
