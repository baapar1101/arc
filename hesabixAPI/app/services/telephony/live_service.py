"""داشبورد زنده، BLF و کنترل تماس."""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session, joinedload

from adapters.db.models.telephony import (
	TelephonyCall,
	TelephonyCommand,
	TelephonyExtension,
	TelephonyPbxConnection,
	TelephonyQueue,
	TelephonyUserExtension,
)
from app.core.responses import ApiError
from app.services.telephony.telephony_service import call_to_dict, extension_to_dict, list_pbx


def _now() -> datetime:
	return datetime.utcnow()


def live_snapshot(db: Session, business_id: int) -> Dict[str, Any]:
	active = (
		db.query(TelephonyCall)
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.status.in_(["ringing", "answered"]),
			TelephonyCall.ended_at.is_(None),
		)
		.order_by(TelephonyCall.started_at.desc())
		.limit(100)
		.all()
	)
	waiting = [c for c in active if c.status == "ringing"]
	talking = [c for c in active if c.status == "answered"]
	exts = (
		db.query(TelephonyExtension)
		.filter(TelephonyExtension.business_id == business_id, TelephonyExtension.is_active == True)  # noqa: E712
		.order_by(TelephonyExtension.extension.asc())
		.all()
	)
	# refresh stale presence to unavailable if PBX offline
	pbx_status = {p["id"]: p["status"] for p in list_pbx(db, business_id)}
	blf = []
	for e in exts:
		presence = e.presence_status
		if pbx_status.get(e.pbx_id) != "online" and presence not in ("busy", "ringing"):
			presence = "unavailable"
		# derive from active calls
		on_call = next((c for c in active if c.extension == e.extension), None)
		if on_call:
			presence = "ringing" if on_call.status == "ringing" else "busy"
		blf.append({**extension_to_dict(e), "presence_status": presence, "active_call_id": on_call.id if on_call else None})

	queues = (
		db.query(TelephonyQueue)
		.filter(TelephonyQueue.business_id == business_id, TelephonyQueue.is_active == True)  # noqa: E712
		.all()
	)
	today = _now().replace(hour=0, minute=0, second=0, microsecond=0)
	missed_today = (
		db.query(TelephonyCall)
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.status == "missed",
			TelephonyCall.started_at >= today,
		)
		.count()
	)
	online_ops = len([b for b in blf if b["presence_status"] in ("idle", "busy", "ringing")])
	return {
		"generated_at": _now().isoformat(),
		"kpis": {
			"active": len(active),
			"waiting": len(waiting),
			"talking": len(talking),
			"missed_today": missed_today,
			"operators_online": online_ops,
		},
		"active_calls": [call_to_dict(c) for c in active],
		"blf": blf,
		"queues": [
			{
				"id": q.id,
				"queue_code": q.queue_code,
				"name": q.name,
				"waiting": q.live_waiting_count,
				"talking": q.live_talking_count,
			}
			for q in queues
		],
		"pbx": list_pbx(db, business_id),
	}


def update_presence_from_event(
	db: Session, business_id: int, extension: Optional[str], status: str
) -> None:
	if not extension:
		return
	rows = (
		db.query(TelephonyExtension)
		.filter(TelephonyExtension.business_id == business_id, TelephonyExtension.extension == extension)
		.all()
	)
	for row in rows:
		row.presence_status = status
		row.presence_updated_at = _now()
		row.updated_at = _now()


def enqueue_control_command(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	command_type: str,
	call_id: Optional[int] = None,
	extension: Optional[str] = None,
	target: Optional[str] = None,
	pbx_id: Optional[int] = None,
	session_id: Optional[str] = None,
) -> Dict[str, Any]:
	if command_type not in ("hangup", "transfer", "hold", "resume"):
		raise ApiError("VALIDATION_ERROR", "نوع دستور نامعتبر است.", http_status=400)

	call = None
	if call_id:
		call = (
			db.query(TelephonyCall)
			.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
			.first()
		)
		if not call:
			raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)
		pbx_id = call.pbx_id
		extension = extension or call.extension

	if not pbx_id:
		# pick primary extension pbx for user
		link = (
			db.query(TelephonyUserExtension)
			.options(joinedload(TelephonyUserExtension.extension_row))
			.filter(
				TelephonyUserExtension.business_id == business_id,
				TelephonyUserExtension.user_id == user_id,
				TelephonyUserExtension.is_primary == True,  # noqa: E712
			)
			.first()
		)
		if not link:
			raise ApiError("NO_EXTENSION", "داخلی برای کنترل تماس تعریف نشده.", http_status=400)
		pbx_id = link.pbx_id
		extension = extension or (link.extension_row.extension if link.extension_row else None)

	pbx = (
		db.query(TelephonyPbxConnection)
		.filter(TelephonyPbxConnection.id == pbx_id, TelephonyPbxConnection.business_id == business_id)
		.first()
	)
	if not pbx or not pbx.is_active:
		raise ApiError("PBX_OFFLINE", "مرکز تلفن در دسترس نیست.", http_status=400)

	command_id = str(uuid.uuid4())
	extra = dict(call.extra_info or {}) if call else {}
	payload = {
		"extension": extension,
		"target": target,
		"asterisk_uniqueid": call.asterisk_uniqueid if call else None,
		"channel": extra.get("channel"),
		"session_id": session_id or extra.get("session_id"),
		"audiosocket_uuid": extra.get("audiosocket_uuid"),
	}
	cmd = TelephonyCommand(
		business_id=business_id,
		pbx_id=pbx.id,
		command_id=command_id,
		command_type=command_type,
		payload=payload,
		status="pending",
		created_by_user_id=user_id,
		call_id=call.id if call else None,
		created_at=_now(),
		expires_at=_now() + timedelta(minutes=1),
	)
	db.add(cmd)
	db.commit()
	return {"ok": True, "command_id": command_id, "type": command_type, "call_id": call.id if call else None}
