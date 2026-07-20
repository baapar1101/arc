---
doc_id: hscript.reference.report-blocks
title: بلوک‌های گزارش
tags: [reference, report]
version: 1
---

# report.*

`title`, `heading`, `paragraph`, `text`, `kpi`, `card`, `table`, `bar_chart`, `line_chart`, `pie_chart`, `area_chart`, `scatter_chart`, `gauge`, `section`, `page_break`, `row_break`, `qr`, `barcode`, `dashboard`, `calendar`, `set_meta`

## تقویم

```hscript
report.calendar("jalali")   # یا gregorian
```

تاریخ‌های جدول با همان تقویم قالب می‌شوند. توابع کمکی: `format_date(...)` و `dates.format(...)` / `dates.parse(...)`.
