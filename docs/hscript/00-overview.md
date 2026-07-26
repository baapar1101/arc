---
doc_id: hscript.overview
title: معرفی HScript
tags: [overview, intro]
version: 1
---

# HScript چیست؟

HScript زبان امن و محدود حسابیکس برای ساخت گزارش‌های سفارشی است.
نحو آن شبیه Python است، اما روی یک Interpreter اختصاصی با AST سفید اجرا می‌شود و به سیستم‌عامل، دیتابیس خام، یا سرویس‌های داخلی دسترسی ندارد.

## قابلیت‌ها
- خواندن داده از ماژول‌های مجاز (`invoices`, `customers`, `persons`, `products`, `payments`, `banks`, `warehouses`, `debtors`, `creditors`)
- محاسبه، حلقه، شرط، تابع و جدول‌های HTable (`where`, `join`, `pivot`, …)
- ساخت عنوان، KPI، جدول، نمودار، QR و بارکد
- خروجی ساختاریافته Report Spec برای نمایش در پنل و PDF
- پارامترهای فرم با `# @param` و کاتالوگ دستورپخت در استودیو

## غیرمجاز
- `import`، فایل، شبکه، SQL، environment، reflection
