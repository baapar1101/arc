"""تاریخ و زمان مؤثر کسب‌وکار (پیش‌فرض منطقهٔ ایران)."""

from __future__ import annotations

from datetime import date, datetime
from typing import Optional
from zoneinfo import ZoneInfo

DEFAULT_BUSINESS_TIMEZONE = "Asia/Tehran"


def business_timezone_name(business_id: Optional[int] = None) -> str:
	"""نام منطقهٔ زمانی کسب‌وکار (یا پیش‌فرض سیستم)."""
	if business_id is not None:
		from app.services.business_timezone_service import get_business_display_timezone_cached

		return get_business_display_timezone_cached(int(business_id))
	from app.services.system_settings_service import get_system_display_timezone_cached

	return get_system_display_timezone_cached()


def business_today(business_id: Optional[int] = None) -> date:
	return datetime.now(ZoneInfo(business_timezone_name(business_id))).date()


def business_now(business_id: Optional[int] = None) -> datetime:
	return datetime.now(ZoneInfo(business_timezone_name(business_id)))
