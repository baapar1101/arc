---
doc_id: hscript.recipe.sales-dashboard
title: داشبورد فروش ماه
tags: [recipe, example, dashboard]
version: 1
example_id: ex_sales_dashboard
---

# دستورپخت: داشبورد فروش ماه

```hscript
# @param limit integer "سقف فاکتور" default=100
report.calendar("jalali")
report.number_format(style="western")
report.dashboard(columns=12)
report.title("داشبورد فروش ماه جاری")
rows = invoices.this_month(limit=params.get("limit", 100))
report.kpi("تعداد فاکتور", rows.count(), format="integer", span=4)
report.kpi("جمع بدهکار", rows.sum("total_debit"), format="currency", span=4)
report.kpi("جمع بستانکار", rows.sum("total_credit"), format="currency", span=4)
report.row_break()
top_rows = rows.top(8, by="total_debit")
report.bar_chart(top_rows, x="code", y="total_debit", title="بیشترین مبالغ", span=6)
report.table(rows.limit(12), columns=["code", "document_date", "total_debit"], formats={"total_debit": "currency"}, title="آخرین فاکتورها", span=6)
```
