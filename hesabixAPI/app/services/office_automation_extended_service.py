"""قابلیت‌های تجاری اتوماسیون اداری: دبیرخانه، ECE، امضا، ابلاغ، بایگانی، گزارش."""
from __future__ import annotations

import logging
import os
import secrets
from datetime import date
from typing import Any, Dict, List, Optional, Sequence

from sqlalchemy import desc, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage
from adapters.db.models.office_automation import (
	OaArchiveFolder,
	OaCartableRule,
	OaDispatch,
	OaEceMessage,
	OaExternalOrg,
	OaLetter,
	OaLetterAttachment,
	OaLetterSignStep,
	OaLetterVersion,
	OaMailboxMessage,
	OaOrgUnit,
	OaPosition,
	OaPositionHolder,
	OaReferral,
	OaSecretariat,
	OaSignPathTemplate,
	OaSignPathTemplateStep,
	OaUserSignature,
)
from adapters.db.models.person import Person
from app.core.calendar import CalendarType
from app.core.responses import ApiError
from app.services.office_automation_ece import build_ece_xml, parse_ece_xml
from app.services.office_automation_service import (
	_allocate_oa_code,
	_audit,
	_can_view_letter,
	_create_referral,
	_ensure_plugin,
	_get_letter,
	_get_position,
	_letter_dict,
	_normalize_i18n,
	_now,
	_occupancy_filter,
	_parse_date,
	_require_letter_open,
	_user_display_name,
	get_letter,
	get_or_create_settings,
	resolve_acting_position,
	resolve_i18n,
)

logger = logging.getLogger(__name__)

_SIGN_STEP_STATUSES = frozenset({"pending", "current", "signed", "rejected", "skipped"})
_DISPATCH_STATUSES = frozenset({"dispatched", "acknowledged"})
_ECE_DIRECTIONS = frozenset({"in", "out"})


def _person_title(person: Person) -> str:
	parts = [person.first_name or "", person.last_name or ""]
	name = " ".join(p for p in parts if p).strip()
	return name or person.alias_name or person.company_name or str(person.id)


def validate_person_id(db: Session, business_id: int, person_id: Optional[int]) -> Optional[int]:
	if not person_id:
		return None
	row = db.query(Person).filter(Person.id == int(person_id), Person.business_id == business_id).first()
	if not row:
		raise ApiError("OA_PERSON_NOT_FOUND", "Person was not found in this business.", http_status=404)
	return row.id


def snapshot_letter_version(db: Session, letter: OaLetter, user_id: int) -> Optional[OaLetterVersion]:
	last = (
		db.query(OaLetterVersion)
		.filter(OaLetterVersion.letter_id == letter.id)
		.order_by(OaLetterVersion.version_no.desc())
		.first()
	)
	next_no = (last.version_no + 1) if last else 1
	if last and last.subject == letter.subject and (last.body or "") == (letter.body or ""):
		return last
	row = OaLetterVersion(
		business_id=letter.business_id,
		letter_id=letter.id,
		version_no=next_no,
		subject=letter.subject,
		body=letter.body,
		body_format=letter.body_format or "markdown",
		created_by_user_id=user_id,
		created_at=_now(),
	)
	db.add(row)
	db.flush()
	return row


def list_letter_versions(db: Session, business_id: int, letter_id: int, user_id: int, position_id: Optional[int], lang: str = "fa", is_admin: bool = False) -> List[dict]:
	get_letter(db, business_id, letter_id, user_id, position_id, lang=lang, is_admin=is_admin)
	rows = (
		db.query(OaLetterVersion)
		.filter(OaLetterVersion.letter_id == letter_id, OaLetterVersion.business_id == business_id)
		.order_by(OaLetterVersion.version_no.desc())
		.all()
	)
	return [
		{
			"id": r.id,
			"version_no": r.version_no,
			"subject": r.subject,
			"body": r.body,
			"body_format": r.body_format,
			"created_by_user_id": r.created_by_user_id,
			"created_at": r.created_at,
		}
		for r in rows
	]


def ensure_default_secretariat(db: Session, business_id: int) -> OaSecretariat:
	row = (
		db.query(OaSecretariat)
		.filter(OaSecretariat.business_id == business_id, OaSecretariat.is_default == True)  # noqa: E712
		.first()
	)
	if row:
		return row
	settings = get_or_create_settings(db, business_id)
	row = OaSecretariat(
		business_id=business_id,
		code="main",
		name_i18n={"fa": "دبیرخانه مرکزی", "en": "Central secretariat"},
		incoming_prefix=settings.incoming_prefix or "IN",
		outgoing_prefix=settings.outgoing_prefix or "OUT",
		internal_prefix=settings.internal_prefix or "INT",
		is_default=True,
		is_active=True,
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	db.flush()
	return row


def _secretariat_dict(row: OaSecretariat, lang: str) -> dict:
	return {
		"id": row.id,
		"code": row.code,
		"name_i18n": row.name_i18n,
		"title": resolve_i18n(row.name_i18n, lang),
		"org_unit_id": row.org_unit_id,
		"incoming_prefix": row.incoming_prefix,
		"outgoing_prefix": row.outgoing_prefix,
		"internal_prefix": row.internal_prefix,
		"is_confidential": row.is_confidential,
		"is_default": row.is_default,
		"is_active": row.is_active,
		"ece_enabled": row.ece_enabled,
		"ece_email": row.ece_email,
		"sort_order": row.sort_order,
	}


def list_secretariats(db: Session, business_id: int, *, include_inactive: bool = False, lang: str = "fa") -> List[dict]:
	_ensure_plugin(db, business_id)
	ensure_default_secretariat(db, business_id)
	q = db.query(OaSecretariat).filter(OaSecretariat.business_id == business_id)
	if not include_inactive:
		q = q.filter(OaSecretariat.is_active == True)  # noqa: E712
	rows = q.order_by(OaSecretariat.sort_order, OaSecretariat.id).all()
	return [_secretariat_dict(r, lang) for r in rows]


def create_secretariat(db: Session, business_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	ensure_default_secretariat(db, business_id)
	code = str(payload.get("code") or "").strip() or _allocate_oa_code(db, business_id, OaSecretariat, "s")
	row = OaSecretariat(
		business_id=business_id,
		org_unit_id=int(payload["org_unit_id"]) if payload.get("org_unit_id") else None,
		code=code[:64],
		name_i18n=_normalize_i18n(payload.get("name_i18n") or payload.get("name")),
		incoming_prefix=str(payload.get("incoming_prefix") or "IN")[:16],
		outgoing_prefix=str(payload.get("outgoing_prefix") or "OUT")[:16],
		internal_prefix=str(payload.get("internal_prefix") or "INT")[:16],
		is_confidential=bool(payload.get("is_confidential")),
		is_default=bool(payload.get("is_default")),
		is_active=bool(payload.get("is_active", True)),
		ece_enabled=bool(payload.get("ece_enabled")),
		ece_email=(str(payload.get("ece_email") or "").strip() or None),
		sort_order=int(payload.get("sort_order") or 0),
		created_at=_now(),
		updated_at=_now(),
	)
	if row.is_default:
		db.query(OaSecretariat).filter(OaSecretariat.business_id == business_id).update({"is_default": False})
	db.add(row)
	_audit(db, business_id=business_id, user_id=user_id, action="secretariat.create", payload={"code": row.code})
	db.commit()
	db.refresh(row)
	return _secretariat_dict(row, lang)


def update_secretariat(db: Session, business_id: int, secretariat_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaSecretariat).filter(OaSecretariat.id == secretariat_id, OaSecretariat.business_id == business_id).first()
	if not row:
		raise ApiError("OA_SECRETARIAT_NOT_FOUND", "Secretariat was not found.", http_status=404)
	if payload.get("name_i18n") or payload.get("name"):
		row.name_i18n = _normalize_i18n(payload.get("name_i18n") or payload.get("name"))
	if payload.get("code"):
		row.code = str(payload["code"]).strip()[:64]
	if "org_unit_id" in payload:
		row.org_unit_id = int(payload["org_unit_id"]) if payload.get("org_unit_id") else None
	for field in ("incoming_prefix", "outgoing_prefix", "internal_prefix"):
		if payload.get(field):
			setattr(row, field, str(payload[field]).strip()[:16])
	if "is_confidential" in payload:
		row.is_confidential = bool(payload["is_confidential"])
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	if "ece_enabled" in payload:
		row.ece_enabled = bool(payload["ece_enabled"])
	if "ece_email" in payload:
		row.ece_email = str(payload.get("ece_email") or "").strip() or None
	if "sort_order" in payload:
		row.sort_order = int(payload.get("sort_order") or 0)
	if payload.get("is_default"):
		db.query(OaSecretariat).filter(OaSecretariat.business_id == business_id).update({"is_default": False})
		row.is_default = True
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="secretariat.update", payload={"id": row.id})
	db.commit()
	db.refresh(row)
	return _secretariat_dict(row, lang)


_CLASSIFIED = frozenset({"confidential", "highly_confidential", "secret"})


def resolve_letter_secretariat(
	db: Session,
	business_id: int,
	position: OaPosition,
	payload: dict,
	confidentiality: Optional[str] = None,
) -> OaSecretariat:
	sid = payload.get("secretariat_id") or getattr(position, "secretariat_id", None)
	row = None
	if sid:
		row = db.query(OaSecretariat).filter(OaSecretariat.id == int(sid), OaSecretariat.business_id == business_id).first()
		if not row:
			raise ApiError("OA_SECRETARIAT_NOT_FOUND", "Secretariat was not found.", http_status=404)
	classified = (confidentiality or "") in _CLASSIFIED
	if classified:
		if row and row.is_confidential:
			return row
		confidential = (
			db.query(OaSecretariat)
			.filter(
				OaSecretariat.business_id == business_id,
				OaSecretariat.is_confidential == True,  # noqa: E712
				OaSecretariat.is_active == True,  # noqa: E712
			)
			.order_by(OaSecretariat.is_default.desc(), OaSecretariat.id)
			.first()
		)
		if row and not row.is_confidential and confidential:
			raise ApiError(
				"OA_CONFIDENTIAL_SECRETARIAT_REQUIRED",
				"Classified letters must be registered in a confidential secretariat.",
				http_status=400,
			)
		if confidential:
			return confidential
	if row:
		return row
	return ensure_default_secretariat(db, business_id)


def fire_oa_workflow(db: Session, business_id: int, trigger_type: str, letter: OaLetter, user_id: int, extra: Optional[dict] = None) -> None:
	try:
		from app.services.workflow.workflow_trigger_service import trigger_workflows

		payload = {
			"letter_id": letter.id,
			"subject": letter.subject,
			"number": letter.secretariat_number,
			"letter_kind": letter.letter_kind,
			"status": letter.status,
			"confidentiality": letter.confidentiality,
			"urgency": letter.urgency,
			"person_id": letter.person_id,
			"secretariat_id": letter.secretariat_id,
		}
		if extra:
			payload.update(extra)
		trigger_workflows(db, business_id, trigger_type, payload, user_id)
	except Exception:
		logger.debug("OA workflow trigger %s skipped", trigger_type, exc_info=True)


def _external_org_dict(row: OaExternalOrg, lang: str) -> dict:
	return {
		"id": row.id,
		"code": row.code,
		"name_i18n": row.name_i18n,
		"title": resolve_i18n(row.name_i18n, lang),
		"ece_email": row.ece_email,
		"national_id": row.national_id,
		"phone": row.phone,
		"address": row.address,
		"is_active": row.is_active,
		"extra_info": row.extra_info or {},
	}


def list_external_orgs(db: Session, business_id: int, *, q: Optional[str] = None, include_inactive: bool = False, lang: str = "fa") -> List[dict]:
	_ensure_plugin(db, business_id)
	query = db.query(OaExternalOrg).filter(OaExternalOrg.business_id == business_id)
	if not include_inactive:
		query = query.filter(OaExternalOrg.is_active == True)  # noqa: E712
	if q:
		like = f"%{q.strip()}%"
		query = query.filter(or_(OaExternalOrg.code.ilike(like), OaExternalOrg.ece_email.ilike(like)))
	rows = query.order_by(OaExternalOrg.id.desc()).limit(200).all()
	items = [_external_org_dict(r, lang) for r in rows]
	if q:
		needle = q.strip().lower()
		items = [i for i in items if needle in i["title"].lower() or needle in (i["code"] or "").lower()]
	return items


def create_external_org(db: Session, business_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip() or _allocate_oa_code(db, business_id, OaExternalOrg, "x")
	row = OaExternalOrg(
		business_id=business_id,
		code=code[:64],
		name_i18n=_normalize_i18n(payload.get("name_i18n") or payload.get("name")),
		ece_email=(str(payload.get("ece_email") or "").strip() or None),
		national_id=(str(payload.get("national_id") or "").strip() or None),
		phone=(str(payload.get("phone") or "").strip() or None),
		address=(str(payload.get("address") or "").strip() or None),
		is_active=bool(payload.get("is_active", True)),
		extra_info=payload.get("extra_info") if isinstance(payload.get("extra_info"), dict) else None,
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(row)
	_audit(db, business_id=business_id, user_id=user_id, action="external_org.create", payload={"code": row.code})
	db.commit()
	db.refresh(row)
	return _external_org_dict(row, lang)


def update_external_org(db: Session, business_id: int, org_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaExternalOrg).filter(OaExternalOrg.id == org_id, OaExternalOrg.business_id == business_id).first()
	if not row:
		raise ApiError("OA_EXTERNAL_ORG_NOT_FOUND", "External organization was not found.", http_status=404)
	if payload.get("name_i18n") or payload.get("name"):
		row.name_i18n = _normalize_i18n(payload.get("name_i18n") or payload.get("name"))
	if payload.get("code"):
		row.code = str(payload["code"]).strip()[:64]
	for field in ("ece_email", "national_id", "phone", "address"):
		if field in payload:
			setattr(row, field, str(payload.get(field) or "").strip() or None)
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	if "extra_info" in payload and isinstance(payload.get("extra_info"), dict):
		row.extra_info = payload["extra_info"]
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="external_org.update", payload={"id": row.id})
	db.commit()
	db.refresh(row)
	return _external_org_dict(row, lang)


def _signature_dict(row: OaUserSignature) -> dict:
	return {
		"id": row.id,
		"user_id": row.user_id,
		"title": row.title,
		"image_file_id": row.image_file_id,
		"color": row.color,
		"is_default": row.is_default,
		"is_active": row.is_active,
	}


def list_signatures(db: Session, business_id: int, user_id: int) -> List[dict]:
	_ensure_plugin(db, business_id)
	rows = (
		db.query(OaUserSignature)
		.filter(OaUserSignature.business_id == business_id, OaUserSignature.user_id == user_id)
		.order_by(OaUserSignature.is_default.desc(), OaUserSignature.id)
		.all()
	)
	return [_signature_dict(r) for r in rows]


def upsert_signature(db: Session, business_id: int, user_id: int, payload: dict) -> dict:
	_ensure_plugin(db, business_id)
	row_id = payload.get("id")
	row = None
	if row_id:
		row = db.query(OaUserSignature).filter(
			OaUserSignature.id == int(row_id),
			OaUserSignature.business_id == business_id,
			OaUserSignature.user_id == user_id,
		).first()
		if not row:
			raise ApiError("OA_SIGNATURE_NOT_FOUND", "Signature was not found.", http_status=404)
	if row is None:
		row = OaUserSignature(
			business_id=business_id,
			user_id=user_id,
			title=str(payload.get("title") or "default")[:120],
			created_at=_now(),
			updated_at=_now(),
		)
		db.add(row)
	if payload.get("title"):
		row.title = str(payload["title"]).strip()[:120]
	if "image_file_id" in payload:
		row.image_file_id = payload.get("image_file_id") or None
	if "color" in payload:
		row.color = payload.get("color")
	if payload.get("is_default"):
		db.query(OaUserSignature).filter(
			OaUserSignature.business_id == business_id, OaUserSignature.user_id == user_id
		).update({"is_default": False})
		row.is_default = True
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return _signature_dict(row)


def _template_dict(row: OaSignPathTemplate, steps: Sequence[OaSignPathTemplateStep], lang: str) -> dict:
	return {
		"id": row.id,
		"name": row.name,
		"letter_kind": row.letter_kind,
		"require_before_register": row.require_before_register,
		"is_active": row.is_active,
		"steps": [
			{
				"id": s.id,
				"position_id": s.position_id,
				"sort_order": s.sort_order,
				"is_required": s.is_required,
				"role_title": s.role_title,
			}
			for s in steps
		],
	}


def list_sign_path_templates(db: Session, business_id: int, lang: str = "fa") -> List[dict]:
	_ensure_plugin(db, business_id)
	rows = db.query(OaSignPathTemplate).filter(OaSignPathTemplate.business_id == business_id).order_by(OaSignPathTemplate.id).all()
	out = []
	for row in rows:
		steps = (
			db.query(OaSignPathTemplateStep)
			.filter(OaSignPathTemplateStep.template_id == row.id)
			.order_by(OaSignPathTemplateStep.sort_order, OaSignPathTemplateStep.id)
			.all()
		)
		out.append(_template_dict(row, steps, lang))
	return out


def save_sign_path_template(db: Session, business_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "Sign path name is required.", http_status=400)
	row = None
	if payload.get("id"):
		row = db.query(OaSignPathTemplate).filter(
			OaSignPathTemplate.id == int(payload["id"]), OaSignPathTemplate.business_id == business_id
		).first()
	if row is None:
		row = OaSignPathTemplate(business_id=business_id, created_at=_now(), updated_at=_now())
		db.add(row)
		db.flush()
	row.name = name[:120]
	kind = payload.get("letter_kind")
	row.letter_kind = kind if kind in {"internal", "incoming", "outgoing"} else None
	row.require_before_register = bool(payload.get("require_before_register"))
	row.is_active = bool(payload.get("is_active", True))
	row.updated_at = _now()
	db.query(OaSignPathTemplateStep).filter(OaSignPathTemplateStep.template_id == row.id).delete()
	for idx, item in enumerate(payload.get("steps") or []):
		pid = int(item.get("position_id") or 0)
		_get_position(db, business_id, pid)
		db.add(
			OaSignPathTemplateStep(
				template_id=row.id,
				position_id=pid,
				sort_order=int(item.get("sort_order") or idx),
				is_required=bool(item.get("is_required", True)),
				role_title=(str(item.get("role_title") or "").strip() or None),
			)
		)
	_audit(db, business_id=business_id, user_id=user_id, action="sign_path.save", payload={"id": row.id})
	db.commit()
	db.refresh(row)
	steps = db.query(OaSignPathTemplateStep).filter(OaSignPathTemplateStep.template_id == row.id).order_by(OaSignPathTemplateStep.sort_order).all()
	return _template_dict(row, steps, lang)


def start_sign_path(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	letter = _get_letter(db, business_id, letter_id)
	_require_letter_open(letter, allow_draft=True)
	db.query(OaLetterSignStep).filter(OaLetterSignStep.letter_id == letter.id).delete()
	steps_payload = list(payload.get("steps") or [])
	if payload.get("template_id") and not steps_payload:
		tpl = db.query(OaSignPathTemplate).filter(
			OaSignPathTemplate.id == int(payload["template_id"]), OaSignPathTemplate.business_id == business_id
		).first()
		if not tpl:
			raise ApiError("OA_SIGN_PATH_NOT_FOUND", "Sign path template was not found.", http_status=404)
		steps_payload = [
			{"position_id": s.position_id, "sort_order": s.sort_order, "is_required": s.is_required}
			for s in db.query(OaSignPathTemplateStep).filter(OaSignPathTemplateStep.template_id == tpl.id).order_by(OaSignPathTemplateStep.sort_order).all()
		]
	if not steps_payload:
		raise ApiError("VALIDATION_ERROR", "Sign path steps are required.", http_status=400)
	for idx, item in enumerate(steps_payload):
		pid = int(item.get("position_id") or 0)
		_get_position(db, business_id, pid)
		db.add(
			OaLetterSignStep(
				business_id=business_id,
				letter_id=letter.id,
				position_id=pid,
				sort_order=int(item.get("sort_order") or idx),
				is_required=bool(item.get("is_required", True)),
				status="current" if idx == 0 else "pending",
				created_at=_now(),
			)
		)
	letter.sign_status = "pending"
	letter.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.sign_path", letter_id=letter.id, position_id=position.id)
	db.commit()
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=True)


def sign_letter_step(
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
	_require_letter_open(letter, allow_draft=True)
	step = (
		db.query(OaLetterSignStep)
		.filter(
			OaLetterSignStep.letter_id == letter.id,
			OaLetterSignStep.position_id == position.id,
			OaLetterSignStep.status == "current",
		)
		.order_by(OaLetterSignStep.sort_order)
		.first()
	)
	if not step:
		raise ApiError("OA_SIGN_STEP_NOT_FOUND", "No current signature step for this position.", http_status=400)
	sig = None
	if payload.get("signature_id"):
		sig = db.query(OaUserSignature).filter(
			OaUserSignature.id == int(payload["signature_id"]),
			OaUserSignature.business_id == business_id,
			OaUserSignature.user_id == user_id,
		).first()
	if sig is None:
		sig = (
			db.query(OaUserSignature)
			.filter(OaUserSignature.business_id == business_id, OaUserSignature.user_id == user_id, OaUserSignature.is_active == True)  # noqa: E712
			.order_by(OaUserSignature.is_default.desc())
			.first()
		)
	step.status = "signed"
	step.signed_by_user_id = user_id
	step.signature_id = sig.id if sig else None
	step.image_file_id = payload.get("image_file_id") or (sig.image_file_id if sig else None)
	step.note = payload.get("note")
	step.signed_at = _now()
	nxt = (
		db.query(OaLetterSignStep)
		.filter(OaLetterSignStep.letter_id == letter.id, OaLetterSignStep.status == "pending")
		.order_by(OaLetterSignStep.sort_order)
		.first()
	)
	if nxt:
		nxt.status = "current"
		letter.sign_status = "pending"
	else:
		letter.sign_status = "signed"
	letter.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.sign", letter_id=letter.id, position_id=position.id)
	db.commit()
	_notify_letter_event(
		db,
		business_id,
		letter,
		"office_automation.letter_signed",
		position_ids=[letter.origin_position_id] + ([nxt.position_id] if nxt else []),
	)
	fire_oa_workflow(db, business_id, "office_automation.letter_signed", letter, user_id)
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=True)


def reject_sign_step(
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
	step = (
		db.query(OaLetterSignStep)
		.filter(
			OaLetterSignStep.letter_id == letter.id,
			OaLetterSignStep.position_id == position.id,
			OaLetterSignStep.status == "current",
		)
		.first()
	)
	if not step:
		raise ApiError("OA_SIGN_STEP_NOT_FOUND", "No current signature step for this position.", http_status=400)
	step.status = "rejected"
	step.note = payload.get("note")
	step.signed_by_user_id = user_id
	step.signed_at = _now()
	letter.sign_status = "rejected"
	letter.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.sign_reject", letter_id=letter.id, position_id=position.id)
	db.commit()
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=True)


def required_signs_complete(db: Session, letter: OaLetter) -> bool:
	pending = (
		db.query(OaLetterSignStep.id)
		.filter(
			OaLetterSignStep.letter_id == letter.id,
			OaLetterSignStep.is_required == True,  # noqa: E712
			OaLetterSignStep.status != "signed",
		)
		.first()
	)
	return pending is None


def dispatch_letter(
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
	letter = _get_letter(db, business_id, letter_id)
	_require_letter_open(letter)
	to_pid = int(payload.get("to_position_id") or 0)
	to_position = _get_position(db, business_id, to_pid)
	row = OaDispatch(
		business_id=business_id,
		letter_id=letter.id,
		from_position_id=position.id,
		to_position_id=to_position.id,
		from_user_id=user_id,
		instruction=payload.get("instruction"),
		status="dispatched",
		created_at=_now(),
	)
	db.add(row)
	_create_referral(
		db,
		letter=letter,
		from_position=position,
		from_user_id=user_id,
		to_position_id=to_position.id,
		kind="action",
		priority=str(payload.get("priority") or letter.urgency),
		instruction=payload.get("instruction") or "ابلاغ",
		due_at=_parse_date(payload.get("due_at"), calendar_type),
		parent_referral_id=None,
	)
	if letter.status == "registered":
		letter.status = "in_circulation"
	letter.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.dispatch", letter_id=letter.id, position_id=position.id)
	db.commit()
	try:
		from app.services.notification_service import NotificationService
		from adapters.db.models.business import Business

		svc = NotificationService(db)
		now = _now()
		uids = {
			r[0]
			for r in db.query(OaPositionHolder.user_id)
			.filter(OaPositionHolder.position_id == to_position.id, OaPositionHolder.business_id == business_id)
			.filter(_occupancy_filter(now))
			.all()
		}
		for uid in uids:
			svc.send(
				user_id=int(uid),
				event_key="office_automation.letter_dispatched",
				context={
					"subject": letter.subject,
					"number": letter.secretariat_number or "",
					"letter_id": letter.id,
					"business_name": db.query(Business.name).filter(Business.id == business_id).scalar() or "",
				},
				preferred_channels=["inapp", "sms", "email"],
			)
	except Exception:
		logger.debug("OA dispatch notify skipped", exc_info=True)
	fire_oa_workflow(db, business_id, "office_automation.letter_dispatched", letter, user_id, extra={"to_position_id": to_position.id})
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=True)


def acknowledge_dispatch(
	db: Session,
	business_id: int,
	dispatch_id: int,
	user_id: int,
	position_id: int,
	lang: str = "fa",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	row = db.query(OaDispatch).filter(OaDispatch.id == dispatch_id, OaDispatch.business_id == business_id).first()
	if not row:
		raise ApiError("OA_DISPATCH_NOT_FOUND", "Dispatch was not found.", http_status=404)
	if row.to_position_id != position.id:
		raise ApiError("OA_LETTER_FORBIDDEN", "This dispatch does not belong to the active position.", http_status=403)
	row.status = "acknowledged"
	row.acknowledged_at = _now()
	row.acknowledged_by_user_id = user_id
	db.commit()
	return get_letter(db, business_id, row.letter_id, user_id, position_id, lang=lang, is_admin=True)


def cancel_referral(db: Session, business_id: int, referral_id: int, payload: dict, user_id: int, position_id: int, lang: str = "fa") -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	row = db.query(OaReferral).filter(OaReferral.id == referral_id, OaReferral.business_id == business_id).first()
	if not row:
		raise ApiError("OA_REFERRAL_NOT_FOUND", "Referral was not found.", http_status=404)
	if row.from_position_id != position.id:
		raise ApiError("OA_LETTER_FORBIDDEN", "Only the sender position can cancel this referral.", http_status=403)
	if row.status in {"done", "returned", "cancelled"}:
		raise ApiError("OA_REFERRAL_CLOSED", "This referral can no longer be cancelled.", http_status=400)
	row.status = "cancelled"
	row.completion_note = payload.get("note")
	row.completed_at = _now()
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="referral.cancel", letter_id=row.letter_id, position_id=position.id)
	db.commit()
	return get_letter(db, business_id, row.letter_id, user_id, position_id, lang=lang, is_admin=True)


def unarchive_letter(db: Session, business_id: int, letter_id: int, user_id: int, position_id: int, lang: str = "fa") -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	letter = _get_letter(db, business_id, letter_id)
	if letter.status != "archived":
		raise ApiError("OA_LETTER_NOT_ARCHIVED", "Only archived letters can be reopened.", http_status=400)
	pending = db.query(OaReferral.id).filter(OaReferral.letter_id == letter.id, OaReferral.status.in_(("pending", "seen"))).first()
	letter.status = "in_circulation" if pending else "closed"
	letter.archive_folder_id = None
	letter.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="letter.unarchive", letter_id=letter.id, position_id=position.id)
	db.commit()
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=True)


def _read_file_bytes(file_row: Optional[FileStorage]) -> bytes:
	if not file_row or not file_row.file_path:
		return b""
	path = file_row.file_path
	if os.path.isfile(path):
		with open(path, "rb") as handle:
			return handle.read()
	return b""


def export_ece(
	db: Session,
	business_id: int,
	letter_id: int,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	data = get_letter(db, business_id, letter_id, user_id, position_id, lang=lang, is_admin=True)
	letter = _get_letter(db, business_id, letter_id)
	if not letter.secretariat_number:
		raise ApiError("OA_LETTER_NOT_REGISTERED", "Register the letter before ECE export.", http_status=400)
	settings = get_or_create_settings(db, business_id)
	sender = {
		"name": letter.sender_name or "",
		"organization": letter.sender_org or "",
		"position": data.get("sender_position_title") or "",
		"department": data.get("sender_unit_title") or "",
		"code": "",
	}
	receiver = {
		"name": letter.receiver_name or "",
		"organization": letter.receiver_org or "",
		"position": data.get("receiver_position_title") or "",
		"department": data.get("receiver_unit_title") or "",
		"code": "",
	}
	attachments = []
	for item in data.get("attachments") or []:
		frow = db.query(FileStorage).filter(FileStorage.id == item.get("file_storage_id")).first()
		content = _read_file_bytes(frow)
		if not content:
			continue
		attachments.append(
			{
				"content": content,
				"filename": getattr(frow, "original_name", None) or "file.bin",
				"mime": getattr(frow, "mime_type", None) or "application/octet-stream",
				"description": item.get("title") or "",
			}
		)
	xml = build_ece_xml(
		sender=sender,
		receiver=receiver,
		letter_no=letter.secretariat_number,
		letter_date=letter.letter_date,
		subject=letter.subject,
		urgency=letter.urgency,
		confidentiality=letter.confidentiality,
		keywords=letter.keywords or "",
		body=letter.body or "",
		attachments=attachments,
		calendar_label=settings.numbering_calendar or calendar_type,
		letter_datetime=letter.registered_at,
	)
	msg = OaEceMessage(
		business_id=business_id,
		letter_id=letter.id,
		secretariat_id=letter.secretariat_id,
		external_org_id=letter.external_org_id,
		direction="out",
		status="exported",
		xml_content=xml,
		created_by_user_id=user_id,
		created_at=_now(),
	)
	db.add(msg)
	db.commit()
	db.refresh(msg)
	return {"id": msg.id, "xml": xml, "letter_id": letter.id, "status": msg.status}


def send_ece(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	exported = export_ece(db, business_id, letter_id, user_id, position_id, lang=lang, calendar_type=calendar_type)
	letter = _get_letter(db, business_id, letter_id)
	to_email = str(payload.get("to_email") or "").strip()
	if not to_email and letter.external_org_id:
		org = db.query(OaExternalOrg).filter(OaExternalOrg.id == letter.external_org_id).first()
		to_email = (org.ece_email if org else "") or ""
	if not to_email:
		raise ApiError("OA_ECE_EMAIL_REQUIRED", "Destination ECE email is required.", http_status=400)
	ok = False
	err = None
	try:
		from app.services.email_service import EmailService

		ok = EmailService(db).send_email_with_attachment(
			to=to_email,
			subject=f"ECE {letter.secretariat_number}",
			body=letter.subject,
			attachment_filename=f"{letter.secretariat_number or 'letter'}.xml",
			attachment_content=exported["xml"].encode("utf-8"),
		)
	except Exception as exc:
		err = str(exc)
		logger.debug("ECE email send failed", exc_info=True)
	msg = db.query(OaEceMessage).filter(OaEceMessage.id == exported["id"]).first()
	if msg:
		msg.to_email = to_email
		msg.status = "sent" if ok else "failed"
		msg.error_message = None if ok else (err or "Email send failed")
		msg.sent_at = _now() if ok else None
		db.commit()
	if not ok:
		raise ApiError("OA_ECE_SEND_FAILED", "ECE email could not be sent. XML was still generated.", http_status=502, details={"xml": exported["xml"]})
	return {"id": exported["id"], "status": "sent", "to_email": to_email, "xml": exported["xml"]}


def import_ece(
	db: Session,
	business_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	xml_text = str(payload.get("xml") or "")
	try:
		parsed = parse_ece_xml(xml_text)
	except Exception as exc:
		raise ApiError("OA_ECE_INVALID", f"Invalid ECE XML: {exc}", http_status=400) from exc
	from app.services.office_automation_service import create_letter_draft

	letter_date = parsed.get("letter_datetime") or ""
	draft_payload = {
		"subject": parsed.get("subject") or "ECE",
		"body": parsed.get("body") or "",
		"letter_kind": "incoming",
		"letter_date": letter_date[:10] if letter_date else None,
		"urgency": parsed.get("urgency") or "normal",
		"confidentiality": parsed.get("confidentiality") or "normal",
		"sender_name": (parsed.get("sender") or {}).get("name"),
		"sender_org": (parsed.get("sender") or {}).get("organization"),
		"receiver_name": (parsed.get("receiver") or {}).get("name"),
		"receiver_org": (parsed.get("receiver") or {}).get("organization"),
		"keywords": parsed.get("keywords"),
		"receipt_number": parsed.get("letter_no"),
	}
	created = create_letter_draft(db, business_id, draft_payload, user_id, position.id, lang=lang, calendar_type=parsed.get("show_as") or calendar_type)
	letter = _get_letter(db, business_id, created["id"])
	msg = OaEceMessage(
		business_id=business_id,
		letter_id=letter.id,
		direction="in",
		status="imported",
		from_email=payload.get("from_email"),
		xml_content=xml_text,
		receipt_number=parsed.get("letter_no"),
		created_by_user_id=user_id,
		created_at=_now(),
	)
	db.add(msg)
	db.commit()
	return get_letter(db, business_id, letter.id, user_id, position.id, lang=lang, is_admin=True)


def list_ece_messages(db: Session, business_id: int, *, direction: Optional[str] = None) -> List[dict]:
	_ensure_plugin(db, business_id)
	q = db.query(OaEceMessage).filter(OaEceMessage.business_id == business_id)
	if direction in _ECE_DIRECTIONS:
		q = q.filter(OaEceMessage.direction == direction)
	rows = q.order_by(OaEceMessage.id.desc()).limit(100).all()
	return [
		{
			"id": r.id,
			"letter_id": r.letter_id,
			"direction": r.direction,
			"status": r.status,
			"to_email": r.to_email,
			"from_email": r.from_email,
			"receipt_number": r.receipt_number,
			"error_message": r.error_message,
			"sent_at": r.sent_at,
			"created_at": r.created_at,
		}
		for r in rows
	]


def apply_cartable_rules(db: Session, business_id: int, letter: OaLetter, referral: OaReferral) -> None:
	rules = (
		db.query(OaCartableRule)
		.filter(OaCartableRule.business_id == business_id, OaCartableRule.is_active == True)  # noqa: E712
		.filter(or_(OaCartableRule.position_id == referral.to_position_id, OaCartableRule.position_id.is_(None)))
		.order_by(OaCartableRule.priority.desc(), OaCartableRule.id)
		.all()
	)
	for rule in rules:
		cond = rule.conditions or {}
		if cond.get("letter_kind") and cond["letter_kind"] != letter.letter_kind:
			continue
		if cond.get("confidentiality") and cond["confidentiality"] != letter.confidentiality:
			continue
		if cond.get("from_position_id") and int(cond["from_position_id"]) != referral.from_position_id:
			continue
		needle = str(cond.get("subject_contains") or "").strip()
		if needle and needle.lower() not in (letter.subject or "").lower():
			continue
		actions = rule.actions or {}
		if actions.get("mark_seen"):
			referral.status = "seen"
			referral.seen_at = _now()
		if actions.get("auto_archive_folder_id"):
			letter.archive_folder_id = int(actions["auto_archive_folder_id"])
			letter.status = "archived"
		to_pid = actions.get("auto_refer_to")
		if to_pid:
			try:
				_create_referral(
					db,
					letter=letter,
					from_position=_get_position(db, business_id, referral.to_position_id),
					from_user_id=referral.from_user_id,
					to_position_id=int(to_pid),
					kind="action",
					priority=referral.priority,
					instruction="ارجاع خودکار",
					due_at=referral.due_at,
					parent_referral_id=referral.id,
				)
			except Exception:
				logger.debug("auto-refer rule failed", exc_info=True)
		break


def list_cartable_rules(db: Session, business_id: int) -> List[dict]:
	_ensure_plugin(db, business_id)
	rows = db.query(OaCartableRule).filter(OaCartableRule.business_id == business_id).order_by(OaCartableRule.priority.desc(), OaCartableRule.id).all()
	return [
		{
			"id": r.id,
			"name": r.name,
			"position_id": r.position_id,
			"priority": r.priority,
			"is_active": r.is_active,
			"conditions": r.conditions or {},
			"actions": r.actions or {},
		}
		for r in rows
	]


def save_cartable_rule(db: Session, business_id: int, payload: dict, user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	name = str(payload.get("name") or "").strip()
	if not name:
		raise ApiError("VALIDATION_ERROR", "Rule name is required.", http_status=400)
	row = None
	if payload.get("id"):
		row = db.query(OaCartableRule).filter(OaCartableRule.id == int(payload["id"]), OaCartableRule.business_id == business_id).first()
	if row is None:
		row = OaCartableRule(business_id=business_id, created_at=_now(), updated_at=_now(), conditions={}, actions={})
		db.add(row)
	row.name = name[:120]
	row.position_id = int(payload["position_id"]) if payload.get("position_id") else None
	row.priority = int(payload.get("priority") or 0)
	row.is_active = bool(payload.get("is_active", True))
	row.conditions = payload.get("conditions") if isinstance(payload.get("conditions"), dict) else {}
	row.actions = payload.get("actions") if isinstance(payload.get("actions"), dict) else {}
	row.updated_at = _now()
	_audit(db, business_id=business_id, user_id=user_id, action="cartable_rule.save")
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"name": row.name,
		"position_id": row.position_id,
		"priority": row.priority,
		"is_active": row.is_active,
		"conditions": row.conditions,
		"actions": row.actions,
	}


def delete_cartable_rule(db: Session, business_id: int, rule_id: int, user_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaCartableRule).filter(OaCartableRule.id == rule_id, OaCartableRule.business_id == business_id).first()
	if not row:
		raise ApiError("OA_RULE_NOT_FOUND", "Cartable rule was not found.", http_status=404)
	db.delete(row)
	_audit(db, business_id=business_id, user_id=user_id, action="cartable_rule.delete", payload={"id": rule_id})
	db.commit()
	return {"id": rule_id, "deleted": True}


def list_archive_folders(db: Session, business_id: int, lang: str = "fa") -> List[dict]:
	_ensure_plugin(db, business_id)
	rows = db.query(OaArchiveFolder).filter(OaArchiveFolder.business_id == business_id).order_by(OaArchiveFolder.sort_order, OaArchiveFolder.id).all()
	return [
		{
			"id": r.id,
			"parent_id": r.parent_id,
			"code": r.code,
			"name_i18n": r.name_i18n,
			"title": resolve_i18n(r.name_i18n, lang),
			"is_active": r.is_active,
			"sort_order": r.sort_order,
		}
		for r in rows
	]


def save_archive_folder(db: Session, business_id: int, payload: dict, user_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	row = None
	if payload.get("id"):
		row = db.query(OaArchiveFolder).filter(OaArchiveFolder.id == int(payload["id"]), OaArchiveFolder.business_id == business_id).first()
	if row is None:
		row = OaArchiveFolder(
			business_id=business_id,
			code=str(payload.get("code") or "").strip() or _allocate_oa_code(db, business_id, OaArchiveFolder, "a"),
			name_i18n=_normalize_i18n(payload.get("name_i18n") or payload.get("name")),
			created_at=_now(),
			updated_at=_now(),
		)
		db.add(row)
	else:
		if payload.get("name_i18n") or payload.get("name"):
			row.name_i18n = _normalize_i18n(payload.get("name_i18n") or payload.get("name"))
		if payload.get("code"):
			row.code = str(payload["code"]).strip()[:64]
	if "parent_id" in payload:
		row.parent_id = int(payload["parent_id"]) if payload.get("parent_id") else None
	if "sort_order" in payload:
		row.sort_order = int(payload.get("sort_order") or 0)
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"parent_id": row.parent_id,
		"code": row.code,
		"name_i18n": row.name_i18n,
		"title": resolve_i18n(row.name_i18n, lang),
		"is_active": row.is_active,
	}


def archive_to_folder(db: Session, business_id: int, letter_id: int, payload: dict, user_id: int, position_id: int, lang: str = "fa") -> dict:
	from app.services.office_automation_service import archive_letter

	folder_id = payload.get("folder_id") or payload.get("archive_folder_id")
	folder = None
	if folder_id:
		folder = db.query(OaArchiveFolder).filter(OaArchiveFolder.id == int(folder_id), OaArchiveFolder.business_id == business_id).first()
		if not folder:
			raise ApiError("OA_ARCHIVE_FOLDER_NOT_FOUND", "Archive folder was not found.", http_status=404)
	data = archive_letter(db, business_id, letter_id, user_id, position_id, lang=lang)
	if folder:
		letter = _get_letter(db, business_id, letter_id)
		letter.archive_folder_id = folder.id
		db.commit()
		data["archive_folder_id"] = folder.id
	return data


def delay_report(db: Session, business_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	today = date.today()
	rows = (
		db.query(OaReferral, OaLetter, OaPosition)
		.join(OaLetter, OaLetter.id == OaReferral.letter_id)
		.join(OaPosition, OaPosition.id == OaReferral.to_position_id)
		.filter(
			OaReferral.business_id == business_id,
			OaReferral.status.in_(("pending", "seen")),
			OaReferral.due_at.isnot(None),
			OaReferral.due_at < today,
		)
		.order_by(OaReferral.due_at)
		.limit(200)
		.all()
	)
	items = []
	for ref, letter, pos in rows:
		items.append(
			{
				"referral_id": ref.id,
				"letter_id": letter.id,
				"subject": letter.subject,
				"number": letter.secretariat_number,
				"due_at": ref.due_at,
				"days_late": (today - ref.due_at).days if ref.due_at else 0,
				"to_position_id": pos.id,
				"to_position_title": resolve_i18n(pos.name_i18n, lang),
				"status": ref.status,
			}
		)
	return {"items": items, "total": len(items)}


def volume_report(db: Session, business_id: int) -> dict:
	_ensure_plugin(db, business_id)
	by_kind = db.query(OaLetter.letter_kind, func.count(OaLetter.id)).filter(OaLetter.business_id == business_id).group_by(OaLetter.letter_kind).all()
	by_status = db.query(OaLetter.status, func.count(OaLetter.id)).filter(OaLetter.business_id == business_id).group_by(OaLetter.status).all()
	return {
		"by_kind": {k: int(c) for k, c in by_kind},
		"by_status": {k: int(c) for k, c in by_status},
	}


def performance_report(db: Session, business_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	rows = (
		db.query(OaReferral, OaPosition)
		.join(OaPosition, OaPosition.id == OaReferral.to_position_id)
		.filter(OaReferral.business_id == business_id, OaReferral.completed_at.isnot(None))
		.all()
	)
	agg: Dict[int, Dict[str, Any]] = {}
	for ref, pos in rows:
		bucket = agg.setdefault(pos.id, {"title": resolve_i18n(pos.name_i18n, lang), "days": [], "count": 0})
		bucket["count"] += 1
		if ref.completed_at and ref.created_at:
			bucket["days"].append(max((ref.completed_at - ref.created_at).total_seconds() / 86400.0, 0))
	items = [
		{
			"position_id": pid,
			"position_title": data["title"],
			"completed": data["count"],
			"avg_days": round(sum(data["days"]) / len(data["days"]), 2) if data["days"] else 0,
		}
		for pid, data in agg.items()
	]
	return {"items": items}


def public_track(db: Session, token: str) -> dict:
	letter = db.query(OaLetter).filter(OaLetter.tracking_token == token).first()
	if not letter:
		raise ApiError("OA_TRACK_NOT_FOUND", "Letter tracking token was not found.", http_status=404)
	last = (
		db.query(OaReferral)
		.filter(OaReferral.letter_id == letter.id)
		.order_by(OaReferral.updated_at.desc())
		.first()
	)
	hide_subject = letter.confidentiality in {"highly_confidential", "secret"}
	return {
		"number": letter.secretariat_number,
		"letter_date": letter.letter_date,
		"status": letter.status,
		"letter_kind": letter.letter_kind,
		"subject": None if hide_subject else letter.subject,
		"registered_at": letter.registered_at,
		"last_action_at": last.updated_at if last else letter.updated_at,
		"confidentiality": letter.confidentiality,
	}


def ensure_tracking_token(letter: OaLetter) -> str:
	if letter.tracking_token:
		return letter.tracking_token
	letter.tracking_token = secrets.token_urlsafe(16)
	return letter.tracking_token


def import_email_as_letter(
	db: Session,
	business_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
	calendar_type: CalendarType = "jalali",
) -> dict:
	from app.services.office_automation_service import create_letter_draft

	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	subject = str(payload.get("subject") or "").strip() or (payload.get("from_email") or "email")
	created = create_letter_draft(
		db,
		business_id,
		{
			"subject": subject[:500],
			"body": payload.get("body") or "",
			"letter_kind": "incoming",
			"sender_name": payload.get("from_email"),
			"sender_org": payload.get("from_email"),
			"letter_date": payload.get("letter_date"),
		},
		user_id,
		position.id,
		lang=lang,
		calendar_type=calendar_type,
	)
	msg = OaMailboxMessage(
		business_id=business_id,
		letter_id=created["id"],
		direction="in",
		from_email=payload.get("from_email"),
		to_email=payload.get("to_email"),
		subject=subject[:500],
		body=payload.get("body"),
		status="imported",
		message_id=payload.get("message_id"),
		created_at=_now(),
	)
	db.add(msg)
	db.commit()
	return get_letter(db, business_id, created["id"], user_id, position.id, lang=lang, is_admin=True)


def send_letter_email(
	db: Session,
	business_id: int,
	letter_id: int,
	payload: dict,
	user_id: int,
	position_id: int,
	lang: str = "fa",
) -> dict:
	letter_data = get_letter(db, business_id, letter_id, user_id, position_id, lang=lang, is_admin=True)
	letter = _get_letter(db, business_id, letter_id)
	to_email = str(payload.get("to_email") or "").strip()
	if not to_email:
		raise ApiError("VALIDATION_ERROR", "Destination email is required.", http_status=400)
	from app.services.email_service import EmailService

	ok = EmailService(db).send_email(
		to=to_email,
		subject=letter.subject,
		body=letter.body or letter.subject,
		html_body=letter.body if letter.body_format == "html" else None,
	)
	msg = OaMailboxMessage(
		business_id=business_id,
		letter_id=letter.id,
		direction="out",
		to_email=to_email,
		subject=letter.subject,
		body=letter.body,
		status="sent" if ok else "failed",
		created_at=_now(),
	)
	db.add(msg)
	db.commit()
	if not ok:
		raise ApiError("OA_EMAIL_SEND_FAILED", "Letter email could not be sent.", http_status=502)
	letter_data["email_status"] = "sent"
	return letter_data


def extract_attachment_text(file_row: FileStorage) -> str:
	data = _read_file_bytes(file_row)
	if not data:
		return ""
	name = file_row.original_name or "file.bin"
	mime = file_row.mime_type or ""
	try:
		from app.services.ai.ai_attachment_service import extract_text_from_bytes

		return extract_text_from_bytes(name, data, mime)
	except Exception:
		pass
	if mime.startswith("image/") or name.lower().endswith((".png", ".jpg", ".jpeg", ".tif", ".tiff")):
		try:
			import pytesseract
			from PIL import Image
			import io

			img = Image.open(io.BytesIO(data))
			return pytesseract.image_to_string(img, lang="fas+eng") or ""
		except Exception:
			logger.debug("OCR image extract skipped", exc_info=True)
	return ""


def refresh_letter_search_text(db: Session, letter: OaLetter) -> None:
	parts = [letter.subject or "", letter.body or "", letter.ocr_text or "", letter.keywords or ""]
	atts = db.query(OaLetterAttachment).filter(OaLetterAttachment.letter_id == letter.id).all()
	for att in atts:
		if att.ocr_text:
			parts.append(att.ocr_text)
	letter.search_text = "\n".join(p for p in parts if p)[:20000]


def ocr_letter_attachments(
	db: Session,
	business_id: int,
	letter_id: int,
	user_id: int,
	position_id: int,
	lang: str = "fa",
) -> dict:
	get_letter(db, business_id, letter_id, user_id, position_id, lang=lang, is_admin=True)
	letter = _get_letter(db, business_id, letter_id)
	atts = (
		db.query(OaLetterAttachment, FileStorage)
		.outerjoin(FileStorage, FileStorage.id == OaLetterAttachment.file_storage_id)
		.filter(OaLetterAttachment.letter_id == letter.id)
		.all()
	)
	collected = []
	for att, frow in atts:
		text = extract_attachment_text(frow) if frow else ""
		att.ocr_text = text or att.ocr_text
		if text:
			collected.append(text)
	letter.ocr_text = "\n".join(collected)[:20000] if collected else letter.ocr_text
	refresh_letter_search_text(db, letter)
	db.commit()
	return get_letter(db, business_id, letter.id, user_id, position_id, lang=lang, is_admin=True)


def summarize_letter(
	db: Session,
	business_id: int,
	letter_id: int,
	user_id: int,
	position_id: int,
	lang: str = "fa",
) -> dict:
	data = get_letter(db, business_id, letter_id, user_id, position_id, lang=lang, is_admin=True)
	letter = _get_letter(db, business_id, letter_id)
	source = " ".join(p for p in (letter.subject, letter.body, letter.ocr_text) if p)
	if not source.strip():
		raise ApiError("OA_EMPTY_LETTER", "Letter has no text to summarize.", http_status=400)
	summary = ""
	try:
		from app.services.ai.ai_service import AIService

		ai = AIService(db=db, user_id=user_id, business_id=business_id)
		prompt = (
			"Summarize this official letter in the same language as the source. "
			"Return 3 to 6 short bullet points of the request, deadline, and action needed.\n\n"
			+ source[:8000]
		)
		result = ai.chat_completion_sync(
			messages=[{"role": "user", "content": prompt}],
			use_function_calling=False,
			max_tokens_override=400,
			session_business_id=business_id,
		)
		summary = str((result or {}).get("content") or (result or {}).get("message") or "").strip()
	except Exception:
		logger.debug("OA AI summary fallback", exc_info=True)
	if not summary:
		words = source.split()
		summary = " ".join(words[:80]) + ("…" if len(words) > 80 else "")
	letter.ai_summary = summary[:4000]
	db.commit()
	data["ai_summary"] = letter.ai_summary
	return data


def _due_already_sent(letter: OaLetter, key: str, today_iso: str) -> bool:
	extra = dict(letter.extra_info or {})
	bag = dict(extra.get("due_notified") or {})
	return bag.get(key) == today_iso


def _mark_due_sent(letter: OaLetter, key: str, today_iso: str) -> None:
	from sqlalchemy.orm.attributes import flag_modified

	extra = dict(letter.extra_info or {})
	bag = dict(extra.get("due_notified") or {})
	bag[key] = today_iso
	extra["due_notified"] = bag
	letter.extra_info = extra
	flag_modified(letter, "extra_info")


def _holder_user_ids(db: Session, business_id: int, position_id: Optional[int]) -> set[int]:
	if not position_id:
		return set()
	now = _now()
	ids = {
		r[0]
		for r in db.query(OaPositionHolder.user_id)
		.filter(OaPositionHolder.position_id == position_id, OaPositionHolder.business_id == business_id)
		.filter(_occupancy_filter(now))
		.all()
	}
	return {int(uid) for uid in ids if uid}


def _notify_letter_event(
	db: Session,
	business_id: int,
	letter: OaLetter,
	event_key: str,
	*,
	position_ids: Optional[Sequence[int]] = None,
	user_ids: Optional[Sequence[int]] = None,
) -> int:
	sent = 0
	try:
		from app.services.notification_service import NotificationService
		from adapters.db.models.business import Business

		svc = NotificationService(db)
		uids = set(int(u) for u in (user_ids or []) if u)
		for pid in position_ids or []:
			uids |= _holder_user_ids(db, business_id, pid)
		bname = db.query(Business.name).filter(Business.id == business_id).scalar() or ""
		for uid in uids:
			try:
				svc.send(
					user_id=int(uid),
					event_key=event_key,
					context={
						"subject": letter.subject,
						"number": letter.secretariat_number or "",
						"letter_id": letter.id,
						"business_name": bname,
					},
					preferred_channels=["inapp", "sms", "email"],
				)
				sent += 1
			except Exception:
				logger.debug("OA event notify failed for user %s", uid, exc_info=True)
	except Exception:
		logger.debug("OA event notify skipped", exc_info=True)
	return sent


def notify_due_followups(db: Session, business_id: Optional[int] = None) -> dict:
	today = date.today()
	today_iso = today.isoformat()
	letter_q = db.query(OaLetter).filter(
		OaLetter.follow_up_at.isnot(None),
		OaLetter.follow_up_at <= today,
		OaLetter.status.in_(("registered", "in_circulation", "closed")),
	)
	if business_id:
		letter_q = letter_q.filter(OaLetter.business_id == business_id)
	letters = letter_q.all()
	ref_q = (
		db.query(OaReferral, OaLetter)
		.join(OaLetter, OaLetter.id == OaReferral.letter_id)
		.filter(
			OaReferral.status.in_(("pending", "seen")),
			OaReferral.due_at.isnot(None),
			OaReferral.due_at <= today,
			OaLetter.status.in_(("registered", "in_circulation", "closed")),
		)
	)
	if business_id:
		ref_q = ref_q.filter(OaReferral.business_id == business_id)
	referrals = ref_q.all()
	sent = 0
	due_letters = 0
	due_referrals = 0
	for letter in letters:
		key = f"followup:{today_iso}"
		if _due_already_sent(letter, key, today_iso):
			continue
		due_letters += 1
		sent += _notify_letter_event(
			db,
			letter.business_id,
			letter,
			"office_automation.letter_followup_due",
			position_ids=[letter.origin_position_id],
		)
		_mark_due_sent(letter, key, today_iso)
	for ref, letter in referrals:
		key = f"ref:{ref.id}:{today_iso}"
		if _due_already_sent(letter, key, today_iso):
			continue
		due_referrals += 1
		sent += _notify_letter_event(
			db,
			letter.business_id,
			letter,
			"office_automation.letter_followup_due",
			position_ids=[ref.to_position_id, letter.origin_position_id],
		)
		_mark_due_sent(letter, key, today_iso)
	return {"due_letters": due_letters, "due_referrals": due_referrals, "notifications": sent}


def enrich_letter_payload(db: Session, data: dict, letter: OaLetter, lang: str) -> dict:
	data["secretariat_id"] = letter.secretariat_id
	data["external_org_id"] = letter.external_org_id
	data["archive_folder_id"] = letter.archive_folder_id
	data["tracking_token"] = letter.tracking_token
	data["receipt_number"] = letter.receipt_number
	data["receipt_date"] = letter.receipt_date
	data["sign_status"] = letter.sign_status or "none"
	data["keywords"] = letter.keywords
	data["ai_summary"] = letter.ai_summary
	data["ocr_text"] = letter.ocr_text
	if letter.person_id:
		person = db.query(Person).filter(Person.id == letter.person_id).first()
		if person:
			data["person_title"] = _person_title(person)
	if letter.external_org_id:
		org = db.query(OaExternalOrg).filter(OaExternalOrg.id == letter.external_org_id).first()
		if org:
			data["external_org_title"] = resolve_i18n(org.name_i18n, lang)
			data["external_org_ece_email"] = org.ece_email
	if letter.secretariat_id:
		sec = db.query(OaSecretariat).filter(OaSecretariat.id == letter.secretariat_id).first()
		if sec:
			data["secretariat_title"] = resolve_i18n(sec.name_i18n, lang)
	steps = (
		db.query(OaLetterSignStep, OaPosition)
		.join(OaPosition, OaPosition.id == OaLetterSignStep.position_id)
		.filter(OaLetterSignStep.letter_id == letter.id)
		.order_by(OaLetterSignStep.sort_order, OaLetterSignStep.id)
		.all()
	)
	data["sign_steps"] = [
		{
			"id": s.id,
			"position_id": s.position_id,
			"position_title": resolve_i18n(pos.name_i18n, lang),
			"status": s.status,
			"is_required": s.is_required,
			"image_file_id": s.image_file_id,
			"note": s.note,
			"signed_at": s.signed_at,
			"signed_by_user_id": s.signed_by_user_id,
		}
		for s, pos in steps
	]
	dispatches = db.query(OaDispatch).filter(OaDispatch.letter_id == letter.id).order_by(OaDispatch.created_at).all()
	data["dispatches"] = [
		{
			"id": d.id,
			"from_position_id": d.from_position_id,
			"to_position_id": d.to_position_id,
			"status": d.status,
			"instruction": d.instruction,
			"created_at": d.created_at,
			"acknowledged_at": d.acknowledged_at,
		}
		for d in dispatches
	]
	return data
