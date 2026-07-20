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
- خواندن داده از ماژول‌های مجاز (`invoices`, `customers`, `products`, `payments`)
- محاسبه، حلقه، شرط، تابع
- ساخت عنوان، KPI، جدول، نمودار، QR و بارکد
- خروجی ساختاریافته Report Spec برای نمایش در پنل و PDF

## غیرمجاز
- `import`، فایل، شبکه، SQL، environment، reflection
