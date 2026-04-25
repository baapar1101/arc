# مستند فنی چت وب CRM (Embed) برای توسعه‌دهندگان

این سند قرارداد **REST API** و **WebSocket** بستر چت وب را توصیف می‌کند. رابط کاربری ویجت روی سایت مشتری (مثلاً افزونهٔ وردپرس) جدا از این مخزن توسعه داده می‌شود؛ اینجا فقط بک‌اند Hesabix است.

## پیش‌نیاز دیتابیس

پس از به‌روزرسانی کد، مایگریشن زیر را اجرا کنید:

```bash
cd hesabixAPI
alembic upgrade head
```

فایل مایگریشن: `migrations/versions/20260505_000001_crm_chat_embed.py`  
جداول: `crm_chat_widgets`, `crm_chat_conversations`, `crm_chat_messages`.

برای ثبت مدل‌ها در metadata آل embیک، `import adapters.db.models.crm_chat` در `migrations/env.py` اضافه شده است. اگر در محیط شما جایی غیر از این، metadata بدون این مدل‌ها لود می‌شود، می‌توانید در `adapters/db/models/__init__.py` نیز ایمپورت مدل‌های `crm_chat` را اضافه کنید.

## اتصال روترها به اپلیکیشن

- مسیرهای مدیریتی چت زیر همان روتر CRM سوار شده‌اند: `router.include_router` در انتهای `adapters/api/v1/crm.py`.
- مسیرهای عمومی در `adapters/api/v1/public_share_links.py` با `include_router` به روتر اشتراک‌لینک‌ها اضافه شده‌اند.
- WebSocket در `adapters/api/v1/notifications_ws.py` با `include_router` کنار `/ws/notifications` ثبت شده است.

نیازی به تغییر `main.py` برای این نسخه نیست.

## جریان کاری (بازدیدکننده)

1. **قبل از چت**، فرم سمت سایت شما نام، نام خانوادگی، ایمیل و تلفن را می‌گیرد.
2. با `POST /api/v1/public/crm-chat/conversations/start` مکالمه ساخته می‌شود و **`visitor_token`** + **`conversation_id`** برمی‌گردد.
3. سپس بازدیدکننده می‌تواند با `POST /api/v1/public/crm-chat/messages` پیام بفرستد و با `GET .../messages` تاریخچه را بخواند.
4. اختیاری: برای رویداد لحظه‌ای، WebSocket بازدیدکننده (پایین) با همان `visitor_token` و `conversation_id`.

## CORS و مبدأ (Origin)

- درخواست‌های عمومی از دامنهٔ سایت مشتری به API Hesabix می‌آیند؛ باید دامنهٔ API در `allow_origins` تنظیمات CORS سرور Hesabix برای آن دامنه‌ها مجاز باشد (مثل سایر کلاینت‌های وب).
- برای هر **ویجت** می‌توان فهرست **`allowed_origins`** (لیست hostname، مثل `example.com`) ذخیره کرد. اگر خالی باشد، از نظر بک‌اند مبدأ بررسی نمی‌شود (پیشنهاد: در تولید حتماً محدود شود). سرور هدر `Origin` یا در نبود آن `Referer` را برای تشخیص host استفاده می‌کند.

## REST — عمومی (بدون `Authorization`)

پایهٔ مسیرها: همان host بک‌اند (مثلاً `https://api.example.com`).

### شروع مکالمه

`POST /api/v1/public/crm-chat/conversations/start`

بدنهٔ JSON نمونه:

```json
{
  "public_key": "<از پنل CRM پس از ساخت ویجت>",
  "first_name": "علی",
  "last_name": "رضایی",
  "email": "ali@example.com",
  "phone": "09123456789",
  "page_url": "https://customer-site.com/contact"
}
```

پاسخ موفق (داخل `data`):

- `conversation_id` (integer)
- `visitor_token` (رشتهٔ محرمانه؛ فقط برای همان مرورگر/نشست نگه دارید)
- `widget_id`

### ارسال پیام بازدیدکننده

`POST /api/v1/public/crm-chat/messages`

```json
{
  "visitor_token": "...",
  "conversation_id": 1,
  "body": "سلام، سوال دارم"
}
```

### لیست پیام‌ها (بازدیدکننده)

`GET /api/v1/public/crm-chat/conversations/{conversation_id}/messages?visitor_token=...&limit=100`

خروجی: `{ "data": { "items": [ { "id", "sender_role", "body", "created_at", ... } ] } }`

`sender_role`: `visitor` | `agent` | `system` (در حال حاضر عمدتاً visitor/agent).

## REST — پنل CRM (با API key کاربر Hesabix)

همه با هدر:

`Authorization: Bearer <api_key>`

و همان الگوی سایر APIها (مثلاً `X-Business-ID` اگر در کلاینت شما لازم است).

پایه: `/api/v1/crm/businesses/{business_id}/chat/...`

| متد | مسیر | مجوز تقریبی |
|-----|------|-------------|
| GET | `/widgets` | `crm` + view |
| POST | `/widgets` | `crm` + write |
| PATCH | `/widgets/{widget_id}` | `crm` + write |
| GET | `/conversations` | `crm` + view |
| GET | `/conversations/{id}/messages` | `crm` + view |
| POST | `/conversations/{id}/messages` | `crm` + write (پاسخ عامل) |
| PATCH | `/conversations/{id}` | `crm` + write (وضعیت، assign، lead_id، person_id) |

فیلدهای ویجت مهم: `public_key`, `allowed_origins`, `is_active`, `settings` (JSON اختیاری برای آیندهٔ UI).

## WebSocket

مسیر: **`/ws/crm-chat`** (بدون پیشوند `/api/v1`؛ همان الگوی `/ws/notifications`).

بلافاصله پس از اتصال TLS، **اولین فریم** باید JSON متنی باشد.

### احراز بازدیدکننده

```json
{
  "type": "auth",
  "role": "visitor",
  "visitor_token": "...",
  "conversation_id": 1
}
```

پاسخ موفق: `{ "type": "auth_ok", "role": "visitor", "conversation_id": 1 }`

سپس سرور رویدادهای `crm_chat.event` را برای همان مکالمه push می‌کند (مثلاً `message.created`).

### احراز عامل CRM

```json
{
  "type": "auth",
  "role": "agent",
  "api_key": "<همان Bearer>",
  "business_id": 123
}
```

پاسخ: `{ "type": "auth_ok", "role": "agent", "business_id": 123 }`

برای دریافت پیام‌های یک ترد خاص، پس از `auth_ok` برای هر مکالمه یک بار بفرستید:

```json
{ "type": "subscribe", "conversation_id": 1 }
```

قالب تقریبی رویداد:

```json
{
  "type": "crm_chat.event",
  "event": "message.created",
  "conversation_id": 1,
  "message": { "id", "conversation_id", "sender_role", "body", "user_id", "created_at" }
}
```

رویدادهای `conversation.started` و `conversation.updated` روی کانال کسب‌وکار نیز برای عامل‌های متصل broadcast می‌شوند.

## ورک‌فلو (اتوماسیون)

تریگرهای ثبت‌شده (کلید برای نود Trigger در ویرایشگر ورک‌فلو):

- `crm.chat.conversation.started`
- `crm.chat.message.received`
- `crm.chat.message.sent`
- `crm.chat.conversation.assigned`
- `crm.chat.conversation.resolved`
- `crm.chat.conversation.reopened`

بدنهٔ `trigger_data` معمولاً شامل `conversation_id`, `widget_id` و برای پیام‌ها `message_id`, `body`, `sender_role` است.

## نمونهٔ حداقلی برای افزونهٔ وردپرس

1. در تنظیمات افزونه: `API_BASE`, `public_key` (و در صورت نیاز `business_id` فقط برای ابزارهای داخلی، نه برای سایت عمومی).
2. در فرانت سایت: فرم نام/نام‌خانوادگی/ایمیل/تلفن → `conversations/start` → ذخیرهٔ `visitor_token` در `sessionStorage`.
3. ارسال پیام‌ها با `POST .../messages` و نمایش تاریخچه با `GET`.
4. اختیاری: `new WebSocket(wsBase + '/ws/crm-chat')` و ارسال فریم `auth` بازدیدکننده.
5. **`public_key` را هرگز در کد سرور وردپرس برای عملیات حساس به‌تنهایی کافی نکنید**؛ برای مدیریت ویجت فقط از توکن‌های ادمین وردپرس و درخواست سمت سرور استفاده کنید. روی سایت عمومی فقط `public_key` (همان که در embed تعمداً عمومی است) کافی است.

اگر اسکریپت ویجت را خودتان روی CDN بگذارید، آدرس آن می‌تواند بعداً فقط `public_key` را به این APIها وصل کند؛ بک‌اند Hesabix فایل JS ویجت سرو نمی‌کند.

## امنیت

- `visitor_token` مانند نشست کوتاه برای همان مکالمه است؛ طولانی نگه ندارید و در لاگ‌های عمومی ننویسید.
- محدودیت نرخ (rate limit) در این نسخهٔ اولیه روی اندپوینت‌های عمومی به‌صورت سراسری به عهدهٔ فایروال/زیرساخت است؛ در صورت نیاز بعداً در اپلیکیشن اضافه می‌شود.

---

سؤالات یا تغییرات قرارداد API را می‌توان در کنار این سند نسخه‌گذاری کرد (مثلاً prefix `v2` در آینده).
