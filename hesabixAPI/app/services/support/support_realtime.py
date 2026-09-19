from __future__ import annotations

import asyncio
import logging
from typing import Any, Dict, Iterable, List, Optional, Set

from fastapi import WebSocket
from sqlalchemy.orm import Session

from adapters.db.repositories.user_repo import UserRepository
from app.services.realtime import RealtimeManager

logger = logging.getLogger(__name__)


class SupportRealtimeManager(RealtimeManager):
    """WebSocket connections for /ws/support/tickets with ticket subscriptions."""

    def __init__(self) -> None:
        super().__init__()
        self._ticket_watchers: Dict[int, Set[WebSocket]] = {}

    async def subscribe_ticket(self, ticket_id: int, websocket: WebSocket) -> None:
        self._ticket_watchers.setdefault(ticket_id, set()).add(websocket)

    async def unsubscribe_ticket(self, ticket_id: int, websocket: WebSocket) -> None:
        socks = self._ticket_watchers.get(ticket_id)
        if not socks:
            return
        socks.discard(websocket)
        if not socks:
            self._ticket_watchers.pop(ticket_id, None)

    async def disconnect(self, user_id: int, websocket: WebSocket) -> None:
        for tid, socks in list(self._ticket_watchers.items()):
            if websocket in socks:
                socks.discard(websocket)
                if not socks:
                    self._ticket_watchers.pop(tid, None)
        await super().disconnect(user_id, websocket)

    async def deliver_support_event(
        self,
        user_ids: Iterable[int],
        ticket_id: Optional[int],
        event: Dict[str, Any],
    ) -> None:
        for uid in set(user_ids):
            await self.send_to_user(uid, event)
        if ticket_id is not None:
            await self.send_to_ticket_watchers(ticket_id, event)

    async def send_to_ticket_watchers(self, ticket_id: int, message: dict) -> None:
        socks = list(self._ticket_watchers.get(ticket_id, set()))
        for ws in socks:
            try:
                await ws.send_json(message)
            except Exception:
                pass


support_realtime_manager = SupportRealtimeManager()


def _support_operator_user_ids(db: Session) -> List[int]:
    repo = UserRepository(db)
    return [u.id for u in repo.get_support_operators()]


def _emit_async(coro) -> None:
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(coro)
    except RuntimeError:
        try:
            asyncio.run(coro)
        except Exception as exc:
            logger.debug("support realtime emit failed: %s", exc)


async def _broadcast_event(
    db: Session,
    *,
    event_type: str,
    ticket_id: int,
    payload: Optional[Dict[str, Any]] = None,
    ticket_owner_id: Optional[int] = None,
    assigned_operator_id: Optional[int] = None,
    notify_all_operators: bool = False,
) -> None:
    from app.services.support.support_realtime_fanout import broadcast_support_cross_worker

    event: Dict[str, Any] = {
        "type": "support",
        "event": event_type,
        "ticket_id": ticket_id,
        "payload": payload or {},
    }
    recipients: List[int] = []
    if ticket_owner_id:
        recipients.append(ticket_owner_id)
    if assigned_operator_id:
        recipients.append(assigned_operator_id)
    if notify_all_operators:
        recipients.extend(_support_operator_user_ids(db))

    await broadcast_support_cross_worker(recipients, ticket_id, event)


def emit_support_event(
    db: Session,
    *,
    event_type: str,
    ticket_id: int,
    payload: Optional[Dict[str, Any]] = None,
    ticket_owner_id: Optional[int] = None,
    assigned_operator_id: Optional[int] = None,
    notify_all_operators: bool = False,
) -> None:
    _emit_async(
        _broadcast_event(
            db,
            event_type=event_type,
            ticket_id=ticket_id,
            payload=payload,
            ticket_owner_id=ticket_owner_id,
            assigned_operator_id=assigned_operator_id,
            notify_all_operators=notify_all_operators,
        )
    )
