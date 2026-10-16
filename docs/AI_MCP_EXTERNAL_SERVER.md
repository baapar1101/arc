# اتصال امن دستیارهای هوش مصنوعی به حسابیکس از طریق MCP

## معماری و وضعیت پیاده‌سازی

`POST /api/v1/ai/mcp` یک سرور راه‌دور MCP مبتنی بر Streamable HTTP است. ابزارها از registry اصلی AI حسابیکس گرفته می‌شوند و همان مجوزهای دامنه‌ای کاربر را رعایت می‌کنند. ابزار `ask_hesabix_agent` نیز چرخهٔ ایجنت را در حالت Analyzer و محدود به کسب‌وکار متصل اجرا می‌کند. قابلیت‌های MCP شامل ابزارها، یک Resource پایهٔ کسب‌وکار و Promptهای راهنمای گزارش‌گیری است.

برای اتصال دستیارهایی مانند ChatGPT، OAuth Authorization Code به همراه PKCE با `S256`، کشف OAuth، ثبت کلاینت DCR و Client ID Metadata Document (برای دامنهٔ مجاز ChatGPT)، رضایت کاربر، refresh token چرخشی، لغو توکن و انتخاب کسب‌وکار پیاده شده است. کلاینت‌های قدیمی‌تر می‌توانند با اتصال Bearer دستی که در API اتصال‌های MCP ساخته می‌شود نیز کار کنند.

## استقرار

در محیط production مقدار origin عمومی و ثابت API را تنظیم کنید؛ این مقدار منبع issuer و audience است و از `Host` درخواست گرفته نمی‌شود:

```env
MCP_PUBLIC_BASE_URL=https://agent.hesabix.ir
```

HTTPS در production اجباری است. سپس migrationها را اجرا کنید:

```powershell
cd hesabixAPI
alembic upgrade head
```

Originهای مرورگری و hostهای callback مجاز را در deployment مطابق کلاینت‌های مورد استفاده محدود کنید. مقادیر پیش‌فرض ChatGPT و Claude را پوشش می‌دهند. دامنه‌های دیگر باید با `MCP_ALLOWED_ORIGINS` و `MCP_OAUTH_TRUSTED_REDIRECT_HOSTS` صریحاً اضافه شوند. `MCP_CIMD_ALLOWED_HOSTS` فقط باید به دامنه‌های قابل‌اعتمادِ سند هویت کلاینت محدود شود؛ پیش‌فرض آن `chatgpt.com` است. مقدارهای list در Pydantic Settings به صورت JSON آرایه‌ای از رشته‌ها تنظیم می‌شوند.

## اتصال در ChatGPT

1. آدرس MCP را به صورت `https://agent.hesabix.ir/api/v1/ai/mcp` به عنوان Custom MCP server اضافه کنید.
2. روش احراز هویت را OAuth بگذارید و جریان اتصال را کامل کنید.
3. وارد حساب حسابیکس شوید، کسب‌وکار درست را انتخاب کنید و فقط مجوزهای مورد نیاز را تایید کنید.
4. مجوز نوشتن به صورت پیش‌فرض داده نمی‌شود. فقط مالک کسب‌وکار می‌تواند گزینهٔ آن را در صفحهٔ رضایت انتخاب کند.

سرور Protected Resource Metadata را در `/.well-known/oauth-protected-resource/api/v1/ai/mcp` و Authorization Server Metadata را در `/.well-known/oauth-authorization-server` منتشر می‌کند. پاسخ 401 نیز آدرس metadata را در `WWW-Authenticate` می‌دهد. Client ID Metadata برای ChatGPT و ثبت پویای کلاینت برای کلاینت‌های سازگار ارائه می‌شوند.

## جریان OAuth

1. کلاینت MCP metadata را کشف می‌کند و برای URL دقیق MCP، پارامتر `resource` را می‌فرستد.
2. کلاینت از CIMD مجاز یا DCR یک شناسهٔ کلاینت می‌گیرد.
3. authorization endpoint، callback ثبت‌شده، `state` در صورت ارسال، `resource` و PKCE `S256` را اعتبارسنجی می‌کند.
4. کاربر از OTP و کپچا وارد می‌شود. API key نشست OTP بلافاصله به یک مجوز رضایت یک‌بارمصرف و محدود به همان درخواست تبدیل و لغو می‌شود.
5. کاربر کسب‌وکار و scope را انتخاب می‌کند. عضویت در لحظهٔ تایید و هنگام هر استفاده از ابزار دوباره بررسی می‌شود.
6. authorization code تصادفی، کوتاه‌عمر، یک‌بارمصرف و به client، redirect URI، کسب‌وکار، resource و PKCE متصل صادر می‌شود.
7. token endpoint کد را با PKCE تعویض می‌کند و access token پانزده‌دقیقه‌ای Bearer با audience همان MCP می‌دهد. Refresh token سی‌روزه فقط در صورت درخواست و رضایت `offline_access` صادر و در هر refresh چرخانده می‌شود.
8. لغو refresh token، replay آن، یا لغو اتصال، تمام توکن‌های همان grant را باطل می‌کند.

## مرزهای دسترسی و محافظت از داده

- `business_id` فقط از رضایت OAuth یا credential سمت سرور گرفته می‌شود؛ مدل نمی‌تواند tenant درخواست را تعیین کند.
- هر credential دقیقاً به یک کسب‌وکار وصل است. عضویت، حذف کسب‌وکار، فعال بودن کاربر، scope و audience در درخواست‌ها دوباره اعتبارسنجی می‌شوند.
- خواندن با `ai:tools:read` انجام می‌شود. نوشتن نیازمند `ai:tools:write` و تایید مالک همان کسب‌وکار است؛ scope نوشتن از RPC یا آرگومان‌های مدل قابل جعل نیست.
- ابزارهایی که registry برای کاربر یا کسب‌وکار جاری مجاز نمی‌کند اصلاً در فهرست MCP ظاهر نمی‌شوند و فراخوانی مستقیم‌شان نیز رد می‌شود.
- ایجنت MCP در حالت Analyzer اجرا می‌شود و خودکار عملیات نوشتنی انجام نمی‌دهد.
- authorization code، access token، refresh token و مجوز رضایت خام در دیتابیس ذخیره نمی‌شوند؛ hash ذخیره می‌شود. کد و توکن در log ثبت نمی‌شوند.
- Redirect URI باید دقیقاً با ثبت کلاینت برابر و میزبانش در allowlist deployment باشد. CIMD فقط از HTTPS و hostهای از پیش مجاز خوانده می‌شود و redirect دنبال نمی‌شود.
- Origin مرورگرهای MCP باید در allowlist باشد؛ درخواست‌های غیرمرورگری بدون `Origin` پذیرفته می‌شوند.
- توکن OAuth فقط به resource canonical همین سرور صادر می‌شود. توکن منقضی، لغوشده یا متعلق به resource دیگر رد می‌شود.

## مدیریت و سازگاری

APIهای قبلی credential دستی همچنان موجودند:

- `POST /api/v1/ai/mcp/connections` ساخت Bearer token محدود به کسب‌وکار
- `GET /api/v1/ai/mcp/connections?business_id=<id>` فهرست اتصالات
- `DELETE /api/v1/ai/mcp/connections/<connection_id>` لغو اتصال؛ برای OAuth، کل grant و refresh tokenهایش نیز لغو می‌شوند

سرور نسخه‌های قدیمی MCP تا `2025-11-25` را با `initialize` و نسخهٔ `2026-07-28` را با متادیتای هر درخواست و `server/discover` می‌پذیرد. درخواست‌های modern باید `MCP-Protocol-Version` و `Mcp-Method` را مطابق body بفرستند؛ درخواست‌های `tools/call`، `resources/read` و `prompts/get` همچنین به `Mcp-Name` منطبق نیاز دارند.

## عملیات نگهداری

کلید `MCP_PUBLIC_BASE_URL` باید با آدرس اتصال خارجی و proxy TLS هم‌خوان باشد. بعد از تغییر دامنهٔ عمومی، metadata، redirect allowlist و URL ثبت‌شده در کلاینت‌ها را به‌روز کنید. ثبت DCR و endpointهای OAuth دارای rate limit هستند. اتصال‌ها را از API مدیریت لغو کنید؛ نشست‌های OAuth در خروجی فهرست اتصال‌ها، مثل credentialهای دستی، به شکل یکپارچهٔ قابل‌نمایش نیستند، اما با revoke اتصال OAuth هر grant از endpoint مدیریت اتصال قابل باطل‌سازی است.
