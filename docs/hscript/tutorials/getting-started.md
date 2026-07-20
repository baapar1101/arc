---
doc_id: hscript.tutorial.getting-started
title: شروع سریع
tags: [tutorial, beginner]
version: 1
example_id: ex_hello_kpi
---

# اولین گزارش

```hscript
report.title("خلاصه فروش")
rows = invoices.this_month()
report.kpi("تعداد فاکتور", rows.count())
report.table(rows.limit(20))
```

ورودی تاریخ را می‌توانید با `params.get("start")` بخوانید.
