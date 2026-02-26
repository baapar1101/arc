# سناریو جامع: افزودن پیام‌رسان بله به کانال‌های اطلاع‌رسانی

این سند یک سناریوی کامل و گام‌به‌گام برای افزودن **پیام‌رسان بله** به عنوان یک کانال نوتیفیکیشن در سیستم Hesabix است؛ از بخش مدیریت و تنظیمات تا استفاده در نوتیفیکیشن‌ها و کوچک‌ترین نقاط تماس.

---

## ۱. نمای کلی معماری فعلی کانال‌ها

در حال حاضر کانال‌های اطلاع‌رسانی به این شکل کار می‌کنند:

| کانال   | Provider (Backend)     | تنظیمات سیستم (Admin)     | شناسه کاربر (User)      | تنظیمات کاربر (فعال/غیرفعال) |
|--------|------------------------|----------------------------|--------------------------|--------------------------------|
| telegram | `TelegramProvider`     | `telegram_bot_token`, webhook, proxy | `users.telegram_chat_id` | `user_notification_settings.channel='telegram'` |
| email  | `EmailProvider`        | (SMTP/سیستم)              | `users.email`            | همان‌طور |
| sms    | `SmsProvider`          | `sms_*` در system_settings | `users.mobile`           | همان‌طور |
| inapp  | `InAppProvider`        | —                          | —                        | همان‌طور |

برای **بله** باید همان الگو را تکرار کنیم: Provider، تنظیمات سیستم، فیلد شناسه در User، و تنظیمات per-user.

---

## ۲. سناریو به تفکیک لایه‌ها

### ۲.۱ لایه دیتابیس و مدل‌ها

#### ۲.۱.۱ مدل User
- **فایل:** `hesabixAPI/adapters/db/models/user.py`
- **تغییرات:**
  - افزودن فیلد `bale_chat_id: Mapped[int | None]` (مشابه `telegram_chat_id`، نوع `BigInteger` در صورت نیاز API بله).
  - افزودن فیلد `bale_connected_at: Mapped[datetime | None]` (اختیاری، برای نمایش زمان اتصال).
- **مایگریشن:** یک مایگریشن Alembic برای اضافه کردن این دو ستون به جدول `users`.

#### ۲.۱.۲ توکن اتصال بله (مشابه تلگرام)
- **جدول جدید (پیشنهاد):** `bale_link_tokens` با ساختار مشابه `telegram_link_tokens`:
  - `id`, `user_id`, `token`, `expires_at`, `used_at`, `created_ip`, `user_agent`, `created_at`
- **فایل مدل:** مثلاً `hesabixAPI/adapters/db/models/bale.py` (یا اضافه کردن به یک فایل integrations).
- **Repository:** `BaleRepository` با متدهای `create_link_token`, `get_by_token`, `mark_used` (مشابه `TelegramRepository`).

#### ۲.۱.۳ جداول نوتیفیکیشن (بدون تغییر اساسی)
- **`notification_outbox.channel`:** مقدار `"bale"` به مقادیر مجاز اضافه شود (در عمل با ذخیره `channel='bale'` در همان ستون String(32) کار می‌کند).
- **`notification_delivery_attempts.channel`:** همان.
- **`user_notification_settings.channel`:** مقدار `"bale"` به مقادیر مجاز اضافه شود.
- **`notification_templates` (سیستم):** در جایی که قالب‌ها بر اساس `channel` فیلتر می‌شوند، مقدار `"bale"` باید شناخته شود.
- **قالب‌های نوتیفیکیشن کسب‌وکار (business):** در سرویس و API مربوط به قالب‌های sms/email، در صورت نیاز آینده به «ارسال از کسب‌وکار به بله» می‌توان کانال `bale` را اضافه کرد (در این سناریو اولیه می‌توان فقط نوتیفیکیشن سیستمی را در نظر گرفت).

---

### ۲.۲ تنظیمات سیستم (Admin)

#### ۲.۲.۱ Environment و Settings
- **فایل:** `hesabixAPI/app/core/settings.py`
- **تغییرات:** افزودن متغیرهای محیطی (اختیاری، برای override از env):
  - `bale_bot_token: str | None = None`
  - `bale_bot_username: str | None = None` (برای ساخت deep link)
  - `bale_webhook_secret: str | None = None`
  - در صورت استفاده از پروکسی برای بله: `bale_proxy_enabled`, `bale_proxy_base_url`, `bale_proxy_api_key`

#### ۲.۲.۲ System Settings Service
- **فایل:** `hesabixAPI/app/services/system_settings_service.py`
- **ثابت‌ها:** تعریف کلیدهایی مثل `NOTIFY_BALE_BOT_TOKEN`, `NOTIFY_BALE_BOT_USERNAME`, `NOTIFY_BALE_WEBHOOK_SECRET`, و در صورت نیاز پروکسی بله.
- **تابع `get_notifications_settings(db)`:** خواندن مقادیر این کلیدها از جدول `system_settings` و برگرداندن در دیکشنری (مثلاً `bale_bot_token`, `bale_bot_username`, ...).
- **تابع `get_effective_notifications_settings(db)`:** ادغام مقادیر DB با env (مشابه تلگرام) و برگرداندن کلیدهای بله در خروجی.
- **تابع `set_notifications_settings(...)`:** پذیرش پارامترهای اختیاری `bale_bot_token`, `bale_bot_username`, `bale_webhook_secret` و ذخیره در DB.

#### ۲.۲.۳ API ادمین
- **فایل:** `hesabixAPI/adapters/api/v1/admin/system_settings.py`
- **Payload:** در `NotificationsConfigPayload` فیلدهای `bale_bot_token`, `bale_bot_username`, `bale_webhook_secret` (و در صورت نیاز پروکسی بله) اضافه شود.
- **Endpoint PUT `/notifications`:** در فراخوانی `set_notifications_settings` این پارامترها پاس داده شوند.
- **Endpoint GET `/notifications`:** خروجی `get_notifications_settings` از قبل شامل مقادیر بله می‌شود اگر در سرویس اضافه شده باشد.
- **وب‌هوک بله (اختیاری):** در صورت وجود API ثبت webhook در بله، یک endpoint مثل `POST /notifications/bale/webhook` برای ثبت آدرس وب‌هوک با استفاده از `bale_bot_token` و `bale_webhook_secret` اضافه شود.

---

### ۲.۳ Provider ارسال پیام (Backend)

#### ۲.۳.۱ BaleProvider
- **فایل جدید:** `hesabixAPI/app/services/providers/bale_provider.py`
- **الگو:** مشابه `TelegramProvider` با توجه به [API بله](https://tapi.bale.ai):
  - متد `__init__(self, *, bot_token=None, proxy_config=None)`.
  - متد `is_configured() -> bool`.
  - متد `send_text(chat_id: int, text: str, parse_mode: Optional[str] = None) -> bool` که درخواست را به `https://tapi.bale.ai/bot<token>/sendMessage` (یا معادل رسمی بله) بفرستد.
  - در صورت استفاده از پروکسی (مثل تلگرام)، متد کمکی برای ارسال از طریق پروکسی.
- **نکته:** مستندات رسمی API بله (مثلاً sendMessage، فرمت chat_id و پاسخ) باید ملاک نهایی باشد.

#### ۲.۳.۲ NotificationService
- **فایل:** `hesabixAPI/app/services/notification_service.py`
- **در `__init__`:** خواندن `notify_cfg = get_effective_notifications_settings(db)` و ساخت `self.bale = BaleProvider(bot_token=notify_cfg.get("bale_bot_token"), proxy_config=notify_cfg.get("bale_proxy"))`.
- **در متد `send`:**
  - در لیست پیش‌فرض کانال‌ها، اضافه کردن `"bale"` در جای مناسب (مثلاً بعد از telegram: `["telegram", "bale", "sms", "email", "inapp"]`).
  - بلوک `elif channel == "bale":` با منطق مشابه تلگرام:
    - بررسی `self.bale.is_configured()`.
    - خواندن `bale_chat_id` از user؛ در صورت نبود، outbox را failed با خطای `no_bale_chat_id` و ادامه به کانال بعد.
    - رندر قالب با `render_for("bale")` و بررسی خالی نبودن body.
    - فراخوانی `self.bale.send_text(chat_id=..., text=body_bale)` و ثبت نتیجه در outbox و `_log_attempt`.
- **در `notify_support_operators`:** در `preferred_channels` می‌توان `"bale"` را اضافه کرد (مثلاً `["inapp", "email", "telegram", "bale", "sms"]`) تا در صورت اتصال اپراتور به بله، از آن کانال هم استفاده شود.

---

### ۲.۴ قالب‌های نوتیفیکیشن (سیستم)

- **Repository قالب‌ها:** `NotificationTemplateRepository` با متد `get(event_key=..., channel=..., locale=...)`. با ذخیره قالب‌هایی که `channel='bale'` باشند، بدون تغییر در repository کار می‌کند.
- **ادمین قالب‌ها:** در `hesabixAPI/adapters/api/v1/admin/notification_templates.py` (یا هر جایی که لیست/فیلتر کانال دارد)، مقدار `"bale"` به انتخاب‌های کانال اضافه شود تا بتوان برای رویدادهایی مثل `auth.otp_login`, `support.operator_reply` و غیره قالب مخصوص بله تعریف کرد.
- **Seed/داده اولیه:** در صورت وجود اسکریپت seed برای قالب‌های پیش‌فرض، یک قالب برای `channel='bale'` برای رویدادهای مهم (مثلاً `auth.otp_login`, `system.test`) اضافه شود.

---

### ۲.۵ API تنظیمات نوتیفیکیشن کاربر و تست

#### ۲.۵.۱ تنظیمات کاربر (فعال/غیرفعال کردن کانال)
- **فایل:** `hesabixAPI/adapters/api/v1/notifications.py`
- **`SettingsPayload`:** فیلد `bale_enabled: Optional[bool] = None` اضافه شود.
- **GET `/notifications/settings`:** در دیکشنری پاسخ، مقدار `bale_enabled` با منطق مشابه تلگرام (خواندن از `user_notification_settings` برای `channel='bale'`، پیش‌فرض True) اضافه شود.
- **PUT `/notifications/settings`:** در صورت ارسال `payload.bale_enabled`، فراخوانی `repo.upsert(user_id=..., channel="bale", event_key=None, enabled=payload.bale_enabled)`.

#### ۲.۵.۲ ارسال تست
- **Endpoint POST `/notifications/test`:** پارامتر `channel` از Query با الگوی مجاز به‌روز شود تا `bale` را هم بپذیرد؛ مثلاً `pattern="^(telegram|email|sms|inapp|bale)$"`.

---

### ۲.۶ اتصال/قطع اتصال کاربر به بله (Integrations)

#### ۲.۶.۱ API اتصال بله
- **مسیر پیشنهادی:** `hesabixAPI/adapters/api/v1/integrations/bale.py` (یا زیرمجموعه یک router یکپارچه integrations).
- **Endpoints (مشابه تلگرام):**
  - **POST `/integrations/bale/link`:**  
    - بررسی پیکربندی: `get_effective_notifications_settings(db)` و وجود `bale_bot_token`.  
    - ایجاد توکن اتصال با `BaleRepository.create_link_token` (TTL مثلاً ۶۰۰ ثانیه).  
    - ساخت deep link به ربات بله با `bale_bot_username` و token (فرمت deep link بله را از مستندات بگیرید).  
    - برگرداندن `deep_link`, `link_token`, `expires_at`.
  - **GET `/integrations/bale/status`:**  
    - برگرداندن `linked: bool` و در صورت اتصال، `chat_id` و در صورت وجود `bale_connected_at`.
  - **DELETE `/integrations/bale/unlink`:**  
    - صفر کردن `user.bale_chat_id` و `user.bale_connected_at` و commit.
  - **POST `/integrations/bale/webhook/{secret}` (وب‌هوک بله):**  
    - اعتبارسنجی secret و در صورت تمایل header امنیتی.  
    - پردازش payload بله: تشخیص دستور `/start <token>` برای لینک کردن کاربر (خواندن token، پیدا کردن `BaleLinkToken`، ست کردن `user.bale_chat_id` و `user.bale_connected_at`، mark_used کردن توکن، ارسال پیام تأیید در بله).  
    - در صورت وجود دستور `/unlink` در بله، قطع اتصال مشابه تلگرام.  
    - برگرداندن پاسخ مناسب برای API بله.

#### ۲.۶.۲ ثبت router
- در `hesabixAPI/app/main.py` (یا جایی که روترهای v1 شامل می‌شوند)، روتر `integrations/bale` به API اضافه شود.

---

### ۲.۷ ورود با OTP و کانال‌های موجود

- **فایل:** `hesabixAPI/app/services/otp_login_service.py`
- **`get_available_channels`:**  
  - اگر ربات بله پیکربندی شده باشد و کاربر پیدا شده و `user.bale_chat_id` داشته باشد، کانال `"bale"` به `available_channels` اضافه شود (مشابه تلگرام).
- **`send_login_otp`:**  
  - در شاخه `channel == "bale"`: بررسی پیکربندی بله و وجود `user.bale_chat_id`، سپس ارسال OTP با استفاده از `BaleProvider.send_text` (یا از طریق NotificationService با `preferred_channels=["bale"]` تا از قالب و outbox یکسان استفاده شود).
- **فایل:** `hesabixAPI/adapters/api/v1/auth.py`
- در پاسخ endpoint ارسال OTP، در `available_channels` و `channel_names` مقدار `"bale"` و نام نمایشی «بله» اضافه شود.
- **مدل/Repo OTP:** در `otp_login_session.channel` و هر جای دیگری که مقدار کانال ذخیره می‌شود، مقدار `"bale"` مجاز باشد.

---

### ۲.۸ نقاط دیگر Backend که به کانال اشاره می‌کنند

- **`notification_processor.py`:** در صورت retry بر اساس `outbox.channel`، با اضافه شدن رکوردهای `channel='bale'` به‌صورت خودکار پردازش می‌شوند اگر در `NotificationService.send` شاخه `bale` اضافه شده باشد.
- **Workflow / Communication actions:** در `communication_actions.py` و هر جایی که `preferred_channels` به صورت لیست ثابت استفاده می‌شود (مثلاً برای اپراتورها یا صاحبان کسب‌وکار)، در صورت تمایل می‌توان `"bale"` را به لیست اضافه کرد.
- **Support (تیکت، اپراتور):** در `adapters/api/v1/support/operator.py` و مشابه، در لیست `preferred_channels` می‌توان `"bale"` را اضافه کرد.
- **Business notifications:** در `business_notification_service.py` فعلاً کانال‌ها `sms` و `email` هستند؛ افزودن بله به نوتیفیکیشن کسب‌وکار (مثلاً برای مشتری) سناریوی جداگانه است و می‌توان در فاز بعد در نظر گرفت (شامل قالب‌های کسب‌وکار برای کانال بله و احتمالاً شناسه بله در پروفایل مشتری/شخص).

---

### ۲.۹ UI – مدیریت (ادمین)

#### ۲.۹.۱ تنظیمات نوتیفیکیشن سیستم
- **فایل:** `hesabixUI/hesabix_ui/lib/pages/profile/notifications_settings_page.dart` (همان صفحه‌ای که برای ادمین بخش تلگرام و SMS وجود دارد).
- **تغییرات:**
  - در حالت ادمین، یک کارت/بخش «بله» اضافه شود (مشابه کارت تلگرام).
  - فیلدهای: توکن ربات بله، نام کاربری ربات (برای لینک)، رمز وب‌هوک (در صورت نیاز)، و در صورت پشتیبانی، پروکسی بله.
  - در `_collectAdvancedPayload` (یا معادل) این مقادیر به payload درخواست PUT تنظیمات اضافه شوند.
  - در بارگذاری اولیه از `getNotificationsConfig`، فیلدهای مربوط به بله از پاسخ خوانده و در کنترلرها قرار گیرند.
- **سرویس:** `hesabixUI/hesabix_ui/lib/services/admin_system_settings_service.dart` (یا مشابه): در متد مربوط به دریافت/ارسال تنظیمات نوتیفیکیشن، فیلدهای بله در map درخواست/پاسخ در نظر گرفته شوند.

---

### ۲.۱۰ UI – تنظیمات نوتیفیکیشن کاربر (فعال/غیرفعال کانال)

- **فایل:** `hesabixUI/hesabix_ui/lib/pages/profile/notifications_settings_page.dart`
- **تغییرات:**
  - یک سوئیچ/کارت «بله» برای فعال/غیرفعال کردن دریافت نوتیفیکیشن از طریق بله (مشابه تلگرام، ایمیل، SMS، InApp).
  - متغیرهای state مثل `_bale` و در `_load` مقدار `bale_enabled` از API خوانده شود؛ در `_save` مقدار `baleEnabled` به `updateSettings` پاس داده شود.
- **سرویس:** `hesabixUI/hesabix_ui/lib/services/notifications_service.dart`: در `getSettings` و `updateSettings` فیلدهای `bale_enabled` در request/response لحاظ شوند.
- **دکمه «ارسال تست»:** برای کانال بله اضافه شود (فراخوانی همان endpoint تست با `channel=bale`).

---

### ۲.۱۱ UI – اتصال/قطع اتصال اکانت بله (پروفایل کاربر)

- **سرویس:** ایجاد سرویس مشابه `TelegramIntegrationService` برای بله، مثلاً `BaleIntegrationService` با متدهای:
  - `createLink()` → POST `/api/v1/integrations/bale/link`
  - `getStatus()` → GET `/api/v1/integrations/bale/status`
  - `unlink()` → DELETE `/api/v1/integrations/bale/unlink`
- **صفحه پروفایل/نوتیفیکیشن:** در جایی که اتصال تلگرام نمایش داده می‌شود (مثلاً `user_notifications_page.dart` یا account_settings)، یک بخش «اتصال بله» اضافه شود:
  - نمایش وضعیت اتصال (متصل است یا نه، و در صورت تمایل تاریخ اتصال).
  - دکمه «اتصال به بله»: درخواست لینک، نمایش deep link / QR برای باز کردن ربات بله با توکن، و polling وضعیت تا زمانی که کاربر در بله /start را بزند و اتصال تأیید شود.
  - دکمه «قطع اتصال بله»: فراخوانی unlink و به‌روزرسانی وضعیت.
- **ترجمه‌ها:** در `app_fa.arb`, `app_en.arb` و فایل‌های تولید شده، رشته‌هایی مثل «اتصال بله»، «قطع اتصال بله»، «بله متصل است» و پیام‌های خطا/موفقیت اضافه شوند.

---

### ۲.۱۲ UI – لیست کانال‌ها در جاهای مختلف

- **تاریخچه نوتیفیکیشن:** در صفحه تاریخچه، مقدار `channel` ممکن است `bale` باشد؛ نمایش برچسب «بله» برای این رکوردها (مشابه تلگرام، ایمیل، SMS).
- **ورود با OTP:** در صفحه ورود با OTP، اگر API کانال `bale` را در `available_channels` برگرداند، گزینه ارسال کد به «بله» نمایش داده شود و در `channel_names` نام «بله» استفاده شود.
- **ادمین قالب‌های نوتیفیکیشن:** در فرم/لیست قالب‌های سیستمی، در dropdown یا لیست کانال‌ها گزینه «بله» اضافه شود.

---

### ۲.۱۳ مستندات و تست

- **مستندات API:** به‌روزرسانی OpenAPI/Swagger برای endpointهای جدید (integrations/bale، تنظیمات بله در admin، و فیلدهای بله در notifications/settings و test).
- **تست دستی/اتوماسیون:**
  - تنظیم توکن ربات بله در ادمین و تست ارسال نوتیفیکیشن تست به کانال بله.
  - سناریوی لینک: ایجاد لینک، باز کردن بله و /start <token>، بررسی به‌روزرسانی وضعیت و ارسال نوتیفیکیشن به کاربر از طریق بله.
  - ورود با OTP از طریق کانال بله.
  - قطع اتصال و اطمینان از عدم ارسال به بله بعد از unlink.

---

## ۳. خلاصه فهرست کارها (چک‌لیست)

| ردیف | لایه | مورد |
|------|------|------|
| 1 | DB | فیلدهای `bale_chat_id`, `bale_connected_at` در مدل User و مایگریشن |
| 2 | DB | مدل و جدول `bale_link_tokens` و BaleRepository |
| 3 | Backend | تنظیمات: Settings، system_settings_service (get/set + effective)، کلیدهای بله در DB |
| 4 | Backend | BaleProvider (ارسال پیام با API بله) |
| 5 | Backend | NotificationService: اضافه کردن بله به کانال‌ها و شاخه ارسال برای channel=bale |
| 6 | Backend | API ادمین: NotificationsConfigPayload و PUT/GET notifications برای بله |
| 7 | Backend | API notifications: SettingsPayload، GET/PUT settings، تست با channel=bale |
| 8 | Backend | API integrations/bale: link, status, unlink, webhook |
| 9 | Backend | OTP login: get_available_channels و send_login_otp برای کانال bale؛ auth API و channel_names |
| 10 | Backend | قالب‌های ادمین و seed: پشتیبانی کانال bale و قالب‌های پیش‌فرض |
| 11 | Backend | نقاط دیگر: support، workflow، notification_processor در صورت نیاز |
| 12 | UI | صفحه تنظیمات نوتیفیکیشن ادمین: کارت بله و فیلدها |
| 13 | UI | صفحه تنظیمات نوتیفیکیشن کاربر: سوئیچ بله و ارسال تست |
| 14 | UI | اتصال/قطع بله در پروفایل: سرویس و UI لینک/وضعیت/قطع |
| 15 | UI | تاریخچه و OTP و ادمین قالب‌ها: نمایش/انتخاب کانال بله |
| 16 | l10n | ترجمه‌های مربوط به بله در arb و تولید شده |
| 17 | مستندات/تست | به‌روزرسانی API docs و سناریوهای تست |

---

## ۴. نکات تکمیلی

- **API بله:** پایه API معمولاً روی `https://tapi.bale.ai` است؛ مستندات رسمی بله برای متدهای `sendMessage`، ساختار webhook و فرمت deep link باید ملاک باشد.
- **پروکسی:** در صورت نیاز به استفاده از پروکسی برای دسترسی به API بله (مشابه تلگرام)، همان الگوی telegram_proxy در تنظیمات و در BaleProvider قابل تکرار است.
- **اولویت کانال:** در لیست پیش‌فرض کانال‌ها، قرار دادن بله در کنار تلگرام منطقی است تا کاربران ایرانی بتوانند یکی از این دو (یا هر دو) را انتخاب کنند.
- **نوتیفیکیشن کسب‌وکار:** افزودن بله به «نوتیفیکیشن به مشتری/شخص» (مثل قالب فاکتور/تعمیر از نوع sms/email) نیاز به تعریف نحوه نگهداری شناسه بله برای «شخص» دارد و می‌توان در فاز دوم انجام شود.

این سناریو تمام لایه‌ها از مدیریت و تنظیمات تا استفاده در ارسال نوتیفیکیشن و کوچک‌ترین بخش‌های UI و API را پوشش می‌دهد و می‌توان آن را به صورت تدریجی (مثلاً ابتدا Backend و ادمین، سپس لینک کاربر و OTP، و در آخر بهبودهای UI) پیاده‌سازی کرد.
