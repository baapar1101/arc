---
doc_id: hscript.security
title: امنیت HScript
tags: [security]
version: 1
---

# امنیت

- `business_id` فقط از Context سرور می‌آید و از params حذف می‌شود.
- داده فقط از Data Gateway با فیلتر کسب‌وکار جاری خوانده می‌شود.
- ویژگی‌ها و نام‌های شروع‌شونده با `_` ممنوع‌اند.
- کلمات کلیدی خطرناک (`import`, `eval`, `class`, ...) مسدودند.
- خروجی فقط JSON-safe است.
