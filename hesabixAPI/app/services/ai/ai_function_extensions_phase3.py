"""
ثبت functionهای AI — فاز ۳ (باشگاه مشتری، فروش سریع، یکپارچه‌سازی، اعتبار، …).
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_query_phase3_service import (
    list_customer_club_ledger,
    search_activity_logs,
    _safe_integration_call,
)
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry

_COMMON = {
    "take": {"type": "integer"},
    "skip": {"type": "integer"},
    "search": {"type": "string"},
}


def register_phase3_business_functions(registry: "AIFunctionRegistry") -> None:
    h = registry._create_handler  # noqa: SLF001

    registry.register(
        AIFunction(
            name="get_customer_club_settings",
            description="تنظیمات باشگاه مشتریان (امتیاز، RFM، …).",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=h(_club_settings),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["customer_club.view"],
            category="customer_club",
        )
    )

    registry.register(
        AIFunction(
            name="list_customer_club_tiers",
            description="سطوح باشگاه مشتریان.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=h(_club_tiers),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["customer_club.view"],
            category="customer_club",
        )
    )

    registry.register(
        AIFunction(
            name="list_customer_club_ledger",
            description="گردش امتیاز باشگاه مشتریان.",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON,
                    "person_id": {"type": "integer"},
                },
                "required": [],
            },
            handler=h(_club_ledger),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["customer_club.view"],
            category="customer_club",
        )
    )

    registry.register(
        AIFunction(
            name="get_customer_club_rfm_summary",
            description="خلاصه تحلیل RFM باشگاه مشتریان.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=h(_club_rfm_summary),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["customer_club.view"],
            category="customer_club",
        )
    )

    registry.register(
        AIFunction(
            name="search_customer_club_rfm_persons",
            description="لیست مشتریان با امتیاز RFM و سگمنت.",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON,
                    "segment_label": {"type": "string"},
                    "sort": {"type": "string", "description": "monetary_total, recency_days, …"},
                    "sort_dir": {"type": "string", "enum": ["asc", "desc"]},
                },
                "required": [],
            },
            handler=h(_club_rfm_persons),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["customer_club.view"],
            category="customer_club",
        )
    )

    registry.register(
        AIFunction(
            name="get_quick_sales_settings",
            description="تنظیمات فروش سریع (انبار، صندوق، مشتری ناشناس پیش‌فرض).",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=h(_quick_sales_settings),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["settings.view"],
            category="sales",
        )
    )

    registry.register(
        AIFunction(
            name="list_price_lists",
            description="لیست‌های قیمت کسب‌وکار.",
            parameters_schema={
                "type": "object",
                "properties": {**_COMMON},
                "required": [],
            },
            handler=h(_price_lists),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["price_lists.view"],
            category="products",
        )
    )

    registry.register(
        AIFunction(
            name="search_activity_logs",
            description="جستجو در لاگ فعالیت‌های کسب‌وکار.",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON,
                    "category": {"type": "string"},
                    "entity_type": {"type": "string"},
                    "from_date": {"type": "string", "format": "date"},
                    "to_date": {"type": "string", "format": "date"},
                },
                "required": [],
            },
            handler=h(_activity_logs),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["activity_logs.view"],
            category="audit",
        )
    )

    registry.register(
        AIFunction(
            name="get_opening_balance",
            description="سند تراز افتتاحیه سال مالی.",
            parameters_schema={
                "type": "object",
                "properties": {"fiscal_year_id": {"type": "integer"}},
                "required": [],
            },
            handler=h(_opening_balance),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["opening_balance.view"],
            category="accounting",
        )
    )

    registry.register(
        AIFunction(
            name="get_business_credit_settings",
            description="تنظیمات اعتبار فروش کسب‌وکار.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=h(_credit_settings),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["credit.view"],
            category="credit",
        )
    )

    registry.register(
        AIFunction(
            name="list_credit_installment_plans",
            description="طرح‌های اقساط اعتباری.",
            parameters_schema={
                "type": "object",
                "properties": {"only_active": {"type": "boolean"}},
                "required": [],
            },
            handler=h(_installment_plans),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["credit.view"],
            category="credit",
        )
    )

    registry.register(
        AIFunction(
            name="get_person_credit",
            description="وضعیت اعتبار یک مشتری.",
            parameters_schema={
                "type": "object",
                "properties": {"person_id": {"type": "integer"}},
                "required": ["person_id"],
            },
            handler=h(_person_credit),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["credit.view"],
            category="credit",
        )
    )

    registry.register(
        AIFunction(
            name="list_woocommerce_orders",
            description="لیست سفارش‌های WooCommerce (نیاز به پلاگین و اتصال).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "page": {"type": "integer"},
                    "per_page": {"type": "integer"},
                    "status": {"type": "string"},
                    "search": {"type": "string"},
                },
                "required": [],
            },
            handler=h(_woo_orders),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["woocommerce.view"],
            category="integration",
        )
    )

    registry.register(
        AIFunction(
            name="list_woocommerce_products",
            description="لیست محصولات WooCommerce از فروشگاه متصل.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "page": {"type": "integer"},
                    "per_page": {"type": "integer"},
                    "search": {"type": "string"},
                },
                "required": [],
            },
            handler=h(_woo_products),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["woocommerce.view"],
            category="integration",
        )
    )

    registry.register(
        AIFunction(
            name="list_basalam_synced_invoices",
            description="فاکتورهای همگام‌شده از باسلام.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "from_date": {"type": "string", "format": "date"},
                    "to_date": {"type": "string", "format": "date"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
                "required": [],
            },
            handler=h(_basalam_invoices),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["basalam.view"],
            category="integration",
        )
    )

    registry.register(
        AIFunction(
            name="list_basalam_product_conflicts",
            description="تعارض‌های همگام‌سازی محصول باسلام.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
                "required": [],
            },
            handler=h(_basalam_conflicts),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["basalam.view"],
            category="integration",
        )
    )


def _club_settings(db, business_id, user_id, **kwargs):
    from app.services.customer_club_service import get_settings

    return get_settings(db, business_id)


def _club_tiers(db, business_id, user_id, **kwargs):
    from app.services.customer_club_service import list_tiers

    return {"items": list_tiers(db, business_id)}


def _club_ledger(db, business_id, user_id, **kwargs):
    return list_customer_club_ledger(db, business_id, kwargs)


def _club_rfm_summary(db, business_id, user_id, **kwargs):
    from app.services.customer_club_analytics_service import get_rfm_summary

    return get_rfm_summary(db, business_id)


def _club_rfm_persons(db, business_id, user_id, **kwargs):
    from app.services.customer_club_analytics_service import list_rfm_persons
    from app.services.ai.ai_query_service import _clamp_pagination

    q = _clamp_pagination(kwargs)
    items, total = list_rfm_persons(
        db,
        business_id,
        skip=q["skip"],
        limit=q["take"],
        segment_label=kwargs.get("segment_label"),
        search=kwargs.get("search"),
        sort=kwargs.get("sort") or "monetary_total",
        sort_dir=kwargs.get("sort_dir") or "desc",
    )
    return {"items": items, "pagination": {"total": total, "per_page": q["take"]}}


def _quick_sales_settings(db, business_id, user_id, **kwargs):
    from app.services.quick_sales_service import get_quick_sales_settings

    return get_quick_sales_settings(db, business_id)


def _price_lists(db, business_id, user_id, **kwargs):
    from app.services.price_list_service import list_price_lists
    from app.services.ai.ai_query_service import _clamp_pagination

    return list_price_lists(db, business_id, _clamp_pagination(kwargs))


def _activity_logs(db, business_id, user_id, **kwargs):
    return search_activity_logs(db, business_id, kwargs)


def _opening_balance(db, business_id, user_id, **kwargs):
    from app.services.opening_balance_service import get_opening_balance

    fy = kwargs.get("fiscal_year_id")
    data = get_opening_balance(db, business_id, fy)
    if not data:
        return {"message": "تراز افتتاحیه برای این سال مالی ثبت نشده", "fiscal_year_id": fy}
    return data


def _credit_settings(db, business_id, user_id, **kwargs):
    from app.services.credit_service import get_business_credit_settings

    return get_business_credit_settings(db, business_id)


def _installment_plans(db, business_id, user_id, **kwargs):
    from app.services.credit_service import list_installment_plans

    only = kwargs.get("only_active")
    if only is None:
        only = True
    return {"items": list_installment_plans(db, business_id, only_active=only)}


def _person_credit(db, business_id, user_id, person_id, **kwargs):
    from app.services.credit_service import get_person_credit

    return get_person_credit(db, business_id, person_id)


def _woo_orders(db, business_id, user_id, **kwargs):
    from app.services.woocommerce_integration_service import list_orders

    return _safe_integration_call(
        list_orders,
        db,
        business_id,
        page=int(kwargs.get("page") or 1),
        per_page=int(kwargs.get("per_page") or 20),
        status=kwargs.get("status"),
        search=kwargs.get("search"),
    )


def _woo_products(db, business_id, user_id, **kwargs):
    from app.services.woocommerce_integration_service import list_products

    return _safe_integration_call(
        list_products,
        db,
        business_id,
        page=int(kwargs.get("page") or 1),
        per_page=int(kwargs.get("per_page") or 20),
        search=kwargs.get("search"),
    )


def _parse_optional_date(v):
    from datetime import date as date_cls

    if not v:
        return None
    try:
        return date_cls.fromisoformat(str(v)[:10])
    except ValueError:
        return None


def _basalam_invoices(db, business_id, user_id, **kwargs):
    from app.services.basalam_reports_service import list_synced_invoices

    return _safe_integration_call(
        list_synced_invoices,
        db,
        business_id,
        date_from=_parse_optional_date(kwargs.get("from_date")),
        date_to=_parse_optional_date(kwargs.get("to_date")),
        skip=int(kwargs.get("skip") or 0),
        take=int(kwargs.get("take") or 50),
    )


def _basalam_conflicts(db, business_id, user_id, **kwargs):
    from app.services.basalam_reports_service import list_product_conflicts_for_report

    return _safe_integration_call(
        list_product_conflicts_for_report,
        db,
        business_id,
        search=kwargs.get("search"),
        limit=int(kwargs.get("take") or 50),
        offset=int(kwargs.get("skip") or 0),
    )
