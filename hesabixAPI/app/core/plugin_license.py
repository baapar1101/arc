"""لایسنس افزونه‌های بازار: entitlement سراسری و بررسی لایسنس کسب‌وکار.

منبع حقیقت برای «آیا این افزونه برای این کسب‌وکار فعال است؟».
افزونه‌ای که ``enabled_for_all_businesses`` داشته باشد بدون ردیف
``business_plugins`` برای همه کسب‌وکارها فعال است.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin, MarketplacePluginPlan
from app.core.responses import ApiError

SOURCE_SYSTEM_DEFAULT = "system_default"


def coerce_bool(value: Any, *, default: bool = False) -> bool:
	"""تبدیل مقدار ستون/payload به bool بدون اینکه MagicMock را True حساب کند."""
	if value is True or value is False:
		return value
	if isinstance(value, int) and type(value) is not bool:
		return value != 0
	if isinstance(value, str):
		normalized = value.strip().lower()
		if normalized in {"1", "true", "yes", "on"}:
			return True
		if normalized in {"0", "false", "no", "off", ""}:
			return False
		return default
	return default


def column_flag(obj: Any, name: str, *, default: bool = False) -> bool:
	if obj is None:
		return default
	return coerce_bool(getattr(obj, name, default), default=default)


def payload_flag(payload: Dict[str, Any], key: str, *, default: bool) -> bool:
	if key not in payload:
		return default
	return coerce_bool(payload.get(key), default=default)


def get_marketplace_plugin(db: Session, plugin_code: str) -> Optional[MarketplacePlugin]:
	return (
		db.query(MarketplacePlugin)
		.filter(MarketplacePlugin.code == plugin_code)
		.first()
	)


def get_marketplace_plugin_by_id(db: Session, plugin_id: int) -> Optional[MarketplacePlugin]:
	return (
		db.query(MarketplacePlugin)
		.filter(MarketplacePlugin.id == int(plugin_id))
		.first()
	)


def _ends_at_date(ends_at: Any) -> Optional[Any]:
	if ends_at is None:
		return None
	if isinstance(ends_at, datetime):
		return ends_at.date()
	return ends_at


def license_row_is_valid(license_row: Any, *, now: Optional[datetime] = None) -> bool:
	if license_row is None:
		return False
	status = getattr(license_row, "status", None)
	if status != "active":
		return False
	ends_at = _ends_at_date(getattr(license_row, "ends_at", None))
	if ends_at is None:
		return True
	today = (now or datetime.utcnow()).date()
	return ends_at >= today


def get_business_plugin_row(
	db: Session,
	business_id: int,
	plugin_id: int,
) -> Optional[BusinessPlugin]:
	return (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.business_id == int(business_id),
			BusinessPlugin.plugin_id == int(plugin_id),
		)
		.first()
	)


def _pick_config_plan_id(db: Session, plugin_id: int) -> Optional[int]:
	plans = (
		db.query(MarketplacePluginPlan)
		.filter(MarketplacePluginPlan.plugin_id == int(plugin_id))
		.all()
	)
	if not plans:
		return None
	active = [p for p in plans if column_flag(p, "is_active", default=True)]
	candidates = active or list(plans)
	lifetime = [p for p in candidates if str(getattr(p, "period", "") or "").lower() == "lifetime"]
	chosen = lifetime[0] if lifetime else min(candidates, key=lambda p: float(getattr(p, "price", 0) or 0))
	return int(chosen.id)


def ensure_plugin_config_row(
	db: Session,
	business_id: int,
	plugin: Any,
) -> Optional[BusinessPlugin]:
	"""ردیف تنظیمات extra_info را برای افزونهٔ سراسری می‌سازد؛ لایسنس خرید نیست.

	``status=system_default`` تا ``license_row_is_valid`` آن را لایسنس نپندارد.
	اگر ردیف واقعی (خرید/trial) وجود داشته باشد همان برگردانده می‌شود.
	"""
	if plugin is None or getattr(plugin, "id", None) is None:
		return None
	existing = get_business_plugin_row(db, business_id, int(plugin.id))
	if existing is not None:
		return existing
	if not plugin_is_globally_enabled(plugin):
		return None
	plan_id = _pick_config_plan_id(db, int(plugin.id))
	if plan_id is None:
		return None
	row = BusinessPlugin(
		business_id=int(business_id),
		plugin_id=int(plugin.id),
		plan_id=plan_id,
		status=SOURCE_SYSTEM_DEFAULT,
		starts_at=datetime.utcnow(),
		ends_at=None,
		auto_renew=False,
		is_trial=False,
		extra_info=None,
	)
	db.add(row)
	db.flush()
	return row


def plugin_is_globally_enabled(plugin: Any) -> bool:
	return column_flag(plugin, "is_active") and column_flag(plugin, "enabled_for_all_businesses")


def license_status_is_system_default(status: Any) -> bool:
	return str(status or "") == SOURCE_SYSTEM_DEFAULT


def plugin_is_listed(plugin: Any) -> bool:
	return column_flag(plugin, "is_active") and column_flag(
		plugin, "listed_in_marketplace", default=True
	)


def plugin_is_purchasable(plugin: Any) -> bool:
	if not plugin_is_listed(plugin):
		return False
	if column_flag(plugin, "enabled_for_all_businesses"):
		return False
	return True


def assert_plugin_purchasable(plugin: Any) -> None:
	"""خرید/trial فقط برای افزونه‌های لیست‌شدهٔ غیرسراسری مجاز است."""
	if plugin is None or not column_flag(plugin, "is_active"):
		raise ApiError("PLUGIN_NOT_FOUND", "افزونه یافت نشد یا غیرفعال است", http_status=404)
	if column_flag(plugin, "enabled_for_all_businesses"):
		raise ApiError(
			"PLUGIN_NOT_FOR_SALE",
			"این افزونه به‌صورت پیش‌فرض برای همه کسب‌وکارها فعال است و نیازی به خرید ندارد.",
			http_status=400,
		)
	if not column_flag(plugin, "listed_in_marketplace", default=True):
		raise ApiError(
			"PLUGIN_NOT_FOR_SALE",
			"این افزونه در بازار افزونه‌ها برای خرید در دسترس نیست.",
			http_status=400,
		)


PLUGIN_ACCESS_ACTIVE = "active"
PLUGIN_ACCESS_MISSING = "missing"
PLUGIN_ACCESS_EXPIRED = "expired"
PLUGIN_ACCESS_PLUGIN_DISABLED = "plugin_disabled"
PLUGIN_ACCESS_PLUGIN_NOT_FOUND = "plugin_not_found"


def get_plugin_access_reason(db: Session, business_id: int, plugin_code: str) -> str:
	"""علت دسترسی به افزونه: active / missing / expired / plugin_disabled / plugin_not_found."""
	plugin = get_marketplace_plugin(db, plugin_code)
	if plugin is None:
		return PLUGIN_ACCESS_PLUGIN_NOT_FOUND
	if not column_flag(plugin, "is_active"):
		return PLUGIN_ACCESS_PLUGIN_DISABLED
	if column_flag(plugin, "enabled_for_all_businesses"):
		return PLUGIN_ACCESS_ACTIVE
	row = get_business_plugin_row(db, business_id, int(plugin.id))
	if row is None or license_status_is_system_default(getattr(row, "status", None)):
		return PLUGIN_ACCESS_MISSING
	if license_row_is_valid(row):
		return PLUGIN_ACCESS_ACTIVE
	ends_at = _ends_at_date(getattr(row, "ends_at", None))
	today = datetime.utcnow().date()
	status = str(getattr(row, "status", "") or "")
	if status == "expired" or (ends_at is not None and ends_at < today):
		return PLUGIN_ACCESS_EXPIRED
	return PLUGIN_ACCESS_MISSING


def is_plugin_active(db: Session, business_id: int, plugin_code: str) -> bool:
	return get_plugin_access_reason(db, business_id, plugin_code) == PLUGIN_ACCESS_ACTIVE


def list_globally_enabled_plugins(db: Session) -> List[MarketplacePlugin]:
	items = db.query(MarketplacePlugin).all()
	return [p for p in items if plugin_is_globally_enabled(p)]


def synthetic_global_license(plugin: Any) -> Dict[str, Any]:
	return {
		"license_id": None,
		"plugin_id": plugin.id,
		"plugin_code": getattr(plugin, "code", None),
		"plugin_name": getattr(plugin, "name", None),
		"plan_id": None,
		"plan_period": None,
		"plan_price": None,
		"status": "active",
		"is_active": True,
		"is_expired": False,
		"is_trial": False,
		"trial_started_at": None,
		"trial_remaining_days": None,
		"starts_at": None,
		"ends_at": None,
		"auto_renew": False,
		"created_at": None,
		"updated_at": None,
		"source": SOURCE_SYSTEM_DEFAULT,
		"globally_enabled": True,
		"purchasable": False,
	}


def overlay_global_access(row: Dict[str, Any]) -> Dict[str, Any]:
	"""دسترسی سراسری را روی پاسخ لایسنس واقعی می‌نشاند؛ انقضا/trial خرید قبلی را پنهان می‌کند."""
	row["is_active"] = True
	row["is_expired"] = False
	row["status"] = "active"
	row["globally_enabled"] = True
	row["purchasable"] = False
	row["is_trial"] = False
	row["trial_remaining_days"] = None
	row["trial_started_at"] = None
	row["ends_at"] = None
	return row


def merge_global_plugin_rows(
	existing: List[Dict[str, Any]],
	global_plugins: Iterable[Any],
) -> List[Dict[str, Any]]:
	"""ردیف‌های لایسنس واقعی را با entitlement سراسری ادغام می‌کند؛ تکراری نمی‌سازد."""
	by_id: Dict[int, Dict[str, Any]] = {}
	out: List[Dict[str, Any]] = []
	for row in existing:
		plugin_id = row.get("plugin_id")
		if plugin_id is not None:
			by_id[int(plugin_id)] = row
		out.append(row)

	for plugin in global_plugins:
		plugin_id = int(plugin.id)
		if plugin_id in by_id:
			overlay_global_access(by_id[plugin_id])
			continue
		out.append(synthetic_global_license(plugin))
	return out
