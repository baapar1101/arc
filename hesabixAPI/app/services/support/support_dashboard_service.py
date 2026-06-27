from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy import func, and_, or_
from sqlalchemy.orm import Session, joinedload

from adapters.db.models.support.message import Message
from adapters.db.models.support.status import Status
from adapters.db.models.support.ticket import Ticket
from adapters.db.repositories.support.ticket_repository import TicketRepository
from app.services.support.support_sla_service import SupportSlaService


class SupportDashboardService:
    def __init__(self, db: Session):
        self.db = db
        self.ticket_repo = TicketRepository(db)
        self.sla = SupportSlaService(db)

    def _open_filter(self):
        return Ticket.status.has(Status.is_final.is_(False))

    def _last_public_message_subquery(self):
        return (
            self.db.query(
                Message.ticket_id,
                func.max(Message.created_at).label("max_created_at"),
            )
            .filter(Message.is_internal.is_(False))
            .group_by(Message.ticket_id)
            .subquery()
        )

    def _unread_operator_count(self, operator_id: Optional[int] = None) -> int:
        last_sub = self._last_public_message_subquery()
        last_msg = (
            self.db.query(
                Message.ticket_id,
                Message.sender_type,
                Message.created_at,
            )
            .join(
                last_sub,
                and_(
                    Message.ticket_id == last_sub.c.ticket_id,
                    Message.created_at == last_sub.c.max_created_at,
                    Message.is_internal.is_(False),
                ),
            )
            .subquery()
        )
        q = (
            self.db.query(func.count(Ticket.id))
            .join(last_msg, Ticket.id == last_msg.c.ticket_id)
            .filter(
                self._open_filter(),
                last_msg.c.sender_type == "user",
                or_(
                    Ticket.operator_last_read_at.is_(None),
                    last_msg.c.created_at > Ticket.operator_last_read_at,
                ),
            )
        )
        if operator_id is not None:
            q = q.filter(Ticket.assigned_operator_id == operator_id)
        return q.scalar() or 0

    def get_stats(self, operator_id: int) -> Dict[str, Any]:
        open_q = self.db.query(func.count(Ticket.id)).filter(self._open_filter())
        open_count = open_q.scalar() or 0

        mine_count = (
            self.db.query(func.count(Ticket.id))
            .filter(self._open_filter(), Ticket.assigned_operator_id == operator_id)
            .scalar()
            or 0
        )

        now = datetime.utcnow()
        overdue_count = (
            self.db.query(func.count(Ticket.id))
            .filter(
                self._open_filter(),
                Ticket.resolution_due_at.isnot(None),
                Ticket.resolution_due_at < now,
            )
            .scalar()
            or 0
        )

        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        resolved_today = (
            self.db.query(func.count(Ticket.id))
            .filter(Ticket.closed_at.isnot(None), Ticket.closed_at >= today_start)
            .scalar()
            or 0
        )

        return {
            "open_count": open_count,
            "my_open_count": mine_count,
            "unread_count": self._unread_operator_count(),
            "my_unread_count": self._unread_operator_count(operator_id),
            "overdue_count": overdue_count,
            "resolved_today_count": resolved_today,
        }

    def get_overdue_tickets(self, limit: int = 20) -> List[Dict[str, Any]]:
        now = datetime.utcnow()
        tickets = (
            self.db.query(Ticket)
            .options(
                joinedload(Ticket.user),
                joinedload(Ticket.priority),
                joinedload(Ticket.status),
            )
            .filter(
                self._open_filter(),
                Ticket.resolution_due_at.isnot(None),
                Ticket.resolution_due_at < now,
            )
            .order_by(Ticket.resolution_due_at.asc())
            .limit(limit)
            .all()
        )
        return [self._ticket_summary(t) for t in tickets]

    def get_activity(self, days: int = 7) -> List[Dict[str, Any]]:
        start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=days - 1)
        created_rows = (
            self.db.query(func.date(Ticket.created_at), func.count(Ticket.id))
            .filter(Ticket.created_at >= start)
            .group_by(func.date(Ticket.created_at))
            .all()
        )
        closed_rows = (
            self.db.query(func.date(Ticket.closed_at), func.count(Ticket.id))
            .filter(Ticket.closed_at.isnot(None), Ticket.closed_at >= start)
            .group_by(func.date(Ticket.closed_at))
            .all()
        )
        created_map = {str(r[0]): r[1] for r in created_rows}
        closed_map = {str(r[0]): r[1] for r in closed_rows}
        result = []
        for i in range(days):
            day = (start + timedelta(days=i)).date()
            key = str(day)
            result.append(
                {
                    "date": key,
                    "created_count": created_map.get(key, 0),
                    "resolved_count": closed_map.get(key, 0),
                }
            )
        return result

    def get_user_ticket_history(self, user_id: int, take: int = 5) -> List[Dict[str, Any]]:
        tickets = (
            self.db.query(Ticket)
            .options(joinedload(Ticket.status), joinedload(Ticket.priority))
            .filter(Ticket.user_id == user_id)
            .order_by(Ticket.created_at.desc())
            .limit(take)
            .all()
        )
        return [self._ticket_summary(t) for t in tickets]

    def _ticket_summary(self, ticket: Ticket) -> Dict[str, Any]:
        overdue_minutes = 0
        if ticket.resolution_due_at and ticket.closed_at is None:
            delta = datetime.utcnow() - ticket.resolution_due_at
            if delta.total_seconds() > 0:
                overdue_minutes = int(delta.total_seconds() // 60)
        return {
            "id": ticket.id,
            "title": ticket.title,
            "status": ticket.status.name if ticket.status else None,
            "priority": ticket.priority.name if ticket.priority else None,
            "user_name": (
                f"{ticket.user.first_name or ''} {ticket.user.last_name or ''}".strip()
                if ticket.user
                else None
            ),
            "created_at": ticket.created_at.isoformat() if ticket.created_at else None,
            "resolution_due_at": ticket.resolution_due_at.isoformat() if ticket.resolution_due_at else None,
            "sla_status": self.sla.sla_status(ticket),
            "overdue_minutes": overdue_minutes,
        }
