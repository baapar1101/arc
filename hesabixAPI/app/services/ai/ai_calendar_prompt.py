"""
بلوک prompt تقویم برای چت AI — تفسیر و نمایش تاریخ بر اساس تنظیم کاربر.
"""
from __future__ import annotations

from typing import Optional

<<<<<<< HEAD
from app.core.business_calendar import business_timezone_name
from app.core.calendar import CalendarConverter, CalendarType
=======
from app.core.business_calendar import business_today
from app.core.calendar import CalendarType
from app.core.date_input import format_user_date
>>>>>>> github/Huma


def build_calendar_context_prompt_block(
    calendar_type: CalendarType = "jalali",
    *,
    business_id: Optional[int] = None,
) -> str:
<<<<<<< HEAD
    """قوانین تقویم (پایدار — بدون ساعت لحظه‌ای؛ برای business_anchor)."""
    _ = business_id  # سازگاری با call-siteهای قبلی
    cal_label = "شمسی (جلالی)" if calendar_type == "jalali" else "میلادی (Gregorian)"
=======
    today = business_today(business_id)
    today_display = format_user_date(today, calendar_type=calendar_type)
    today_iso = today.isoformat()
    cal_label = "شمسی (جلالی)" if calendar_type == "jalali" else "میلادی (Gregorian)"

>>>>>>> github/Huma
    example_from = "1404/01/01" if calendar_type == "jalali" else "2025-03-21"
    example_to = "1404/01/31" if calendar_type == "jalali" else "2025-04-20"

    return f"""
## تقویم و تاریخ (الزامی)

- تقویم انتخاب‌شده کاربر: **{cal_label}** (`calendar_type={calendar_type}`)
<<<<<<< HEAD
- **الان** (تاریخ و ساعت دقیق) در بلوک جداگانهٔ «زمان جاری» در همین prompt آمده — از آن برای «امروز»، «الان» و بازه‌های نسبی استفاده کن.
=======
- امروز (نمایشی): **{today_display}** — معادل میلادی DB: `{today_iso}`
>>>>>>> github/Huma

### قوانین
1. عبارات کاربر («فروردین»، «ماه گذشته»، «هفته اخیر») را با تقویم **{cal_label}** تفسیر کن.
2. برای بازه‌های مبهم ابتدا `resolve_date_range` را صدا بزن (relative، jalali_year/month، fiscal_year_id).
3. در **function call** تاریخ‌ها را به **میلادی ISO** (`YYYY-MM-DD`) بفرست؛ سیستم ورودی شمسی `YYYY/MM/DD` را هم می‌پذیرد.
4. در **پاسخ متنی** تاریخ را به تقویم کاربر (**{cal_label}**) نمایش بده؛ از ISO خام در متن کاربر پرهیز کن.
5. اگر سال مالی مدنظر است: `get_current_fiscal_year` یا `list_fiscal_years` سپس `resolve_date_range(fiscal_year_id=…)`.

### مثال بازه (تقویم فعلی)
- from_date: `{example_from}` → to_date: `{example_to}` (در tool به ISO تبدیل می‌شود)
""".strip()
<<<<<<< HEAD


def build_datetime_now_prompt_block(
    calendar_type: CalendarType = "jalali",
    *,
    business_id: Optional[int] = None,
) -> str:
    """زمان جاری per-request — شمسی و میلادی با timezone کسب‌وکار."""
    from app.core.business_calendar import business_now

    now = business_now(business_id)
    tz_name = business_timezone_name(business_id)
    jalali = CalendarConverter.to_jalali(now)
    gregorian = CalendarConverter.to_gregorian(now)
    cal_label = "شمسی (جلالی)" if calendar_type == "jalali" else "میلادی (Gregorian)"

    return f"""
## زمان جاری (الزامی — per-request)

- منطقهٔ زمانی کسب‌وکار: **{tz_name}**
- **الان — شمسی (جلالی):** {jalali["formatted"]} ({jalali["weekday_name"]}، {jalali["month_name"]} {jalali["year"]})
- **الان — میلادی (Gregorian):** {gregorian["formatted"]} ({gregorian["weekday_name"]}, {gregorian["month_name"]} {gregorian["year"]})
- تاریخ DB (میلادی ISO): `{gregorian["date_only"]}`

در پاسخ به کاربر تاریخ/ساعت را با تقویم **{cal_label}** نمایش بده؛ برای tool و DB از میلادی ISO استفاده کن.
""".strip()
=======
>>>>>>> github/Huma
