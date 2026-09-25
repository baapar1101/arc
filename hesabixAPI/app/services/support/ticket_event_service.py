from __future__ import annotations

from typing import Any, Optional

from sqlalchemy.orm import Session

from adapters.db.models.support.ticket_event import TicketEvent


class TicketEventService:
    def __init__(self, db: Session):
        self.db = db

    def record(
        self,
        ticket_id: int,
        event_type: str,
        actor_id: Optional[int] = None,
        old_value: Optional[dict[str, Any]] = None,
        new_value: Optional[dict[str, Any]] = None,
    ) -> TicketEvent:
        event = TicketEvent(
            ticket_id=ticket_id,
            actor_id=actor_id,
            event_type=event_type,
            old_value=old_value,
            new_value=new_value,
        )
        self.db.add(event)
        self.db.flush()
        return event

    def list_for_ticket(self, ticket_id: int, limit: int = 50) -> list[TicketEvent]:
        return (
            self.db.query(TicketEvent)
            .filter(TicketEvent.ticket_id == ticket_id)
            .order_by(TicketEvent.created_at.desc())
            .limit(limit)
            .all()
        )
