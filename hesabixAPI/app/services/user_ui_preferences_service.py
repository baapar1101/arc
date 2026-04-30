from __future__ import annotations

import re
from datetime import datetime
from typing import Any, Dict, List, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.user_ui_preferences import UserUiPreferences

_BUSINESS_PATH_RE = re.compile(r"^/business/(\d+)(/.*)?$")
_MAX_TABS_PER_BUSINESS = 24


def _default_preferences() -> Dict[str, Any]:
	return {
		"business_panel_navigation": "single",
		"business_panel_tabs": {},
	}


def _normalize_tabs_payload(raw: Any) -> Dict[str, Any]:
	if not isinstance(raw, dict):
		return {}
	out: Dict[str, Any] = {}
	for bid_str, entry in raw.items():
		try:
			bid = int(str(bid_str))
		except Exception:
			continue
		if not isinstance(entry, dict):
			continue
		paths_raw = entry.get("paths") or []
		if not isinstance(paths_raw, list):
			continue
		paths: List[str] = []
		for p in paths_raw[:_MAX_TABS_PER_BUSINESS]:
			if not isinstance(p, str):
				continue
			p = p.strip()
			if not p.startswith("/"):
				p = "/" + p
			ok, pbid, _ = _parse_business_path(p)
			if not ok or pbid != bid:
				continue
			paths.append(p)
		# حذف تکراری با حفظ ترتیب
		seen = set()
		uniq: List[str] = []
		for p in paths:
			if p in seen:
				continue
			seen.add(p)
			uniq.append(p)
		active = entry.get("active_path")
		active_str = str(active).strip() if active is not None else None
		if active_str and not active_str.startswith("/"):
			active_str = "/" + active_str
		if active_str:
			ok_a, aid, _ = _parse_business_path(active_str)
			if not ok_a or aid != bid or active_str not in uniq:
				active_str = uniq[-1] if uniq else None
		else:
			active_str = uniq[-1] if uniq else None
		if uniq:
			out[str(bid)] = {"paths": uniq, "active_path": active_str}
	return out


def _parse_business_path(path: str) -> Tuple[bool, int, str]:
	m = _BUSINESS_PATH_RE.match(path.split("?")[0])
	if not m:
		return False, 0, ""
	return True, int(m.group(1)), m.group(2) or ""


def get_user_ui_preferences(db: Session, user_id: int) -> Dict[str, Any]:
	row = db.query(UserUiPreferences).filter(UserUiPreferences.user_id == user_id).first()
	base = _default_preferences()
	if row is None or not isinstance(row.preferences, dict):
		return dict(base)
	data = dict(base)
	stored = dict(row.preferences)
	mode = stored.get("business_panel_navigation")
	if mode in ("single", "tabs"):
		data["business_panel_navigation"] = mode
	tabs = _normalize_tabs_payload(stored.get("business_panel_tabs"))
	data["business_panel_tabs"] = tabs
	return data


def save_user_ui_preferences(db: Session, user_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	now = datetime.utcnow()
	row = db.query(UserUiPreferences).filter(UserUiPreferences.user_id == user_id).first()

	base = _default_preferences()
	current = get_user_ui_preferences(db, user_id) if row else base

	mode = payload.get("business_panel_navigation")
	if mode is None:
		mode = current["business_panel_navigation"]
	if mode not in ("single", "tabs"):
		mode = "single"

	if "business_panel_tabs" in payload and isinstance(payload["business_panel_tabs"], dict):
		tabs = _normalize_tabs_payload(payload["business_panel_tabs"])
	else:
		tabs = current["business_panel_tabs"]

	next_prefs = {
		"business_panel_navigation": mode,
		"business_panel_tabs": tabs,
	}

	if row is None:
		row = UserUiPreferences(user_id=user_id, preferences=next_prefs, created_at=now, updated_at=now)
		db.add(row)
	else:
		row.preferences = next_prefs
		row.updated_at = now
	db.flush()
	return get_user_ui_preferences(db, user_id)
