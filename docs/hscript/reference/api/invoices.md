---
doc_id: hscript.api.invoices
title: invoices API
tags: [api, invoices]
version: 1
permissions: [reports.read]
---

# invoices

- `invoices.filter(document_type="invoice_sales", from_date=..., to_date=..., limit=100)`
- `invoices.this_month()`
- `invoices.last_month()`
- `invoices.all(limit=100)`
- `invoices.count(...)`

خروجی: `Table` با متدهای `filter`, `select`, `sort`, `limit`, `top`, `sum`, `count`, `group_sum`.
