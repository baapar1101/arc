from __future__ import annotations

import re
from datetime import datetime
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from adapters.db.models.data_table_user_column_settings import DataTableUserColumnSettings

_TABLE_ID_RE = re.compile(r"^[a-zA-Z0-9_]{1,255}$")


def validate_table_id(raw: str) -> str:
	t = (raw or "").strip()
	if not _TABLE_ID_RE.match(t):
		raise ValueError("INVALID_TABLE_ID")
	return t


def get_column_settings(
	db: Session,
	business_id: int,
	user_id: int,
	table_id: str,
) -> Optional[Dict[str, Any]]:
	tid = validate_table_id(table_id)
	row = (
		db.query(DataTableUserColumnSettings)
		.filter(
			DataTableUserColumnSettings.business_id == business_id,
			DataTableUserColumnSettings.user_id == user_id,
			DataTableUserColumnSettings.table_id == tid,
		)
		.first()
	)
	if row is None or not row.settings:
		return None
	return dict(row.settings) if isinstance(row.settings, dict) else None


def save_column_settings(
	db: Session,
	business_id: int,
	user_id: int,
	table_id: str,
	settings: Dict[str, Any],
) -> Dict[str, Any]:
	tid = validate_table_id(table_id)
	if not isinstance(settings, dict):
		raise ValueError("INVALID_SETTINGS")
	now = datetime.utcnow()
	row = (
		db.query(DataTableUserColumnSettings)
		.filter(
			DataTableUserColumnSettings.business_id == business_id,
			DataTableUserColumnSettings.user_id == user_id,
			DataTableUserColumnSettings.table_id == tid,
		)
		.first()
	)
	if row is None:
		row = DataTableUserColumnSettings(
			business_id=business_id,
			user_id=user_id,
			table_id=tid,
			settings=dict(settings),
		)
		db.add(row)
	else:
		row.settings = dict(settings)
		row.updated_at = now
	db.flush()
	return {
		"table_id": tid,
		"settings": row.settings,
		"updated_at": row.updated_at.isoformat() + "Z",
	}


def delete_column_settings(
	db: Session,
	business_id: int,
	user_id: int,
	table_id: str,
) -> bool:
	tid = validate_table_id(table_id)
	row = (
		db.query(DataTableUserColumnSettings)
		.filter(
			DataTableUserColumnSettings.business_id == business_id,
			DataTableUserColumnSettings.user_id == user_id,
			DataTableUserColumnSettings.table_id == tid,
		)
		.first()
	)
	if row is None:
		return False
	db.delete(row)
	db.flush()
	return True
