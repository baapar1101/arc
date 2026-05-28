"""تاریخ و زمان مؤثر کسب‌وکار (پیش‌فرض منطقهٔ ایران)."""

from __future__ import annotations

from datetime import date, datetime
from typing import Optional
from zoneinfo import ZoneInfo

DEFAULT_BUSINESS_TIMEZONE = "Asia/Tehran"


def business_timezone_name(_business_id: Optional[int] = None) -> str:
	"""نام منطقهٔ زمانی کسب‌وکار؛ فعلاً پیش‌فرض تهران."""
	# TODO: خواندن از تنظیمات کسب‌وکار وقتی فیلد timezone اضافه شد.
	return DEFAULT_BUSINESS_TIMEZONE


def business_today(business_id: Optional[int] = None) -> date:
	return datetime.now(ZoneInfo(business_timezone_name(business_id))).date()


def business_now(business_id: Optional[int] = None) -> datetime:
	return datetime.now(ZoneInfo(business_timezone_name(business_id)))
