"""سرویس‌های اصلی افزونه تلفن: تنظیمات، PBX، داخلی، تماس، Click-to-Call."""
from __future__ import annotations

import secrets
import uuid
import json
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session, joinedload

from adapters.db.models.crm import CrmActivity, Lead
from adapters.db.models.person import Person
from adapters.db.models.telephony import (
	TelephonyCall,
	TelephonyCallEvent,
	TelephonyCommand,
	TelephonyExtension,
	TelephonyNumberAlias,
	TelephonyPbxConnection,
	TelephonySettings,
	TelephonyUserExtension,
)
from adapters.db.models.user import User
from app.core.responses import ApiError
from app.core.security import generate_api_key, hash_api_key
from app.core.telephony_plugin_dependency import check_telephony_plugin_active
from app.services.telephony.phone_normalizer import extract_digits, normalize_iran_phone, numbers_match
from app.services.realtime import realtime_manager


DEFAULT_PHONE_FIELDS = ["mobile", "mobile_2", "mobile_3", "phone"]


def _iso(dt: Optional[datetime]) -> Optional[str]:
	return dt.isoformat() if dt else None


def _now() -> datetime:
	return datetime.utcnow()


# ─── Settings ───────────────────────────────────────────────────────────────


def get_or_create_settings(db: Session, business_id: int) -> TelephonySettings:
	row = db.query(TelephonySettings).filter(TelephonySettings.business_id == business_id).first()
	if row:
		return row
	row = TelephonySettings(
		business_id=business_id,
		primary_phone_fields=list(DEFAULT_PHONE_FIELDS),
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	return row


def settings_to_dict(row: TelephonySettings) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"primary_phone_fields": row.primary_phone_fields or list(DEFAULT_PHONE_FIELDS),
		"number_normalization_rules": row.number_normalization_rules or {},
		"screen_pop_enabled": bool(row.screen_pop_enabled),
		"auto_create_activity": bool(row.auto_create_activity),
		"post_call_form_required": bool(row.post_call_form_required),
		"default_category": row.default_category,
		"missed_call_create_task": bool(row.missed_call_create_task),
		"missed_call_task_due_minutes": row.missed_call_task_due_minutes,
		"recording_access_mode": row.recording_access_mode,
		"multi_pbx_enabled": bool(row.multi_pbx_enabled),
		"ui_preferences": row.ui_preferences or {},
		"extra_settings": row.extra_settings or {},
		"updated_at": _iso(row.updated_at),
	}


def update_settings(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	row = get_or_create_settings(db, business_id)
	for key in (
		"primary_phone_fields",
		"number_normalization_rules",
		"screen_pop_enabled",
		"auto_create_activity",
		"post_call_form_required",
		"default_category",
		"missed_call_create_task",
		"missed_call_task_due_minutes",
		"recording_access_mode",
		"multi_pbx_enabled",
		"ui_preferences",
		"extra_settings",
	):
		if key in payload:
			setattr(row, key, payload[key])
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return settings_to_dict(row)


# ─── PBX ────────────────────────────────────────────────────────────────────


def pbx_to_dict(row: TelephonyPbxConnection, *, include_token_hint: bool = True) -> Dict[str, Any]:
	offline = False
	if row.last_seen_at:
		offline = (_now() - row.last_seen_at) > timedelta(minutes=3)
	status = row.status
	if status == "online" and offline:
		status = "offline"
	return {
		"id": row.id,
		"business_id": row.business_id,
		"name": row.name,
		"pbx_type": row.pbx_type,
		"host_hint": row.host_hint,
		"connector_token_prefix": row.connector_token_prefix if include_token_hint else None,
		"connector_version": row.connector_version,
		"last_seen_at": _iso(row.last_seen_at),
		"status": status,
		"last_error": row.last_error,
		"settings": row.settings or {},
		"is_active": bool(row.is_active),
		"created_at": _iso(row.created_at),
		"updated_at": _iso(row.updated_at),
	}


def list_pbx(db: Session, business_id: int) -> List[Dict[str, Any]]:
	rows = (
		db.query(TelephonyPbxConnection)
		.filter(TelephonyPbxConnection.business_id == business_id)
		.order_by(TelephonyPbxConnection.id.asc())
		.all()
	)
	return [pbx_to_dict(r) for r in rows]


def create_pbx(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	name = (payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "نام مرکز تلفن الزامی است.", http_status=400)
	api_key, key_hash = generate_api_key(prefix="hsx_tel_", length=36)
	row = TelephonyPbxConnection(
		business_id=business_id,
		name=name,
		pbx_type=(payload.get("pbx_type") or "issabel").strip(),
		host_hint=(payload.get("host_hint") or None),
		connector_token_hash=key_hash,
		connector_token_prefix=api_key[:12],
		settings=payload.get("settings") or {
			"originate_context": "from-internal",
			"originate_timeout_ms": 30000,
			"softphone": {
				"relay_enabled": True,
				"direct_enabled": False,
				"media_codec_prefs": ["pcm_ws_v1"],
				"max_concurrent_softphone_sessions": 50,
				"audiosocket_host": "127.0.0.1",
				"audiosocket_port": 9092,
			},
		},
		status="pending",
		is_active=True,
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	data = pbx_to_dict(row)
	data["connector_token"] = api_key  # فقط یک‌بار
	data["install_hint"] = (
		"توکن را فقط یک‌بار کپی کنید و در فایل تنظیمات Connector روی سرور Issabel قرار دهید."
	)
	return data


def rotate_pbx_token(db: Session, business_id: int, pbx_id: int) -> Dict[str, Any]:
	row = (
		db.query(TelephonyPbxConnection)
		.filter(TelephonyPbxConnection.id == pbx_id, TelephonyPbxConnection.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "مرکز تلفن یافت نشد.", http_status=404)
	api_key, key_hash = generate_api_key(prefix="hsx_tel_", length=36)
	row.connector_token_hash = key_hash
	row.connector_token_prefix = api_key[:12]
	row.status = "pending"
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	data = pbx_to_dict(row)
	data["connector_token"] = api_key
	return data


def update_pbx(db: Session, business_id: int, pbx_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	row = (
		db.query(TelephonyPbxConnection)
		.filter(TelephonyPbxConnection.id == pbx_id, TelephonyPbxConnection.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "مرکز تلفن یافت نشد.", http_status=404)
	for key in ("name", "pbx_type", "host_hint", "settings", "is_active"):
		if key in payload:
			setattr(row, key, payload[key])
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return pbx_to_dict(row)


def authenticate_connector(
	db: Session, *, token: str, business_id: int, pbx_id: int
) -> TelephonyPbxConnection:
	if not token or not check_telephony_plugin_active(db, business_id):
		raise ApiError("UNAUTHORIZED", "Connector authentication failed.", http_status=401)
	token_hash = hash_api_key(token)
	row = (
		db.query(TelephonyPbxConnection)
		.filter(
			TelephonyPbxConnection.id == pbx_id,
			TelephonyPbxConnection.business_id == business_id,
			TelephonyPbxConnection.connector_token_hash == token_hash,
			TelephonyPbxConnection.is_active == True,  # noqa: E712
		)
		.first()
	)
	if not row:
		raise ApiError("UNAUTHORIZED", "Invalid connector token.", http_status=401)
	return row


def connector_heartbeat(
	db: Session,
	pbx: TelephonyPbxConnection,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	pbx.last_seen_at = _now()
	pbx.connector_version = payload.get("connector_version") or pbx.connector_version
	pbx.status = "online" if payload.get("status", "ok") == "ok" else "error"
	if payload.get("status") != "ok":
		pbx.last_error = str(payload.get("error") or "connector error")
	else:
		pbx.last_error = None
	pbx.updated_at = _now()
	db.commit()
	return {"ok": True, "pbx_id": pbx.id, "status": pbx.status}


# ─── Extensions & user mapping ──────────────────────────────────────────────


def extension_to_dict(row: TelephonyExtension) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"pbx_id": row.pbx_id,
		"extension": row.extension,
		"display_name": row.display_name,
		"queue_codes": row.queue_codes,
		"is_active": bool(row.is_active),
		"presence_status": row.presence_status,
		"presence_updated_at": _iso(row.presence_updated_at),
	}


def list_extensions(db: Session, business_id: int, pbx_id: Optional[int] = None) -> List[Dict[str, Any]]:
	q = db.query(TelephonyExtension).filter(TelephonyExtension.business_id == business_id)
	if pbx_id:
		q = q.filter(TelephonyExtension.pbx_id == pbx_id)
	rows = q.order_by(TelephonyExtension.extension.asc()).all()
	return [extension_to_dict(r) for r in rows]


def upsert_extension(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	pbx_id = int(payload.get("pbx_id") or 0)
	ext = str(payload.get("extension") or "").strip()
	if not pbx_id or not ext:
		raise ApiError("VALIDATION_ERROR", "pbx_id و extension الزامی است.", http_status=400)
	pbx = (
		db.query(TelephonyPbxConnection)
		.filter(TelephonyPbxConnection.id == pbx_id, TelephonyPbxConnection.business_id == business_id)
		.first()
	)
	if not pbx:
		raise ApiError("NOT_FOUND", "مرکز تلفن یافت نشد.", http_status=404)
	row = (
		db.query(TelephonyExtension)
		.filter(TelephonyExtension.pbx_id == pbx_id, TelephonyExtension.extension == ext)
		.first()
	)
	if not row:
		row = TelephonyExtension(
			business_id=business_id,
			pbx_id=pbx_id,
			extension=ext,
			created_at=_now(),
			updated_at=_now(),
		)
		db.add(row)
	row.display_name = payload.get("display_name", row.display_name)
	if "queue_codes" in payload:
		row.queue_codes = payload.get("queue_codes")
	if "is_active" in payload:
		row.is_active = bool(payload.get("is_active"))
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return extension_to_dict(row)


def user_extension_to_dict(row: TelephonyUserExtension) -> Dict[str, Any]:
	ext = row.extension_row
	return {
		"id": row.id,
		"business_id": row.business_id,
		"user_id": row.user_id,
		"pbx_id": row.pbx_id,
		"extension_id": row.extension_id,
		"extension": ext.extension if ext else None,
		"extension_display_name": ext.display_name if ext else None,
		"is_primary": bool(row.is_primary),
		"receive_screen_pop": bool(row.receive_screen_pop),
		"can_click_to_call": bool(row.can_click_to_call),
		"caller_id_override": row.caller_id_override,
		"endpoint_mode": getattr(row, "endpoint_mode", None) or "desk",
		"allow_mode_fallback": bool(getattr(row, "allow_mode_fallback", True)),
		"direct_sip_user": getattr(row, "direct_sip_user", None),
	}


def list_user_extensions(
	db: Session, business_id: int, user_id: Optional[int] = None
) -> List[Dict[str, Any]]:
	q = (
		db.query(TelephonyUserExtension)
		.options(joinedload(TelephonyUserExtension.extension_row))
		.filter(TelephonyUserExtension.business_id == business_id)
	)
	if user_id:
		q = q.filter(TelephonyUserExtension.user_id == user_id)
	rows = q.order_by(TelephonyUserExtension.id.asc()).all()
	return [user_extension_to_dict(r) for r in rows]


def upsert_user_extension(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	user_id = int(payload.get("user_id") or 0)
	extension_id = int(payload.get("extension_id") or 0)
	if not user_id or not extension_id:
		raise ApiError("VALIDATION_ERROR", "user_id و extension_id الزامی است.", http_status=400)
	ext = (
		db.query(TelephonyExtension)
		.filter(TelephonyExtension.id == extension_id, TelephonyExtension.business_id == business_id)
		.first()
	)
	if not ext:
		raise ApiError("NOT_FOUND", "داخلی یافت نشد.", http_status=404)
	user = db.get(User, user_id)
	if not user:
		raise ApiError("NOT_FOUND", "کاربر یافت نشد.", http_status=404)

	row = (
		db.query(TelephonyUserExtension)
		.filter(
			TelephonyUserExtension.business_id == business_id,
			TelephonyUserExtension.user_id == user_id,
			TelephonyUserExtension.extension_id == extension_id,
		)
		.first()
	)
	if not row:
		row = TelephonyUserExtension(
			business_id=business_id,
			user_id=user_id,
			pbx_id=ext.pbx_id,
			extension_id=extension_id,
			created_at=_now(),
			updated_at=_now(),
		)
		db.add(row)
	is_primary = bool(payload.get("is_primary", True))
	if is_primary:
		db.query(TelephonyUserExtension).filter(
			TelephonyUserExtension.business_id == business_id,
			TelephonyUserExtension.user_id == user_id,
			TelephonyUserExtension.id != (row.id or 0),
		).update({"is_primary": False}, synchronize_session=False)
	row.is_primary = is_primary
	if "receive_screen_pop" in payload:
		row.receive_screen_pop = bool(payload["receive_screen_pop"])
	if "can_click_to_call" in payload:
		row.can_click_to_call = bool(payload["can_click_to_call"])
	if "caller_id_override" in payload:
		row.caller_id_override = payload.get("caller_id_override")
	if "endpoint_mode" in payload:
		mode = str(payload.get("endpoint_mode") or "desk").strip().lower()
		if mode not in ("relay", "direct", "desk"):
			raise ApiError("VALIDATION_ERROR", "endpoint_mode باید relay، direct یا desk باشد.", http_status=400)
		row.endpoint_mode = mode
	if "allow_mode_fallback" in payload:
		row.allow_mode_fallback = bool(payload.get("allow_mode_fallback"))
	if "direct_sip_user" in payload:
		row.direct_sip_user = payload.get("direct_sip_user")
	row.pbx_id = ext.pbx_id
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	row = (
		db.query(TelephonyUserExtension)
		.options(joinedload(TelephonyUserExtension.extension_row))
		.filter(TelephonyUserExtension.id == row.id)
		.first()
	)
	return user_extension_to_dict(row)


def delete_user_extension(db: Session, business_id: int, link_id: int) -> None:
	row = (
		db.query(TelephonyUserExtension)
		.filter(TelephonyUserExtension.id == link_id, TelephonyUserExtension.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "نگاشت داخلی یافت نشد.", http_status=404)
	db.delete(row)
	db.commit()


def get_my_extension_context(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
	links = list_user_extensions(db, business_id, user_id=user_id)
	primary = next((x for x in links if x.get("is_primary")), links[0] if links else None)
	pbx_list = list_pbx(db, business_id)
	settings = settings_to_dict(get_or_create_settings(db, business_id))
	missed_today = (
		db.query(func.count(TelephonyCall.id))
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.assigned_user_id == user_id,
			TelephonyCall.status == "missed",
			TelephonyCall.started_at >= datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0),
		)
		.scalar()
		or 0
	)
	from app.services.telephony import softphone_service as softphone_svc
	from app.services.telephony.media_hub import media_hub

	softphone_ctx: Dict[str, Any] = {
		"endpoint_mode": (primary or {}).get("endpoint_mode") or "desk",
		"supported_profiles": ["pcm_ws_v1"],
	}
	try:
		softphone_ctx = softphone_svc.softphone_health(db, business_id, user_id)
	except Exception:
		softphone_ctx["media_hub"] = media_hub.health()
		softphone_ctx["tunnel"] = None

	return {
		"plugin_active": True,
		"settings": settings,
		"extensions": links,
		"primary": primary,
		"pbx_connections": pbx_list,
		"missed_today": int(missed_today),
		"has_extension": bool(links),
		"softphone": softphone_ctx,
	}


# ─── Caller ID match ────────────────────────────────────────────────────────


def match_caller(
	db: Session,
	business_id: int,
	raw_number: Optional[str],
	phone_fields: Optional[List[str]] = None,
) -> Dict[str, Any]:
	norm = normalize_iran_phone(raw_number)
	candidates = norm["candidates"]
	if not candidates:
		return {"person": None, "lead": None, "persons": [], "leads": [], "is_anonymous": True, "normalized": None}

	# aliases
	alias = (
		db.query(TelephonyNumberAlias)
		.filter(
			TelephonyNumberAlias.business_id == business_id,
			TelephonyNumberAlias.number_normalized.in_(candidates),
		)
		.first()
	)
	if alias:
		person = db.get(Person, alias.person_id) if alias.person_id else None
		lead = db.get(Lead, alias.lead_id) if alias.lead_id else None
		return {
			"person": _person_brief(person) if person and person.business_id == business_id else None,
			"lead": _lead_brief(lead) if lead and lead.business_id == business_id else None,
			"persons": [],
			"leads": [],
			"is_anonymous": person is None and lead is None,
			"normalized": norm["canonical"],
			"match_method": "alias",
		}

	fields = phone_fields or DEFAULT_PHONE_FIELDS
	ors = []
	for field in fields:
		col = getattr(Person, field, None)
		if col is not None:
			ors.append(col.in_(candidates))
	persons: List[Person] = []
	if ors:
		persons = (
			db.query(Person)
			.filter(Person.business_id == business_id, or_(*ors))
			.limit(10)
			.all()
		)
	# de-dupe keeping order
	seen = set()
	uniq_persons = []
	for p in persons:
		if p.id not in seen:
			seen.add(p.id)
			uniq_persons.append(p)

	# soft suffix match فقط اگر exact چیزی پیدا نشد (حداقل ۱۰ رقم)
	if not uniq_persons:
		suffixes = [extract_digits(c)[-10:] for c in candidates if len(extract_digits(c)) >= 10]
		suffixes = list({s for s in suffixes if len(s) == 10})
		soft_ors = []
		for field in fields:
			col = getattr(Person, field, None)
			if col is None:
				continue
			for s in suffixes:
				soft_ors.append(col.like(f"%{s}"))
		if soft_ors:
			soft_persons = (
				db.query(Person)
				.filter(Person.business_id == business_id, or_(*soft_ors))
				.limit(10)
				.all()
			)
			for p in soft_persons:
				# تأیید نهایی با numbers_match
				vals = [getattr(p, f, None) for f in fields]
				if any(numbers_match(raw_number, v) for v in vals if v):
					if p.id not in seen:
						seen.add(p.id)
						uniq_persons.append(p)

	leads = (
		db.query(Lead)
		.filter(Lead.business_id == business_id, Lead.mobile.in_(candidates))
		.limit(10)
		.all()
	)
	if not leads:
		suffixes = [extract_digits(c)[-10:] for c in candidates if len(extract_digits(c)) >= 10]
		soft = []
		for s in {x for x in suffixes if len(x) == 10}:
			soft.append(Lead.mobile.like(f"%{s}"))
		if soft:
			cand = db.query(Lead).filter(Lead.business_id == business_id, or_(*soft)).limit(10).all()
			leads = [l for l in cand if numbers_match(raw_number, l.mobile)]

	is_anon = not uniq_persons and not leads
	return {
		"person": _person_brief(uniq_persons[0]) if len(uniq_persons) == 1 else None,
		"lead": _lead_brief(leads[0]) if len(leads) == 1 and not uniq_persons else None,
		"persons": [_person_brief(p) for p in uniq_persons],
		"leads": [_lead_brief(l) for l in leads],
		"is_anonymous": is_anon,
		"normalized": norm["canonical"],
		"match_method": "auto" if not is_anon else None,
		"ambiguous": len(uniq_persons) > 1 or (len(uniq_persons) == 0 and len(leads) > 1),
	}


def _person_brief(p: Optional[Person]) -> Optional[Dict[str, Any]]:
	if not p:
		return None
	name = (p.alias_name or "").strip()
	if not name:
		name = f"{p.first_name or ''} {p.last_name or ''}".strip() or p.company_name or f"#{p.id}"
	return {
		"id": p.id,
		"name": name,
		"company_name": p.company_name,
		"mobile": p.mobile,
		"phone": p.phone,
		"mobile_2": p.mobile_2,
		"mobile_3": p.mobile_3,
	}


def _lead_brief(l: Optional[Lead]) -> Optional[Dict[str, Any]]:
	if not l:
		return None
	return {
		"id": l.id,
		"name": l.name,
		"company_name": l.company_name,
		"mobile": l.mobile,
		"code": l.code,
	}


# ─── Calls ───────────────────────────────────────────────────────────────────


def call_to_dict(row: TelephonyCall) -> Dict[str, Any]:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"pbx_id": row.pbx_id,
		"asterisk_uniqueid": row.asterisk_uniqueid,
		"asterisk_linkedid": row.asterisk_linkedid,
		"direction": row.direction,
		"status": row.status,
		"from_number_raw": row.from_number_raw,
		"from_number_normalized": row.from_number_normalized,
		"to_number_raw": row.to_number_raw,
		"to_number_normalized": row.to_number_normalized,
		"extension": row.extension,
		"queue_code": row.queue_code,
		"transferred_from": row.transferred_from,
		"transferred_to": row.transferred_to,
		"started_at": _iso(row.started_at),
		"answered_at": _iso(row.answered_at),
		"ended_at": _iso(row.ended_at),
		"duration_sec": row.duration_sec,
		"talk_sec": row.talk_sec,
		"hangup_cause": row.hangup_cause,
		"recording_status": row.recording_status,
		"recording_url": row.recording_url,
		"person_id": row.person_id,
		"lead_id": row.lead_id,
		"deal_id": row.deal_id,
		"document_id": row.document_id,
		"crm_activity_id": row.crm_activity_id,
		"assigned_user_id": row.assigned_user_id,
		"category": row.category,
		"outcome": row.outcome,
		"note": row.note,
		"match_method": row.match_method,
		"is_anonymous": bool(row.is_anonymous),
		"extra_info": row.extra_info or {},
		"created_at": _iso(row.created_at),
		"updated_at": _iso(row.updated_at),
	}


def list_calls(
	db: Session,
	business_id: int,
	*,
	direction: Optional[str] = None,
	status: Optional[str] = None,
	assigned_user_id: Optional[int] = None,
	person_id: Optional[int] = None,
	q: Optional[str] = None,
	limit: int = 50,
	offset: int = 0,
) -> Dict[str, Any]:
	query = db.query(TelephonyCall).filter(TelephonyCall.business_id == business_id)
	if direction:
		query = query.filter(TelephonyCall.direction == direction)
	if status:
		query = query.filter(TelephonyCall.status == status)
	if assigned_user_id:
		query = query.filter(TelephonyCall.assigned_user_id == assigned_user_id)
	if person_id:
		query = query.filter(TelephonyCall.person_id == person_id)
	if q:
		like = f"%{q.strip()}%"
		query = query.filter(
			or_(
				TelephonyCall.from_number_raw.ilike(like),
				TelephonyCall.from_number_normalized.ilike(like),
				TelephonyCall.to_number_raw.ilike(like),
				TelephonyCall.to_number_normalized.ilike(like),
				TelephonyCall.extension.ilike(like),
				TelephonyCall.note.ilike(like),
			)
		)
	total = query.count()
	rows = query.order_by(TelephonyCall.started_at.desc()).offset(offset).limit(min(limit, 200)).all()
	return {"items": [call_to_dict(r) for r in rows], "total": total, "limit": limit, "offset": offset}


def get_call(db: Session, business_id: int, call_id: int) -> Dict[str, Any]:
	row = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)
	data = call_to_dict(row)
	events = (
		db.query(TelephonyCallEvent)
		.filter(TelephonyCallEvent.call_id == call_id)
		.order_by(TelephonyCallEvent.occurred_at.asc())
		.all()
	)
	data["events"] = [
		{
			"id": e.id,
			"event_id": e.event_id,
			"event_type": e.event_type,
			"payload": e.payload,
			"occurred_at": _iso(e.occurred_at),
		}
		for e in events
	]
	return data


def patch_call(db: Session, business_id: int, call_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	row = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)
	for key in (
		"note",
		"category",
		"outcome",
		"person_id",
		"lead_id",
		"deal_id",
		"document_id",
		"match_method",
	):
		if key in payload:
			setattr(row, key, payload[key])
	if payload.get("person_id"):
		row.is_anonymous = False
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return call_to_dict(row)


def _users_for_extension(db: Session, business_id: int, extension: Optional[str]) -> List[TelephonyUserExtension]:
	if not extension:
		return []
	return (
		db.query(TelephonyUserExtension)
		.options(joinedload(TelephonyUserExtension.extension_row))
		.join(TelephonyExtension, TelephonyExtension.id == TelephonyUserExtension.extension_id)
		.filter(
			TelephonyUserExtension.business_id == business_id,
			TelephonyExtension.extension == extension,
			TelephonyUserExtension.receive_screen_pop == True,  # noqa: E712
		)
		.all()
	)


async def _notify_users(user_ids: List[int], message: Dict[str, Any]) -> None:
	for uid in set(user_ids):
		try:
			await realtime_manager.send_to_user(uid, message)
		except Exception:
			pass


def _notify_users_sync(user_ids: List[int], message: Dict[str, Any]) -> None:
	import anyio

	try:
		anyio.from_thread.run(_notify_users, user_ids, message)
	except Exception:
		try:
			import asyncio

			asyncio.get_event_loop().create_task(_notify_users(user_ids, message))
		except Exception:
			pass


def process_connector_event(
	db: Session,
	pbx: TelephonyPbxConnection,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	event_id = str(payload.get("event_id") or secrets.token_hex(16))
	existing = (
		db.query(TelephonyCallEvent)
		.filter(TelephonyCallEvent.pbx_id == pbx.id, TelephonyCallEvent.event_id == event_id)
		.first()
	)
	if existing:
		return {"ok": True, "duplicate": True, "call_id": existing.call_id}

	event_type = str(payload.get("type") or payload.get("event_type") or "").strip()
	uniqueid = str(payload.get("uniqueid") or "").strip()
	if not event_type or not uniqueid:
		raise ApiError("VALIDATION_ERROR", "type و uniqueid الزامی است.", http_status=400)

	occurred_at = _now()
	raw_at = payload.get("pbx_event_at")
	if raw_at:
		try:
			occurred_at = datetime.fromisoformat(str(raw_at).replace("Z", "+00:00")).replace(tzinfo=None)
		except Exception:
			pass

	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.pbx_id == pbx.id, TelephonyCall.asterisk_uniqueid == uniqueid)
		.first()
	)

	settings = get_or_create_settings(db, pbx.business_id)
	direction = str(payload.get("direction") or (call.direction if call else "inbound")).lower()
	extension = str(payload.get("extension") or (call.extension if call else "") or "").strip() or None
	from_raw = payload.get("from") or payload.get("from_number") or (call.from_number_raw if call else None)
	to_raw = payload.get("to") or payload.get("to_number") or (call.to_number_raw if call else None)
	from_norm = normalize_iran_phone(from_raw)["canonical"]
	to_norm = normalize_iran_phone(to_raw)["canonical"]

	created = False
	if not call:
		match = match_caller(
			db,
			pbx.business_id,
			from_raw if direction == "inbound" else to_raw,
			phone_fields=settings.primary_phone_fields or DEFAULT_PHONE_FIELDS,
		)
		assigned_user_id = None
		links = _users_for_extension(db, pbx.business_id, extension)
		if links:
			assigned_user_id = links[0].user_id
		call = TelephonyCall(
			business_id=pbx.business_id,
			pbx_id=pbx.id,
			asterisk_uniqueid=uniqueid,
			asterisk_linkedid=payload.get("linkedid"),
			direction=direction if direction in ("inbound", "outbound", "internal") else "inbound",
			status="ringing",
			from_number_raw=str(from_raw) if from_raw else None,
			from_number_normalized=from_norm,
			to_number_raw=str(to_raw) if to_raw else None,
			to_number_normalized=to_norm,
			extension=extension,
			queue_code=payload.get("queue"),
			started_at=occurred_at,
			person_id=(match.get("person") or {}).get("id") if match.get("person") else None,
			lead_id=(match.get("lead") or {}).get("id") if match.get("lead") else None,
			assigned_user_id=assigned_user_id,
			match_method=match.get("match_method"),
			is_anonymous=bool(match.get("is_anonymous")),
			extra_info={"match": match},
			created_at=_now(),
			updated_at=_now(),
		)
		db.add(call)
		db.flush()
		created = True
	else:
		if from_raw:
			call.from_number_raw = str(from_raw)
			call.from_number_normalized = from_norm
		if to_raw:
			call.to_number_raw = str(to_raw)
			call.to_number_normalized = to_norm
		if extension:
			call.extension = extension
		if payload.get("queue"):
			call.queue_code = payload.get("queue")
		if payload.get("linkedid"):
			call.asterisk_linkedid = payload.get("linkedid")

	# state transitions
	notify_type = None
	if event_type in ("call.ringing", "ringing"):
		call.status = "ringing"
		notify_type = "telephony.incoming_call" if call.direction == "inbound" else "telephony.outbound_ringing"
	elif event_type in ("call.answered", "answered"):
		call.status = "answered"
		call.answered_at = call.answered_at or occurred_at
		notify_type = "telephony.call_answered"
	elif event_type in ("call.missed", "missed"):
		call.status = "missed"
		call.ended_at = occurred_at
		notify_type = "telephony.call_missed"
	elif event_type in ("call.busy", "busy"):
		call.status = "busy"
		call.ended_at = occurred_at
		notify_type = "telephony.call_ended"
	elif event_type in ("call.failed", "failed"):
		call.status = "failed"
		call.ended_at = occurred_at
		notify_type = "telephony.call_ended"
	elif event_type in ("call.ended", "ended", "hangup"):
		if call.status == "answered":
			call.status = "completed"
		elif call.status == "ringing":
			call.status = "missed"
			notify_type = "telephony.call_missed"
		call.ended_at = occurred_at
		if call.started_at:
			call.duration_sec = max(0, int((occurred_at - call.started_at).total_seconds()))
		if call.answered_at:
			call.talk_sec = max(0, int((occurred_at - call.answered_at).total_seconds()))
		call.hangup_cause = payload.get("hangup_cause") or call.hangup_cause
		notify_type = notify_type or "telephony.call_ended"
	elif event_type in ("recording.ready",):
		call.recording_status = "available"
		call.recording_remote_path = payload.get("recording_path") or call.recording_remote_path
		call.recording_url = payload.get("recording_url") or call.recording_url

	call.updated_at = _now()

	ev = TelephonyCallEvent(
		business_id=pbx.business_id,
		pbx_id=pbx.id,
		call_id=call.id,
		event_id=event_id,
		event_type=event_type,
		payload=payload,
		occurred_at=occurred_at,
		created_at=_now(),
	)
	db.add(ev)

	# auto CRM activity on terminal states
	if settings.auto_create_activity and call.status in ("completed", "missed", "busy", "failed") and not call.crm_activity_id:
		try:
			_ensure_crm_activity(db, call, user_id=call.assigned_user_id)
		except Exception:
			pass

	# missed call follow-up task
	if call.status == "missed" and settings.missed_call_create_task:
		try:
			_ensure_missed_call_task(db, call, settings)
		except Exception:
			pass

	# presence updates
	try:
		from app.services.telephony.live_service import update_presence_from_event

		if call.status == "ringing":
			update_presence_from_event(db, pbx.business_id, call.extension, "ringing")
		elif call.status == "answered":
			update_presence_from_event(db, pbx.business_id, call.extension, "busy")
		elif call.status in ("completed", "missed", "busy", "failed", "cancelled"):
			update_presence_from_event(db, pbx.business_id, call.extension, "idle")
	except Exception:
		pass

	try:
		from app.services.telephony.recording_service import bump_metric, apply_recording_meta

		bump_metric(db, pbx.business_id, f"events_{event_type.replace('.', '_')}")
		bump_metric(db, pbx.business_id, "events_total")
		if event_type in ("recording.ready",):
			apply_recording_meta(db, call, payload)
	except Exception:
		pass

	# store channel for later control
	if payload.get("channel"):
		extra = dict(call.extra_info or {})
		extra["channel"] = payload.get("channel")
		call.extra_info = extra

	db.commit()
	db.refresh(call)

	# realtime
	links = _users_for_extension(db, pbx.business_id, call.extension)
	user_ids = [lnk.user_id for lnk in links if lnk.receive_screen_pop]
	if call.assigned_user_id and call.assigned_user_id not in user_ids:
		user_ids.append(call.assigned_user_id)
	if notify_type and user_ids and (settings.screen_pop_enabled or notify_type != "telephony.incoming_call"):
		person_brief = None
		if call.person_id:
			person_brief = _person_brief(db.get(Person, call.person_id))
		msg = {
			"type": notify_type,
			"business_id": pbx.business_id,
			"call_id": call.id,
			"extension": call.extension,
			"direction": call.direction,
			"status": call.status,
			"from_number": call.from_number_normalized or call.from_number_raw,
			"to_number": call.to_number_normalized or call.to_number_raw,
			"person": person_brief,
			"is_anonymous": call.is_anonymous,
			"deep_link": f"/business/{pbx.business_id}/telephony/calls/{call.id}",
		}
		_notify_users_sync(user_ids, msg)

	return {"ok": True, "created": created, "call": call_to_dict(call)}


def _ensure_crm_activity(db: Session, call: TelephonyCall, user_id: Optional[int]) -> None:
	uid = user_id or call.assigned_user_id
	if not uid:
		# fallback: business owner not resolved here — skip
		return
	code = f"TEL-{call.id}"
	existing = (
		db.query(CrmActivity)
		.filter(CrmActivity.business_id == call.business_id, CrmActivity.code == code)
		.first()
	)
	if existing:
		call.crm_activity_id = existing.id
		return
	direction_fa = {"inbound": "ورودی", "outbound": "خروجی", "internal": "داخلی"}.get(call.direction, call.direction)
	subject = f"تماس {direction_fa} {call.from_number_normalized or call.from_number_raw or ''}".strip()
	act = CrmActivity(
		business_id=call.business_id,
		person_id=call.person_id,
		lead_id=call.lead_id,
		deal_id=call.deal_id,
		code=code,
		activity_type="call",
		subject=subject[:255],
		description=call.note,
		activity_date=call.started_at or _now(),
		created_by_user_id=uid,
		assigned_to_user_id=uid,
		status="done" if call.status in ("completed", "missed", "busy", "failed") else "open",
		completed_at=call.ended_at,
		outcome=call.outcome or call.status,
		extra_info={"telephony_call_id": call.id, "direction": call.direction, "duration_sec": call.duration_sec},
		telephony_call_id=call.id,
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(act)
	db.flush()
	call.crm_activity_id = act.id


def _ensure_missed_call_task(db: Session, call: TelephonyCall, settings: TelephonySettings) -> None:
	uid = call.assigned_user_id
	if not uid:
		return
	code = f"TEL-MISS-{call.id}"
	existing = (
		db.query(CrmActivity)
		.filter(CrmActivity.business_id == call.business_id, CrmActivity.code == code)
		.first()
	)
	if existing:
		return
	due_min = int(settings.missed_call_task_due_minutes or 60)
	due_at = (call.ended_at or _now()) + timedelta(minutes=due_min)
	number = call.from_number_normalized or call.from_number_raw or ""
	act = CrmActivity(
		business_id=call.business_id,
		person_id=call.person_id,
		lead_id=call.lead_id,
		code=code,
		activity_type="call",
		subject=f"پیگیری تماس از دست‌رفته {number}"[:255],
		description="ایجاد خودکار پس از تماس از دست‌رفته",
		activity_date=_now(),
		created_by_user_id=uid,
		assigned_to_user_id=uid,
		is_task=True,
		due_at=due_at,
		status="open",
		priority="high",
		extra_info={"telephony_call_id": call.id, "auto_missed_followup": True},
		telephony_call_id=call.id,
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(act)


# ─── Screen pop context ─────────────────────────────────────────────────────


def screen_pop_context(db: Session, business_id: int, call_id: int) -> Dict[str, Any]:
	from app.services.person_service import calculate_person_balance
	from adapters.db.models.check import Check, CheckStatus

	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not call:
		raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)

	match = (call.extra_info or {}).get("match") or match_caller(
		db, business_id, call.from_number_raw if call.direction == "inbound" else call.to_number_raw
	)
	person_id = call.person_id or (match.get("person") or {}).get("id")
	balance = None
	recent_docs: List[Dict[str, Any]] = []
	overdue_checks: List[Dict[str, Any]] = []
	open_deals: List[Dict[str, Any]] = []
	person = None
	if person_id:
		person = db.get(Person, person_id)
		if person and person.business_id == business_id:
			try:
				amount, status = calculate_person_balance(db, person_id)
				balance = {"amount": amount, "status": status}
			except Exception:
				balance = None
			from adapters.db.models.document import Document
			from adapters.db.models.document_line import DocumentLine

			docs = (
				db.query(Document)
				.join(DocumentLine, DocumentLine.document_id == Document.id)
				.filter(Document.business_id == business_id, DocumentLine.person_id == person_id)
				.order_by(Document.document_date.desc())
				.limit(5)
				.all()
			)
			recent_docs = [
				{
					"id": d.id,
					"code": d.code,
					"document_type": d.document_type,
					"document_date": _iso(d.document_date) if hasattr(d.document_date, "isoformat") else str(d.document_date),
					"description": d.description,
				}
				for d in docs
			]
			now = _now()
			checks = (
				db.query(Check)
				.filter(
					Check.business_id == business_id,
					Check.person_id == person_id,
					Check.due_date <= now,
					Check.status.in_(
						[
							CheckStatus.RECEIVED_ON_HAND,
							CheckStatus.DEPOSITED,
							CheckStatus.BOUNCED,
							CheckStatus.RETURNED,
						]
					),
				)
				.order_by(Check.due_date.asc())
				.limit(5)
				.all()
			)
			overdue_checks = [
				{
					"id": ch.id,
					"check_number": ch.check_number,
					"amount": float(ch.amount or 0),
					"due_date": _iso(ch.due_date),
					"status": ch.status.value if ch.status else None,
				}
				for ch in checks
			]
			from adapters.db.models.crm import Deal

			deals = (
				db.query(Deal)
				.filter(Deal.business_id == business_id, Deal.person_id == person_id, Deal.closed_at.is_(None))
				.order_by(Deal.created_at.desc())
				.limit(5)
				.all()
			)
			open_deals = [
				{"id": d.id, "title": d.title, "code": d.code, "amount": float(d.amount or 0)}
				for d in deals
			]

	return {
		"call": call_to_dict(call),
		"person": _person_brief(person) if person else match.get("person"),
		"lead": match.get("lead"),
		"match": match,
		"balance": balance,
		"recent_documents": recent_docs,
		"overdue_checks": overdue_checks,
		"open_deals": open_deals,
		"settings": {
			"post_call_form_required": get_or_create_settings(db, business_id).post_call_form_required,
		},
	}


# ─── Click to call ───────────────────────────────────────────────────────────


def click_to_call(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	destination = str(payload.get("destination") or payload.get("number") or "").strip()
	if not destination:
		raise ApiError("VALIDATION_ERROR", "شماره مقصد الزامی است.", http_status=400)
	norm = normalize_iran_phone(destination)
	dest_canonical = norm["canonical"] or extract_digits(destination)
	if not dest_canonical:
		raise ApiError("VALIDATION_ERROR", "شماره مقصد نامعتبر است.", http_status=400)

	links = (
		db.query(TelephonyUserExtension)
		.options(joinedload(TelephonyUserExtension.extension_row))
		.filter(
			TelephonyUserExtension.business_id == business_id,
			TelephonyUserExtension.user_id == user_id,
			TelephonyUserExtension.can_click_to_call == True,  # noqa: E712
		)
		.all()
	)
	if not links:
		raise ApiError("NO_EXTENSION", "برای شما داخلی Click-to-Call تعریف نشده است.", http_status=400)

	link = None
	wanted_ext_id = payload.get("extension_id")
	if wanted_ext_id:
		link = next((x for x in links if x.extension_id == int(wanted_ext_id)), None)
	if not link:
		link = next((x for x in links if x.is_primary), links[0])

	ext = link.extension_row
	pbx = db.get(TelephonyPbxConnection, link.pbx_id)
	if not pbx or not pbx.is_active:
		raise ApiError("PBX_OFFLINE", "مرکز تلفن فعال نیست.", http_status=400)

	settings_pbx = pbx.settings or {}
	command_id = str(uuid.uuid4())
	cmd_payload = {
		"extension": ext.extension,
		"destination": dest_canonical,
		"caller_id": link.caller_id_override or settings_pbx.get("default_caller_id"),
		"timeout_ms": int(settings_pbx.get("originate_timeout_ms") or 30000),
		"context": settings_pbx.get("originate_context") or "from-internal",
	}
	uniqueid = f"out-{command_id}"
	match = match_caller(db, business_id, dest_canonical)
	call = TelephonyCall(
		business_id=business_id,
		pbx_id=pbx.id,
		asterisk_uniqueid=uniqueid,
		direction="outbound",
		status="ringing",
		from_number_raw=ext.extension,
		from_number_normalized=ext.extension,
		to_number_raw=destination,
		to_number_normalized=dest_canonical,
		extension=ext.extension,
		started_at=_now(),
		person_id=payload.get("person_id") or (match.get("person") or {}).get("id"),
		lead_id=payload.get("lead_id") or (match.get("lead") or {}).get("id"),
		assigned_user_id=user_id,
		match_method=match.get("match_method") or ("manual" if payload.get("person_id") else None),
		is_anonymous=bool(match.get("is_anonymous")) and not payload.get("person_id"),
		extra_info={"originate_command_id": command_id, "match": match},
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(call)
	db.flush()

	cmd = TelephonyCommand(
		business_id=business_id,
		pbx_id=pbx.id,
		command_id=command_id,
		command_type="originate",
		payload=cmd_payload,
		status="pending",
		created_by_user_id=user_id,
		call_id=call.id,
		created_at=_now(),
		expires_at=_now() + timedelta(minutes=2),
	)
	db.add(cmd)
	db.commit()
	db.refresh(call)
	return {
		"ok": True,
		"command_id": command_id,
		"call": call_to_dict(call),
		"message": "دستور شماره‌گیری برای Connector ارسال شد.",
	}


def poll_commands(db: Session, pbx: TelephonyPbxConnection, limit: int = 10) -> List[Dict[str, Any]]:
	now = _now()
	rows = (
		db.query(TelephonyCommand)
		.filter(
			TelephonyCommand.pbx_id == pbx.id,
			TelephonyCommand.status == "pending",
			or_(TelephonyCommand.expires_at.is_(None), TelephonyCommand.expires_at > now),
		)
		.order_by(TelephonyCommand.created_at.asc())
		.limit(min(limit, 50))
		.all()
	)
	out = []
	for row in rows:
		row.status = "sent"
		out.append(
			{
				"command_id": row.command_id,
				"type": row.command_type,
				**row.payload,
				"call_id": row.call_id,
			}
		)
	db.commit()
	return out


def ack_command(db: Session, pbx: TelephonyPbxConnection, command_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
	row = (
		db.query(TelephonyCommand)
		.filter(TelephonyCommand.pbx_id == pbx.id, TelephonyCommand.command_id == command_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "دستور یافت نشد.", http_status=404)
	ok = bool(payload.get("accepted", True))
	row.status = "acked" if ok else "failed"
	row.result_payload = payload
	row.acked_at = _now()
	db.commit()
	return {"ok": True, "command_id": command_id, "status": row.status}


# ─── Create person / lead from call ──────────────────────────────────────────


def create_person_from_call(
	db: Session, business_id: int, call_id: int, payload: Dict[str, Any], user_id: int
) -> Dict[str, Any]:
	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not call:
		raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)

	number = call.from_number_normalized if call.direction == "inbound" else call.to_number_normalized
	number = number or call.from_number_raw or call.to_number_raw
	digits = extract_digits(number or "")
	mobile_val = None
	phone_val = payload.get("phone")
	if len(digits) >= 10 and digits[-10:].startswith("9"):
		mobile_val = "0" + digits[-10:]
	elif number:
		phone_val = phone_val or number
	# کد بعدی شخص
	max_code = (
		db.query(func.max(Person.code)).filter(Person.business_id == business_id).scalar()
	)
	next_code = int(max_code or 0) + 1
	person = Person(
		business_id=business_id,
		code=next_code,
		alias_name=(payload.get("alias_name") or payload.get("name") or number or "مخاطب تلفنی").strip(),
		first_name=payload.get("first_name"),
		last_name=payload.get("last_name"),
		company_name=payload.get("company_name"),
		mobile=mobile_val or payload.get("mobile"),
		phone=phone_val,
		person_types=json.dumps(["مشتری"], ensure_ascii=False),
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(person)
	db.flush()
	call.person_id = person.id
	call.is_anonymous = False
	call.match_method = "created_person"
	call.updated_at = _now()
	db.commit()
	db.refresh(call)
	return {"call": call_to_dict(call), "person": _person_brief(person)}


def create_lead_from_call(
	db: Session, business_id: int, call_id: int, payload: Dict[str, Any], user_id: int
) -> Dict[str, Any]:
	from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage

	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not call:
		raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)

	process = (
		db.query(CrmProcessDefinition)
		.filter(
			CrmProcessDefinition.business_id == business_id,
			CrmProcessDefinition.process_type == "lead_funnel",
			CrmProcessDefinition.is_active == True,  # noqa: E712
		)
		.order_by(CrmProcessDefinition.is_default.desc(), CrmProcessDefinition.id.asc())
		.first()
	)
	if not process:
		raise ApiError("NO_LEAD_FUNNEL", "فانل سرنخ برای این کسب‌وکار تعریف نشده است.", http_status=400)
	stage = (
		db.query(CrmProcessStage)
		.filter(CrmProcessStage.process_definition_id == process.id)
		.order_by(CrmProcessStage.order_index.asc())
		.first()
	)
	if not stage:
		raise ApiError("NO_LEAD_STAGE", "مرحله سرنخ یافت نشد.", http_status=400)

	number = call.from_number_normalized if call.direction == "inbound" else call.to_number_normalized
	number = number or call.from_number_raw or call.to_number_raw
	code = f"TEL-L-{call.id}-{secrets.token_hex(2)}"
	lead = Lead(
		business_id=business_id,
		process_definition_id=process.id,
		stage_id=stage.id,
		code=code,
		name=(payload.get("name") or number or "سرنخ تلفنی").strip(),
		company_name=payload.get("company_name"),
		mobile=number,
		source_code=payload.get("source_code") or "telephony",
		description=payload.get("description") or call.note,
		assigned_to_user_id=payload.get("assigned_to_user_id") or user_id,
		created_by_user_id=user_id,
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(lead)
	db.flush()
	call.lead_id = lead.id
	call.is_anonymous = False
	call.match_method = "created_lead"
	call.updated_at = _now()
	db.commit()
	db.refresh(call)
	return {"call": call_to_dict(call), "lead": _lead_brief(lead)}


def dashboard_summary(db: Session, business_id: int, user_id: Optional[int] = None) -> Dict[str, Any]:
	today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
	base = db.query(TelephonyCall).filter(
		TelephonyCall.business_id == business_id, TelephonyCall.started_at >= today_start
	)
	inbound = base.filter(TelephonyCall.direction == "inbound").count()
	outbound = base.filter(TelephonyCall.direction == "outbound").count()
	answered = base.filter(TelephonyCall.status.in_(["answered", "completed"])).count()
	missed = base.filter(TelephonyCall.status == "missed").count()
	active = (
		db.query(TelephonyCall)
		.filter(
			TelephonyCall.business_id == business_id,
			TelephonyCall.status.in_(["ringing", "answered"]),
			TelephonyCall.ended_at.is_(None),
		)
		.count()
	)
	pbx_rows = list_pbx(db, business_id)
	my_missed = 0
	if user_id:
		my_missed = (
			base.filter(TelephonyCall.assigned_user_id == user_id, TelephonyCall.status == "missed").count()
		)
	return {
		"today": {
			"inbound": inbound,
			"outbound": outbound,
			"answered": answered,
			"missed": missed,
			"my_missed": my_missed,
		},
		"active_calls": active,
		"pbx_connections": pbx_rows,
	}
