"""
ابزارهای برنامهٔ کاری موقت agent در جلسهٔ چت.
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_session_todo_service import (
    SESSION_TODO_TOOL_NAMES,
    create_session_plan,
    list_session_todos,
    todos_dicts_from_rows,
    todos_summary,
    update_session_todo,
    parse_plan_items_arg,
)
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


def register_session_todo_functions(registry: "AIFunctionRegistry") -> None:
    create_handler = registry._create_handler  # noqa: SLF001

    def _require_session(context: Dict[str, Any]) -> int:
        session_id = context.get("session_id")
        if not session_id:
            raise ValueError("شناسه جلسه در context موجود نیست")
        return int(session_id)

    def create_session_plan_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        session_id = _require_session(context)
        items = parse_plan_items_arg(args.get("items"))
        plan_title = (args.get("plan_title") or "").strip() or None
        replace = bool(args.get("replace_existing", True))
        rows = create_session_plan(
            db,
            session_id,
            items,
            origin_message_id=context.get("origin_message_id"),
            plan_title=plan_title,
            replace_existing=replace,
        )
        summary = todos_summary(rows)
        return {
            "success": True,
            "plan_title": plan_title,
            "items": todos_dicts_from_rows(rows),
            "summary": summary,
        }

    def list_session_todos_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        session_id = _require_session(context)
        include_completed = bool(args.get("include_completed", True))
        rows = list_session_todos(db, session_id, include_completed=include_completed)
        summary = todos_summary(rows)
        return {
            "items": todos_dicts_from_rows(rows),
            "summary": summary,
        }

    def update_session_todo_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
        from sqlalchemy.orm import Session

        db: Session = context["db"]
        session_id = _require_session(context)
        todo_id = str(args.get("todo_id") or args.get("id") or "").strip()
        row = update_session_todo(
            db,
            session_id,
            todo_id=todo_id,
            title=args.get("title"),
            description=args.get("description"),
            status=args.get("status"),
            order=args.get("order"),
            linked_tool=args.get("linked_tool"),
            error_message=args.get("error_message"),
        )
        all_rows = list_session_todos(db, session_id)
        return {
            "success": True,
            "item": todos_dicts_from_rows([row])[0],
            "summary": todos_summary(all_rows),
        }

    registry.register(
        AIFunction(
            name="create_session_plan",
            description=(
                "ساخت برنامهٔ کاری چندمرحله‌ای برای سناریوی پیچیده در همین گفت‌وگو. "
                "فقط وقتی کار بیش از یک مرحلهٔ مجزا دارد استفاده کن. "
                "هر آیتم باید title داشته باشد؛ description و linked_tool اختیاری‌اند."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "plan_title": {
                        "type": "string",
                        "description": "عنوان کلی برنامه (اختیاری)",
                    },
                    "replace_existing": {
                        "type": "boolean",
                        "description": "جایگزینی برنامهٔ باز قبلی (پیش‌فرض: true)",
                    },
                    "items": {
                        "type": "array",
                        "description": "لیست مراحل کار",
                        "items": {
                            "type": "object",
                            "properties": {
                                "title": {"type": "string"},
                                "description": {"type": "string"},
                                "status": {
                                    "type": "string",
                                    "enum": [
                                        "pending",
                                        "in_progress",
                                        "done",
                                        "skipped",
                                        "error",
                                    ],
                                },
                                "order": {"type": "integer"},
                                "linked_tool": {
                                    "type": "string",
                                    "description": "نام ابزار مرتبط با این مرحله",
                                },
                            },
                            "required": ["title"],
                        },
                    },
                },
                "required": ["items"],
            },
            handler=create_handler(create_session_plan_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="agent",
            is_readonly=False,
            requires_approval=False,
            risk_level="safe",
            is_agent_internal=True,
        )
    )

    registry.register(
        AIFunction(
            name="list_session_todos",
            description=(
                "خواندن برنامهٔ کاری جاری این گفت‌وگو و وضعیت هر مرحله. "
                "قبل از به‌روزرسانی وضعیت از این ابزار استفاده کن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "include_completed": {
                        "type": "boolean",
                        "description": "شامل آیتم‌های انجام‌شده (پیش‌فرض: true)",
                    },
                },
            },
            handler=create_handler(list_session_todos_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="agent",
            is_readonly=True,
            requires_approval=False,
            risk_level="safe",
            is_agent_internal=True,
        )
    )

    registry.register(
        AIFunction(
            name="update_session_todo",
            description=(
                "به‌روزرسانی یک آیتم برنامهٔ کاری: تغییر وضعیت (in_progress/done/skipped/error)، "
                "عنوان، یا ابزار مرتبط. قبل از شروع هر مرحله in_progress و بعد done بزن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "todo_id": {
                        "type": "string",
                        "description": "شناسه آیتم از list_session_todos یا create_session_plan",
                    },
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                    "status": {
                        "type": "string",
                        "enum": [
                            "pending",
                            "in_progress",
                            "done",
                            "skipped",
                            "error",
                        ],
                    },
                    "order": {"type": "integer"},
                    "linked_tool": {"type": "string"},
                    "error_message": {
                        "type": "string",
                        "description": "توضیح خطا هنگام status=error",
                    },
                },
                "required": ["todo_id"],
            },
            handler=create_handler(update_session_todo_handler),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=[],
            category="agent",
            is_readonly=False,
            requires_approval=False,
            risk_level="safe",
            is_agent_internal=True,
        )
    )


__all__ = ["register_session_todo_functions", "SESSION_TODO_TOOL_NAMES"]
