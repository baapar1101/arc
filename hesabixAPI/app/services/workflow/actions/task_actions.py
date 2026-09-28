"""Task/project actions for the existing Hesabix workflow engine."""

from __future__ import annotations

from typing import Any, Dict

from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution


class InstantiateTaskTemplateAction(ActionHandler):
    """Instantiate a native project/task template from any workflow trigger."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد پروژه/کارها از قالب",
            "description": "ساخت پروژه و کارهای بومی از Task Project Template",
            "config_schema": {
                "template_id": {
                    "type": "integer",
                    "description": "شناسه قالب پروژه/کار",
                    "required": True,
                },
                "project_id": {
                    "type": "integer",
                    "description": "پروژه موجود؛ در صورت خالی بودن پروژه جدید ساخته می‌شود",
                    "required": False,
                },
                "project_code": {
                    "type": "string",
                    "description": "کد پروژه جدید؛ قابلیت reference به trigger/node",
                    "required": False,
                },
                "project_name": {
                    "type": "string",
                    "description": "نام پروژه جدید؛ قابلیت reference به trigger/node",
                    "required": False,
                },
                "start_date": {
                    "type": "string",
                    "description": "تاریخ پایه قالب (ISO date)",
                    "required": False,
                },
                "person_id": {
                    "type": "integer",
                    "description": "شناسه مشتری/شخص مرتبط پروژه جدید",
                    "required": False,
                },
                "manager_user_id": {
                    "type": "integer",
                    "description": "مدیر پروژه جدید",
                    "required": False,
                },
                "link_entity_type": {
                    "type": "string",
                    "description": "نوع موجودیت CRM برای لینک‌کردن کارهای تولیدشده",
                    "required": False,
                    "enum": [
                        "person",
                        "lead",
                        "deal",
                        "crm_activity",
                        "document",
                        "product",
                    ],
                },
                "link_entity_id": {
                    "type": "string",
                    "description": "شناسه موجودیت CRM؛ می‌تواند reference به trigger باشد",
                    "required": False,
                },
                "relationship_type": {
                    "type": "string",
                    "description": "نوع ارتباط کارها با موجودیت",
                    "required": False,
                    "default": "related",
                    "enum": [
                        "related",
                        "customer",
                        "contact",
                        "source",
                        "regarding",
                        "billing",
                        "product",
                        "follow_up",
                    ],
                },
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from adapters.db.models.business import Business
        from app.services.task_template_service import (
            instantiate_project_task_template,
        )
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine

        skipped = dry_run_skip(context, "ایجاد پروژه/کارها از قالب")
        if skipped is not None:
            return skipped

        db = context.get("db")
        business_id = context.get("business_id")
        if db is None or business_id is None:
            return {
                "success": False,
                "error": "db or business_id missing in workflow context",
            }

        def resolve(key: str):
            return WorkflowEngine._resolve_value_static(
                config.get(key),
                context,
                node_results,
            )

        template_id = resolve("template_id")
        if template_id in (None, ""):
            return {"success": False, "error": "template_id is required"}

        actor_user_id = context.get("user_id")
        if not actor_user_id:
            business = db.query(Business).filter(
                Business.id == int(business_id)
            ).first()
            actor_user_id = business.owner_id if business else None
        if not actor_user_id:
            return {
                "success": False,
                "error": "workflow user or business owner is required",
            }

        payload: Dict[str, Any] = {}
        integer_fields = {"project_id", "person_id", "manager_user_id"}
        for key in [
            "project_id",
            "project_code",
            "project_name",
            "start_date",
            "person_id",
            "manager_user_id",
            "link_entity_type",
            "link_entity_id",
            "relationship_type",
        ]:
            value = resolve(key)
            if value in (None, ""):
                continue
            if key in integer_fields:
                try:
                    value = int(value)
                except (TypeError, ValueError):
                    return {
                        "success": False,
                        "error": f"{key} must resolve to an integer",
                    }
            payload[key] = value

        try:
            result = instantiate_project_task_template(
                db,
                int(business_id),
                int(template_id),
                int(actor_user_id),
                payload,
            )
            return {"success": True, **result}
        except Exception as exc:
            return {"success": False, "error": str(exc)}
