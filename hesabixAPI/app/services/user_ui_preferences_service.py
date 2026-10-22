from __future__ import annotations

import re
from datetime import datetime
from typing import Any, Dict, List, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.user_ui_preferences import UserUiPreferences

_BUSINESS_PATH_RE = re.compile(r"^/business/(\d+)(/.*)?$")
_MAX_TABS_PER_BUSINESS = 24
_MAX_QUICK_SALES_SHORTCUT_BUSINESSES = 100
_MAX_QUICK_SALES_SHORTCUTS_PER_BUSINESS = 100
_QUICK_SALES_SHORTCUT_PLATFORMS = frozenset({"windows", "web"})


def _default_preferences() -> Dict[str, Any]:
	return {
		"business_panel_navigation": "single",
		# reuse_across_tabs: همان منطق قبلی (اسکن تب‌ها برای همان مقصد یا تب جدید)
		# long_press_new_tab: کلیک معمولی فقط تب فعال را عوض می‌کند؛ لانگ‌پرس منطق بالا را اعمال می‌کند
		"business_panel_sidebar_tab_behavior": "reuse_across_tabs",
		"business_panel_tabs": {},
		# theme_id / theme_mode فقط وقتی کاربر صریحاً انتخاب کند ذخیره می‌شوند
		# تا پیش‌فرض ادمین برای کاربران جدید حفظ بماند
	}


_ALLOWED_THEME_IDS = frozenset({"classic_blue", "turquoise_sea", "emerald_forest", "warm_copper"})
_ALLOWED_THEME_MODES = frozenset({"system", "light", "dark"})


def _normalize_theme_id(raw: Any, fallback: str | None = None) -> str | None:
	value = str(raw or "").strip().lower()
	if value in _ALLOWED_THEME_IDS:
		return value
	return fallback


def _normalize_theme_mode(raw: Any, fallback: str | None = None) -> str | None:
	value = str(raw or "").strip().lower()
	if value in _ALLOWED_THEME_MODES:
		return value
	return fallback


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
		pinned_raw = entry.get("pinned")
		if not isinstance(pinned_raw, list):
			pinned_raw = []
		# (path, pinned) — پین با ایندکس مسیر هم‌تراز می‌ماند حتی بعد از فیلتر/dedupe
		paired: List[Tuple[str, bool]] = []
		for i, p in enumerate(paths_raw[:_MAX_TABS_PER_BUSINESS]):
			if not isinstance(p, str):
				continue
			p = p.strip()
			if not p.startswith("/"):
				p = "/" + p
			ok, pbid, _ = _parse_business_path(p)
			if not ok or pbid != bid:
				continue
			is_pinned = bool(pinned_raw[i]) if i < len(pinned_raw) else False
			paired.append((p, is_pinned))
		# حذف تکراری با حفظ ترتیب
		seen = set()
		uniq: List[str] = []
		uniq_pinned: List[bool] = []
		for p, is_pinned in paired:
			if p in seen:
				continue
			seen.add(p)
			uniq.append(p)
			uniq_pinned.append(bool(is_pinned))
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
			out[str(bid)] = {
				"paths": uniq,
				"active_path": active_str,
				"pinned": uniq_pinned,
			}
	return out


def _normalize_quick_sales_payment_shortcuts(raw: Any) -> Dict[str, Any]:
	"""Keep per-user quick-sales shortcuts small and safe inside the JSON preferences row."""
	if not isinstance(raw, dict):
		return {}
	out: Dict[str, Any] = {}
	for business_key, platform_payload in list(raw.items())[:_MAX_QUICK_SALES_SHORTCUT_BUSINESSES]:
		try:
			business_id = int(str(business_key))
		except (TypeError, ValueError):
			continue
		if business_id <= 0 or not isinstance(platform_payload, dict):
			continue
		platforms: Dict[str, Dict[str, str]] = {}
		for platform in _QUICK_SALES_SHORTCUT_PLATFORMS:
			button_payload = platform_payload.get(platform)
			if not isinstance(button_payload, dict):
				continue
			buttons: Dict[str, str] = {}
			for button_key, shortcut in list(button_payload.items())[:_MAX_QUICK_SALES_SHORTCUTS_PER_BUSINESS]:
				key = str(button_key or "").strip()
				value = str(shortcut or "").strip().upper().replace(" ", "")
				if not key or len(key) > 64 or not value or len(value) > 32:
					continue
				buttons[key] = value
			if buttons:
				platforms[platform] = buttons
		if platforms:
			out[str(business_id)] = platforms
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
	sb = stored.get("business_panel_sidebar_tab_behavior")
	if sb in ("reuse_across_tabs", "long_press_new_tab"):
		data["business_panel_sidebar_tab_behavior"] = sb
	else:
		data["business_panel_sidebar_tab_behavior"] = base["business_panel_sidebar_tab_behavior"]
	tabs = _normalize_tabs_payload(stored.get("business_panel_tabs"))
	data["business_panel_tabs"] = tabs
	data["quick_sales_payment_shortcuts"] = _normalize_quick_sales_payment_shortcuts(
		stored.get("quick_sales_payment_shortcuts")
	)
	# فقط اگر کاربر قبلاً تم را صریحاً ذخیره کرده باشد برگردان
	if "theme_id" in stored:
		tid = _normalize_theme_id(stored.get("theme_id"))
		if tid is not None:
			data["theme_id"] = tid
	if "theme_mode" in stored:
		tmode = _normalize_theme_mode(stored.get("theme_mode"))
		if tmode is not None:
			data["theme_mode"] = tmode
	return data


def save_user_ui_preferences(db: Session, user_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	now = datetime.utcnow()
	row = db.query(UserUiPreferences).filter(UserUiPreferences.user_id == user_id).first()

	base = _default_preferences()
	current = get_user_ui_preferences(db, user_id) if row else dict(base)
	stored_raw = dict(row.preferences) if row is not None and isinstance(row.preferences, dict) else {}

	mode = payload.get("business_panel_navigation")
	if mode is None:
		mode = current["business_panel_navigation"]
	if mode not in ("single", "tabs"):
		mode = "single"

	sidebar_behavior = payload.get("business_panel_sidebar_tab_behavior")
	if sidebar_behavior is None:
		sidebar_behavior = current.get("business_panel_sidebar_tab_behavior", "reuse_across_tabs")
	if sidebar_behavior not in ("reuse_across_tabs", "long_press_new_tab"):
		sidebar_behavior = "reuse_across_tabs"

	if "business_panel_tabs" in payload and isinstance(payload["business_panel_tabs"], dict):
		tabs = _normalize_tabs_payload(payload["business_panel_tabs"])
	else:
		tabs = current["business_panel_tabs"]

	next_prefs: Dict[str, Any] = {
		"business_panel_navigation": mode,
		"business_panel_sidebar_tab_behavior": sidebar_behavior,
		"business_panel_tabs": tabs,
	}

	if "quick_sales_payment_shortcuts" in payload:
		quick_sales_shortcuts = _normalize_quick_sales_payment_shortcuts(
			payload.get("quick_sales_payment_shortcuts")
		)
	else:
		quick_sales_shortcuts = _normalize_quick_sales_payment_shortcuts(
			stored_raw.get("quick_sales_payment_shortcuts")
		)
	if quick_sales_shortcuts:
		next_prefs["quick_sales_payment_shortcuts"] = quick_sales_shortcuts

	# تم فقط وقتی در payload باشد یا قبلاً توسط کاربر ذخیره شده باشد حفظ می‌شود
	if "theme_id" in payload:
		tid = _normalize_theme_id(payload.get("theme_id"), "classic_blue")
		if tid is not None:
			next_prefs["theme_id"] = tid
	elif "theme_id" in stored_raw:
		tid = _normalize_theme_id(stored_raw.get("theme_id"))
		if tid is not None:
			next_prefs["theme_id"] = tid

	if "theme_mode" in payload:
		tmode = _normalize_theme_mode(payload.get("theme_mode"), "system")
		if tmode is not None:
			next_prefs["theme_mode"] = tmode
	elif "theme_mode" in stored_raw:
		tmode = _normalize_theme_mode(stored_raw.get("theme_mode"))
		if tmode is not None:
			next_prefs["theme_mode"] = tmode

	if row is None:
		row = UserUiPreferences(user_id=user_id, preferences=next_prefs, created_at=now, updated_at=now)
		db.add(row)
	else:
		row.preferences = next_prefs
		row.updated_at = now
	db.flush()
	return get_user_ui_preferences(db, user_id)


def get_quick_sales_payment_shortcuts(
	db: Session,
	user_id: int,
	business_id: int,
	*,
	platform: str = "windows",
) -> Dict[str, str]:
	preferences = get_user_ui_preferences(db, user_id)
	all_shortcuts = preferences.get("quick_sales_payment_shortcuts") or {}
	business_shortcuts = all_shortcuts.get(str(int(business_id))) or {}
	platform_shortcuts = business_shortcuts.get(platform) or {}
	return dict(platform_shortcuts) if isinstance(platform_shortcuts, dict) else {}


def save_quick_sales_payment_shortcuts(
	db: Session,
	user_id: int,
	business_id: int,
	shortcuts: Dict[str, str],
	*,
	platform: str = "windows",
) -> Dict[str, str]:
	if platform not in _QUICK_SALES_SHORTCUT_PLATFORMS:
		raise ValueError("Unsupported quick-sales shortcut platform")
	preferences = get_user_ui_preferences(db, user_id)
	all_shortcuts = dict(preferences.get("quick_sales_payment_shortcuts") or {})
	business_key = str(int(business_id))
	business_shortcuts = dict(all_shortcuts.get(business_key) or {})
	clean_shortcuts = {
		str(key): str(value)
		for key, value in shortcuts.items()
		if str(key).strip() and str(value).strip()
	}
	if clean_shortcuts:
		business_shortcuts[platform] = clean_shortcuts
		all_shortcuts[business_key] = business_shortcuts
	else:
		business_shortcuts.pop(platform, None)
		if business_shortcuts:
			all_shortcuts[business_key] = business_shortcuts
		else:
			all_shortcuts.pop(business_key, None)
	result = save_user_ui_preferences(
		db,
		user_id,
		{"quick_sales_payment_shortcuts": all_shortcuts},
	)
	return dict(
		((result.get("quick_sales_payment_shortcuts") or {}).get(business_key) or {}).get(platform)
		or {}
	)
