"""MCP tools for WooCommerce and Basalam settings/sync. Tokens are never accepted or returned."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
WOO_UPDATE = mcp_schema(
    {
        "store_base_url": {"type": "string", "maxLength": 400},
        "push_stock_to_wc_on_warehouse_post": {"type": "boolean"},
    }
)
IDS = mcp_schema({"ids": {"type": "array", "maxItems": 100, "items": {"type": "integer", "minimum": 1}}})
WOO_PRODUCT = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1, "description": "شناسه محصول ووکامرس"},
        "variation_id": {"type": "integer", "minimum": 1},
    },
    ["product_id"],
)
BASALAM_UPDATE = mcp_schema(
    {
        "enabled": {"type": "boolean"},
        "api_base_url": {"type": "string", "maxLength": 400},
        "default_basalam_vendor_id": {"type": ["integer", "null"]},
        "default_basalam_category_id": {"type": ["integer", "null"]},
        "default_basalam_stock": {"type": "integer", "minimum": 0},
        "order_sync_enabled": {"type": "boolean"},
        "chat_enabled": {"type": "boolean"},
        "payment_sync_enabled": {"type": "boolean"},
        "create_sales_invoice_on_sync": {"type": "boolean"},
        "invoice_type_on_sync": {"type": "string", "maxLength": 40},
        "product_conflict_price_strategy": {"type": "string", "enum": ["local_wins", "remote_wins", "manual_review"]},
        "product_conflict_stock_strategy": {"type": "string", "enum": ["local_wins", "remote_wins", "manual_review"]},
        "product_variant_strategy": {"type": "string", "enum": ["manual_review", "local_wins", "remote_wins"]},
        "basalam_monetary_unit": {"type": "string", "enum": ["rial", "toman"]},
        "auto_create_person_mode": {"type": "string", "maxLength": 40},
        "auto_create_product_mode": {"type": "string", "maxLength": 40},
        "default_order_tag": {"type": "string", "maxLength": 40},
    }
)
SYNC_PAYLOAD = mcp_schema({"payload": {"type": "object", "additionalProperties": True}})
RESOLVE = mcp_schema(
    {
        "conflict_ids": {"type": "array", "minItems": 1, "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
        "resolution": {"type": "string", "enum": ["local_wins", "remote_wins"]},
    },
    ["conflict_ids", "resolution"],
)
_SECRET_KEYS = ("api_key", "api_refresh_token", "webhook_secret", "bridge_token")


def _mask(data):
    if not isinstance(data, dict):
        return data
    out = dict(data)
    for key in _SECRET_KEYS:
        if key in out and out[key]:
            out[key] = "***"
            out[f"{key}_set"] = True
        elif key in out:
            out[f"{key}_set"] = False
    return out


def get_woocommerce_settings_handler(args, context):
    from app.services.woocommerce_integration_service import get_settings

    return mcp_jsonable(_mask(mcp_run(get_settings, mcp_db(context), mcp_bid(context))))


def update_woocommerce_settings_handler(args, context):
    from app.services.woocommerce_integration_service import update_settings

    payload = {k: args[k] for k in ("store_base_url", "push_stock_to_wc_on_warehouse_post") if k in args}
    return mcp_jsonable(_mask(mcp_run(update_settings, mcp_db(context), mcp_bid(context), payload)))


def test_woocommerce_bridge_handler(args, context):
    from app.services.woocommerce_integration_service import test_bridge

    return mcp_jsonable(mcp_run(test_bridge, mcp_db(context), mcp_bid(context)))


def get_woocommerce_sync_stats_handler(args, context):
    from app.services.woocommerce_integration_service import control_sync_stats

    return mcp_jsonable(mcp_run(control_sync_stats, mcp_db(context), mcp_bid(context)))


def sync_woocommerce_orders_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_sync_orders

    return mcp_jsonable(mcp_run(post_control_sync_orders, mcp_db(context), mcp_bid(context), args.get("ids") or []))


def sync_woocommerce_products_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_sync_products

    return mcp_jsonable(mcp_run(post_control_sync_products, mcp_db(context), mcp_bid(context), args.get("ids") or []))


def sync_woocommerce_customers_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_sync_customers

    return mcp_jsonable(mcp_run(post_control_sync_customers, mcp_db(context), mcp_bid(context), args.get("ids") or []))


def sync_woocommerce_product_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_sync_product

    return mcp_jsonable(
        mcp_run(
            post_control_sync_product,
            mcp_db(context),
            mcp_bid(context),
            product_id=int(args["product_id"]),
            variation_id=args.get("variation_id"),
        )
    )


def get_woocommerce_stock_conflicts_handler(args, context):
    from app.services.woocommerce_integration_service import control_stock_conflicts

    return mcp_jsonable(mcp_run(control_stock_conflicts, mcp_db(context), mcp_bid(context), limit=25))


def get_basalam_settings_handler(args, context):
    from app.services.basalam_integration_service import get_settings

    return mcp_jsonable(_mask(mcp_run(get_settings, mcp_db(context), mcp_bid(context))))


def update_basalam_settings_handler(args, context):
    from app.services.basalam_integration_service import update_settings

    payload = dict(args)
    payload.pop("api_key", None)
    payload.pop("api_refresh_token", None)
    payload.pop("webhook_secret", None)
    return mcp_jsonable(_mask(mcp_run(update_settings, mcp_db(context), mcp_bid(context), payload)))


def sync_basalam_orders_handler(args, context):
    from app.services.basalam_integration_service import manual_sync_orders

    return mcp_jsonable(
        mcp_run(manual_sync_orders, mcp_db(context), mcp_bid(context), args.get("payload") or {}, user_id=mcp_uid(context))
    )


def sync_basalam_products_handler(args, context):
    from app.services.basalam_integration_service import manual_sync_products

    return mcp_jsonable(
        mcp_run(manual_sync_products, mcp_db(context), mcp_bid(context), args.get("payload") or {}, user_id=mcp_uid(context))
    )


def publish_basalam_products_handler(args, context):
    from app.services.basalam_integration_service import publish_products_to_basalam

    return mcp_jsonable(
        mcp_run(
            publish_products_to_basalam,
            mcp_db(context),
            mcp_bid(context),
            args.get("payload") or {},
            user_id=mcp_uid(context),
        )
    )


def pull_basalam_products_handler(args, context):
    from app.services.basalam_integration_service import pull_products_from_basalam

    return mcp_jsonable(
        mcp_run(
            pull_products_from_basalam,
            mcp_db(context),
            mcp_bid(context),
            args.get("payload") or {},
            user_id=mcp_uid(context),
        )
    )


def push_basalam_products_incremental_handler(args, context):
    from app.services.basalam_integration_service import push_products_incremental

    return mcp_jsonable(
        mcp_run(
            push_products_incremental,
            mcp_db(context),
            mcp_bid(context),
            args.get("payload") or {},
            user_id=mcp_uid(context),
        )
    )


def resolve_basalam_product_conflicts_handler(args, context):
    from app.services.basalam_integration_service import resolve_product_conflicts

    return mcp_jsonable(
        mcp_run(
            resolve_product_conflicts,
            mcp_db(context),
            mcp_bid(context),
            {"conflict_ids": args["conflict_ids"], "resolution": args["resolution"]},
            user_id=mcp_uid(context),
        )
    )


def register_mcp_connector_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_woocommerce_settings",
        description="تنظیمات اتصال ووکامرس کسب‌وکار با توکن پل ماسک‌شده. افزونه باید فعال باشد.",
        parameters_schema=EMPTY,
        handler=get_woocommerce_settings_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="update_woocommerce_settings",
        description="ذخیره آدرس فروشگاه و پوش موجودی به ووکامرس. توکن پل از MCP پذیرفته نمی‌شود. نیازمند تأیید.",
        parameters_schema=WOO_UPDATE,
        handler=update_woocommerce_settings_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.manage"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="test_woocommerce_bridge",
        description="آزمون اتصال پل وردپرس ووکامرس کسب‌وکار متصل.",
        parameters_schema=EMPTY,
        handler=test_woocommerce_bridge_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.manage"],
        category="integration",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="get_woocommerce_sync_stats",
        description="آمار همگام‌سازی سفارش/کالا/مشتری ووکامرس.",
        parameters_schema=EMPTY,
        handler=get_woocommerce_sync_stats_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="sync_woocommerce_orders",
        description="همگام‌سازی سفارش‌های ووکامرس با شناسه‌های داده‌شده (خالی = طبق تنظیم پل). نیازمند تأیید.",
        parameters_schema=IDS,
        handler=sync_woocommerce_orders_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="sync_woocommerce_products",
        description="همگام‌سازی کالاهای ووکامرس. نیازمند تأیید.",
        parameters_schema=IDS,
        handler=sync_woocommerce_products_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="sync_woocommerce_customers",
        description="همگام‌سازی مشتریان ووکامرس. نیازمند تأیید.",
        parameters_schema=IDS,
        handler=sync_woocommerce_customers_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="sync_woocommerce_product",
        description="همگام‌سازی یک محصول/تنوع ووکامرس با شناسه فروشگاه. نیازمند تأیید.",
        parameters_schema=WOO_PRODUCT,
        handler=sync_woocommerce_product_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.sync"],
        category="integration",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="get_woocommerce_stock_conflicts",
        description="تعارض موجودی بین حسابیکس و ووکامرس.",
        parameters_schema=EMPTY,
        handler=get_woocommerce_stock_conflicts_handler,
        allowed_roles=roles,
        required_permissions=["woocommerce.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="get_basalam_settings",
        description="تنظیمات باسلام کسب‌وکار با کلید API و webhook ماسک‌شده.",
        parameters_schema=EMPTY,
        handler=get_basalam_settings_handler,
        allowed_roles=roles,
        required_permissions=["basalam.view"],
        category="integration",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="update_basalam_settings",
        description="ویرایش پرچم‌ها و استراتژی همگام باسلام. توکن API از MCP پذیرفته نمی‌شود. نیازمند تأیید.",
        parameters_schema=BASALAM_UPDATE,
        handler=update_basalam_settings_handler,
        allowed_roles=roles,
        required_permissions=["basalam.manage"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="sync_basalam_orders",
        description="همگام‌سازی دستی سفارش‌های باسلام. نیازمند تأیید.",
        parameters_schema=SYNC_PAYLOAD,
        handler=sync_basalam_orders_handler,
        allowed_roles=roles,
        required_permissions=["basalam.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="sync_basalam_products",
        description="همگام‌سازی دستی کالاهای باسلام. نیازمند تأیید.",
        parameters_schema=SYNC_PAYLOAD,
        handler=sync_basalam_products_handler,
        allowed_roles=roles,
        required_permissions=["basalam.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="publish_basalam_products",
        description="انتشار کالاهای حسابیکس در باسلام. نیازمند تأیید.",
        parameters_schema=SYNC_PAYLOAD,
        handler=publish_basalam_products_handler,
        allowed_roles=roles,
        required_permissions=["basalam.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="pull_basalam_products",
        description="دریافت کالا از باسلام به کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=SYNC_PAYLOAD,
        handler=pull_basalam_products_handler,
        allowed_roles=roles,
        required_permissions=["basalam.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="push_basalam_products_incremental",
        description="پوش افزایشی کالا به باسلام. نیازمند تأیید.",
        parameters_schema=SYNC_PAYLOAD,
        handler=push_basalam_products_incremental_handler,
        allowed_roles=roles,
        required_permissions=["basalam.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="resolve_basalam_product_conflicts",
        description="حل تعارض کالای باسلام با استراتژی local_wins یا remote_wins. نیازمند تأیید.",
        parameters_schema=RESOLVE,
        handler=resolve_basalam_product_conflicts_handler,
        allowed_roles=roles,
        required_permissions=["basalam.sync"],
        category="integration",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
