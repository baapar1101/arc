"""MCP tools for business currencies and FX rates. extra_info is out of band."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

CREATE_CURRENCY_RATE_SCHEMA: Dict[str, Any] = {}
UPDATE_CURRENCY_RATE_SCHEMA: Dict[str, Any] = {}

CREATE_CURRENCY_RATE_SCHEMA = mcp_schema(
    {
        "currency_id": {"type": "integer", "minimum": 1},
        "effective_at": {"type": "string", "description": "زمان مؤثر ISO-8601"},
        "rate": {"type": "number", "exclusiveMinimum": 0},
        "note": {"type": ["string", "null"], "maxLength": 500},
    },
    ["currency_id", "effective_at", "rate"],
)
UPDATE_CURRENCY_RATE_SCHEMA = mcp_schema(
    {
        "rate_id": {"type": "integer", "minimum": 1},
        "currency_id": {"type": "integer", "minimum": 1},
        "effective_at": {"type": "string"},
        "rate": {"type": "number", "exclusiveMinimum": 0},
        "note": {"type": ["string", "null"], "maxLength": 500},
    },
    ["rate_id"],
)
_RATE_ID = mcp_schema({"rate_id": {"type": "integer", "minimum": 1}}, ["rate_id"])
_CUR_ID = mcp_schema({"currency_id": {"type": "integer", "minimum": 1}}, ["currency_id"])
_LIST = mcp_schema(
    {
        "currency_id": {"type": "integer", "minimum": 1},
        "take": {"type": "integer", "minimum": 1, "maximum": 200},
        "skip": {"type": "integer", "minimum": 0},
    }
)
_RESOLVE = mcp_schema(
    {
        "currency_id": {"type": "integer", "minimum": 1},
        "as_of": {"type": "string", "description": "زمان ISO-8601"},
    },
    ["currency_id"],
)
_RATE_KEYS = ("currency_id", "effective_at", "rate", "note")


def list_currency_rates_handler(args, context):
    from app.services.business_currency_rate_service import list_business_currency_rates

    items, total = mcp_run(
        list_business_currency_rates,
        mcp_db(context),
        mcp_bid(context),
        currency_id=args.get("currency_id"),
        skip=int(args.get("skip") or 0),
        take=int(args.get("take") or 50),
    )
    return mcp_jsonable({"items": items, "total": total})


def get_latest_currency_rates_handler(args, context):
    from app.services.business_currency_rate_service import list_latest_rates_for_business

    return mcp_jsonable(mcp_run(list_latest_rates_for_business, mcp_db(context), mcp_bid(context)))


def resolve_currency_rate_handler(args, context):
    from datetime import datetime, timezone

    from app.services.business_currency_rate_service import resolve_rate_to_base

    raw = args.get("as_of")
    if raw:
        as_of = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    else:
        as_of = datetime.now(timezone.utc)
    return mcp_jsonable(
        mcp_run(resolve_rate_to_base, mcp_db(context), mcp_bid(context), int(args["currency_id"]), as_of)
    )


def create_currency_rate_handler(args, context):
    from app.services.business_currency_rate_service import create_business_currency_rate

    data = {k: v for k, v in args.items() if k in _RATE_KEYS}
    row = mcp_run(create_business_currency_rate, mcp_db(context), mcp_bid(context), mcp_uid(context), data)
    mcp_commit(context)
    return mcp_jsonable(row)


def update_currency_rate_handler(args, context):
    from app.services.business_currency_rate_service import update_business_currency_rate

    data = {k: v for k, v in args.items() if k in _RATE_KEYS}
    row = mcp_run(
        update_business_currency_rate,
        mcp_db(context),
        mcp_bid(context),
        mcp_uid(context),
        int(args["rate_id"]),
        data,
    )
    mcp_commit(context)
    return mcp_jsonable(row)


def delete_currency_rate_handler(args, context):
    from app.services.business_currency_rate_service import delete_business_currency_rate

    mcp_run(delete_business_currency_rate, mcp_db(context), mcp_bid(context), int(args["rate_id"]))
    mcp_commit(context)
    return {"deleted": True, "id": int(args["rate_id"])}


def add_business_currency_handler(args, context):
    from app.services.business_service import add_business_currency

    return mcp_jsonable(
        mcp_run(add_business_currency, mcp_db(context), mcp_bid(context), int(args["currency_id"]), mcp_uid(context))
    )


def remove_business_currency_handler(args, context):
    from app.services.business_service import remove_business_currency

    mcp_run(remove_business_currency, mcp_db(context), mcp_bid(context), int(args["currency_id"]), mcp_uid(context))
    return {"deleted": True, "currency_id": int(args["currency_id"])}


def register_mcp_fx_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_latest_currency_rates",
        description="آخرین نرخ هر ارز فرعی فعال کسب‌وکار متصل.",
        parameters_schema=mcp_schema({}),
        handler=get_latest_currency_rates_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.view"],
        category="financial",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_currency_rate",
        description="ثبت نرخ تسعیر برای ارز فرعی فعال کسب‌وکار متصل. برای ارز پایه نرخ ثبت نمی‌شود.",
        parameters_schema=CREATE_CURRENCY_RATE_SCHEMA,
        handler=create_currency_rate_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.write"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_currency_rate",
        description="ویرایش نرخ تسعیر متعلق به کسب‌وکار متصل.",
        parameters_schema=UPDATE_CURRENCY_RATE_SCHEMA,
        handler=update_currency_rate_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.write"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_currency_rate",
        description="حذف نرخ تسعیر متعلق به کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_RATE_ID,
        handler=delete_currency_rate_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.delete"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="add_business_currency",
        description="فعال‌سازی ارز جانبی برای کسب‌وکار متصل.",
        parameters_schema=_CUR_ID,
        handler=add_business_currency_handler,
        allowed_roles=roles,
        required_permissions=["settings.business"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="remove_business_currency",
        description="حذف ارز جانبی در صورت عدم استفاده در اسناد. نیازمند تأیید.",
        parameters_schema=_CUR_ID,
        handler=remove_business_currency_handler,
        allowed_roles=roles,
        required_permissions=["settings.business"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
