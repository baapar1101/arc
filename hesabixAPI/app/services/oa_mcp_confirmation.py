"""تأیید عمل پرریسک اتوماسیون از نشست کاربر. آرگومان MCP خودش مجوز اجرا نیست."""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta
from typing import Any, Optional

from sqlalchemy.orm import Session

from adapters.db.models.oa_mcp_confirmation import OaMcpConfirmation
from adapters.db.models.office_automation import OaAuditLog
from app.core.responses import ApiError

_CLASSIFIED = frozenset({"confidential", "highly_confidential", "secret"})
_DRAFT_TOOLS = frozenset({"create_oa_letter_draft", "update_oa_letter_draft"})
_TTL = timedelta(minutes=30)
_LABELS = {
	"register_oa_letter": "ثبت نامه",
	"delete_oa_letter_draft": "حذف پیش‌نویس",
	"sign_oa_letter": "امضای تصویر نامه",
	"start_oa_sign_path": "شروع مسیر امضا",
	"dispatch_oa_letter": "ابلاغ نامه",
	"send_oa_email_letter": "ارسال ایمیل نامه",
	"send_oa_ece": "ارسال ECE",
	"import_oa_ece": "ورود ECE",
	"assign_oa_position_holder": "واگذاری سمت",
	"delete_oa_letter_format": "حذف فرمت نامه",
	"delete_oa_letter_template": "حذف قالب نامه",
	"create_oa_letter_draft": "پیش‌نویس طبقه‌بندی‌شده",
	"update_oa_letter_draft": "تغییر محرمانگی پیش‌نویس",
}


def _now() -> datetime:
	return datetime.utcnow()


def _canonical(value: Any) -> str:
	return json.dumps(value or {}, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)


def _hash(value: Any) -> str:
	return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _classified_draft(tool_name: str, arguments: dict) -> bool:
	if tool_name not in _DRAFT_TOOLS:
		return False
	payload = arguments.get("payload")
	if not isinstance(payload, dict):
		return False
	return str(payload.get("confidentiality") or "") in _CLASSIFIED


def oa_tool_needs_server_confirmation(func: Any, tool_name: str, arguments: dict) -> bool:
	if func is None or getattr(func, "category", None) != "office_automation":
		return False
	if getattr(func, "risk_level", None) in ("medium", "high"):
		return True
	return _classified_draft(tool_name, arguments)


def _summary(tool_name: str, arguments: dict) -> str:
	parts = [_LABELS.get(tool_name, tool_name)]
	for key in ("letter_id", "document_id", "to_position_id", "as_position_id"):
		if arguments.get(key) not in (None, ""):
			parts.append(f"{key}={arguments[key]}")
	payload = arguments.get("payload")
	if isinstance(payload, dict) and payload.get("confidentiality"):
		parts.append(f"confidentiality={payload['confidentiality']}")
	return " · ".join(parts)[:300]


def _public(row: OaMcpConfirmation) -> dict:
	return {
		"id": row.id,
		"tool_name": row.tool_name,
		"summary": row.summary,
		"status": row.status,
		"created_at": row.created_at,
		"expires_at": row.expires_at,
	}


def _audit(db: Session, row: OaMcpConfirmation, user_id: int, action: str) -> None:
	db.add(
		OaAuditLog(
			business_id=row.business_id,
			user_id=user_id,
			action=action,
			payload={"confirmation_id": row.id, "tool_name": row.tool_name},
			created_at=_now(),
		)
	)


def gate_sensitive_oa_call(
	db: Session,
	registry: Any,
	tool_name: str,
	arguments: dict,
	*,
	user_id: int,
	business_id: int,
	connection_id: Optional[int],
	confirmation_id: Any = None,
) -> Optional[dict]:
	"""None یعنی ابزار مجاز است اجرا شود. دیکشنری یعنی اجرا نشده است."""
	func = registry.get_function(tool_name) if registry is not None else None
	if not oa_tool_needs_server_confirmation(func, tool_name, arguments):
		return None
	digest = _hash(arguments)
	if confirmation_id not in (None, ""):
		return _consume(db, int(confirmation_id), user_id, business_id, tool_name, digest)
	return _issue(db, user_id, business_id, connection_id, tool_name, arguments, digest)


def _issue(db: Session, user_id: int, business_id: int, connection_id: Optional[int], tool_name: str, arguments: dict, digest: str) -> dict:
	now = _now()
	existing = (
		db.query(OaMcpConfirmation)
		.filter(
			OaMcpConfirmation.business_id == business_id,
			OaMcpConfirmation.user_id == user_id,
			OaMcpConfirmation.tool_name == tool_name,
			OaMcpConfirmation.arguments_hash == digest,
			OaMcpConfirmation.status == "pending",
			OaMcpConfirmation.expires_at > now,
		)
		.order_by(OaMcpConfirmation.id.desc())
		.first()
	)
	if existing is None:
		existing = OaMcpConfirmation(
			business_id=business_id,
			user_id=user_id,
			connection_id=connection_id,
			tool_name=tool_name,
			arguments_hash=digest,
			arguments_json=dict(arguments),
			summary=_summary(tool_name, arguments),
			status="pending",
			created_at=now,
			expires_at=now + _TTL,
		)
		db.add(existing)
		db.flush()
		_audit(db, existing, user_id, "mcp.confirmation.request")
	db.commit()
	db.refresh(existing)
	return {
		"error": "OA_CONFIRMATION_REQUIRED",
		"confirmation_id": existing.id,
		"summary": existing.summary,
		"expires_at": existing.expires_at,
		"message": "این عمل تا تأیید شما در میز کار اتوماسیون اداری اجرا نمی‌شود.",
	}


def _consume(db: Session, confirmation_id: int, user_id: int, business_id: int, tool_name: str, digest: str) -> Optional[dict]:
	row = (
		db.query(OaMcpConfirmation)
		.filter(OaMcpConfirmation.id == confirmation_id, OaMcpConfirmation.business_id == business_id, OaMcpConfirmation.user_id == user_id)
		.first()
	)
	if row is None:
		return {"error": "OA_CONFIRMATION_NOT_FOUND", "message": "تأیید پیدا نشد."}
	if row.expires_at <= _now():
		return {"error": "OA_CONFIRMATION_EXPIRED", "confirmation_id": row.id, "message": "مهلت تأیید تمام شده است."}
	if row.tool_name != tool_name or row.arguments_hash != digest:
		return {"error": "OA_CONFIRMATION_MISMATCH", "confirmation_id": row.id, "message": "آرگومان‌ها با عمل تأییدشده یکی نیست."}
	if row.status == "pending":
		return {"error": "OA_CONFIRMATION_PENDING", "confirmation_id": row.id, "message": "این عمل هنوز در میز کار تأیید نشده است."}
	if row.status != "approved":
		return {"error": "OA_CONFIRMATION_CLOSED", "confirmation_id": row.id, "message": "این تأیید دیگر قابل استفاده نیست."}
	updated = (
		db.query(OaMcpConfirmation)
		.filter(OaMcpConfirmation.id == row.id, OaMcpConfirmation.status == "approved")
		.update({"status": "consumed", "consumed_at": _now()}, synchronize_session=False)
	)
	if updated != 1:
		db.rollback()
		return {"error": "OA_CONFIRMATION_CLOSED", "confirmation_id": row.id, "message": "این تأیید دیگر قابل استفاده نیست."}
	db.expire(row)
	db.flush()
	_audit(db, row, user_id, "mcp.confirmation.consume")
	return None


def list_confirmations(db: Session, business_id: int, user_id: int) -> dict:
	now = _now()
	rows = (
		db.query(OaMcpConfirmation)
		.filter(
			OaMcpConfirmation.business_id == business_id,
			OaMcpConfirmation.user_id == user_id,
			OaMcpConfirmation.status.in_(("pending", "approved")),
			OaMcpConfirmation.expires_at > now,
		)
		.order_by(OaMcpConfirmation.id.desc())
		.limit(30)
		.all()
	)
	return {"items": [_public(row) for row in rows]}


def decide_confirmation(db: Session, business_id: int, user_id: int, confirmation_id: int, *, accept: bool, via_mcp: bool = False) -> dict:
	if via_mcp:
		raise ApiError("OA_CONFIRMATION_CHANNEL", "An MCP connection cannot approve its own sensitive action.", http_status=403)
	row = (
		db.query(OaMcpConfirmation)
		.filter(OaMcpConfirmation.id == confirmation_id, OaMcpConfirmation.business_id == business_id, OaMcpConfirmation.user_id == user_id)
		.first()
	)
	if row is None:
		raise ApiError("OA_CONFIRMATION_NOT_FOUND", "Confirmation was not found.", http_status=404)
	if row.expires_at <= _now():
		raise ApiError("OA_CONFIRMATION_EXPIRED", "Confirmation has expired.", http_status=400)
	if row.status != "pending":
		raise ApiError("OA_CONFIRMATION_CLOSED", "Confirmation is already decided.", http_status=400)
	row.status = "approved" if accept else "rejected"
	row.decided_at = _now()
	_audit(db, row, user_id, "mcp.confirmation.approve" if accept else "mcp.confirmation.reject")
	db.commit()
	db.refresh(row)
	return _public(row)
