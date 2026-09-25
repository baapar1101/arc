"""ابزارهای مرکزی تاریخ/زمان — قرارداد: ذخیره UTC naive، نمایش بر اساس timezone کسب‌وکار/سیستم."""

from __future__ import annotations

from datetime import datetime, timezone as dt_timezone
from typing import Optional

from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def utc_now() -> datetime:
	"""لحظهٔ فعلی UTC به‌صورت naive (سازگار با ستون‌های DateTime بدون tz)."""
	return datetime.now(dt_timezone.utc).replace(tzinfo=None)


def utc_naive_to_aware(dt: datetime) -> datetime:
	if dt.tzinfo is None:
		return dt.replace(tzinfo=dt_timezone.utc)
	return dt.astimezone(dt_timezone.utc)


def utc_naive_to_iso_z(dt: datetime) -> str:
	"""ISO 8601 با پسوند Z برای پارس امن در کلاینت."""
	return utc_naive_to_aware(dt).isoformat().replace("+00:00", "Z")


def localize_assumed_utc_naive_for_display(dt: datetime, tz_name: str) -> datetime:
	"""
	قرارداد: datetime بدون tz در DB به‌عنوان UTC ذخیره شده است.
	خروجی: همان لحظه به‌صورت «ساعت دیوار» در منطقهٔ نمایش (naive برای تبدیل تقویم).
	"""
	name = (tz_name or "Asia/Tehran").strip() or "Asia/Tehran"
	try:
		tz = ZoneInfo(name)
	except ZoneInfoNotFoundError:
		tz = ZoneInfo("Asia/Tehran")
	utc_dt = utc_naive_to_aware(dt)
	return utc_dt.astimezone(tz).replace(tzinfo=None)


def resolve_display_timezone_name(business_id: Optional[int] = None) -> str:
	"""منطقهٔ زمانی نمایش: ابتدا کسب‌وکار، سپس پیش‌فرض سیستم."""
	if business_id is not None:
		from app.services.business_timezone_service import get_business_display_timezone_cached

		return get_business_display_timezone_cached(int(business_id))
	from app.services.system_settings_service import get_system_display_timezone_cached

	return get_system_display_timezone_cached()


def resolve_display_timezone_from_request(request) -> str:
	"""timezone نمایش از request.state.business_id (در صورت وجود)."""
	business_id: Optional[int] = None
	try:
		if request is not None and hasattr(request.state, "business_id"):
			raw = getattr(request.state, "business_id", None)
			if raw is not None:
				business_id = int(raw)
	except Exception:
		business_id = None
	return resolve_display_timezone_name(business_id)


def format_datetime_for_calendar(
	dt: datetime,
	calendar_type: str,
	tz_name: str,
) -> dict:
	from app.core.calendar import CalendarConverter

	local_dt = localize_assumed_utc_naive_for_display(dt, tz_name)
	return CalendarConverter.format_datetime(local_dt, calendar_type)


def utc_now_aware() -> datetime:
	"""لحظهٔ فعلی UTC با timezone (برای ستون‌های TIMESTAMPTZ)."""
	return datetime.now(dt_timezone.utc)


def business_wall_clock_now(business_id: Optional[int] = None) -> datetime:
	"""ساعت دیوار در منطقهٔ زمانی کسب‌وکار (naive برای قالب‌ها)."""
	from app.core.business_calendar import business_now

	return business_now(business_id).replace(tzinfo=None)


def resolve_calendar_type_for_request(request, is_fa: bool = False) -> str:
	"""تقویم نمایش از middleware یا هدر X-Calendar-Type."""
	try:
		if request is not None and hasattr(request.state, "calendar_type") and request.state.calendar_type:
			return str(request.state.calendar_type)
	except Exception:
		pass
	try:
		from app.core.calendar import get_calendar_type_from_header

		cal_header = request.headers.get("X-Calendar-Type") if request is not None else None
		if cal_header:
			return get_calendar_type_from_header(cal_header)
	except Exception:
		pass
	return "jalali" if is_fa else "gregorian"


def _trim_seconds_display(s: str) -> str:
	if len(s) >= 3 and s[-3] == ":" and s[-2:].isdigit():
		return s[:-3]
	return s


def format_generated_at_for_pdf(
	business_id: Optional[int],
	calendar_type: str = "jalali",
) -> str:
	"""زمان تولید PDF/گزارش در timezone کسب‌وکار و تقویم انتخابی."""
	from app.core.calendar import CalendarConverter

	now_dt = business_wall_clock_now(business_id)
	try:
		out = CalendarConverter.format_datetime(now_dt, calendar_type)
		s = str(out.get("formatted") or out.get("date_time") or "")
		if s:
			return _trim_seconds_display(s)
	except Exception:
		pass
	return now_dt.strftime("%Y/%m/%d %H:%M")


def export_filename_timestamp(business_id: Optional[int] = None) -> str:
	"""پسوند نام فایل export بر اساس ساعت دیوار کسب‌وکار."""
	return business_wall_clock_now(business_id).strftime("%Y%m%d_%H%M%S")
