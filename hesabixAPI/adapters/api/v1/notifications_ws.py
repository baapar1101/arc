from __future__ import annotations

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from app.core.security import hash_api_key
from app.services.realtime import realtime_manager
from adapters.db.models.user import User

router = APIRouter()


@router.websocket("/ws/notifications")
async def notifications_ws(websocket: WebSocket, db: Session = Depends(get_db)):
	# Expect query param ?api_key=... with raw value (like normal ApiKey header)
	api_key = websocket.query_params.get("api_key")
	if not api_key:
		await websocket.close(code=4401)
		return
	key_hash = hash_api_key(api_key)
	repo = ApiKeyRepository(db)
	obj = repo.get_by_hash(key_hash)
	if not obj or obj.revoked_at is not None:
		await websocket.close(code=4401)
		return
	user = db.get(User, obj.user_id)
	if not user or not user.is_active:
		await websocket.close(code=4401)
		return

	await realtime_manager.connect(user.id, websocket)
	try:
		while True:
			# keep connection alive; ignore client messages
			_ = await websocket.receive_text()
	except WebSocketDisconnect:
		pass
	finally:
		await realtime_manager.disconnect(user.id, websocket)


