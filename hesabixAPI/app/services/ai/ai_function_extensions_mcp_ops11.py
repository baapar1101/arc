"""MCP leftovers: business dashboard layout, widgets, quick links, and menu preferences."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
BP = mcp_schema({"breakpoint": {"type": "string", "enum": ["xs", "sm", "md", "lg", "xl"]}})
LAYOUT_SAVE = mcp_schema(
    {
        "breakpoint": {"type": "string", "enum": ["xs", "sm", "md", "lg", "xl"]},
        "items": {"type": "array", "minItems": 1, "maxItems": 40, "items": {"type": "object"}},
    },
    ["breakpoint", "items"],
)
WIDGET_DATA = mcp_schema(
    {
        "widget_keys": {"type": "array", "minItems": 1, "maxItems": 20, "items": {"type": "string"}},
        "filters": {"type": "object"},
        "calendar_type": {"type": "string", "enum": ["gregorian", "jalali"]},
    },
    ["widget_keys"],
)
QL_SAVE = mcp_schema({"items": {"type": "array", "maxItems": 20, "items": {"type": "object"}}}, ["items"])
MENU_SAVE = mcp_schema({"preferences": {"type": "object"}}, ["preferences"])


def list_dashboard_widget_definitions_handler(args, context):
    from app.services.dashboard_widgets_service import get_widget_definitions

    return mcp_jsonable(mcp_run(get_widget_definitions, mcp_db(context), mcp_bid(context), mcp_uid(context), context.get("user_context")))


def get_dashboard_layout_handler(args, context):
    from app.services.dashboard_widgets_service import get_dashboard_layout_profile

    bp = str(args.get("breakpoint") or "lg")
    return mcp_jsonable(mcp_run(get_dashboard_layout_profile, mcp_db(context), mcp_bid(context), mcp_uid(context), bp))


def save_dashboard_layout_handler(args, context):
    from app.services.dashboard_widgets_service import save_dashboard_layout_profile

    out = mcp_run(
        save_dashboard_layout_profile,
        mcp_db(context),
        mcp_bid(context),
        mcp_uid(context),
        str(args.get("breakpoint") or "lg"),
        list(args.get("items") or []),
    )
    mcp_commit(context)
    return mcp_jsonable(out)


def get_default_dashboard_layout_handler(args, context):
    from app.services.dashboard_widgets_service import get_business_default_layout

    data = mcp_run(get_business_default_layout, mcp_db(context), mcp_bid(context), str(args.get("breakpoint") or "lg"))
    return mcp_jsonable(data or {"items": None})


def save_default_dashboard_layout_handler(args, context):
    from app.services.dashboard_widgets_service import save_business_default_layout

    out = mcp_run(
        save_business_default_layout,
        mcp_db(context),
        mcp_bid(context),
        str(args.get("breakpoint") or "lg"),
        list(args.get("items") or []),
    )
    mcp_commit(context)
    return mcp_jsonable(out)


def get_dashboard_widgets_data_handler(args, context):
    from app.services.dashboard_widgets_service import get_widgets_batch_data

    keys = [str(k) for k in (args.get("widget_keys") or [])][:20]
    filters = args.get("filters") if isinstance(args.get("filters"), dict) else {}
    cal = str(args.get("calendar_type") or "gregorian")
    return mcp_jsonable(
        mcp_run(
            get_widgets_batch_data,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            keys,
            filters,
            cal,
            context.get("user_context"),
        )
    )


def list_dashboard_quick_link_presets_handler(args, context):
    from app.services.business_quick_links_service import get_quick_link_presets_catalog

    return mcp_jsonable(mcp_run(get_quick_link_presets_catalog, context.get("user_context")))


def get_dashboard_quick_links_handler(args, context):
    from app.services.business_quick_links_service import get_or_create_quick_links

    return mcp_jsonable(mcp_run(get_or_create_quick_links, mcp_db(context), mcp_bid(context), mcp_uid(context)))


def save_dashboard_quick_links_handler(args, context):
    from app.services.business_quick_links_service import save_quick_links

    out = mcp_run(save_quick_links, mcp_db(context), mcp_bid(context), mcp_uid(context), list(args.get("items") or []), context.get("user_context"))
    mcp_commit(context)
    return mcp_jsonable(out)


def get_business_menu_preferences_handler(args, context):
    from app.services.business_menu_preferences_service import get_or_create_menu_preferences

    return mcp_jsonable(mcp_run(get_or_create_menu_preferences, mcp_db(context), mcp_bid(context), mcp_uid(context)))


def save_business_menu_preferences_handler(args, context):
    from app.services.business_menu_preferences_service import save_menu_preferences

    out = mcp_run(save_menu_preferences, mcp_db(context), mcp_bid(context), mcp_uid(context), args.get("preferences") or {})
    mcp_commit(context)
    return mcp_jsonable(out)


def register_mcp_ops11_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="list_dashboard_widget_definitions", description="کاتالوگ ویجت‌های مجاز داشبورد کسب‌وکار برای کاربر جاری.", parameters_schema=EMPTY, handler=list_dashboard_widget_definitions_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="get_dashboard_layout", description="چیدمان ویجت داشبورد کاربر برای یک breakpoint.", parameters_schema=BP, handler=get_dashboard_layout_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="save_dashboard_layout", description="ذخیره چیدمان ویجت داشبورد کاربر. نیازمند تأیید.", parameters_schema=LAYOUT_SAVE, handler=save_dashboard_layout_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="get_default_dashboard_layout", description="چیدمان پیش‌فرض داشبورد کسب‌وکار.", parameters_schema=BP, handler=get_default_dashboard_layout_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="save_default_dashboard_layout", description="ذخیره چیدمان پیش‌فرض داشبورد کسب‌وکار. نیازمند تأیید.", parameters_schema=LAYOUT_SAVE, handler=save_default_dashboard_layout_handler, allowed_roles=roles, required_permissions=["settings.business"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_dashboard_widgets_data", description="داده دسته‌ای ویجت‌های داشبورد برای کلیدهای درخواستی.", parameters_schema=WIDGET_DATA, handler=get_dashboard_widgets_data_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_dashboard_quick_link_presets", description="کاتالوگ میانبرهای آماده داشبورد بر اساس مجوز کاربر.", parameters_schema=EMPTY, handler=list_dashboard_quick_link_presets_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="get_dashboard_quick_links", description="میانبرهای داشبورد کاربر جاری.", parameters_schema=EMPTY, handler=get_dashboard_quick_links_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="save_dashboard_quick_links", description="ذخیره میانبرهای داشبورد کاربر. نیازمند تأیید.", parameters_schema=QL_SAVE, handler=save_dashboard_quick_links_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="get_business_menu_preferences", description="ترتیب و پین منوی کسب‌وکار برای کاربر جاری.", parameters_schema=EMPTY, handler=get_business_menu_preferences_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="save_business_menu_preferences", description="ذخیره ترجیحات منوی کسب‌وکار. نیازمند تأیید.", parameters_schema=MENU_SAVE, handler=save_business_menu_preferences_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", requires_approval=True, risk_level="low", is_readonly=False))
