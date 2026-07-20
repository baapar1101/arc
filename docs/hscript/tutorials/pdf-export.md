---
doc_id: hscript.tutorial.pdf-export
title: خروجی PDF
tags: [tutorial, pdf]
version: 1
---

# خروجی PDF

پس از ساخت Spec با `report.*` می‌توانید از استودیو دکمه PDF را بزنید یا API زیر را صدا بزنید:

`POST /api/v1/businesses/{id}/hscript/pdf`

بدنه نمونه:

```json
{
  "source_code": "report.title(\"گزارش\")\nreport.kpi(\"n\", 1)\n",
  "params": {}
}
```

یا با Spec از پیش اجرا شده:

```json
{ "spec": { "version": 1, "title": "...", "blocks": [] } }
```

نیازمند مجوز `reports.export` است. متن‌ها در HTML قبل از WeasyPrint escape می‌شوند.
