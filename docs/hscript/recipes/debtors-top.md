---
doc_id: hscript.recipe.debtors-top
title: بدهکاران برتر
tags: [recipe, example, debtors]
version: 1
example_id: ex_debtors_top
---

# دستورپخت: بدهکاران برتر

```hscript
# @param limit integer "تعداد" default=10
report.calendar("jalali")
report.number_format(style="western")
report.title("بدهکاران برتر")
n = params.get("limit", 10)
rows = debtors.top(n)
report.kpi("تعداد", rows.count(), format="integer", span=6)
report.kpi("جمع بدهی", rows.sum("debt"), format="currency", span=6)
report.row_break()
report.bar_chart(rows, x="name", y="debt", title="بیشترین بدهی", span=12)
report.table(rows, columns=["code", "name", "debt"], formats={"debt": "currency"}, span=12)
```
