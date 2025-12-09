from __future__ import annotations

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from adapters.db.session import SessionLocal
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from app.core.security import hash_api_key
from app.services.realtime import realtime_manager
from adapters.db.models.user import User

router = APIRouter()


@router.websocket("/ws/notifications")
async def notifications_ws(websocket: WebSocket):
	"""
	WebSocket endpoint برای دریافت نوتیفیکیشن‌های لحظه‌ای
	
	⚠️ مهم: Session را فقط برای authentication استفاده می‌کنیم و سپس می‌بندیم
	تا از connection leak جلوگیری کنیم.
	"""
	# Expect query param ?api_key=... with raw value (like normal ApiKey header)
	api_key = websocket.query_params.get("api_key")
	if not api_key:
		await websocket.close(code=4401)
		return
	
	# ایجاد session موقت فقط برای authentication
	db: Session = SessionLocal()
	user_id = None
	try:
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
		
		user_id = user.id
	finally:
		# بستن session بلافاصله بعد از authentication
		db.close()
	
	# اتصال WebSocket (بدون session)
	await realtime_manager.connect(user_id, websocket)
	try:
		while True:
			# keep connection alive; ignore client messages
			_ = await websocket.receive_text()
	except WebSocketDisconnect:
		pass
	finally:
		await realtime_manager.disconnect(user_id, websocket)


