"""Business logic for barcode label templates."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.barcode_label_settings import BarcodeLabelSettings
from adapters.db.models.label_template import LabelTemplate, LabelTemplateRevision
from app.core.responses import ApiError
from app.services.barcode_label_design_validator import (
	design_warnings,
	sample_print_context,
	validate_design_json,
	validate_sheet_json,
)
from app.services.barcode_label_presets import (
	default_sheet,
	empty_design,
	get_preset,
	list_presets,
)

_DEFAULT_PRINTER_SETTINGS: Dict[str, Any] = {
	"printer_profiles": [],
	"active_profile_id": None,
}

_ALLOWED_PRINTER_MODES = frozenset({"pdf_spooler", "zpl", "escpos"})
_ALLOWED_CONNECTIONS = frozenset({"system_default", "tcp", "usb", "ble"})


def _summary(row: LabelTemplate) -> Dict[str, Any]:
	canvas = (row.design_json or {}).get("canvas") or {}
	return {
		"id": row.id,
		"name": row.name,
		"description": row.description,
		"status": row.status,
		"is_default": bool(row.is_default),
		"version": row.version,
		"schema_version": row.schema_version,
		"canvas_width_mm": canvas.get("width_mm"),
		"canvas_height_mm": canvas.get("height_mm"),
		"created_at": row.created_at,
		"updated_at": row.updated_at,
		"published_at": row.published_at,
	}


def _detail(row: LabelTemplate) -> Dict[str, Any]:
	data = _summary(row)
	data["design_json"] = row.design_json
	data["sheet_json"] = row.sheet_json
	data["warnings"] = design_warnings(row.design_json or {})
	return data


def list_templates(
	db: Session,
	business_id: int,
	*,
	status: Optional[str] = None,
	q: Optional[str] = None,
	for_print_only: bool = False,
) -> Dict[str, Any]:
	query = db.query(LabelTemplate).filter(LabelTemplate.business_id == business_id)
	if for_print_only:
		query = query.filter(LabelTemplate.status == "published")
	elif status and status != "all":
		query = query.filter(LabelTemplate.status == status)
	if q:
		like = f"%{q.strip()}%"
		query = query.filter(LabelTemplate.name.ilike(like))
	rows = query.order_by(LabelTemplate.is_default.desc(), LabelTemplate.updated_at.desc()).all()
	return {"items": [_summary(r) for r in rows]}


def get_template(db: Session, business_id: int, template_id: int) -> Dict[str, Any]:
	row = (
		db.query(LabelTemplate)
		.filter(LabelTemplate.business_id == business_id, LabelTemplate.id == template_id)
		.first()
	)
	if not row:
		raise ApiError("TEMPLATE_NOT_FOUND", "Label template not found", http_status=404)
	return _detail(row)


def create_template(
	db: Session,
	business_id: int,
	*,
	name: str,
	description: Optional[str],
	design_json: Optional[Dict[str, Any]],
	sheet_json: Optional[Dict[str, Any]],
	user_id: Optional[int],
) -> Dict[str, Any]:
	design = validate_design_json(design_json or empty_design())
	sheet = validate_sheet_json(sheet_json or default_sheet())
	name_clean = (name or "").strip() or "طرح جدید"
	row = LabelTemplate(
		business_id=business_id,
		name=name_clean[:160],
		description=(description or None),
		status="draft",
		is_default=False,
		version=1,
		schema_version=1,
		design_json=design,
		sheet_json=sheet,
		created_by=user_id,
		created_at=datetime.utcnow(),
		updated_at=datetime.utcnow(),
	)
	db.add(row)
	db.flush()
	_add_revision(db, row, changelog="created", user_id=user_id)
	db.commit()
	db.refresh(row)
	return _detail(row)


def update_template(
	db: Session,
	business_id: int,
	template_id: int,
	*,
	payload: Dict[str, Any],
	user_id: Optional[int],
) -> Dict[str, Any]:
	row = (
		db.query(LabelTemplate)
		.filter(LabelTemplate.business_id == business_id, LabelTemplate.id == template_id)
		.first()
	)
	if not row:
		raise ApiError("TEMPLATE_NOT_FOUND", "Label template not found", http_status=404)
	if row.status == "archived":
		raise ApiError("TEMPLATE_ARCHIVED", "Cannot edit archived template", http_status=409)

	if "name" in payload and payload["name"] is not None:
		row.name = str(payload["name"]).strip()[:160] or row.name
	if "description" in payload:
		row.description = payload["description"]
	if "design_json" in payload and payload["design_json"] is not None:
		row.design_json = validate_design_json(payload["design_json"])
	if "sheet_json" in payload and payload["sheet_json"] is not None:
		row.sheet_json = validate_sheet_json(payload["sheet_json"])

	row.version = int(row.version or 1) + 1
	row.updated_at = datetime.utcnow()
	_add_revision(db, row, changelog=payload.get("changelog") or "updated", user_id=user_id)
	db.commit()
	db.refresh(row)
	return _detail(row)


def publish_template(
	db: Session, business_id: int, template_id: int, *, user_id: Optional[int]
) -> Dict[str, Any]:
	row = (
		db.query(LabelTemplate)
		.filter(LabelTemplate.business_id == business_id, LabelTemplate.id == template_id)
		.first()
	)
	if not row:
		raise ApiError("TEMPLATE_NOT_FOUND", "Label template not found", http_status=404)
	if row.status == "archived":
		raise ApiError("TEMPLATE_ARCHIVED", "Cannot publish archived template", http_status=409)
	# re-validate strictly
	row.design_json = validate_design_json(row.design_json, strict_publish=True)
	row.sheet_json = validate_sheet_json(row.sheet_json)
	row.status = "published"
	row.published_at = datetime.utcnow()
	row.updated_at = datetime.utcnow()
	row.version = int(row.version or 1) + 1
	_add_revision(db, row, changelog="published", user_id=user_id)
	db.commit()
	db.refresh(row)
	return _detail(row)


def archive_template(
	db: Session, business_id: int, template_id: int, *, user_id: Optional[int]
) -> Dict[str, Any]:
	row = (
		db.query(LabelTemplate)
		.filter(LabelTemplate.business_id == business_id, LabelTemplate.id == template_id)
		.first()
	)
	if not row:
		raise ApiError("TEMPLATE_NOT_FOUND", "Label template not found", http_status=404)
	row.status = "archived"
	row.is_default = False
	row.updated_at = datetime.utcnow()
	row.version = int(row.version or 1) + 1
	_add_revision(db, row, changelog="archived", user_id=user_id)
	db.commit()
	db.refresh(row)
	return _detail(row)


def duplicate_template(
	db: Session, business_id: int, template_id: int, *, user_id: Optional[int]
) -> Dict[str, Any]:
	src = (
		db.query(LabelTemplate)
		.filter(LabelTemplate.business_id == business_id, LabelTemplate.id == template_id)
		.first()
	)
	if not src:
		raise ApiError("TEMPLATE_NOT_FOUND", "Label template not found", http_status=404)
	name = f"کپی {src.name}"[:160]
	return create_template(
		db,
		business_id,
		name=name,
		description=src.description,
		design_json=src.design_json,
		sheet_json=src.sheet_json,
		user_id=user_id,
	)


def set_default_template(db: Session, business_id: int, template_id: int) -> Dict[str, Any]:
	row = (
		db.query(LabelTemplate)
		.filter(LabelTemplate.business_id == business_id, LabelTemplate.id == template_id)
		.first()
	)
	if not row:
		raise ApiError("TEMPLATE_NOT_FOUND", "Label template not found", http_status=404)
	if row.status != "published":
		raise ApiError(
			"DEFAULT_REQUIRES_PUBLISHED",
			"Only published templates can be set as default",
			http_status=409,
		)
	db.query(LabelTemplate).filter(
		LabelTemplate.business_id == business_id,
		LabelTemplate.is_default == True,  # noqa: E712
	).update({"is_default": False})
	row.is_default = True
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return _detail(row)


def get_default_template(db: Session, business_id: int) -> Dict[str, Any]:
	row = (
		db.query(LabelTemplate)
		.filter(
			LabelTemplate.business_id == business_id,
			LabelTemplate.status == "published",
			LabelTemplate.is_default == True,  # noqa: E712
		)
		.first()
	)
	if not row:
		raise ApiError("DEFAULT_NOT_FOUND", "No default label template", http_status=404)
	return _detail(row)


def create_from_preset(
	db: Session,
	business_id: int,
	*,
	preset_code: str,
	name: Optional[str],
	user_id: Optional[int],
) -> Dict[str, Any]:
	preset = get_preset(preset_code)
	if not preset:
		raise ApiError("PRESET_NOT_FOUND", f"Unknown preset: {preset_code}", http_status=404)
	return create_template(
		db,
		business_id,
		name=(name or preset["name"]),
		description=preset.get("description"),
		design_json=preset["design_json"],
		sheet_json=preset["sheet_json"],
		user_id=user_id,
	)


def list_template_revisions(db: Session, business_id: int, template_id: int) -> Dict[str, Any]:
	row = (
		db.query(LabelTemplate)
		.filter(LabelTemplate.business_id == business_id, LabelTemplate.id == template_id)
		.first()
	)
	if not row:
		raise ApiError("TEMPLATE_NOT_FOUND", "Label template not found", http_status=404)
	revs = (
		db.query(LabelTemplateRevision)
		.filter(LabelTemplateRevision.template_id == template_id)
		.order_by(LabelTemplateRevision.version_no.desc())
		.limit(50)
		.all()
	)
	return {
		"items": [
			{
				"id": r.id,
				"version_no": r.version_no,
				"changelog": r.changelog,
				"created_at": r.created_at,
				"created_by": r.created_by,
			}
			for r in revs
		]
	}


def get_sample_context() -> Dict[str, Any]:
	return sample_print_context()


def presets_catalog() -> Dict[str, Any]:
	return {"items": list_presets()}


def get_printer_settings(db: Session, business_id: int) -> Dict[str, Any]:
	row = (
		db.query(BarcodeLabelSettings)
		.filter(BarcodeLabelSettings.business_id == business_id)
		.first()
	)
	if not row or not isinstance(row.settings_json, dict):
		return dict(_DEFAULT_PRINTER_SETTINGS)
	data = dict(row.settings_json)
	data.setdefault("printer_profiles", [])
	data.setdefault("active_profile_id", None)
	return data


def upsert_printer_settings(
	db: Session, business_id: int, payload: Dict[str, Any]
) -> Dict[str, Any]:
	profiles_raw = payload.get("printer_profiles") or []
	if not isinstance(profiles_raw, list):
		raise ApiError("INVALID_PROFILES", "printer_profiles must be a list", http_status=400)
	if len(profiles_raw) > 50:
		raise ApiError("TOO_MANY_PROFILES", "Maximum 50 printer profiles", http_status=400)

	normalized: List[Dict[str, Any]] = []
	seen_ids: set[str] = set()
	for i, raw in enumerate(profiles_raw):
		if not isinstance(raw, dict):
			raise ApiError("INVALID_PROFILE", f"Profile #{i + 1} is invalid", http_status=400)
		pid = str(raw.get("id") or "").strip()
		name = str(raw.get("name") or "").strip()
		mode = str(raw.get("mode") or "pdf_spooler").strip().lower()
		connection = str(raw.get("connection") or "system_default").strip().lower()
		if not pid or not name:
			raise ApiError("INVALID_PROFILE", f"Profile #{i + 1} needs id and name", http_status=400)
		if pid in seen_ids:
			raise ApiError("DUPLICATE_PROFILE_ID", f"Duplicate profile id: {pid}", http_status=400)
		if mode not in _ALLOWED_PRINTER_MODES:
			raise ApiError("INVALID_MODE", f"Unsupported mode: {mode}", http_status=400)
		if connection not in _ALLOWED_CONNECTIONS:
			raise ApiError(
				"INVALID_CONNECTION", f"Unsupported connection: {connection}", http_status=400
			)
		seen_ids.add(pid)
		host = raw.get("host")
		port = raw.get("port")
		normalized.append(
			{
				"id": pid[:64],
				"name": name[:120],
				"mode": mode,
				"connection": connection,
				"host": (str(host).strip()[:255] if host else None) or None,
				"port": int(port) if port is not None and str(port).strip() != "" else None,
				"label_width_mm": float(raw.get("label_width_mm") or 50),
				"label_height_mm": float(raw.get("label_height_mm") or 30),
				"dpi": int(raw.get("dpi") or 203),
				"enabled": bool(raw.get("enabled", True)),
			}
		)

	active_id = payload.get("active_profile_id")
	active_id = str(active_id).strip() if active_id else None
	if active_id and active_id not in seen_ids:
		raise ApiError("ACTIVE_NOT_FOUND", "active_profile_id not in profiles", http_status=400)

	settings = {
		"printer_profiles": normalized,
		"active_profile_id": active_id,
	}
	now = datetime.utcnow()
	row = (
		db.query(BarcodeLabelSettings)
		.filter(BarcodeLabelSettings.business_id == business_id)
		.first()
	)
	if row:
		row.settings_json = settings
		row.updated_at = now
	else:
		row = BarcodeLabelSettings(
			business_id=business_id,
			settings_json=settings,
			created_at=now,
			updated_at=now,
		)
		db.add(row)
	db.commit()
	db.refresh(row)
	return dict(row.settings_json)


def _add_revision(
	db: Session, row: LabelTemplate, *, changelog: str, user_id: Optional[int]
) -> None:
	db.add(
		LabelTemplateRevision(
			template_id=row.id,
			version_no=int(row.version or 1),
			design_json=row.design_json,
			sheet_json=row.sheet_json,
			changelog=changelog[:512] if changelog else None,
			created_by=user_id,
			created_at=datetime.utcnow(),
		)
	)
