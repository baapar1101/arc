---
doc_id: hscript.recipe.top-customers
title: مشتریان برتر
tags: [recipe, example]
version: 1
example_id: ex_top_customers
---

# دستورپخت

```hscript
report.title("۱۰ مشتری اخیر فاکتور")
rows = invoices.this_month(limit=200)
report.kpi("تعداد", rows.count())
report.table(rows.limit(10))
```
