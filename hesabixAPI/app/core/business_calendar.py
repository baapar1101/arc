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


def business_day_utc_bounds(business_id: Optional[int], day: date) -> tuple[datetime, datetime]:
	"""شروع و پایان روز تقویم کسب‌وکار، به‌صورت datetime ناآگاه UTC (مطابق ذخیره‌سازی utcnow)."""
	tz = ZoneInfo(business_timezone_name(business_id))
	start_local = datetime.combine(day, datetime.min.time(), tzinfo=tz)
	end_local = datetime.combine(day, datetime.max.time(), tzinfo=tz)
	return (
		start_local.astimezone(ZoneInfo("UTC")).replace(tzinfo=None),
		end_local.astimezone(ZoneInfo("UTC")).replace(tzinfo=None),
	)
