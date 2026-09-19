# سناریوی فاز ۰ — زیرساخت چندارزی، ارائه‌دهندگان نرخ، و اسنپ‌شات مرکزی

**تاریخ:** ۲۰۲۶-۰۷-۱۸  
**وضعیت:** در حال پیاده‌سازی  
**وابستگی:** [MULTI_CURRENCY_IMPLEMENTATION_GUIDE.md](./MULTI_CURRENCY_IMPLEMENTATION_GUIDE.md)

---

## ۱. هدف این فاز

1. **Gate چندارزی:** کسب‌وکار تک‌ارزی هیچ UI/API چندارزی جدیدی را نبیند (`is_multi_currency`).
2. **مدیریت ارائه‌دهندگان نرخ در ادمین کل:** ثبت providerهایی مثل BRS API (`brsapi.ir`)، مثقال (جایگاه آینده)، و کلید API رمزنگاری‌شده.
3. **واکشی متمرکز دوره‌ای:** حداکثر یک درخواست دوره‌ای به سرویس خارجی (پیش‌فرض هر ۱۵ دقیقه) — نه به‌ازای هر کسب‌وکار.
4. **اسنپ‌شات سراسری:** نرخ‌ها در جداول مرکزی ذخیره شوند؛ کسب‌وکار فقط از همین اسنپ‌شات بخواند.
5. **ثبت سریع تسعیر:** کاربر چندارزی بتواند با یک کلیک از نرخ اسنپ‌شات، ردیف `business_currency_rates` بسازد.

---

## ۲. یافتهٔ کاوش brsapi.ir

| مورد | مقدار |
|------|--------|
| Endpoint رایگان | `GET https://Api.BrsApi.ir/Market/Gold_Currency.php?key={API_KEY}` |
| نسخه Pro | نیاز به خرید؛ فعلاً استفاده نمی‌شود |
| محدودیت اعلام‌شده کاربر | حدود ۱۰۰ درخواست / ۵ دقیقه (در پاسخ Pro فیلد `usage_5min_limit` دیده شد) |
| واحد قیمت ارز | **تومان** (`unit: "تومان"`) |
| نمادهای نمونه | `USD`, `EUR`, `AED`, `GBP`, `JPY` (JPY = قیمت یکصد ین), `USDT_IRT`, … |
| ساختار پاسخ | `{ "gold": [...], "currency": [ { symbol, name, price, unit, time_unix, ... } ] }` |

**تبدیل به ارز پایه حسابیکس (معمولاً IRR):**  
`rate_irr = price_toman × 10`  
یعنی ۱ دلار ≈ `193200` تومان ≈ `1,932,000` ریال.

**سیاست درخواست:** فقط worker مرکزی هر N دقیقه یک بار صدا بزند. کسب‌وکارها هرگز مستقیم به brsapi درخواست نزنند.

---

## ۳. معماری

```text
[Admin UI] ──manage──► fx_rate_providers (کلید رمزنگاری‌شده)
                              │
                              ▼
              [Background loop ~15min]
                              │  1 request / interval
                              ▼
                         brsapi.ir
                              │
                              ▼
                   fx_global_rates (اسنپ‌شات)
                              │
          ┌───────────────────┴───────────────────┐
          ▼                                       ▼
   Business UI (MC only)                   Admin test/fetch now
   «ثبت سریع تسعیر از نرخ روز»
          │
          ▼
   business_currency_rates (نرخ اختصاصی کسب‌وکار)
```

---

## ۴. مدل داده

### ۴.۱ `fx_rate_providers`
| ستون | توضیح |
|------|--------|
| `code` | یکتا: `brsapi`, `mesghal`, … |
| `display_name` | نام نمایشی |
| `api_base_url` | پایه URL |
| `api_key_encrypted` | Fernet |
| `is_active` | فعال برای واکشی دوره‌ای |
| `fetch_interval_seconds` | پیش‌فرض ۹۰۰ (۱۵ دقیقه) |
| `config_json` | quote_unit=`IRT`, symbol_map، divisorها (مثلاً JPY÷100) |
| `last_fetch_at`, `last_fetch_status`, `last_fetch_error`, `last_fetch_http_status` | وضعیت |

### ۴.۲ `fx_global_rates`
آخرین نرخ به‌ازای `(provider_id, symbol)`:

| ستون | توضیح |
|------|--------|
| `symbol` | نماد خام provider (مثلاً `USD`) |
| `currency_code` | ISO نگاشت‌شده (مثلاً `USD`) |
| `price_quote` | قیمت خام |
| `quote_unit` | `IRT` / `IRR` / … |
| `price_irr` | نرمال‌شده به ریال (۱ واحد ارز = چند ریال) |
| `name_fa`, `name_en` | برچسب |
| `source_time` | زمان اعلام‌شده توسط provider |
| `fetched_at` | زمان دریافت ما |
| `raw_json` | نمونهٔ خام برای دیباگ |

---

## ۵. APIها

### ادمین (`system_settings`)
- `GET /api/v1/admin/fx-providers`
- `PUT /api/v1/admin/fx-providers/{code}` — ایجاد/ویرایش (api_key خالی = حفظ قبلی)
- `POST /api/v1/admin/fx-providers/{code}/test` — یک درخواست تست (با احتیاط rate-limit)
- `POST /api/v1/admin/fx-providers/{code}/fetch-now` — واکشی فوری و ذخیره اسنپ‌شات
- ادمین: `GET /api/v1/admin/fx-providers/global-rates` — مشاهده اسنپ‌شات مرکزی

### کسب‌وکار (فقط اگر `is_multi_currency`)
- فیلد `is_multi_currency` روی پاسخ کسب‌وکار
- `GET /api/v1/businesses/{id}/fx-global-rates/latest` — نرخ‌های مرتبط با ارزهای فرعی کسب‌وکار از اسنپ‌شات
- `POST /api/v1/businesses/{id}/currency-rates/apply-from-global`  
  body: `{ "items": [ { "currency_id" یا "currency_code", "symbol?" } ], "note?" }`  
  → ساخت ردیف در `business_currency_rates` از `price_irr` (یا تبدیل به ارز پایه اگر پایه ≠ IRR)

---

## ۶. UI

| محل | رفتار |
|-----|--------|
| سیستم‌تنظیمات → مالی | کارت «ارائه‌دهندگان نرخ ارز» |
| صفحه ادمین providers | لیست، ویرایش کلید، فعال/غیرفعال، بازه، تست، واکشی فوری، وضعیت آخرین sync |
| `AuthStore.isMultiCurrency` | از `is_multi_currency` |
| منوی تسعیر / صفحه نرخ‌ها | فقط وقتی MC=ON |
| دکمه «ثبت از نرخ روز» | دیالوگ انتخاب ارزهای فرعی که در اسنپ‌شات موجودند → apply |

---

## ۷. معیار پذیرش

- [x] تک‌ارزی: بدون منوی تسعیر جدید و بدون endpoint کاربردی MC
- [x] ادمین می‌تواند BRS را با کلید تنظیم و تست کند
- [x] Worker هر ۱۵ دقیقه (قابل تنظیم) حداکثر یک fetch به ازای provider فعال می‌زند
- [x] کسب‌وکار چندارزی نرخ را از اسنپ‌شات می‌خواند؛ با «ثبت سریع» در `business_currency_rates` می‌نویسد
- [x] کلید API در ریپو commit نمی‌شود

> یادداشت: کلید BRS در دیتابیس (رمزنگاری‌شده) ذخیره شد. در لحظه تست از این سرور، `Api.BrsApi.ir` گاهی Connection reset می‌دهد؛ از UI ادمین «واکشی اکنون» را وقتی شبکه پایدار است اجرا کنید.

---

## ۸. تصمیم‌های این فاز

| موضوع | تصمیم |
|--------|--------|
| D2 واحد | اسنپ‌شات مرکزی `price_irr` دارد؛ تبدیل به پایه کسب‌وکار در apply |
| Provider اول | `brsapi` (رایگان Gold_Currency) |
| مثقال | ردیف غیرفعال/placeholder تا پیاده‌سازی بعدی |
| کلید | رمزنگاری DB + fallback اختیاری env `HESABIX_FX_BRSAPI_API_KEY` |

---

## ۹. خارج از این فاز

- نوار ابزار نرخ در shell کسب‌وکار (فاز ۱)
- پرداخت/انتقال چندارزی
- API مثقال واقعی
- Pro endpoint برس
