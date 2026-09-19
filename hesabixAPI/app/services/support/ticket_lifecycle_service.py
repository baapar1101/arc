from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.models.support.status import Status
from adapters.db.models.support.ticket import Ticket
from adapters.db.repositories.support.ticket_repository import TicketRepository
from app.core.responses import ApiError
from app.services.support.ticket_access_service import TicketAccessService
from app.services.support.ticket_event_service import TicketEventService


class TicketLifecycleService:
    def __init__(self, db: Session):
        self.db = db
        self.ticket_repo = TicketRepository(db)
        self.access = TicketAccessService(db)
        self.events = TicketEventService(db)

    def _find_closed_status(self) -> Status:
        status = (
            self.db.query(Status)
            .filter(Status.is_final.is_(True))
            .order_by(Status.id.desc())
            .first()
        )
        if not status:
            raise ApiError("STATUS_NOT_FOUND", "وضعیت بسته یافت نشد", http_status=500)
        return status

    def _find_open_status(self) -> Status:
        status = (
            self.db.query(Status)
            .filter(Status.is_final.is_(False))
            .order_by(Status.id.asc())
            .first()
        )
        if not status:
            raise ApiError("STATUS_NOT_FOUND", "وضعیت باز یافت نشد", http_status=500)
        return status

    def close_by_user(self, ticket_id: int, user_id: int) -> Ticket:
        ticket = self.access.get_user_ticket(ticket_id, user_id)
        if ticket.status and ticket.status.is_final:
            raise ApiError("TICKET_ALREADY_CLOSED", "این تیکت قبلاً بسته شده است", http_status=409)

        closed_status = self._find_closed_status()
        old_status_id = ticket.status_id
        updated = self.ticket_repo.update_ticket_status(ticket_id, closed_status.id)
        if not updated:
            raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)

        self.events.record(
            ticket_id,
            "closed",
            actor_id=user_id,
            old_value={"status_id": old_status_id},
            new_value={"status_id": closed_status.id},
        )
        self.db.commit()
        return self.ticket_repo.get_ticket_with_details(ticket_id, user_id)

    def reopen_by_user(self, ticket_id: int, user_id: int) -> Ticket:
        ticket = self.access.get_user_ticket(ticket_id, user_id)
        if not ticket.status or not ticket.status.is_final:
            raise ApiError("TICKET_ALREADY_OPEN", "این تیکت در حال حاضر باز است", http_status=409)

        open_status = self._find_open_status()
        old_status_id = ticket.status_id
        updated = self.ticket_repo.update_ticket_status(ticket_id, open_status.id)
        if not updated:
            raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)

        self.events.record(
            ticket_id,
            "reopened",
            actor_id=user_id,
            old_value={"status_id": old_status_id},
            new_value={"status_id": open_status.id},
        )
        self.db.commit()
        return self.ticket_repo.get_ticket_with_details(ticket_id, user_id)

    def update_status(
        self,
        ticket_id: int,
        status_id: int,
        actor_id: int,
        assigned_operator_id: Optional[int] = None,
    ) -> Ticket:
        ticket = self.access.get_operator_ticket(ticket_id)
        old_status_id = ticket.status_id
        old_operator_id = ticket.assigned_operator_id

        updated = self.ticket_repo.update_ticket_status(
            ticket_id, status_id, operator_id=assigned_operator_id
        )
        if not updated:
            raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)

        self.events.record(
            ticket_id,
            "status_changed",
            actor_id=actor_id,
            old_value={"status_id": old_status_id, "assigned_operator_id": old_operator_id},
            new_value={"status_id": status_id, "assigned_operator_id": assigned_operator_id},
        )
        self.db.commit()
        return self.ticket_repo.get_operator_ticket_with_details(ticket_id)

    def update_priority(self, ticket_id: int, priority_id: int, actor_id: int) -> Ticket:
        ticket = self.access.get_operator_ticket(ticket_id)
        old_priority_id = ticket.priority_id
        ticket.priority_id = priority_id
        self.db.commit()

        self.events.record(
            ticket_id,
            "priority_changed",
            actor_id=actor_id,
            old_value={"priority_id": old_priority_id},
            new_value={"priority_id": priority_id},
        )
        self.db.commit()
        return self.ticket_repo.get_operator_ticket_with_details(ticket_id)

    def assign(self, ticket_id: int, operator_id: int, actor_id: int) -> Ticket:
        ticket = self.access.get_operator_ticket(ticket_id)
        old_operator_id = ticket.assigned_operator_id
        updated = self.ticket_repo.assign_ticket(ticket_id, operator_id)
        if not updated:
            raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)

        self.events.record(
            ticket_id,
            "assigned",
            actor_id=actor_id,
            old_value={"assigned_operator_id": old_operator_id},
            new_value={"assigned_operator_id": operator_id},
        )
        self.db.commit()
        return self.ticket_repo.get_operator_ticket_with_details(ticket_id)
