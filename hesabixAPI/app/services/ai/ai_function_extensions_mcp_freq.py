"""MCP tools for frequent document descriptions. Membership-only writes; tenant pinned."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_run, mcp_schema

CREATE_FREQUENT_DESCRIPTION_SCHEMA: Dict[str, Any] = {}
UPDATE_FREQUENT_DESCRIPTION_SCHEMA: Dict[str, Any] = {}

CREATE_FREQUENT_DESCRIPTION_SCHEMA = mcp_schema(
    {
        "text": {"type": "string", "minLength": 1, "maxLength": 2000},
        "scope": {"type": "string", "maxLength": 64, "description": "مثل general یا receipt_payment"},
        "sort_order": {"type": "integer"},
    },
    ["text"],
)
UPDATE_FREQUENT_DESCRIPTION_SCHEMA = mcp_schema(
    {
        "description_id": {"type": "integer", "minimum": 1},
        "text": {"type": "string", "minLength": 1, "maxLength": 2000},
        "sort_order": {"type": "integer"},
    },
    ["description_id"],
)
_ID = mcp_schema({"description_id": {"type": "integer", "minimum": 1}}, ["description_id"])


def _map_freq_error(exc: BaseException) -> None:
    if isinstance(exc, ValueError) and exc.args:
        code = exc.args[0]
        mapping = {
            "TEXT_TOO_LONG": "حداکثر طول شرح ۲۰۰۰ کاراکتر است.",
            "TEXT_EMPTY": "متن شرح نمی‌تواند خالی باشد.",
            "LIMIT_REACHED": "حداکثر ۵۰۰ شرح پرتکرار برای هر بخش مجاز است.",
        }
        if code in mapping:
            raise ValueError(mapping[code]) from exc
    from app.core.responses import ApiError

    if isinstance(exc, ApiError):
        raise ValueError(exc.message) from exc
    raise exc


def _run_freq(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception as exc:
        _map_freq_error(exc)


def create_frequent_description_handler(args, context):
    from app.services.business_frequent_description_service import create_row, to_dict

    row = _run_freq(
        create_row,
        mcp_db(context),
        mcp_bid(context),
        args["text"],
        sort_order=args.get("sort_order"),
        scope=args.get("scope"),
    )
    mcp_commit(context)
    return to_dict(row)


def update_frequent_description_handler(args, context):
    from app.services.business_frequent_description_service import to_dict, update_row

    row = _run_freq(
        update_row,
        mcp_db(context),
        mcp_bid(context),
        int(args["description_id"]),
        text=args.get("text"),
        sort_order=args.get("sort_order"),
    )
    if row is None:
        raise ValueError("شرح پرتکرار یافت نشد")
    mcp_commit(context)
    return to_dict(row)


def delete_frequent_description_handler(args, context):
    from app.services.business_frequent_description_service import delete_row

    ok = _run_freq(delete_row, mcp_db(context), mcp_bid(context), int(args["description_id"]))
    if not ok:
        raise ValueError("شرح پرتکرار یافت نشد")
    mcp_commit(context)
    return {"deleted": True, "id": int(args["description_id"])}


def register_mcp_frequent_description_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="create_frequent_description",
        description="افزودن شرح پرتکرار برای اسناد کسب‌وکار متصل. حداکثر ۵۰۰ مورد در هر اسکوپ.",
        parameters_schema=CREATE_FREQUENT_DESCRIPTION_SCHEMA,
        handler=create_frequent_description_handler,
        allowed_roles=roles,
        required_permissions=["settings.business"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_frequent_description",
        description="ویرایش متن یا ترتیب شرح پرتکرار متعلق به کسب‌وکار متصل.",
        parameters_schema=UPDATE_FREQUENT_DESCRIPTION_SCHEMA,
        handler=update_frequent_description_handler,
        allowed_roles=roles,
        required_permissions=["settings.business"],
        category="financial",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_frequent_description",
        description="حذف شرح پرتکرار متعلق به کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_ID,
        handler=delete_frequent_description_handler,
        allowed_roles=roles,
        required_permissions=["settings.business"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
