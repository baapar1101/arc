"""سرویس اتوماسیون اداری سمت‌محور: ساختار، نامه، کارتابل، ارجاع، پاراف و پیوست."""
from __future__ import annotations

import logging
import re
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Sequence, Tuple

from sqlalchemy import and_, desc, false, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage
from adapters.db.models.office_automation import (
	OaAuditLog,
	OaCartableSavedFilter,
	OaDelegation,
	OaLetter,
	OaLetterAttachment,
	OaLetterSignStep,
	OaLetterFormat,
	OaLetterLink,
	OaLetterNumberCounter,
	OaLetterTemplate,
	OaOrgUnit,
	OaParaph,
	OaPosition,
	OaPositionHolder,
	OaReferral,
	OaSecretariat,
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
_CONFIDENTIALITY = frozenset({"normal", "confidential", "highly_confidential", "secret"})
_CLASSIFIED = frozenset({"confidential", "highly_confidential", "secret"})
_REFERRAL_KINDS = frozenset({"action", "info", "signature", "return"})
_REFERRAL_STATUSES = frozenset({"pending", "seen", "done", "returned", "cancelled"})
_DELEGATION_SCOPES = frozenset({"full", "view", "refer"})
_LINK_KINDS = frozenset({"related", "reply", "followup"})
_CARTABLE_FOLDERS = frozenset({"inbox", "action", "cc", "drafts", "sent", "followup", "overdue", "archive", "registry"})
_PREFIX_BY_KIND = {"internal": "internal_prefix", "incoming": "incoming_prefix", "outgoing": "outgoing_prefix"}
_BODY_FORMATS = frozenset({"markdown", "html", "plain"})
_PAPER_SIZES = frozenset({"a4", "a5", "letter"})
_PAPER_ORIENTATIONS = frozenset({"portrait", "landscape"})


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


_TIMELINE_TITLES = {
	"letter.view": "مشاهده نامه",
	"letter.draft": "پیش‌نویس",
	"letter.update_draft": "ویرایش پیش‌نویس",
	"letter.delete_draft": "حذف پیش‌نویس",
	"letter.attach": "پیوست",
	"letter.detach": "حذف پیوست",
	"letter.register": "ثبت دبیرخانه",
	"letter.refer": "ارجاع",
	"letter.reply": "پاسخ",
	"letter.link": "پیوند",
	"letter.paraph": "پاراف",
	"letter.archive": "بایگانی",
	"letter.follow_up": "پیگیری",
	"letter.sign": "امضا",
	"letter.dispatch": "ارسال",
}


def _letter_timeline(audit: Sequence[OaAuditLog], referrals: Sequence[dict], paraphs: Sequence[dict]) -> List[dict]:
	events: List[dict] = []
	for row in audit:
		events.append(
			{
				"kind": "audit",
				"action": row.action,
				"created_at": row.created_at,
				"position_id": row.position_id,
				"summary": _TIMELINE_TITLES.get(row.action, row.action),
			}
		)
	for item in referrals:
		events.append(
			{
				"kind": "referral",
				"action": f"referral.{item.get('kind') or 'action'}",
				"created_at": item.get("created_at"),
				"summary": f"{item.get('from_position_title') or ''} → {item.get('to_position_title') or ''}".strip(),
				"status": item.get("status"),
			}
		)
	for item in paraphs:
		text = str(item.get("text") or "").strip()
		events.append(
			{
				"kind": "paraph",
				"action": "paraph",
				"created_at": item.get("created_at"),
				"summary": text[:180],
			}
		)
	events.sort(key=lambda item: item.get("created_at") or datetime.min)
	return events


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
	if "background_file_id" in payload:
		row.background_file_id = payload.get("background_file_id") or None
	if "footer_text" in payload:
		row.footer_text = (str(payload.get("footer_text") or "").strip() or None)
	if payload.get("paper_size") in _PAPER_SIZES:
		row.paper_size = payload["paper_size"]
	if payload.get("paper_orientation") in _PAPER_ORIENTATIONS:
		row.paper_orientation = payload["paper_orientation"]
	for field in ("margin_top", "margin_right", "margin_bottom", "margin_left"):
		if field in payload and payload.get(field) is not None:
			setattr(row, field, max(0, min(int(payload[field]), 80)))
	if payload.get("default_body_format") in _BODY_FORMATS:
		row.default_body_format = payload["default_body_format"]
	if "default_format_id" in payload:
		fmt_id = payload.get("default_format_id")
		row.default_format_id = int(fmt_id) if fmt_id else None
		if row.default_format_id:
			fmt = db.query(OaLetterFormat).filter(
				OaLetterFormat.id == row.default_format_id, OaLetterFormat.business_id == business_id
			).first()
			if not fmt:
				raise ApiError("OA_FORMAT_NOT_FOUND", "Letter format was not found.", http_status=404)
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
		"background_file_id": row.background_file_id,
		"footer_text": row.footer_text,
		"paper_size": row.paper_size or "a4",
		"paper_orientation": row.paper_orientation or "portrait",
		"margin_top": row.margin_top if row.margin_top is not None else 20,
		"margin_right": row.margin_right if row.margin_right is not None else 20,
		"margin_bottom": row.margin_bottom if row.margin_bottom is not None else 20,
		"margin_left": row.margin_left if row.margin_left is not None else 20,
		"default_body_format": row.default_body_format or "markdown",
		"default_format_id": row.default_format_id,
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
		"secretariat_id": row.secretariat_id,
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


def list_positions(
	db: Session,
	business_id: int,
	*,
	include_inactive: bool = False,
	lang: str = "fa",
	q: Optional[str] = None,
	limit: Optional[int] = None,
) -> List[dict]:
	_ensure_plugin(db, business_id)
	query = (
		db.query(OaPosition, OaOrgUnit)
		.join(OaOrgUnit, OaOrgUnit.id == OaPosition.org_unit_id)
		.filter(OaPosition.business_id == business_id)
	)
	if not include_inactive:
		query = query.filter(OaPosition.is_active == True)  # noqa: E712
	rows = query.order_by(OaPosition.sort_order, OaPosition.id).all()
	items = [_position_dict(pos, lang, unit) for pos, unit in rows]
	_attach_position_holders(db, business_id, items)
	needle = (q or "").strip().lower()
	if needle:
		def _matches(item: dict) -> bool:
			blob = " ".join(
				str(part or "")
				for part in (
					item.get("title"),
					item.get("code"),
					item.get("org_unit_title"),
					item.get("org_unit_code"),
					item.get("holder_name"),
					" ".join(item.get("holder_names") or []),
					str(item.get("name_i18n") or ""),
				)
			).lower()
			return needle in blob

		items = [item for item in items if _matches(item)]
	if limit:
		items = items[: max(1, min(int(limit), 200))]
	return items


def _attach_position_holders(db: Session, business_id: int, items: List[dict]) -> None:
	ids = [int(item["id"]) for item in items if item.get("id")]
	if not ids:
		return
	now = _now()
	rows = (
		db.query(OaPositionHolder, User)
		.join(User, User.id == OaPositionHolder.user_id)
		.filter(OaPositionHolder.business_id == business_id, OaPositionHolder.position_id.in_(ids))
		.filter(_occupancy_filter(now))
		.order_by(OaPositionHolder.is_primary.desc(), OaPositionHolder.id)
		.all()
	)
	by_pos: Dict[int, List[str]] = {}
	for holder, user in rows:
		name = _user_display_name(user)
		if name:
			by_pos.setdefault(holder.position_id, []).append(name)
	for item in items:
		names = by_pos.get(int(item["id"]), [])
		item["holder_names"] = names
		item["holder_name"] = names[0] if names else ""


def _validate_letter_refs(db: Session, business_id: int, row: OaLetter) -> None:
	for pid in (row.sender_position_id, row.receiver_position_id):
		if pid:
			_get_position(db, business_id, int(pid))
	if row.format_id:
		fmt = db.query(OaLetterFormat).filter(
			OaLetterFormat.id == int(row.format_id), OaLetterFormat.business_id == business_id
		).first()
		if not fmt:
			raise ApiError("OA_FORMAT_NOT_FOUND", "Letter format was not found.", http_status=404)
	if row.template_id:
		tpl = db.query(OaLetterTemplate).filter(
			OaLetterTemplate.id == int(row.template_id), OaLetterTemplate.business_id == business_id
		).first()
		if not tpl:
			raise ApiError("OA_TEMPLATE_NOT_FOUND", "Letter template was not found.", http_status=404)
	if row.person_id:
		from app.services.office_automation_extended_service import validate_person_id

		validate_person_id(db, business_id, row.person_id)


def _margin(value: Any, default: int = 20) -> int:
	try:
		return max(0, min(int(value if value is not None else default), 80))
	except (TypeError, ValueError):
		return default


def _format_dict(row: OaLetterFormat) -> dict:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"name": row.name,
		"paper_size": row.paper_size or "a4",
		"paper_orientation": row.paper_orientation or "portrait",
		"margin_top": row.margin_top if row.margin_top is not None else 20,
		"margin_right": row.margin_right if row.margin_right is not None else 20,
		"margin_bottom": row.margin_bottom if row.margin_bottom is not None else 20,
		"margin_left": row.margin_left if row.margin_left is not None else 20,
		"letterhead_file_id": row.letterhead_file_id,
		"background_file_id": row.background_file_id,
		"footer_text": row.footer_text,
		"header_html": row.header_html,
		"is_default": bool(row.is_default),
		"is_active": bool(row.is_active),
		"sort_order": row.sort_order or 0,
	}


def _template_dict(row: OaLetterTemplate) -> dict:
	return {
		"id": row.id,
		"business_id": row.business_id,
		"name": row.name,
		"letter_kind": row.letter_kind,
		"subject": row.subject,
		"body": row.body,
		"body_format": row.body_format or "markdown",
		"format_id": row.format_id,
		"is_default": bool(row.is_default),
		"is_active": bool(row.is_active),
		"sort_order": row.sort_order or 0,
	}


def _clear_default_formats(db: Session, business_id: int, except_id: Optional[int] = None) -> None:
	q = db.query(OaLetterFormat).filter(OaLetterFormat.business_id == business_id, OaLetterFormat.is_default == True)  # noqa: E712
	if except_id:
		q = q.filter(OaLetterFormat.id != except_id)
	for row in q.all():
		row.is_default = False


def _clear_default_templates(db: Session, business_id: int, except_id: Optional[int] = None) -> None:
	q = db.query(OaLetterTemplate).filter(OaLetterTemplate.business_id == business_id, OaLetterTemplate.is_default == True)  # noqa: E712
	if except_id:
		q = q.filter(OaLetterTemplate.id != except_id)
	for row in q.all():
		row.is_default = False


def list_letter_formats(db: Session, business_id: int, *, include_inactive: bool = False) -> List[dict]:
	_ensure_plugin(db, business_id)
	q = db.query(OaLetterFormat).filter(OaLetterFormat.business_id == business_id)
	if not include_inactive:
		q = q.filter(OaLetterFormat.is_active == True)  # noqa: E712
	rows = q.order_by(OaLetterFormat.is_default.desc(), OaLetterFormat.sort_order, OaLetterFormat.id).all()
	return [_format_dict(r) for r in rows]


def create_letter_format(db: Session, business_id: int, payload: dict, user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "Format name is required.", http_status=400)
	row = OaLetterFormat(
		business_id=business_id,
		name=name[:120],
		paper_size=payload.get("paper_size") if payload.get("paper_size") in _PAPER_SIZES else "a4",
		paper_orientation=payload.get("paper_orientation") if payload.get("paper_orientation") in _PAPER_ORIENTATIONS else "portrait",
		margin_top=_margin(payload.get("margin_top")),
		margin_right=_margin(payload.get("margin_right")),
		margin_bottom=_margin(payload.get("margin_bottom")),
		margin_left=_margin(payload.get("margin_left")),
		letterhead_file_id=payload.get("letterhead_file_id") or None,
		background_file_id=payload.get("background_file_id") or None,
		footer_text=(str(payload.get("footer_text") or "").strip() or None),
		header_html=(str(payload.get("header_html") or "").strip() or None),
		is_default=bool(payload.get("is_default")),
		is_active=bool(payload.get("is_active", True)),
		sort_order=int(payload.get("sort_order") or 0),
		created_at=_now(),
		updated_at=_now(),
	)
	if row.is_default:
		_clear_default_formats(db, business_id)
	db.add(row)
	db.flush()
	if row.is_default:
		settings = get_or_create_settings(db, business_id)
		settings.default_format_id = row.id
	_audit(db, business_id=business_id, user_id=user_id, action="format.create", payload={"id": row.id})
	db.commit()
	db.refresh(row)
	return _format_dict(row)


def update_letter_format(db: Session, business_id: int, format_id: int, payload: dict, user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaLetterFormat).filter(OaLetterFormat.id == format_id, OaLetterFormat.business_id == business_id).first()
	if not row:
		raise ApiError("OA_FORMAT_NOT_FOUND", "Letter format was not found.", http_status=404)
	if payload.get("name"):
		row.name = str(payload["name"]).strip()[:120]
	if payload.get("paper_size") in _PAPER_SIZES:
		row.paper_size = payload["paper_size"]
	if payload.get("paper_orientation") in _PAPER_ORIENTATIONS:
		row.paper_orientation = payload["paper_orientation"]
	for field in ("margin_top", "margin_right", "margin_bottom", "margin_left"):
		if field in payload:
			setattr(row, field, _margin(payload.get(field)))
	if "letterhead_file_id" in payload:
		row.letterhead_file_id = payload.get("letterhead_file_id") or None
	if "background_file_id" in payload:
		row.background_file_id = payload.get("background_file_id") or None
	if "footer_text" in payload:
		row.footer_text = (str(payload.get("footer_text") or "").strip() or None)
	if "header_html" in payload:
		row.header_html = (str(payload.get("header_html") or "").strip() or None)
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	if "sort_order" in payload:
		row.sort_order = int(payload.get("sort_order") or 0)
	if "is_default" in payload:
		row.is_default = bool(payload["is_default"])
		if row.is_default:
			_clear_default_formats(db, business_id, except_id=row.id)
			settings = get_or_create_settings(db, business_id)
			settings.default_format_id = row.id
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="format.update", payload={"id": row.id})
	db.commit()
	db.refresh(row)
	return _format_dict(row)


def delete_letter_format(db: Session, business_id: int, format_id: int, user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaLetterFormat).filter(OaLetterFormat.id == format_id, OaLetterFormat.business_id == business_id).first()
	if not row:
		raise ApiError("OA_FORMAT_NOT_FOUND", "Letter format was not found.", http_status=404)
	db.query(OaLetter).filter(OaLetter.format_id == row.id).update({"format_id": None})
	db.query(OaLetterTemplate).filter(OaLetterTemplate.format_id == row.id).update({"format_id": None})
	settings = get_or_create_settings(db, business_id)
	if settings.default_format_id == row.id:
		settings.default_format_id = None
	db.delete(row)
	_audit(db, business_id=business_id, user_id=user_id, action="format.delete", payload={"id": format_id})
	db.commit()
	return {"id": format_id, "deleted": True}


def _refuse_shared_template(db: Session, business_id: int, *, source_letter_id: Any, subject: Optional[str], body: Optional[str]) -> None:
	if source_letter_id:
		source = db.query(OaLetter).filter(OaLetter.id == int(source_letter_id), OaLetter.business_id == business_id).first()
		if source is None:
			raise ApiError("OA_LETTER_NOT_FOUND", "Letter was not found.", http_status=404)
		if _is_classified(source.confidentiality):
			raise ApiError(
				"OA_CLASSIFIED_EXTERNAL",
				"A classified letter cannot be saved as a shared template.",
				http_status=403,
			)
	text = body if isinstance(body, str) else ""
	title = (subject or "").strip()
	if text.strip():
		copied = (
			db.query(OaLetter.id)
			.filter(
				OaLetter.business_id == business_id,
				OaLetter.confidentiality.in_(tuple(_CLASSIFIED)),
				OaLetter.body == text,
			)
			.first()
		)
		if copied is not None:
			raise ApiError(
				"OA_CLASSIFIED_EXTERNAL",
				"A classified letter cannot be saved as a shared template.",
				http_status=403,
			)
	elif title:
		copied_title = (
			db.query(OaLetter.id)
			.filter(
				OaLetter.business_id == business_id,
				OaLetter.confidentiality.in_(tuple(_CLASSIFIED)),
				OaLetter.subject == title,
				or_(OaLetter.body.is_(None), OaLetter.body == ""),
			)
			.first()
		)
		if copied_title is not None:
			raise ApiError(
				"OA_CLASSIFIED_EXTERNAL",
				"A classified letter cannot be saved as a shared template.",
				http_status=403,
			)


def list_letter_templates(db: Session, business_id: int, *, include_inactive: bool = False, letter_kind: Optional[str] = None) -> List[dict]:
	_ensure_plugin(db, business_id)
	q = db.query(OaLetterTemplate).filter(OaLetterTemplate.business_id == business_id)
	if not include_inactive:
		q = q.filter(OaLetterTemplate.is_active == True)  # noqa: E712
	if letter_kind:
		q = q.filter(or_(OaLetterTemplate.letter_kind == letter_kind, OaLetterTemplate.letter_kind.is_(None)))
	rows = q.order_by(OaLetterTemplate.is_default.desc(), OaLetterTemplate.sort_order, OaLetterTemplate.id).all()
	return [_template_dict(r) for r in rows]


def create_letter_template(db: Session, business_id: int, payload: dict, user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "Template name is required.", http_status=400)
	kind = payload.get("letter_kind")
	if kind and kind not in _LETTER_KINDS:
		raise ApiError("VALIDATION_ERROR", "Invalid letter kind.", http_status=400)
	fmt_id = int(payload["format_id"]) if payload.get("format_id") else None
	if fmt_id:
		fmt = db.query(OaLetterFormat).filter(OaLetterFormat.id == fmt_id, OaLetterFormat.business_id == business_id).first()
		if not fmt:
			raise ApiError("OA_FORMAT_NOT_FOUND", "Letter format was not found.", http_status=404)
	row = OaLetterTemplate(
		business_id=business_id,
		name=name[:120],
		letter_kind=kind or None,
		subject=(str(payload.get("subject") or "").strip()[:500] or None),
		body=payload.get("body"),
		body_format=payload.get("body_format") if payload.get("body_format") in _BODY_FORMATS else "markdown",
		format_id=fmt_id,
		is_default=bool(payload.get("is_default")),
		is_active=bool(payload.get("is_active", True)),
		sort_order=int(payload.get("sort_order") or 0),
		created_at=_now(),
		updated_at=_now(),
	)
	if row.is_default:
		_clear_default_templates(db, business_id)
	_refuse_shared_template(
		db, business_id, source_letter_id=payload.get("source_letter_id"), subject=row.subject, body=row.body,
	)
	db.add(row)
	db.flush()
	_audit(db, business_id=business_id, user_id=user_id, action="template.create", payload={"id": row.id})
	db.commit()
	db.refresh(row)
	return _template_dict(row)


def update_letter_template(db: Session, business_id: int, template_id: int, payload: dict, user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaLetterTemplate).filter(OaLetterTemplate.id == template_id, OaLetterTemplate.business_id == business_id).first()
	if not row:
		raise ApiError("OA_TEMPLATE_NOT_FOUND", "Letter template was not found.", http_status=404)
	next_subject = (str(payload.get("subject") or "").strip()[:500] or None) if "subject" in payload else row.subject
	next_body = payload.get("body") if "body" in payload else row.body
	_refuse_shared_template(
		db, business_id, source_letter_id=payload.get("source_letter_id"), subject=next_subject, body=next_body,
	)
	if payload.get("name"):
		row.name = str(payload["name"]).strip()[:120]
	if "letter_kind" in payload:
		kind = payload.get("letter_kind")
		if kind and kind not in _LETTER_KINDS:
			raise ApiError("VALIDATION_ERROR", "Invalid letter kind.", http_status=400)
		row.letter_kind = kind or None
	if "subject" in payload:
		row.subject = (str(payload.get("subject") or "").strip()[:500] or None)
	if "body" in payload:
		row.body = payload.get("body")
	if payload.get("body_format") in _BODY_FORMATS:
		row.body_format = payload["body_format"]
	if "format_id" in payload:
		fmt_id = int(payload["format_id"]) if payload.get("format_id") else None
		if fmt_id:
			fmt = db.query(OaLetterFormat).filter(OaLetterFormat.id == fmt_id, OaLetterFormat.business_id == business_id).first()
			if not fmt:
				raise ApiError("OA_FORMAT_NOT_FOUND", "Letter format was not found.", http_status=404)
		row.format_id = fmt_id
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	if "sort_order" in payload:
		row.sort_order = int(payload.get("sort_order") or 0)
	if "is_default" in payload:
		row.is_default = bool(payload["is_default"])
		if row.is_default:
			_clear_default_templates(db, business_id, except_id=row.id)
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="template.update", payload={"id": row.id})
	db.commit()
	db.refresh(row)
	return _template_dict(row)


def delete_letter_template(db: Session, business_id: int, template_id: int, user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaLetterTemplate).filter(OaLetterTemplate.id == template_id, OaLetterTemplate.business_id == business_id).first()
	if not row:
		raise ApiError("OA_TEMPLATE_NOT_FOUND", "Letter template was not found.", http_status=404)
	db.query(OaLetter).filter(OaLetter.template_id == row.id).update({"template_id": None})
	db.delete(row)
	_audit(db, business_id=business_id, user_id=user_id, action="template.delete", payload={"id": template_id})
	db.commit()
	return {"id": template_id, "deleted": True}


def search_letters(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	q: Optional[str] = None,
	limit: int = 20,
	lang: str = "fa",
	is_admin: bool = False,
) -> List[dict]:
	_ensure_plugin(db, business_id)
	query = db.query(OaLetter).filter(OaLetter.business_id == business_id, OaLetter.status != "draft")
	needle = (q or "").strip()
	if needle:
		like = f"%{needle}%"
		if needle.isdigit():
			query = query.filter(
				or_(
					OaLetter.id == int(needle),
					OaLetter.subject.ilike(like),
					OaLetter.secretariat_number.ilike(like),
				)
			)
		else:
			query = query.filter(
				or_(
					OaLetter.subject.ilike(like),
					OaLetter.secretariat_number.ilike(like),
					OaLetter.body.ilike(like),
					OaLetter.search_text.ilike(like),
					OaLetter.ocr_text.ilike(like),
					OaLetter.keywords.ilike(like),
				)
			)
	want = max(1, min(int(limit or 20), 50))
	query = query.filter(_visible_letter_clause(db, business_id, user_id, is_admin))
	rows = query.order_by(OaLetter.id.desc()).limit(want).all()
	return [
		{
			"id": row.id,
			"subject": row.subject,
			"secretariat_number": row.secretariat_number,
			"status": row.status,
			"letter_kind": row.letter_kind,
			"letter_date": row.letter_date,
		}
		for row in rows
	]


def _resolve_print_format(db: Session, business_id: int, letter: OaLetter) -> dict:
	settings = get_or_create_settings(db, business_id)
	fmt = None
	if letter.format_id:
		fmt = db.query(OaLetterFormat).filter(
			OaLetterFormat.id == letter.format_id, OaLetterFormat.business_id == business_id
		).first()
	if fmt is None and settings.default_format_id:
		fmt = db.query(OaLetterFormat).filter(
			OaLetterFormat.id == settings.default_format_id, OaLetterFormat.business_id == business_id
		).first()
	if fmt is None:
		fmt = (
			db.query(OaLetterFormat)
			.filter(OaLetterFormat.business_id == business_id, OaLetterFormat.is_default == True)  # noqa: E712
			.first()
		)
	if fmt is not None:
		data = _format_dict(fmt)
	else:
		data = {
			"id": None,
			"name": "",
			"paper_size": settings.paper_size or "a4",
			"paper_orientation": settings.paper_orientation or "portrait",
			"margin_top": settings.margin_top if settings.margin_top is not None else 20,
			"margin_right": settings.margin_right if settings.margin_right is not None else 20,
			"margin_bottom": settings.margin_bottom if settings.margin_bottom is not None else 20,
			"margin_left": settings.margin_left if settings.margin_left is not None else 20,
			"letterhead_file_id": settings.letterhead_file_id,
			"background_file_id": settings.background_file_id,
			"footer_text": settings.footer_text,
			"header_html": None,
		}
	if not data.get("letterhead_file_id"):
		data["letterhead_file_id"] = settings.letterhead_file_id
	if not data.get("background_file_id"):
		data["background_file_id"] = settings.background_file_id
	if not data.get("footer_text"):
		data["footer_text"] = settings.footer_text
	return data


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
		secretariat_id=int(payload["secretariat_id"]) if payload.get("secretariat_id") else None,
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
	if "secretariat_id" in payload:
		row.secretariat_id = int(payload["secretariat_id"]) if payload.get("secretariat_id") else None
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


def _allocate_number(
	db: Session,
	settings: OaSettings,
	kind: str,
	letter_date: date,
	secretariat: Optional[OaSecretariat] = None,
) -> Tuple[str, int, int]:
	year = _numbering_year(letter_date, settings.numbering_calendar)
	sec_id = int(secretariat.id) if secretariat is not None else 0
	counter = (
		db.query(OaLetterNumberCounter)
		.filter(
			OaLetterNumberCounter.business_id == settings.business_id,
			OaLetterNumberCounter.letter_kind == kind,
			OaLetterNumberCounter.year == year,
			OaLetterNumberCounter.secretariat_id == sec_id,
		)
		.with_for_update()
		.first()
	)
	if not counter:
		counter = OaLetterNumberCounter(
			business_id=settings.business_id,
			letter_kind=kind,
			year=year,
			secretariat_id=sec_id,
			last_seq=0,
		)
		db.add(counter)
		db.flush()
	counter.last_seq += 1
	if secretariat is not None:
		prefix = getattr(secretariat, _PREFIX_BY_KIND[kind], None) or getattr(settings, _PREFIX_BY_KIND[kind])
	else:
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
		"body_format": row.body_format or "markdown",
		"locale": row.locale,
		"letter_date": row.letter_date,
		"urgency": row.urgency,
		"confidentiality": row.confidentiality,
		"sender_name": row.sender_name,
		"sender_org": row.sender_org,
		"receiver_name": row.receiver_name,
		"receiver_org": row.receiver_org,
		"sender_position_id": row.sender_position_id,
		"receiver_position_id": row.receiver_position_id,
		"format_id": row.format_id,
		"template_id": row.template_id,
		"origin_position_id": row.origin_position_id,
		"created_by_user_id": row.created_by_user_id,
		"registered_at": row.registered_at,
		"secretariat_number": row.secretariat_number,
		"secretariat_year": row.secretariat_year,
		"secretariat_seq": row.secretariat_seq,
		"follow_up_at": row.follow_up_at,
		"person_id": row.person_id,
		"secretariat_id": row.secretariat_id,
		"external_org_id": row.external_org_id,
		"archive_folder_id": row.archive_folder_id,
		"tracking_token": row.tracking_token,
		"receipt_number": row.receipt_number,
		"receipt_date": row.receipt_date,
		"sign_status": getattr(row, "sign_status", None) or "none",
		"branch_id": getattr(row, "branch_id", None),
		"retain_until": getattr(row, "retain_until", None),
		"retention_status": getattr(row, "retention_status", None) or "none",
		"qualified_sign_status": getattr(row, "qualified_sign_status", None) or "none",
		"keywords": getattr(row, "keywords", None),
		"ai_summary": getattr(row, "ai_summary", None),
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


_CONFIDENTIALITY_RANK = {"normal": 0, "confidential": 1, "highly_confidential": 2, "secret": 3}


def _is_classified(value: Optional[str]) -> bool:
	return (value or "normal") in _CLASSIFIED


def _refuse_lower_confidentiality(current: Optional[str], requested: Any) -> None:
	"""ثبت نامه سطح محرمانگی پیش‌نویس را پایین نمی‌آورد. کاهش سطح فقط با ویرایش پیش‌نویس است."""
	if requested not in _CONFIDENTIALITY_RANK:
		return
	if _CONFIDENTIALITY_RANK[str(requested)] < _CONFIDENTIALITY_RANK.get(current or "normal", 0):
		raise ApiError(
			"OA_CLASSIFIED_EXTERNAL",
			"Registration cannot make a letter less confidential.",
			http_status=403,
		)


def letter_notification(letter: OaLetter, business_name: str) -> tuple[dict, List[str]]:
	outside = not _is_classified(letter.confidentiality)
	return (
		{
			"subject": letter.subject if outside else "",
			"number": (letter.secretariat_number or "") if outside else "",
			"letter_id": letter.id,
			"business_name": business_name,
		},
		["inapp", "sms", "email"] if outside else ["inapp"],
	)


_MODEL_TEXT = frozenset({
	"subject",
	"body",
	"title",
	"text",
	"note",
	"summary",
	"instruction",
	"completion_note",
	"keywords",
	"ocr_text",
	"ai_summary",
	"search_text",
	"extracted_text",
	"suggested_value",
	"sender_name",
	"sender_org",
	"receiver_name",
	"receiver_org",
	"header_html",
	"footer_text",
	"xml",
	"xml_content",
	"original_name",
	"related_subject",
})


def withhold_classified_text(value: Any, *, classified: bool = False) -> Any:
	if isinstance(value, list):
		return [withhold_classified_text(item, classified=classified) for item in value]
	if not isinstance(value, dict):
		return value
	own = _is_classified(value.get("confidentiality"))
	active = classified or own
	out: Dict[str, Any] = {}
	for key, item in value.items():
		if key == "tracking_token":
			continue
		if active and key in _MODEL_TEXT and not isinstance(item, (dict, list)):
			out[key] = "" if item is not None else None
			continue
		out[key] = withhold_classified_text(item, classified=active)
	if own:
		out["text_withheld"] = True
	return out


def refuse_external_letter(letter: OaLetter) -> None:
	if _is_classified(letter.confidentiality):
		raise ApiError(
			"OA_CLASSIFIED_EXTERNAL",
			"Classified letters stay inside the organization and are not emailed, exported, or sent to the assistant.",
			http_status=403,
		)


def business_display_name(db: Session, business_id: int) -> str:
	try:
		return db.query(Business.name).filter(Business.id == business_id).scalar() or ""
	except Exception:
		db.rollback()
		logger.debug("OA business name skipped", exc_info=True)
		return ""


def _secretariat_row(db: Session, business_id: int, secretariat_id: Optional[int]) -> Optional[OaSecretariat]:
	if not secretariat_id:
		return None
	return (
		db.query(OaSecretariat)
		.filter(OaSecretariat.id == int(secretariat_id), OaSecretariat.business_id == business_id)
		.first()
	)


def _secretariat_grants_view(db: Session, position: OaPosition, letter: OaLetter) -> bool:
	"""دبیرخانه فقط دفتر خودش را می‌بیند؛ نامه طبقه‌بندی‌شده فقط از دبیرخانه محرمانه همان نامه."""
	if not position.is_secretariat or letter.status == "draft":
		return False
	sec = _secretariat_row(db, letter.business_id, letter.secretariat_id)
	classified = _is_classified(letter.confidentiality)
	if classified:
		return bool(sec and sec.is_confidential and position.secretariat_id == sec.id)
	if sec is not None and sec.is_confidential:
		return position.secretariat_id == sec.id
	if position.secretariat_id:
		return letter.secretariat_id in {None, position.secretariat_id}
	return True


def _apply_registry_scope(db: Session, query, business_id: int, position: OaPosition):
	query = query.filter(OaLetter.status != "draft")
	if position.secretariat_id:
		sec = _secretariat_row(db, business_id, position.secretariat_id)
		query = query.filter(OaLetter.secretariat_id == position.secretariat_id)
		if not sec or not sec.is_confidential:
			query = query.filter(OaLetter.confidentiality.notin_(tuple(_CLASSIFIED)))
		return query
	confidential_ids = [
		row[0]
		for row in db.query(OaSecretariat.id)
		.filter(OaSecretariat.business_id == business_id, OaSecretariat.is_confidential == True)  # noqa: E712
		.all()
	]
	query = query.filter(OaLetter.confidentiality.notin_(tuple(_CLASSIFIED)))
	if confidential_ids:
		query = query.filter(or_(OaLetter.secretariat_id.is_(None), ~OaLetter.secretariat_id.in_(confidential_ids)))
	return query


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
	on_sign_path = (
		db.query(OaLetterSignStep.id)
		.filter(OaLetterSignStep.letter_id == letter.id, OaLetterSignStep.position_id.in_(position_ids))
		.first()
	)
	if on_sign_path:
		return True
	positions = db.query(OaPosition).filter(OaPosition.id.in_(position_ids)).all()
	if any(_secretariat_grants_view(db, position, letter) for position in positions):
		return True
	if _is_classified(letter.confidentiality):
		return False
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


def _can_register_draft(db: Session, letter: OaLetter, position: OaPosition, is_admin: bool) -> bool:
	"""دبیرخانه نامه عادی دیگران را شماره می‌کند. پیش‌نویس طبقه‌بندی‌شده فقط برای مبدأ یا دبیرخانه محرمانه است."""
	if is_admin or letter.origin_position_id == position.id:
		return True
	if not position.is_secretariat:
		return False
	if not _is_classified(letter.confidentiality):
		return True
	sec = _secretariat_row(db, letter.business_id, position.secretariat_id)
	return bool(sec and sec.is_confidential)


def _require_letter_view(db: Session, letter: OaLetter, user_id: int, is_admin: bool = False) -> None:
	if not _can_view_letter(db, letter, user_id, is_admin):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot view this letter.", http_status=403)


def _visible_letter_clause(db: Session, business_id: int, user_id: int, is_admin: bool):
	"""همان قاعده _can_view_letter، تا limit جست‌وجو بعد از مشاهده اعمال شود."""
	if is_admin:
		return OaLetter.id.isnot(None)
	position_ids = _user_position_ids(db, business_id, user_id)
	if not position_ids:
		return false()
	positions = db.query(OaPosition).filter(OaPosition.id.in_(position_ids)).all()
	classified = OaLetter.confidentiality.in_(tuple(_CLASSIFIED))
	clauses = [
		OaLetter.origin_position_id.in_(position_ids),
		OaLetter.id.in_(
			db.query(OaReferral.letter_id).filter(
				OaReferral.business_id == business_id,
				or_(OaReferral.from_position_id.in_(position_ids), OaReferral.to_position_id.in_(position_ids)),
			)
		),
		OaLetter.id.in_(
			db.query(OaLetterSignStep.letter_id).filter(OaLetterSignStep.position_id.in_(position_ids))
		),
	]
	non_confidential = [
		row[0]
		for row in db.query(OaSecretariat.id)
		.filter(OaSecretariat.business_id == business_id, OaSecretariat.is_confidential.is_(False))
		.all()
	]
	for position in positions:
		if position.is_secretariat:
			if position.secretariat_id:
				sec = _secretariat_row(db, business_id, position.secretariat_id)
				if sec is not None and sec.is_confidential:
					clauses.append(OaLetter.secretariat_id == position.secretariat_id)
				else:
					clauses.append(
						and_(
							~classified,
							or_(OaLetter.secretariat_id.is_(None), OaLetter.secretariat_id == position.secretariat_id),
						)
					)
			else:
				clauses.append(
					and_(
						~classified,
						or_(OaLetter.secretariat_id.is_(None), OaLetter.secretariat_id.in_(non_confidential or [-1])),
					)
				)
		if position.can_view_subtree:
			unit_ids = _descendant_unit_ids(db, business_id, position.org_unit_id) | {position.org_unit_id}
			related = [
				row[0]
				for row in db.query(OaPosition.id).filter(OaPosition.org_unit_id.in_(unit_ids or {0})).all()
			]
			if related:
				clauses.append(
					and_(
						~classified,
						or_(
							OaLetter.origin_position_id.in_(related),
							OaLetter.id.in_(
								db.query(OaReferral.letter_id).filter(
									OaReferral.business_id == business_id,
									or_(
										OaReferral.from_position_id.in_(related),
										OaReferral.to_position_id.in_(related),
									),
								)
							),
						),
					)
				)
	return or_(*clauses)


def _apply_letter_payload(row: OaLetter, payload: dict, calendar_type: CalendarType) -> None:
	if payload.get("subject"):
		row.subject = str(payload["subject"]).strip()[:500]
	if "body" in payload:
		row.body = payload.get("body")
	if payload.get("body_format") in _BODY_FORMATS:
		row.body_format = payload["body_format"]
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
	if "sender_position_id" in payload:
		row.sender_position_id = int(payload["sender_position_id"]) if payload.get("sender_position_id") else None
	if "receiver_position_id" in payload:
		row.receiver_position_id = int(payload["receiver_position_id"]) if payload.get("receiver_position_id") else None
	if "format_id" in payload:
		row.format_id = int(payload["format_id"]) if payload.get("format_id") else None
	if "template_id" in payload:
		row.template_id = int(payload["template_id"]) if payload.get("template_id") else None
	if "letter_date" in payload and payload.get("letter_date"):
		row.letter_date = _parse_date(payload["letter_date"], calendar_type) or row.letter_date
	if "follow_up_at" in payload:
		row.follow_up_at = _parse_date(payload.get("follow_up_at"), calendar_type)
	if "secretariat_id" in payload:
		row.secretariat_id = int(payload["secretariat_id"]) if payload.get("secretariat_id") else None
	if "external_org_id" in payload:
		row.external_org_id = int(payload["external_org_id"]) if payload.get("external_org_id") else None
	if "keywords" in payload:
		row.keywords = (str(payload.get("keywords") or "").strip()[:500] or None)
	if "receipt_number" in payload:
		row.receipt_number = (str(payload.get("receipt_number") or "").strip()[:64] or None)
	if "receipt_date" in payload:
		row.receipt_date = _parse_date(payload.get("receipt_date"), calendar_type)


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
		body_format=payload.get("body_format") if payload.get("body_format") in _BODY_FORMATS else "markdown",
		locale=payload.get("locale") if payload.get("locale") in {"fa", "en"} else "fa",
		letter_date=letter_date,
		urgency=payload.get("urgency") if payload.get("urgency") in _URGENCY else "normal",
		confidentiality=payload.get("confidentiality") if payload.get("confidentiality") in _CONFIDENTIALITY else "normal",
		sender_name=payload.get("sender_name"),
		sender_org=payload.get("sender_org"),
		receiver_name=payload.get("receiver_name"),
		receiver_org=payload.get("receiver_org"),
		sender_position_id=int(payload["sender_position_id"]) if payload.get("sender_position_id") else None,
		receiver_position_id=int(payload["receiver_position_id"]) if payload.get("receiver_position_id") else None,
		format_id=int(payload["format_id"]) if payload.get("format_id") else None,
		template_id=int(payload["template_id"]) if payload.get("template_id") else None,
		origin_position_id=position.id,
		created_by_user_id=user_id,
		person_id=int(payload["person_id"]) if payload.get("person_id") else None,
		secretariat_id=int(payload["secretariat_id"]) if payload.get("secretariat_id") else None,
		external_org_id=int(payload["external_org_id"]) if payload.get("external_org_id") else None,
		keywords=(str(payload.get("keywords") or "").strip()[:500] or None),
		receipt_number=(str(payload.get("receipt_number") or "").strip()[:64] or None),
		receipt_date=_parse_date(payload.get("receipt_date"), calendar_type),
		follow_up_at=_parse_date(payload.get("follow_up_at"), calendar_type),
		created_at=_now(),
		updated_at=_now(),
	)
	_validate_letter_refs(db, business_id, row)
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
	_validate_letter_refs(db, business_id, row)
	from app.services.office_automation_extended_service import refresh_letter_search_text, snapshot_letter_version

	snapshot_letter_version(db, row, user_id)
	refresh_letter_search_text(db, row)
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
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = _get_letter(db, business_id, letter_id)
	if not _can_register_draft(db, row, position, is_admin):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot register a letter you cannot open.", http_status=403)
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
	from app.services.office_automation_extended_service import (
		ensure_tracking_token,
		refresh_letter_search_text,
		required_signs_complete,
		resolve_letter_secretariat,
		snapshot_letter_version,
	)

	if kind == "outgoing" and not required_signs_complete(db, row):
		raise ApiError(
			"OA_SIGNATURE_REQUIRED",
			"Required signature steps must be completed before registering an outgoing letter.",
			http_status=400,
		)
	_refuse_lower_confidentiality(row.confidentiality, payload.get("confidentiality"))
	_apply_letter_payload(row, payload, calendar_type)
	row.letter_kind = kind
	secretariat = resolve_letter_secretariat(db, business_id, position, payload, confidentiality=row.confidentiality)
	row.secretariat_id = secretariat.id
	number, year, seq = _allocate_number(db, settings, kind, row.letter_date, secretariat)
	row.secretariat_number = number
	row.secretariat_year = year
	row.secretariat_seq = seq
	ensure_tracking_token(row)
	snapshot_letter_version(db, row, user_id)
	refresh_letter_search_text(db, row)
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
		from app.services.office_automation_extended_service import apply_cartable_rules

		for ref in created_referrals:
			apply_cartable_rules(db, business_id, row, ref)
	from app.services.oa_enterprise_service import apply_letter_scope

	apply_letter_scope(db, row)
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
	from app.services.office_automation_extended_service import fire_oa_workflow

	fire_oa_workflow(db, business_id, "office_automation.letter_registered", row, user_id)
	if created_referrals:
		fire_oa_workflow(db, business_id, "office_automation.letter_referred", row, user_id, extra={"referral_count": len(created_referrals)})
	return get_letter(db, business_id, row.id, user_id, position_id, lang=lang, is_admin=is_admin)


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
					context, channels = letter_notification(letter, business_display_name(db, business_id))
					svc.send(
						user_id=int(uid),
						event_key=(
							"office_automation.letter_returned"
							if referral.kind == "return"
							else "office_automation.letter_referred"
						),
						context=context,
						preferred_channels=channels,
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
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	row = _get_letter(db, business_id, letter_id)
	_require_letter_view(db, row, user_id, is_admin)
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
	from app.services.office_automation_extended_service import apply_cartable_rules

	for ref in created:
		apply_cartable_rules(db, business_id, row, ref)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.refer", letter_id=row.id, position_id=position.id)
	db.commit()
	_notify_referral_recipients(db, business_id, created, row)
	from app.services.office_automation_extended_service import fire_oa_workflow

	fire_oa_workflow(db, business_id, "office_automation.letter_referred", row, user_id, extra={"referral_count": len(created)})
	return get_letter(db, business_id, row.id, user_id, position_id, lang=lang, is_admin=is_admin)


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
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=False)


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
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=False)


def add_paraph(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	letter = _get_letter(db, business_id, letter_id)
	_require_letter_view(db, letter, user_id, is_admin)
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
		"confidentiality": letter.confidentiality,
		"created_at": row.created_at,
	}


def add_attachment(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	letter = _get_letter(db, business_id, letter_id)
	_require_letter_view(db, letter, user_id, is_admin)
	_require_letter_open(letter, allow_draft=True)
	file_id = str(payload.get("file_storage_id") or "").strip()
	if not file_id:
		raise ApiError("VALIDATION_ERROR", "file_storage_id is required.", http_status=400)
	storage = db.query(FileStorage).filter(FileStorage.id == file_id).first()
	if not storage or (storage.business_id not in (None, business_id)):
		raise ApiError("FILE_NOT_FOUND", "Attachment file was not found.", http_status=404)
	from app.services.oa_document_service import assert_file_stays_on_letter

	assert_file_stays_on_letter(db, business_id, user_id, file_id, letter, is_admin=is_admin)
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
	db.flush()
	from adapters.db.models.oa_document import OaOcrJob
	from app.services.office_automation_extended_service import refresh_letter_search_text

	db.add(
		OaOcrJob(
			business_id=business_id,
			document_version_id=None,
			letter_attachment_id=row.id,
			status="queued",
			created_at=_now(),
		)
	)
	refresh_letter_search_text(db, letter)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.attach", letter_id=letter.id, position_id=position.id)
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"letter_id": row.letter_id,
		"file_storage_id": row.file_storage_id,
		"title": row.title,
		"ocr_text": row.ocr_text,
		"original_name": storage.original_name,
		"confidentiality": letter.confidentiality,
		"mime_type": storage.mime_type,
		"file_size": storage.file_size,
		"created_at": row.created_at,
	}


def remove_attachment(db: Session, business_id: int, attachment_id: int, user_id: int, position_id: int, is_admin: bool = False) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = db.query(OaLetterAttachment).filter(
		OaLetterAttachment.id == attachment_id, OaLetterAttachment.business_id == business_id
	).first()
	if not row:
		raise ApiError("OA_ATTACHMENT_NOT_FOUND", "Attachment was not found.", http_status=404)
	letter = _get_letter(db, business_id, row.letter_id)
	_require_letter_view(db, letter, user_id, is_admin)
	_require_letter_open(letter, allow_draft=True)
	letter_id = row.letter_id
	db.delete(row)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.detach", letter_id=letter_id, position_id=position.id)
	db.commit()
	return {"id": attachment_id, "deleted": True}


def archive_letter(db: Session, business_id: int, letter_id: int, user_id: int, position_id: int, lang: str = "fa", is_admin: bool = False) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = _get_letter(db, business_id, letter_id)
	_require_letter_view(db, row, user_id, is_admin)
	if row.status == "draft":
		raise ApiError("OA_LETTER_STILL_DRAFT", "Draft letters cannot be archived.", http_status=400)
	if row.status == "archived":
		raise ApiError("OA_LETTER_ARCHIVED", "Letter is already archived.", http_status=400)
	row.status = "archived"
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.archive", letter_id=row.id, position_id=position.id)
	db.commit()
	from app.services.office_automation_extended_service import fire_oa_workflow

	fire_oa_workflow(db, business_id, "office_automation.letter_archived", row, user_id)
	return get_letter(db, business_id, row.id, user_id, position_id, lang=lang, is_admin=is_admin)


def set_follow_up(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	row = _get_letter(db, business_id, letter_id)
	_require_letter_view(db, row, user_id, is_admin)
	_require_letter_open(row)
	row.follow_up_at = _parse_date(payload.get("follow_up_at"), calendar_type)
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.follow_up", letter_id=row.id, position_id=position.id)
	db.commit()
	return get_letter(db, business_id, row.id, user_id, position_id, lang=lang, is_admin=is_admin)


def link_letters(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	letter = _get_letter(db, business_id, letter_id)
	_require_letter_open(letter)
	related_id = int(payload.get("related_letter_id") or 0)
	if related_id == letter.id:
		raise ApiError("VALIDATION_ERROR", "A letter cannot be linked to itself.", http_status=400)
	related = _get_letter(db, business_id, related_id)
	if not _can_view_letter(db, letter, user_id, is_admin) or not _can_view_letter(db, related, user_id, is_admin):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot link a letter you cannot view.", http_status=403)
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


def reply_to_letter(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
	is_admin: bool = False,
) -> dict:
	"""پیش‌نویس پاسخ می‌سازد و آن را از هر دو سو به نامه مبدأ پیوند می‌دهد."""
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	source = _get_letter(db, business_id, letter_id)
	if source.status == "draft":
		raise ApiError("OA_LETTER_STILL_DRAFT", "Register the letter before replying.", http_status=400)
	if not _can_view_letter(db, source, user_id, is_admin):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot reply to this letter.", http_status=403)
	subject = str(payload.get("subject") or "").strip()
	if not subject:
		subject = f"پاسخ: {source.subject}"
	draft = create_letter_draft(
		db,
		business_id,
		{
			"subject": subject[:500],
			"body": payload.get("body") or "",
			"body_format": payload.get("body_format") or source.body_format,
			"letter_kind": payload.get("letter_kind") or "internal",
			"letter_date": payload.get("letter_date"),
			"urgency": payload.get("urgency") or source.urgency,
			"confidentiality": source.confidentiality,
			"person_id": source.person_id,
			"external_org_id": source.external_org_id,
			"keywords": source.keywords,
		},
		user_id,
		position.id,
		lang=lang,
		calendar_type=calendar_type,
	)
	now = _now()
	for origin_id, related_id in ((source.id, int(draft["id"])), (int(draft["id"]), source.id)):
		db.add(
			OaLetterLink(
				business_id=business_id,
				letter_id=origin_id,
				related_letter_id=related_id,
				link_kind="reply",
				created_by_user_id=user_id,
				created_at=now,
			)
		)
	_audit(
		db,
		business_id=business_id,
		user_id=user_id,
		action="letter.reply",
		letter_id=source.id,
		position_id=position.id,
		payload={"reply_id": int(draft["id"])},
	)
	db.commit()
	return get_letter(db, business_id, int(draft["id"]), user_id, position.id, lang=lang, is_admin=is_admin)


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
	_audit(
		db,
		business_id=business_id,
		user_id=user_id,
		action="letter.view",
		letter_id=row.id,
		position_id=position_id,
		payload={"confidentiality": row.confidentiality},
	)
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
	reverse_links = (
		db.query(OaLetterLink, OaLetter)
		.join(OaLetter, OaLetter.id == OaLetterLink.letter_id)
		.filter(OaLetterLink.related_letter_id == row.id)
		.all()
	)
	audit = (
		db.query(OaAuditLog)
		.filter(OaAuditLog.letter_id == row.id)
		.order_by(OaAuditLog.created_at)
		.all()
	)
	data = _letter_dict(row, lang, origin=origin)
	party_ids = {pid for pid in (row.sender_position_id, row.receiver_position_id) if pid}
	if party_ids:
		party_rows = (
			db.query(OaPosition, OaOrgUnit)
			.join(OaOrgUnit, OaOrgUnit.id == OaPosition.org_unit_id)
			.filter(OaPosition.id.in_(party_ids))
			.all()
		)
		by_id = {p.id: (p, u) for p, u in party_rows}
		if row.sender_position_id in by_id:
			pos, unit = by_id[row.sender_position_id]
			data["sender_position_title"] = resolve_i18n(pos.name_i18n, lang)
			data["sender_unit_title"] = resolve_i18n(unit.name_i18n, lang)
		if row.receiver_position_id in by_id:
			pos, unit = by_id[row.receiver_position_id]
			data["receiver_position_title"] = resolve_i18n(pos.name_i18n, lang)
			data["receiver_unit_title"] = resolve_i18n(unit.name_i18n, lang)
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
	def _visible_link(lnk: OaLetterLink, other: OaLetter, direction: str) -> Optional[dict]:
		if not _can_view_letter(db, other, user_id, is_admin):
			return None
		return {
			"id": lnk.id,
			"link_kind": lnk.link_kind,
			"related_letter_id": other.id,
			"related_subject": other.subject,
			"related_number": other.secretariat_number,
			"confidentiality": other.confidentiality,
			"direction": direction,
		}

	data["links"] = [
		item
		for item in (
			[_visible_link(lnk, related, "out") for lnk, related in links]
			+ [_visible_link(lnk, other, "in") for lnk, other in reverse_links]
		)
		if item is not None
	]
	data["timeline"] = _letter_timeline(audit, data["referrals"], data["paraphs"])
	from app.services.office_automation_extended_service import enrich_letter_payload

	return enrich_letter_payload(db, data, row, lang)


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
	letter = _get_letter(db, business_id, letter_id)
	fmt = _resolve_print_format(db, business_id, letter)
	data["format"] = fmt
	data["print"] = {
		"letterhead_file_id": fmt.get("letterhead_file_id") or settings.get("letterhead_file_id"),
		"background_file_id": fmt.get("background_file_id") or settings.get("background_file_id"),
		"footer_text": fmt.get("footer_text") or settings.get("footer_text"),
		"header_html": fmt.get("header_html"),
		"paper_size": fmt.get("paper_size") or "a4",
		"paper_orientation": fmt.get("paper_orientation") or "portrait",
		"margin_top": fmt.get("margin_top", 20),
		"margin_right": fmt.get("margin_right", 20),
		"margin_bottom": fmt.get("margin_bottom", 20),
		"margin_left": fmt.get("margin_left", 20),
		"numbering_calendar": settings.get("numbering_calendar"),
		"incoming_prefix": settings.get("incoming_prefix"),
		"outgoing_prefix": settings.get("outgoing_prefix"),
		"internal_prefix": settings.get("internal_prefix"),
		"body_format": data.get("body_format") or "markdown",
		"copies_label": "رونوشت" if str(lang).startswith("fa") else "Copies",
		"copies": [
			r.get("to_position_title")
			for r in (data.get("referrals") or [])
			if r.get("kind") == "info" and r.get("to_position_title")
		],
		"signatures": [
			{
				"title": s.get("position_title"),
				"image_file_id": s.get("image_file_id"),
				"note": s.get("note"),
				"signed_at": s.get("signed_at"),
			}
			for s in (data.get("sign_steps") or [])
			if s.get("status") == "signed"
		],
	}
	return data


def _list_letter(row: OaLetter, lang: str, *, origin: Optional[OaPosition] = None) -> dict:
	data = _letter_dict(row, lang, origin=origin)
	for secret in ("body", "ocr_text", "ai_summary"):
		data.pop(secret, None)
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
			filters = [
				OaLetter.subject.ilike(like),
				OaLetter.secretariat_number.ilike(like),
				OaLetter.search_text.ilike(like),
				OaLetter.keywords.ilike(like),
			]
			if include_body:
				filters.extend([OaLetter.body.ilike(like), OaLetter.ocr_text.ilike(like)])
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
		items = [_list_letter(r, lang, origin=position) for r in rows]
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
			data = _list_letter(letter, lang, origin=position)
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
		items = [_list_letter(r, lang, origin=position) for r in rows]
	elif folder == "overdue":
		today = date.today()
		query = (
			db.query(OaReferral, OaLetter)
			.join(OaLetter, OaLetter.id == OaReferral.letter_id)
			.filter(
				OaReferral.business_id == business_id,
				OaReferral.to_position_id == position.id,
				OaReferral.status.in_(("pending", "seen")),
				OaReferral.due_at.isnot(None),
				OaReferral.due_at < today,
			)
		)
		query = _apply_search(query, include_body=False)
		total = query.count()
		rows = query.order_by(OaReferral.due_at).offset(skip).limit(limit).all()
		for ref, letter in rows:
			data = _list_letter(letter, lang)
			data["referral_id"] = ref.id
			data["referral_kind"] = ref.kind
			data["referral_status"] = ref.status
			data["referral_priority"] = ref.priority
			data["due_at"] = ref.due_at
			data["instruction"] = ref.instruction
			items.append(data)
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
		items = [_list_letter(r, lang, origin=position) for r in rows]
	elif folder == "registry":
		if not position.is_secretariat:
			raise ApiError("OA_SECRETARIAT_REQUIRED", "Registry search requires a secretariat position.", http_status=403)
		query = _apply_registry_scope(
			db,
			db.query(OaLetter).filter(OaLetter.business_id == business_id),
			business_id,
			position,
		)
		query = _apply_search(query)
		total = query.count()
		rows = query.order_by(desc(OaLetter.registered_at), desc(OaLetter.updated_at)).offset(skip).limit(limit).all()
		items = [_list_letter(r, lang, origin=position) for r in rows]
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
			data = _list_letter(letter, lang)
			data["referral_id"] = ref.id
			data["referral_kind"] = ref.kind
			data["referral_status"] = ref.status
			data["referral_priority"] = ref.priority
			data["due_at"] = ref.due_at
			data["instruction"] = ref.instruction
			items.append(data)
	return {"items": items, "total": total, "folder": folder, "position_id": position.id}


_BOARD_COLUMNS = ("pending", "seen", "done", "returned")


def list_cartable_board(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	*,
	q: Optional[str] = None,
	limit: int = 40,
	lang: str = "fa",
) -> dict:
	"""ستون‌های کار سمت فعال. جابه‌جایی کارت فقط با complete/return روی سرور است."""
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="view")
	limit = max(1, min(int(limit or 40), 80))
	columns: Dict[str, dict] = {}
	for status in _BOARD_COLUMNS:
		query = (
			db.query(OaReferral, OaLetter)
			.join(OaLetter, OaLetter.id == OaReferral.letter_id)
			.filter(
				OaReferral.business_id == business_id,
				OaReferral.to_position_id == position.id,
				OaReferral.status == status,
			)
		)
		if q and q.strip():
			like = f"%{q.strip()}%"
			query = query.filter(
				or_(
					OaLetter.subject.ilike(like),
					OaLetter.secretariat_number.ilike(like),
					OaLetter.search_text.ilike(like),
					OaLetter.keywords.ilike(like),
				)
			)
		total = query.count()
		order = desc(OaReferral.completed_at) if status in {"done", "returned"} else desc(OaReferral.created_at)
		rows = query.order_by(order).limit(limit).all()
		items: List[dict] = []
		for ref, letter in rows:
			data = _list_letter(letter, lang)
			data["referral_id"] = ref.id
			data["referral_kind"] = ref.kind
			data["referral_status"] = ref.status
			data["referral_priority"] = ref.priority
			data["due_at"] = ref.due_at
			data["instruction"] = ref.instruction
			items.append(data)
		columns[status] = {"items": items, "total": int(total)}
	return {"position_id": position.id, "columns": columns}


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
	overdue = db.query(func.count(OaReferral.id)).filter(
		OaReferral.business_id == business_id,
		OaReferral.to_position_id == pid,
		OaReferral.status.in_(pending),
		OaReferral.due_at.isnot(None),
		OaReferral.due_at < date.today(),
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
		"overdue": int(overdue),
		"archive": int(archive),
		"registry": 0,
	}
	if position.is_secretariat:
		counts["registry"] = int(
			_apply_registry_scope(
				db,
				db.query(func.count(OaLetter.id)).filter(OaLetter.business_id == business_id),
				business_id,
				position,
			).scalar()
			or 0
		)
	return counts


def get_dashboard(db: Session, business_id: int, user_id: int, position_id: Optional[int], lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	my_positions = list_my_positions(db, business_id, user_id, lang=lang)
	counts = {"inbox": 0, "action": 0, "cc": 0, "drafts": 0, "sent": 0, "followup": 0, "overdue": 0, "archive": 0, "registry": 0}
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


def _desk_letter(letter: OaLetter, *, referral: Optional[OaReferral] = None) -> dict:
	data = {
		"letter_id": letter.id,
		"subject": letter.subject,
		"number": letter.secretariat_number,
		"confidentiality": letter.confidentiality,
		"urgency": letter.urgency,
		"status": letter.status,
		"follow_up_at": letter.follow_up_at,
	}
	if referral is not None:
		data["referral_id"] = referral.id
		data["due_at"] = referral.due_at
		data["referral_status"] = referral.status
	return data


def get_personal_desk(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	*,
	lang: str = "fa",
	horizon_days: int = 7,
) -> dict:
	"""کار همین سمت: شمارنده‌ها و سررسیدها، بدون نامه سمت‌های دیگر و بدون متن بدنه."""
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="view")
	today = date.today()
	horizon = today + timedelta(days=max(1, min(int(horizon_days or 7), 30)))
	open_status = ("pending", "seen")
	overdue_rows = (
		db.query(OaReferral, OaLetter)
		.join(OaLetter, OaLetter.id == OaReferral.letter_id)
		.filter(
			OaReferral.business_id == business_id,
			OaReferral.to_position_id == position.id,
			OaReferral.status.in_(open_status),
			OaReferral.due_at.isnot(None),
			OaReferral.due_at < today,
		)
		.order_by(OaReferral.due_at)
		.limit(8)
		.all()
	)
	soon_rows = (
		db.query(OaReferral, OaLetter)
		.join(OaLetter, OaLetter.id == OaReferral.letter_id)
		.filter(
			OaReferral.business_id == business_id,
			OaReferral.to_position_id == position.id,
			OaReferral.status.in_(open_status),
			OaReferral.due_at.isnot(None),
			OaReferral.due_at >= today,
			OaReferral.due_at <= horizon,
		)
		.order_by(OaReferral.due_at)
		.limit(8)
		.all()
	)
	follow_rows = (
		db.query(OaLetter)
		.filter(
			OaLetter.business_id == business_id,
			OaLetter.follow_up_at.isnot(None),
			OaLetter.follow_up_at <= horizon,
			OaLetter.status.notin_(("draft", "archived")),
			or_(
				OaLetter.origin_position_id == position.id,
				OaLetter.id.in_(
					db.query(OaReferral.letter_id).filter(
						OaReferral.business_id == business_id,
						OaReferral.to_position_id == position.id,
					)
				),
			),
		)
		.order_by(OaLetter.follow_up_at)
		.limit(8)
		.all()
	)
	return {
		"position_id": position.id,
		"position_title": resolve_i18n(position.name_i18n, lang),
		"counts": _folder_counts(db, business_id, position),
		"overdue": [_desk_letter(letter, referral=ref) for ref, letter in overdue_rows],
		"due_soon": [_desk_letter(letter, referral=ref) for ref, letter in soon_rows],
		"follow_ups": [_desk_letter(letter) for letter in follow_rows],
		"horizon_days": max(1, min(int(horizon_days or 7), 30)),
	}


def _saved_filter_dict(row: OaCartableSavedFilter) -> dict:
	return {
		"id": row.id,
		"name": row.name,
		"folder": row.folder,
		"q": row.query_text,
		"date_from": row.date_from,
		"date_to": row.date_to,
		"updated_at": row.updated_at,
	}


def list_saved_filters(db: Session, business_id: int, user_id: int) -> List[dict]:
	_ensure_plugin(db, business_id)
	rows = (
		db.query(OaCartableSavedFilter)
		.filter(OaCartableSavedFilter.business_id == business_id, OaCartableSavedFilter.user_id == user_id)
		.order_by(OaCartableSavedFilter.name)
		.all()
	)
	return [_saved_filter_dict(row) for row in rows]


def save_saved_filter(db: Session, business_id: int, user_id: int, payload: dict) -> dict:
	_ensure_plugin(db, business_id)
	name = str(payload.get("name") or "").strip()
	if not name or len(name) > 80:
		raise ApiError("OA_FILTER_NAME_REQUIRED", "Filter name is required.", http_status=400)
	folder = str(payload.get("folder") or "inbox").strip()
	if folder not in _CARTABLE_FOLDERS:
		raise ApiError("OA_FOLDER_INVALID", "Unknown cartable folder.", http_status=400)
	query_text = str(payload.get("q") or "").strip() or None
	if query_text and len(query_text) > 200:
		query_text = query_text[:200]
	date_from = str(payload.get("date_from") or "").strip() or None
	date_to = str(payload.get("date_to") or "").strip() or None
	row = (
		db.query(OaCartableSavedFilter)
		.filter(
			OaCartableSavedFilter.business_id == business_id,
			OaCartableSavedFilter.user_id == user_id,
			OaCartableSavedFilter.name == name,
		)
		.first()
	)
	if row is None:
		count = (
			db.query(func.count(OaCartableSavedFilter.id))
			.filter(OaCartableSavedFilter.business_id == business_id, OaCartableSavedFilter.user_id == user_id)
			.scalar()
			or 0
		)
		if int(count) >= 30:
			raise ApiError("OA_FILTER_LIMIT", "Saved filter limit reached.", http_status=400)
		row = OaCartableSavedFilter(
			business_id=business_id,
			user_id=user_id,
			name=name,
			created_at=_now(),
			updated_at=_now(),
		)
		db.add(row)
	row.folder = folder
	row.query_text = query_text
	row.date_from = date_from[:32] if date_from else None
	row.date_to = date_to[:32] if date_to else None
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return _saved_filter_dict(row)


def delete_saved_filter(db: Session, business_id: int, user_id: int, filter_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = (
		db.query(OaCartableSavedFilter)
		.filter(
			OaCartableSavedFilter.id == filter_id,
			OaCartableSavedFilter.business_id == business_id,
			OaCartableSavedFilter.user_id == user_id,
		)
		.first()
	)
	if row is None:
		raise ApiError("OA_FILTER_NOT_FOUND", "Saved filter was not found.", http_status=404)
	db.delete(row)
	db.commit()
	return {"id": filter_id, "deleted": True}
