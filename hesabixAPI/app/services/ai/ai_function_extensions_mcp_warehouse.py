"""MCP tools for warehouse master, locations, and placements. Tenant is pinned from the credential."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import (
    mcp_bid,
    mcp_db,
    mcp_jsonable,
    mcp_run,
    mcp_schema,
    mcp_unwrap,
)

CREATE_WAREHOUSE_SCHEMA: Dict[str, Any] = {}
UPDATE_WAREHOUSE_SCHEMA: Dict[str, Any] = {}
CREATE_WAREHOUSE_LOCATION_SCHEMA: Dict[str, Any] = {}
CREATE_WAREHOUSE_PLACEMENT_SCHEMA: Dict[str, Any] = {}

_KINDS = ["zone", "aisle", "rack", "shelf", "bin", "other"]
_WH_ID = mcp_schema({"warehouse_id": {"type": "integer", "minimum": 1}}, ["warehouse_id"])
CREATE_WAREHOUSE_SCHEMA = mcp_schema(
    {
        "code": {"type": ["string", "null"], "maxLength": 64},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "warehouse_keeper": {"type": ["string", "null"], "maxLength": 255},
        "phone": {"type": ["string", "null"], "maxLength": 32},
        "address": {"type": ["string", "null"], "maxLength": 2000},
        "postal_code": {"type": ["string", "null"], "maxLength": 16},
        "is_default": {"type": "boolean"},
    },
    ["name"],
)
UPDATE_WAREHOUSE_SCHEMA = mcp_schema(
    {
        "warehouse_id": {"type": "integer", "minimum": 1},
        "code": {"type": ["string", "null"], "maxLength": 64},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "warehouse_keeper": {"type": ["string", "null"], "maxLength": 255},
        "phone": {"type": ["string", "null"], "maxLength": 32},
        "address": {"type": ["string", "null"], "maxLength": 2000},
        "postal_code": {"type": ["string", "null"], "maxLength": 16},
        "is_default": {"type": "boolean"},
    },
    ["warehouse_id"],
)
CREATE_WAREHOUSE_LOCATION_SCHEMA = mcp_schema(
    {
        "warehouse_id": {"type": "integer", "minimum": 1},
        "code": {"type": ["string", "null"], "maxLength": 64},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "parent_id": {"type": ["integer", "null"], "minimum": 1},
        "location_kind": {"type": "string", "enum": _KINDS},
        "sort_order": {"type": "integer"},
        "is_active": {"type": "boolean"},
        "notes": {"type": ["string", "null"], "maxLength": 4000},
        "auto_generate_code": {"type": "boolean"},
    },
    ["warehouse_id", "name"],
)
_LOC_UPDATE = mcp_schema(
    {
        "warehouse_id": {"type": "integer", "minimum": 1},
        "location_id": {"type": "integer", "minimum": 1},
        "code": {"type": ["string", "null"], "maxLength": 64},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "parent_id": {"type": ["integer", "null"], "minimum": 1},
        "location_kind": {"type": "string", "enum": _KINDS},
        "sort_order": {"type": "integer"},
        "is_active": {"type": "boolean"},
        "notes": {"type": ["string", "null"], "maxLength": 4000},
    },
    ["warehouse_id", "location_id"],
)
_LOC_ID = mcp_schema(
    {
        "warehouse_id": {"type": "integer", "minimum": 1},
        "location_id": {"type": "integer", "minimum": 1},
    },
    ["warehouse_id", "location_id"],
)
CREATE_WAREHOUSE_PLACEMENT_SCHEMA = mcp_schema(
    {
        "warehouse_id": {"type": "integer", "minimum": 1},
        "product_id": {"type": "integer", "minimum": 1},
        "warehouse_location_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "number"},
        "notes": {"type": ["string", "null"], "maxLength": 4000},
    },
    ["warehouse_id", "product_id", "warehouse_location_id"],
)
_PLACE_UPDATE = mcp_schema(
    {
        "warehouse_id": {"type": "integer", "minimum": 1},
        "placement_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "number"},
        "notes": {"type": ["string", "null"], "maxLength": 4000},
        "warehouse_location_id": {"type": "integer", "minimum": 1},
    },
    ["warehouse_id", "placement_id"],
)
_PLACE_ID = mcp_schema(
    {
        "warehouse_id": {"type": "integer", "minimum": 1},
        "placement_id": {"type": "integer", "minimum": 1},
    },
    ["warehouse_id", "placement_id"],
)
_WH_KEYS = ("code", "name", "description", "warehouse_keeper", "phone", "address", "postal_code", "is_default")
_LOC_KEYS = ("code", "name", "parent_id", "location_kind", "sort_order", "is_active", "notes", "auto_generate_code")
_PLACE_KEYS = ("product_id", "warehouse_location_id", "quantity", "notes")


def get_warehouse_handler(args, context):
    from app.services.warehouse_service import get_warehouse

    data = mcp_run(get_warehouse, mcp_db(context), mcp_bid(context), int(args["warehouse_id"]))
    if not data:
        raise ValueError("انبار یافت نشد")
    return mcp_jsonable(data)


def create_warehouse_handler(args, context):
    from adapters.api.v1.schema_models.warehouse import WarehouseCreateRequest
    from app.services.warehouse_service import create_warehouse

    payload = WarehouseCreateRequest(**{k: v for k, v in args.items() if k in _WH_KEYS})
    result = mcp_run(create_warehouse, mcp_db(context), mcp_bid(context), payload)
    mcp_db(context).commit()
    return mcp_jsonable(mcp_unwrap(result))


def update_warehouse_handler(args, context):
    from adapters.api.v1.schema_models.warehouse import WarehouseUpdateRequest
    from app.services.warehouse_service import update_warehouse

    payload = WarehouseUpdateRequest(**{k: v for k, v in args.items() if k in _WH_KEYS and k in args})
    result = mcp_run(update_warehouse, mcp_db(context), mcp_bid(context), int(args["warehouse_id"]), payload)
    if not result:
        raise ValueError("انبار یافت نشد")
    mcp_db(context).commit()
    return mcp_jsonable(mcp_unwrap(result))


def delete_warehouse_handler(args, context):
    from app.services.warehouse_service import delete_warehouse

    ok = mcp_run(delete_warehouse, mcp_db(context), mcp_bid(context), int(args["warehouse_id"]))
    if not ok:
        raise ValueError("انبار یافت نشد یا در اسناد استفاده شده و قابل حذف نیست")
    return {"deleted": True, "id": int(args["warehouse_id"])}


def create_warehouse_location_handler(args, context):
    from app.services.warehouse_location_service import create_location

    payload = {k: v for k, v in args.items() if k in _LOC_KEYS}
    if not payload.get("auto_generate_code") and not str(payload.get("code") or "").strip():
        raise ValueError("کد محل الزامی است یا گزینهٔ تولید خودکار را فعال کنید")
    return mcp_jsonable(
        mcp_run(create_location, mcp_db(context), mcp_bid(context), int(args["warehouse_id"]), payload)
    )


def update_warehouse_location_handler(args, context):
    from app.services.warehouse_location_service import update_location

    payload = {k: v for k, v in args.items() if k in _LOC_KEYS and k != "auto_generate_code"}
    result = mcp_run(
        update_location,
        mcp_db(context),
        mcp_bid(context),
        int(args["warehouse_id"]),
        int(args["location_id"]),
        payload,
    )
    if not result:
        raise ValueError("محل انبار یافت نشد")
    return mcp_jsonable(result)


def delete_warehouse_location_handler(args, context):
    from app.services.warehouse_location_service import delete_location

    ok = mcp_run(delete_location, mcp_db(context), mcp_bid(context), int(args["warehouse_id"]), int(args["location_id"]))
    if not ok:
        raise ValueError("محل انبار یافت نشد")
    return {"deleted": True, "id": int(args["location_id"])}


def create_warehouse_placement_handler(args, context):
    from app.services.warehouse_location_service import create_placement

    payload = {k: v for k, v in args.items() if k in _PLACE_KEYS}
    return mcp_jsonable(
        mcp_run(create_placement, mcp_db(context), mcp_bid(context), int(args["warehouse_id"]), payload)
    )


def update_warehouse_placement_handler(args, context):
    from app.services.warehouse_location_service import update_placement

    payload = {k: v for k, v in args.items() if k in ("quantity", "notes", "warehouse_location_id")}
    result = mcp_run(
        update_placement,
        mcp_db(context),
        mcp_bid(context),
        int(args["warehouse_id"]),
        int(args["placement_id"]),
        payload,
    )
    if not result:
        raise ValueError("چیدمان یافت نشد")
    return mcp_jsonable(result)


def delete_warehouse_placement_handler(args, context):
    from app.services.warehouse_location_service import delete_placement

    ok = mcp_run(delete_placement, mcp_db(context), mcp_bid(context), int(args["warehouse_id"]), int(args["placement_id"]))
    if not ok:
        raise ValueError("چیدمان یافت نشد")
    return {"deleted": True, "id": int(args["placement_id"])}


def reconcile_warehouse_placements_handler(args, context):
    from app.services.warehouse_placement_sync import placement_reconciliation_for_warehouse

    return mcp_jsonable(
        mcp_run(placement_reconciliation_for_warehouse, mcp_db(context), mcp_bid(context), int(args["warehouse_id"]))
    )


def register_mcp_warehouse_master_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_warehouse",
        description="جزئیات یک انبار متعلق به کسب‌وکار متصل.",
        parameters_schema=_WH_ID,
        handler=get_warehouse_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.view"],
        category="warehouse",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_warehouse",
        description="ثبت انبار جدید در کسب‌وکار متصل. اگر کد نیاید خودکار ساخته می‌شود.",
        parameters_schema=CREATE_WAREHOUSE_SCHEMA,
        handler=create_warehouse_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_warehouse",
        description="ویرایش انبار متعلق به کسب‌وکار متصل.",
        parameters_schema=UPDATE_WAREHOUSE_SCHEMA,
        handler=update_warehouse_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_warehouse",
        description="حذف انباری که در حواله استفاده نشده. نیازمند تأیید.",
        parameters_schema=_WH_ID,
        handler=delete_warehouse_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.delete"],
        category="warehouse",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="create_warehouse_location",
        description="ثبت محل چیدمان (زون/قفسه/بین) داخل انبار کسب‌وکار متصل.",
        parameters_schema=CREATE_WAREHOUSE_LOCATION_SCHEMA,
        handler=create_warehouse_location_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_warehouse_location",
        description="ویرایش محل چیدمان متعلق به همان انبار و کسب‌وکار متصل.",
        parameters_schema=_LOC_UPDATE,
        handler=update_warehouse_location_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_warehouse_location",
        description="حذف محل چیدمان انبار کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_LOC_ID,
        handler=delete_warehouse_location_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.delete"],
        category="warehouse",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="create_warehouse_placement",
        description="ثبت چیدمان کالا در محل انبار کسب‌وکار متصل.",
        parameters_schema=CREATE_WAREHOUSE_PLACEMENT_SCHEMA,
        handler=create_warehouse_placement_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_warehouse_placement",
        description="ویرایش مقدار یا محل چیدمان کالا در انبار کسب‌وکار متصل.",
        parameters_schema=_PLACE_UPDATE,
        handler=update_warehouse_placement_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.write"],
        category="warehouse",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_warehouse_placement",
        description="حذف چیدمان کالا در انبار کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=_PLACE_ID,
        handler=delete_warehouse_placement_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.delete"],
        category="warehouse",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="reconcile_warehouse_placements",
        description="گزارش مغایرت چیدمان محل‌ها با موجودی انبار کسب‌وکار متصل.",
        parameters_schema=_WH_ID,
        handler=reconcile_warehouse_placements_handler,
        allowed_roles=roles,
        required_permissions=["warehouses.view"],
        category="warehouse",
        is_readonly=True,
    ))
