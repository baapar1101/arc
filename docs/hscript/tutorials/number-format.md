---
doc_id: hscript.tutorial.number-format
title: قالب‌بندی اعداد
tags: [tutorial, number, format]
version: 1
---

# قالب‌بندی اعداد

```hscript
report.number_format(style="western")  # 1,234,567.50
report.number_format(style="fa")       # 1٬234٬567٫50

report.kpi("فروش", 12500000, format="currency")
report.kpi("رشد", 12.5, format="percent")
report.table(rows, formats={"total_debit": "currency", "rate": "number:2"})
report.text(format_number(9999, "number"))
```

قالب‌ها: `integer`, `number`, `number:2`, `currency`, `decimal:3`, `percent`, `raw`
EOF
