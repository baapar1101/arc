from __future__ import annotations

from sqlalchemy.orm import Session

from adapters.db.models.support.ticket import Ticket
from adapters.db.repositories.support.ticket_repository import TicketRepository
from app.core.responses import ApiError


class TicketAccessService:
    def __init__(self, db: Session):
        self.db = db
        self.ticket_repo = TicketRepository(db)

    def get_user_ticket(self, ticket_id: int, user_id: int) -> Ticket:
        ticket = self.ticket_repo.get_ticket_with_details(ticket_id, user_id)
        if not ticket:
            raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)
        return ticket

    def get_operator_ticket(self, ticket_id: int) -> Ticket:
        ticket = self.ticket_repo.get_operator_ticket_with_details(ticket_id)
        if not ticket:
            raise ApiError("TICKET_NOT_FOUND", "تیکت یافت نشد", http_status=404)
        return ticket

    @staticmethod
    def assert_ticket_open(ticket: Ticket) -> None:
        if ticket.status and ticket.status.is_final:
            raise ApiError(
                "TICKET_CLOSED",
                "این تیکت بسته شده و امکان ارسال پیام وجود ندارد",
                http_status=409,
            )
