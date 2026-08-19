"""
ابزارهای AI برای طراحی، تست و دیباگ اتوماسیون — کاتالوگ پویا از رجیستری.
"""
from __future__ import annotations

from typing import Any, Dict, TYPE_CHECKING

from app.services.ai.ai_workflow_catalog_service import (
    get_component_schema,
    get_workflow_design_rules,
    list_action_catalog,
    list_builtin_node_catalog,
    list_trigger_catalog,
)
from app.services.ai.ai_workflow_service import (
    create_workflow_for_ai,
    delete_workflow_for_ai,
    get_execution_debug_for_ai,
    get_workflow_for_ai,
    summarize_execution_for_ai,
    test_workflow_for_ai,
    update_workflow_for_ai,
    validate_workflow_draft,
)
from app.services.ai.function_registry import AIRole, AIFunction

if TYPE_CHECKING:
    from app.services.ai.function_registry import AIFunctionRegistry


def register_workflow_ai_functions(registry: "AIFunctionRegistry") -> None:
    h = registry._create_handler  # noqa: SLF001

    registry.register(
        AIFunction(
            name="list_workflow_trigger_catalog",
            description=(
                "لیست پویاى تریگرهای اتوماسیون از رجیستری سیستم (هر تریگر جدید خودکار ظاهر می‌شود). "
                "compact=true فقط نام/کلید؛ برای schema کامل از get_workflow_component_schema استفاده کن."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "compact": {"type": "boolean", "default": True},
                    "search": {"type": "string"},
                    "category": {"type": "string"},
                },
            },
            handler=h(_list_triggers),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="list_workflow_action_catalog",
            description="لیست پویاى اکشن‌های اتوماسیون از رجیستری سیستم.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "compact": {"type": "boolean", "default": True},
                    "search": {"type": "string"},
                    "category": {"type": "string"},
                },
            },
            handler=h(_list_actions),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="list_workflow_builtin_nodes",
            description="نودهای ساختاری (condition، loop) و schema آن‌ها.",
            parameters_schema={
                "type": "object",
                "properties": {"compact": {"type": "boolean", "default": True}},
            },
            handler=h(_list_builtin),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="get_workflow_component_schema",
            description=(
                "schema کامل یک جزء: component_kind=trigger|action|builtin و key "
                "(مثلاً invoice.created یا send_telegram یا condition)."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "component_kind": {"type": "string", "enum": ["trigger", "action", "builtin"]},
                    "key": {"type": "string"},
                },
                "required": ["component_kind", "key"],
            },
            handler=h(_get_schema),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="get_workflow_design_rules",
            description="قوانین ساخت workflow_data (nodes, connections) — مستقل از لیست تریگرها.",
            parameters_schema={"type": "object", "properties": {}},
            handler=h(_design_rules),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="validate_workflow_draft",
            description="اعتبارسنجی workflow_data قبل از ذخیره.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "workflow_data": {"type": "object"},
                },
                "required": ["workflow_data"],
            },
            handler=h(_validate),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="get_workflow",
            description="دریافت workflow؛ include_graph=true برای workflow_data کامل.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "workflow_id": {"type": "integer"},
                    "include_graph": {"type": "boolean", "default": True},
                },
                "required": ["workflow_id"],
            },
            handler=h(_get_workflow),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="create_workflow",
            description=(
                "ایجاد اتوماسیون جدید. اول get_workflow_design_rules و "
                "list_workflow_trigger_catalog / list_workflow_action_catalog، "
                "سپس validate_workflow_draft، بعد create با status=پیش‌نویس. "
                "workflow_data = {nodes, connections}. نیاز به تأیید."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "نام اتوماسیون"},
                    "description": {"type": "string", "description": "شرح (اختیاری)"},
                    "workflow_data": {
                        "type": "object",
                        "description": (
                            "گراف: {nodes: [...], connections: [{source, target, branch?}]}. "
                            "هر نود id و type=trigger|action|condition|loop. "
                            "قبل از ذخیره validate_workflow_draft."
                        ),
                    },
                    "status": {
                        "type": "string",
                        "enum": ["پیش‌نویس", "فعال", "غیرفعال"],
                        "default": "پیش‌نویس",
                        "description": "پیش‌فرض پیش‌نویس؛ فعال فقط با تأیید کاربر",
                    },
                    "settings": {"type": "object", "description": "تنظیمات اختیاری"},
                },
                "required": ["name", "workflow_data"],
            },
            handler=h(_create_workflow),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.write"],
            category="workflow",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="update_workflow",
            description=(
                "به‌روزرسانی اتوماسیون. اول get_workflow. "
                "اگر گراف عوض می‌شود validate_workflow_draft. نیاز به تأیید."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "workflow_id": {"type": "integer", "description": "شناسه اتوماسیون از list_workflows"},
                    "name": {"type": "string", "description": "نام جدید (اختیاری)"},
                    "description": {"type": "string", "description": "شرح (اختیاری)"},
                    "workflow_data": {
                        "type": "object",
                        "description": "گراف کامل {nodes, connections} اگر می‌خواهی جایگزین شود",
                    },
                    "status": {
                        "type": "string",
                        "enum": ["پیش‌نویس", "فعال", "غیرفعال"],
                        "description": "وضعیت (اختیاری)",
                    },
                    "settings": {"type": "object", "description": "تنظیمات (اختیاری)"},
                },
                "required": ["workflow_id"],
            },
            handler=h(_update_workflow),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.write"],
            category="workflow",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="delete_workflow",
            description="حذف اتوماسیون.",
            parameters_schema={
                "type": "object",
                "properties": {"workflow_id": {"type": "integer"}},
                "required": ["workflow_id"],
            },
            handler=h(_delete_workflow),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.write"],
            category="workflow",
            requires_approval=True,
            risk_level="high",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="test_workflow",
            description=(
                "اجرای آزمایشی workflow. workflow_data بدون ذخیره روی sandbox تست می‌شود. "
                "workflow_id برای تست اتوماسیون ذخیره‌شده. wait_for_completion=true لاگ کامل برمی‌گرداند."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "workflow_id": {
                        "type": "integer",
                        "description": "شناسه workflow ذخیره‌شده (اختیاری اگر workflow_data داده شود)",
                    },
                    "workflow_data": {
                        "type": "object",
                        "description": "گراف پیش‌نمایش — روی sandbox، بدون تغییر اتوماسیون کاربر",
                    },
                    "trigger_data": {"type": "object"},
                    "dry_run": {"type": "boolean", "default": True},
                    "wait_for_completion": {
                        "type": "boolean",
                        "default": True,
                        "description": "منتظر پایان اجرا و برگرداندن debug/summary",
                    },
                },
            },
            handler=h(_test_workflow),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.write"],
            category="workflow",
            requires_approval=False,
            risk_level="medium",
            is_readonly=False,
        )
    )

    registry.register(
        AIFunction(
            name="poll_workflow_execution",
            description=(
                "ادامهٔ دیباگ اجرا (polling لاگ). بعد از test_workflow با wait_for_completion=false "
                "یا برای به‌روزرسانی لاگ."
            ),
            parameters_schema={
                "type": "object",
                "properties": {
                    "workflow_id": {"type": "integer"},
                    "execution_id": {"type": "integer"},
                    "after_log_id": {"type": "integer", "default": 0},
                    "wait_for_completion": {"type": "boolean", "default": True},
                },
                "required": ["workflow_id", "execution_id"],
            },
            handler=h(_poll_execution),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )

    registry.register(
        AIFunction(
            name="get_workflow_execution_debug",
            description="لاگ و خطاهای یک اجرا برای دیباگ اتوماسیون از چت.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "workflow_id": {"type": "integer"},
                    "execution_id": {"type": "integer"},
                    "after_log_id": {"type": "integer", "default": 0},
                },
                "required": ["workflow_id", "execution_id"],
            },
            handler=h(_execution_debug),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["workflows.view"],
            category="workflow",
            is_readonly=True,
        )
    )


def _list_triggers(db, business_id, user_id, **kwargs):
    return list_trigger_catalog(
        compact=bool(kwargs.get("compact", True)),
        search=kwargs.get("search"),
        category=kwargs.get("category"),
    )


def _list_actions(db, business_id, user_id, **kwargs):
    return list_action_catalog(
        compact=bool(kwargs.get("compact", True)),
        search=kwargs.get("search"),
        category=kwargs.get("category"),
    )


def _list_builtin(db, business_id, user_id, **kwargs):
    return list_builtin_node_catalog(compact=bool(kwargs.get("compact", True)))


def _get_schema(db, business_id, user_id, component_kind, key, **kwargs):
    return get_component_schema(component_kind, key)


def _design_rules(db, business_id, user_id, **kwargs):
    return get_workflow_design_rules()


def _validate(db, business_id, user_id, workflow_data, **kwargs):
    from app.services.ai.ai_tool_payloads import normalize_workflow_graph

    return validate_workflow_draft(normalize_workflow_graph(workflow_data))


def _get_workflow(db, business_id, user_id, workflow_id, include_graph=True, **kwargs):
    return get_workflow_for_ai(
        db, business_id, int(workflow_id), include_graph=bool(include_graph)
    )


def _create_workflow(
    db, business_id, user_id, name=None, workflow_data=None, description=None, status="پیش‌نویس", settings=None, **kwargs
):
    from app.services.ai.ai_tool_payloads import build_create_workflow_payload

    payload = build_create_workflow_payload(
        {
            "name": name,
            "workflow_data": workflow_data,
            "description": description,
            "status": status,
            "settings": settings,
            **kwargs,
        }
    )
    return create_workflow_for_ai(
        db,
        business_id,
        user_id,
        name=payload["name"],
        workflow_data=payload["workflow_data"],
        description=payload.get("description"),
        status=payload.get("status"),
        settings=payload.get("settings"),
    )


def _update_workflow(db, business_id, user_id, workflow_id, **kwargs):
    from app.services.ai.ai_tool_payloads import (
        _WORKFLOW_STATUS_ALIASES,
        normalize_workflow_graph,
    )

    workflow_data = kwargs.get("workflow_data")
    if workflow_data is not None:
        workflow_data = normalize_workflow_graph(workflow_data)
    status = kwargs.get("status")
    if status:
        status = _WORKFLOW_STATUS_ALIASES.get(str(status).strip(), status)
    return update_workflow_for_ai(
        db,
        business_id,
        int(workflow_id),
        name=kwargs.get("name"),
        description=kwargs.get("description"),
        status=status,
        workflow_data=workflow_data,
        settings=kwargs.get("settings"),
    )


def _delete_workflow(db, business_id, user_id, workflow_id, **kwargs):
    return delete_workflow_for_ai(db, business_id, int(workflow_id))


def _test_workflow(db, business_id, user_id, workflow_id=None, **kwargs):
    wid = int(workflow_id) if workflow_id is not None else None
    return test_workflow_for_ai(
        db,
        business_id,
        user_id,
        wid,
        workflow_data=kwargs.get("workflow_data"),
        trigger_data=kwargs.get("trigger_data"),
        dry_run=bool(kwargs.get("dry_run", True)),
        wait_for_completion=bool(kwargs.get("wait_for_completion", True)),
    )


def _poll_execution(
    db, business_id, user_id, workflow_id, execution_id, after_log_id=0, **kwargs
):
    from app.services.ai.ai_workflow_service import _wait_for_execution

    wid = int(workflow_id)
    eid = int(execution_id)
    wait = bool(kwargs.get("wait_for_completion", True))
    if wait and int(after_log_id or 0) == 0:
        _wait_for_execution(db, eid)
    debug = get_execution_debug_for_ai(
        db, business_id, wid, eid, after_log_id=int(after_log_id or 0)
    )
    debug["summary"] = summarize_execution_for_ai(db, business_id, wid, eid)
    return debug


def _execution_debug(
    db, business_id, user_id, workflow_id, execution_id, after_log_id=0, **kwargs
):
    return get_execution_debug_for_ai(
        db,
        business_id,
        int(workflow_id),
        int(execution_id),
        after_log_id=int(after_log_id or 0),
    )
