---
doc_id: hscript.tutorial.calendar
title: تقویم شمسی و میلادی
tags: [tutorial, calendar, date]
version: 1
---

# تقویم در HScript

حسابیکس دو تقویم دارد: `jalali` (شمسی) و `gregorian` (میلادی).

## تنظیم تقویم گزارش

```hscript
report.calendar("jalali")
# یا
report.calendar("gregorian")
```

این مقدار در `meta.calendar_type` ذخیره می‌شود و تاریخ‌های جدول با همان قالب نمایش داده می‌شوند.

اگر اسکریپت `report.calendar` نزند، پیش‌فرض از هدر `X-Calendar-Type` کلاینت می‌آید (معمولاً همان تقویم پنل).

## قالب‌بندی دستی

```hscript
report.calendar("jalali")
d = format_date("2026-07-20")
report.kpi("امروز", d)

# یا با ماژول dates
report.text(dates.format("2026-07-20", calendar="gregorian"))
```

## فیلتر با تاریخ جلالی

وقتی تقویم گزارش `jalali` باشد، فیلترها هم جلالی را می‌فهمند:

```hscript
report.calendar("jalali")
rows = invoices.filter(from_date="1404/04/01", to_date="1404/04/31", limit=100)
report.table(rows, columns=["code", "document_date", "total_debit"])
```

سال بین ۱۲۰۰ تا ۱۵۰۰ در رشتهٔ `YYYY/MM/DD` به‌صورت جلالی تفسیر می‌شود.
EOF
