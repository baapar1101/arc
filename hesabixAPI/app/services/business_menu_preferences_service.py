from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List

from sqlalchemy.orm import Session

from adapters.db.models.business_user_menu_preferences import BusinessUserMenuPreference

_MAX_KEYS = 300
_MAX_CHILDREN_GROUPS = 120
_MAX_KEY_LEN = 128


def _default_preferences() -> Dict[str, Any]:
	return {
		"root_order": [],
		"hidden_keys": [],
		"children_order": {},
	}


def _sanitize_keys_list(raw: Any) -> List[str]:
	if not isinstance(raw, list):
		return []
	out: List[str] = []
	seen = set()
	for v in raw[:_MAX_KEYS]:
		if not isinstance(v, str):
			continue
		key = v.strip()
		if not key or len(key) > _MAX_KEY_LEN:
			continue
		if key in seen:
			continue
		seen.add(key)
		out.append(key)
	return out


def _sanitize_children_order(raw: Any) -> Dict[str, List[str]]:
	if not isinstance(raw, dict):
		return {}
	out: Dict[str, List[str]] = {}
	for idx, (k, v) in enumerate(raw.items()):
		if idx >= _MAX_CHILDREN_GROUPS:
			break
		if not isinstance(k, str):
			continue
		parent_key = k.strip()
		if not parent_key or len(parent_key) > _MAX_KEY_LEN:
			continue
		out[parent_key] = _sanitize_keys_list(v)
	return out


def _sanitize_preferences(payload: Dict[str, Any]) -> Dict[str, Any]:
	return {
		"root_order": _sanitize_keys_list(payload.get("root_order")),
		"hidden_keys": _sanitize_keys_list(payload.get("hidden_keys")),
		"children_order": _sanitize_children_order(payload.get("children_order")),
	}


def _row_to_api_dict(row: BusinessUserMenuPreference) -> Dict[str, Any]:
	prefs = row.preferences if isinstance(row.preferences, dict) else {}
	clean = _sanitize_preferences(prefs)
	return {
		**_default_preferences(),
		**clean,
		"updated_at": row.updated_at.isoformat() + "Z" if row.updated_at else "",
	}


def get_or_create_menu_preferences(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
	row = (
		db.query(BusinessUserMenuPreference)
		.filter(
			BusinessUserMenuPreference.business_id == business_id,
			BusinessUserMenuPreference.user_id == user_id,
		)
		.first()
	)
	now = datetime.utcnow()
	if row is None:
		row = BusinessUserMenuPreference(
			business_id=business_id,
			user_id=user_id,
			preferences=_default_preferences(),
			created_at=now,
			updated_at=now,
		)
		db.add(row)
		db.flush()
	return _row_to_api_dict(row)


def save_menu_preferences(db: Session, business_id: int, user_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	now = datetime.utcnow()
	clean = _sanitize_preferences(payload if isinstance(payload, dict) else {})
	row = (
		db.query(BusinessUserMenuPreference)
		.filter(
			BusinessUserMenuPreference.business_id == business_id,
			BusinessUserMenuPreference.user_id == user_id,
		)
		.first()
	)
	if row is None:
		row = BusinessUserMenuPreference(
			business_id=business_id,
			user_id=user_id,
			preferences=clean,
			created_at=now,
			updated_at=now,
		)
		db.add(row)
	else:
		row.preferences = clean
		row.updated_at = now
	db.flush()
	return _row_to_api_dict(row)
