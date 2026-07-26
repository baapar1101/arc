---
doc_id: hscript.api.debtors
title: API: debtors / creditors
tags: [api, debtors, creditors]
version: 1
---

# debtors و creditors

## debtors
- `debtors.filter(search?, min_balance?, from_date?, to_date?, limit?)`
- `debtors.all(limit?)`
- `debtors.top(n=10)`

فیلدها: `person_id`, `code`, `name`, `balance`, `debt`

## creditors
- `creditors.filter(...)` مشابه
- `creditors.top(n=10)`

فیلدها: `person_id`, `code`, `name`, `balance`, `credit`
