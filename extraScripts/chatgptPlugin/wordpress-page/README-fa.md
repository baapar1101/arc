# صفحهٔ اتصال Hesabix به ChatGPT

این پوشه سورس صفحهٔ اختصاصی `/chatgpt/` در پوستهٔ وردپرس `hesabix2` را نگه می‌دارد.

## فایل‌ها

- `page-chatgpt-hesabix.php`: قالب برگهٔ وردپرس؛ از هدر و فوتر پوسته استفاده می‌کند.
- `chatgpt-connector.css`: طراحی واکنش‌گرا با کلاس‌های محدود به همین صفحه و پالت `hesabix2`.
- `chatgpt-connector.js`: کپی نشانی MCP.
- `hesabix-chatgpt-nav.php`: افزونهٔ MU برای افزودن لینک صفحه به ستون «هوشمندسازی» منوی محصول.

## نصب در وردپرس

- فایل PHP قالب در ریشهٔ پوستهٔ فعال قرار می‌گیرد.
- CSS و JavaScript در مسیرهای `assets/css/` و `assets/js/` همان پوسته قرار می‌گیرند.
- افزونهٔ ناوبری در `wp-content/mu-plugins/` قرار می‌گیرد.
- برگه‌ای با نامک `chatgpt` و قالب `page-chatgpt-hesabix.php` به صفحهٔ آنلاین وصل می‌شود.

نشانی canonical فعلی MCP درج‌شده در صفحه `https://hsxn.hesabix.ir/api/v1/ai/mcp` است. از همین میزبان برای سازگاری دقیق با مقدار `resource` و `issuer` در OAuth استفاده کنید؛ میزبان قدیمی `arc.hesabix.ir` فراداده را با نام canonical یعنی `hsxn.hesabix.ir` برمی‌گرداند.

صفحهٔ آنلاین روش نصب ZIP در ChatGPT وب را راهنمایی می‌کند: دریافت فایل، رفتن به Admin console و Plugins، انتخاب Add و Upload plugin، و سپس تکمیل اتصال/مجوزدهی Hesabix. امکان آپلود به سطح دسترسی حساب یا فضای کاری وابسته است. بارگذاری ZIP به‌تنهایی اپ متصل را مجاز نمی‌کند؛ کاربر باید ورود و مجوزهای اتصال حسابیکس را هم کامل کند. در صورت نبود گزینهٔ Upload plugin، دسترسی Plugins را از مدیر فضای کاری پیگیری کنید.

منبع رسمی مراحل: https://help.openai.com/en/articles/20001256-plugins-in-chatgpt
