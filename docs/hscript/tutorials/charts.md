---
doc_id: hscript.tutorial.charts
title: نمودارها
tags: [tutorial, charts]
version: 1
---

# نمودار

```hscript
data = table([{"name": "فروردین", "total": 10}, {"name": "اردیبهشت", "total": 18}])
report.bar_chart(data, x="name", y="total", title="روند")
report.pie_chart(data, label="name", value="total")
report.line_chart(data, x="name", y="total")
```
