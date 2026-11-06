"""MCP tools for CRM web-chat widgets, conversations, and agent replies."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import (
    mcp_await,
    mcp_bid,
    mcp_db,
    mcp_jsonable,
    mcp_run,
    mcp_schema,
    mcp_uid,
)

EMPTY = mcp_schema({})
SETTINGS_UPDATE = mcp_schema(
    {"allow_web_chat_file_upload": {"type": "boolean"}, "allow_web_chat_voice": {"type": "boolean"}}
)
WIDGET_CREATE = mcp_schema(
    {
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "allowed_origins": {"type": "array", "maxItems": 50, "items": {"type": "string", "maxLength": 255}},
        "is_active": {"type": "boolean"},
    },
    ["name"],
)
WIDGET_UPDATE = mcp_schema(
    {
        "widget_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "allowed_origins": {"type": "array", "maxItems": 50, "items": {"type": "string", "maxLength": 255}},
        "is_active": {"type": "boolean"},
    },
    ["widget_id"],
)
CONV_LIST = mcp_schema(
    {
        "status": {"type": "string", "enum": ["open", "pending", "resolved"]},
        "search": {"type": "string", "maxLength": 120},
        "limit": {"type": "integer", "minimum": 1, "maximum": 200},
        "offset": {"type": "integer", "minimum": 0},
    }
)
CONV_ID = mcp_schema({"conversation_id": {"type": "integer", "minimum": 1}}, ["conversation_id"])
MSG_LIST = mcp_schema(
    {
        "conversation_id": {"type": "integer", "minimum": 1},
        "limit": {"type": "integer", "minimum": 1, "maximum": 200},
        "before_message_id": {"type": "integer", "minimum": 1},
    },
    ["conversation_id"],
)
MSG_SEND = mcp_schema(
    {
        "conversation_id": {"type": "integer", "minimum": 1},
        "body": {"type": ["string", "null"], "maxLength": 8000},
        "file_storage_id": {"type": ["string", "null"], "maxLength": 36},
    },
    ["conversation_id"],
)
MSG_PATCH = mcp_schema(
    {
        "conversation_id": {"type": "integer", "minimum": 1},
        "message_id": {"type": "integer", "minimum": 1},
        "body": {"type": "string", "minLength": 1, "maxLength": 8000},
    },
    ["conversation_id", "message_id", "body"],
)
CONV_PATCH = mcp_schema(
    {
        "conversation_id": {"type": "integer", "minimum": 1},
        "status": {"type": "string", "enum": ["open", "pending", "resolved"]},
        "assigned_to_user_id": {"type": ["integer", "null"], "minimum": 1},
        "lead_id": {"type": ["integer", "null"], "minimum": 1},
        "person_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["conversation_id"],
)
READ_SCHEMA = mcp_schema(
    {
        "conversation_id": {"type": "integer", "minimum": 1},
        "up_to_message_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["conversation_id"],
)
BULK_DEL = mcp_schema({"status": {"type": "string", "enum": ["open", "pending", "resolved"]}})


def get_crm_web_chat_settings_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    s = mcp_run(chat_svc.get_or_create_crm_settings, mcp_db(context), mcp_bid(context))
    return mcp_jsonable(chat_svc.business_crm_settings_to_dict(s))


def update_crm_web_chat_settings_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    s = mcp_run(
        chat_svc.update_crm_business_settings,
        mcp_db(context),
        mcp_bid(context),
        allow_web_chat_file_upload=args.get("allow_web_chat_file_upload"),
        allow_web_chat_voice=args.get("allow_web_chat_voice"),
    )
    return mcp_jsonable(chat_svc.business_crm_settings_to_dict(s))


def list_crm_chat_widgets_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    rows = mcp_run(chat_svc.list_widgets, mcp_db(context), mcp_bid(context))
    return {"items": mcp_jsonable([chat_svc.widget_to_dict(w) for w in rows])}


def create_crm_chat_widget_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    w = mcp_run(
        chat_svc.create_widget,
        mcp_db(context),
        mcp_bid(context),
        args["name"],
        args.get("allowed_origins"),
        None,
        bool(args.get("is_active", True)),
    )
    return mcp_jsonable(chat_svc.widget_to_dict(w))


def update_crm_chat_widget_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    w = mcp_run(
        chat_svc.update_widget,
        mcp_db(context),
        mcp_bid(context),
        int(args["widget_id"]),
        name=args.get("name"),
        allowed_origins=args.get("allowed_origins"),
        is_active=args.get("is_active"),
    )
    return mcp_jsonable(chat_svc.widget_to_dict(w))


def list_crm_chat_conversations_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    items, has_more = mcp_run(
        chat_svc.list_conversations_agent,
        mcp_db(context),
        mcp_bid(context),
        status=args.get("status"),
        limit=int(args.get("limit") or 50),
        offset=int(args.get("offset") or 0),
        search=args.get("search"),
    )
    return mcp_jsonable({"items": items, "has_more": has_more})


def list_crm_chat_messages_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    items, has_more_older = mcp_run(
        chat_svc.list_messages_agent,
        mcp_db(context),
        mcp_bid(context),
        int(args["conversation_id"]),
        limit=int(args.get("limit") or 80),
        before_message_id=args.get("before_message_id"),
    )
    return mcp_jsonable({"items": items, "has_more_older": has_more_older})


def send_crm_chat_agent_message_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    body = (args.get("body") or "").strip() or None
    fid = (args.get("file_storage_id") or "").strip() or None
    if not body and not fid:
        raise ValueError("متن پیام یا file_storage_id الزامی است.")
    return mcp_jsonable(
        mcp_await(
            chat_svc.post_agent_message(
                mcp_db(context),
                business_id=mcp_bid(context),
                conversation_id=int(args["conversation_id"]),
                body=body,
                user_id=mcp_uid(context),
                file_storage_id=fid,
            )
        )
    )


def update_crm_chat_agent_message_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    return mcp_jsonable(
        mcp_await(
            chat_svc.patch_agent_message(
                mcp_db(context),
                mcp_bid(context),
                int(args["conversation_id"]),
                int(args["message_id"]),
                body=str(args["body"]),
            )
        )
    )


def update_crm_chat_conversation_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    return mcp_jsonable(
        mcp_await(
            chat_svc.patch_conversation_agent(
                mcp_db(context),
                mcp_bid(context),
                int(args["conversation_id"]),
                status=args.get("status"),
                assigned_to_user_id=args.get("assigned_to_user_id"),
                lead_id=args.get("lead_id"),
                person_id=args.get("person_id"),
                acting_user_id=mcp_uid(context),
            )
        )
    )


def mark_crm_chat_read_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    user = context.get("user_context")
    reading_user = getattr(user, "user", None) or user
    return mcp_jsonable(
        mcp_await(
            chat_svc.mark_messages_read_by_agent(
                mcp_db(context),
                business_id=mcp_bid(context),
                conversation_id=int(args["conversation_id"]),
                up_to_message_id=args.get("up_to_message_id"),
                reading_user=reading_user,
            )
        )
    )


def delete_crm_chat_conversation_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    return mcp_jsonable(
        mcp_await(chat_svc.delete_conversation_agent(mcp_db(context), mcp_bid(context), int(args["conversation_id"])))
    )


def delete_crm_chat_conversations_bulk_handler(args, context):
    from app.services import crm_chat_service as chat_svc

    return mcp_jsonable(
        mcp_await(chat_svc.delete_conversations_bulk_agent(mcp_db(context), mcp_bid(context), status=args.get("status")))
    )


def register_mcp_crm_chat_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="get_crm_web_chat_settings",
        description="تنظیمات آپلود فایل و پیام صوتی چت وب CRM کسب‌وکار متصل.",
        parameters_schema=EMPTY,
        handler=get_crm_web_chat_settings_handler,
        allowed_roles=roles,
        required_permissions=["crm.view"],
        category="crm",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="update_crm_web_chat_settings",
        description="فعال/غیرفعال کردن آپلود فایل و ویس در چت وب. نیازمند تأیید.",
        parameters_schema=SETTINGS_UPDATE,
        handler=update_crm_web_chat_settings_handler,
        allowed_roles=roles,
        required_permissions=["crm.write"],
        category="crm",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_crm_chat_widgets",
        description="ویجت‌های چت وب کسب‌وکار متصل شامل public_key برای جاسازی.",
        parameters_schema=EMPTY,
        handler=list_crm_chat_widgets_handler,
        allowed_roles=roles,
        required_permissions=["crm.view"],
        category="crm",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_crm_chat_widget",
        description="ایجاد ویجت چت وب با مبدأهای مجاز. نیازمند تأیید.",
        parameters_schema=WIDGET_CREATE,
        handler=create_crm_chat_widget_handler,
        allowed_roles=roles,
        required_permissions=["crm.write"],
        category="crm",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_crm_chat_widget",
        description="ویرایش نام، مبدأهای مجاز یا وضعیت ویجت چت وب. نیازمند تأیید.",
        parameters_schema=WIDGET_UPDATE,
        handler=update_crm_chat_widget_handler,
        allowed_roles=roles,
        required_permissions=["crm.write"],
        category="crm",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_crm_chat_conversations",
        description="مکالمات چت وب کسب‌وکار متصل با فیلتر وضعیت و جستجو.",
        parameters_schema=CONV_LIST,
        handler=list_crm_chat_conversations_handler,
        allowed_roles=roles,
        required_permissions=["crm.view"],
        category="crm",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="list_crm_chat_messages",
        description="پیام‌های یک مکالمه چت وب متعلق به کسب‌وکار متصل.",
        parameters_schema=MSG_LIST,
        handler=list_crm_chat_messages_handler,
        allowed_roles=roles,
        required_permissions=["crm.view"],
        category="crm",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="send_crm_chat_agent_message",
        description="ارسال پاسخ اپراتور به مکالمه چت وب. نیازمند تأیید.",
        parameters_schema=MSG_SEND,
        handler=send_crm_chat_agent_message_handler,
        allowed_roles=roles,
        required_permissions=["crm.write"],
        category="crm",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_crm_chat_agent_message",
        description="ویرایش متن پیام اپراتور در مکالمه چت وب. نیازمند تأیید.",
        parameters_schema=MSG_PATCH,
        handler=update_crm_chat_agent_message_handler,
        allowed_roles=roles,
        required_permissions=["crm.write"],
        category="crm",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_crm_chat_conversation",
        description="تغییر وضعیت، مسئول، سرنخ یا شخص مکالمه چت وب. نیازمند تأیید.",
        parameters_schema=CONV_PATCH,
        handler=update_crm_chat_conversation_handler,
        allowed_roles=roles,
        required_permissions=["crm.write"],
        category="crm",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="mark_crm_chat_read",
        description="علامت خوانده‌شدن پیام‌های مکالمه چت وب تا شناسه مشخص.",
        parameters_schema=READ_SCHEMA,
        handler=mark_crm_chat_read_handler,
        allowed_roles=roles,
        required_permissions=["crm.view"],
        category="crm",
        is_readonly=False,
        requires_approval=True,
        risk_level="medium",
    ))
    registry.register(AIFunction(
        name="delete_crm_chat_conversation",
        description="حذف یک مکالمه چت وب. نیازمند تأیید.",
        parameters_schema=CONV_ID,
        handler=delete_crm_chat_conversation_handler,
        allowed_roles=roles,
        required_permissions=["crm.write"],
        category="crm",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_crm_chat_conversations_bulk",
        description="حذف دسته‌ای مکالمات چت وب، اختیاری فقط یک وضعیت. نیازمند تأیید.",
        parameters_schema=BULK_DEL,
        handler=delete_crm_chat_conversations_bulk_handler,
        allowed_roles=roles,
        required_permissions=["crm.write"],
        category="crm",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
