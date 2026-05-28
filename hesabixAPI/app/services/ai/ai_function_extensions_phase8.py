"""
فاز ۸ AI — بازار افزونه، باشگاه مشتریان (write)، باسلام (read گسترده).
"""
from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


def register_phase8_business_functions(registry: "AIFunctionRegistry") -> None:
    # --- Marketplace ---
    def list_marketplace_plugins_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.marketplace_service import list_plugins

        db = context["db"]
        items = list_plugins(db)
        return {"items": items, "total": len(items)}

    registry.register(
        AIFunction(
            name="list_marketplace_plugins",
            description="کاتالوگ افزونه‌های قابل خرید در بازار افزونه.",
            parameters_schema={"type": "object", "properties": {}},
            handler=list_marketplace_plugins_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["marketplace.view"],
            category="marketplace",
            is_readonly=True,
        )
    )

    def list_business_plugins_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.marketplace_service import list_business_plugins

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        items = list_business_plugins(db, business_id)
        return {"items": items, "total": len(items)}

    registry.register(
        AIFunction(
            name="list_business_plugins",
            description="افزونه‌های فعال/غیرفعال این کسب‌وکار (باشگاه مشتریان، باسلام، …).",
            parameters_schema={"type": "object", "properties": {}},
            handler=list_business_plugins_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["marketplace.view"],
            category="marketplace",
            is_readonly=True,
        )
    )

    # --- Basalam read ---
    def get_basalam_overview_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.basalam_reports_service import get_overview

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        return get_overview(db, business_id, chart_days=int(args.get("chart_days") or 90))

    registry.register(
        AIFunction(
            name="get_basalam_overview",
            description="خلاصه وضعیت یکپارچه‌سازی باسلام (سفارش، تعارض، dead-letter).",
            parameters_schema={
                "type": "object",
                "properties": {"chart_days": {"type": "integer"}},
            },
            handler=get_basalam_overview_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["basalam.view"],
            category="integration",
            is_readonly=True,
        )
    )

    def list_basalam_dead_letter_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.basalam_reports_service import list_dead_letter_for_report

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        limit = min(int(args.get("take") or 50), 200)
        skip = int(args.get("skip") or 0)
        return list_dead_letter_for_report(
            db,
            business_id,
            item_type=args.get("item_type"),
            limit=limit,
            offset=skip,
        )

    registry.register(
        AIFunction(
            name="list_basalam_dead_letter",
            description="صف خطاهای همگام‌سازی باسلام (dead-letter).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "item_type": {"type": "string"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
            },
            handler=list_basalam_dead_letter_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["basalam.view"],
            category="integration",
            is_readonly=True,
        )
    )

    # --- Customer club write ---
    def adjust_customer_club_points_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.customer_club_service import manual_adjustment

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        user_id = context["user_context"].get_user_id()
        desc = str(args.get("description") or "").strip()
        if not desc:
            raise ValueError("description الزامی است")
        return manual_adjustment(
            db,
            business_id,
            user_id,
            int(args["person_id"]),
            Decimal(str(args["delta_points"])),
            desc,
        )

    registry.register(
        AIFunction(
            name="adjust_customer_club_points",
            description="تنظیم دستی امتیاز باشگاه مشتریان برای یک شخص. نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "person_id": {"type": "integer"},
                    "delta_points": {"type": "number"},
                    "description": {"type": "string"},
                },
                "required": ["person_id", "delta_points", "description"],
            },
            handler=adjust_customer_club_points_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["customer_club.write"],
            category="customer_club",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    def recalculate_customer_club_rfm_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.customer_club_analytics_service import recalculate_rfm_snapshots

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        return recalculate_rfm_snapshots(db, business_id)

    registry.register(
        AIFunction(
            name="recalculate_customer_club_rfm",
            description="محاسبهٔ مجدد تحلیل RFM باشگاه مشتریان. نیاز به تأیید.",
            parameters_schema={"type": "object", "properties": {}},
            handler=recalculate_customer_club_rfm_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["customer_club.write"],
            category="customer_club",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    def update_customer_club_settings_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.customer_club_service import update_settings

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        payload = dict(args.get("settings") or {})
        if not payload:
            raise ValueError("settings (object) الزامی است")
        return update_settings(db, business_id, payload)

    registry.register(
        AIFunction(
            name="update_customer_club_settings",
            description="به‌روزرسانی تنظیمات باشگاه مشتریان (فقط فیلدهای ارسالی). نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "settings": {"type": "object", "description": "enabled, earn_mode, …"},
                },
                "required": ["settings"],
            },
            handler=update_customer_club_settings_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["customer_club.write"],
            category="customer_club",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )
