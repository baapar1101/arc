# noqa: D100
"""WebSocket برای چت وب CRM (بازدیدکننده و عامل CRM)."""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Dict, Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.crm_chat import CrmChatConversation
from adapters.db.models.user import User
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from adapters.db.session import SessionLocal
from app.core.auth_dependency import AuthContext
from app.core.crm_web_chat_permissions import check_crm_web_chat_capability
from app.core.security import hash_api_key
from app.services.crm_chat_realtime import crm_chat_realtime_manager
from app.services import crm_chat_service as chat_svc
from app.services.crm_chat_service import _hash_visitor_token
from app.services.ws_api_key_handshake import WsAuthRejected, close_ws_safe

logger = logging.getLogger(__name__)

router = APIRouter()

DEFAULT_WS_AUTH_TIMEOUT_SEC = 15.0


async def _read_first_auth_message(websocket: WebSocket, *, timeout_sec: float = DEFAULT_WS_AUTH_TIMEOUT_SEC) -> Dict[str, Any]:
	try:
		raw = await asyncio.wait_for(websocket.receive_text(), timeout=timeout_sec)
	except asyncio.TimeoutError:
		raise WsAuthRejected(4408) from None
	except WebSocketDisconnect:
		raise WsAuthRejected(4400) from None
	try:
		payload = json.loads(raw)
	except json.JSONDecodeError:
		raise WsAuthRejected(4400) from None
	if not isinstance(payload, dict) or payload.get("type") != "auth":
		raise WsAuthRejected(4400)
	return payload


def _authenticate_api_key_db(db: Session, api_key: str) -> Optional[User]:
	key_hash = hash_api_key(api_key)
	repo = ApiKeyRepository(db)
	obj = repo.get_by_hash(key_hash)
	if not obj or obj.revoked_at is not None:
		return None
	user = db.get(User, obj.user_id)
	if not user or not user.is_active:
		return None
	return user


def _agent_may(
	db: Session,
	user: User,
	business_id: int,
	*,
	need_write: bool,
) -> bool:
	ctx = AuthContext(user=user, api_key_id=0, business_id=business_id, db=db)
	if not ctx.can_access_business(business_id):
		return False
	if ctx.is_superadmin() or ctx.is_business_owner(business_id):
		return True
	repo = BusinessPermissionRepository(db)
	perm_obj = repo.get_by_user_and_business(user.id, business_id)
	if not perm_obj or not perm_obj.business_permissions:
		return False
	perms = ctx._normalize_permissions_value(perm_obj.business_permissions)
	cap = "reply" if need_write else "view"
	return check_crm_web_chat_capability(perms, cap)


def _conv_belongs_to_business(db: Session, conversation_id: int, business_id: int) -> bool:
	c = db.get(CrmChatConversation, conversation_id)
	return bool(c and c.business_id == business_id)


@router.websocket("/ws/crm-chat")
async def crm_chat_websocket(websocket: WebSocket):
	"""
	احراز هویت اولین فریم (JSON متنی):

	بازدیدکننده:
	{"type":"auth","role":"visitor","visitor_token":"...","conversation_id":123}

	عامل CRM:
	{"type":"auth","role":"agent","api_key":"...","business_id":456}

	پس از auth_ok عامل می‌تواند مشترک یک مکالمه شود:
	{"type":"subscribe","conversation_id":123}
	"""
	await websocket.accept()
	role: Optional[str] = None
	business_id: Optional[int] = None
	agent_user: Optional[User] = None
	try:
		auth = await _read_first_auth_message(websocket)
		role = auth.get("role")
		if role == "visitor":
			token = auth.get("visitor_token")
			cid = auth.get("conversation_id")
			if not token or not isinstance(token, str) or not cid:
				raise WsAuthRejected(4401)
			try:
				cid_int = int(cid)
			except (TypeError, ValueError):
				raise WsAuthRejected(4401)
			db: Session = SessionLocal()
			visitor_business_id: int
			try:
				th = _hash_visitor_token(token)
				c = db.scalar(
					select(CrmChatConversation).where(
						CrmChatConversation.id == cid_int,
						CrmChatConversation.visitor_token_hash == th,
					)
				)
				if not c:
					raise WsAuthRejected(4403)
				visitor_business_id = c.business_id
			finally:
				db.close()
			await crm_chat_realtime_manager.add_to_conversation(cid_int, websocket)
			await websocket.send_json({"type": "auth_ok", "role": "visitor", "conversation_id": cid_int})
			try:
				while True:
					raw = await websocket.receive_text()
					try:
						msg = json.loads(raw)
					except json.JSONDecodeError:
						continue
					if not isinstance(msg, dict) or msg.get("type") != "typing":
						continue
					await chat_svc.broadcast_typing(
						cid_int,
						visitor_business_id,
						from_role="visitor",
						active=bool(msg.get("active", True)),
					)
			except WebSocketDisconnect:
				pass
			finally:
				await crm_chat_realtime_manager.disconnect_all(websocket)
			return

		if role == "agent":
			api_key = auth.get("api_key")
			bid = auth.get("business_id")
			if not api_key or not isinstance(api_key, str) or bid is None:
				raise WsAuthRejected(4401)
			try:
				business_id = int(bid)
			except (TypeError, ValueError):
				raise WsAuthRejected(4401)
			db = SessionLocal()
			try:
				agent_user = _authenticate_api_key_db(db, api_key.strip())
				if agent_user is None:
					raise WsAuthRejected(4401)
				if not _agent_may(db, agent_user, business_id, need_write=False):
					raise WsAuthRejected(4403)
			finally:
				db.close()
			await crm_chat_realtime_manager.add_to_business(business_id, websocket)
			await websocket.send_json({"type": "auth_ok", "role": "agent", "business_id": business_id})
			try:
				while True:
					raw = await websocket.receive_text()
					try:
						msg = json.loads(raw)
					except json.JSONDecodeError:
						continue
					if not isinstance(msg, dict):
						continue
					if msg.get("type") == "typing":
						scid = msg.get("conversation_id")
						if scid is None:
							continue
						try:
							scid_int = int(scid)
						except (TypeError, ValueError):
							continue
						db2 = SessionLocal()
						try:
							if not _conv_belongs_to_business(db2, scid_int, business_id):
								logger.warning(
									"crm_chat_ws typing dropped: conversation_id=%s business_id=%s (not found or wrong tenant)",
									scid_int,
									business_id,
								)
								continue
							if not _agent_may(db2, agent_user, business_id, need_write=False):
								logger.warning(
									"crm_chat_ws typing dropped: conversation_id=%s business_id=%s user_id=%s (permission)",
									scid_int,
									business_id,
									getattr(agent_user, "id", None),
								)
								continue
						finally:
							db2.close()
						await chat_svc.broadcast_typing(
							scid_int,
							business_id,
							from_role="agent",
							active=bool(msg.get("active", True)),
							actor_name=chat_svc.agent_display_name(agent_user),
						)
						continue
					if msg.get("type") != "subscribe":
						continue
					scid = msg.get("conversation_id")
					if scid is None:
						continue
					try:
						scid_int = int(scid)
					except (TypeError, ValueError):
						continue
					db2 = SessionLocal()
					try:
						if not _conv_belongs_to_business(db2, scid_int, business_id):
							logger.warning(
								"crm_chat_ws subscribe dropped: conversation_id=%s business_id=%s (not found or wrong tenant)",
								scid_int,
								business_id,
							)
							continue
						if not _agent_may(db2, agent_user, business_id, need_write=False):
							logger.warning(
								"crm_chat_ws subscribe dropped: conversation_id=%s business_id=%s user_id=%s (permission)",
								scid_int,
								business_id,
								getattr(agent_user, "id", None),
							)
							continue
					finally:
						db2.close()
					await crm_chat_realtime_manager.add_to_conversation(scid_int, websocket)
					await chat_svc.broadcast_agent_joined(
						scid_int,
						business_id,
						agent_user_id=int(agent_user.id),
						agent_name=chat_svc.agent_display_name(agent_user),
					)
			except WebSocketDisconnect:
				pass
			finally:
				await crm_chat_realtime_manager.disconnect_all(websocket)
			return

		raise WsAuthRejected(4400)
	except WsAuthRejected as e:
		await close_ws_safe(websocket, e.close_code)
	except Exception:
		logger.exception("crm_chat_ws error")
		await close_ws_safe(websocket, 4500)
