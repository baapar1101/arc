"""منطقهٔ زمانی نمایش هر کسب‌وکار (با کش و fallback به تنظیمات سیستم)."""

from __future__ import annotations

from typing import Optional

from sqlalchemy.orm import Session

from app.services.system_settings_service import (
	get_system_display_timezone_cached,
	resolve_system_display_timezone_string,
	validate_iana_timezone_name,
)


def _cache_key(business_id: int) -> str:
	return f"business:display_timezone:{int(business_id)}"


def resolve_business_display_timezone_string(db: Session, business_id: int) -> str:
	from adapters.db.models.business import Business

	row = (
		db.query(Business.display_timezone)
		.filter(Business.id == int(business_id))
		.first()
	)
	raw = (row[0] if row and row[0] else "").strip() if row else ""
	if raw:
		return validate_iana_timezone_name(raw)
	return resolve_system_display_timezone_string(db)


def get_business_display_timezone_cached(business_id: int) -> str:
	from app.core.cache import get_cache

	cache = get_cache()
	key = _cache_key(business_id)
	cached = cache.get(key)
	if cached is not None:
		return str(cached)
	try:
		from adapters.db.session import get_db_session

		with get_db_session() as db:
			tz = resolve_business_display_timezone_string(db, business_id)
	except Exception:
		tz = get_system_display_timezone_cached()
	cache.set(key, tz, ttl=300)
	return tz


def invalidate_business_display_timezone_cache(business_id: int) -> None:
	try:
		from app.core.cache import get_cache

		get_cache().delete(_cache_key(business_id))
	except Exception:
		pass


def normalize_business_display_timezone(value: Optional[str]) -> Optional[str]:
	"""اعتبارسنجی مقدار ورودی؛ رشتهٔ خالی = استفاده از پیش‌فرض سیستم."""
	if value is None:
		return None
	raw = str(value).strip()
	if not raw:
		return None
	return validate_iana_timezone_name(raw)
