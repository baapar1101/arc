---
doc_id: hscript.reference.htable
title: متدهای HTable
tags: [reference, table]
version: 1
---

# HTable

علاوه بر `filter/select/sort/limit/top/sum/count/avg/group_by/group_sum`:

```hscript
rows.where("amount", "gt", 1000)
rows.where(amount__gte=1000, status="paid")
rows.distinct("person_id")
joined = invoices.join(customers, left_on="person_id", right_on="id", how="left")
pivoted = rows.pivot(index="month", columns="product", values="amount", agg="sum")
renamed = rows.rename(total_debit="amount")
```

عملگرهای where: `eq ne gt gte lt lte contains startswith in isnull`
پسوند kwargs: `field__gt=…`
