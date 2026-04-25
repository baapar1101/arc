from __future__ import annotations

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from adapters.db.session import SessionLocal
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from app.core.security import hash_api_key
from app.services.realtime import realtime_manager
from app.services.ws_api_key_handshake import (
	WsAuthClientDisconnected,
	WsAuthRejected,
	WsAuthTimeout,
	close_ws_safe,
	read_api_key_from_first_text_message,
)
from adapters.db.models.user import User

router = APIRouter()


def _authenticate_api_key(api_key: str) -> int | None:
	db: Session = SessionLocal()
	try:
		key_hash = hash_api_key(api_key)
		repo = ApiKeyRepository(db)
		obj = repo.get_by_hash(key_hash)
		if not obj or obj.revoked_at is not None:
			return None
		user = db.get(User, obj.user_id)
		if not user or not user.is_active:
			return None
		return user.id
	finally:
		db.close()


@router.websocket("/ws/notifications")
async def notifications_ws(websocket: WebSocket):
	"""
	WebSocket endpoint برای دریافت نوتیفیکیشن‌های لحظه‌ای

	احراز هویت: بلافاصله پس از برقراری TLS، کلاینت باید اولین فریم متنی JSON بفرستد:
	{"type":"auth","api_key":"..."}
	قرار دادن api_key در query string پشتیبانی نمی‌شود (در لاگ‌ها و تاریخچه لو می‌رود).
	"""
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

	user_id = _authenticate_api_key(api_key)
	if user_id is None:
		await close_ws_safe(websocket, 4401)
		return

	await realtime_manager.connect(user_id, websocket, already_accepted=True)
	try:
		await websocket.send_json({"type": "auth_ok"})
	except Exception:
		pass
	try:
		while True:
			# keep connection alive; ignore client messages
			_ = await websocket.receive_text()
	except WebSocketDisconnect:
		pass
	finally:
		await realtime_manager.disconnect(user_id, websocket)


from adapters.api.v1.crm_chat_ws import router as _crm_chat_ws_router  # noqa: E402

router.include_router(_crm_chat_ws_router)

