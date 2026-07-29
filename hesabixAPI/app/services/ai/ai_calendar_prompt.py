"""
بلوک prompt تقویم برای چت AI — تفسیر و نمایش تاریخ بر اساس تنظیم کاربر.
"""
from __future__ import annotations

from typing import Optional

from app.core.business_calendar import business_today
from app.core.calendar import CalendarType
from app.core.date_input import format_user_date


def build_calendar_context_prompt_block(
    calendar_type: CalendarType = "jalali",
    *,
    business_id: Optional[int] = None,
) -> str:
    today = business_today(business_id)
    today_display = format_user_date(today, calendar_type=calendar_type)
    today_iso = today.isoformat()
    cal_label = "شمسی (جلالی)" if calendar_type == "jalali" else "میلادی (Gregorian)"

    example_from = "1404/01/01" if calendar_type == "jalali" else "2025-03-21"
    example_to = "1404/01/31" if calendar_type == "jalali" else "2025-04-20"

    return f"""
## تقویم و تاریخ (الزامی)

- تقویم انتخاب‌شده کاربر: **{cal_label}** (`calendar_type={calendar_type}`)
- امروز (نمایشی): **{today_display}** — معادل میلادی DB: `{today_iso}`

### قوانین
1. عبارات کاربر («فروردین»، «ماه گذشته»، «هفته اخیر») را با تقویم **{cal_label}** تفسیر کن.
2. برای بازه‌های مبهم ابتدا `resolve_date_range` را صدا بزن (relative، jalali_year/month، fiscal_year_id).
3. در **function call** تاریخ‌ها را به **میلادی ISO** (`YYYY-MM-DD`) بفرست؛ سیستم ورودی شمسی `YYYY/MM/DD` را هم می‌پذیرد.
4. در **پاسخ متنی** تاریخ را به تقویم کاربر (**{cal_label}**) نمایش بده؛ از ISO خام در متن کاربر پرهیز کن.
5. اگر سال مالی مدنظر است: `get_current_fiscal_year` یا `list_fiscal_years` سپس `resolve_date_range(fiscal_year_id=…)`.

### مثال بازه (تقویم فعلی)
- from_date: `{example_from}` → to_date: `{example_to}` (در tool به ISO تبدیل می‌شود)
""".strip()
