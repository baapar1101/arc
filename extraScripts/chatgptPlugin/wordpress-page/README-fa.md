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

اتصال شخصی در ChatGPT از مسیر Plugins → Add custom MCP server انجام می‌شود؛ نشانی canonical سرور را وارد کنید، OAuth را کامل کنید و ابزارها را مرور کنید. ZIP صفحه برای توسعه‌دهنده‌ای است که می‌خواهد پلاگین را از پرتال OpenAI بارگذاری و برای بازبینی/انتشار آماده کند؛ ZIP به‌تنهایی اتصال شخصی نمی‌سازد. انتشار بسته به اتصال و تأیید دامنه در پرتال توسعه‌دهندگان نیاز دارد.

منبع رسمی بسته‌بندی و اتصال MCP: https://developers.openai.com/plugins/build/plugins
