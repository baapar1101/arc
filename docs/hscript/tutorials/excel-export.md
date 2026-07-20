---
doc_id: hscript.tutorial.excel-export
title: خروجی Excel
tags: [tutorial, excel]
version: 1
---

# خروجی Excel

از استودیو دکمه Excel را بزنید یا:

`POST /api/v1/businesses/{id}/hscript/excel`

Workbook شامل:
- شیت «خلاصه» برای KPI/کارت
- یک شیت برای هر جدول
- شیت «نمودارها» با دادهٔ خام نمودارها

نیازمند `reports.export` است.
