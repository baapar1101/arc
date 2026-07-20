---
doc_id: hscript.tutorial.dashboard
title: ساخت داشبورد
tags: [tutorial, dashboard]
version: 1
---

# داشبورد

```hscript
report.dashboard(columns=12)
report.title("داشبورد فروش")
report.kpi("تعداد", 10, span=4)
report.kpi("مبلغ", 1000, format="currency", span=4)
report.card("وضعیت", "فعال", span=4)
report.row_break()
report.bar_chart(table([{"m": "فروردین", "v": 3}]), x="m", y="v", span=6)
report.table(table([{"m": "فروردین", "v": 3}]), span=6)
```

- `span` عرض بلوک در شبکه ۱۲ (یا ۶/۲۴) ستونه است.
- `row_break()` ردیف را می‌بندد.
