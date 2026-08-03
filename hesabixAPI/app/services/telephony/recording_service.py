"""مدل‌های DLQ/متریک را از models می‌گیرد — منطق در همین ماژول."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.telephony import (
	TelephonyCall,
	TelephonyEventDeadLetter,
	TelephonyMetricCounter,
)
from app.core.permissions import has_business_permission_for_business
from app.core.responses import ApiError


def bump_metric(db: Session, business_id: int, key: str, delta: int = 1) -> None:
	row = (
		db.query(TelephonyMetricCounter)
		.filter(TelephonyMetricCounter.business_id == business_id, TelephonyMetricCounter.metric_key == key)
		.first()
	)
	now = datetime.utcnow()
	if not row:
		row = TelephonyMetricCounter(business_id=business_id, metric_key=key, value=delta, updated_at=now)
		db.add(row)
	else:
		row.value = int(row.value or 0) + delta
		row.updated_at = now


def push_dead_letter(
	db: Session,
	*,
	business_id: int,
	pbx_id: Optional[int],
	payload: Dict[str, Any],
	error: str,
) -> None:
	db.add(
		TelephonyEventDeadLetter(
			business_id=business_id,
			pbx_id=pbx_id,
			event_id=str(payload.get("event_id") or "") or None,
			payload=payload,
			error_message=error[:2000],
			created_at=datetime.utcnow(),
		)
	)
	bump_metric(db, business_id, "events_failed")


def list_dead_letters(db: Session, business_id: int, *, only_open: bool = True, limit: int = 50) -> List[Dict[str, Any]]:
	q = db.query(TelephonyEventDeadLetter).filter(TelephonyEventDeadLetter.business_id == business_id)
	if only_open:
		q = q.filter(TelephonyEventDeadLetter.resolved == False)  # noqa: E712
	rows = q.order_by(TelephonyEventDeadLetter.created_at.desc()).limit(min(limit, 200)).all()
	return [
		{
			"id": r.id,
			"pbx_id": r.pbx_id,
			"event_id": r.event_id,
			"error_message": r.error_message,
			"payload": r.payload,
			"resolved": bool(r.resolved),
			"created_at": r.created_at.isoformat() if r.created_at else None,
		}
		for r in rows
	]


def resolve_dead_letter(db: Session, business_id: int, dlq_id: int) -> Dict[str, Any]:
	row = (
		db.query(TelephonyEventDeadLetter)
		.filter(TelephonyEventDeadLetter.id == dlq_id, TelephonyEventDeadLetter.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "DLQ یافت نشد.", http_status=404)
	row.resolved = True
	row.resolved_at = datetime.utcnow()
	db.commit()
	return {"ok": True, "id": dlq_id}


def metrics_summary(db: Session, business_id: int) -> Dict[str, Any]:
	rows = db.query(TelephonyMetricCounter).filter(TelephonyMetricCounter.business_id == business_id).all()
	return {
		"business_id": business_id,
		"metrics": {r.metric_key: r.value for r in rows},
		"open_dlq": db.query(TelephonyEventDeadLetter)
		.filter(
			TelephonyEventDeadLetter.business_id == business_id,
			TelephonyEventDeadLetter.resolved == False,  # noqa: E712
		)
		.count(),
	}


def apply_recording_meta(
	db: Session,
	call: TelephonyCall,
	payload: Dict[str, Any],
) -> TelephonyCall:
	call.recording_status = "available"
	call.recording_remote_path = payload.get("recording_path") or call.recording_remote_path
	call.recording_url = payload.get("recording_url") or call.recording_url
	if payload.get("file_storage_id"):
		try:
			call.recording_file_storage_id = int(payload["file_storage_id"])
		except Exception:
			pass
	call.updated_at = datetime.utcnow()
	return call


def assert_can_listen(auth_ctx, db: Session, business_id: int) -> None:
	from adapters.db.models.telephony import TelephonySettings

	settings = (
		db.query(TelephonySettings).filter(TelephonySettings.business_id == business_id).first()
	)
	mode = (settings.recording_access_mode if settings else None) or "permission_based"
	if mode == "all_operators":
		if has_business_permission_for_business(auth_ctx, db, business_id, "telephony", "view") or has_business_permission_for_business(
			auth_ctx, db, business_id, "telephony", "listen_recordings"
		):
			return
		raise ApiError("FORBIDDEN", "مجوز گوش دادن به ضبط مکالمه را ندارید.", http_status=403)
	if not has_business_permission_for_business(auth_ctx, db, business_id, "telephony", "listen_recordings"):
		raise ApiError("FORBIDDEN", "مجوز گوش دادن به ضبط مکالمه را ندارید.", http_status=403)


def recording_info(db: Session, business_id: int, call_id: int) -> Dict[str, Any]:
	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not call:
		raise ApiError("NOT_FOUND", "تماس یافت نشد.", http_status=404)
	return {
		"call_id": call.id,
		"recording_status": call.recording_status,
		"recording_url": call.recording_url,
		"recording_remote_path": call.recording_remote_path,
		"recording_file_storage_id": call.recording_file_storage_id,
		"can_stream": bool(call.recording_url or call.recording_file_storage_id),
	}
