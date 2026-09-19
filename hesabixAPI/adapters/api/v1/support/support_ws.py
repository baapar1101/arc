from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.session import SessionLocal
from app.core.security import hash_api_key
from app.services.support.support_realtime import support_realtime_manager
from app.services.ws_api_key_handshake import (
    WsAuthClientDisconnected,
    WsAuthRejected,
    WsAuthTimeout,
    close_ws_safe,
    read_api_key_from_first_text_message,
)

logger = logging.getLogger(__name__)
router = APIRouter()


def _authenticate_api_key(api_key: str) -> tuple[int | None, bool]:
    db: Session = SessionLocal()
    try:
        key_hash = hash_api_key(api_key)
        repo = ApiKeyRepository(db)
        obj = repo.get_by_hash(key_hash)
        if not obj or obj.revoked_at is not None:
            return None, False
        user_repo = UserRepository(db)
        from adapters.db.models.user import User

        user = db.get(User, obj.user_id)
        if not user or not user.is_active:
            return None, False
        is_operator = user_repo.is_support_operator(user.id)
        return user.id, is_operator
    finally:
        db.close()


@router.websocket("/ws/support/tickets")
async def support_tickets_ws(websocket: WebSocket):
    await websocket.accept()
    try:
        api_key = await read_api_key_from_first_text_message(websocket)
    except WsAuthClientDisconnected:
        return
    except WsAuthTimeout:
        await close_ws_safe(websocket, 4408)
        return
    except WsAuthRejected as e:
        await close_ws_safe(websocket, e.close_code)
        return

    user_id, is_operator = _authenticate_api_key(api_key)
    if user_id is None:
        await close_ws_safe(websocket, 4401)
        return

    await support_realtime_manager.connect(user_id, websocket, already_accepted=True)
    try:
        await websocket.send_json({"type": "auth_ok", "is_operator": is_operator})
    except Exception:
        pass

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not isinstance(msg, dict):
                continue
            mtype = msg.get("type")
            if mtype == "subscribe" and msg.get("ticket_id") is not None:
                await support_realtime_manager.subscribe_ticket(int(msg["ticket_id"]), websocket)
            elif mtype == "unsubscribe" and msg.get("ticket_id") is not None:
                await support_realtime_manager.unsubscribe_ticket(int(msg["ticket_id"]), websocket)
            elif mtype == "ping":
                await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    finally:
        await support_realtime_manager.disconnect(user_id, websocket)
