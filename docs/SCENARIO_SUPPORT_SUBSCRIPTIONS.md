# سناریو: اشتراک پشتیبانی کاربر (پرداخت مستقیم درگاه — بدون کسب‌وکار و بدون کیف‌پول)

## ۱. خلاصه اجرایی

بخش تیکت‌های پشتیبانی امروز برای همهٔ کاربران (در صورت فعال بودن سوییچ سیستم) **رایگان** است و هیچ مدل قیمت‌گذاری، اشتراک، صورتحساب یا گزارش درآمد ندارد.

این سناریو لایهٔ **اشتراک پشتیبانی در سطح کاربر (User)** را اضافه می‌کند تا:

- پشتیبانی بتواند **رایگان**، **پولی**، یا **ترکیبی (سهمیه رایگان + پولی)** باشد.
- کاربر بتواند پلن‌های **۱ ماهه / ۳ ماهه / ۶ ماهه / ۱۲ ماهه** بخرد.
- مدیر سیستم قیمت‌ها، پلن‌ها و قوانین دسترسی را کنترل کند.
- پرداخت **مستقیم از درگاه بانکی ثبت‌شده در تنظیمات سیستم** انجام شود (هدایت کاربر به سایت بانک/درگاه).
- **سوابق صورت‌حساب** برای کاربر قابل مشاهده باشد.
- در پنل مدیریت، **گزارش آماری** درآمد و اشتراک اضافه شود.
- ماژول تیکت فعلی (پیام، SLA، اپراتور، CSAT، پیوست، realtime) دست نخورده بماند و فقط **گیت دسترسی** روی آن سوار شود.

### اصول قطعی (غیرقابل مذاکره در این سناریو)

| اصل | توضیح |
|-----|--------|
| بدون کسب‌وکار | هیچ `business_id` در خرید، اشتراک، صورتحساب، callback یا entitlement وجود ندارد. |
| بدون کیف‌پول | هیچ شارژ/برداشت از `Wallet`، `WalletTransaction` نوع top-up/service، یا موجودی کسب‌وکار انجام نمی‌شود. |
| پرداخت مستقیم | پس از انتخاب پلن، بلافاصله درخواست پرداخت روی درگاه سیستم ساخته می‌شود و کاربر به URL درگاه هدایت می‌شود. |
| مالکیت کاربر | اشتراک و صورتحساب متعلق به `user_id` است (همان کاربری که تیکت می‌سازد). |
| درگاه سیستم | فقط از `payment_gateways` فعال در مدیریت سیستم استفاده می‌شود؛ `business_payment_gateways` اصلاً دخیل نیست. |

---

## ۲. اهداف و غیرهدف‌ها

### اهداف

1. کنترل حالت پشتیبانی (رایگان / پولی / ترکیبی) توسط ادمین.
2. CRUD پلن‌های پشتیبانی با مدت و قیمت.
3. خرید مستقیم با درگاه (زرین‌پال / پارسیان / بیت‌پی — همان ارائه‌دهندگان فعلی سیستم).
4. فعال‌سازی اشتراک فقط پس از تأیید موفق callback درگاه.
5. نمایش و دانلود/جزئیات سوابق صورت‌حساب برای کاربر.
6. مسدودسازی ایجاد/پاسخ تیکت وقتی entitlement فعال نیست (بسته به حالت سیستم).
7. گزارش آماری مدیریتی (درآمد، اشتراک فعال، تبدیل، انقضا، CSAT تفکیک‌شده).
8. اعلان‌های انقضا، grace period، تمدید، و تمایز SLA/اولویت بر اساس پلن (پیشنهادی ضروری).

### غیرهدف‌ها (عمداً خارج از اسکوپ)

- اتصال به کیف‌پول کسب‌وکار یا فاکتور حسابداری کسب‌وکار.
- فروش پشتیبانی به‌صورت لایسنس سازمانی چندکاربره (می‌تواند فاز بعد باشد).
- تغییر هستهٔ اپراتور/SLA/پیام‌رسانی تیکت مگر برای گیت entitlement و متادیتای پلن.
- پرداخت چندمرحله‌ای اقساطی.

---

## ۳. واژه‌نامه

| اصطلاح | معنی |
|--------|------|
| **حالت پشتیبانی (Support Mode)** | تنظیم سراسری: `free` / `paid` / `hybrid` |
| **پلن پشتیبانی (Support Plan)** | بستهٔ قابل فروش با `period_months` و `price` |
| **اشتراک (Subscription)** | entitlement زمانی کاربر روی یک پلن (`starts_at` … `ends_at`) |
| **صورت‌حساب پشتیبانی (Support Invoice)** | سند مالی کاربر برای یک خرید/تمدید؛ مستقل از فاکتور حسابداری کسب‌وکار |
| **نشست پرداخت (Payment Session)** | رکورد موقت/دائمی برای ردیابی درخواست درگاه تا verify |
| **سهمیه رایگان (Free Quota)** | در حالت hybrid: تعداد تیکت قابل ایجاد در بازهٔ زمانی بدون اشتراک |
| **Grace Period** | مهلت کوتاه بعد از انقضا که هنوز دسترسی خواندن/پاسخ محدود برقرار است |
| **Entitlement** | نتیجهٔ محاسبه: آیا کاربر الان حق ایجاد/پاسخ تیکت دارد یا نه |

---

## ۴. حالت‌های سیستم (ادمین)

کلید جدید در تنظیمات سیستم (کنار `support_tickets_enabled`):

### ۴.۱. `support_billing_mode`

| مقدار | رفتار |
|-------|--------|
| `free` | مثل امروز: همه با تیکتینگ فعال می‌توانند تیکت بسازند/پاسخ دهند. پلن‌ها فقط برای نمایش/آینده اختیاری‌اند؛ خرید اجباری نیست. |
| `paid` | بدون اشتراک فعال (یا grace معتبر)، ایجاد تیکت و پاسخ کاربر **ممنوع**. مشاهده تیکت‌های قبلی مجاز است (read-only). |
| `hybrid` | تا سقف سهمیه رایگان ماهانه می‌توان تیکت ساخت؛ بیش از سقف یا برای ویژگی‌های پلن پولی، نیاز به اشتراک. |

### ۴.۲. سایر تنظیمات سراسری

| کلید | نوع | پیش‌فرض پیشنهادی | توضیح |
|------|-----|------------------|--------|
| `support_tickets_enabled` | bool | موجود | اگر خاموش باشد، کل تیکتینگ کاربر بسته است (اپراتور باز می‌ماند). |
| `support_tickets_disabled_message` | string | موجود | پیام نمایش به کاربر. |
| `support_billing_mode` | enum | `free` | بالا. |
| `support_free_quota_per_month` | int | `2` | فقط در `hybrid`: تعداد تیکت جدید قابل ایجاد در هر ماه تقویمی شمسی/میلادی (قابل انتخاب؛ پیش‌فرض میلادی UTC یا تقویم سیستم). |
| `support_grace_period_days` | int | `3` | بعد از `ends_at`؛ در این بازه پاسخ به تیکت‌های باز مجاز، ایجاد تیکت جدید خیر (قابل تنظیم دقیق‌تر در بخش قوانین). |
| `support_allow_read_without_subscription` | bool | `true` | در حالت paid/hybrid بدون اشتراک، لیست و جزئیات تیکت‌های قبلی قابل مشاهده باشد. |
| `support_require_subscription_to_reply` | bool | `true` | در paid: بدون اشتراک حتی پاسخ هم بسته شود. در hybrid: اگر سهمیه تمام شده و اشتراک ندارد، پاسخ بسته شود (قابل پیکربندی). |
| `support_default_gateway_id` | int\|null | اولین درگاه فعال سیستم | درگاه پیش‌فرض برای خرید پشتیبانی. اگر null و چند درگاه فعال باشد، کاربر از بین درگاه‌های سیستم انتخاب می‌کند. |
| `support_invoice_prefix` | string | `SUP` | پیشوند کد صورت‌حساب (`SUP-1405-000123`). |
| `support_expiry_notify_days` | int[] | `[7, 3, 1]` | روزهای قبل از انقضا برای اعلان. |
| `support_paid_priority_boost` | bool | `true` | تیکت کاربران دارای اشتراک پولی، در صف اپراتور با نشان/اولویت نسبی بالاتر نمایش داده شود (بدون شکستن SLA policy موجود مگر پلن صریحاً SLA داشته باشد). |

**نکته مهاجرت:** مقدار پیش‌فرض `support_billing_mode = free` است تا رفتار فعلی سیستم بعد از دیپلوی تغییر نکند.

---

## ۵. مدل داده

همه جداول جدید **بدون FK به businesses**.

### ۵.۱. `support_plans`

| فیلد | نوع | توضیح |
|------|-----|--------|
| `id` | PK | |
| `name` | string(200) | نام نمایشی |
| `code` | string(100) unique | مثلاً `support_1m`, `support_3m` |
| `period_months` | int | فقط یکی از: `1`, `3`, `6`, `12` (در فاز ۱) |
| `price` | numeric(18,2) | مبلغ قابل پرداخت به ریال/واحد ارز سیستم |
| `currency_id` | FK currencies | اجباری |
| `is_free` | bool | پلن رایگان (قیمت ۰)؛ فعال‌سازی بدون درگاه |
| `is_active` | bool | قابل خرید بودن |
| `sort_order` | int | ترتیب نمایش کارت‌ها |
| `description` | text\|null | توضیح کوتاه برای کاربر |
| `features_json` | JSON\|null | لیست بولت ویژگی‌ها برای UI |
| `max_open_tickets` | int\|null | سقف تیکت باز همزمان؛ null = نامحدود |
| `sla_policy_id` | FK\|null | اختیاری: اتصال به SLA خاص این پلن |
| `priority_weight` | int | پیش‌فرض `0`؛ برای boost در لیست اپراتور |
| `includes_priority_support` | bool | نشان «پشتیبانی اولویت‌دار» در UI |
| `trial_days` | int | پیش‌فرض `0`؛ اگر >0 و کاربر هرگز اشتراک نداشته، می‌تواند trial بگیرد (پیشنهادی) |
| `created_at` / `updated_at` | datetime | |

**Seed پیشنهادی اولیه (غیرفعال تا ادمین قیمت بگذارد یا با قیمت ۰ و is_free):**

- پشتیبانی ۱ ماهه (`period_months=1`)
- پشتیبانی ۳ ماهه (`period_months=3`)
- پشتیبانی ۶ ماهه (`period_months=6`)
- پشتیبانی ۱۲ ماهه (`period_months=12`)

### ۵.۲. `support_subscriptions`

| فیلد | نوع | توضیح |
|------|-----|--------|
| `id` | PK | |
| `user_id` | FK users CASCADE | مالک |
| `plan_id` | FK support_plans RESTRICT | پلن خریداری‌شده |
| `status` | string | `pending` / `active` / `grace` / `expired` / `cancelled` / `replaced` |
| `starts_at` | datetime | |
| `ends_at` | datetime\|null | برای پلن‌های مدت‌دار اجباری |
| `grace_ends_at` | datetime\|null | `ends_at + grace_period_days` |
| `auto_renew` | bool | پیش‌فرض `false`؛ فاز ۱ می‌تواند UI داشته باشد ولی تمدید خودکار فقط اگر درگاه توکن ذخیره کند — **در فاز ۱ توصیه: فقط تمدید دستی** |
| `source_invoice_id` | FK support_invoices\|null | صورتحسابی که این اشتراک را فعال کرد |
| `cancelled_at` | datetime\|null | |
| `cancel_reason` | string\|null | |
| `created_at` / `updated_at` | datetime | |

**قواعد:**

- در هر لحظه حداکثر **یک** اشتراک `active` (یا `grace`) برای هر کاربر.
- خرید جدید در حین اشتراک فعال = **تمدید/ارتقا** (بخش ۷.۴).
- `pending` فقط اگر بخواهیم قبل از پرداخت رکورد بسازیم؛ ترجیح: اول invoice + payment_session، بعد از verify اشتراک `active` ساخته/تمدید شود.

### ۵.۳. `support_invoices`

| فیلد | نوع | توضیح |
|------|-----|--------|
| `id` | PK | |
| `user_id` | FK users | |
| `plan_id` | FK support_plans | |
| `code` | string(50) unique | مثلاً `SUP-20260721-000042` |
| `invoice_type` | string | `purchase` / `renewal` / `upgrade` / `trial` |
| `amount` | numeric(18,2) | مبلغ نهایی پرداخت‌شده/قابل پرداخت |
| `discount_amount` | numeric(18,2) | پیش‌فرض ۰ |
| `currency_id` | FK | |
| `status` | string | `draft` / `awaiting_payment` / `paid` / `failed` / `expired` / `void` / `refunded` |
| `issued_at` | datetime | |
| `due_at` | datetime\|null | مهلت پرداخت نشست (مثلاً ۳۰ دقیقه) |
| `paid_at` | datetime\|null | |
| `payment_session_id` | FK\|null | |
| `gateway_id` | int\|null | درگاه استفاده‌شده |
| `gateway_provider` | string\|null | zarinpal/parsian/bitpay |
| `gateway_ref` | string\|null | Authority/Token |
| `gateway_trace` | string\|null | RefId بانکی |
| `period_months` | int | اسنپ‌شات مدت در زمان خرید |
| `coverage_starts_at` | datetime\|null | بازه پوشش بعد از پرداخت |
| `coverage_ends_at` | datetime\|null | |
| `promo_code_id` | FK\|null | اختیاری فاز ۱.۵ |
| `extra_info` | JSON\|null | جزئیات خام verify، IP، user-agent، … |
| `created_at` / `updated_at` | datetime | |

### ۵.۴. `support_payment_sessions`

جایگزین کیف‌پول برای ردیابی درگاه — **کاملاً مستقل از `wallet_transactions`.**

| فیلد | نوع | توضیح |
|------|-----|--------|
| `id` | PK | |
| `user_id` | FK users | |
| `invoice_id` | FK support_invoices | |
| `gateway_id` | FK payment_gateways | درگاه سیستم |
| `amount` | numeric(18,2) | |
| `currency_id` | FK | |
| `status` | string | `created` / `redirected` / `verifying` / `paid` / `failed` / `cancelled` / `expired` |
| `external_ref` | string\|null | Authority/Token |
| `provider_payload` | JSON\|null | پاسخ خام initiate (بدون secret) |
| `verify_payload` | JSON\|null | پاسخ خام verify |
| `client_return_path` | string\|null | مسیر برگشت فرانت (`/user/profile/support/billing?…`) |
| `expires_at` | datetime | انقضای نشست پرداخت |
| `paid_at` | datetime\|null | |
| `created_at` / `updated_at` | datetime | |

### ۵.۵. `support_usage_counters` (برای hybrid)

| فیلد | نوع | توضیح |
|------|-----|--------|
| `id` | PK | |
| `user_id` | FK | |
| `period_key` | string | مثلاً `2026-07` (ماه میلادی) یا کلید شمسی |
| `tickets_created` | int | شمار ایجاد تیکت در آن دوره |
| `updated_at` | datetime | |

Unique(`user_id`, `period_key`).

### ۵.۶. `support_promo_codes` (پیشنهادی — فاز ۱.۵، غنای فروش)

| فیلد | توضیح |
|------|--------|
| `code`, `percent_off` یا `amount_off`, `valid_from/to`, `max_redemptions`, `per_user_limit`, `applicable_plan_ids`, `is_active` | |

در فاز ۱ می‌توان جدول را ساخت ولی UI ادمین را ساده نگه داشت؛ یا کامل در همان فاز اول اگر زمان اجازه دهد.

---

## ۶. لایه پرداخت (مستقیم به بانک)

### ۶.۱. انتخاب درگاه

1. خواندن `support_default_gateway_id` از تنظیمات سیستم.
2. اگر معتبر و `is_active` باشد → همان.
3. وگرنه: لیست `payment_gateways` با `is_active=true` (سطح سیستم).
4. اگر هیچ درگاه فعالی نباشد → خطا با پیام واضح به کاربر و ادمین: «درگاه پرداخت سیستم پیکربندی نشده است.»
5. **هرگز** از `business_payment_gateways` استفاده نشود.

### ۶.۲. جریان خرید (Happy Path)

```
کاربر → انتخاب پلن
     → (اختیاری) وارد کردن کد تخفیف
     → POST ایجاد صورت‌حساب + نشست پرداخت
     → Backend: initiate روی درگاه سیستم (بدون business_id)
     → پاسخ: payment_url
     → فرانت: باز کردن/هدایت به payment_url (سایت بانک/درگاه)
     → کاربر پرداخت می‌کند
     → درگاه → Callback سرور حسابیکس
     → Verify
     → invoice=paid + subscription active/extended
     → Redirect کاربر به صفحه نتیجه در UI پشتیبانی
```

### ۶.۳. تغییرات فنی لازم روی سرویس پرداخت

امروز `initiate_payment(..., business_id, tx_id, ...)` و callback عمدتاً به `WalletTransaction` و `confirm_top_up` گره‌خورده است.

برای پشتیبانی باید یکی از این دو مسیر (ترجیح: A):

**مسیر A — تعمیم کنترل‌شده (توصیه‌شده)**

- افزودن تابع‌های موازی:
  - `initiate_system_payment(db, *, gateway_id, amount, callback_kind, internal_id, description, metadata)`
  - `verify` موجود بماند ولی بعد از verify به‌جای `confirm_top_up`، بر اساس `callback_kind` / رجیستری handler، `confirm_support_payment(session_id)` صدا زده شود.
- Callback جدید یا پارامتر `kind=support` روی callbackهای موجود:
  - مثلاً `/api/v1/payments/callback/{provider}?kind=support&session_id=…`
  - یا مسیر اختصاصی: `/api/v1/support/payments/callback/{provider}`
- `callback_url` درگاه برای پشتیبانی باید در config درگاه یا به‌صورت override در initiate به URL پشتیبانی اشاره کند (یا همان URL عمومی با `kind`).

**مسیر B — کپی حداقلی**

- سرویس جدا `support_payment_service.py` که همان پروتکل زرین‌پال/پارسیان/بیت‌پی را صدا می‌زند ولی به `support_payment_sessions` می‌نویسد.
- خطر: دوباره‌کاری؛ فقط اگر تعمیم payment_service پرریسک باشد.

**الزام:** در هر دو مسیر، مبلغ، `session_id`، و `user_id` قبل از redirect در DB قفل شوند؛ بعد از verify مبلغ درگاه با مبلغ نشست **باید** برابر باشد وگرنه `failed` و اشتراک فعال نشود.

### ۶.۴. نتیجه برگشت به فرانت

صفحهٔ نتیجه داخل پروفایل پشتیبانی:

- موفقیت: «اشتراک شما تا {ends_at} فعال شد» + دکمه رفتن به تیکت‌ها / صدور تیکت.
- شکست: دلیل خلاصه + دکمه تلاش مجدد (ساخت نشست جدید روی همان invoice اگر هنوز `awaiting_payment` و منقضی نشده؛ در غیر این صورت invoice جدید).
- در وب‌ویو موبایل/دسکتاپ: همان الگوی `detect_source` و صفحات HTML موفقیت/شکست فعلی قابل الهام است، ولی مقصد نهایی UX باید داخل اپ پشتیبانی باشد نه wallet.

### ۶.۵. Idempotency و امنیت پرداخت

- Verify تکراری برای یک `session` که قبلاً `paid` است → no-op موفق (اشتراک دوباره ساخته نشود).
- نشست منقضی (`expires_at`) بعد از بازگشت دیرهنگام → `failed/expired`؛ کاربر باید دوباره بخرد.
- امضای/Authority باید به همان `session_id` و `amount` بخورد.
- کاربر فقط به invoice/session خودش دسترسی دارد.
- ادمین می‌تواند invoice را `void` کند ولی refund بانکی دستی/خارج از باند است مگر بعداً API استرداد اضافه شود.
- حداقل مبلغ درگاه (مثلاً بیت‌پی ۵۰۰۰ ریال) قبل از initiate چک شود؛ پلن با قیمت کمتر از حداقل، در حالت غیررایگان قابل خرید نباشد یا ادمین هشدار ببیند.

### ۶.۶. پلن رایگان (`is_free` یا price=0)

- بدون redirect به بانک.
- صورت‌حساب با `status=paid`, `amount=0`, `invoice_type=purchase|trial`.
- اشتراک فوراً فعال می‌شود.
- محدودیت: هر کاربر فقط یک‌بار پلن رایگان غیر‌trial، یا طبق سیاست ادمین (`max_free_activations_per_user`).

---

## ۷. قوانین Entitlement (دسترسی تیکت)

تابع مرکزی پیشنهادی:

`get_support_entitlement(db, user_id) -> SupportEntitlement`

خروجی منطقی:

```text
mode: free|paid|hybrid
can_create_ticket: bool
can_reply: bool
can_read: bool
reason_code: ok|billing_disabled|no_subscription|quota_exceeded|grace_reply_only|…
subscription: {plan, status, ends_at, grace_ends_at} | null
quota: {used, limit, period_key} | null   # فقط hybrid
upsell_required: bool
```

### ۷.۱. ماتریس رفتار

| حالت | اشتراک فعال | Grace | سهمیه hybrid باقی | ایجاد تیکت | پاسخ | خواندن |
|------|-------------|-------|-------------------|------------|------|--------|
| tickets disabled | — | — | — | خیر | خیر | خیر (یا پیام disabled) |
| `free` | — | — | — | بله | بله | بله |
| `paid` | بله | — | — | بله* | بله | بله |
| `paid` | خیر | بله | — | خیر | بله (اگر تنظیم اجازه دهد) | بله |
| `paid` | خیر | خیر | — | خیر | خیر/بسته به تنظیم | بله اگر allow_read |
| `hybrid` | بله | — | — | بله* | بله | بله |
| `hybrid` | خیر | — | بله | بله (از سهمیه) | بله | بله |
| `hybrid` | خیر | — | خیر | خیر | خیر/بسته به تنظیم | بله اگر allow_read |

\* علاوه بر سقف `max_open_tickets` پلن.

### ۷.۲. نقاط اعمال گیت

- `POST /api/v1/support` (ایجاد)
- `POST /api/v1/support/{id}/messages` وقتی `sender_type=user`
- `PUT .../reopen` (بازگشایی = نیازمند entitlement ایجاد/پاسخ)
- فرانت: قبل از نمایش فرم ایجاد، banner وضعیت + CTA خرید

اپراتور و AI اپراتور **تحت این گیت نیستند**.

### ۷.۳. شمارش سهمیه hybrid

- فقط روی **ایجاد موفق** تیکت اینکریمنت شود.
- تیکت حذف‌شده توسط ادمین سهمیه را برنمی‌گرداند مگر سیاست خلاف آن تعریف شود (پیش‌فرض: برنمی‌گردد).
- کاربر دارای اشتراک فعال از سهمیه رایگان مصرف نمی‌کند (یا مصرف می‌کند ولی بی‌اثر است — ترجیح: مصرف نکند تا آمار سهمیه تمیز بماند).

### ۷.۴. تمدید و ارتقا

| سناریو | رفتار |
|--------|--------|
| تمدید همان پلن قبل از انقضا | بعد از پرداخت موفق: `ends_at = max(now, ends_at) + period_months` (stack) |
| تمدید بعد از انقضا (خارج grace) | `starts_at=now`, `ends_at=now+period` |
| ارتقا به پلن گران‌تر/طولانی‌تر وسط دوره | فاز ۱ پیشنهادی: پرداخت کامل پلن جدید + باقیمانده روزهای قبلی به‌صورت اعتبار روز به انتهای جدید اضافه شود **یا** ساده‌تر: فقط stack مدت بدون proration. **توصیه فاز ۱: بدون proration مبلغی؛ فقط افزودن مدت به انتهای اشتراک فعلی** تا پیچیدگی مالی کم شود. |
| خرید همزمان دو نشست باز | فقط یک `awaiting_payment` فعال per user؛ نشست قبلی `cancelled/expired` شود. |

### ۷.۵. انقضا و Grace

Job پس‌زمینه (مشابه jobs پشتیبانی موجود):

1. `active` و `now > ends_at` و `now <= grace_ends_at` → `grace`
2. `now > grace_ends_at` → `expired`
3. ارسال اعلان‌های `support.subscription_expiring` در روزهای تنظیم‌شده
4. اعلان `support.subscription_expired` و `support.subscription_grace_ended`

---

## ۸. تجربه کاربری (Flutter)

### ۸.۱. ساختار صفحه پشتیبانی کاربر

تب‌ها / بخش‌های پیشنهادی در `/user/profile/support`:

1. **تیکت‌ها** (موجود)
2. **اشتراک من** — وضعیت فعلی، تاریخ پایان، پلن، دکمه تمدید
3. **خرید پشتیبانی** — کارت پلن‌های فعال ۱/۳/۶/۱۲
4. **صورت‌حساب‌ها** — لیست invoiceها با فیلتر وضعیت

Header مشترک: چیپ وضعیت (`رایگان سیستمی` / `فعال تا …` / `منقضی` / `سهمیه: ۲/۲`).

### ۸.۲. جریان UI خرید

1. کارت پلن → جزئیات ویژگی‌ها → «پرداخت و فعال‌سازی»
2. دیالوگ تأیید مبلغ و مدت (بدون انتخاب کسب‌وکار)
3. اگر چند درگاه سیستم فعال و default مشخص نیست → انتخاب درگاه
4. Loading «در حال اتصال به درگاه…»
5. External browser / WebView / launchUrl به `payment_url`
6. بازگشت به اپ → صفحه نتیجه با poll کوتاه وضعیت invoice (در صورتی که کاربر دستی برگشت قبل از callback)

### ۸.۳. Empty / Block states

- حالت paid بدون اشتراک: به‌جای فرم ایجاد تیکت، کارت upsell با پلن‌های پیشنهادی.
- خطای درگاه پیکربندی‌نشده: پیام غیرمقصرانه برای کاربر + لاگ برای ادمین.
- تیکتینگ کلاً disabled: همان پیام فعلی.

### ۸.۴. صورت‌حساب‌ها

ستون‌ها: کد، نوع، پلن، مبلغ، وضعیت، تاریخ صدور، تاریخ پرداخت، شماره پیگیری درگاه.

جزئیات: اسنپ‌شات پلن + بازه پوشش + دکمه «پرداخت مجدد» اگر `awaiting_payment` و معتبر.

---

## ۹. پنل مدیریت سیستم

### ۹.۱. صفحه تنظیمات پشتیبانی (گسترش system configuration یا صفحه اختصاصی)

- فعال/غیرفعال تیکتینگ کاربر (موجود)
- حالت صورتحساب: free / paid / hybrid
- سهمیه رایگان، grace، اعلان انقضا
- درگاه پیش‌فرض پشتیبانی
- پیشوند صورت‌حساب

### ۹.۲. صفحه «پلن‌های پشتیبانی»

CRUD مشابه `storage_plans_admin_page`:

- نام، کد، مدت (dropdown ۱/۳/۶/۱۲)، قیمت، ارز، فعال، رایگان، ترتیب، توضیحات، ویژگی‌ها، سقف تیکت باز، وزن اولویت، SLA اختیاری

اعتبارسنجی: اگر `is_free` → `price` باید ۰ باشد.

### ۹.۳. صفحه/تب «صورت‌حساب‌های پشتیبانی»

- جستجو بر اساس کد، کاربر، وضعیت، بازه تاریخ
- جزئیات verify درگاه (فقط ادمین)
- عملیات: void (قبل از پرداخت)، علامت‌گذاری دستی paid فقط برای سوپرادمین با audit log (موارد استثنایی پشتیبانی)

### ۹.۴. گزارش آماری (ابزار جدید)

داشبورد جدا یا تب در operator/admin:

**KPIهای ضروری**

| شاخص | تعریف |
|------|--------|
| درآمد دوره | sum(invoice.amount) where paid در بازه |
| تعداد پرداخت موفق / ناموفق | |
| نرخ تبدیل | کاربران visit-plans یا blocked-create → paid (تقریبی با event) |
| اشتراک فعال الان | count status in (active, grace) |
| تفکیک پلن | pie/bar بر اساس period_months |
| MRR تقریبی | نرمال‌سازی مبلغ به ماه: `amount / period_months` برای invoiceهای paid در دوره |
| در شرف انقضا ۷ روز | |
| انقضاشده دوره | |
| میانگین CSAT | کاربران با اشتراک فعال vs بدون/رایگان |
| تیکت به‌ازای مشترک | |
| سهمیه hybrid مصرف‌شده | متوسط used/limit |

**فیلترها:** از–تا، پلن، درگاه، وضعیت.

**خروجی:** جدول + نمودار ساده (الهام از `support_activity_chart`) + خروجی CSV برای ادمین.

### ۹.۵. اپراتور

- نشان کوچک روی تیکت: «مشترک» / «اولویت‌دار» اگر `includes_priority_support`.
- فیلتر لیست: فقط مشترکان.
- در جزئیات تیکت: پلن فعال کاربر و تاریخ پایان (فقط خواندنی).

---

## ۱۰. API (پیشنهادی)

### کاربر

| Method | Path | توضیح |
|--------|------|--------|
| GET | `/api/v1/support/billing/entitlement` | وضعیت دسترسی فعلی |
| GET | `/api/v1/support/billing/plans` | پلن‌های فعال قابل خرید |
| GET | `/api/v1/support/billing/subscription` | اشتراک جاری |
| GET | `/api/v1/support/billing/invoices` | لیست صورت‌حساب‌های کاربر |
| GET | `/api/v1/support/billing/invoices/{id}` | جزئیات |
| POST | `/api/v1/support/billing/checkout` | body: `{plan_id, gateway_id?, promo_code?}` → `{invoice, payment_url?}` |
| POST | `/api/v1/support/billing/invoices/{id}/retry-payment` | نشست جدید |
| GET | `/api/v1/support/billing/gateways` | درگاه‌های سیستم مجاز برای پشتیبانی (بدون secret) |

### Callback

| Method | Path | توضیح |
|--------|------|--------|
| GET/POST | `/api/v1/support/payments/callback/{provider}` | verify و فعال‌سازی |

### ادمین

| Method | Path | توضیح |
|--------|------|--------|
| CRUD | `/api/v1/admin/support-plans` | |
| GET | `/api/v1/admin/support-invoices` | جستجو |
| POST | `/api/v1/admin/support-invoices/{id}/void` | |
| GET | `/api/v1/admin/support-billing/stats` | خلاصه KPI |
| GET | `/api/v1/admin/support-billing/stats/timeseries` | سری زمانی درآمد/خرید |
| GET | `/api/v1/admin/support-billing/stats/export.csv` | |
| PATCH | تنظیمات سیستم موجود | فیلدهای بخش ۴ |

پرمیشن‌ها: ادمین سیستم / سوپرادمین؛ آمار می‌تواند به `support_operator` فقط‌خواندنی هم داده شود (اختیاری؛ پیش‌فرض فقط ادمین مالی/سیستم).

---

## ۱۱. اعلان‌ها (Event Keys پیشنهادی)

| Event | زمان | گیرنده |
|-------|------|--------|
| `support.subscription_activated` | پرداخت موفق / فعال‌سازی رایگان | کاربر |
| `support.subscription_renewed` | تمدید موفق | کاربر |
| `support.subscription_expiring` | N روز قبل از ends_at | کاربر |
| `support.subscription_expired` | ورود به expired | کاربر |
| `support.subscription_grace` | ورود به grace | کاربر |
| `support.payment_failed` | verify ناموفق | کاربر |
| `support.quota_exhausted` | hybrid سهمیه تمام | کاربر |
| `support.billing_blocked_create` | تلاش ایجاد بدون entitlement (اختیاری، برای آنالیتیکس) | — یا کاربر راهنما |

کانال‌ها: inapp + email حداقل؛ SMS/تلگرام مطابق زیرساخت ناتیفیکیشن موجود.

---

## ۱۲. موارد پیشنهادی غنی‌سازی (اولویت‌بندی)

### ضروری در همان نسخهٔ اول (P0)

1. حالت‌های `free` / `paid` / `hybrid`
2. پلن‌های ۱/۳/۶/۱۲ + قیمت ادمین
3. Checkout مستقیم درگاه سیستم + callback + فعال‌سازی
4. صورت‌حساب و تاریخچه کاربر
5. گیت create/reply
6. Grace period + اعلان انقضا
7. داشبورد آماری ادمین (KPIهای اصلی)
8. Idempotent verify و یک نشست باز همزمان
9. Seed امن با `billing_mode=free` تا رفتار فعلی نشکند

### بسیار توصیه‌شده هم‌زمان یا بلافاصله بعد (P1)

10. نشان «مشترک/اولویت‌دار» برای اپراتور + `priority_weight`
11. سقف `max_open_tickets` بر اساس پلن
12. اتصال اختیاری پلن به `sla_policy`
13. کد تخفیف
14. Retry پرداخت روی صورت‌حساب awaiting
15. خروجی CSV گزارش
16. Trial چندروزه یک‌بارمصرف
17. صفحه نتیجه پرداخت داخل مسیر پشتیبانی (نه wallet)

### فاز بعد (P2)

18. Auto-renew واقعی (نیازمند پرداخت خودکار/توکن درگاه — فعلاً اکثر درگاه‌های داخلی محدودند)
19. Proration دقیق ارتقا
20. استرداد آنلاین
21. اشتراک سازمانی چندکاربره روی یک پرداخت
22. مالیات/عوارض جدا روی صورت‌حساب
23. وب‌هوک حسابداری خارجی

---

## ۱۳. سازگاری با وضعیت فعلی

| مورد | تصمیم |
|------|--------|
| کاربران فعلی | با `billing_mode=free` بدون تغییر کار می‌کنند |
| تیکت‌های باز | همیشه خواندنی طبق تنظیم؛ با سوییچ به `paid` برای ادامه پاسخ نیاز به خرید دارند |
| اپراتورها | بدون تغییر دسترسی |
| کیف‌پول / کسب‌وکار | صفر تداخل؛ جداول و سرویس‌های جدید |
| درگاه‌های ثبت‌شده ادمین | همان رکوردهای `payment_gateways`؛ فقط مصرف‌کننده جدید |

---

## ۱۴. موارد لبه‌ای و خطاها

| وضعیت | رفتار |
|-------|--------|
| کاربر پرداخت را در بانک لغو کند | session/invoice → failed؛ اشتراک تغییر نکند |
| Dual-tab دوبار checkout | نشست قبلی cancel؛ فقط آخرین معتبر |
| قیمت پلن وسط خرید توسط ادمین عوض شود | مبلغ از اسنپ‌شات invoice؛ نه قیمت لحظه‌ای پلن بعد از صدور |
| پلن وسط خرید غیرفعال شود | checkout جدید ممنوع؛ نشست جاری تا انقضا قابل تکمیل است |
| کاربر حذف‌شده | cascade منطقی؛ گزارش‌ها anonymize اختیاری |
| اختلاف مبلغ verify | failed + هشدار امنیتی در لاگ |
| درگاه sandbox | فقط اگر `is_sandbox` و محیط اجازه دهد؛ در UI ادمین برچسب واضح |
| ساعت سرور / timezone | ذخیره UTC؛ نمایش محلی کاربر در UI |
| همزمانی verify و retry | قفل سطری روی payment_session |

---

## ۱۵. معیارهای پذیرش (Acceptance Criteria)

1. با `billing_mode=free` رفتار تیکت دقیقاً مثل قبل است.
2. با `paid` و بدون اشتراک، ایجاد تیکت API و UI مسدود و پیام upsell نشان داده می‌شود.
3. ادمین می‌تواند ۴ پلن با قیمت‌های مختلف بسازد/ویرایش کند.
4. کاربر با انتخاب پلن به URL درگاه سیستم می‌رود؛ **هیچ انتخاب کسب‌وکار یا کیف‌پولی در UI نیست.**
5. پس از پرداخت موفق، اشتراک فعال و صورت‌حساب `paid` با `gateway_trace` ثبت می‌شود.
6. کاربر لیست صورت‌حساب‌های خودش را می‌بیند و به دیگران دسترسی ندارد.
7. ادمین در گزارش، درآمد بازه و تعداد اشتراک فعال را می‌بیند.
8. انقضای اشتراک پس از job پس‌زمینه وضعیت را عوض می‌کند و اعلان ارسال می‌شود.
9. در کل جریان خرید/callback هیچ نوشتن روی جداول wallet/business برای این محصول رخ نمی‌دهد.
10. Verify تکراری اشتراک دوم نمی‌سازد.

---

## ۱۶. ترتیب پیاده‌سازی پیشنهادی

1. Migration جداول + تنظیمات سیستم + seed پلن‌ها  
2. سرویس entitlement + گیت API تیکت  
3. Admin CRUD پلن‌ها و تنظیمات billing  
4. Checkout + payment session + initiate درگاه (بدون business)  
5. Callback verify + فعال‌سازی اشتراک  
6. UI کاربر: اشتراک / خرید / صورت‌حساب / block states  
7. اعلان انقضا + job وضعیت  
8. آمار ادمین + نشان اپراتور  
9. Promo/trial در صورت باقی ماندن ظرفیت  

---

## ۱۷. جمع‌بندی تصمیم معماری

```text
[User] --checkout--> [Support Invoice + Payment Session]
                           |
                           v
              [System PaymentGateway]
                           |
                           v
                    [Bank / PSP Web]
                           |
                           v
              [Support Callback Verify]
                           |
                           v
              [User Subscription Active]
                           |
                           v
              [Ticket Entitlement Gate]
```

**کیف‌پول و کسب‌وکار در این گراف وجود ندارند.**  
تیکت‌ها همچنان متعلق به کاربرند؛ فقط حق استفاده از کانال پشتیبانی با اشتراک/سهمیه کنترل می‌شود.
