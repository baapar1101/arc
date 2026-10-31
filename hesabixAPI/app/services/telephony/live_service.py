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
from app.services.telephony.telephony_access import TelephonyScope, require_call_in_scope, resolve_scope, write_audit
from app.services.telephony.telephony_service import call_to_dict, extension_to_dict, list_pbx


def _now() -> datetime:
	return datetime.utcnow()


def live_snapshot(db: Session, business_id: int, *, auth_ctx=None) -> Dict[str, Any]:
	scope: Optional[TelephonyScope] = resolve_scope(db, auth_ctx, business_id) if auth_ctx is not None else None
	active_q = (
		db.query(TelephonyCall)
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.status.in_(["ringing", "answered"]),
			TelephonyCall.ended_at.is_(None),
		)
		.order_by(TelephonyCall.started_at.desc())
	)
	if scope is not None:
		active_q = scope.apply_call_filter(active_q)
	active = active_q.limit(100).all()
	waiting = [c for c in active if c.status == "ringing"]
	talking = [c for c in active if c.status == "answered"]
	exts_q = (
		db.query(TelephonyExtension)
		.filter(TelephonyExtension.business_id == business_id, TelephonyExtension.is_active == True)  # noqa: E712
	)
	if scope is not None and not scope.view_all:
		if scope.extension_ids:
			exts_q = exts_q.filter(TelephonyExtension.id.in_(list(scope.extension_ids)))
		else:
			exts_q = exts_q.filter(TelephonyExtension.id == -1)
	exts = exts_q.order_by(TelephonyExtension.extension.asc()).all()
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
	if scope is not None and not scope.view_all:
		if scope.team_codes:
			queues = [q for q in queues if scope.allows_queue(q.queue_code)]
		else:
			queues = []
	if scope is not None and not scope.view_all:
		if scope.team_codes:
			queues = [q for q in queues if str(q.queue_code or "") in scope.team_codes]
		else:
			queues = []
	today = _now().replace(hour=0, minute=0, second=0, microsecond=0)
	missed_q = db.query(TelephonyCall).filter(
		TelephonyCall.business_id == business_id,
		TelephonyCall.status == "missed",
		TelephonyCall.started_at >= today,
	)
	if scope is not None:
		missed_q = scope.apply_call_filter(missed_q)
	missed_today = missed_q.count()
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
		"pbx": list_pbx(db, business_id, include_token_hint=bool(scope.can_manage) if scope else False),
		"access": scope.to_dict() if scope else None,
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
	auth_ctx=None,
	call_id: Optional[int] = None,
	extension: Optional[str] = None,
	target: Optional[str] = None,
	pbx_id: Optional[int] = None,
	session_id: Optional[str] = None,
) -> Dict[str, Any]:
	if command_type not in ("hangup", "transfer", "hold", "resume"):
		raise ApiError("INVALID_COMMAND_TYPE", "INVALID_COMMAND_TYPE", http_status=400)

	call = None
	scope = resolve_scope(db, auth_ctx, business_id) if auth_ctx is not None else None
	if call_id:
		if auth_ctx is not None:
			call = require_call_in_scope(db, auth_ctx, business_id, call_id, scope=scope)
		else:
			call = (
				db.query(TelephonyCall)
				.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
				.first()
			)
			if not call:
				raise ApiError("CALL_NOT_FOUND", "CALL_NOT_FOUND", http_status=404)
		pbx_id = call.pbx_id
		extension = extension or call.extension
	elif scope is not None and extension and not scope.allows_extension(extension):
		raise ApiError("EXTENSION_OUT_OF_SCOPE", "EXTENSION_OUT_OF_SCOPE", http_status=404)

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
			raise ApiError("NO_EXTENSION", "NO_EXTENSION", http_status=400)
		pbx_id = link.pbx_id
		extension = extension or (link.extension_row.extension if link.extension_row else None)

	pbx = (
		db.query(TelephonyPbxConnection)
		.filter(TelephonyPbxConnection.id == pbx_id, TelephonyPbxConnection.business_id == business_id)
		.first()
	)
	if not pbx or not pbx.is_active:
		raise ApiError("PBX_OFFLINE", "PBX_OFFLINE", http_status=400)

	command_id = str(uuid.uuid4())
	extra = dict(call.extra_info or {}) if call else {}
	from app.services.telephony.ami_channels import expand_hangup_channels

	channels = expand_hangup_channels(
		[extra.get("dest_channel"), extra.get("channel")],
	)
	payload = {
		"type": command_type,
		"extension": extension,
		"target": target,
		"asterisk_uniqueid": call.asterisk_uniqueid if call else None,
		"linkedid": call.asterisk_linkedid if call else None,
		"channel": extra.get("dest_channel") or extra.get("channel"),
		"channels": channels,
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
	write_audit(
		db,
		business_id=business_id,
		user_id=user_id,
		action="control_call",
		call_id=call.id if call else None,
		target=command_type,
		extra={"target_extension": target},
	)
	db.commit()
	return {"ok": True, "command_id": command_id, "type": command_type, "call_id": call.id if call else None}
