"""
فاز ۷ AI — قالب‌های گزارش و چاپ (read + write با تأیید).
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


def _template_summary(t) -> Dict[str, Any]:
    return {
        "id": t.id,
        "name": t.name,
        "module_key": t.module_key,
        "subtype": t.subtype,
        "status": t.status,
        "is_default": bool(t.is_default),
        "version": t.version,
        "updated_at": t.updated_at.isoformat() if t.updated_at else None,
    }


def register_phase7_business_functions(registry: "AIFunctionRegistry") -> None:
    def list_report_templates_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.report_template_service import ReportTemplateService

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        ctx = context["user_context"]
        only_published = not ctx.can_write_section("report_templates")
        templates = ReportTemplateService.list_templates(
            db,
            business_id,
            module_key=args.get("module_key"),
            subtype=args.get("subtype"),
            status=args.get("status"),
            only_published=only_published,
        )
        return {"items": [_template_summary(t) for t in templates], "total": len(templates)}

    registry.register(
        AIFunction(
            name="list_report_templates",
            description="لیست قالب‌های گزارش/چاپ کسب‌وکار (فاکتور، دریافت/پرداخت، …).",
            parameters_schema={
                "type": "object",
                "properties": {
                    "module_key": {"type": "string"},
                    "subtype": {"type": "string"},
                    "status": {"type": "string"},
                },
            },
            handler=list_report_templates_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["report_templates.view"],
            category="report_templates",
            is_readonly=True,
        )
    )

    def get_report_template_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.report_template_service import ReportTemplateService

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        tid = int(args["template_id"])
        t = ReportTemplateService.get_template(db, tid, business_id)
        if not t:
            raise ValueError("قالب یافت نشد")
        out = _template_summary(t)
        out["description"] = t.description
        out["paper_size"] = t.paper_size
        out["orientation"] = t.orientation
        return out

    registry.register(
        AIFunction(
            name="get_report_template",
            description="جزئیات یک قالب گزارش (بدون محتوای HTML کامل).",
            parameters_schema={
                "type": "object",
                "properties": {"template_id": {"type": "integer"}},
                "required": ["template_id"],
            },
            handler=get_report_template_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["report_templates.view"],
            category="report_templates",
            is_readonly=True,
        )
    )

    def get_report_template_scope_catalog_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.report_template_scope_registry import catalog

        return {"items": catalog()}

    registry.register(
        AIFunction(
            name="get_report_template_scope_catalog",
            description="کاتالوگ scopeهای مجاز برای اتصال قالب (invoices/detail، …).",
            parameters_schema={"type": "object", "properties": {}},
            handler=get_report_template_scope_catalog_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["report_templates.view"],
            category="report_templates",
            is_readonly=True,
        )
    )

    def set_default_report_template_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.report_template_service import ReportTemplateService

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        entity = ReportTemplateService.set_default(
            db,
            business_id,
            str(args["module_key"]),
            args.get("subtype"),
            int(args["template_id"]),
        )
        return _template_summary(entity)

    registry.register(
        AIFunction(
            name="set_default_report_template",
            description="تنظیم قالب پیش‌فرض برای یک scope (module_key + subtype). نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "template_id": {"type": "integer"},
                    "module_key": {"type": "string"},
                    "subtype": {"type": "string"},
                },
                "required": ["template_id", "module_key"],
            },
            handler=set_default_report_template_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["report_templates.write"],
            category="report_templates",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )

    def publish_report_template_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from app.services.report_template_service import ReportTemplateService

        db = context["db"]
        business_id = int(args.get("business_id") or context.get("business_id"))
        tid = int(args["template_id"])
        publish = bool(args.get("publish", True))
        entity = ReportTemplateService.publish_template(db, tid, business_id, is_published=publish)
        return _template_summary(entity)

    registry.register(
        AIFunction(
            name="publish_report_template",
            description="انتشار یا بازگشت قالب به پیش‌نویس. publish=true برای انتشار. نیاز به تأیید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "template_id": {"type": "integer"},
                    "publish": {"type": "boolean"},
                },
                "required": ["template_id"],
            },
            handler=publish_report_template_handler,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["report_templates.write"],
            category="report_templates",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )
