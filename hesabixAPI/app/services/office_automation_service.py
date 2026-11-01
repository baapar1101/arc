"""سرویس اتوماسیون اداری سمت‌محور: ساختار، نامه، کارتابل، ارجاع، پاراف و پیوست."""
from __future__ import annotations

import logging
import re
from datetime import date, datetime
from typing import Any, Dict, List, Optional, Sequence, Tuple

from sqlalchemy import and_, desc, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage
from adapters.db.models.office_automation import (
	OaAuditLog,
	OaDelegation,
	OaLetter,
	OaLetterAttachment,
	OaLetterLink,
	OaLetterNumberCounter,
	OaOrgUnit,
	OaParaph,
	OaPosition,
	OaPositionHolder,
	OaReferral,
	OaSettings,
)
from adapters.db.models.user import User
from adapters.db.models.business import Business
from app.core.calendar import CalendarConverter, CalendarType
from app.core.date_input import DateParseError, parse_user_date
from app.core.office_automation_plugin_dependency import check_office_automation_plugin_active
from app.core.responses import ApiError

logger = logging.getLogger(__name__)

_CODE_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9_]{0,63}$")
_LETTER_KINDS = frozenset({"internal", "incoming", "outgoing"})
_LETTER_STATUSES = frozenset({"draft", "registered", "in_circulation", "closed", "archived"})
_URGENCY = frozenset({"normal", "urgent", "immediate"})
_CONFIDENTIALITY = frozenset({"normal", "confidential"})
_REFERRAL_KINDS = frozenset({"action", "info", "signature", "return"})
_REFERRAL_STATUSES = frozenset({"pending", "seen", "done", "returned", "cancelled"})
_DELEGATION_SCOPES = frozenset({"full", "view", "refer"})
_LINK_KINDS = frozenset({"related", "reply", "followup"})
_CARTABLE_FOLDERS = frozenset({"inbox", "action", "cc", "drafts", "sent", "followup", "archive", "registry"})
_PREFIX_BY_KIND = {"internal": "internal_prefix", "incoming": "incoming_prefix", "outgoing": "outgoing_prefix"}


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_office_automation_plugin_active(db, business_id):
		raise ApiError(
			"OA_PLUGIN_NOT_ACTIVE",
			"Office automation add-on is not active for this business.",
			http_status=403,
			details={"plugin_code": "office_automation"},
		)


def resolve_i18n(name_i18n: Any, lang: str = "fa") -> str:
	if not isinstance(name_i18n, dict):
		return str(name_i18n or "")
	base = (lang or "fa").split("-")[0]
	value = name_i18n.get(base) or name_i18n.get("fa") or name_i18n.get("en")
	if value:
		return str(value)
	for val in name_i18n.values():
		if val:
			return str(val)
	return ""


def _normalize_i18n(value: Any) -> dict:
	if isinstance(value, dict):
		out = {}
		for key in ("fa", "en"):
			raw = value.get(key)
			if raw is not None and str(raw).strip():
				out[key] = str(raw).strip()[:200]
		if not out:
			raise ApiError("VALIDATION_ERROR", "name_i18n requires fa or en.", http_status=400)
		return out
	text = str(value or "").strip()
	if not text:
		raise ApiError("VALIDATION_ERROR", "name_i18n is required.", http_status=400)
	return {"fa": text[:200], "en": text[:200]}


def _now() -> datetime:
	return datetime.utcnow()


def _parse_date(value: Any, calendar_type: CalendarType) -> Optional[date]:
	if value is None or value == "":
		return None
	if isinstance(value, date) and not isinstance(value, datetime):
		return value
	if isinstance(value, datetime):
		return value.date()
	try:
		return parse_user_date(str(value), calendar_type=calendar_type)
	except DateParseError as exc:
		raise ApiError("VALIDATION_ERROR", str(exc), http_status=400) from exc


def _parse_datetime(value: Any, calendar_type: CalendarType) -> Optional[datetime]:
	if value is None or value == "":
		return None
	if isinstance(value, datetime):
		return value
	if isinstance(value, date):
		return datetime.combine(value, datetime.min.time())
	dt_str = str(value).strip()
	try:
		return datetime.fromisoformat(dt_str.replace("Z", "+00:00")).replace(tzinfo=None)
	except Exception:
		try:
			d = parse_user_date(dt_str, calendar_type=calendar_type)
		except DateParseError as exc:
			raise ApiError("VALIDATION_ERROR", str(exc), http_status=400) from exc
		return datetime.combine(d, datetime.min.time())


def _user_display_name(user: Optional[User]) -> str:
	if user is None:
		return ""
	parts = [str(getattr(user, "first_name", None) or "").strip(), str(getattr(user, "last_name", None) or "").strip()]
	name = " ".join(part for part in parts if part)
	return name or (getattr(user, "email", None) or getattr(user, "mobile", None) or str(user.id))


def _require_letter_open(letter: OaLetter, *, allow_draft: bool = False) -> None:
	if letter.status == "draft" and not allow_draft:
		raise ApiError("OA_LETTER_STILL_DRAFT", "Register the letter before this action.", http_status=400)
	if letter.status == "archived":
		raise ApiError("OA_LETTER_ARCHIVED", "Archived letters cannot be changed.", http_status=400)


def _code(value: Any) -> str:
	code = str(value or "").strip()
	if not _CODE_RE.match(code):
		raise ApiError("VALIDATION_ERROR", "Code must be latin letters, numbers, and underscore.", http_status=400)
	return code.lower()


def _allocate_oa_code(db: Session, business_id: int, model: Any, prefix: str) -> str:
	rows = db.query(model.code).filter(model.business_id == business_id).all()
	used = {str(code or "").strip().lower() for (code,) in rows}
	seq = 1
	while seq <= 99999:
		candidate = f"{prefix}{seq:04d}"
		if candidate not in used:
			return candidate
		seq += 1
	raise ApiError("VALIDATION_ERROR", "Could not allocate a unique code.", http_status=400)


def _ensure_unique_code(
	db: Session,
	business_id: int,
	model: Any,
	code: str,
	*,
	exclude_id: Optional[int] = None,
) -> None:
	q = db.query(model.id).filter(model.business_id == business_id, model.code == code)
	if exclude_id:
		q = q.filter(model.id != exclude_id)
	if q.first():
		raise ApiError("OA_CODE_EXISTS", "This code is already used.", http_status=400)


def _resolve_create_code(db: Session, business_id: int, payload: dict, model: Any, prefix: str) -> str:
	raw = str(payload.get("code") or "").strip()
	explicit_auto = payload.get("auto_generate_code")
	if explicit_auto is False:
		if not raw:
			raise ApiError("VALIDATION_ERROR", "Code is required.", http_status=400)
		code = _code(raw)
		_ensure_unique_code(db, business_id, model, code)
		return code
	if explicit_auto is True or not raw:
		return _allocate_oa_code(db, business_id, model, prefix)
	code = _code(raw)
	_ensure_unique_code(db, business_id, model, code)
	return code


def _apply_code_update(db: Session, business_id: int, payload: dict, row: Any, model: Any, prefix: str) -> None:
	if payload.get("auto_generate_code") is True:
		row.code = _allocate_oa_code(db, business_id, model, prefix)
		return
	if payload.get("code"):
		code = _code(payload["code"])
		_ensure_unique_code(db, business_id, model, code, exclude_id=row.id)
		row.code = code


def _audit(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	action: str,
	letter_id: Optional[int] = None,
	position_id: Optional[int] = None,
	payload: Optional[dict] = None,
) -> None:
	db.add(
		OaAuditLog(
			business_id=business_id,
			letter_id=letter_id,
			user_id=user_id,
			position_id=position_id,
			action=action,
			payload=payload,
			created_at=_now(),
		)
	)


def _occupancy_filter(now: datetime):
	return and_(
		OaPositionHolder.is_active == True,  # noqa: E712
		OaPositionHolder.starts_at <= now,
		or_(OaPositionHolder.ends_at.is_(None), OaPositionHolder.ends_at >= now),
	)


def _delegation_filter(now: datetime):
	return and_(
		OaDelegation.is_active == True,  # noqa: E712
		OaDelegation.starts_at <= now,
		or_(OaDelegation.ends_at.is_(None), OaDelegation.ends_at >= now),
	)


def get_or_create_settings(db: Session, business_id: int) -> OaSettings:
	_ensure_plugin(db, business_id)
	row = db.query(OaSettings).filter(OaSettings.business_id == business_id).first()
	if row:
		return row
	row = OaSettings(business_id=business_id, created_at=_now(), updated_at=_now())
	db.add(row)
	db.flush()
	return row


def get_settings(db: Session, business_id: int) -> dict:
	return _settings_dict(get_or_create_settings(db, business_id))


def update_settings(db: Session, business_id: int, payload: dict, user_id: int) -> dict:
	row = get_or_create_settings(db, business_id)
	if "enabled" in payload:
		row.enabled = bool(payload["enabled"])
	if payload.get("numbering_calendar") in {"jalali", "gregorian"}:
		row.numbering_calendar = payload["numbering_calendar"]
	for field in ("incoming_prefix", "outgoing_prefix", "internal_prefix"):
		if payload.get(field):
			setattr(row, field, str(payload[field]).strip()[:16])
	if "letterhead_file_id" in payload:
		row.letterhead_file_id = payload.get("letterhead_file_id") or None
	if "extra_settings" in payload and payload["extra_settings"] is not None:
		row.extra_settings = payload["extra_settings"]
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="settings.update")
	db.commit()
	db.refresh(row)
	return _settings_dict(row)


def _settings_dict(row: OaSettings) -> dict:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"enabled": row.enabled,
		"numbering_calendar": row.numbering_calendar,
		"incoming_prefix": row.incoming_prefix,
		"outgoing_prefix": row.outgoing_prefix,
		"internal_prefix": row.internal_prefix,
		"letterhead_file_id": row.letterhead_file_id,
		"extra_settings": row.extra_settings or {},
		"created_at": row.created_at,
		"updated_at": row.updated_at,
	}


def _unit_dict(row: OaOrgUnit, lang: str) -> dict:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"parent_id": row.parent_id,
		"code": row.code,
		"name_i18n": row.name_i18n,
		"title": resolve_i18n(row.name_i18n, lang),
		"sort_order": row.sort_order,
		"is_active": row.is_active,
	}


def _position_dict(row: OaPosition, lang: str, unit: Optional[OaOrgUnit] = None) -> dict:
	data = {
		"id": row.id,
		"business_id": row.business_id,
		"org_unit_id": row.org_unit_id,
		"code": row.code,
		"name_i18n": row.name_i18n,
		"title": resolve_i18n(row.name_i18n, lang),
		"is_secretariat": row.is_secretariat,
		"can_view_subtree": row.can_view_subtree,
		"sort_order": row.sort_order,
		"is_active": row.is_active,
	}
	if unit is not None:
		data["org_unit_title"] = resolve_i18n(unit.name_i18n, lang)
		data["org_unit_code"] = unit.code
	return data


def list_org_units(db: Session, business_id: int, *, include_inactive: bool = False, lang: str = "fa") -> List[dict]:
	_ensure_plugin(db, business_id)
	q = db.query(OaOrgUnit).filter(OaOrgUnit.business_id == business_id)
	if not include_inactive:
		q = q.filter(OaOrgUnit.is_active == True)  # noqa: E712
	rows = q.order_by(OaOrgUnit.sort_order, OaOrgUnit.id).all()
	return [_unit_dict(r, lang) for r in rows]


def create_org_unit(db: Session, business_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	parent_id = payload.get("parent_id")
	if parent_id:
		parent = db.query(OaOrgUnit).filter(OaOrgUnit.id == int(parent_id), OaOrgUnit.business_id == business_id).first()
		if not parent:
			raise ApiError("OA_ORG_UNIT_NOT_FOUND", "Parent organization unit was not found.", http_status=404)
	row = OaOrgUnit(
		business_id=business_id,
		parent_id=int(parent_id) if parent_id else None,
		code=_resolve_create_code(db, business_id, payload, OaOrgUnit, "u"),
		name_i18n=_normalize_i18n(payload.get("name_i18n") or payload.get("name")),
		sort_order=int(payload.get("sort_order") or 0),
		is_active=bool(payload.get("is_active", True)),
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	_audit(db, business_id=business_id, user_id=user_id, action="org_unit.create", payload={"code": row.code})
	try:
		db.commit()
	except Exception as exc:
		db.rollback()
		raise ApiError("OA_CODE_EXISTS", "This code is already used.", http_status=400) from exc
	db.refresh(row)
	return _unit_dict(row, lang)


def update_org_unit(db: Session, business_id: int, unit_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaOrgUnit).filter(OaOrgUnit.id == unit_id, OaOrgUnit.business_id == business_id).first()
	if not row:
		raise ApiError("OA_ORG_UNIT_NOT_FOUND", "Organization unit was not found.", http_status=404)
	if payload.get("parent_id"):
		pid = int(payload["parent_id"])
		if pid == row.id:
			raise ApiError("VALIDATION_ERROR", "An organization unit cannot be its own parent.", http_status=400)
		parent = db.query(OaOrgUnit).filter(OaOrgUnit.id == pid, OaOrgUnit.business_id == business_id).first()
		if not parent:
			raise ApiError("OA_ORG_UNIT_NOT_FOUND", "Parent organization unit was not found.", http_status=404)
		row.parent_id = pid
	elif "parent_id" in payload:
		row.parent_id = None
	if row.parent_id:
		descendants = _descendant_unit_ids(db, business_id, row.id)
		if row.parent_id in descendants:
			raise ApiError("OA_ORG_UNIT_CYCLE", "An organization unit cannot be nested under its own descendant.", http_status=400)
	_apply_code_update(db, business_id, payload, row, OaOrgUnit, "u")
	if payload.get("name_i18n") or payload.get("name"):
		row.name_i18n = _normalize_i18n(payload.get("name_i18n") or payload.get("name"))
	if "sort_order" in payload:
		row.sort_order = int(payload.get("sort_order") or 0)
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="org_unit.update", payload={"id": row.id})
	db.commit()
	db.refresh(row)
	return _unit_dict(row, lang)


def list_positions(db: Session, business_id: int, *, include_inactive: bool = False, lang: str = "fa") -> List[dict]:
	_ensure_plugin(db, business_id)
	q = (
		db.query(OaPosition, OaOrgUnit)
		.join(OaOrgUnit, OaOrgUnit.id == OaPosition.org_unit_id)
		.filter(OaPosition.business_id == business_id)
	)
	if not include_inactive:
		q = q.filter(OaPosition.is_active == True)  # noqa: E712
	rows = q.order_by(OaPosition.sort_order, OaPosition.id).all()
	return [_position_dict(pos, lang, unit) for pos, unit in rows]


def _get_position(db: Session, business_id: int, position_id: int) -> OaPosition:
	row = db.query(OaPosition).filter(OaPosition.id == position_id, OaPosition.business_id == business_id).first()
	if not row:
		raise ApiError("OA_POSITION_NOT_FOUND", "Position was not found.", http_status=404)
	return row


def create_position(db: Session, business_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	unit = db.query(OaOrgUnit).filter(
		OaOrgUnit.id == int(payload.get("org_unit_id") or 0),
		OaOrgUnit.business_id == business_id,
	).first()
	if not unit:
		raise ApiError("OA_ORG_UNIT_NOT_FOUND", "Organization unit was not found.", http_status=404)
	row = OaPosition(
		business_id=business_id,
		org_unit_id=unit.id,
		code=_resolve_create_code(db, business_id, payload, OaPosition, "p"),
		name_i18n=_normalize_i18n(payload.get("name_i18n") or payload.get("name")),
		is_secretariat=bool(payload.get("is_secretariat", False)),
		can_view_subtree=bool(payload.get("can_view_subtree", False)),
		sort_order=int(payload.get("sort_order") or 0),
		is_active=bool(payload.get("is_active", True)),
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	_audit(db, business_id=business_id, user_id=user_id, action="position.create", payload={"code": row.code})
	try:
		db.commit()
	except Exception as exc:
		db.rollback()
		raise ApiError("OA_CODE_EXISTS", "This code is already used.", http_status=400) from exc
	db.refresh(row)
	return _position_dict(row, lang, unit)


def update_position(db: Session, business_id: int, position_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	row = _get_position(db, business_id, position_id)
	if payload.get("org_unit_id"):
		unit = db.query(OaOrgUnit).filter(
			OaOrgUnit.id == int(payload["org_unit_id"]), OaOrgUnit.business_id == business_id
		).first()
		if not unit:
			raise ApiError("OA_ORG_UNIT_NOT_FOUND", "Organization unit was not found.", http_status=404)
		row.org_unit_id = unit.id
	_apply_code_update(db, business_id, payload, row, OaPosition, "p")
	if payload.get("name_i18n") or payload.get("name"):
		row.name_i18n = _normalize_i18n(payload.get("name_i18n") or payload.get("name"))
	if "is_secretariat" in payload:
		row.is_secretariat = bool(payload["is_secretariat"])
	if "can_view_subtree" in payload:
		row.can_view_subtree = bool(payload["can_view_subtree"])
	if "sort_order" in payload:
		row.sort_order = int(payload.get("sort_order") or 0)
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	row.updated_at = _now()
	unit = db.query(OaOrgUnit).filter(OaOrgUnit.id == row.org_unit_id).first()
	_audit(db, business_id=business_id, user_id=user_id, action="position.update", position_id=row.id)
	db.commit()
	db.refresh(row)
	return _position_dict(row, lang, unit)


def _holder_dict(row: OaPositionHolder, lang: str, position: Optional[OaPosition] = None, user: Optional[User] = None) -> dict:
	data = {
		"id": row.id,
		"position_id": row.position_id,
		"user_id": row.user_id,
		"starts_at": row.starts_at,
		"ends_at": row.ends_at,
		"is_primary": row.is_primary,
		"is_active": row.is_active,
	}
	if position is not None:
		data["position_title"] = resolve_i18n(position.name_i18n, lang)
		data["position_code"] = position.code
		data["is_secretariat"] = position.is_secretariat
	if user is not None:
		data["user_name"] = _user_display_name(user)
	return data


def list_position_holders(
	db: Session, business_id: int, *, position_id: Optional[int] = None, user_id: Optional[int] = None, lang: str = "fa"
) -> List[dict]:
	_ensure_plugin(db, business_id)
	q = (
		db.query(OaPositionHolder, OaPosition, User)
		.join(OaPosition, OaPosition.id == OaPositionHolder.position_id)
		.join(User, User.id == OaPositionHolder.user_id)
		.filter(OaPositionHolder.business_id == business_id)
	)
	if position_id:
		q = q.filter(OaPositionHolder.position_id == position_id)
	if user_id:
		q = q.filter(OaPositionHolder.user_id == user_id)
	rows = q.order_by(OaPositionHolder.is_primary.desc(), OaPositionHolder.id).all()
	return [_holder_dict(h, lang, p, u) for h, p, u in rows]


def assign_position_holder(db: Session, business_id: int, payload: dict, actor_user_id: int, lang: str = "fa", calendar_type: CalendarType = "jalali") -> dict:
	_ensure_plugin(db, business_id)
	position = _get_position(db, business_id, int(payload.get("position_id") or 0))
	user_id = int(payload.get("user_id") or 0)
	user = db.query(User).filter(User.id == user_id).first()
	if not user:
		raise ApiError("USER_NOT_FOUND", "User was not found.", http_status=404)
	overlap = (
		db.query(OaPositionHolder)
		.filter(
			OaPositionHolder.business_id == business_id,
			OaPositionHolder.position_id == position.id,
			OaPositionHolder.user_id == user_id,
		)
		.filter(_occupancy_filter(_now()))
		.first()
	)
	if overlap:
		raise ApiError("OA_HOLDER_EXISTS", "This user already occupies this position.", http_status=400)
	starts_at = _parse_datetime(payload.get("starts_at"), calendar_type) or _now()
	ends_at = _parse_datetime(payload.get("ends_at"), calendar_type)
	if bool(payload.get("is_primary")):
		db.query(OaPositionHolder).filter(
			OaPositionHolder.business_id == business_id,
			OaPositionHolder.user_id == user_id,
			OaPositionHolder.is_primary == True,  # noqa: E712
		).update({"is_primary": False})
	row = OaPositionHolder(
		business_id=business_id,
		position_id=position.id,
		user_id=user_id,
		starts_at=starts_at,
		ends_at=ends_at,
		is_primary=bool(payload.get("is_primary", False)),
		is_active=bool(payload.get("is_active", True)),
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	_audit(db, business_id=business_id, user_id=actor_user_id, action="holder.assign", position_id=position.id, payload={"user_id": user_id})
	db.commit()
	db.refresh(row)
	return _holder_dict(row, lang, position, user)


def end_position_holder(db: Session, business_id: int, holder_id: int, actor_user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaPositionHolder).filter(
		OaPositionHolder.id == holder_id, OaPositionHolder.business_id == business_id
	).first()
	if not row:
		raise ApiError("OA_HOLDER_NOT_FOUND", "Position occupancy was not found.", http_status=404)
	row.is_active = False
	row.ends_at = _now()
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=actor_user_id, action="holder.end", position_id=row.position_id)
	db.commit()
	return {"id": row.id, "ended": True}


def list_my_positions(db: Session, business_id: int, user_id: int, lang: str = "fa") -> List[dict]:
	_ensure_plugin(db, business_id)
	now = _now()
	held = (
		db.query(OaPositionHolder, OaPosition, OaOrgUnit)
		.join(OaPosition, OaPosition.id == OaPositionHolder.position_id)
		.join(OaOrgUnit, OaOrgUnit.id == OaPosition.org_unit_id)
		.filter(OaPositionHolder.business_id == business_id, OaPositionHolder.user_id == user_id)
		.filter(_occupancy_filter(now))
		.filter(OaPosition.is_active == True)  # noqa: E712
		.all()
	)
	items: List[dict] = []
	seen = set()
	for holder, position, unit in held:
		seen.add(position.id)
		data = _position_dict(position, lang, unit)
		data["occupancy_kind"] = "holder"
		data["is_primary"] = holder.is_primary
		data["holder_id"] = holder.id
		items.append(data)
	delegated = (
		db.query(OaDelegation, OaPosition, OaOrgUnit)
		.join(OaPosition, OaPosition.id == OaDelegation.position_id)
		.join(OaOrgUnit, OaOrgUnit.id == OaPosition.org_unit_id)
		.filter(OaDelegation.business_id == business_id, OaDelegation.delegate_user_id == user_id)
		.filter(_delegation_filter(now))
		.filter(OaPosition.is_active == True)  # noqa: E712
		.all()
	)
	for delegation, position, unit in delegated:
		if position.id in seen:
			continue
		data = _position_dict(position, lang, unit)
		data["occupancy_kind"] = "delegate"
		data["delegation_scope"] = delegation.scope
		data["is_primary"] = False
		items.append(data)
	items.sort(key=lambda x: (not x.get("is_primary"), x.get("title") or ""))
	return items


def resolve_acting_position(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	*,
	required_scope: str = "full",
) -> Tuple[OaPosition, str]:
	_ensure_plugin(db, business_id)
	position = _get_position(db, business_id, position_id)
	if not position.is_active:
		raise ApiError("OA_POSITION_INACTIVE", "This position is inactive.", http_status=400)
	now = _now()
	holder = (
		db.query(OaPositionHolder)
		.filter(
			OaPositionHolder.business_id == business_id,
			OaPositionHolder.position_id == position_id,
			OaPositionHolder.user_id == user_id,
		)
		.filter(_occupancy_filter(now))
		.first()
	)
	if holder:
		return position, "holder"
	delegation = (
		db.query(OaDelegation)
		.filter(
			OaDelegation.business_id == business_id,
			OaDelegation.position_id == position_id,
			OaDelegation.delegate_user_id == user_id,
		)
		.filter(_delegation_filter(now))
		.first()
	)
	if delegation:
		if required_scope != "view" and delegation.scope == "view":
			raise ApiError("OA_DELEGATION_VIEW_ONLY", "This delegation is view-only.", http_status=403)
		if required_scope == "full" and delegation.scope == "refer":
			raise ApiError("OA_DELEGATION_REFER_ONLY", "This delegation only allows referrals.", http_status=403)
		return position, "delegate"
	raise ApiError("OA_POSITION_NOT_HELD", "You do not currently occupy this position.", http_status=403)


def list_delegations(db: Session, business_id: int, *, position_id: Optional[int] = None, lang: str = "fa") -> List[dict]:
	_ensure_plugin(db, business_id)
	q = (
		db.query(OaDelegation, OaPosition, User)
		.join(OaPosition, OaPosition.id == OaDelegation.position_id)
		.join(User, User.id == OaDelegation.delegate_user_id)
		.filter(OaDelegation.business_id == business_id)
	)
	if position_id:
		q = q.filter(OaDelegation.position_id == position_id)
	rows = q.order_by(desc(OaDelegation.id)).all()
	out = []
	for d, p, u in rows:
		out.append({
			"id": d.id,
			"position_id": d.position_id,
			"position_title": resolve_i18n(p.name_i18n, lang),
			"delegate_user_id": d.delegate_user_id,
			"delegate_name": _user_display_name(u),
			"scope": d.scope,
			"starts_at": d.starts_at,
			"ends_at": d.ends_at,
			"is_active": d.is_active,
		})
	return out


def create_delegation(db: Session, business_id: int, payload: dict, actor_user_id: int, lang: str = "fa", calendar_type: CalendarType = "jalali") -> dict:
	_ensure_plugin(db, business_id)
	position = _get_position(db, business_id, int(payload.get("position_id") or 0))
	scope = str(payload.get("scope") or "full")
	if scope not in _DELEGATION_SCOPES:
		raise ApiError("VALIDATION_ERROR", "Invalid delegation scope.", http_status=400)
	user_id = int(payload.get("delegate_user_id") or 0)
	user = db.query(User).filter(User.id == user_id).first()
	if not user:
		raise ApiError("USER_NOT_FOUND", "User was not found.", http_status=404)
	overlap = (
		db.query(OaDelegation)
		.filter(
			OaDelegation.business_id == business_id,
			OaDelegation.position_id == position.id,
			OaDelegation.delegate_user_id == user_id,
		)
		.filter(_delegation_filter(_now()))
		.first()
	)
	if overlap:
		raise ApiError("OA_DELEGATION_EXISTS", "An active delegation already exists for this user and position.", http_status=400)
	row = OaDelegation(
		business_id=business_id,
		position_id=position.id,
		delegate_user_id=user_id,
		created_by_user_id=actor_user_id,
		scope=scope,
		starts_at=_parse_datetime(payload.get("starts_at"), calendar_type) or _now(),
		ends_at=_parse_datetime(payload.get("ends_at"), calendar_type),
		is_active=True,
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	_audit(db, business_id=business_id, user_id=actor_user_id, action="delegation.create", position_id=position.id)
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"position_id": row.position_id,
		"position_title": resolve_i18n(position.name_i18n, lang),
		"delegate_user_id": row.delegate_user_id,
		"scope": row.scope,
		"starts_at": row.starts_at,
		"ends_at": row.ends_at,
		"is_active": row.is_active,
	}


def end_delegation(db: Session, business_id: int, delegation_id: int, actor_user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaDelegation).filter(
		OaDelegation.id == delegation_id, OaDelegation.business_id == business_id
	).first()
	if not row:
		raise ApiError("OA_DELEGATION_NOT_FOUND", "Delegation was not found.", http_status=404)
	row.is_active = False
	row.ends_at = _now()
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=actor_user_id, action="delegation.end", position_id=row.position_id)
	db.commit()
	return {"id": row.id, "ended": True}


def _numbering_year(letter_date: date, calendar: str) -> int:
	dt = datetime.combine(letter_date, datetime.min.time())
	if calendar == "jalali":
		return int(CalendarConverter.to_jalali(dt)["year"])
	return letter_date.year


def _allocate_number(db: Session, settings: OaSettings, kind: str, letter_date: date) -> Tuple[str, int, int]:
	year = _numbering_year(letter_date, settings.numbering_calendar)
	counter = (
		db.query(OaLetterNumberCounter)
		.filter(
			OaLetterNumberCounter.business_id == settings.business_id,
			OaLetterNumberCounter.letter_kind == kind,
			OaLetterNumberCounter.year == year,
		)
		.with_for_update()
		.first()
	)
	if not counter:
		counter = OaLetterNumberCounter(
			business_id=settings.business_id, letter_kind=kind, year=year, last_seq=0
		)
		db.add(counter)
		db.flush()
	counter.last_seq += 1
	prefix = getattr(settings, _PREFIX_BY_KIND[kind])
	number = f"{prefix}-{year}/{counter.last_seq:04d}"
	return number, year, counter.last_seq


def _letter_dict(
	row: OaLetter,
	lang: str,
	*,
	origin: Optional[OaPosition] = None,
	paraph_count: Optional[int] = None,
	attachment_count: Optional[int] = None,
	pending_count: Optional[int] = None,
) -> dict:
	data = {
		"id": row.id,
		"letter_kind": row.letter_kind,
		"status": row.status,
		"subject": row.subject,
		"body": row.body,
		"locale": row.locale,
		"letter_date": row.letter_date,
		"urgency": row.urgency,
		"confidentiality": row.confidentiality,
		"sender_name": row.sender_name,
		"sender_org": row.sender_org,
		"receiver_name": row.receiver_name,
		"receiver_org": row.receiver_org,
		"origin_position_id": row.origin_position_id,
		"created_by_user_id": row.created_by_user_id,
		"registered_at": row.registered_at,
		"secretariat_number": row.secretariat_number,
		"secretariat_year": row.secretariat_year,
		"secretariat_seq": row.secretariat_seq,
		"follow_up_at": row.follow_up_at,
		"person_id": row.person_id,
		"created_at": row.created_at,
		"updated_at": row.updated_at,
	}
	if origin is not None:
		data["origin_position_title"] = resolve_i18n(origin.name_i18n, lang)
	if paraph_count is not None:
		data["paraph_count"] = paraph_count
	if attachment_count is not None:
		data["attachment_count"] = attachment_count
	if pending_count is not None:
		data["pending_referral_count"] = pending_count
	return data


def _get_letter(db: Session, business_id: int, letter_id: int) -> OaLetter:
	row = db.query(OaLetter).filter(OaLetter.id == letter_id, OaLetter.business_id == business_id).first()
	if not row:
		raise ApiError("OA_LETTER_NOT_FOUND", "Letter was not found.", http_status=404)
	return row


def _user_position_ids(db: Session, business_id: int, user_id: int) -> List[int]:
	now = _now()
	held = [
		r[0]
		for r in db.query(OaPositionHolder.position_id)
		.filter(OaPositionHolder.business_id == business_id, OaPositionHolder.user_id == user_id)
		.filter(_occupancy_filter(now))
		.all()
	]
	delegated = [
		r[0]
		for r in db.query(OaDelegation.position_id)
		.filter(OaDelegation.business_id == business_id, OaDelegation.delegate_user_id == user_id)
		.filter(_delegation_filter(now))
		.all()
	]
	return list({*held, *delegated})


def _descendant_unit_ids(db: Session, business_id: int, root_unit_id: int) -> set[int]:
	rows = db.query(OaOrgUnit.id, OaOrgUnit.parent_id).filter(OaOrgUnit.business_id == business_id).all()
	by_parent: Dict[Optional[int], List[int]] = {}
	for unit_id, parent_id in rows:
		by_parent.setdefault(parent_id, []).append(unit_id)
	found: set[int] = set()
	stack = [root_unit_id]
	while stack:
		current = stack.pop()
		for child in by_parent.get(current, []):
			if child not in found:
				found.add(child)
				stack.append(child)
	return found


def _can_view_letter(db: Session, letter: OaLetter, user_id: int, is_admin: bool) -> bool:
	if is_admin:
		return True
	position_ids = _user_position_ids(db, letter.business_id, user_id)
	if not position_ids:
		return False
	if letter.origin_position_id in position_ids:
		return True
	exists = (
		db.query(OaReferral.id)
		.filter(
			OaReferral.letter_id == letter.id,
			or_(OaReferral.from_position_id.in_(position_ids), OaReferral.to_position_id.in_(position_ids)),
		)
		.first()
	)
	if exists:
		return True
	positions = db.query(OaPosition).filter(OaPosition.id.in_(position_ids)).all()
	if letter.status != "draft" and any(p.is_secretariat for p in positions):
		return True
	for position in positions:
		if not position.can_view_subtree:
			continue
		unit_ids = _descendant_unit_ids(db, letter.business_id, position.org_unit_id) | {position.org_unit_id}
		related_position_ids = [
			row[0]
			for row in db.query(OaPosition.id).filter(OaPosition.org_unit_id.in_(unit_ids or {0})).all()
		]
		if letter.origin_position_id in related_position_ids:
			return True
		subtree_hit = (
			db.query(OaReferral.id)
			.filter(
				OaReferral.letter_id == letter.id,
				or_(
					OaReferral.from_position_id.in_(related_position_ids or [0]),
					OaReferral.to_position_id.in_(related_position_ids or [0]),
				),
			)
			.first()
		)
		if subtree_hit:
			return True
	return False


def _apply_letter_payload(row: OaLetter, payload: dict, calendar_type: CalendarType) -> None:
	if payload.get("subject"):
		row.subject = str(payload["subject"]).strip()[:500]
	if "body" in payload:
		row.body = payload.get("body")
	if payload.get("locale") in {"fa", "en"}:
		row.locale = payload["locale"]
	if payload.get("letter_kind") in _LETTER_KINDS:
		row.letter_kind = payload["letter_kind"]
	if payload.get("urgency") in _URGENCY:
		row.urgency = payload["urgency"]
	if payload.get("confidentiality") in _CONFIDENTIALITY:
		row.confidentiality = payload["confidentiality"]
	if "sender_name" in payload:
		row.sender_name = payload.get("sender_name")
	if "sender_org" in payload:
		row.sender_org = payload.get("sender_org")
	if "receiver_name" in payload:
		row.receiver_name = payload.get("receiver_name")
	if "receiver_org" in payload:
		row.receiver_org = payload.get("receiver_org")
	if "person_id" in payload:
		row.person_id = int(payload["person_id"]) if payload.get("person_id") else None
	if "letter_date" in payload and payload.get("letter_date"):
		row.letter_date = _parse_date(payload["letter_date"], calendar_type) or row.letter_date
	if "follow_up_at" in payload:
		row.follow_up_at = _parse_date(payload.get("follow_up_at"), calendar_type)


def create_letter_draft(
	db: Session,
	business_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	subject = str(payload.get("subject") or "").strip()
	if not subject:
		raise ApiError("VALIDATION_ERROR", "Letter subject is required.", http_status=400)
	kind = str(payload.get("letter_kind") or "internal")
	if kind not in _LETTER_KINDS:
		raise ApiError("VALIDATION_ERROR", "Invalid letter kind.", http_status=400)
	letter_date = _parse_date(payload.get("letter_date"), calendar_type) or date.today()
	row = OaLetter(
		business_id=business_id,
		letter_kind=kind,
		status="draft",
		subject=subject[:500],
		body=payload.get("body"),
		locale=payload.get("locale") if payload.get("locale") in {"fa", "en"} else "fa",
		letter_date=letter_date,
		urgency=payload.get("urgency") if payload.get("urgency") in _URGENCY else "normal",
		confidentiality=payload.get("confidentiality") if payload.get("confidentiality") in _CONFIDENTIALITY else "normal",
		sender_name=payload.get("sender_name"),
		sender_org=payload.get("sender_org"),
		receiver_name=payload.get("receiver_name"),
		receiver_org=payload.get("receiver_org"),
		origin_position_id=position.id,
		created_by_user_id=user_id,
		person_id=int(payload["person_id"]) if payload.get("person_id") else None,
		follow_up_at=_parse_date(payload.get("follow_up_at"), calendar_type),
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	db.flush()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.draft", letter_id=row.id, position_id=position.id)
	db.commit()
	db.refresh(row)
	return _letter_dict(row, lang, origin=position)


def update_letter_draft(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = _get_letter(db, business_id, letter_id)
	if row.status != "draft":
		raise ApiError("OA_LETTER_NOT_DRAFT", "Only draft letters can be edited.", http_status=400)
	if row.origin_position_id != position.id:
		raise ApiError("OA_LETTER_FORBIDDEN", "This draft does not belong to the active position.", http_status=403)
	_apply_letter_payload(row, payload, calendar_type)
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.update_draft", letter_id=row.id, position_id=position.id)
	db.commit()
	db.refresh(row)
	return _letter_dict(row, lang, origin=position)


def delete_letter_draft(db: Session, business_id: int, letter_id: int, user_id: int, position_id: int) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = _get_letter(db, business_id, letter_id)
	if row.status != "draft":
		raise ApiError("OA_LETTER_NOT_DRAFT", "Only draft letters can be deleted.", http_status=400)
	if row.origin_position_id != position.id:
		raise ApiError("OA_LETTER_FORBIDDEN", "This draft does not belong to the active position.", http_status=403)
	db.query(OaLetterAttachment).filter(OaLetterAttachment.letter_id == row.id).delete()
	db.query(OaParaph).filter(OaParaph.letter_id == row.id).delete()
	db.query(OaLetterLink).filter(or_(OaLetterLink.letter_id == row.id, OaLetterLink.related_letter_id == row.id)).delete()
	db.delete(row)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.delete_draft", letter_id=letter_id, position_id=position.id)
	db.commit()
	return {"id": letter_id, "deleted": True}


def register_letter(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = _get_letter(db, business_id, letter_id)
	if row.status != "draft":
		raise ApiError("OA_LETTER_NOT_DRAFT", "Only draft letters can be registered.", http_status=400)
	kind = str(payload.get("letter_kind") or row.letter_kind)
	if kind not in _LETTER_KINDS:
		raise ApiError("VALIDATION_ERROR", "Invalid letter kind.", http_status=400)
	if kind in {"incoming", "outgoing"} and not position.is_secretariat:
		raise ApiError("OA_SECRETARIAT_REQUIRED", "Incoming and outgoing letters require a secretariat position.", http_status=403)
	if kind == "internal" and row.origin_position_id != position.id and not position.is_secretariat:
		raise ApiError("OA_LETTER_FORBIDDEN", "This draft does not belong to the active position.", http_status=403)
	settings = get_or_create_settings(db, business_id)
	if not settings.enabled:
		raise ApiError("OA_DISABLED", "Office automation is disabled in settings.", http_status=400)
	_apply_letter_payload(row, payload, calendar_type)
	row.letter_kind = kind
	number, year, seq = _allocate_number(db, settings, kind, row.letter_date)
	row.secretariat_number = number
	row.secretariat_year = year
	row.secretariat_seq = seq
	row.registered_at = _now()
	row.registered_by_user_id = user_id
	row.registered_by_position_id = position.id
	row.status = "registered"
	row.updated_at = _now()
	recipients = payload.get("recipients") or []
	created_referrals = []
	for item in recipients:
		created_referrals.append(
			_create_referral(
				db,
				letter=row,
				from_position=position,
				from_user_id=user_id,
				to_position_id=int(item.get("to_position_id") or 0),
				kind=str(item.get("kind") or "action"),
				priority=str(item.get("priority") or row.urgency),
				instruction=item.get("instruction"),
				due_at=_parse_date(item.get("due_at"), calendar_type),
				parent_referral_id=None,
			)
		)
	if created_referrals:
		row.status = "in_circulation"
	_audit(
		db,
		business_id=business_id,
		user_id=user_id,
		action="letter.register",
		letter_id=row.id,
		position_id=position.id,
		payload={"number": number, "kind": kind},
	)
	db.commit()
	db.refresh(row)
	_notify_referral_recipients(db, business_id, created_referrals, row)
	return get_letter(db, business_id, row.id, user_id, position_id, lang=lang, is_admin=True)


def _create_referral(
	db: Session,
	*,
	letter: OaLetter,
	from_position: OaPosition,
	from_user_id: int,
	to_position_id: int,
	kind: str,
	priority: str,
	instruction: Optional[str],
	due_at: Optional[date],
	parent_referral_id: Optional[int],
) -> OaReferral:
	if kind not in _REFERRAL_KINDS:
		raise ApiError("VALIDATION_ERROR", "Invalid referral kind.", http_status=400)
	to_position = _get_position(db, letter.business_id, to_position_id)
	if not to_position.is_active:
		raise ApiError("OA_POSITION_INACTIVE", "Target position is inactive.", http_status=400)
	row = OaReferral(
		business_id=letter.business_id,
		letter_id=letter.id,
		from_position_id=from_position.id,
		to_position_id=to_position.id,
		from_user_id=from_user_id,
		parent_referral_id=parent_referral_id,
		kind=kind,
		priority=priority if priority in _URGENCY else "normal",
		instruction=instruction,
		due_at=due_at,
		status="pending",
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	db.flush()
	return row


def _notify_referral_recipients(db: Session, business_id: int, referrals: Sequence[OaReferral], letter: OaLetter) -> None:
	if not referrals:
		return
	try:
		from app.services.notification_service import NotificationService

		svc = NotificationService(db)
		now = _now()
		for referral in referrals:
			user_ids = {
				r[0]
				for r in db.query(OaPositionHolder.user_id)
				.filter(OaPositionHolder.position_id == referral.to_position_id, OaPositionHolder.business_id == business_id)
				.filter(_occupancy_filter(now))
				.all()
			}
			user_ids |= {
				r[0]
				for r in db.query(OaDelegation.delegate_user_id)
				.filter(OaDelegation.position_id == referral.to_position_id, OaDelegation.business_id == business_id)
				.filter(_delegation_filter(now))
				.all()
			}
			for uid in user_ids:
				try:
					svc.send(
						user_id=int(uid),
						event_key=(
							"office_automation.letter_returned"
							if referral.kind == "return"
							else "office_automation.letter_referred"
						),
						context={
							"subject": letter.subject,
							"number": letter.secretariat_number or "",
							"letter_id": letter.id,
							"business_name": (
								db.query(Business.name).filter(Business.id == business_id).scalar() or ""
							),
						},
						preferred_channels=["inapp"],
					)
				except Exception:
					logger.debug("OA referral notify failed for user %s", uid, exc_info=True)
	except Exception:
		logger.debug("OA notification skipped", exc_info=True)


def refer_letter(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	row = _get_letter(db, business_id, letter_id)
	if row.status == "draft":
		raise ApiError("OA_LETTER_STILL_DRAFT", "Register the letter before referring it.", http_status=400)
	if row.status == "archived":
		raise ApiError("OA_LETTER_ARCHIVED", "Archived letters cannot be referred.", http_status=400)
	recipients = payload.get("recipients") or []
	if not recipients and payload.get("to_position_id"):
		recipients = [payload]
	if not recipients:
		raise ApiError("VALIDATION_ERROR", "At least one recipient is required.", http_status=400)
	created = []
	parent_id = int(payload["parent_referral_id"]) if payload.get("parent_referral_id") else None
	for item in recipients:
		created.append(
			_create_referral(
				db,
				letter=row,
				from_position=position,
				from_user_id=user_id,
				to_position_id=int(item.get("to_position_id") or 0),
				kind=str(item.get("kind") or "action"),
				priority=str(item.get("priority") or row.urgency),
				instruction=item.get("instruction"),
				due_at=_parse_date(item.get("due_at"), calendar_type),
				parent_referral_id=parent_id,
			)
		)
	if row.status == "registered":
		row.status = "in_circulation"
		row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.refer", letter_id=row.id, position_id=position.id)
	db.commit()
	_notify_referral_recipients(db, business_id, created, row)
	return get_letter(db, business_id, row.id, user_id, position_id, lang=lang, is_admin=True)


def _get_referral(db: Session, business_id: int, referral_id: int) -> OaReferral:
	row = db.query(OaReferral).filter(OaReferral.id == referral_id, OaReferral.business_id == business_id).first()
	if not row:
		raise ApiError("OA_REFERRAL_NOT_FOUND", "Referral was not found.", http_status=404)
	return row


def complete_referral(
	db: Session,
	business_id: int,
	referral_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	row = _get_referral(db, business_id, referral_id)
	if row.to_position_id != position.id:
		raise ApiError("OA_REFERRAL_FORBIDDEN", "This referral is not in the active position cartable.", http_status=403)
	if row.status in {"done", "returned", "cancelled"}:
		raise ApiError("OA_REFERRAL_CLOSED", "This referral is already closed.", http_status=400)
	letter = _get_letter(db, business_id, row.letter_id)
	if letter.status == "archived":
		raise ApiError("OA_LETTER_ARCHIVED", "Archived letters cannot be changed.", http_status=400)
	row.status = "done"
	row.completed_at = _now()
	row.completion_note = payload.get("note")
	row.updated_at = _now()
	open_count = (
		db.query(func.count(OaReferral.id))
		.filter(
			OaReferral.letter_id == letter.id,
			OaReferral.status.in_(["pending", "seen"]),
			OaReferral.kind == "action",
		)
		.scalar()
		or 0
	)
	if open_count == 0 and letter.status == "in_circulation":
		letter.status = "closed"
		letter.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="referral.complete", letter_id=letter.id, position_id=position.id)
	db.commit()
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=True)


def return_referral(
	db: Session,
	business_id: int,
	referral_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	row = _get_referral(db, business_id, referral_id)
	if row.to_position_id != position.id:
		raise ApiError("OA_REFERRAL_FORBIDDEN", "This referral is not in the active position cartable.", http_status=403)
	if row.status in {"done", "returned", "cancelled"}:
		raise ApiError("OA_REFERRAL_CLOSED", "This referral is already closed.", http_status=400)
	letter = _get_letter(db, business_id, row.letter_id)
	if letter.status == "archived":
		raise ApiError("OA_LETTER_ARCHIVED", "Archived letters cannot be changed.", http_status=400)
	row.status = "returned"
	row.completed_at = _now()
	row.completion_note = payload.get("note")
	row.updated_at = _now()
	returned = _create_referral(
		db,
		letter=letter,
		from_position=position,
		from_user_id=user_id,
		to_position_id=row.from_position_id,
		kind="return",
		priority=row.priority,
		instruction=payload.get("note"),
		due_at=None,
		parent_referral_id=row.id,
	)
	_audit(db, business_id=business_id, user_id=user_id, action="referral.return", letter_id=letter.id, position_id=position.id)
	db.commit()
	_notify_referral_recipients(db, business_id, [returned], letter)
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=True)


def add_paraph(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	letter = _get_letter(db, business_id, letter_id)
	_require_letter_open(letter)
	text = str(payload.get("text") or "").strip()
	if not text:
		raise ApiError("VALIDATION_ERROR", "Paraph text is required.", http_status=400)
	row = OaParaph(
		business_id=business_id,
		letter_id=letter.id,
		referral_id=int(payload["referral_id"]) if payload.get("referral_id") else None,
		position_id=position.id,
		user_id=user_id,
		text=text,
		created_at=_now(),
	)
	db.add(row)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.paraph", letter_id=letter.id, position_id=position.id)
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"letter_id": row.letter_id,
		"position_id": row.position_id,
		"position_title": resolve_i18n(position.name_i18n, lang),
		"user_id": row.user_id,
		"text": row.text,
		"created_at": row.created_at,
	}


def add_attachment(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	letter = _get_letter(db, business_id, letter_id)
	_require_letter_open(letter, allow_draft=True)
	file_id = str(payload.get("file_storage_id") or "").strip()
	if not file_id:
		raise ApiError("VALIDATION_ERROR", "file_storage_id is required.", http_status=400)
	storage = db.query(FileStorage).filter(FileStorage.id == file_id).first()
	if not storage or (storage.business_id not in (None, business_id)):
		raise ApiError("FILE_NOT_FOUND", "Attachment file was not found.", http_status=404)
	row = OaLetterAttachment(
		business_id=business_id,
		letter_id=letter.id,
		file_storage_id=file_id,
		title=payload.get("title") or storage.original_name,
		uploaded_by_user_id=user_id,
		uploaded_as_position_id=position.id,
		created_at=_now(),
	)
	db.add(row)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.attach", letter_id=letter.id, position_id=position.id)
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"letter_id": row.letter_id,
		"file_storage_id": row.file_storage_id,
		"title": row.title,
		"original_name": storage.original_name,
		"mime_type": storage.mime_type,
		"file_size": storage.file_size,
		"created_at": row.created_at,
	}


def remove_attachment(db: Session, business_id: int, attachment_id: int, user_id: int, position_id: int) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = db.query(OaLetterAttachment).filter(
		OaLetterAttachment.id == attachment_id, OaLetterAttachment.business_id == business_id
	).first()
	if not row:
		raise ApiError("OA_ATTACHMENT_NOT_FOUND", "Attachment was not found.", http_status=404)
	letter = _get_letter(db, business_id, row.letter_id)
	_require_letter_open(letter, allow_draft=True)
	letter_id = row.letter_id
	db.delete(row)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.detach", letter_id=letter_id, position_id=position.id)
	db.commit()
	return {"id": attachment_id, "deleted": True}


def archive_letter(db: Session, business_id: int, letter_id: int, user_id: int, position_id: int, lang: str = "fa") -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = _get_letter(db, business_id, letter_id)
	if row.status == "draft":
		raise ApiError("OA_LETTER_STILL_DRAFT", "Draft letters cannot be archived.", http_status=400)
	if row.status == "archived":
		raise ApiError("OA_LETTER_ARCHIVED", "Letter is already archived.", http_status=400)
	row.status = "archived"
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.archive", letter_id=row.id, position_id=position.id)
	db.commit()
	return get_letter(db, business_id, row.id, user_id, position_id, lang=lang, is_admin=True)


def set_follow_up(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	row = _get_letter(db, business_id, letter_id)
	_require_letter_open(row)
	row.follow_up_at = _parse_date(payload.get("follow_up_at"), calendar_type)
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.follow_up", letter_id=row.id, position_id=position.id)
	db.commit()
	return get_letter(db, business_id, row.id, user_id, position_id, lang=lang, is_admin=True)


def link_letters(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	letter = _get_letter(db, business_id, letter_id)
	_require_letter_open(letter)
	related_id = int(payload.get("related_letter_id") or 0)
	if related_id == letter.id:
		raise ApiError("VALIDATION_ERROR", "A letter cannot be linked to itself.", http_status=400)
	related = _get_letter(db, business_id, related_id)
	kind = str(payload.get("link_kind") or "related")
	if kind not in _LINK_KINDS:
		raise ApiError("VALIDATION_ERROR", "Invalid letter link kind.", http_status=400)
	row = OaLetterLink(
		business_id=business_id,
		letter_id=letter.id,
		related_letter_id=related.id,
		link_kind=kind,
		created_by_user_id=user_id,
		created_at=_now(),
	)
	db.add(row)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.link", letter_id=letter.id, position_id=position.id)
	try:
		db.commit()
	except Exception as exc:
		db.rollback()
		raise ApiError("VALIDATION_ERROR", "These letters are already linked.", http_status=400) from exc
	return {"id": row.id, "letter_id": letter.id, "related_letter_id": related.id, "link_kind": kind}


def get_letter(
	db: Session,
	business_id: int,
	letter_id: int,
	user_id: int,
	position_id: Optional[int],
	lang: str = "fa",
	is_admin: bool = False,
) -> dict:
	_ensure_plugin(db, business_id)
	row = _get_letter(db, business_id, letter_id)
	if position_id:
		resolve_acting_position(db, business_id, user_id, position_id, required_scope="view")
	if not _can_view_letter(db, row, user_id, is_admin):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot view this letter.", http_status=403)
	origin = db.query(OaPosition).filter(OaPosition.id == row.origin_position_id).first()
	if position_id:
		pending = (
			db.query(OaReferral)
			.filter(
				OaReferral.letter_id == row.id,
				OaReferral.to_position_id == position_id,
				OaReferral.status == "pending",
			)
			.all()
		)
		for ref in pending:
			ref.status = "seen"
			ref.seen_at = _now()
			ref.updated_at = _now()
		if pending:
			db.commit()
	paraphs = (
		db.query(OaParaph, OaPosition)
		.join(OaPosition, OaPosition.id == OaParaph.position_id)
		.filter(OaParaph.letter_id == row.id)
		.order_by(OaParaph.created_at)
		.all()
	)
	attachments = (
		db.query(OaLetterAttachment, FileStorage)
		.outerjoin(FileStorage, FileStorage.id == OaLetterAttachment.file_storage_id)
		.filter(OaLetterAttachment.letter_id == row.id)
		.order_by(OaLetterAttachment.created_at)
		.all()
	)
	referrals = (
		db.query(OaReferral, OaPosition)
		.join(OaPosition, OaPosition.id == OaReferral.to_position_id)
		.filter(OaReferral.letter_id == row.id)
		.order_by(OaReferral.created_at)
		.all()
	)
	from_positions = {
		p.id: p
		for p in db.query(OaPosition).filter(
			OaPosition.id.in_({r.from_position_id for r, _ in referrals} or {0})
		).all()
	}
	links = (
		db.query(OaLetterLink, OaLetter)
		.join(OaLetter, OaLetter.id == OaLetterLink.related_letter_id)
		.filter(OaLetterLink.letter_id == row.id)
		.all()
	)
	audit = (
		db.query(OaAuditLog)
		.filter(OaAuditLog.letter_id == row.id)
		.order_by(OaAuditLog.created_at)
		.all()
	)
	data = _letter_dict(row, lang, origin=origin)
	data["paraphs"] = [
		{
			"id": p.id,
			"text": p.text,
			"position_id": p.position_id,
			"position_title": resolve_i18n(pos.name_i18n, lang),
			"user_id": p.user_id,
			"created_at": p.created_at,
		}
		for p, pos in paraphs
	]
	data["attachments"] = [
		{
			"id": a.id,
			"file_storage_id": a.file_storage_id,
			"title": a.title,
			"original_name": getattr(f, "original_name", None),
			"mime_type": getattr(f, "mime_type", None),
			"file_size": getattr(f, "file_size", None),
			"created_at": a.created_at,
		}
		for a, f in attachments
	]
	data["referrals"] = [
		{
			"id": r.id,
			"kind": r.kind,
			"priority": r.priority,
			"status": r.status,
			"instruction": r.instruction,
			"due_at": r.due_at,
			"from_position_id": r.from_position_id,
			"from_position_title": resolve_i18n(from_positions[r.from_position_id].name_i18n, lang) if r.from_position_id in from_positions else "",
			"to_position_id": r.to_position_id,
			"to_position_title": resolve_i18n(to_pos.name_i18n, lang),
			"completion_note": r.completion_note,
			"created_at": r.created_at,
			"seen_at": r.seen_at,
			"completed_at": r.completed_at,
		}
		for r, to_pos in referrals
	]
	data["links"] = [
		{
			"id": lnk.id,
			"link_kind": lnk.link_kind,
			"related_letter_id": related.id,
			"related_subject": related.subject,
			"related_number": related.secretariat_number,
		}
		for lnk, related in links
	]
	data["timeline"] = [
		{"id": a.id, "action": a.action, "user_id": a.user_id, "position_id": a.position_id, "payload": a.payload, "created_at": a.created_at}
		for a in audit
	]
	return data


def get_letter_print(
	db: Session,
	business_id: int,
	letter_id: int,
	user_id: int,
	position_id: Optional[int],
	lang: str = "fa",
	is_admin: bool = False,
) -> dict:
	data = get_letter(db, business_id, letter_id, user_id, position_id, lang=lang, is_admin=is_admin)
	settings = get_settings(db, business_id)
	data["print"] = {
		"letterhead_file_id": settings.get("letterhead_file_id"),
		"numbering_calendar": settings.get("numbering_calendar"),
		"incoming_prefix": settings.get("incoming_prefix"),
		"outgoing_prefix": settings.get("outgoing_prefix"),
		"internal_prefix": settings.get("internal_prefix"),
	}
	return data


def list_cartable(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	*,
	folder: str = "inbox",
	q: Optional[str] = None,
	limit: int = 50,
	skip: int = 0,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
	date_from: Any = None,
	date_to: Any = None,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="view")
	if folder not in _CARTABLE_FOLDERS:
		raise ApiError("VALIDATION_ERROR", "Invalid cartable folder.", http_status=400)
	limit = max(1, min(int(limit or 50), 200))
	skip = max(0, int(skip or 0))
	from_d = _parse_date(date_from, calendar_type)
	to_d = _parse_date(date_to, calendar_type)

	def _apply_search(query, *, include_body: bool = True):
		if q:
			like = f"%{q.strip()}%"
			filters = [OaLetter.subject.ilike(like), OaLetter.secretariat_number.ilike(like)]
			if include_body:
				filters.append(OaLetter.body.ilike(like))
			query = query.filter(or_(*filters))
		if from_d:
			query = query.filter(OaLetter.letter_date >= from_d)
		if to_d:
			query = query.filter(OaLetter.letter_date <= to_d)
		return query

	items: List[dict] = []
	total = 0
	if folder == "drafts":
		query = db.query(OaLetter).filter(
			OaLetter.business_id == business_id,
			OaLetter.origin_position_id == position.id,
			OaLetter.status == "draft",
		)
		query = _apply_search(query)
		total = query.count()
		rows = query.order_by(desc(OaLetter.updated_at)).offset(skip).limit(limit).all()
		items = [_letter_dict(r, lang, origin=position) for r in rows]
	elif folder == "sent":
		query = (
			db.query(OaReferral, OaLetter)
			.join(OaLetter, OaLetter.id == OaReferral.letter_id)
			.filter(OaReferral.business_id == business_id, OaReferral.from_position_id == position.id)
		)
		query = _apply_search(query, include_body=False)
		total = query.count()
		rows = query.order_by(desc(OaReferral.created_at)).offset(skip).limit(limit).all()
		for ref, letter in rows:
			data = _letter_dict(letter, lang, origin=position)
			data["referral_id"] = ref.id
			data["referral_kind"] = ref.kind
			data["referral_status"] = ref.status
			items.append(data)
	elif folder == "followup":
		query = db.query(OaLetter).filter(
			OaLetter.business_id == business_id,
			OaLetter.follow_up_at.isnot(None),
			OaLetter.status != "draft",
			or_(
				OaLetter.origin_position_id == position.id,
				OaLetter.id.in_(db.query(OaReferral.letter_id).filter(OaReferral.to_position_id == position.id)),
			),
		)
		query = _apply_search(query)
		total = query.count()
		rows = query.order_by(OaLetter.follow_up_at).offset(skip).limit(limit).all()
		items = [_letter_dict(r, lang, origin=position) for r in rows]
	elif folder == "archive":
		query = db.query(OaLetter).filter(
			OaLetter.business_id == business_id,
			OaLetter.status == "archived",
			or_(
				OaLetter.origin_position_id == position.id,
				OaLetter.id.in_(db.query(OaReferral.letter_id).filter(
					or_(OaReferral.to_position_id == position.id, OaReferral.from_position_id == position.id)
				)),
			),
		)
		query = _apply_search(query)
		total = query.count()
		rows = query.order_by(desc(OaLetter.updated_at)).offset(skip).limit(limit).all()
		items = [_letter_dict(r, lang, origin=position) for r in rows]
	elif folder == "registry":
		if not position.is_secretariat:
			raise ApiError("OA_SECRETARIAT_REQUIRED", "Registry search requires a secretariat position.", http_status=403)
		query = db.query(OaLetter).filter(
			OaLetter.business_id == business_id,
			OaLetter.status != "draft",
		)
		query = _apply_search(query)
		total = query.count()
		rows = query.order_by(desc(OaLetter.registered_at), desc(OaLetter.updated_at)).offset(skip).limit(limit).all()
		items = [_letter_dict(r, lang, origin=position) for r in rows]
	else:
		query = (
			db.query(OaReferral, OaLetter)
			.join(OaLetter, OaLetter.id == OaReferral.letter_id)
			.filter(OaReferral.business_id == business_id, OaReferral.to_position_id == position.id)
		)
		if folder == "action":
			query = query.filter(OaReferral.kind == "action", OaReferral.status.in_(["pending", "seen"]))
		elif folder == "cc":
			query = query.filter(OaReferral.kind == "info", OaReferral.status.in_(["pending", "seen"]))
		else:
			query = query.filter(OaReferral.status.in_(["pending", "seen"]))
		query = _apply_search(query, include_body=False)
		total = query.count()
		rows = query.order_by(desc(OaReferral.created_at)).offset(skip).limit(limit).all()
		for ref, letter in rows:
			data = _letter_dict(letter, lang)
			data["referral_id"] = ref.id
			data["referral_kind"] = ref.kind
			data["referral_status"] = ref.status
			data["referral_priority"] = ref.priority
			data["due_at"] = ref.due_at
			data["instruction"] = ref.instruction
			items.append(data)
	return {"items": items, "total": total, "folder": folder, "position_id": position.id}


def _folder_counts(db: Session, business_id: int, position: OaPosition) -> dict:
	pid = position.id
	pending = ("pending", "seen")
	inbox = db.query(func.count(OaReferral.id)).filter(
		OaReferral.business_id == business_id,
		OaReferral.to_position_id == pid,
		OaReferral.status.in_(pending),
	).scalar() or 0
	action = db.query(func.count(OaReferral.id)).filter(
		OaReferral.business_id == business_id,
		OaReferral.to_position_id == pid,
		OaReferral.kind == "action",
		OaReferral.status.in_(pending),
	).scalar() or 0
	cc = db.query(func.count(OaReferral.id)).filter(
		OaReferral.business_id == business_id,
		OaReferral.to_position_id == pid,
		OaReferral.kind == "info",
		OaReferral.status.in_(pending),
	).scalar() or 0
	drafts = db.query(func.count(OaLetter.id)).filter(
		OaLetter.business_id == business_id,
		OaLetter.origin_position_id == pid,
		OaLetter.status == "draft",
	).scalar() or 0
	sent = db.query(func.count(OaReferral.id)).filter(
		OaReferral.business_id == business_id,
		OaReferral.from_position_id == pid,
	).scalar() or 0
	followup = db.query(func.count(OaLetter.id)).filter(
		OaLetter.business_id == business_id,
		OaLetter.follow_up_at.isnot(None),
		OaLetter.status != "draft",
		or_(
			OaLetter.origin_position_id == pid,
			OaLetter.id.in_(db.query(OaReferral.letter_id).filter(OaReferral.to_position_id == pid)),
		),
	).scalar() or 0
	archive = db.query(func.count(OaLetter.id)).filter(
		OaLetter.business_id == business_id,
		OaLetter.status == "archived",
		or_(
			OaLetter.origin_position_id == pid,
			OaLetter.id.in_(db.query(OaReferral.letter_id).filter(
				or_(OaReferral.to_position_id == pid, OaReferral.from_position_id == pid)
			)),
		),
	).scalar() or 0
	counts = {
		"inbox": int(inbox),
		"action": int(action),
		"cc": int(cc),
		"drafts": int(drafts),
		"sent": int(sent),
		"followup": int(followup),
		"archive": int(archive),
		"registry": 0,
	}
	if position.is_secretariat:
		counts["registry"] = int(
			db.query(func.count(OaLetter.id)).filter(
				OaLetter.business_id == business_id,
				OaLetter.status != "draft",
			).scalar() or 0
		)
	return counts


def get_dashboard(db: Session, business_id: int, user_id: int, position_id: Optional[int], lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	my_positions = list_my_positions(db, business_id, user_id, lang=lang)
	counts = {"inbox": 0, "action": 0, "cc": 0, "drafts": 0, "sent": 0, "followup": 0, "archive": 0, "registry": 0}
	held_ids = {p["id"] for p in my_positions}
	active_id = position_id if position_id in held_ids else (my_positions[0]["id"] if my_positions else None)
	if active_id:
		position = _get_position(db, business_id, int(active_id))
		counts = _folder_counts(db, business_id, position)
	return {
		"my_positions": my_positions,
		"active_position_id": active_id,
		"counts": counts,
	}
