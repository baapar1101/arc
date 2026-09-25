"""توابع تاریخ امن برای HScript با پشتیبانی جلالی/میلادی."""

from __future__ import annotations

import re
from datetime import date, datetime
from typing import Any, Literal, Optional

from app.core.calendar import CalendarConverter, CalendarType
from app.services.hscript.errors import TypeErrorHS

CalendarName = Literal["jalali", "gregorian", "shamsi", "persian"]

_JALALI_ALIASES = frozenset({"jalali", "shamsi", "persian", "fa", "j"})
_GREGORIAN_ALIASES = frozenset({"gregorian", "miladi", "en", "g", "christian"})


def normalize_calendar(value: Any, *, default: CalendarType = "jalali") -> CalendarType:
	if value is None:
		return default
	s = str(value).strip().lower()
	if not s:
		return default
	if s in _JALALI_ALIASES:
		return "jalali"
	if s in _GREGORIAN_ALIASES:
		return "gregorian"
	raise TypeErrorHS("نوع تقویم باید jalali یا gregorian باشد")


def _to_datetime(value: Any) -> datetime:
	if value is None:
		raise TypeErrorHS("تاریخ خالی است")
	if isinstance(value, datetime):
		return value
	if isinstance(value, date):
		return datetime(value.year, value.month, value.day)
	s = str(value).strip()
	if not s:
		raise TypeErrorHS("تاریخ خالی است")
	# ISO با Z
	try:
		return datetime.fromisoformat(s.replace("Z", "+00:00")).replace(tzinfo=None)
	except ValueError:
		pass
	# YYYY-MM-DD یا YYYY/MM/DD میلادی
	m = re.match(r"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?$", s)
	if m:
		y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
		hh = int(m.group(4) or 0)
		mm = int(m.group(5) or 0)
		ss = int(m.group(6) or 0)
		# سال جلالی معمولاً ۱۳۰۰–۱۵۰۰
		if 1200 <= y <= 1500:
			import jdatetime

			return jdatetime.datetime(y, mo, d, hh, mm, ss).togregorian()
		return datetime(y, mo, d, hh, mm, ss)
	raise TypeErrorHS(f"تاریخ نامعتبر: {s[:64]}")


def parse_date(value: Any, *, calendar: Optional[Any] = None) -> str:
	"""
	تبدیل ورودی به تاریخ میلادی ISO (YYYY-MM-DD) برای فیلتر Gateway.
	اگر calendar=jalali باشد و رشته شبیه جلالی باشد، از جلالی parse می‌شود.
	"""
	cal = normalize_calendar(calendar, default="gregorian") if calendar is not None else None
	s = str(value).strip() if value is not None and not isinstance(value, (date, datetime)) else None
	if cal == "jalali" and s:
		m = re.match(r"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$", s)
		if m:
			import jdatetime

			y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
			g = jdatetime.date(y, mo, d).togregorian()
			return g.isoformat()
	dt = _to_datetime(value)
	return dt.date().isoformat()


def format_date(
	value: Any,
	*,
	calendar: Any = "jalali",
	with_time: bool = False,
) -> str:
	"""قالب‌بندی تاریخ برای نمایش در گزارش."""
	cal = normalize_calendar(calendar, default="jalali")
	dt = _to_datetime(value)
	info = CalendarConverter.format_datetime(dt, cal)
	key = "formatted" if with_time else "date_only"
	return str(info.get(key) or "")


def format_date_value(value: Any, calendar: CalendarType) -> Any:
	"""اگر مقدار شبیه تاریخ باشد قالب می‌کند؛ وگرنه همان را برمی‌گرداند."""
	if value is None or isinstance(value, (bool, int, float)):
		return value
	if isinstance(value, (date, datetime)):
		return format_date(value, calendar=calendar, with_time=isinstance(value, datetime))
	s = str(value).strip()
	if not s:
		return value
	# فقط رشته‌های تاریخ‌مانند
	if not re.match(r"^\d{4}[-/]\d{1,2}[-/]\d{1,2}", s):
		return value
	try:
		with_time = "T" in s or " " in s
		return format_date(s, calendar=calendar, with_time=with_time)
	except TypeErrorHS:
		return value


def today(*, calendar: Any = "gregorian") -> str:
	"""تاریخ امروز؛ خروجی همیشه ISO میلادی برای فیلتر Gateway است مگر calendar=jalali برای نمایش."""
	cal = normalize_calendar(calendar, default="gregorian")
	d = date.today()
	if cal == "jalali":
		return format_date(d, calendar="jalali")
	return d.isoformat()


def month_bounds(ref: Any = None) -> dict[str, str]:
	"""بازه ماه جاری میلادی ISO: {from_date, to_date}."""
	from datetime import timedelta

	base = _to_datetime(ref).date() if ref is not None else date.today()
	start = base.replace(day=1)
	if start.month == 12:
		end = start.replace(year=start.year + 1, month=1, day=1) - timedelta(days=1)
	else:
		end = start.replace(year=start.year, month=start.month + 1, day=1) - timedelta(days=1)
	return {"from_date": start.isoformat(), "to_date": end.isoformat()}


def last_month_bounds(ref: Any = None) -> dict[str, str]:
	from datetime import timedelta

	base = _to_datetime(ref).date() if ref is not None else date.today()
	first_this = base.replace(day=1)
	end = first_this - timedelta(days=1)
	start = end.replace(day=1)
	return {"from_date": start.isoformat(), "to_date": end.isoformat()}


def days_ago(n: int) -> str:
	from datetime import timedelta

	return (date.today() - timedelta(days=int(n))).isoformat()
