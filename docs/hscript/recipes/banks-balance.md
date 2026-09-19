---
doc_id: hscript.recipe.banks-balance
title: مانده حساب‌های بانکی
tags: [recipe, example, banks]
version: 1
example_id: ex_banks_balance
---

# دستورپخت: مانده بانک‌ها

```hscript
report.calendar("jalali")
report.number_format(style="western")
report.title("مانده حساب‌های بانکی")
rows = banks.all(limit=50)
report.kpi("تعداد حساب", rows.count(), format="integer", span=6)
report.kpi("جمع مانده", rows.sum("balance"), format="currency", span=6)
report.row_break()
report.table(rows, columns=["code", "name", "branch", "balance"], formats={"balance": "currency"}, span=12)
```
