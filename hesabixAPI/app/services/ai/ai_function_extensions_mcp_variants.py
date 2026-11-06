"""MCP tools for product variant dimensions, SKUs, balances, and inventory enablement."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

PRODUCT_ID = mcp_schema({"product_id": {"type": "integer", "minimum": 1}}, ["product_id"])
BALANCES_SCHEMA = mcp_schema(
    {"product_id": {"type": "integer", "minimum": 1}, "warehouse_id": {"type": "integer", "minimum": 1}},
    ["product_id"],
)
BARCODE_SCHEMA = mcp_schema({"token": {"type": "string", "minLength": 1, "maxLength": 128}}, ["token"])
_DIM = {
    "type": "object",
    "additionalProperties": False,
    "required": ["attribute_id"],
    "properties": {
        "attribute_id": {"type": "integer", "minimum": 1},
        "is_required": {"type": "boolean"},
        "sort_order": {"type": "integer", "minimum": 0},
    },
}
REPLACE_DIM_SCHEMA = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "dimensions": {"type": "array", "maxItems": 8, "items": _DIM},
    },
    ["product_id", "dimensions"],
)
_ATTR = {
    "type": "object",
    "additionalProperties": False,
    "required": ["attribute_id", "option_id"],
    "properties": {
        "attribute_id": {"type": "integer", "minimum": 1},
        "option_id": {"type": "integer", "minimum": 1},
    },
}
CREATE_SCHEMA = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "attribute_values": {"type": "array", "minItems": 1, "maxItems": 8, "items": _ATTR},
        "code": {"type": ["string", "null"], "maxLength": 64},
        "barcode": {"type": ["string", "null"], "maxLength": 128},
        "display_title": {"type": ["string", "null"], "maxLength": 255},
        "is_active": {"type": "boolean"},
        "sales_price": {"type": ["string", "null"]},
        "purchase_price": {"type": ["string", "null"]},
    },
    ["product_id", "attribute_values"],
)
UPDATE_SCHEMA = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "variant_id": {"type": "integer", "minimum": 1},
        "code": {"type": ["string", "null"], "maxLength": 64},
        "barcode": {"type": ["string", "null"], "maxLength": 128},
        "display_title": {"type": ["string", "null"], "maxLength": 255},
        "is_active": {"type": "boolean"},
        "sales_price": {"type": ["string", "null"]},
        "purchase_price": {"type": ["string", "null"]},
        "row_version": {"type": "integer"},
        "attribute_values": {"type": "array", "maxItems": 8, "items": _ATTR},
    },
    ["product_id", "variant_id"],
)
DEACTIVATE_SCHEMA = mcp_schema(
    {"product_id": {"type": "integer", "minimum": 1}, "variant_id": {"type": "integer", "minimum": 1}},
    ["product_id", "variant_id"],
)
ENABLE_SCHEMA = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "warehouse_id": {"type": "integer", "minimum": 1},
        "splits": {
            "type": "array",
            "maxItems": 200,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["variant_id", "quantity"],
                "properties": {
                    "variant_id": {"type": "integer", "minimum": 1},
                    "quantity": {"type": "string"},
                },
            },
        },
        "document_date": {"type": ["string", "null"]},
    },
    ["product_id", "warehouse_id"],
)


def list_product_variant_dimensions_handler(args, context):
    from app.services.product_variant_service import list_dimensions, _serialize_dimension

    rows = mcp_run(list_dimensions, mcp_db(context), mcp_bid(context), int(args["product_id"]))
    return mcp_jsonable([_serialize_dimension(row) for row in rows])


def replace_product_variant_dimensions_handler(args, context):
    from app.services.product_variant_service import replace_dimensions

    data = mcp_jsonable(
        mcp_run(replace_dimensions, mcp_db(context), mcp_bid(context), int(args["product_id"]), args.get("dimensions") or [])
    )
    mcp_commit(context)
    return data


def list_product_variants_handler(args, context):
    from app.services.product_variant_service import list_variants

    return mcp_jsonable(mcp_run(list_variants, mcp_db(context), mcp_bid(context), int(args["product_id"])))


def list_product_variant_balances_handler(args, context):
    from app.services.product_variant_service import list_variant_balances

    return mcp_jsonable(
        mcp_run(
            list_variant_balances,
            mcp_db(context),
            mcp_bid(context),
            int(args["product_id"]),
            warehouse_id=args.get("warehouse_id"),
        )
    )


def create_product_variant_handler(args, context):
    from app.services.product_variant_service import create_variant

    payload = {k: v for k, v in args.items() if k != "product_id"}
    data = mcp_jsonable(mcp_run(create_variant, mcp_db(context), mcp_bid(context), int(args["product_id"]), payload))
    mcp_commit(context)
    return data


def update_product_variant_handler(args, context):
    from app.services.product_variant_service import update_variant

    payload = {k: v for k, v in args.items() if k not in {"product_id", "variant_id"}}
    data = mcp_jsonable(
        mcp_run(
            update_variant,
            mcp_db(context),
            mcp_bid(context),
            int(args["product_id"]),
            int(args["variant_id"]),
            payload,
        )
    )
    mcp_commit(context)
    return data


def deactivate_product_variant_handler(args, context):
    from app.services.product_variant_service import deactivate_variant

    data = mcp_jsonable(
        mcp_run(deactivate_variant, mcp_db(context), mcp_bid(context), int(args["product_id"]), int(args["variant_id"]))
    )
    mcp_commit(context)
    return data


def enable_product_inventory_variants_handler(args, context):
    from app.services.product_variant_enable_service import enable_inventory_variants

    payload = {k: v for k, v in args.items() if k != "product_id"}
    data = mcp_jsonable(
        mcp_run(
            enable_inventory_variants,
            mcp_db(context),
            mcp_bid(context),
            int(args["product_id"]),
            mcp_uid(context),
            payload,
        )
    )
    mcp_commit(context)
    return data


def resolve_product_barcode_handler(args, context):
    from app.services.product_variant_service import resolve_barcode_token

    return mcp_jsonable(mcp_run(resolve_barcode_token, mcp_db(context), mcp_bid(context), str(args["token"])))


def register_mcp_variant_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="list_product_variant_dimensions",
        description="ابعاد ویژگی تنوع کالای کسب‌وکار متصل.",
        parameters_schema=PRODUCT_ID,
        handler=list_product_variant_dimensions_handler,
        allowed_roles=roles,
        required_permissions=["products.view"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="replace_product_variant_dimensions",
        description="جایگزینی ابعاد تنوع کالا. پس از گردش موجودی تنوع‌دار مجاز نیست. نیازمند تأیید.",
        parameters_schema=REPLACE_DIM_SCHEMA,
        handler=replace_product_variant_dimensions_handler,
        allowed_roles=roles,
        required_permissions=["products.edit"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_product_variants",
        description="ترکیب‌های SKU تنوع یک کالا در کسب‌وکار متصل.",
        parameters_schema=PRODUCT_ID,
        handler=list_product_variants_handler,
        allowed_roles=roles,
        required_permissions=["products.view"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="list_product_variant_balances",
        description="مانده موجودی هر ترکیب تنوع کالا، اختیاری فیلتر انبار.",
        parameters_schema=BALANCES_SCHEMA,
        handler=list_product_variant_balances_handler,
        allowed_roles=roles,
        required_permissions=["products.view"],
        category="products",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_product_variant",
        description="ایجاد ترکیب تنوع کالا با مقادیر ویژگی. نیازمند تأیید.",
        parameters_schema=CREATE_SCHEMA,
        handler=create_product_variant_handler,
        allowed_roles=roles,
        required_permissions=["products.edit"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_product_variant",
        description="ویرایش کد، بارکد، قیمت یا مقادیر ویژگی یک ترکیب تنوع. نیازمند تأیید.",
        parameters_schema=UPDATE_SCHEMA,
        handler=update_product_variant_handler,
        allowed_roles=roles,
        required_permissions=["products.edit"],
        category="products",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="deactivate_product_variant",
        description="غیرفعال‌سازی ترکیب تنوع کالا. نیازمند تأیید.",
        parameters_schema=DEACTIVATE_SCHEMA,
        handler=deactivate_product_variant_handler,
        allowed_roles=roles,
        required_permissions=["products.edit"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="enable_product_inventory_variants",
        description="فعال‌سازی تفکیک موجودی تنوع با تقسیم موجودی انبار به ترکیب‌ها. حواله انبار می‌سازد. نیازمند تأیید.",
        parameters_schema=ENABLE_SCHEMA,
        handler=enable_product_inventory_variants_handler,
        allowed_roles=roles,
        required_permissions=["products.edit"],
        category="products",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="resolve_product_barcode",
        description="تطبیق بارکد با کالا یا ترکیب تنوع کسب‌وکار متصل.",
        parameters_schema=BARCODE_SCHEMA,
        handler=resolve_product_barcode_handler,
        allowed_roles=roles,
        required_permissions=["products.view"],
        category="products",
        is_readonly=True,
    ))
