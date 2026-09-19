"""Read tracking and CSAT for support tickets."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import update
from sqlalchemy.orm import Session

from adapters.db.models.support.message import Message, SenderType
from adapters.db.models.support.ticket import Ticket


def ticket_last_activity_at(ticket: Ticket) -> datetime:
    return ticket.last_message_at or ticket.created_at


def _latest_public_message(db: Session, ticket_id: int) -> Optional[Message]:
    return (
        db.query(Message)
        .filter(Message.ticket_id == ticket_id, Message.is_internal.is_(False))
        .order_by(Message.created_at.desc())
        .first()
    )


def _sender_is(sender_type, expected: SenderType) -> bool:
    if sender_type is None:
        return False
    if isinstance(sender_type, SenderType):
        return sender_type == expected
    return str(sender_type) == expected.value


def is_unread_for_user(ticket: Ticket, latest: Optional[Message] = None) -> bool:
    if latest is None:
        return False
    if not _sender_is(latest.sender_type, SenderType.OPERATOR):
        return False
    if ticket.user_last_read_at is None:
        return True
    return latest.created_at > ticket.user_last_read_at


def is_unread_for_operator(ticket: Ticket, latest: Optional[Message] = None) -> bool:
    if latest is None:
        return False
    if not _sender_is(latest.sender_type, SenderType.USER):
        return False
    if ticket.operator_last_read_at is None:
        return True
    return latest.created_at > ticket.operator_last_read_at


def mark_user_read(db: Session, ticket: Ticket) -> Ticket:
    now = datetime.utcnow()
    db.execute(
        update(Ticket)
        .where(Ticket.id == ticket.id)
        .values(user_last_read_at=now)
    )
    db.commit()
    db.refresh(ticket)
    return ticket


def mark_operator_read(db: Session, ticket: Ticket) -> Ticket:
    now = datetime.utcnow()
    db.execute(
        update(Ticket)
        .where(Ticket.id == ticket.id)
        .values(operator_last_read_at=now)
    )
    db.commit()
    db.refresh(ticket)
    return ticket


def submit_csat(db: Session, ticket: Ticket, rating: int, comment: Optional[str] = None) -> Ticket:
    if rating < 1 or rating > 5:
        raise ValueError("rating must be between 1 and 5")
    if ticket.csat_submitted_at is not None:
        raise ValueError("CSAT already submitted")
    ticket.csat_rating = rating
    ticket.csat_comment = (comment or "").strip() or None
    ticket.csat_submitted_at = datetime.utcnow()
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    return ticket


def engagement_fields(db: Session, ticket: Ticket) -> dict:
    latest = _latest_public_message(db, ticket.id)
    return {
        "user_last_read_at": ticket.user_last_read_at,
        "operator_last_read_at": ticket.operator_last_read_at,
        "is_unread_for_user": is_unread_for_user(ticket, latest),
        "is_unread_for_operator": is_unread_for_operator(ticket, latest),
        "csat_rating": ticket.csat_rating,
        "csat_comment": ticket.csat_comment,
        "csat_submitted_at": ticket.csat_submitted_at,
        "last_message_at": ticket.last_message_at,
        "last_activity_at": ticket_last_activity_at(ticket),
        "last_message_from_user": _sender_is(latest.sender_type, SenderType.USER) if latest else None,
    }
