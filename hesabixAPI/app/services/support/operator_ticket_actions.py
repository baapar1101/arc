"""Shared operator ticket commands used by the HTTP API side-effects and MCP tools."""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.api.v1.support.message_helpers import serialize_message
from adapters.api.v1.support.ticket_serialize import ticket_response_dict, ticket_to_dict
from adapters.db.models.support.message import SenderType
from adapters.db.models.support.ticket import Ticket
from adapters.db.repositories.support.attachment_repository import AttachmentRepository
from adapters.db.repositories.support.message_repository import MessageRepository
from adapters.db.repositories.support.ticket_repository import TicketRepository
from adapters.db.repositories.user_repo import UserRepository
from app.core.responses import ApiError
from app.services.notification_service import NotificationService
from app.services.support.notification_helpers import (
    support_notification_context,
    support_operator_notification_context,
    resolve_announcement_navigation,
)
from app.services.support.ticket_access_service import TicketAccessService
from app.services.support.ticket_engagement_service import mark_operator_read
from app.services.support.ticket_lifecycle_service import TicketLifecycleService

logger = logging.getLogger(__name__)

BULK_LIMIT = 20
REPLY_MAX_CHARS = 8000


def _operator_display_name(user: Any) -> str:
    first = getattr(user, "first_name", None) or ""
    last = getattr(user, "last_name", None) or ""
    return f"{first} {last}".strip() or "اپراتور پشتیبانی"


def _notify_user_reply(db: Session, ticket: Ticket, operator_name: str, content: str) -> None:
    if not ticket.user_id:
        return
    try:
        from app.services.support.support_sla_service import SupportSlaService

        SupportSlaService(db).mark_first_response(ticket)
        preview = content[:200] + ("..." if len(content) > 200 else "")
        context = support_notification_context(
            {
                "subject": f"پاسخ جدید به تیکت #{ticket.id}",
                "message": f"اپراتور {operator_name} به تیکت شما پاسخ داد:\n\n{preview}",
                "ticket_id": ticket.id,
                "ticket_title": ticket.title,
                "operator_name": operator_name,
                "message_preview": preview,
            },
            ticket.id,
        )
        NotificationService(db).send(
            user_id=ticket.user_id,
            event_key="support.operator_reply",
            context=context,
            preferred_channels=["inapp", "email", "telegram", "sms"],
            broadcast_mode=False,
        )
    except Exception:
        logger.exception("failed to notify user about operator reply ticket_id=%s", ticket.id)


def _broadcast_message(db: Session, ticket: Ticket, message_id: int, preview: str) -> None:
    try:
        from app.services.support.support_broadcast import broadcast_message_created

        broadcast_message_created(
            db,
            ticket,
            sender_type="operator",
            message_id=message_id,
            preview=preview,
        )
    except Exception:
        logger.debug("support broadcast skipped ticket_id=%s", ticket.id, exc_info=True)


def _notify_assigned(db: Session, ticket: Ticket, operator_id: int) -> None:
    try:
        operator = UserRepository(db).get_by_id(operator_id)
        operator_name = _operator_display_name(operator) if operator else "اپراتور پشتیبانی"
        context = support_operator_notification_context(
            {
                "subject": f"تیکت جدید به شما تخصیص داده شد: #{ticket.id}",
                "message": f"تیکت #{ticket.id}: {ticket.title} به شما تخصیص داده شد.",
                "ticket_title": ticket.title,
                "operator_name": operator_name,
                "user_id": ticket.user_id,
            },
            ticket.id,
        )
        NotificationService(db).send(
            user_id=operator_id,
            event_key="support.ticket_assigned",
            context=context,
            preferred_channels=["inapp", "email", "telegram"],
            broadcast_mode=False,
        )
    except Exception:
        logger.exception("failed to notify operator assignment ticket_id=%s", ticket.id)


def _notify_status_changed(db: Session, ticket: Ticket, operator_name: str, old_status: str, new_status: str) -> None:
    if not ticket.user_id:
        return
    try:
        context = support_notification_context(
            {
                "subject": f"وضعیت تیکت #{ticket.id} تغییر کرد",
                "message": (
                    f"وضعیت تیکت شما (#{ticket.id}: {ticket.title}) "
                    f"از '{old_status}' به '{new_status}' تغییر کرد."
                ),
                "ticket_id": ticket.id,
                "ticket_title": ticket.title,
                "operator_name": operator_name,
                "old_status": old_status,
                "new_status": new_status,
                "user_id": ticket.user_id,
            },
            ticket.id,
        )
        NotificationService(db).send(
            user_id=ticket.user_id,
            event_key="support.ticket_status_changed",
            context=context,
            preferred_channels=["inapp", "email", "telegram"],
            broadcast_mode=False,
        )
    except Exception:
        logger.exception("failed to notify status change ticket_id=%s", ticket.id)


def reply_as_operator(
    db: Session,
    *,
    ticket_id: int,
    actor_id: int,
    actor_user: Any,
    content: str,
    is_internal: bool = False,
) -> Dict[str, Any]:
    access = TicketAccessService(db)
    ticket = access.get_operator_ticket(ticket_id)
    if not is_internal:
        access.assert_ticket_open(ticket)
    text = (content or "").strip()
    if not text:
        raise ApiError("EMPTY_MESSAGE", "متن پیام الزامی است", http_status=400)
    if len(text) > REPLY_MAX_CHARS:
        raise ApiError("MESSAGE_TOO_LONG", f"متن پیام حداکثر {REPLY_MAX_CHARS} کاراکتر است", http_status=400)

    message = MessageRepository(db).create_message(
        ticket_id=ticket_id,
        sender_id=actor_id,
        sender_type=SenderType.OPERATOR,
        content=text,
        is_internal=is_internal,
    )
    if not ticket.assigned_operator_id:
        TicketRepository(db).assign_ticket(ticket_id, actor_id)

    operator_name = _operator_display_name(actor_user)
    if not is_internal:
        _notify_user_reply(db, ticket, operator_name, text)
        _broadcast_message(db, ticket, message.id, text)

    return serialize_message(message, AttachmentRepository(db))


def assign_ticket(
    db: Session,
    *,
    ticket_id: int,
    operator_id: int,
    actor_id: int,
) -> Dict[str, Any]:
    user_repo = UserRepository(db)
    if not user_repo.is_support_operator(operator_id):
        raise ApiError("INVALID_OPERATOR", "کاربر مشخص‌شده اپراتور پشتیبانی نیست", http_status=400)
    ticket_repo = TicketRepository(db)
    old = ticket_repo.get_operator_ticket_with_details(ticket_id)
    if not old:
        raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)
    old_operator_id = old.assigned_operator_id
    updated = TicketLifecycleService(db).assign(ticket_id, operator_id, actor_id)
    try:
        from app.services.support.support_broadcast import broadcast_ticket_updated

        broadcast_ticket_updated(db, updated, changes={"assigned_operator_id": operator_id})
    except Exception:
        logger.debug("assign broadcast skipped ticket_id=%s", ticket_id, exc_info=True)
    if operator_id and operator_id != old_operator_id:
        _notify_assigned(db, updated, operator_id)
    return ticket_response_dict(updated, db)


def update_status(
    db: Session,
    *,
    ticket_id: int,
    status_id: int,
    actor_id: int,
    actor_user: Any,
    assigned_operator_id: Optional[int] = None,
) -> Dict[str, Any]:
    ticket_repo = TicketRepository(db)
    old = ticket_repo.get_operator_ticket_with_details(ticket_id)
    if not old:
        raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)
    old_status_name = old.status.name if old.status else "نامشخص"
    assignee = assigned_operator_id or actor_id
    updated = TicketLifecycleService(db).update_status(
        ticket_id=ticket_id,
        status_id=status_id,
        actor_id=actor_id,
        assigned_operator_id=assignee,
    )
    new_status_name = updated.status.name if updated.status else "نامشخص"
    if old.status_id != status_id:
        _notify_status_changed(db, updated, _operator_display_name(actor_user), old_status_name, new_status_name)
    return ticket_response_dict(updated, db)


def update_priority(db: Session, *, ticket_id: int, priority_id: int, actor_id: int) -> Dict[str, Any]:
    updated = TicketLifecycleService(db).update_priority(ticket_id, priority_id, actor_id)
    return ticket_response_dict(updated, db)


def mark_read(db: Session, *, ticket_id: int) -> Dict[str, Any]:
    ticket = TicketAccessService(db).get_operator_ticket(ticket_id)
    mark_operator_read(db, ticket)
    return ticket_to_dict(ticket, db)


def bulk_assign(db: Session, *, ticket_ids: List[int], operator_id: int) -> Dict[str, Any]:
    ids = _unique_ticket_ids(ticket_ids)
    user_repo = UserRepository(db)
    if not user_repo.is_support_operator(operator_id):
        raise ApiError("INVALID_OPERATOR", "کاربر مشخص‌شده اپراتور پشتیبانی نیست", http_status=400)
    ticket_repo = TicketRepository(db)
    existing = ticket_repo.db.query(Ticket).filter(Ticket.id.in_(ids)).count()
    if existing != len(ids):
        raise ApiError("TICKETS_NOT_FOUND", "برخی از تیکت‌ها یافت نشدند", http_status=400)
    updated_count = ticket_repo.bulk_assign_tickets(ids, operator_id)
    if updated_count > 0:
        try:
            operator = user_repo.get_by_id(operator_id)
            operator_name = _operator_display_name(operator) if operator else "اپراتور پشتیبانی"
            context = {
                "subject": f"{updated_count} تیکت به شما تخصیص داده شد",
                "message": f"{updated_count} تیکت به شما تخصیص داده شد.",
                "operator_name": operator_name,
                "ticket_count": updated_count,
            }
            context.update(resolve_announcement_navigation("support.tickets_bulk_assigned", context))
            NotificationService(db).send(
                user_id=operator_id,
                event_key="support.tickets_bulk_assigned",
                context=context,
                preferred_channels=["inapp", "email", "telegram"],
                broadcast_mode=False,
            )
        except Exception:
            logger.exception("failed to notify bulk assignment operator_id=%s", operator_id)
    return {"updated_count": updated_count, "ticket_ids": ids}


def bulk_update_status(
    db: Session,
    *,
    ticket_ids: List[int],
    status_id: int,
    actor_id: int,
    actor_user: Any,
) -> Dict[str, Any]:
    ids = _unique_ticket_ids(ticket_ids)
    ticket_repo = TicketRepository(db)
    existing = ticket_repo.db.query(Ticket).filter(Ticket.id.in_(ids)).count()
    if existing != len(ids):
        raise ApiError("TICKETS_NOT_FOUND", "برخی از تیکت‌ها یافت نشدند", http_status=400)
    updated_count = ticket_repo.bulk_update_status(ids, status_id, actor_id)
    if updated_count > 0:
        try:
            from adapters.db.models.support.status import Status

            tickets = ticket_repo.db.query(Ticket).filter(Ticket.id.in_(ids)).all()
            new_status = db.query(Status).filter(Status.id == status_id).first()
            new_status_name = new_status.name if new_status else "نامشخص"
            operator_name = _operator_display_name(actor_user)
            user_ids = list({t.user_id for t in tickets if t.user_id})
            for user_id in user_ids:
                user_tickets = [t for t in tickets if t.user_id == user_id]
                context: Dict[str, Any] = {
                    "subject": f"وضعیت {len(user_tickets)} تیکت شما تغییر کرد",
                    "message": f"وضعیت {len(user_tickets)} تیکت شما به '{new_status_name}' تغییر کرد.",
                    "operator_name": operator_name,
                    "new_status": new_status_name,
                    "ticket_count": len(user_tickets),
                }
                if len(user_tickets) == 1:
                    context = support_notification_context(context, user_tickets[0].id)
                else:
                    context.update(resolve_announcement_navigation("support.tickets_bulk_status_changed", context))
                NotificationService(db).send(
                    user_id=user_id,
                    event_key="support.tickets_bulk_status_changed",
                    context=context,
                    preferred_channels=["inapp", "email", "telegram"],
                    broadcast_mode=False,
                )
        except Exception:
            logger.exception("failed to notify bulk status change")
    return {"updated_count": updated_count, "ticket_ids": ids, "status_id": status_id}


def _unique_ticket_ids(ticket_ids: List[int]) -> List[int]:
    cleaned: List[int] = []
    seen = set()
    for raw in ticket_ids or []:
        value = int(raw)
        if value <= 0 or value in seen:
            continue
        seen.add(value)
        cleaned.append(value)
    if not cleaned:
        raise ApiError("TICKET_IDS_REQUIRED", "حداقل یک شناسه تیکت لازم است", http_status=400)
    if len(cleaned) > BULK_LIMIT:
        raise ApiError("BULK_LIMIT", f"حداکثر {BULK_LIMIT} تیکت در هر درخواست مجاز است", http_status=400)
    return cleaned
