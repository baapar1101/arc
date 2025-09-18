from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional
import jdatetime

CalendarType = Literal["gregorian", "jalali"]


class CalendarConverter:
    """Utility class for converting dates between Gregorian and Jalali calendars"""
    
    @staticmethod
    def to_jalali(dt: datetime) -> dict:
        """Convert Gregorian datetime to Jalali format"""
        if dt is None:
            return None
        
        jalali = jdatetime.datetime.fromgregorian(datetime=dt)
        # نام ماه‌های شمسی
        jalali_month_names = [
            'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
            'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
        ]
        # نام روزهای هفته شمسی
        jalali_weekday_names = [
            'شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه'
        ]
        
        return {
            "year": jalali.year,
            "month": jalali.month,
            "day": jalali.day,
            "hour": jalali.hour,
            "minute": jalali.minute,
            "second": jalali.second,
            "weekday": jalali.weekday(),
            "month_name": jalali_month_names[jalali.month - 1],
            "weekday_name": jalali_weekday_names[jalali.weekday()],
            "formatted": jalali.strftime("%Y/%m/%d %H:%M:%S"),
            "date_only": jalali.strftime("%Y/%m/%d"),
            "time_only": jalali.strftime("%H:%M:%S"),
            "is_leap_year": jalali.isleap(),
            "month_days": jalali.days_in_month,
        }
    
    @staticmethod
    def to_gregorian(dt: datetime) -> dict:
        """Convert Gregorian datetime to standard format"""
        if dt is None:
            return None
        
        return {
            "year": dt.year,
            "month": dt.month,
            "day": dt.day,
            "hour": dt.hour,
            "minute": dt.minute,
            "second": dt.second,
            "weekday": dt.weekday(),
            "month_name": dt.strftime("%B"),
            "weekday_name": dt.strftime("%A"),
            "formatted": dt.strftime("%Y-%m-%d %H:%M:%S"),
            "date_only": dt.strftime("%Y-%m-%d"),
            "time_only": dt.strftime("%H:%M:%S"),
        }
    
    @staticmethod
    def format_datetime(dt: datetime, calendar_type: CalendarType) -> dict:
        """Format datetime based on calendar type"""
        if calendar_type == "jalali":
            return CalendarConverter.to_jalali(dt)
        else:
            return CalendarConverter.to_gregorian(dt)
    
    @staticmethod
    def format_datetime_list(dt_list: list[datetime], calendar_type: CalendarType) -> list[dict]:
        """Format list of datetimes based on calendar type"""
        return [CalendarConverter.format_datetime(dt, calendar_type) for dt in dt_list if dt is not None]


def get_calendar_type_from_header(calendar_header: Optional[str]) -> CalendarType:
    """Extract calendar type from X-Calendar-Type header"""
    if not calendar_header:
        return "gregorian"
    
    calendar_type = calendar_header.lower().strip()
    if calendar_type in ["jalali", "persian", "shamsi"]:
        return "jalali"
    else:
        return "gregorian"
