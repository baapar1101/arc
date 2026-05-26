"""
ثبت functionهای AI — فاز ۲ (پروژه، مالیات، workflow، BOM، تعمیرگاه، …).
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_query_phase2_service import (
    get_project_summary,
    get_tax_data_quality_for_ai,
    get_tax_settings_for_ai,
    list_workflows_for_ai,
    list_workflow_executions_for_ai,
    search_projects,
    search_tax_workspace,
)
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry

_COMMON = {
    "search": {"type": "string", "description": "متن جستجو (اختیاری)"},
    "from_date": {"type": "string", "format": "date", "description": "از تاریخ (اختیاری)"},
    "to_date": {"type": "string", "format": "date", "description": "تا تاریخ (اختیاری)"},
    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"},
    "take": {"type": "integer", "description": "تعداد نتایج (پیش‌فرض ۵۰)"},
    "skip": {"type": "integer", "description": "ردیف شروع"},
}


def register_phase2_business_functions(registry: "AIFunctionRegistry") -> None:
    h = registry._create_handler  # noqa: SLF001

    registry.register(
        AIFunction(
            name="search_projects",
            description="جستجو و لیست پروژه‌های کسب‌وکار.",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON,
                    "status": {"type": "string", "description": "active, completed, on_hold, cancelled"},
                    "is_active": {"type": "boolean"},
                    "person_id": {"type": "integer"},
                },
                "required": [],
            },
            handler=h(_search_projects),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["accounting_documents.view"],
            category="projects",
        )
    )

    registry.register(
        AIFunction(
            name="get_project_summary",
            description="جزئیات و آمار مالی یک پروژه.",
            parameters_schema={
                "type": "object",
                "properties": {"project_id": {"type": "integer"}},
                "required": ["project_id"],
            },
            handler=h(_get_project_summary),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["accounting_documents.view"],
            category="projects",
        )
    )

    registry.register(
        AIFunction(
            name="list_boms",
            description="لیست BOM (فرمول تولید) کالاها.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer", "description": "فیلتر کالا (اختیاری)"},
                },
                "required": [],
            },
            handler=h(_list_boms),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["inventory.read"],
            category="production",
        )
    )

    registry.register(
        AIFunction(
            name="get_bom_details",
            description="جزئیات یک BOM.",
            parameters_schema={
                "type": "object",
                "properties": {"bom_id": {"type": "integer"}},
                "required": ["bom_id"],
            },
            handler=h(_get_bom),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["inventory.read"],
            category="production",
        )
    )

    registry.register(
        AIFunction(
            name="search_production_documents",
            description="جستجوی اسناد تولید (invoice_production).",
            parameters_schema={"type": "object", "properties": dict(_COMMON), "required": []},
            handler=h(_search_production),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.read"],
            category="production",
        )
    )

    registry.register(
        AIFunction(
            name="search_repair_orders",
            description="لیست سفارشات تعمیرگاه (نیاز به پلاگین تعمیرگاه).",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON,
                    "status": {"type": "string", "description": "received, in_progress, ready, ..."},
                    "customer_person_id": {"type": "integer"},
                },
                "required": [],
            },
            handler=h(_search_repair_orders),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.read"],
            category="repair",
        )
    )

    registry.register(
        AIFunction(
            name="get_repair_order_details",
            description="جزئیات کامل سفارش تعمیر.",
            parameters_schema={
                "type": "object",
                "properties": {"repair_order_id": {"type": "integer"}},
                "required": ["repair_order_id"],
            },
            handler=h(_get_repair_order),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.read"],
            category="repair",
        )
    )

    registry.register(
        AIFunction(
            name="get_tax_settings",
            description="تنظیمات مالیاتی کسب‌وکار (بدون کلید خصوصی).",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=h(_tax_settings),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["moadian.view"],
            category="tax",
        )
    )

    registry.register(
        AIFunction(
            name="search_tax_workspace",
            description="جستجو در فاکتورهای کارپوشه مودیان.",
            parameters_schema={
                "type": "object",
                "properties": {
                    **_COMMON,
                    "document_type": {"type": "string"},
                    "tax_status": {"type": "string", "description": "وضعیت ارسال مالیاتی (اختیاری)"},
                },
                "required": [],
            },
            handler=h(_search_tax_ws),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["moadian.view"],
            category="tax",
        )
    )

    registry.register(
        AIFunction(
            name="get_tax_data_quality",
            description="گزارش کیفیت داده برای ارسال مالیاتی (کالا/شخص بدون کد مالیاتی و …).",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=h(_tax_quality),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["moadian.view"],
            category="tax",
        )
    )

    registry.register(
        AIFunction(
            name="list_workflows",
            description="لیست workflowهای اتوماسیون کسب‌وکار.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string"},
                    "status": {"type": "string"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
                "required": [],
            },
            handler=h(_list_workflows),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
        )
    )

    registry.register(
        AIFunction(
            name="list_workflow_executions",
            description="لیست اجراهای یک workflow.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "workflow_id": {"type": "integer"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
                "required": ["workflow_id"],
            },
            handler=h(_list_wf_executions),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
        )
    )

    registry.register(
        AIFunction(
            name="list_distribution_routes",
            description="لیست مسیرهای توزیع (نیاز به پلاگین توزیع).",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=_distribution_routes_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["distribution.view"],
            category="distribution",
        )
    )

    registry.register(
        AIFunction(
            name="search_warranty_codes",
            description="جستجوی کدهای گارانتی.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "status": {"type": "string"},
                    "product_id": {"type": "integer"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
                "required": [],
            },
            handler=h(_search_warranty),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["warranty.read"],
            category="warranty",
        )
    )

    registry.register(
        AIFunction(
            name="list_petty_cash",
            description="لیست صندوق‌های خرد با موجودی.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string"},
                    "fiscal_year_id": {"type": "integer"},
                    "take": {"type": "integer"},
                    "skip": {"type": "integer"},
                },
                "required": [],
            },
            handler=h(_list_petty),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["petty_cash.view"],
            category="financial",
        )
    )


def _search_projects(db, business_id, user_id, **kwargs):
    return search_projects(db, business_id, kwargs)


def _get_project_summary(db, business_id, user_id, project_id, **kwargs):
    return get_project_summary(db, business_id, project_id)


def _list_boms(db, business_id, user_id, **kwargs):
    from app.services.bom_service import list_boms

    return list_boms(db, business_id, kwargs.get("product_id"))


def _get_bom(db, business_id, user_id, bom_id, **kwargs):
    from app.services.bom_service import get_bom

    data = get_bom(db, business_id, bom_id)
    if not data:
        raise ValueError(f"BOM {bom_id} یافت نشد")
    return data


def _search_production(db, business_id, user_id, **kwargs):
    from app.services.document_service import list_documents
    from app.services.ai.ai_query_service import _build_list_query

    q = _build_list_query(kwargs)
    q["document_type"] = "invoice_production"
    return list_documents(db, business_id, q)


def _search_repair_orders(db, business_id, user_id, **kwargs):
    from app.services.repair_shop_service import list_repair_orders
    from app.services.ai.ai_query_service import _clamp_pagination

    q = _clamp_pagination(kwargs)
    flt = {k: kwargs[k] for k in ("status", "customer_person_id", "search") if kwargs.get(k) is not None}
    return list_repair_orders(db, business_id, flt, offset=q["skip"], limit=q["take"])


def _get_repair_order(db, business_id, user_id, repair_order_id, **kwargs):
    from app.services.repair_shop_service import get_repair_order

    return get_repair_order(db, business_id, repair_order_id)


def _tax_settings(db, business_id, user_id, **kwargs):
    return get_tax_settings_for_ai(db, business_id)


def _search_tax_ws(db, business_id, user_id, **kwargs):
    return search_tax_workspace(db, business_id, kwargs)


def _tax_quality(db, business_id, user_id, **kwargs):
    return get_tax_data_quality_for_ai(db, business_id)


def _list_workflows(db, business_id, user_id, **kwargs):
    return list_workflows_for_ai(db, business_id, kwargs)


def _list_wf_executions(db, business_id, user_id, workflow_id, **kwargs):
    return list_workflow_executions_for_ai(db, business_id, workflow_id, kwargs)


def _search_warranty(db, business_id, user_id, **kwargs):
    from app.services.warranty_service import list_warranty_codes
    from app.services.ai.ai_query_service import _clamp_pagination

    q = _clamp_pagination(kwargs)
    return list_warranty_codes(
        db,
        business_id,
        status=kwargs.get("status"),
        product_id=kwargs.get("product_id"),
        limit=q["take"],
        skip=q["skip"],
    )


def _list_petty(db, business_id, user_id, **kwargs):
    from app.services.petty_cash_service import list_petty_cash
    from app.services.ai.ai_query_service import _build_list_query

    q = _build_list_query(kwargs)
    if q.get("search") and not q.get("search_fields"):
        q["search_fields"] = ["code", "name"]
    return list_petty_cash(db, business_id, q)


def _distribution_routes_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.distribution_service import list_routes

    db = context["db"]
    business_id = int(args.get("business_id") or context.get("business_id"))
    ctx = context["user_context"]
    routes = list_routes(db, business_id, ctx)
    return {"items": routes, "total": len(routes)}
