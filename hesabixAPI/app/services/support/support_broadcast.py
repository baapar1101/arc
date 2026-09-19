from __future__ import annotations

from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from adapters.db.models.support.ticket import Ticket
from app.services.support.support_realtime import emit_support_event


def broadcast_ticket_created(db: Session, ticket: Ticket) -> None:
    emit_support_event(
        db,
        event_type="ticket.created",
        ticket_id=ticket.id,
        payload={"title": ticket.title, "priority_id": ticket.priority_id},
        ticket_owner_id=ticket.user_id,
        notify_all_operators=True,
    )


def broadcast_message_created(
    db: Session,
    ticket: Ticket,
    *,
    sender_type: str,
    message_id: int,
    preview: str,
) -> None:
    payload: Dict[str, Any] = {
        "message_id": message_id,
        "sender_type": sender_type,
        "preview": preview[:200],
    }
    if sender_type == "user":
        emit_support_event(
            db,
            event_type="message.created",
            ticket_id=ticket.id,
            payload=payload,
            ticket_owner_id=ticket.user_id,
            assigned_operator_id=ticket.assigned_operator_id,
            notify_all_operators=ticket.assigned_operator_id is None,
        )
    else:
        emit_support_event(
            db,
            event_type="message.created",
            ticket_id=ticket.id,
            payload=payload,
            ticket_owner_id=ticket.user_id,
            assigned_operator_id=ticket.assigned_operator_id,
        )


def broadcast_ticket_updated(
    db: Session,
    ticket: Ticket,
    *,
    changes: Optional[Dict[str, Any]] = None,
) -> None:
    emit_support_event(
        db,
        event_type="ticket.updated",
        ticket_id=ticket.id,
        payload=changes or {},
        ticket_owner_id=ticket.user_id,
        assigned_operator_id=ticket.assigned_operator_id,
        notify_all_operators=False,
    )
