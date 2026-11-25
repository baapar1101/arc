"""MCP leftovers: club RFM person-ids, club points balance, bulk price sheet JSON."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema

RFM_IDS = mcp_schema(
    {
        "segment_label": {"type": "string", "maxLength": 80},
        "q": {"type": "string", "maxLength": 80},
        "take": {"type": "integer", "minimum": 1, "maximum": 200},
    }
)
PERSON_ID = mcp_schema({"person_id": {"type": "integer", "minimum": 1}}, ["person_id"])
SHEET_ITEMS = mcp_schema(
    {
        "product_ids": {
            "type": "array",
            "minItems": 1,
            "maxItems": 50,
            "items": {"type": "integer", "minimum": 1},
        },
        "price_list_ids": {
            "type": "array",
            "minItems": 1,
            "maxItems": 12,
            "items": {"type": "integer", "minimum": 1},
        },
    },
    ["product_ids", "price_list_ids"],
)
SHEET_APPLY = mcp_schema(
    {
        "items": {
            "type": "array",
            "minItems": 1,
            "maxItems": 50,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "product_id": {"type": "integer", "minimum": 1},
                    "base_sales_price": {"type": "number", "minimum": 0},
                    "base_purchase_price": {"type": "number", "minimum": 0},
                    "clear_base_sales_price": {"type": "boolean"},
                    "clear_base_purchase_price": {"type": "boolean"},
                    "price_item_updates": {
                        "type": "array",
                        "maxItems": 20,
                        "items": {
                            "type": "object",
                            "additionalProperties": False,
                            "properties": {
                                "price_item_id": {"type": "integer", "minimum": 1},
                                "price": {"type": "number", "minimum": 0},
                            },
                            "required": ["price_item_id", "price"],
                        },
                    },
                },
                "required": ["product_id"],
            },
        }
    },
    ["items"],
)


def _club(context) -> None:
    from app.core.customer_club_plugin_dependency import check_customer_club_plugin_active

    if not check_customer_club_plugin_active(mcp_db(context), mcp_bid(context)):
        raise ValueError("افزونه باشگاه مشتریان برای این کسب‌وکار فعال نیست")


def list_customer_club_rfm_person_ids_handler(args, context):
    from app.services.customer_club_analytics_service import list_rfm_person_ids

    _club(context)
    take = min(int(args.get("take") or 100), 200)
    return mcp_jsonable(
        mcp_run(
            list_rfm_person_ids,
            mcp_db(context),
            mcp_bid(context),
            segment_label=args.get("segment_label"),
            search=args.get("q"),
            limit=take,
        )
    )


def get_customer_club_person_balance_handler(args, context):
    from app.services.customer_club_service import get_person_balance

    _club(context)
    return mcp_jsonable(
        mcp_run(get_person_balance, mcp_db(context), mcp_bid(context), int(args["person_id"]))
    )


def list_bulk_product_prices_sheet_items_handler(args, context):
    from adapters.api.v1.schema_models.product import BulkProductPriceSheetItemsRequest
    from app.services.bulk_product_prices_sheet_service import list_bulk_price_sheet_items

    payload = BulkProductPriceSheetItemsRequest.model_validate(
        {
            "product_ids": [int(x) for x in args["product_ids"]][:50],
            "price_list_ids": [int(x) for x in args["price_list_ids"]][:12],
        }
    )
    return mcp_jsonable(mcp_run(list_bulk_price_sheet_items, mcp_db(context), mcp_bid(context), payload))


def apply_bulk_product_prices_sheet_handler(args, context):
    from adapters.api.v1.schema_models.product import BulkProductPriceSheetApplyRequest
    from app.services.bulk_product_prices_sheet_service import apply_bulk_product_price_sheet

    items = list(args.get("items") or [])[:50]
    payload = BulkProductPriceSheetApplyRequest.model_validate({"items": items})
    return mcp_jsonable(mcp_run(apply_bulk_product_price_sheet, mcp_db(context), mcp_bid(context), payload))


def register_mcp_ops18_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(
        AIFunction(
            name="list_customer_club_rfm_person_ids",
            description="شناسه اشخاص یک سگمنت RFM باشگاه مشتریان کسب‌وکار متصل؛ حداکثر ۲۰۰.",
            parameters_schema=RFM_IDS,
            handler=list_customer_club_rfm_person_ids_handler,
            allowed_roles=roles,
            required_permissions=["customer_club.view"],
            category="customer_club",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="get_customer_club_person_balance",
            description="مانده امتیاز باشگاه مشتریان یک شخص متعلق به کسب‌وکار متصل؛ با امتیاز نرمال RFM اگر فعال باشد.",
            parameters_schema=PERSON_ID,
            handler=get_customer_club_person_balance_handler,
            allowed_roles=roles,
            required_permissions=["customer_club.view"],
            category="customer_club",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="list_bulk_product_prices_sheet_items",
            description="ردیف‌های لیست قیمت برای حداکثر ۵۰ کالا و ۱۲ لیست؛ ورودی نمای ویرایش گسترده قیمت.",
            parameters_schema=SHEET_ITEMS,
            handler=list_bulk_product_prices_sheet_items_handler,
            allowed_roles=roles,
            required_permissions=["products.read"],
            category="products",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="apply_bulk_product_prices_sheet",
            description="اعمال دسته‌ای قیمت پایه و سلول‌های لیست قیمت حداکثر ۵۰ ردیف. برگشت‌ناپذیر. نیازمند تأیید.",
            parameters_schema=SHEET_APPLY,
            handler=apply_bulk_product_prices_sheet_handler,
            allowed_roles=roles,
            required_permissions=["products.write"],
            category="products",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )
