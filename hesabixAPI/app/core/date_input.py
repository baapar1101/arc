"""
پارس و نمایش تاریخ ورودی کاربر با توجه به تقویم انتخاب‌شده (شمسی/میلادی).
"""
from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Optional, Tuple

import jdatetime

from app.core.calendar import CalendarConverter, CalendarType


class DateParseError(ValueError):
    """خطای پارس تاریخ — با پیام قابل‌فهم برای AI/UI."""

    def __init__(self, value: object, *, calendar_type: CalendarType = "jalali", hint: str = "") -> None:
        self.value = value
        self.calendar_type = calendar_type
        msg = f"فرمت تاریخ نامعتبر: {value!r}"
        if hint:
            msg = f"{msg}. {hint}"
        super().__init__(msg)


def parse_user_date(
    value: str | datetime | date | None,
    *,
    calendar_type: CalendarType = "jalali",
) -> date:
    """تبدیل ورودی کاربر به date میلادی برای کوئری DB."""
    if value is None or value == "":
        raise DateParseError(value, calendar_type=calendar_type)
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()

    dt_str = str(value).strip()
    if not dt_str:
        raise DateParseError(value, calendar_type=calendar_type)

    try:
        dt_str_clean = dt_str.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(dt_str_clean)
        return parsed.date()
    except Exception:
        pass

    try:
        if len(dt_str) == 10 and dt_str.count("-") == 2:
            return datetime.strptime(dt_str, "%Y-%m-%d").date()
    except Exception:
        pass

    if len(dt_str) == 10 and dt_str.count("/") == 2:
        parts = dt_str.split("/")
        if len(parts) == 3:
            year_int = int(parts[0])
            month_int = int(parts[1])
            day_int = int(parts[2])
            if calendar_type == "jalali" or year_int >= 1300:
                try:
                    return jdatetime.date(year_int, month_int, day_int).togregorian()
                except (ValueError, jdatetime.JalaliDateError) as exc:
                    raise DateParseError(
                        value,
                        calendar_type=calendar_type,
                        hint="برای شمسی از YYYY/MM/DD استفاده کنید.",
                    ) from exc
            return datetime.strptime(dt_str, "%Y/%m/%d").date()

    raise DateParseError(
        value,
        calendar_type=calendar_type,
        hint="فرمت‌های مجاز: YYYY-MM-DD (میلادی) یا YYYY/MM/DD (شمسی).",
    )


def format_user_date(d: date | datetime | None, *, calendar_type: CalendarType = "jalali") -> Optional[str]:
    if d is None:
        return None
    if isinstance(d, datetime):
        d = d.date()
    formatted = CalendarConverter.format_datetime(
        datetime.combine(d, datetime.min.time()),
        calendar_type,
    )
    return formatted.get("date_only") or formatted.get("formatted")


def normalize_date_range(
    date_from: str | date | None,
    date_to: str | date | None,
    *,
    calendar_type: CalendarType = "jalali",
) -> Tuple[Optional[date], Optional[date]]:
    """نرمال‌سازی بازهٔ تاریخ؛ در صورت خطا ValueError."""
    from_parsed = parse_user_date(date_from, calendar_type=calendar_type) if date_from else None
    to_parsed = parse_user_date(date_to, calendar_type=calendar_type) if date_to else None
    if from_parsed and to_parsed and from_parsed > to_parsed:
        raise ValueError(
            f"from_date ({format_user_date(from_parsed, calendar_type=calendar_type)}) "
            f"بزرگ‌تر از to_date ({format_user_date(to_parsed, calendar_type=calendar_type)}) است."
        )
    return from_parsed, to_parsed


def jalali_month_range(year: int, month: int) -> Tuple[date, date]:
    """بازهٔ یک ماه شمسی به میلادی."""
    jalali_start = jdatetime.date(year, month, 1)
    days_in_month = jdatetime.j_days_in_month[month - 1]
    if month == 12 and jalali_start.isleap():
        days_in_month = 30
    jalali_end = jdatetime.date(year, month, days_in_month)
    gs = jalali_start.togregorian()
    ge = jalali_end.togregorian()
    return date(gs.year, gs.month, gs.day), date(ge.year, ge.month, ge.day)


def gregorian_month_range(year: int, month: int) -> Tuple[date, date]:
    start = date(year, month, 1)
    if month == 12:
        end = date(year, 12, 31)
    else:
        end = date(year, month + 1, 1) - timedelta(days=1)
    return start, end
