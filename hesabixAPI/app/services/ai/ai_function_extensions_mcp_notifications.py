"""MCP tools for business notification templates and send. Connector secrets stay out of band."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

CREATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA: Dict[str, Any] = {}
UPDATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA: Dict[str, Any] = {}
SEND_BUSINESS_NOTIFICATION_SCHEMA: Dict[str, Any] = {}

CREATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA = mcp_schema(
    {
        "code": {"type": "string", "minLength": 1, "maxLength": 100},
        "name": {"type": "string", "minLength": 1, "maxLength": 200},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "event_type": {"type": "string", "minLength": 1, "maxLength": 100},
        "channel": {"type": "string", "enum": ["sms", "email"]},
        "recipient_type": {"type": "string", "enum": ["customer", "supplier", "employee"]},
        "subject": {"type": ["string", "null"], "maxLength": 200},
        "body": {"type": "string", "minLength": 1, "maxLength": 8000},
        "daily_limit": {"type": "integer", "minimum": 1, "maximum": 10000},
        "is_automated": {"type": "boolean"},
    },
    ["code", "name", "event_type", "channel", "body"],
)
UPDATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA = mcp_schema(
    {
        "template_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 200},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "subject": {"type": ["string", "null"], "maxLength": 200},
        "body": {"type": "string", "minLength": 1, "maxLength": 8000},
        "daily_limit": {"type": "integer", "minimum": 1, "maximum": 10000},
        "is_automated": {"type": "boolean"},
        "is_active": {"type": "boolean"},
    },
    ["template_id"],
)
_TID = mcp_schema({"template_id": {"type": "integer", "minimum": 1}}, ["template_id"])
_PREVIEW = mcp_schema(
    {
        "template_id": {"type": "integer", "minimum": 1},
        "sample_context": {"type": "object"},
    },
    ["template_id", "sample_context"],
)
SEND_BUSINESS_NOTIFICATION_SCHEMA = mcp_schema(
    {
        "person_id": {"type": "integer", "minimum": 1},
        "event_type": {"type": "string", "minLength": 1, "maxLength": 100},
        "context": {"type": "object"},
        "channel": {"anyOf": [{"type": "string", "enum": ["sms", "email"]}, {"type": "null"}]},
        "recipient_mobile": {"type": ["string", "null"], "maxLength": 32},
    },
    ["person_id", "event_type", "context"],
)


def _public_template(template) -> Dict[str, Any]:
    return {
        "id": template.id,
        "code": template.code,
        "name": template.name,
        "description": getattr(template, "description", None),
        "event_type": template.event_type,
        "channel": template.channel,
        "recipient_type": getattr(template, "recipient_type", None),
        "subject": getattr(template, "subject", None),
        "body": template.body,
        "status": template.status,
        "is_active": getattr(template, "is_active", None),
        "approval_status": getattr(template, "approval_status", None),
        "daily_limit": getattr(template, "daily_limit", None),
        "is_automated": getattr(template, "is_automated", None),
    }


def get_business_notification_template_handler(args, context):
    from adapters.db.repositories.business_notification_repo import BusinessNotificationTemplateRepository

    template = BusinessNotificationTemplateRepository(mcp_db(context)).get_by_id(
        int(args["template_id"]), mcp_bid(context)
    )
    if not template:
        raise ValueError("قالب اعلان یافت نشد")
    return _public_template(template)


def create_business_notification_template_handler(args, context):
    from adapters.api.v1.schema_models.business_notification import TemplateCreate
    from adapters.db.repositories.business_notification_repo import (
        BusinessNotificationTemplateRepository,
        NotificationEventTypeRepository,
    )
    from app.services.business_notification_service import TemplateRenderService

    create_keys = (
        "code",
        "name",
        "description",
        "event_type",
        "channel",
        "recipient_type",
        "subject",
        "body",
        "daily_limit",
        "is_automated",
    )
    data = TemplateCreate(**{k: v for k, v in args.items() if k in create_keys})
    db = mcp_db(context)
    bid = mcp_bid(context)
    repo = BusinessNotificationTemplateRepository(db)
    if repo.get_by_code(bid, data.code):
        raise ValueError("کد قالب تکراری است")
    event_type = NotificationEventTypeRepository(db).get_by_code(data.event_type)
    if not event_type:
        raise ValueError("نوع رویداد نامعتبر است")
    validation = TemplateRenderService().validate_template(
        data.body, [var["key"] for var in (event_type.available_variables or [])]
    )
    if not validation.get("is_valid"):
        raise ValueError(f"قالب نامعتبر است: {', '.join(validation.get('errors') or [])}")
    payload = data.dict()
    payload.update(
        {
            "business_id": bid,
            "created_by_user_id": mcp_uid(context),
            "available_variables": event_type.available_variables,
            "status": "draft",
            "is_active": False,
            "approval_status": "pending",
        }
    )
    template = repo.create(payload)
    db.commit()
    return {
        "id": template.id,
        "code": template.code,
        "status": template.status,
        "message": "قالب ایجاد شد. برای فعال‌سازی باید آن را برای تایید ارسال کنید.",
    }


def update_business_notification_template_handler(args, context):
    from adapters.db.repositories.business_notification_repo import BusinessNotificationTemplateRepository

    db = mcp_db(context)
    repo = BusinessNotificationTemplateRepository(db)
    template = repo.get_by_id(int(args["template_id"]), mcp_bid(context))
    if not template:
        raise ValueError("قالب اعلان یافت نشد")
    update_data = {k: v for k, v in args.items() if k in ("name", "description", "subject", "body", "daily_limit", "is_automated", "is_active")}
    repo.update(template, update_data)
    db.commit()
    return {"id": template.id, "message": "قالب به‌روزرسانی شد"}


def submit_business_notification_template_handler(args, context):
    from adapters.db.repositories.business_notification_repo import (
        BusinessNotificationTemplateRepository,
        NotificationModerationQueueRepository,
    )

    db = mcp_db(context)
    bid = mcp_bid(context)
    template_id = int(args["template_id"])
    template_repo = BusinessNotificationTemplateRepository(db)
    template = template_repo.get_by_id(template_id, bid)
    if not template:
        raise ValueError("قالب اعلان یافت نشد")
    if template.status not in ["draft", "rejected"]:
        raise ValueError("قالب در این وضعیت قابل ارسال برای تایید نیست")
    queue_repo = NotificationModerationQueueRepository(db)
    if queue_repo.get_by_template(template_id):
        raise ValueError("این قالب در حال حاضر در صف بررسی است")
    queue_repo.create({"template_id": template_id, "business_id": bid, "status": "pending", "priority": 0})
    template_repo.update(template, {"status": "pending_approval"})
    db.commit()
    return {"message": "قالب برای تایید ارسال شد", "id": template_id}


def preview_business_notification_template_handler(args, context):
    from app.services.business_notification_service import BusinessNotificationService

    result = mcp_run(
        BusinessNotificationService(mcp_db(context)).preview_template,
        mcp_bid(context),
        int(args["template_id"]),
        args.get("sample_context") or {},
    )
    return mcp_jsonable(result)


def send_business_notification_handler(args, context):
    from app.services.business_notification_service import BusinessNotificationService

    mobile = args.get("recipient_mobile")
    result = mcp_run(
        BusinessNotificationService(mcp_db(context)).send_to_person,
        business_id=mcp_bid(context),
        person_id=int(args["person_id"]),
        event_type=args["event_type"],
        context=args.get("context") or {},
        channel=args.get("channel"),
        recipient_mobile_override=(str(mobile).strip() or None) if mobile else None,
        triggered_by_user_id=mcp_uid(context),
    )
    return mcp_jsonable(result)


def register_mcp_notification_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_business_notification_template",
        description="جزئیات قالب اعلان کسب‌وکار متصل. توکن ارائه‌دهنده برنمی‌گردد.",
        parameters_schema=_TID,
        handler=get_business_notification_template_handler,
        allowed_roles=roles,
        required_permissions=["notifications.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_business_notification_template",
        description="ایجاد قالب اعلان پیش‌نویس. برای فعال‌سازی باید برای تایید ارسال شود.",
        parameters_schema=CREATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA,
        handler=create_business_notification_template_handler,
        allowed_roles=roles,
        required_permissions=["notifications.write"],
        category="business",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_business_notification_template",
        description="ویرایش قالب اعلان متعلق به کسب‌وکار متصل.",
        parameters_schema=UPDATE_BUSINESS_NOTIFICATION_TEMPLATE_SCHEMA,
        handler=update_business_notification_template_handler,
        allowed_roles=roles,
        required_permissions=["notifications.write"],
        category="business",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="submit_business_notification_template",
        description="ارسال قالب پیش‌نویس به صف تایید. نیازمند تأیید.",
        parameters_schema=_TID,
        handler=submit_business_notification_template_handler,
        allowed_roles=roles,
        required_permissions=["notifications.write"],
        category="business",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="preview_business_notification_template",
        description="پیش‌نمایش قالب اعلان با context نمونه. ارسال واقعی نیست.",
        parameters_schema=_PREVIEW,
        handler=preview_business_notification_template_handler,
        allowed_roles=roles,
        required_permissions=["notifications.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="send_business_notification",
        description="ارسال اعلان به یک شخص از قالب فعال event_type. نیازمند تأیید.",
        parameters_schema=SEND_BUSINESS_NOTIFICATION_SCHEMA,
        handler=send_business_notification_handler,
        allowed_roles=roles,
        required_permissions=["notifications.send"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
