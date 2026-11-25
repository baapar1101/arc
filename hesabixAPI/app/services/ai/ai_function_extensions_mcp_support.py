"""Platform support-desk MCP tools. Not tenant-bound; OPERATOR/ADMIN only."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.services.ai.ai_mcp_tool_util import mcp_db, mcp_jsonable, mcp_raise, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
TICKET_ID = mcp_schema({"ticket_id": {"type": "integer", "minimum": 1}}, ["ticket_id"])
SEARCH = mcp_schema(
    {
        "search": {"type": "string", "maxLength": 200},
        "status_id": {"type": "integer", "minimum": 1},
        "priority_id": {"type": "integer", "minimum": 1},
        "category_id": {"type": "integer", "minimum": 1},
        "assigned_operator_id": {"type": "integer", "minimum": 1},
        "unassigned": {"type": "boolean"},
        "unread": {"type": "boolean"},
        "sla_breached": {"type": "boolean"},
        "open_only": {"type": "boolean", "description": "پیش‌فرض true؛ فقط تیکت‌های باز"},
        "take": {"type": "integer", "minimum": 1, "maximum": 50},
        "skip": {"type": "integer", "minimum": 0},
        "sort_by": {
            "type": "string",
            "enum": ["last_message_at", "created_at", "updated_at", "id", "priority_id"],
        },
        "sort_desc": {"type": "boolean"},
    }
)
MESSAGES = mcp_schema(
    {
        "ticket_id": {"type": "integer", "minimum": 1},
        "search": {"type": "string", "maxLength": 200},
        "take": {"type": "integer", "minimum": 1, "maximum": 50},
        "skip": {"type": "integer", "minimum": 0},
    },
    ["ticket_id"],
)
HISTORY = mcp_schema(
    {
        "ticket_user_id": {
            "type": "integer",
            "minimum": 1,
            "description": "شناسه کاربر صاحب تیکت؛ هویت اپراتور از اتصال گرفته می‌شود",
        },
        "take": {"type": "integer", "minimum": 1, "maximum": 20},
    },
    ["ticket_user_id"],
)
ACTIVITY = mcp_schema({"days": {"type": "integer", "minimum": 1, "maximum": 30}})
OVERDUE = mcp_schema({"limit": {"type": "integer", "minimum": 1, "maximum": 50}})
REPLY = mcp_schema(
    {
        "ticket_id": {"type": "integer", "minimum": 1},
        "content": {"type": "string", "minLength": 1, "maxLength": 8000},
    },
    ["ticket_id", "content"],
)
ASSIGN = mcp_schema(
    {
        "ticket_id": {"type": "integer", "minimum": 1},
        "operator_id": {"type": "integer", "minimum": 1},
    },
    ["ticket_id", "operator_id"],
)
STATUS = mcp_schema(
    {
        "ticket_id": {"type": "integer", "minimum": 1},
        "status_id": {"type": "integer", "minimum": 1},
        "assigned_operator_id": {"type": "integer", "minimum": 1},
    },
    ["ticket_id", "status_id"],
)
PRIORITY = mcp_schema(
    {
        "ticket_id": {"type": "integer", "minimum": 1},
        "priority_id": {"type": "integer", "minimum": 1},
    },
    ["ticket_id", "priority_id"],
)
BULK_ASSIGN = mcp_schema(
    {
        "ticket_ids": {
            "type": "array",
            "minItems": 1,
            "maxItems": 20,
            "items": {"type": "integer", "minimum": 1},
            "uniqueItems": True,
        },
        "operator_id": {"type": "integer", "minimum": 1},
    },
    ["ticket_ids", "operator_id"],
)
BULK_STATUS = mcp_schema(
    {
        "ticket_ids": {
            "type": "array",
            "minItems": 1,
            "maxItems": 20,
            "items": {"type": "integer", "minimum": 1},
            "uniqueItems": True,
        },
        "status_id": {"type": "integer", "minimum": 1},
    },
    ["ticket_ids", "status_id"],
)


def _actor(context: Dict[str, Any]):
    user = context.get("user_context")
    if user is None:
        raise ValueError("هویت اپراتور موجود نیست")
    return user


def _run(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception as exc:
        mcp_raise(exc)


def _iso(value: Any) -> Optional[str]:
    return value.isoformat() if value is not None and hasattr(value, "isoformat") else None


def _user_brief(user: Any) -> Optional[Dict[str, Any]]:
    if user is None:
        return None
    name = f"{getattr(user, 'first_name', None) or ''} {getattr(user, 'last_name', None) or ''}".strip()
    return {
        "id": user.id,
        "name": name or None,
        "email": getattr(user, "email", None),
    }


def _ticket_brief(ticket: Any, *, include_email: bool = False) -> Dict[str, Any]:
    user = _user_brief(ticket.user) if getattr(ticket, "user", None) else {"id": ticket.user_id}
    if user and not include_email:
        user = {k: v for k, v in user.items() if k != "email"}
    operator = _user_brief(ticket.assigned_operator) if getattr(ticket, "assigned_operator", None) else None
    if operator:
        operator = {k: v for k, v in operator.items() if k != "email"}
    return {
        "id": ticket.id,
        "title": ticket.title,
        "user": user,
        "category": ticket.category.name if ticket.category else None,
        "priority": ticket.priority.name if ticket.priority else None,
        "status": ticket.status.name if ticket.status else None,
        "status_is_final": bool(ticket.status.is_final) if ticket.status else None,
        "assigned_operator": operator,
        "sla_breached": bool(ticket.sla_breached),
        "first_response_due_at": _iso(ticket.first_response_due_at),
        "resolution_due_at": _iso(ticket.resolution_due_at),
        "last_message_at": _iso(ticket.last_message_at),
        "created_at": _iso(ticket.created_at),
        "updated_at": _iso(ticket.updated_at),
    }


def _message_brief(message: Any) -> Dict[str, Any]:
    sender_type = message.sender_type
    if hasattr(sender_type, "value"):
        sender_type = sender_type.value
    sender = _user_brief(message.sender) if getattr(message, "sender", None) else None
    if sender:
        sender = {k: v for k, v in sender.items() if k != "email"}
    return {
        "id": message.id,
        "ticket_id": message.ticket_id,
        "sender_type": sender_type,
        "sender": sender,
        "content": message.content,
        "is_internal": bool(message.is_internal),
        "created_at": _iso(message.created_at),
    }


def search_support_tickets_handler(args, context):
    from adapters.api.v1.schemas import FilterItem, QueryInfo
    from adapters.db.models.support.status import Status
    from adapters.db.repositories.support.ticket_repository import TicketRepository

    db = mcp_db(context)
    filters: List[FilterItem] = []
    if args.get("status_id"):
        filters.append(FilterItem(property="status_id", operator="==", value=int(args["status_id"])))
    if args.get("priority_id"):
        filters.append(FilterItem(property="priority_id", operator="==", value=int(args["priority_id"])))
    if args.get("category_id"):
        filters.append(FilterItem(property="category_id", operator="==", value=int(args["category_id"])))
    if args.get("unassigned") is True:
        filters.append(FilterItem(property="assigned_operator_id", operator="is_null", value=None))
    elif args.get("assigned_operator_id"):
        filters.append(
            FilterItem(property="assigned_operator_id", operator="==", value=int(args["assigned_operator_id"]))
        )
    if args.get("unread") is True:
        filters.append(FilterItem(property="is_unread_for_operator", operator="==", value=True))
    if args.get("sla_breached") is True:
        filters.append(FilterItem(property="sla_breached", operator="==", value=True))
    open_only = args.get("open_only")
    if open_only is not False and not args.get("status_id"):
        open_ids = [row.id for row in db.query(Status).filter(Status.is_final.is_(False)).all()]
        if open_ids:
            filters.append(FilterItem(property="status_id", operator="in", value=open_ids))
    query = QueryInfo(
        search=(args.get("search") or None),
        search_fields=["title", "description", "user_email", "user_name"],
        take=int(args.get("take") or 20),
        skip=int(args.get("skip") or 0),
        sort_by=str(args.get("sort_by") or "last_message_at"),
        sort_desc=bool(args.get("sort_desc", True)),
        filters=filters or None,
    )
    tickets, total = TicketRepository(db).get_operator_tickets(query)
    return mcp_jsonable({"total": total, "items": [_ticket_brief(ticket) for ticket in tickets]})


def get_support_ticket_handler(args, context):
    from adapters.db.repositories.support.ticket_repository import TicketRepository
    from app.services.support.ticket_event_service import TicketEventService

    db = mcp_db(context)
    ticket = TicketRepository(db).get_operator_ticket_with_details(int(args["ticket_id"]))
    if not ticket:
        raise ValueError("تیکت یافت نشد")
    payload = _ticket_brief(ticket, include_email=True)
    payload["description"] = ticket.description
    payload["closed_at"] = _iso(ticket.closed_at)
    payload["first_responded_at"] = _iso(ticket.first_responded_at)
    payload["csat_rating"] = ticket.csat_rating
    payload["csat_comment"] = ticket.csat_comment
    try:
        from adapters.api.v1.support.ticket_serialize import attach_support_subscription as attach_sub

        attach_sub(payload, db, ticket.user_id)
    except Exception:
        payload["support_subscription"] = None
    messages = list(ticket.messages or [])
    payload["messages"] = [_message_brief(item) for item in messages[-40:]]
    payload["message_count"] = len(messages)
    events = TicketEventService(db).list_for_ticket(ticket.id)
    payload["events"] = [
        {
            "id": event.id,
            "event_type": event.event_type,
            "actor_id": event.actor_id,
            "old_value": event.old_value,
            "new_value": event.new_value,
            "created_at": _iso(event.created_at),
        }
        for event in events[-30:]
    ]
    return mcp_jsonable(payload)


def list_support_ticket_messages_handler(args, context):
    from adapters.api.v1.schemas import QueryInfo
    from adapters.db.repositories.support.message_repository import MessageRepository
    from app.services.support.ticket_access_service import TicketAccessService

    db = mcp_db(context)
    _run(TicketAccessService(db).get_operator_ticket, int(args["ticket_id"]))
    query = QueryInfo(
        search=(args.get("search") or None),
        search_fields=["content"],
        take=int(args.get("take") or 30),
        skip=int(args.get("skip") or 0),
        sort_by="created_at",
        sort_desc=False,
    )
    messages, total = MessageRepository(db).get_ticket_messages(int(args["ticket_id"]), query)
    return mcp_jsonable({"total": total, "items": [_message_brief(item) for item in messages]})


def list_support_ticket_events_handler(args, context):
    from app.services.support.ticket_access_service import TicketAccessService
    from app.services.support.ticket_event_service import TicketEventService

    db = mcp_db(context)
    _run(TicketAccessService(db).get_operator_ticket, int(args["ticket_id"]))
    events = TicketEventService(db).list_for_ticket(int(args["ticket_id"]))
    return mcp_jsonable(
        {
            "items": [
                {
                    "id": event.id,
                    "event_type": event.event_type,
                    "actor_id": event.actor_id,
                    "old_value": event.old_value,
                    "new_value": event.new_value,
                    "created_at": _iso(event.created_at),
                }
                for event in events
            ]
        }
    )


def get_support_dashboard_stats_handler(args, context):
    from app.services.support.support_dashboard_service import SupportDashboardService

    return mcp_jsonable(SupportDashboardService(mcp_db(context)).get_stats(mcp_uid(context)))


def list_overdue_support_tickets_handler(args, context):
    from app.services.support.support_dashboard_service import SupportDashboardService

    items = SupportDashboardService(mcp_db(context)).get_overdue_tickets(limit=int(args.get("limit") or 20))
    return mcp_jsonable({"items": items})


def list_support_activity_handler(args, context):
    from app.services.support.support_dashboard_service import SupportDashboardService

    return mcp_jsonable({"items": SupportDashboardService(mcp_db(context)).get_activity(days=int(args.get("days") or 7))})


def get_user_support_ticket_history_handler(args, context):
    from app.services.support.support_dashboard_service import SupportDashboardService

    items = SupportDashboardService(mcp_db(context)).get_user_ticket_history(
        int(args["ticket_user_id"]),
        take=int(args.get("take") or 5),
    )
    return mcp_jsonable({"items": items})


def list_support_operators_handler(args, context):
    from adapters.db.repositories.user_repo import UserRepository

    operators = UserRepository(mcp_db(context)).get_support_operators()
    return mcp_jsonable(
        {
            "items": [
                {
                    "id": op.id,
                    "name": f"{op.first_name or ''} {op.last_name or ''}".strip() or None,
                    "email": op.email,
                }
                for op in operators
            ]
        }
    )


def list_support_categories_handler(args, context):
    from adapters.db.repositories.support.category_repository import CategoryRepository

    items = CategoryRepository(mcp_db(context)).get_active_categories()
    return mcp_jsonable({"items": [{"id": row.id, "name": row.name, "description": row.description} for row in items]})


def list_support_priorities_handler(args, context):
    from adapters.db.repositories.support.priority_repository import PriorityRepository

    items = PriorityRepository(mcp_db(context)).get_priorities_ordered()
    return mcp_jsonable(
        {"items": [{"id": row.id, "name": row.name, "order": row.order, "color": row.color} for row in items]}
    )


def list_support_statuses_handler(args, context):
    from adapters.db.repositories.support.status_repository import StatusRepository

    items = StatusRepository(mcp_db(context)).get_all_statuses()
    return mcp_jsonable(
        {"items": [{"id": row.id, "name": row.name, "is_final": bool(row.is_final), "color": row.color} for row in items]}
    )


def list_support_response_templates_handler(args, context):
    from adapters.db.repositories.support.response_template_repository import ResponseTemplateRepository

    items = ResponseTemplateRepository(mcp_db(context)).list_active()
    return mcp_jsonable(
        {
            "items": [
                {
                    "id": row.id,
                    "name": row.name,
                    "content": row.content,
                    "category_id": row.category_id,
                    "usage_count": row.usage_count,
                }
                for row in items
            ]
        }
    )


def reply_support_ticket_handler(args, context):
    from app.services.support.operator_ticket_actions import reply_as_operator

    actor = _actor(context)
    return mcp_jsonable(
        _run(
            reply_as_operator,
            mcp_db(context),
            ticket_id=int(args["ticket_id"]),
            actor_id=mcp_uid(context),
            actor_user=getattr(actor, "user", actor),
            content=str(args["content"]),
            is_internal=False,
        )
    )


def add_support_internal_note_handler(args, context):
    from app.services.support.operator_ticket_actions import reply_as_operator

    actor = _actor(context)
    return mcp_jsonable(
        _run(
            reply_as_operator,
            mcp_db(context),
            ticket_id=int(args["ticket_id"]),
            actor_id=mcp_uid(context),
            actor_user=getattr(actor, "user", actor),
            content=str(args["content"]),
            is_internal=True,
        )
    )


def assign_support_ticket_handler(args, context):
    from app.services.support.operator_ticket_actions import assign_ticket

    return mcp_jsonable(
        _run(
            assign_ticket,
            mcp_db(context),
            ticket_id=int(args["ticket_id"]),
            operator_id=int(args["operator_id"]),
            actor_id=mcp_uid(context),
        )
    )


def update_support_ticket_status_handler(args, context):
    from app.services.support.operator_ticket_actions import update_status

    actor = _actor(context)
    return mcp_jsonable(
        _run(
            update_status,
            mcp_db(context),
            ticket_id=int(args["ticket_id"]),
            status_id=int(args["status_id"]),
            actor_id=mcp_uid(context),
            actor_user=getattr(actor, "user", actor),
            assigned_operator_id=int(args["assigned_operator_id"]) if args.get("assigned_operator_id") else None,
        )
    )


def update_support_ticket_priority_handler(args, context):
    from app.services.support.operator_ticket_actions import update_priority

    return mcp_jsonable(
        _run(
            update_priority,
            mcp_db(context),
            ticket_id=int(args["ticket_id"]),
            priority_id=int(args["priority_id"]),
            actor_id=mcp_uid(context),
        )
    )


def mark_support_ticket_read_handler(args, context):
    from app.services.support.operator_ticket_actions import mark_read

    return mcp_jsonable(_run(mark_read, mcp_db(context), ticket_id=int(args["ticket_id"])))


def bulk_assign_support_tickets_handler(args, context):
    from app.services.support.operator_ticket_actions import bulk_assign

    return mcp_jsonable(
        _run(
            bulk_assign,
            mcp_db(context),
            ticket_ids=list(args["ticket_ids"]),
            operator_id=int(args["operator_id"]),
        )
    )


def bulk_update_support_ticket_status_handler(args, context):
    from app.services.support.operator_ticket_actions import bulk_update_status

    actor = _actor(context)
    return mcp_jsonable(
        _run(
            bulk_update_status,
            mcp_db(context),
            ticket_ids=list(args["ticket_ids"]),
            status_id=int(args["status_id"]),
            actor_id=mcp_uid(context),
            actor_user=getattr(actor, "user", actor),
        )
    )


def register_mcp_support_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="search_support_tickets", description="جستجو و فیلتر تیکت‌های پشتیبانی پلتفرم برای اپراتور؛ پیش‌فرض فقط تیکت‌های باز.", parameters_schema=SEARCH, handler=search_support_tickets_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="get_support_ticket", description="جزئیات کامل یک تیکت پشتیبانی شامل شرح، پیام‌ها، رویدادها و اشتراک پشتیبانی.", parameters_schema=TICKET_ID, handler=get_support_ticket_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_support_ticket_messages", description="فهرست صفحه‌بندی‌شده پیام‌های یک تیکت پشتیبانی شامل یادداشت‌های داخلی اپراتور.", parameters_schema=MESSAGES, handler=list_support_ticket_messages_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_support_ticket_events", description="تاریخچه رویدادهای یک تیکت پشتیبانی مانند تخصیص، تغییر وضعیت و بستن.", parameters_schema=TICKET_ID, handler=list_support_ticket_events_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="get_support_dashboard_stats", description="آمار میز پشتیبانی: تیکت‌های باز، تخصیص‌شده، نخوانده، تأخیری و حل‌شده امروز.", parameters_schema=EMPTY, handler=get_support_dashboard_stats_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_overdue_support_tickets", description="تیکت‌های باز که از موعد SLA عبور کرده‌اند، مرتب‌شده بر اساس قدیمی‌ترین تأخیر.", parameters_schema=OVERDUE, handler=list_overdue_support_tickets_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_support_activity", description="تعداد تیکت ایجادشده و حل‌شده به‌ازای هر روز در بازه حداکثر ۳۰ روز.", parameters_schema=ACTIVITY, handler=list_support_activity_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="get_user_support_ticket_history", description="تاریخچه اخیر تیکت‌های پشتیبانی یک کاربر مشخص برای زمینه پاسخ‌گویی.", parameters_schema=HISTORY, handler=get_user_support_ticket_history_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_support_operators", description="فهرست اپراتورها و مدیران سیستم که مجوز میز پشتیبانی دارند.", parameters_schema=EMPTY, handler=list_support_operators_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_support_categories", description="دسته‌بندی‌های فعال تیکت پشتیبانی برای فیلتر و درک موضوع تیکت.", parameters_schema=EMPTY, handler=list_support_categories_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_support_priorities", description="اولویت‌های تعریف‌شده تیکت پشتیبانی به ترتیب نمایش.", parameters_schema=EMPTY, handler=list_support_priorities_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_support_statuses", description="وضعیت‌های تیکت پشتیبانی شامل وضعیت‌های نهایی مثل بسته‌شده.", parameters_schema=EMPTY, handler=list_support_statuses_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="list_support_response_templates", description="قالب‌های آماده پاسخ پشتیبانی برای استفاده در پیش‌نویس یا ارسال پاسخ.", parameters_schema=EMPTY, handler=list_support_response_templates_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", is_readonly=True))
    registry.register(AIFunction(name="reply_support_ticket", description="ارسال پاسخ عمومی اپراتور به کاربر تیکت؛ تیکت در صورت عدم تخصیص به همین اپراتور اختصاص می‌یابد.", parameters_schema=REPLY, handler=reply_support_ticket_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="add_support_internal_note", description="افزودن یادداشت داخلی روی تیکت که برای کاربر نهایی نمایش داده نمی‌شود.", parameters_schema=REPLY, handler=add_support_internal_note_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="assign_support_ticket", description="تخصیص تیکت پشتیبانی به یک اپراتور فعال میز پشتیبانی.", parameters_schema=ASSIGN, handler=assign_support_ticket_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="update_support_ticket_status", description="تغییر وضعیت تیکت پشتیبانی و در صورت نیاز تخصیص به اپراتور جاری.", parameters_schema=STATUS, handler=update_support_ticket_status_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="update_support_ticket_priority", description="تغییر اولویت یک تیکت پشتیبانی پس از بررسی محتوا و SLA.", parameters_schema=PRIORITY, handler=update_support_ticket_priority_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="mark_support_ticket_read", description="علامت‌گذاری تیکت به‌عنوان خوانده‌شده توسط اپراتور متصل.", parameters_schema=TICKET_ID, handler=mark_support_ticket_read_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="bulk_assign_support_tickets", description="تخصیص گروهی حداکثر ۲۰ تیکت پشتیبانی به یک اپراتور. نیازمند تأیید.", parameters_schema=BULK_ASSIGN, handler=bulk_assign_support_tickets_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="bulk_update_support_ticket_status", description="تغییر وضعیت گروهی حداکثر ۲۰ تیکت پشتیبانی. نیازمند تأیید.", parameters_schema=BULK_STATUS, handler=bulk_update_support_ticket_status_handler, allowed_roles=roles, required_permissions=["support_operator"], business_context_required=False, category="support", requires_approval=True, risk_level="high", is_readonly=False))
