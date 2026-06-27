"""Background jobs for support ticketing (SLA breach checks)."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from sqlalchemy.exc import TimeoutError as SQLTimeoutError

from adapters.db.models.support.status import Status
from adapters.db.models.support.ticket import Ticket
from adapters.db.session import get_db_session

logger = logging.getLogger(__name__)


def _refresh_sla_breach_flags() -> int:
    """Mark open tickets whose SLA is breached. Returns count of updated rows."""
    try:
        with get_db_session(retries=1, delay=0.5) as db:
            now = datetime.utcnow()
            tickets = (
                db.query(Ticket)
                .join(Ticket.status)
                .filter(Status.is_final.is_(False), Ticket.closed_at.is_(None))
                .all()
            )
            changed = 0
            for ticket in tickets:
                breached = False
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
                    changed += 1
            if changed:
                db.commit()
            return changed
    except SQLTimeoutError as exc:
        logger.warning("SLA breach check skipped (pool exhausted): %s", exc)
        return 0
    except Exception:
        logger.exception("SLA breach check failed")
        return 0


async def support_sla_breach_check_loop(interval_seconds: int = 300) -> None:
    """Every 5 minutes by default, refresh sla_breached on open tickets."""
    while True:
        try:
            changed = await asyncio.to_thread(_refresh_sla_breach_flags)
            if changed:
                logger.info("Support SLA: updated breach flag on %s ticket(s)", changed)
        except Exception:
            logger.exception("Error in support SLA breach loop")
        await asyncio.sleep(interval_seconds)
