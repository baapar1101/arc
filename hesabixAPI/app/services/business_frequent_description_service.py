from __future__ import annotations

from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from adapters.db.models.business_frequent_description import BusinessFrequentDescription

_MAX_TEXT_LEN = 2000
_MAX_ROWS_PER_SCOPE = 500


def _normalize_text(text: str) -> str:
	s = (text or "").strip()
	if len(s) > _MAX_TEXT_LEN:
		raise ValueError("TEXT_TOO_LONG")
	if not s:
		raise ValueError("TEXT_EMPTY")
	return s


def _normalize_scope(scope: str | None) -> str:
	s = (scope or "general").strip().lower()
	if not s or len(s) > 64:
		return "general"
	for ch in s:
		if not (ch.isascii() and (ch.isalnum() or ch == "_")):
			return "general"
	return s


def list_for_business(db: Session, business_id: int, scope: str | None = None) -> list[BusinessFrequentDescription]:
	sc = _normalize_scope(scope)
	stmt = (
		select(BusinessFrequentDescription)
		.where(BusinessFrequentDescription.business_id == business_id)
		.where(BusinessFrequentDescription.scope == sc)
		.order_by(BusinessFrequentDescription.sort_order.asc(), BusinessFrequentDescription.id.asc())
	)
	return list(db.scalars(stmt).all())


def create_row(
	db: Session,
	business_id: int,
	text: str,
	sort_order: int | None = None,
	scope: str | None = None,
) -> BusinessFrequentDescription:
	sc = _normalize_scope(scope)
	count = db.scalar(
		select(func.count())
		.select_from(BusinessFrequentDescription)
		.where(BusinessFrequentDescription.business_id == business_id)
		.where(BusinessFrequentDescription.scope == sc)
	) or 0
	if int(count) >= _MAX_ROWS_PER_SCOPE:
		raise ValueError("LIMIT_REACHED")
	norm = _normalize_text(text)
	now = datetime.utcnow()
	row = BusinessFrequentDescription(
		business_id=business_id,
		scope=sc,
		text=norm,
		sort_order=int(sort_order) if sort_order is not None else 0,
		created_at=now,
		updated_at=now,
	)
	db.add(row)
	db.flush()
	return row


def update_row(
	db: Session,
	business_id: int,
	row_id: int,
	text: str | None = None,
	sort_order: int | None = None,
) -> BusinessFrequentDescription | None:
	row = db.get(BusinessFrequentDescription, row_id)
	if row is None or row.business_id != business_id:
		return None
	if text is not None:
		row.text = _normalize_text(text)
	if sort_order is not None:
		row.sort_order = int(sort_order)
	row.updated_at = datetime.utcnow()
	db.flush()
	return row


def delete_row(db: Session, business_id: int, row_id: int) -> bool:
	row = db.get(BusinessFrequentDescription, row_id)
	if row is None or row.business_id != business_id:
		return False
	db.delete(row)
	db.flush()
	return True


def to_dict(row: BusinessFrequentDescription) -> dict:
	def _iso(dt: datetime) -> str:
		if dt.tzinfo is None:
			return dt.isoformat() + "Z"
		return dt.isoformat()

	return {
		"id": row.id,
		"business_id": row.business_id,
		"scope": row.scope,
		"text": row.text,
		"sort_order": row.sort_order,
		"created_at": _iso(row.created_at),
		"updated_at": _iso(row.updated_at),
	}
