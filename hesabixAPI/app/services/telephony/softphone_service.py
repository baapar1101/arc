"""سرویس Softphone — سشن، سلامت، خروجی relay، همگام‌سازی با CTI."""
from __future__ import annotations

import secrets
import uuid
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session, joinedload

from adapters.db.models.telephony import (
	TelephonyCall,
	TelephonyCommand,
	TelephonyPbxConnection,
	TelephonySoftphoneSession,
	TelephonyUserExtension,
)
from app.core.responses import ApiError
from app.core.security import hash_api_key
from app.services.realtime import realtime_manager
from app.services.telephony.media_edge import (
	fetch_media_edge_snapshot,
	is_media_edge_process,
	process_role,
	require_media_edge_process,
)
from app.services.telephony.media_hub import MEDIA_PROFILE_PCM_WS_V1, media_hub
from app.services.telephony import telephony_service as tel


def _now() -> datetime:
	return datetime.utcnow()


def _iso(dt: Optional[datetime]) -> Optional[str]:
	return dt.isoformat() if dt else None


SESSION_TTL_MINUTES = 120
VALID_ENDPOINT_MODES = ("relay", "direct", "desk")
ACTIVE_SESSION_STATES = ("creating", "registered", "ringing", "in_call")


def softphone_settings_from_pbx(pbx: TelephonyPbxConnection) -> Dict[str, Any]:
	settings = dict(pbx.settings or {})
	soft = dict(settings.get("softphone") or {})
	soft.setdefault("relay_enabled", True)
	soft.setdefault("direct_enabled", False)
	soft.setdefault("media_codec_prefs", ["pcm_ws_v1"])
	soft.setdefault("max_concurrent_softphone_sessions", 50)
	soft.setdefault("audiosocket_host", "127.0.0.1")
	soft.setdefault("audiosocket_port", 9092)
	return soft


def session_to_dict(row: TelephonySoftphoneSession, *, include_secrets: bool = False) -> Dict[str, Any]:
	out: Dict[str, Any] = {
		"id": row.id,
		"session_id": row.session_id,
		"business_id": row.business_id,
		"pbx_id": row.pbx_id,
		"user_id": row.user_id,
		"extension": row.extension,
		"mode": row.mode,
		"state": row.state,
		"media_edge_node": row.media_edge_node,
		"connector_tunnel_id": row.connector_tunnel_id,
		"call_id": row.call_id,
		"ice_policy": row.ice_policy,
		"turn_used": bool(row.turn_used),
		"last_quality": row.last_quality_json or {},
		"client_info": row.client_info or {},
		"last_heartbeat_at": _iso(row.last_heartbeat_at),
		"expires_at": _iso(row.expires_at),
		"ended_at": _iso(row.ended_at),
		"end_reason": row.end_reason,
		"created_at": _iso(row.created_at),
		"updated_at": _iso(row.updated_at),
	}
	if include_secrets:
		out["media_ticket_prefix"] = row.media_ticket_prefix
	return out


def _primary_user_extension(db: Session, business_id: int, user_id: int) -> TelephonyUserExtension:
	row = (
		db.query(TelephonyUserExtension)
		.options(joinedload(TelephonyUserExtension.extension_row))
		.filter(
			TelephonyUserExtension.business_id == business_id,
			TelephonyUserExtension.user_id == user_id,
		)
		.order_by(TelephonyUserExtension.is_primary.desc(), TelephonyUserExtension.id.asc())
		.first()
	)
	if not row or not row.extension_row:
		raise ApiError(
			"SOFTPHONE_NO_EXTENSION",
			"برای Softphone باید داخلی به کاربر نگاشت شده باشد.",
			http_status=400,
		)
	return row


def _resolve_mode(link: TelephonyUserExtension, soft: Dict[str, Any], requested: Optional[str]) -> str:
	mode = (requested or link.endpoint_mode or "desk").strip().lower()
	if mode not in VALID_ENDPOINT_MODES:
		raise ApiError("VALIDATION_ERROR", "endpoint_mode نامعتبر است.", http_status=400)
	if mode == "desk":
		raise ApiError(
			"SOFTPHONE_DESK_MODE",
			"حالت این کاربر desk است؛ از Click-to-Call استفاده کنید یا حالت را به relay/direct تغییر دهید.",
			http_status=400,
		)
	if mode == "relay" and not soft.get("relay_enabled", True):
		if link.allow_mode_fallback and soft.get("direct_enabled"):
			return "direct"
		raise ApiError("SOFTPHONE_RELAY_DISABLED", "حالت رله روی این PBX غیرفعال است.", http_status=400)
	if mode == "direct" and not soft.get("direct_enabled", False):
		if link.allow_mode_fallback and soft.get("relay_enabled", True):
			return "relay"
		raise ApiError("SOFTPHONE_DIRECT_DISABLED", "حالت مستقیم روی این PBX غیرفعال است.", http_status=400)
	return mode


def softphone_health(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
	try:
		link = _primary_user_extension(db, business_id, user_id)
		pbx = db.get(TelephonyPbxConnection, link.pbx_id)
	except ApiError:
		hub = media_hub.health() if is_media_edge_process() else (fetch_media_edge_snapshot() or {}).get("media_hub")
		return {
			"ok": False,
			"reason": "no_extension",
			"media_hub": hub or media_hub.health(),
			"tunnel": None,
			"endpoint_mode": None,
			"process_role": process_role(),
			"ws_client_connected": False,
		}
	soft = softphone_settings_from_pbx(pbx) if pbx else {}
	if is_media_edge_process():
		hub = media_hub.health()
		tunnel = media_hub.tunnel_snapshot(link.pbx_id) if pbx else None
	else:
		snap = fetch_media_edge_snapshot(pbx_id=link.pbx_id) or {}
		hub = snap.get("media_hub") or {"node_id": None, "clients": 0, "tunnels": 0, "bridges": 0}
		tunnel = snap.get("tunnel")
	active = (
		db.query(TelephonySoftphoneSession)
		.filter(
			TelephonySoftphoneSession.business_id == business_id,
			TelephonySoftphoneSession.user_id == user_id,
			TelephonySoftphoneSession.state.in_(ACTIVE_SESSION_STATES),
			TelephonySoftphoneSession.expires_at > _now(),
		)
		.order_by(TelephonySoftphoneSession.id.desc())
		.first()
	)
	ws_connected = bool(active and is_media_edge_process() and media_hub.get_client(active.session_id))
	if active and not is_media_edge_process():
		# روی API worker فقط از شمارش clients لبه تقریبی نداریم؛ state DB را گزارش می‌کنیم
		ws_connected = bool(active.state in ("registered", "ringing", "in_call"))
	ok = bool(pbx and pbx.status == "online" and (tunnel and tunnel.get("online")))
	if link.endpoint_mode == "direct" and soft.get("direct_enabled"):
		ok = bool(pbx and pbx.is_active)
	return {
		"ok": ok,
		"reason": None if ok else ("tunnel_offline" if not (tunnel and tunnel.get("online")) else "pbx_offline"),
		"endpoint_mode": link.endpoint_mode,
		"extension": link.extension_row.extension if link.extension_row else None,
		"pbx_id": link.pbx_id,
		"pbx_status": pbx.status if pbx else None,
		"softphone_settings": soft,
		"tunnel": tunnel,
		"active_session": session_to_dict(active) if active else None,
		"media_hub": hub,
		"supported_profiles": [MEDIA_PROFILE_PCM_WS_V1],
		"process_role": process_role(),
		"ws_client_connected": ws_connected,
	}


def create_session(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	payload = payload or {}
	require_media_edge_process()
	link = _primary_user_extension(db, business_id, user_id)
	pbx = db.get(TelephonyPbxConnection, link.pbx_id)
	if not pbx or not pbx.is_active:
		raise ApiError("PBX_NOT_FOUND", "مرکز تلفن فعال یافت نشد.", http_status=404)
	soft = softphone_settings_from_pbx(pbx)
	mode = _resolve_mode(link, soft, payload.get("mode") or link.endpoint_mode)

	if mode == "relay" and not media_hub.tunnel_online(pbx.id):
		raise ApiError(
			"SOFTPHONE_TUNNEL_OFFLINE",
			"تونل رسانه Connector قطع است. روی سرور تلفن Connector را به‌روز و سرویس را ری‌استارت کنید.",
			http_status=503,
		)

	# پایان سشن‌های قبلی همان کاربر
	old_rows = (
		db.query(TelephonySoftphoneSession)
		.filter(
			TelephonySoftphoneSession.business_id == business_id,
			TelephonySoftphoneSession.user_id == user_id,
			TelephonySoftphoneSession.state.in_(ACTIVE_SESSION_STATES),
		)
		.all()
	)
	for old in old_rows:
		old.state = "ended"
		old.ended_at = _now()
		old.end_reason = "replaced"
		old.updated_at = _now()

	active_count = (
		db.query(TelephonySoftphoneSession)
		.filter(
			TelephonySoftphoneSession.pbx_id == pbx.id,
			TelephonySoftphoneSession.state.in_(ACTIVE_SESSION_STATES),
			TelephonySoftphoneSession.expires_at > _now(),
		)
		.count()
	)
	max_sessions = int(soft.get("max_concurrent_softphone_sessions") or 50)
	if active_count >= max_sessions:
		raise ApiError("SOFTPHONE_CAPACITY", "سقف سشن همزمان Softphone پر است.", http_status=429)

	session_id = str(uuid.uuid4())
	ticket = "hsx_media_" + secrets.token_urlsafe(24)
	ticket_hash = hash_api_key(ticket)
	now = _now()
	row = TelephonySoftphoneSession(
		session_id=session_id,
		business_id=business_id,
		pbx_id=pbx.id,
		user_id=user_id,
		extension=link.extension_row.extension,
		mode=mode,
		state="creating",
		media_ticket_hash=ticket_hash,
		media_ticket_prefix=ticket[:16],
		media_edge_node=media_hub.node_id,
		connector_tunnel_id=(media_hub.tunnel_snapshot(pbx.id) or {}).get("tunnel_id"),
		ice_policy="relay_first" if mode == "relay" else "all",
		client_info=payload.get("client_info") if isinstance(payload.get("client_info"), dict) else {},
		last_heartbeat_at=now,
		expires_at=now + timedelta(minutes=SESSION_TTL_MINUTES),
		created_at=now,
		updated_at=now,
	)
	db.add(row)
	db.commit()
	db.refresh(row)

	devices = softphone_devices_config(db, business_id, pbx)
	return {
		"session": session_to_dict(row),
		"media_ticket": ticket,
		"ws_path": "/ws/telephony/softphone",
		"media_profile": MEDIA_PROFILE_PCM_WS_V1,
		"devices_config": devices,
		"health": softphone_health(db, business_id, user_id),
	}


def heartbeat_session(db: Session, business_id: int, user_id: int, session_id: str) -> Dict[str, Any]:
	row = _get_user_session(db, business_id, user_id, session_id)
	if row.state not in ACTIVE_SESSION_STATES:
		raise ApiError("SOFTPHONE_SESSION_ENDED", "سشن Softphone پایان یافته است.", http_status=409)
	row.last_heartbeat_at = _now()
	row.expires_at = _now() + timedelta(minutes=SESSION_TTL_MINUTES)
	row.updated_at = _now()
	# فقط وقتی WebSocket واقعاً روی همین Media Edge ثبت شده، creating→registered
	# (قبلاً heartbeat بدون WS سشن را registered می‌کرد و UI فکر می‌کرد آنلاین است)
	if row.state == "creating" and is_media_edge_process() and media_hub.get_client(session_id):
		row.state = "registered"
	db.commit()
	db.refresh(row)
	return session_to_dict(row)


def end_session(
	db: Session,
	business_id: int,
	user_id: int,
	session_id: str,
	*,
	reason: str = "logout",
) -> Dict[str, Any]:
	row = _get_user_session(db, business_id, user_id, session_id)
	row.state = "ended"
	row.ended_at = _now()
	row.end_reason = reason
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return session_to_dict(row)


def _get_user_session(
	db: Session, business_id: int, user_id: int, session_id: str
) -> TelephonySoftphoneSession:
	row = (
		db.query(TelephonySoftphoneSession)
		.filter(
			TelephonySoftphoneSession.session_id == session_id,
			TelephonySoftphoneSession.business_id == business_id,
			TelephonySoftphoneSession.user_id == user_id,
		)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "سشن Softphone یافت نشد.", http_status=404)
	return row


def get_session_by_ticket(db: Session, session_id: str, media_ticket: str) -> TelephonySoftphoneSession:
	row = (
		db.query(TelephonySoftphoneSession)
		.filter(TelephonySoftphoneSession.session_id == session_id)
		.first()
	)
	if not row or row.state not in ACTIVE_SESSION_STATES:
		raise ApiError("UNAUTHORIZED", "سشن نامعتبر است.", http_status=401)
	if row.expires_at < _now():
		raise ApiError("UNAUTHORIZED", "سشن منقضی شده است.", http_status=401)
	if hash_api_key(media_ticket) != row.media_ticket_hash:
		raise ApiError("UNAUTHORIZED", "بلیت رسانه نامعتبر است.", http_status=401)
	return row


def softphone_devices_config(
	db: Session, business_id: int, pbx: Optional[TelephonyPbxConnection] = None
) -> Dict[str, Any]:
	# TURN از تنظیمات سیستم/محیط قابل تزریق است؛ پیش‌فرض فقط STUN عمومی برای Direct
	from app.core.settings import get_settings

	settings = get_settings()
	ice_servers: List[Dict[str, Any]] = [{"urls": ["stun:stun.l.google.com:19302"]}]
	turn_url = getattr(settings, "telephony_turn_url", None) or None
	turn_user = getattr(settings, "telephony_turn_username", None) or None
	turn_pass = getattr(settings, "telephony_turn_password", None) or None
	if turn_url:
		entry: Dict[str, Any] = {"urls": [turn_url]}
		if turn_user:
			entry["username"] = turn_user
		if turn_pass:
			entry["credential"] = turn_pass
		ice_servers.append(entry)
	return {
		"ice_servers": ice_servers,
		"media_profile": MEDIA_PROFILE_PCM_WS_V1,
		"pcm": {"sample_rate": 8000, "channels": 1, "encoding": "pcm_s16le", "frame_ms": 20},
		"business_id": business_id,
		"pbx_id": pbx.id if pbx else None,
	}


def mark_session_state(
	db: Session,
	session_id: str,
	state: str,
	*,
	call_id: Optional[int] = None,
	quality: Optional[Dict[str, Any]] = None,
) -> None:
	row = (
		db.query(TelephonySoftphoneSession)
		.filter(TelephonySoftphoneSession.session_id == session_id)
		.first()
	)
	if not row:
		return
	row.state = state
	if call_id is not None:
		row.call_id = call_id
	if quality is not None:
		row.last_quality_json = quality
	row.updated_at = _now()
	db.commit()


async def notify_softphone_event(user_id: int, business_id: int, event_type: str, payload: Dict[str, Any]) -> None:
	try:
		await realtime_manager.send_to_user(
			user_id,
			{
				"type": event_type,
				"business_id": business_id,
				**payload,
			},
		)
	except Exception:
		pass


def start_outbound_relay_call(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	"""شروع تماس خروجی در حالت relay: پل رسانه + Originate سمت مقصد."""
	require_media_edge_process()
	session_id = str(payload.get("session_id") or "").strip()
	destination = str(payload.get("destination") or "").strip()
	if not session_id or not destination:
		raise ApiError("VALIDATION_ERROR", "session_id و destination الزامی است.", http_status=400)

	row = _get_user_session(db, business_id, user_id, session_id)
	if row.mode != "relay":
		raise ApiError("SOFTPHONE_MODE", "خروجی relay فقط در حالت relay مجاز است.", http_status=400)
	if row.state not in ("registered", "in_call"):
		raise ApiError(
			"SOFTPHONE_SESSION_STATE",
			"سشن برای تماس آماده نیست. ابتدا Softphone را آنلاین کنید تا WebSocket وصل شود.",
			http_status=409,
		)
	if not media_hub.get_client(session_id):
		raise ApiError(
			"SOFTPHONE_WS_REQUIRED",
			"کانال Softphone روی Media Edge ثبت نشده است. صفحه را رفرش کنید و دوباره آنلاین شوید.",
			http_status=409,
		)
	if not media_hub.tunnel_online(row.pbx_id):
		raise ApiError("SOFTPHONE_TUNNEL_OFFLINE", "تونل رسانه قطع است.", http_status=503)

	# از مسیر CTI موجود برای ساخت تماس/دستور استفاده می‌کنیم با payload ویژه softphone
	from app.services.telephony.phone_normalizer import normalize_iran_phone

	norm = normalize_iran_phone(destination)
	pbx = db.get(TelephonyPbxConnection, row.pbx_id)
	if not pbx:
		raise ApiError("PBX_NOT_FOUND", "PBX یافت نشد.", http_status=404)
	soft = softphone_settings_from_pbx(pbx)
	settings = pbx.settings or {}
	context = settings.get("originate_context") or "from-internal"
	timeout_ms = int(settings.get("originate_timeout_ms") or 30000)

	uniqueid = f"hsx-sf-{uuid.uuid4().hex[:16]}"
	call = TelephonyCall(
		business_id=business_id,
		pbx_id=row.pbx_id,
		asterisk_uniqueid=uniqueid,
		asterisk_linkedid=uniqueid,
		direction="outbound",
		status="ringing",
		from_number_raw=row.extension,
		from_number_normalized=row.extension,
		to_number_raw=destination,
		to_number_normalized=norm.get("canonical") or destination,
		extension=row.extension,
		started_at=_now(),
		assigned_user_id=user_id,
		person_id=payload.get("person_id"),
		lead_id=payload.get("lead_id"),
		match_method="manual" if payload.get("person_id") or payload.get("lead_id") else None,
		is_anonymous=False,
		extra_info={"softphone": True, "session_id": session_id, "mode": "relay"},
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(call)
	db.flush()

	as_uuid = str(uuid.uuid4())
	cmd = TelephonyCommand(
		business_id=business_id,
		pbx_id=row.pbx_id,
		command_id=str(uuid.uuid4()),
		command_type="softphone_bridge_out",
		payload={
			"type": "softphone_bridge_out",
			"session_id": session_id,
			"extension": row.extension,
			"destination": destination,
			"context": context,
			"timeout_ms": timeout_ms,
			"audiosocket_uuid": as_uuid,
			"audiosocket_host": soft.get("audiosocket_host") or "127.0.0.1",
			"audiosocket_port": int(soft.get("audiosocket_port") or 9092),
			"call_id": call.id,
			"uniqueid": uniqueid,
		},
		status="pending",
		created_by_user_id=user_id,
		call_id=call.id,
		created_at=_now(),
		expires_at=_now() + timedelta(seconds=120),
	)
	db.add(cmd)
	row.state = "ringing"
	row.call_id = call.id
	row.updated_at = _now()
	db.commit()
	db.refresh(call)

	return {
		"call": tel.call_to_dict(call),
		"session_id": session_id,
		"audiosocket_uuid": as_uuid,
		"command_id": cmd.command_id,
	}


def enqueue_answer_inbound(
	db: Session,
	business_id: int,
	user_id: int,
	call_id: int,
	payload: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	payload = payload or {}
	require_media_edge_process()
	session_id = str(payload.get("session_id") or "").strip()
	row = _get_user_session(db, business_id, user_id, session_id) if session_id else None
	if row is None:
		# آخرین سشن فعال
		row = (
			db.query(TelephonySoftphoneSession)
			.filter(
				TelephonySoftphoneSession.business_id == business_id,
				TelephonySoftphoneSession.user_id == user_id,
				TelephonySoftphoneSession.state.in_(ACTIVE_SESSION_STATES),
			)
			.order_by(TelephonySoftphoneSession.id.desc())
			.first()
		)
	if not row:
		raise ApiError("SOFTPHONE_NO_SESSION", "سشن Softphone فعال نیست.", http_status=409)
	if not media_hub.get_client(row.session_id):
		raise ApiError(
			"SOFTPHONE_WS_REQUIRED",
			"کانال Softphone روی Media Edge ثبت نشده است. صفحه را رفرش کنید و دوباره آنلاین شوید.",
			http_status=409,
		)

	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not call:
		raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)

	as_uuid = str(uuid.uuid4())
	soft = softphone_settings_from_pbx(db.get(TelephonyPbxConnection, row.pbx_id))
	cmd = TelephonyCommand(
		business_id=business_id,
		pbx_id=row.pbx_id,
		command_id=str(uuid.uuid4()),
		command_type="softphone_bridge_in",
		payload={
			"type": "softphone_bridge_in",
			"session_id": row.session_id,
			"extension": row.extension,
			"call_id": call.id,
			"uniqueid": call.asterisk_uniqueid,
			"channel": (call.extra_info or {}).get("channel"),
			"audiosocket_uuid": as_uuid,
			"audiosocket_host": soft.get("audiosocket_host") or "127.0.0.1",
			"audiosocket_port": int(soft.get("audiosocket_port") or 9092),
		},
		status="pending",
		created_by_user_id=user_id,
		call_id=call.id,
		created_at=_now(),
		expires_at=_now() + timedelta(seconds=60),
	)
	db.add(cmd)
	row.state = "in_call"
	row.call_id = call.id
	row.updated_at = _now()
	call.status = "answered"
	if not call.answered_at:
		call.answered_at = _now()
	call.updated_at = _now()
	db.commit()
	return {
		"call": tel.call_to_dict(call),
		"session_id": row.session_id,
		"audiosocket_uuid": as_uuid,
		"command_id": cmd.command_id,
	}


def enqueue_dtmf(
	db: Session,
	business_id: int,
	user_id: int,
	call_id: int,
	digit: str,
	session_id: Optional[str] = None,
) -> Dict[str, Any]:
	digit = (digit or "").strip()
	if not digit or len(digit) > 8:
		raise ApiError("VALIDATION_ERROR", "رقم DTMF نامعتبر است.", http_status=400)
	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not call:
		raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)
	cmd = TelephonyCommand(
		business_id=business_id,
		pbx_id=call.pbx_id,
		command_id=str(uuid.uuid4()),
		command_type="softphone_dtmf",
		payload={
			"type": "softphone_dtmf",
			"call_id": call.id,
			"digit": digit,
			"channel": (call.extra_info or {}).get("channel"),
			"session_id": session_id,
		},
		status="pending",
		created_by_user_id=user_id,
		call_id=call.id,
		created_at=_now(),
		expires_at=_now() + timedelta(seconds=30),
	)
	db.add(cmd)
	db.commit()
	return {"accepted": True, "command_id": cmd.command_id}
