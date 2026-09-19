from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.support.sla_policy import SlaPolicy
from adapters.db.models.support.ticket import Ticket


DEFAULT_SLA_BY_ORDER = [
    (15, 240),
    (60, 480),
    (240, 1440),
    (480, 4320),
]


class SupportSlaService:
    def __init__(self, db: Session):
        self.db = db

    def _policy_for_priority(self, priority_id: int) -> Tuple[int, int]:
        policy = (
            self.db.query(SlaPolicy)
            .filter(SlaPolicy.priority_id == priority_id, SlaPolicy.is_active.is_(True))
            .first()
        )
        if policy:
            return policy.first_response_minutes, policy.resolution_minutes

        from adapters.db.models.support.priority import Priority

        prio = self.db.get(Priority, priority_id)
        order_idx = max(0, (prio.order if prio else 1) - 1)
        idx = min(order_idx, len(DEFAULT_SLA_BY_ORDER) - 1)
        return DEFAULT_SLA_BY_ORDER[idx]

    def apply_on_create(self, ticket: Ticket) -> None:
        fr_min, res_min = self._policy_for_priority(ticket.priority_id)
        base = ticket.created_at or datetime.utcnow()
        ticket.first_response_due_at = base + timedelta(minutes=fr_min)
        ticket.resolution_due_at = base + timedelta(minutes=res_min)
        ticket.sla_breached = False
        self.db.commit()

    def mark_first_response(self, ticket: Ticket) -> None:
        if ticket.first_responded_at is not None:
            return
        ticket.first_responded_at = datetime.utcnow()
        self.db.commit()

    def refresh_breach_flag(self, ticket: Ticket) -> None:
        now = datetime.utcnow()
        breached = False
        if ticket.closed_at is None:
            if ticket.resolution_due_at and now > ticket.resolution_due_at:
                breached = True
            elif (
                ticket.first_response_due_at
                and ticket.first_responded_at is None
                and now > ticket.first_response_due_at
            ):
                breached = True
        if ticket.sla_breached != breached:
            ticket.sla_breached = breached
            self.db.commit()

    def sla_status(self, ticket: Ticket) -> str:
        """ok | warning | breached"""
        self.refresh_breach_flag(ticket)
        if ticket.sla_breached:
            return "breached"
        now = datetime.utcnow()
        due = ticket.resolution_due_at or ticket.first_response_due_at
        if due and ticket.closed_at is None:
            remaining = (due - now).total_seconds()
            if remaining <= 1800:
                return "warning"
        return "ok"
