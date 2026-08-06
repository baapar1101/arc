"""WebSocket Softphone: کلاینت اپراتور + تونل رسانه Connector."""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from adapters.db.session import SessionLocal
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.models.user import User
from app.core.security import hash_api_key
from app.services.telephony import softphone_service as soft_svc
from app.services.telephony import telephony_service as tel_svc
from app.services.telephony.media_hub import SoftphoneClientLink, media_hub
from app.services.ws_api_key_handshake import (
	WsAuthClientDisconnected,
	WsAuthRejected,
	WsAuthTimeout,
	close_ws_safe,
)

LOG = logging.getLogger("hesabix.telephony.softphone_ws")
router = APIRouter(tags=["telephony-softphone-ws"])


def _db() -> Session:
	return SessionLocal()


def _auth_user_api_key(api_key: str) -> Optional[int]:
	db = _db()
	try:
		repo = ApiKeyRepository(db)
		obj = repo.get_by_hash(hash_api_key(api_key))
		if not obj or obj.revoked_at is not None:
			return None
		user = db.get(User, obj.user_id)
		if not user or not user.is_active:
			return None
		return int(user.id)
	finally:
		db.close()


async def _read_json_auth(websocket: WebSocket, *, timeout_sec: float = 15.0) -> dict[str, Any]:
	try:
		raw = await asyncio.wait_for(websocket.receive_text(), timeout=timeout_sec)
	except asyncio.TimeoutError:
		raise WsAuthTimeout from None
	except WebSocketDisconnect:
		raise WsAuthClientDisconnected from None
	try:
		payload = json.loads(raw)
	except json.JSONDecodeError:
		raise WsAuthRejected(4400) from None
	if not isinstance(payload, dict) or payload.get("type") != "auth":
		raise WsAuthRejected(4400)
	return payload


@router.websocket("/ws/telephony/softphone")
async def softphone_client_ws(websocket: WebSocket) -> None:
	"""
	کانال Softphone اپراتور.

	اولین پیام:
	{"type":"auth","api_key":"...","session_id":"...","media_ticket":"...","business_id":123}
	"""
	from app.services.telephony.media_edge import is_media_edge_process

	await websocket.accept()
	if not is_media_edge_process():
		await close_ws_safe(websocket, 4503)
		return
	try:
		auth = await _read_json_auth(websocket)
	except WsAuthClientDisconnected:
		return
	except WsAuthTimeout:
		await close_ws_safe(websocket, 4408)
		return
	except WsAuthRejected as e:
		await close_ws_safe(websocket, e.close_code)
		return

	api_key = str(auth.get("api_key") or "").strip()
	session_id = str(auth.get("session_id") or "").strip()
	media_ticket = str(auth.get("media_ticket") or "").strip()
	business_id = auth.get("business_id")
	try:
		business_id_i = int(business_id)
	except Exception:
		await close_ws_safe(websocket, 4400)
		return

	user_id = _auth_user_api_key(api_key)
	if user_id is None or not session_id or not media_ticket:
		await close_ws_safe(websocket, 4401)
		return

	db = _db()
	try:
		row = soft_svc.get_session_by_ticket(db, session_id, media_ticket)
		if row.user_id != user_id or row.business_id != business_id_i:
			await close_ws_safe(websocket, 4403)
			return
		soft_svc.mark_session_state(db, session_id, "registered")
		extension = row.extension
		pbx_id = row.pbx_id
	except Exception:
		await close_ws_safe(websocket, 4401)
		return
	finally:
		db.close()

	link = SoftphoneClientLink(
		session_id=session_id,
		business_id=business_id_i,
		pbx_id=pbx_id,
		user_id=user_id,
		extension=extension,
		websocket=websocket,
	)
	await media_hub.register_client(link)
	try:
		await websocket.send_json(
			{
				"type": "auth_ok",
				"session_id": session_id,
				"media_profile": link.media_profile,
				"media_hub": media_hub.health(),
				"tunnel_online": media_hub.tunnel_online(pbx_id),
			}
		)
	except Exception:
		await media_hub.unregister_client(session_id, reason="send_auth_ok_failed")
		return

	try:
		while True:
			msg = await websocket.receive()
			if msg.get("type") == "websocket.disconnect":
				break
			if "bytes" in msg and msg["bytes"] is not None:
				parsed = media_hub.unpack_pcm_frame(msg["bytes"])
				if parsed:
					_, sid, pcm = parsed
					await media_hub.forward_media_client_to_tunnel(sid or session_id, pcm)
				else:
					await media_hub.forward_media_client_to_tunnel(session_id, msg["bytes"])
				continue
			text = msg.get("text")
			if not text:
				continue
			try:
				payload = json.loads(text)
			except json.JSONDecodeError:
				continue
			await _handle_client_control(session_id, business_id_i, user_id, payload)
	except WebSocketDisconnect:
		pass
	except Exception as e:
		LOG.warning("softphone client ws error: %s", e)
	finally:
		await media_hub.unregister_client(session_id, reason="client_disconnect")
		db2 = _db()
		try:
			try:
				soft_svc.end_session(db2, business_id_i, user_id, session_id, reason="ws_disconnect")
			except Exception:
				soft_svc.mark_session_state(db2, session_id, "ended")
		finally:
			db2.close()


async def _handle_client_control(
	session_id: str,
	business_id: int,
	user_id: int,
	payload: dict[str, Any],
) -> None:
	typ = str(payload.get("type") or "")
	if typ == "ping":
		await media_hub.send_to_client(session_id, {"type": "pong", "ts": payload.get("ts")})
		return
	if typ == "mute":
		link = media_hub.get_client(session_id)
		if link:
			link.muted = bool(payload.get("muted", True))
			await media_hub.send_to_client(session_id, {"type": "mute_ok", "muted": link.muted})
		return
	if typ == "dtmf":
		digit = str(payload.get("digit") or "")
		call_id = payload.get("call_id")
		if digit and call_id is not None:
			db = _db()
			try:
				soft_svc.enqueue_dtmf(db, business_id, user_id, int(call_id), digit, session_id=session_id)
			finally:
				db.close()
		return
	if typ == "quality":
		link = media_hub.get_client(session_id)
		state = "in_call" if link and link.bridge_id else "registered"
		db = _db()
		try:
			soft_svc.mark_session_state(
				db,
				session_id,
				state,
				quality=payload.get("metrics") if isinstance(payload.get("metrics"), dict) else payload,
			)
		finally:
			db.close()
		return
	if typ == "hangup_media":
		await media_hub.stop_bridge(session_id, reason=str(payload.get("reason") or "client_hangup"))
		return


@router.websocket("/ws/telephony/connector/media")
async def connector_media_tunnel_ws(websocket: WebSocket) -> None:
	"""
	تونل خروجی رسانه Connector.

	اولین پیام:
	{
	  "type":"auth",
	  "connector_token":"...",
	  "business_id":1,
	  "pbx_id":2,
	  "capabilities":["audiosocket","pcm_ws_v1"]
	}
	"""
	from app.services.telephony.media_edge import is_media_edge_process

	await websocket.accept()
	if not is_media_edge_process():
		await close_ws_safe(websocket, 4503)
		return
	try:
		auth = await _read_json_auth(websocket)
	except WsAuthClientDisconnected:
		return
	except WsAuthTimeout:
		await close_ws_safe(websocket, 4408)
		return
	except WsAuthRejected as e:
		await close_ws_safe(websocket, e.close_code)
		return

	token = str(auth.get("connector_token") or auth.get("api_key") or "").strip()
	try:
		business_id = int(auth.get("business_id"))
		pbx_id = int(auth.get("pbx_id"))
	except Exception:
		await close_ws_safe(websocket, 4400)
		return
	capabilities = auth.get("capabilities") if isinstance(auth.get("capabilities"), list) else ["audiosocket", "pcm_ws_v1"]

	db = _db()
	try:
		pbx = tel_svc.authenticate_connector(db, token=token, business_id=business_id, pbx_id=pbx_id)
		tel_svc.connector_heartbeat(db, pbx, {"status": "ok", "media_tunnel": True})
	except Exception:
		await close_ws_safe(websocket, 4401)
		return
	finally:
		db.close()

	tunnel = await media_hub.register_tunnel(
		business_id=business_id,
		pbx_id=pbx_id,
		websocket=websocket,
		capabilities=[str(c) for c in capabilities],
	)
	try:
		await websocket.send_json(
			{
				"type": "auth_ok",
				"tunnel_id": tunnel.tunnel_id,
				"media_hub": media_hub.health(),
				"supported_profiles": ["pcm_ws_v1"],
			}
		)
	except Exception:
		await media_hub.unregister_tunnel(pbx_id, tunnel.tunnel_id)
		return

	try:
		while True:
			msg = await websocket.receive()
			if msg.get("type") == "websocket.disconnect":
				break
			await media_hub.touch_tunnel(pbx_id)
			if "bytes" in msg and msg["bytes"] is not None:
				parsed = media_hub.unpack_pcm_frame(msg["bytes"])
				if not parsed:
					continue
				_ftype, session_id, pcm = parsed
				await media_hub.forward_media_tunnel_to_client(session_id, pcm)
				continue
			text = msg.get("text")
			if not text:
				continue
			try:
				payload = json.loads(text)
			except json.JSONDecodeError:
				continue
			await _handle_tunnel_control(pbx_id, payload)
	except WebSocketDisconnect:
		pass
	except Exception as e:
		LOG.warning("connector media tunnel error pbx=%s: %s", pbx_id, e)
	finally:
		await media_hub.unregister_tunnel(pbx_id, tunnel.tunnel_id)


async def _handle_tunnel_control(pbx_id: int, payload: dict[str, Any]) -> None:
	typ = str(payload.get("type") or "")
	if typ == "ping":
		await media_hub.send_to_tunnel(pbx_id, {"type": "pong", "ts": payload.get("ts")})
		await media_hub.touch_tunnel(pbx_id)
		return
	if typ == "bridge.active":
		bridge_id = str(payload.get("bridge_id") or "")
		if bridge_id:
			await media_hub.mark_bridge_active(bridge_id)
		return
	if typ == "bridge.failed":
		session_id = str(payload.get("session_id") or "")
		if session_id:
			await media_hub.stop_bridge(session_id, reason=str(payload.get("reason") or "bridge_failed"))
			await media_hub.send_to_client(
				session_id,
				{"type": "bridge.failed", "reason": payload.get("reason"), "bridge_id": payload.get("bridge_id")},
			)
		return
	if typ == "incoming_softphone_ring":
		session_id = str(payload.get("session_id") or "")
		if session_id:
			await media_hub.send_to_client(
				session_id,
				{
					"type": "incoming_ring",
					"call_id": payload.get("call_id"),
					"from": payload.get("from"),
					"extension": payload.get("extension"),
				},
			)
		return
