"""MCP tools for catalog specification fields. extra_info is out of band."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_unwrap

CREATE_CATALOG_SPEC_FIELD_SCHEMA: Dict[str, Any] = {}
UPDATE_CATALOG_SPEC_FIELD_SCHEMA: Dict[str, Any] = {}

_TYPES = ["text", "number", "date", "select", "boolean"]
CREATE_CATALOG_SPEC_FIELD_SCHEMA = mcp_schema(
    {
        "title": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"]},
        "data_type": {"type": "string", "enum": _TYPES},
        "options": {"type": "array", "items": {"type": "string"}, "maxItems": 200},
        "sort_order": {"type": "integer", "minimum": 0},
        "is_required": {"type": "boolean"},
        "is_active": {"type": "boolean"},
    },
    ["title"],
)
UPDATE_CATALOG_SPEC_FIELD_SCHEMA = mcp_schema(
    {
        "field_id": {"type": "integer", "minimum": 1},
        "title": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"]},
        "data_type": {"type": "string", "enum": _TYPES},
        "options": {"type": "array", "items": {"type": "string"}, "maxItems": 200},
        "sort_order": {"type": "integer", "minimum": 0},
        "is_required": {"type": "boolean"},
        "is_active": {"type": "boolean"},
    },
    ["field_id"],
)
_FIELD_ID = mcp_schema({"field_id": {"type": "integer", "minimum": 1}}, ["field_id"])
_LIST = mcp_schema(
    {
        "active_only": {"type": "boolean"},
        "search": {"type": "string", "maxLength": 200},
        "take": {"type": "integer", "minimum": 1, "maximum": 100},
        "skip": {"type": "integer", "minimum": 0},
    }
)
_CREATE_KEYS = ("title", "description", "data_type", "options", "sort_order", "is_required", "is_active")


def list_catalog_spec_fields_handler(args, context):
    from app.services.catalog_spec_field_service import list_catalog_spec_fields

    return mcp_jsonable(
        mcp_run(
            list_catalog_spec_fields,
            mcp_db(context),
            mcp_bid(context),
            active_only=bool(args.get("active_only")),
            take=int(args.get("take") or 100),
            skip=int(args.get("skip") or 0),
            search=args.get("search"),
        )
    )


def get_catalog_spec_field_handler(args, context):
    from app.services.catalog_spec_field_service import get_catalog_spec_field

    data = mcp_run(get_catalog_spec_field, mcp_db(context), mcp_bid(context), int(args["field_id"]))
    if not data:
        raise ValueError("فیلد مشخصات یافت نشد")
    return mcp_jsonable(data)


def create_catalog_spec_field_handler(args, context):
    from adapters.api.v1.schema_models.catalog_spec_field import CatalogSpecFieldCreateRequest
    from app.services.catalog_spec_field_service import create_catalog_spec_field

    payload = CatalogSpecFieldCreateRequest(**{k: v for k, v in args.items() if k in _CREATE_KEYS})
    return mcp_jsonable(mcp_unwrap(mcp_run(create_catalog_spec_field, mcp_db(context), mcp_bid(context), payload)))


def update_catalog_spec_field_handler(args, context):
    from adapters.api.v1.schema_models.catalog_spec_field import CatalogSpecFieldUpdateRequest
    from app.services.catalog_spec_field_service import update_catalog_spec_field

    payload = CatalogSpecFieldUpdateRequest(**{k: v for k, v in args.items() if k in _CREATE_KEYS})
    result = mcp_run(update_catalog_spec_field, mcp_db(context), mcp_bid(context), int(args["field_id"]), payload)
    if not result:
        raise ValueError("فیلد مشخصات یافت نشد")
    return mcp_jsonable(mcp_unwrap(result) if isinstance(result, dict) else result)


def delete_catalog_spec_field_handler(args, context):
    from app.services.catalog_spec_field_service import delete_catalog_spec_field

    ok = mcp_run(delete_catalog_spec_field, mcp_db(context), mcp_bid(context), int(args["field_id"]))
    if not ok:
        raise ValueError("فیلد مشخصات یافت نشد")
    return {"deleted": True, "id": int(args["field_id"])}


def register_mcp_catalog_spec_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="list_catalog_spec_fields",
        description="فهرست فیلدهای مشخصات کاتالوگ کسب‌وکار متصل. حداکثر ۱۰۰ مورد در صفحه.",
        parameters_schema=_LIST,
        handler=list_catalog_spec_fields_handler,
        allowed_roles=roles,
        required_permissions=["products.read"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="get_catalog_spec_field",
        description="جزئیات یک فیلد مشخصات کاتالوگ متعلق به کسب‌وکار متصل.",
        parameters_schema=_FIELD_ID,
        handler=get_catalog_spec_field_handler,
        allowed_roles=roles,
        required_permissions=["products.read"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_catalog_spec_field",
        description="ثبت فیلد مشخصات کاتالوگ. برای نوع select حداقل یک گزینه لازم است.",
        parameters_schema=CREATE_CATALOG_SPEC_FIELD_SCHEMA,
        handler=create_catalog_spec_field_handler,
        allowed_roles=roles,
        required_permissions=["products.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_catalog_spec_field",
        description="ویرایش فیلد مشخصات کاتالوگ متعلق به کسب‌وکار متصل.",
        parameters_schema=UPDATE_CATALOG_SPEC_FIELD_SCHEMA,
        handler=update_catalog_spec_field_handler,
        allowed_roles=roles,
        required_permissions=["products.write"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_catalog_spec_field",
        description="حذف فیلد مشخصات کاتالوگ متعلق به کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_FIELD_ID,
        handler=delete_catalog_spec_field_handler,
        allowed_roles=roles,
        required_permissions=["products.delete"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
