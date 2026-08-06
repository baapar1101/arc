# افزونه اتصال به آستریکس و ایزابل — سند اجرایی کامل

**کد افزونه:** `asterisk_issabel_connector`  
**نام نمایشی:** اتصال به آستریکس و ایزابل  
**دسته مارکت‌پلیس:** `integration`  
**وضعیت سند:** در حال پیاده‌سازی فعال  
**نسخه سند:** `1.1.0`  
**تاریخ:** ۱۴۰۵/۰۵/۱۲ (2026-08-03)

> به‌روزرسانی پیاده‌سازی: فاز ۰ و ۱ کامل شده؛ فازهای ۲ (ضبط/گزارش/CRM عمیق)، ۳ (داشبورد زنده/کنترل تماس)، ۴ (DLQ/متریک) و اسکفولد فاز ۵ (Softphone) در کد پیاده شده‌اند. **هسته Softphone Media Relay (فاز ۵/سند جدا) از ۱۴۰۵/۰۵/۱۵ در حال پیاده‌سازی است** — جزئیات و چک‌لیست: `TELEPHONY_SOFTPHONE_MEDIA_RELAY_EXECUTION_SCENARIO.md`.

این سند مرجع واحد برای پیاده‌سازی افزونه تلفنی حسابیکس است. هر فاز باید فقط بر اساس همین سند و چک‌لیست پذیرش همان فاز انجام شود.

---

## ۰. خلاصه اجرایی

حسابیکس امروز CRM، اشخاص، مانده حساب، فعالیت نوع `call`، اعلان WebSocket، مارکت‌پلیس افزونه و چندسکویی Flutter (وب / اندروید / iOS / دسکتاپ) دارد، اما **هیچ لایه CTI/Asterisk ندارد**.

افزونه باید:

1. هر کسب‌وکار را به یک یا چند PBX (Issabel/Asterisk) وصل کند.
2. تماس ورودی را با Screen Pop به اپراتور نشان دهد.
3. Click-to-Call از داخل CRM انجام دهد.
4. تاریخچه کامل تماس + ضبط را ذخیره کند.
5. با CRM، اشخاص، مانده حساب، چک، فاکتور و Workflow یکپارچه شود.
6. داخلی هر کاربر را **به‌ازای هر کسب‌وکار** جدا نگه دارد.
7. روی وب، موبایل و دسکتاپ UI یکپارچه و باکیفیت داشته باشد.

**تصمیم‌های قفل‌شده این سند (پیش‌فرض محصولی):**

| موضوع | تصمیم |
|--------|--------|
| تماس از CRM در MVP | Click-to-Call با AMI Originate (نه Softphone) |
| Softphone WebRTC | فقط فاز ۵ (اختیاری) |
| نصب روی ایزابل | الزامی — Hesabix Telephony Connector |
| تاریخچه تماس | جدول first-class `telephony_calls` + Activity اختیاری |
| تیکت از تماس | در MVP = وظیفه/فعالیت CRM؛ ماژول تیکت کسب‌وکار خارج از scope |
| ضبط مکالمه | لینک/پروکسی از PBX + آپلود اختیاری به `file_storage` |
| پلتفرم UI | یک Flutter codebase — Responsive + Adaptive برای Web/Mobile/Desktop |

---

## ۱. هدف، محدوده و خارج از محدوده

### ۱.۱ هدف

ارائه یک افزونه مارکت‌پلیس که کسب‌وکار بتواند مرکز تلفن Issabel/Asterisk خود را به حسابیکس وصل کند و اپراتورها بتوانند تماس را ببینند، بگیرند، ثبت کنند و با پرونده مشتری ادامه دهند — روی وب، موبایل و دسکتاپ.

### ۱.۲ داخل محدوده (In Scope)

- لایسنس افزونه، تنظیمات PBX، نگاشت کاربر↔داخلی
- Connector سمت Issabel (AMI + webhook)
- Screen Pop، Click-to-Call، تاریخچه، ضبط، اعلان‌ها
- یکپارچگی با Person / Lead / Deal / CrmActivity / مانده حساب / چک / فاکتور
- گزارش‌ها و داشبورد لحظه‌ای (فازهای بعدی)
- کنترل‌های پیشرفته Hold/Transfer/Hangup (فاز ۳+)
- UI کامل چندسکویی

### ۱.۳ خارج از محدوده (Out of Scope)

- جایگزینی کامل Issabel (IVR builder، مدیریت کامل dialplan)
- ماژول تیکت پشتیبانی کسب‌وکار جدید (تا وقتی جداگانه تعریف نشود)
- تماس ویدیویی / تماس AI voice موجود حسابیکس
- یکپارچگی با PBXهای غیر Asterisk-family (مثل ۳CX، FreePBX جدا — مگر سازگاری AMI حفظ شود)
- ضبط مکالمه قانونی/قضاوت حقوقی (مسئولیت پیکربندی با مشتری است)

### ۱.۴ فرضیات عملیاتی ایران

- Issabel معمولاً پشت NAT/فایروال است → Connector خروجی HTTPS می‌زند؛ پورت ورودی روی PBX لازم نیست.
- Caller ID با فرمت‌های `09…` / `9…` / `98…` / `+98…` / شهری می‌آید → نرمال‌سازی اجباری.
- اپراتور معمولاً Softphone یا تلفن رومیزی SIP دارد → Originate کافی است.
- کیفیت شبکه شعب متغیر است → UI باید offline-tolerant برای تاریخچه محلی نباشد، ولی وضعیت اتصال Connector را شفاف نشان دهد.

---

## ۲. نقش‌ها و سناریوهای کلیدی

### ۲.۱ نقش‌ها

| نقش | توضیح |
|------|--------|
| مالک کسب‌وکار | خرید افزونه، اتصال PBX، تعریف دسترسی |
| مدیر تلفن | نگاشت داخلی‌ها، صف‌ها، تنظیمات شناسایی شماره |
| اپراتور فروش/پشتیبانی | دریافت Pop، تماس خروجی، ثبت نتیجه |
| ناظر/سرپرست | داشبورد زنده، گزارش عملکرد، گوش دادن به ضبط (با مجوز) |

### ۲.۲ سناریوهای پذیرش محصول (Must-pass)

1. **ورودی شناخته‌شده:** زنگ → Pop با نام + مانده → پاسخ → ثبت خودکار → یادداشت پس از تماس.
2. **ورودی ناشناس:** Pop ناشناس → ایجاد Lead یا Person → ثبت تماس روی همان موجودیت.
3. **خروجی Click-to-Call:** از پروفایل مشتری → Originate → وضعیت زنده → ثبت خروجی.
4. **از دست‌رفته:** Missed → اعلان + ردیف تاریخچه + (اختیاری) وظیفه پیگیری.
5. **چند کسب‌وکار:** یک User با دو داخلی در دو Business — با تعویض کسب‌وکار، context تلفن عوض شود.
6. **قطع Connector:** UI وضعیت «قطع از مرکز تلفن» نشان دهد؛ تماس‌ها در صف Connector بعداً sync شوند.

---

## ۳. معماری سیستم

### ۳.۱ نمای کلی

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter Client (Web/Mobile/Desktop)         │
│  Phone Bar · Screen Pop · Dialer · History · Live Dashboard     │
└───────────────────────────────▲─────────────────────────────────┘
                                │ REST + WebSocket (/ws/notifications
                                │  + /ws/telephony اختیاری)
┌───────────────────────────────┴─────────────────────────────────┐
│                     Hesabix API (FastAPI)                        │
│  telephony_* routers · plugin gate · phone normalizer            │
│  CRM / Person / Balance / Check / FileStorage / Workflow hooks   │
└───────────────────────────────▲─────────────────────────────────┘
                                │ HTTPS Webhook + Command API
┌───────────────────────────────┴─────────────────────────────────┐
│              Hesabix Telephony Connector (on Issabel)            │
│  AMI listener · event mapper · CDR poll · recording index        │
│  command executor (Originate/Hangup/Transfer/Hold)               │
└───────────────────────────────▲─────────────────────────────────┘
                                │ AMI / (ARI later)
┌───────────────────────────────┴─────────────────────────────────┐
│                     Issabel / Asterisk PBX                       │
│  Extensions · Queues · CDR · MixMonitor recordings               │
└─────────────────────────────────────────────────────────────────┘
```

### ۳.۲ اصول معماری

1. **Tenant boundary = `business_id`** همیشه.
2. **Connector هویت کسب‌وکار دارد** (`connector_token` per PBX).
3. **Idempotency:** هر رویداد Asterisk با `uniqueid`/`linkedid` یک‌بار پردازش شود.
4. **Source of truth تماس = `telephony_calls`**؛ CRM Activity مشتق/اختیاری است.
5. **Realtime فقط به کاربران مجاز همان کسب‌وکار و داخلی مرتبط** فرستاده شود.
6. **UI هیچ dialplanی را فرض نکند**؛ فقط وضعیت‌های نرمال‌شده را نشان دهد.

### ۳.۳ الگوی هم‌راستا با افزونه‌های موجود

| الگو | مرجع موجود | استفاده در این افزونه |
|------|------------|------------------------|
| مارکت‌پلیس + لایسنس | `payroll`, `basalam_connector` | `asterisk_issabel_connector` |
| Gate API | `*_plugin_dependency.py` | `telephony_plugin_dependency.py` |
| Gate Flutter | `payroll_plugin_gate.dart` | `telephony_plugin_gate.dart` |
| تنظیمات کسب‌وکار | WooCommerce / Basalam settings | صفحه تنظیمات تلفن |
| اتصال خارجی | Basalam webhook + bridge | Connector webhook |
| فایل | `FileStorageService` + Repair attachments | ضبط مکالمه |
| Realtime | `realtime_manager` | Screen Pop / وضعیت تماس |
| CRM | `CrmActivity`, Lead convert | پیگیری پس از تماس |

---

## ۴. مدل داده (ERD اجرایی)

همه جداول با prefix `telephony_` و `business_id` (جز جایی که صریحاً گفته شود).

### ۴.۱ `telephony_pbx_connections`

اتصال یک مرکز تلفن به یک کسب‌وکار.

| فیلد | نوع | توضیح |
|------|-----|--------|
| id | PK | |
| business_id | FK businesses | |
| name | string | مثلاً «مرکز تهران» |
| pbx_type | enum | `issabel` \| `asterisk` \| `freepbx_compat` |
| host_hint | string nullable | فقط نمایشی/دیباگ — اتصال از سمت Connector است |
| connector_token_hash | string | هش توکن Connector |
| connector_version | string nullable | |
| last_seen_at | datetime nullable | heartbeat |
| status | enum | `pending` \| `online` \| `offline` \| `error` |
| last_error | text nullable | |
| settings | JSON | timezone، context پیش‌فرض Originate، مسیر ضبط، و … |
| is_active | bool | |
| created_at / updated_at | datetime | |

**Constraint:** چند PBX per business مجاز است.

### ۴.۲ `telephony_extensions`

کاتالوگ داخلی‌ها (sync یا دستی).

| فیلد | نوع | توضیح |
|------|-----|--------|
| id | PK | |
| business_id | FK | |
| pbx_id | FK telephony_pbx_connections | |
| extension | string | مثلاً `102` |
| display_name | string nullable | |
| queue_codes | JSON nullable | صف‌های مرتبط |
| is_active | bool | |
| presence_status | enum | `unknown` \| `idle` \| `ringing` \| `busy` \| `unavailable` |
| presence_updated_at | datetime nullable | |

**Unique:** `(pbx_id, extension)`

### ۴.۳ `telephony_user_extensions`

نگاشت کاربر حسابیکس ↔ داخلی در یک کسب‌وکار.

| فیلد | نوع | توضیح |
|------|-----|--------|
| id | PK | |
| business_id | FK | |
| user_id | FK users | |
| pbx_id | FK | |
| extension_id | FK telephony_extensions | |
| is_primary | bool | داخلی پیش‌فرض Click-to-Call |
| receive_screen_pop | bool | |
| can_click_to_call | bool | |
| caller_id_override | string nullable | |

**Unique پیشنهادی:** `(business_id, user_id, extension_id)`  
**قانون:** هر کاربر در هر کسب‌وکار حداقل یک `is_primary` اگر داخلی دارد.

### ۴.۴ `telephony_queues`

| فیلد | نوع |
|------|-----|
| id, business_id, pbx_id | |
| queue_code, name | |
| is_active | |
| live_waiting_count, live_talking_count | cached optional |
| extra_info | JSON |

### ۴.۵ `telephony_calls` (هسته)

| فیلد | نوع | توضیح |
|------|-----|--------|
| id | PK | |
| business_id | FK | |
| pbx_id | FK | |
| asterisk_uniqueid | string | idempotency |
| asterisk_linkedid | string nullable | |
| direction | enum | `inbound` \| `outbound` \| `internal` |
| status | enum | `ringing` \| `answered` \| `missed` \| `busy` \| `failed` \| `completed` \| `cancelled` |
| from_number_raw | string | |
| from_number_normalized | string indexed | |
| to_number_raw | string | |
| to_number_normalized | string indexed | |
| extension | string nullable | داخلی درگیر |
| queue_code | string nullable | |
| transferred_from | string nullable | |
| transferred_to | string nullable | |
| started_at | datetime | |
| answered_at | datetime nullable | |
| ended_at | datetime nullable | |
| duration_sec | int nullable | کل |
| talk_sec | int nullable | از answer تا end |
| hangup_cause | string nullable | |
| recording_status | enum | `none` \| `pending` \| `available` \| `failed` |
| recording_file_storage_id | FK nullable | |
| recording_remote_path | string nullable | مسیر روی PBX |
| recording_url | string nullable | URL امن پروکسی |
| person_id | FK nullable | |
| lead_id | FK nullable | |
| deal_id | FK nullable | |
| document_id | FK nullable | فاکتور/سند |
| crm_activity_id | FK nullable | |
| assigned_user_id | FK nullable | اپراتور |
| category | enum/string nullable | `sales` \| `support` \| `finance` \| `other` \| custom |
| outcome | string nullable | نتیجه انسانی |
| note | text nullable | |
| match_method | enum nullable | `auto` \| `manual` \| `created_person` \| `created_lead` |
| is_anonymous | bool | |
| extra_info | JSON | |
| created_at / updated_at | | |

**Indexes ضروری:**

- `(business_id, started_at DESC)`
- `(business_id, from_number_normalized)`
- `(business_id, to_number_normalized)`
- `(business_id, assigned_user_id, started_at)`
- `UNIQUE(pbx_id, asterisk_uniqueid)`

### ۴.۶ `telephony_call_events`

لاگ ریز رویدادها برای دیباگ و state machine.

| فیلد | نوع |
|------|-----|
| id, call_id, business_id | |
| event_type | `ringing`, `answer`, `hangup`, `transfer`, `hold`, `unhold`, … |
| payload | JSON |
| occurred_at | datetime |

### ۴.۷ `telephony_settings`

یک ردیف per business (مثل payroll_settings).

| فیلد | توضیح |
|------|--------|
| business_id | unique |
| primary_phone_fields | JSON مثلاً `["mobile","mobile_2","mobile_3","phone"]` |
| number_normalization_rules | JSON |
| screen_pop_enabled | bool |
| auto_create_activity | bool |
| post_call_form_required | bool |
| default_category | string nullable |
| missed_call_create_task | bool |
| missed_call_task_due_minutes | int |
| recording_access_mode | `owner_and_managers` \| `permission_based` |
| multi_pbx_enabled | bool |
| ui_preferences | JSON | رفتار Pop، صدا، و … |
| extra_settings | JSON |

### ۴.۸ جداول کمکی

| جدول | نقش |
|------|-----|
| `telephony_connector_heartbeats` | اختیاری؛ یا در connection ذخیره شود |
| `telephony_command_logs` | Originate/Hangup/Transfer برای audit |
| `telephony_number_aliases` | نگاشت دستی شماره‌های خاص به Person |

### ۴.۹ تغییرات حداقلی روی موجودیت‌های فعلی

| موجودیت | تغییر |
|---------|--------|
| `CrmActivity` | افزودن `telephony_call_id` nullable + برگرداندن `extra_info` در API در صورت نیاز |
| `Lead` | اختیاری فاز ۲: فیلد `phone` (ثابت) — در فاز ۱ فقط mobile کافی است |
| Permissions JSON | بخش جدید `telephony` |
| Marketplace seed | افزونه جدید |
| Workflow triggers | `telephony.*` |

**Customer 360:** در فاز ۱ تغییر اجباری ندارد؛ Screen Pop از endpoint ترکیبی telephony استفاده می‌کند که 360 + balance + checks را aggregate می‌کند.

---

## ۵. نرمال‌سازی و تطبیق شماره

### ۵.۱ الگوریتم پیشنهادی `normalize_iran_phone(raw) -> candidates[]`

1. حذف فاصله، `-`، `()`، حروف فارسی ارقام → لاتین.
2. اگر با `+` شروع شد نگه دار؛ در غیر این صورت ارقام را استخراج کن.
3. قواعد:
   - `0098…` → `98…`
   - `+98…` → `98…`
   - `98` + 10 رقم موبایل → همچنین فرم محلی `0` + 10 رقم
   - `0` + 10 رقم موبایل → همچنین `98` + 10 رقم
   - شماره‌های شهری: حفظ کد شهر؛ تولید فرم‌های با/بدون `0`
4. خروجی: لیست کاندیدا برای OR-match + فرم canonical ذخیره‌شده (`from_number_normalized`).

### ۵.۲ ترتیب جستجو

1. `telephony_number_aliases`
2. Person: `mobile`, `mobile_2`, `mobile_3`, `phone` با کاندیداها
3. Lead: `mobile` (+ `phone` اگر اضافه شد)
4. اگر چند match → Pop با انتخاب دستی «کدام پرونده؟»
5. اگر صفر → ناشناس

### ۵.۳ تنظیمات کسب‌وکار

- فیلدهای قابل جستجو قابل انتخاب در تنظیمات
- حداقل طول رقم برای match (پیش‌فرض ۸)

---

## ۶. پروتکل Connector ↔ Hesabix

### ۶.۱ احراز هویت

- هنگام ساخت PBX در UI: توکن یک‌بارمصرف نمایش داده می‌شود؛ فقط hash ذخیره می‌شود.
- Header: `Authorization: Bearer <connector_token>`
- همچنین `X-Hesabix-Business-Id` و `X-Hesabix-Pbx-Id` برای دفاع در عمق

### ۶.۲ Heartbeat

`POST /api/v1/telephony/connector/heartbeat`

```json
{
  "connector_version": "1.2.0",
  "asterisk_version": "18.x",
  "extensions_count": 24,
  "status": "ok"
}
```

هر ۶۰ ثانیه. اگر > ۳ دقیقه نبض نیاید → `offline`.

### ۶.۳ رویداد تماس (Webhook)

`POST /api/v1/telephony/connector/events`

رویدادهای نرمال‌شده (نه raw AMI مستقیم به کلاینت):

```json
{
  "event_id": "uuid",
  "pbx_event_at": "2026-08-03T07:15:01Z",
  "type": "call.ringing",
  "uniqueid": "1722666901.42",
  "linkedid": "1722666901.42",
  "direction": "inbound",
  "from": "09121234567",
  "to": "02191000000",
  "extension": "102",
  "queue": "sales",
  "channel": "SIP/102-0000001a",
  "extra": {}
}
```

انواع الزامی فاز ۱:

- `call.ringing`
- `call.answered`
- `call.ended`
- `call.missed`
- `call.busy`
- `call.failed`
- `extension.presence` (فاز ۲/۳)
- `recording.ready` (فاز ۲)

پردازش باید idempotent بر اساس `(pbx_id, event_id)` یا `(pbx_id, uniqueid, type)`.

### ۶.۴ دستورات از Hesabix به Connector

Connector یا:

- **Pull:** `GET /api/v1/telephony/connector/commands/poll`  
یا
- **Push کانال معکوس:** WebSocket Connector (ترجیحی فاز ۲)

دستور Originate فاز ۱:

```json
{
  "command_id": "uuid",
  "type": "originate",
  "extension": "102",
  "destination": "09121234567",
  "caller_id": "02191000000",
  "timeout_ms": 30000,
  "context": "from-internal"
}
```

پاسخ:

```json
{ "command_id": "uuid", "accepted": true, "asterisk_action_id": "..." }
```

دستورات فاز ۳: `hangup`, `transfer`, `hold`, `resume`.

### ۶.۵ امنیت Connector

- فقط HTTPS outbound از PBX
- توکن قابل rotate از UI
- Rate limit روی endpoints کانکتور
- عدم پذیرش raw AMI از اینترنت به Hesabix

### ۶.۶ پکیج نصب Connector

مسیر پیشنهادی ریپو:

`extraScripts/HesabixTelephonyConnector/`

شامل:

- سرویس systemd
- فایل config (`hesabix-url`, `token`, `ami-host`, `ami-user`, `ami-secret`)
- اسکریپت نصب Issabel (CentOS/Rocky متداول)
- README فارسی نصب
- قابلیت dry-run تست AMI

---

## ۷. API حسابیکس (قرارداد اجرایی)

پایه: `/api/v1/telephony/...`  
همه endpointهای کاربری با:

- `require_business_access`
- `require_telephony_plugin_active`
- `require_business_permission_dep("telephony", …)`

### ۷.۱ تنظیمات و PBX

| Method | Path | Perm | توضیح |
|--------|------|------|--------|
| GET | `/settings` | view | |
| PUT | `/settings` | manage | |
| GET/POST | `/pbx` | view/manage | |
| POST | `/pbx/{id}/rotate-token` | manage | |
| GET | `/pbx/{id}/status` | view | |
| POST | `/pbx/{id}/test` | manage | درخواست تست به Connector |

### ۷.۲ داخلی و نگاشت کاربران

| Method | Path | Perm |
|--------|------|------|
| GET/POST/PATCH | `/extensions` | view/manage |
| POST | `/extensions/sync` | manage |
| GET/PUT | `/user-extensions` | manage |
| GET | `/me/extension-context` | view | داخلی‌های کاربر جاری در business جاری |

### ۷.۳ تماس‌ها

| Method | Path | Perm |
|--------|------|------|
| GET | `/calls` | view | فیلتر و صفحه‌بندی |
| GET | `/calls/{id}` | view | |
| PATCH | `/calls/{id}` | view+write-ish | note/category/outcome/links |
| POST | `/calls/{id}/link-person` | view | |
| POST | `/calls/{id}/create-person` | view | |
| POST | `/calls/{id}/create-lead` | view | |
| POST | `/calls/{id}/create-activity` | view | |
| POST | `/calls/{id}/create-task` | view | |
| GET | `/calls/{id}/recording` | listen_recordings | stream/redirect |
| POST | `/click-to-call` | click_to_call | |
| GET | `/calls/{id}/screen-pop-context` | view | aggregate Pop |

### ۷.۴ زنده و گزارش

| Method | Path | Phase | Perm |
|--------|------|-------|------|
| GET | `/live/snapshot` | ۳ | live_monitor |
| GET | `/reports/summary` | ۲ | reports |
| GET | `/reports/operators` | ۲ | reports |
| GET | `/reports/by-person` | ۲ | reports |

### ۷.۵ Connector (بدون session کاربر — با token)

| Method | Path |
|--------|------|
| POST | `/connector/heartbeat` |
| POST | `/connector/events` |
| GET | `/connector/commands/poll` |
| POST | `/connector/commands/{id}/ack` |
| POST | `/connector/recordings/meta` |

### ۷.۶ WebSocket

گزینه A (فاز ۱): استفاده از `/ws/notifications` با `type: telephony.*`  
گزینه B (فاز ۲): `/ws/telephony` اختصاصی برای ترافیک پرتکرار وضعیت تماس

Payload نمونه Screen Pop:

```json
{
  "type": "telephony.incoming_call",
  "business_id": 12,
  "call_id": 987,
  "extension": "102",
  "from_number": "09121234567",
  "person": {"id": 55, "name": "علی احمدی"},
  "balance": {"amount": 2450000, "status": "debtor"},
  "deep_link": "/business/12/telephony/calls/987"
}
```

---

## ۸. مجوزها

```json
{
  "telephony": {
    "view": true,
    "manage": true,
    "click_to_call": true,
    "listen_recordings": true,
    "live_monitor": true,
    "reports": true,
    "control_calls": true
  }
}
```

| اکشن | معنی |
|------|------|
| view | تاریخچه، Pop، جزئیات تماس |
| manage | PBX، داخلی، تنظیمات، نگاشت کاربران |
| click_to_call | Originate |
| listen_recordings | پخش/دانلود ضبط |
| live_monitor | داشبورد زنده / BLF |
| reports | گزارش‌ها |
| control_calls | Hangup/Transfer/Hold |

مالک کسب‌وکار و superadmin طبق الگوی فعلی bypass دارند.

---

## ۹. یکپارچگی با حسابیکس

### ۹.۱ CRM

- ساخت/به‌روزرسانی `CrmActivity(activity_type=call)` وقتی تنظیم `auto_create_activity` روشن است.
- اتصال `lead_id` / `deal_id` / `person_id`.
- Post-call → ایجاد Task با `due_at`.
- تبدیل ناشناس به Lead با `source_code=telephony` (seed فرایند در صورت نیاز).

### ۹.۲ مالی و مشتری

Screen Pop Context باید aggregate کند:

- خلاصه Person
- `calculate_person_balance` (+ چند ارزی اگر لازم)
- آخرین N فاکتور (`Document`)
- چک‌های سررسید/معوق از مدل `check`
- آخرین فعالیت‌ها / یادداشت‌ها
- معاملات باز

### ۹.۳ Workflow triggers (فاز ۲+)

- `telephony.call.ringing`
- `telephony.call.missed`
- `telephony.call.completed`
- `telephony.call.anonymous`

Actions پیشنهادی: ایجاد وظیفه، ارسال اعلان، ایجاد Lead.

### ۹.۴ اعلان‌ها

از `InAppProvider` / `realtime_manager`:

- تماس ورودی
- از دست‌رفته
- پایان تماس (درخواست ثبت نتیجه)
- قطع اتصال Connector (برای مدیران)

---

## ۱۰. طراحی رابط کاربری (Web / Mobile / Desktop)

### ۱۰.۱ اصول طراحی محصول

این افزونه UI «مرکز تماس مدرن داخل ERP» است، نه یک داشبورد شلوغ.

**اصول سخت:**

1. **یک نوار تلفن همیشگی** در shell کسب‌وکار وقتی افزونه فعال است — هویت بصری ثابت روی هر سه پلتفرم.
2. **Screen Pop غیرمسدودکننده** — کار فعلی کاربر را کامل قطع نکند؛ روی دسکتاپ/وب پنل کناری، روی موبایل bottom sheet هوشمند.
3. **Brand/Feature presence:** کلمه «تماس» یا وضعیت داخلی باید در viewport اول صفحات تلفن واضح باشد؛ اما در بقیه CRM فقط به‌صورت Phone Bar ظریف ظاهر شود.
4. **بدون کارت‌های تزئینی اضافه** در Pop؛ اطلاعات سلسله‌مراتبی و خوانا.
5. **حرکت هدفمند:** ۲–۳ motion اصلی:
   - ظاهر شدن Pop با slide + fade
   - pulse ملایم وضعیت «زنگ می‌خورد»
   - انتقال وضعیت تماس در Phone Bar (idle → ringing → in-call)
6. **تایپوگرافی:** هم‌خوان با سیستم فونت حسابیکس (ایران‌یکان/فونت فعلی اپ) — از Inter/Roboto/Arial استفاده نشود اگر اپ فونت برند دارد.
7. **رنگ:** متغیرهای اختصاصی telephony در تم موجود؛ از تم بنفش پیش‌فرض AI و پس‌زمینه کرم کلیشه‌ای پرهیز شود. پیشنهاد:
   - Idle: سبز ملایم وضعیت
   - Ringing: کهربایی/نارنجی هشدار
   - In-call: آبی عملیاتی حسابیکس (یا primary موجود)
   - Missed: قرمز سیستمی موجود
8. **Dense on desktop, focused on mobile:** دسکتاپ اطلاعات بیشتر؛ موبایل فقط تصمیم‌های فوری.

### ۱۰.۲ توکن‌های UI پیشنهادی

```css
--tel-bar-height-desktop: 48px;
--tel-bar-height-mobile: 44px;
--tel-pop-width-desktop: 420px;
--tel-ring-pulse: 1.2s;
--tel-status-idle: var(--success);
--tel-status-ringing: #D97706;
--tel-status-busy: var(--primary);
--tel-status-offline: var(--muted);
--tel-status-missed: var(--danger);
```

### ۱۰.۳ نقاط ورود UI در اپ

| نقطه | مسیر پیشنهادی |
|------|----------------|
| منوی کسب‌وکار | «مرکز تماس» (فقط اگر لایسنس فعال) |
| زیرمسیرها | `/business/:id/telephony/...` |
| تنظیمات | `/business/:id/settings/telephony` |
| Phone Bar | داخل `BusinessShell` |
| آیکون تماس کنار شماره | Person، Lead، 360، لیست‌ها |

### ۱۰.۴ Phone Bar (همه پلتفرم‌ها)

**محتوا:**

- وضعیت داخلی primary: نقطه رنگی + متن کوتاه (`آزاد` / `زنگ` / `مکالمه` / `آفلاین`)
- شماره داخلی
- دکمه شماره‌گیر
- Badge از دست‌رفته امروز
- دکمه ورود به داشبورد/تاریخچه

**Desktop/Web (≥1100px):** نوار افقی زیر هدر یا بالای محتوا.  
**Tablet:** همان نوار فشرده‌تر.  
**Mobile:** نوار پایین‌تر از AppBar یا چسبیده بالای bottom navigation؛ در حالت مکالمه به **In-Call Mini Bar** تبدیل می‌شود.

### ۱۰.۵ Screen Pop

#### Desktop / Web وسیع

پنل end-side (در RTL: چپ) عرض ~420px روی محتوا، با backdrop خیلی ملایم یا بدون قفل کامل.

ساختار:

1. هدر تماس: جهت + وضعیت + تایمر
2. هویت: نام / شرکت / شماره (بزرگ و خوانا)
3. سیگنال مالی یک خط: مانده + وضعیت بدهی
4. Tabs فشرده: خلاصه | فاکتورها | چک‌ها | سوابق تماس | یادداشت
5. اکشن‌های ثابت پایین: ایجاد Lead / اتصال به شخص / ثبت یادداشت / (در فاز ۳ کنترل تماس)

#### Mobile

- هنگام زنگ: **high-priority bottom sheet** تا 70% ارتفاع، دستگیره drag
- یک CTA اصلی واضح نیست اگر پاسخ روی گوشی سخت‌افزاری است؛ به‌جای آن «باز کردن پرونده» و «ایجاد سرنخ»
- اطلاعات مالی فقط ۱ خط؛ جزئیات در تب

#### Desktop app (Windows)

مثل Web وسیع + پشتیبانی میانبر صفحه‌کلید:

- `Ctrl/Cmd+Shift+D` شماره‌گیر
- `Esc` بستن Pop (اگر در حالت ringing اجباری نباشد)

### ۱۰.۶ شماره‌گیر (Dialer)

- جستجوی شماره هنگام تایپ (Person/Lead)
- لیست اخیر
- پد عددی بزرگ روی موبایل؛ روی دسکتاپ پد + فیلد متنی
- انتخاب داخلی مبدأ اگر کاربر چند داخلی دارد

### ۱۰.۷ پنل مکالمه فعال (In-Call)

- تایمر بزرگ
- نام طرف مقابل
- اکشن‌ها بر اساس فاز: فاز ۱ فقط یادداشت سریع؛ فاز ۳ Hold/Transfer/Hangup
- پس از پایان: **Post-Call Sheet** اجباری/اختیاری طبق تنظیمات:
  - نتیجه
  - دسته‌بندی
  - یادداشت
  - ایجاد وظیفه
  - اتصال به Deal/فاکتور

### ۱۰.۸ صفحات اصلی

#### الف) تاریخچه تماس‌ها

- فیلتر چیپی: ورودی/خروجی/از دست‌رفته/امروز/من
- جدول در دسکتاپ؛ لیست کارت‌مانند تعامل‌محور در موبایل (کارت فقط چون container تعامل لیست است)
- ردیف: جهت، طرف، داخلی، مدت، نتیجه، دکمه پخش ضبط
- جزئیات تماس: timeline رویدادها + پخش‌کننده صوت

#### ب) تنظیمات تلفن

بخش‌ها:

1. وضعیت اتصال PBX + نصب Connector (لینک راهنما + کپی توکن)
2. قوانین شماره
3. نگاشت کاربران به داخلی (جدول دسکتاپ / لیست موبایل)
4. رفتار Pop و Post-call
5. دسترسی ضبط

#### ج) داشبورد لحظه‌ای (فاز ۳)

ترکیب یک ترکیب واحد، نه دیوار کارت:

- نوار بالا: فعال / انتظار / از دست‌رفته امروز / میانگین پاسخ
- ناحیه اصلی: ماتریس وضعیت داخلی‌ها (BLF)
- نوار کناری: صف‌ها

روی موبایل: فقط KPIهای ضروری + لیست داخلی‌های تیم کاربر.

#### د) گزارش‌ها (فاز ۲)

چارت‌های ساده + جدول؛ فیلتر بازه، داخلی، اپراتور، مشتری.

### ۱۰.۹ Click-to-Call در سطح سیستم

کامپوننت مشترک:

`TelephonyPhoneLink(number, personId?, leadId?)`

نمایش:

- متن شماره قابل کپی
- آیکون تماس (فقط اگر `click_to_call` + افزونه فعال + داخلی mapped)

روی موبایل: تأیید کوتاه قبل از Originate (جلوگیری از لمس تصادفی).

### ۱۰.۱۰ حالت‌های خالی و خطا (الزامی UI)

| حالت | پیام/رفتار |
|------|-------------|
| افزونه غیرفعال | `TelephonyPluginGate` → مارکت‌پلیس |
| Connector offline | Banner نارنجی در تنظیمات و Phone Bar |
| کاربر بدون داخلی | Phone Bar: «داخلی تعریف نشده» + لینک به مدیر |
| شماره نامعتبر | Dialer خطا با راهنمای فرمت |
| چند match | Pop انتخاب پرونده |
| بدون مجوز ضبط | پلیر مخفی؛ متن جایگزین |

### ۱۰.۱۱ دسترس‌پذیری و i18n

- FA پیش‌فرض؛ EN برای کلیدها از الگوی i18n موجود
- کنتراست وضعیت‌ها فقط متکی به رنگ نباشد (آیکون + متن)
- تایمر و اعداد با ارقام سازگار با locale اپ
- پخش صوت با کنترل صفحه کلید در وب/دسکتاپ

### ۱۰.۱۲ پرفورمنس UI

- Pop data از endpoint aggregate؛ نه ۱۰ درخواست جدا در UI
- debounce جستجوی Dialer 250–300ms
- WS events فقط برای business فعال در `AuthStore`
- با تعویض business: unsubscribe ذهنی + clear state تلفن

---

## ۱۱. ساختار کد پیشنهادی

### ۱۱.۱ Backend

```
hesabixAPI/
  adapters/db/models/telephony.py
  adapters/db/repositories/telephony_*.py
  adapters/api/v1/telephony/
    __init__.py
    settings.py
    pbx.py
    extensions.py
    calls.py
    click_to_call.py
    reports.py
    live.py
    connector.py
  app/core/telephony_plugin_dependency.py
  app/services/telephony/
    phone_normalizer.py
    call_state_machine.py
    caller_id_matcher.py
    screen_pop_service.py
    originate_service.py
    recording_service.py
    connector_command_service.py
    reports_service.py
    realtime_publisher.py
  migrations/versions/YYYYMMDD_telephony_*.py
  scripts/add_telephony_plugin.py
  adapters/db/seed_data/marketplace_plugins_seed.py  # اضافه کردن افزونه
```

### ۱۱.۲ Frontend

```
hesabixUI/hesabix_ui/lib/
  pages/business/telephony/
    telephony_shell_bar.dart
    telephony_dialer_sheet.dart
    telephony_screen_pop.dart
    telephony_in_call_panel.dart
    telephony_post_call_sheet.dart
    telephony_calls_page.dart
    telephony_call_detail_page.dart
    telephony_settings_page.dart
    telephony_live_dashboard_page.dart
    telephony_reports_page.dart
  widgets/telephony/
    telephony_plugin_gate.dart
    telephony_status_dot.dart
    telephony_phone_link.dart
    telephony_recording_player.dart
  services/telephony/
    telephony_api.dart
    telephony_realtime_controller.dart
    telephony_session_controller.dart
```

### ۱۱.۳ Connector

```
extraScripts/HesabixTelephonyConnector/
  README.md
  install.sh
  config.example.env
  app/
    main.py
    ami_client.py
    event_mapper.py
    hesabix_client.py
    commands.py
    recordings.py
  systemd/hesabix-telephony-connector.service
```

---

## ۱۲. فازهای اجرایی

هر فاز خروجی قابل دمو و چک‌لیست پذیرش دارد. تا پذیرش فاز n، فاز n+1 شروع نشود مگر کارهای زیرساختی موازی بی‌خطر.

---

### فاز ۰ — آماده‌سازی و قراردادها (۳–۵ روز)

**هدف:** قفل طراحی، seed افزونه، اسکلت خالی بدون رفتار تلفنی واقعی.

**کارها:**

1. ثبت افزونه در `marketplace_plugins_seed` با کد `asterisk_issabel_connector`
2. اسکریپت `add_telephony_plugin.py`
3. سند API OpenAPI draft داخل همین ریپو یا swagger stubs
4. تعریف permissionها در UI مجوزها
5. ایجاد branch/workflow تیمی و برش تیکت‌ها از همین سند

**پذیرش:**

- افزونه در مارکت‌پلیس دیده می‌شود (حتی اگر صفحات «به‌زودی» باشند)
- کد افزونه و قیمت‌گذاری seed شده

---

### فاز ۱ — MVP عملیاتی CTI (۶–۸ هفته)

**هدف:** اتصال واقعی Issabel، Screen Pop، Click-to-Call، تاریخچه پایه.

#### ۱.A Backend

- مدل‌ها و migrationهای بخش ۴ (حداقل: settings, pbx, extensions, user_extensions, calls, call_events)
- plugin dependency gate
- phone normalizer + matcher
- connector heartbeat/events/commands poll
- call state machine
- click-to-call originate command
- screen-pop-context aggregate (person/lead + balance پایه)
- WS notification `telephony.incoming_call` / `telephony.call_ended` / `telephony.call_missed`
- CRUD تاریخچه و patch نتیجه/یادداشت
- ایجاد Person/Lead از تماس

#### ۱.B Connector

- AMI login
- map رویدادهای Dial/Hangup به webhook
- originate
- heartbeat
- نصب‌نامه Issabel
- صف محلی retry اگر Hesabix در دسترس نبود

#### ۱.C Flutter UI

- Plugin gate + منو + routes
- Phone Bar در BusinessShell
- Screen Pop (desktop side panel + mobile sheet)
- Dialer
- صفحه تاریخچه و جزئیات تماس
- تنظیمات: PBX token، نگاشت کاربر↔داخلی، تست اتصال
- `TelephonyPhoneLink` در Person و Lead
- Post-call sheet ساده

#### ۱.D کیفیت

- تست واحد normalizer (ماتریس شماره‌های ایرانی)
- تست idempotency رویدادها
- تست مجوزها و لایسنس
- سناریو دستی روی Issabel staging

**پذیرش فاز ۱:**

- [ ] Connector online در UI
- [ ] تماس ورودی شناخته‌شده → Pop صحیح برای همان کاربر/داخلی/کسب‌وکار
- [ ] ناشناس → ایجاد Lead/Person
- [ ] Click-to-Call از پروفایل کار می‌کند
- [ ] تاریخچه ورودی/خروجی با مدت و وضعیت
- [ ] تعویض کسب‌وکار context داخلی را عوض می‌کند
- [ ] UI روی Chrome وب، Android، و Windows desktop قابل استفاده است (layout نشکند)

**صریحاً خارج از فاز ۱:** Hold/Transfer، داشبورد زنده، گزارش پیشرفته، Softphone، آپلود انبوه ضبط.

---

### فاز ۲ — عمق CRM + ضبط + گزارش (۴–۶ هفته)

**هدف:** تماس بخشی از فروش و پشتیبانی روزمره شود.

**کارها:**

- recording.ready از Connector + پروکسی پخش/دانلود با permission
- آپلود اختیاری به `file_storage` (`module_context=telephony_recording`)
- اتصال تماس به Deal و Document
- auto activity + task برای missed
- بهبود Screen Pop: فاکتورها، چک‌ها، آخرین خریدها، یادداشت‌ها
- گزارش‌های summary / operators / by-person / by-time
- Workflow triggers اولیه
- بهبود UI گزارش و پلیر صوت زیبا (waveform ساده یا progress دقیق)
- number aliases
- sync بهتر داخلی‌ها از Connector

**پذیرش فاز ۲:**

- [ ] پخش ضبط برای کاربر مجاز؛ رد برای غیرمجاز
- [ ] Pop مانده حساب و چک معوق را نشان می‌دهد
- [ ] گزارش هفتگی اپراتور قابل استخراج است
- [ ] missed call می‌تواند وظیفه بسازد

---

### فاز ۳ — مرکز تماس زنده و کنترل تماس (۶–۸ هفته)

**هدف:** سرپرست و اپراتور دید زنده و کنترل داشته باشند.

**کارها:**

- live snapshot: تماس‌های فعال، صف، حضور داخلی (BLF)
- UI Live Dashboard تطبیقی
- دستورات Hangup / Transfer / Hold / Resume (AMI یا ARI)
- چند PBX / چند شعبه در UX
- اعلان تماس برگشتی
- مشاهده تماس‌های در حال انجام تیم
- `control_calls` permission enforcement
- بهینه‌سازی WS اختصاصی در صورت نیاز

**پذیرش فاز ۳:**

- [ ] داشبورد زنده تأخیر محسوس < ۳ ثانیه در شبکه عادی دارد
- [ ] Transfer از UI روی Issabel واقعی کار می‌کند
- [ ] BLF وضعیت آزاد/مشغول/آفلاین را نشان می‌دهد

---

### فاز ۴ — سخت‌سازی تولید و عملیات (۳–۴ هفته)

**هدف:** آماده فروش گسترده.

**کارها:**

- مشاهده‌پذیری: متریک‌ها، لاگ ساخت‌یافته، DLQ رویدادهای شکست‌خورده
- rotate token، audit log دستورات
- محدودیت نرخ، محافظت replay
- راهنمای نصب ویدیویی/متنی فارسی کامل
- تست بار رویداد همزمان
- بهبود UX حالت‌های خطا و بازیابی Connector
- FA/EN کامل رشته‌ها
- چک‌لیست امنیتی

**پذیرش فاز ۴:**

- [ ] مستندات نصب توسط یک تکنسین Issabel بدون کمک تیم توسعه انجام‌پذیر است
- [ ] قطع و وصل شبکه باعث فساد داده تماس نمی‌شود
- [ ] سوپرادمین متریک سلامت کانکتورها را می‌بیند (حداقلی)

---

### فاز ۵ — پیشرفته اختیاری (۸+ هفته یا بک‌لاگ)

فقط با تأیید محصول:

- Softphone WebRTC داخل Flutter Web/Desktop
- تحلیل تماس ناشناس
- صف انتظار پیشرفته و wallboard تمام‌صفحه
- اتصال به کانال‌های دیگر (در صورت نیاز)
- ماژول تیکت کسب‌وکار جدا + اتصال به تماس
- ضبط با سطح دسترسی بسیار دانه‌ریز per call

---

## ۱۳. برنامه اسپرینت پیشنهادی فاز ۱

| اسپرینت | مدت | خروجی |
|---------|-----|--------|
| S1 | ۲ هفته | مدل داده، seed، settings/pbx API، اسکلت Flutter settings + gate |
| S2 | ۲ هفته | Connector AMI + events + call state + تاریخچه |
| S3 | ۲ هفته | Screen Pop + WS + matcher + Pop UI همه پلتفرم‌ها |
| S4 | ۲ هفته | Click-to-Call + Dialer + Phone Bar + PhoneLink + پایدارسازی و QA |

---

## ۱۴. معیارهای کیفیت و تست

### ۱۴.۱ ماتریس تست شماره

حداقل ۳۰ نمونه شامل:

- `09121234567`, `9121234567`, `989121234567`, `+989121234567`, `00989121234567`
- شهری `02191001234` با/بدون صفر
- شماره کوتاه داخلی
- شماره با خط تیره و فاصله فارسی

### ۱۴.۲ تست چندمستأجری

- رویداد business A هرگز به کاربر business B نرسد
- حتی اگر همان user در هر دو عضو است، Pop فقط برای mapping همان business برود

### ۱۴.۳ تست پلتفرم UI

| پلتفرم | حداقل بررسی |
|--------|-------------|
| Web Chrome/Firefox | Pop، Dialer، WS، پخش صوت |
| Android | bottom sheet، Originate، نوار وضعیت |
| iOS | همان + محدودیت background (مستند شود) |
| Windows desktop | میانبرها، پنل کناری، فونت/RTL |

### ۱۴.۴ تست کارایی

- ۱۰ رویداد/ثانیه per PBX بدون drop (فاز ۱ هدف اولیه)
- Pop context p95 < ۵۰۰ms روی داده متوسط

---

## ۱۵. امنیت و حریم خصوصی

1. توکن Connector فقط hash در DB
2. ضبط مکالمه فقط با permission
3. URL ضبط زمان‌دار یا stream احراز‌هویت‌شده — لینک عمومی خام ممنوع
4. AMI credential فقط روی سرور مشتری (Connector)، نه در کلود حسابیکس
5. Audit برای listen recording و control commands
6. حداقل داده در WS (بدون ارسال کامل تاریخچه مالی در خود event اگر سنگین است؛ client می‌تواند context را fetch کند — یا نسخه خلاصه)

**تصمیم فاز ۱ برای Pop:** event WS خلاصه بفرستد؛ UI بلافاصله `screen-pop-context` را GET کند (سریع‌تر برای امنیت و تازگی داده).

---

## ۱۶. قیمت‌گذاری و مارکت‌پلیس (پیشنهاد اولیه)

| دوره | قیمت پیشنهادی seed | قابل تغییر توسط ادمین |
|------|---------------------|------------------------|
| ماهانه | ۳۵۰٬۰۰۰ ریال? → **به تومان رایج مارکت:** هم‌تراز integrationها مثلاً ۲۵۰٬۰۰۰–۵۰۰٬۰۰۰ تومان | بله |
| سالانه | ۱۰× ماهانه با تخفیف | بله |
| Trial | ۱۴ روز | بله |

دسته: `integration`  
توضیح مارکت‌پلیس باید صریحاً بگوید: «نیاز به نصب Connector روی Issabel/Asterisk دارد».

> مبلغ نهایی را مالک محصول قبل از انتشار عمومی در seed قطعی کند.

---

## ۱۷. ریسک‌ها و کاهش ریسک

| ریسک | اثر | کاهش |
|------|-----|------|
| تنوع dialplan ایزابل | Originate کار نکند | تنظیم context در settings + راهنمای تشخیص |
| NAT/قطع اینترنت شعبه | از دست رفتن رویداد | صف retry محلی Connector |
| Caller ID نامعتبر مخابرات | Pop اشتباه | aliases + UI اصلاح دستی |
| انتظار Softphone در MVP | نارضایتی | شفاف‌سازی فروش: Click-to-Call نیاز به گوشی SIP دارد |
| حجم ضبط‌ها | هزینه storage | پیش‌فرض لینک PBX؛ آپلود اختیاری |
| پیچیدگی UI مرکز تماس | شلوغی | فازبندی و Phone Bar مینیمال |

---

## ۱۸. تصمیم‌های باز (باید قبل/حین فاز ۱ بسته شوند)

| # | موضوع | گزینه‌ها | پیشنهاد سند |
|---|--------|----------|-------------|
| 1 | مبلغ نهایی افزونه | — | توسط محصول |
| 2 | کانال معکوس دستورات | Poll vs WS Connector | فاز ۱ Poll؛ فاز ۲ WS |
| 3 | آیا Post-call اجباری باشد؟ | بله/خیر/تنظیمی | تنظیمی؛ پیش‌فرض خیر |
| 4 | ذخیره ضبط در کلود | همیشه/اختیاری/هرگز | اختیاری |
| 5 | افزودن `phone` به Lead | بله/خیر | فاز ۲ در صورت نیاز واقعی |
| 6 | نام منو | مرکز تماس / تلفن / آستریکس | «مرکز تماس» |

---

## ۱۹. چک‌لیست شروع پیاده‌سازی (روز ۱)

1. تأیید این سند توسط محصول/فنی
2. بستن جدول تصمیم‌های باز بخش ۱۸ (حداقلی: ۱، ۳، ۴، ۶)
3. ایجاد تیکت‌های فاز ۰ و اسپرینت ۱ از بخش ۱۳
4. آماده‌سازی یک Issabel staging با AMI user تست
5. شروع seed + migration اسکلت طبق فاز ۰/۱.A

---

## ۲۰. پیوست A — نگاشت لیست نیازمندی کاربر به فاز

| نیازمندی | فاز |
|----------|-----|
| Screen Pop | ۱ |
| جستجوی خودکار مخاطب/مشتری | ۱ |
| سوابق/فاکتور/یادداشت در Pop | ۱ خلاصه؛ ۲ کامل |
| وضعیت بدهی/اعتبار | ۱ (balance)؛ ۲ غنی‌تر |
| ایجاد مخاطب/Lead ناشناس | ۱ |
| Click-to-Call | ۱ |
| ثبت خودکار ورودی/خروجی | ۱ |
| مدت/شروع/پایان/نتیجه/داخلی | ۱ |
| یادداشت و دسته‌بندی پس از تماس | ۱ |
| ضبط لینک/پخش/دانلود/دسترسی | ۲ |
| نگاشت کاربر↔داخلی + چند داخلی | ۱ |
| وضعیت داخلی | ۳ (در ۱ فقط هنگام رویداد تماس) |
| از دست‌رفته / تعداد امروز | ۱ پایه؛ ۳ زنده |
| Activity/یادآوری/وظیفه | ۲ |
| اتصال به Deal/فاکتور | ۲ |
| گزارش‌ها | ۲ |
| چند PBX / صف‌ها / گروه‌ها | ۳ (تعریف صف ۲/۳) |
| اعلان‌ها | ۱ |
| صف انتظار / BLF / تماس فعال | ۳ |
| قطع/انتقال/Hold | ۳ |
| شماره‌گیری سریع / جستجو حین تایپ | ۱ |
| چند شعبه | ۳ |
| یکپارچگی تیکت/تقویم/اسناد/چک/مکاتبات | ۲ (تیکت کسب‌وکار خارج مگر تعریف شود) |
| داشبورد لحظه‌ای | ۳ |
| Softphone داخل اپ | ۵ |

---

## ۲۱. پیوست B — نمونه جریان State Machine تماس

```
                ┌──────────┐
                │  (new)   │
                └────┬─────┘
                     │ call.ringing
                     ▼
                ┌──────────┐
         ┌──────│ ringing  │──────┐
         │      └────┬─────┘      │
 call.missed/failed  │ answered    │ busy
         │           ▼             │
         │      ┌──────────┐       │
         │      │ answered │       │
         │      └────┬─────┘       │
         │           │ ended       │
         ▼           ▼             ▼
      missed      completed       busy
```

هر انتقال باید `telephony_call_events` بنویسد و در صورت نیاز WS بفرستد.

---

## ۲۲. پیوست C — معیار «UI عالی» برای پذیرش بصری

قبل از انتشار هر فاز دارای UI، این موارد باید پاس شوند:

1. Phone Bar در وب/دسکتاپ/موبایل هم‌معنا و بدون شکستگی RTL
2. Pop در ۳ اندازه صفحه (≤400، 768، ≥1280) بازبینی شده
3. حالت ringing بدون چشمک‌زن آزاردهنده؛ فقط pulse ملایم
4. پخش صوت کنترل واضح دارد (play/pause/seek/speed اختیاری)
5. تنظیمات Connector برای کاربر غیرفنی قابل فهم است (۳ گام: نصب → توکن → تأیید آنلاین)
6. هیچ صفحه تلفن فقط «جدول خام بدون سلسله‌مراتب» نباشد
7. زمان تعامل اپراتور برای ثبت نتیجه پس از تماس < ۲۰ ثانیه

---

**پایان سند اجرایی v1.0.0**

مرحله بعد پس از تأیید این سند: اجرای فاز ۰ و برش تیکت‌های اسپرینت ۱ دقیقاً مطابق بخش‌های ۱۲ و ۱۳.
