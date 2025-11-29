# راهنمای راه‌اندازی سرویس‌های استعلامات زحل

این مستندات راهنمای کامل برای راه‌اندازی و استفاده از سرویس‌های استعلامات زحل است.

## 📋 فهرست مطالب

1. [پیش‌نیازها](#پیش‌نیازها)
2. [نصب و راه‌اندازی](#نصب-و-راه‌اندازی)
3. [تنظیمات اولیه](#تنظیمات-اولیه)
4. [استفاده از API](#استفاده-از-api)
5. [مدیریت سرویس‌ها](#مدیریت-سرویس‌ها)

## 🔧 پیش‌نیازها

- اجرای Migration برای ایجاد جداول `zohal_services` و `zohal_service_logs`
- وجود ارز IRR در سیستم
- وجود حساب کیف پول برای کسب‌وکارها
- کلید API زحل

## 🚀 نصب و راه‌اندازی

### مرحله 1: اجرای Migration

ابتدا باید جداول مورد نیاز را ایجاد کنید:

```bash
cd /var/www/ark/hesabixAPI
alembic upgrade head
```

یا اگر از migration دستی استفاده می‌کنید:

```bash
python3 -m alembic upgrade head
```

### مرحله 2: ایجاد حساب‌های حسابداری

حساب هزینه سرویس‌های استعلامات (70903) باید ایجاد شود:

```bash
cd /var/www/ark/hesabixAPI
python3 scripts/ensure_zohal_accounts.py
```

این اسکریپت حساب `70903` (هزینه سرویس‌های استعلامات) را ایجاد می‌کند.

### مرحله 3: بارگذاری سرویس‌ها از فایل JSON

سرویس‌ها را از فایل `docs/zohal.json` بارگذاری کنید:

```bash
cd /var/www/ark/hesabixAPI
python3 scripts/load_zohal_services.py
```

این اسکریپت:
- تمام سرویس‌های موجود در فایل JSON را می‌خواند
- سرویس‌های جدید را ایجاد می‌کند
- سرویس‌های موجود را به‌روزرسانی می‌کند
- قیمت پیش‌فرض: 1000 تومان (IRR)

## ⚙️ تنظیمات اولیه

### تنظیم API Key زحل

برای استفاده از سرویس‌های زحل، باید کلید API را تنظیم کنید:

**Endpoint:** `PUT /api/v1/admin/zohal/settings`

**Body:**
```json
{
  "api_key": "your-zohal-api-key-here",
  "base_url": "https://service.zohal.io/api/v0",
  "low_balance_threshold": 10000
}
```

**پارامترها:**
- `api_key`: کلید API زحل (الزامی)
- `base_url`: آدرس پایه API زحل (پیش‌فرض: `https://service.zohal.io/api/v0`)
- `low_balance_threshold`: آستانه موجودی کم برای اخطار (پیش‌فرض: 10000 تومان)

### تنظیم قیمت سرویس‌ها

برای هر سرویس می‌توانید قیمت جداگانه تعیین کنید:

**Endpoint:** `PUT /api/v1/admin/zohal/services/{service_id}/price`

**Body:**
```json
{
  "base_price": 1500,
  "currency_id": 1
}
```

## 📡 استفاده از API

### برای کاربران کسب‌وکار

#### 1. دریافت لیست سرویس‌های فعال

**Endpoint:** `GET /api/v1/businesses/{business_id}/zohal/services`

**Response:**
```json
{
  "success": true,
  "data": {
    "services": [
      {
        "id": 1,
        "service_code": "card_inquiry",
        "service_name": "استعلام نام صاحب کارت",
        "service_category": "بانکی",
        "base_price": 1000,
        "currency_code": "IRR",
        "request_schema": {...}
      }
    ],
    "wallet_balance": 50000,
    "wallet_currency": "IRR",
    "low_balance_warning": false,
    "low_balance_threshold": 10000
  }
}
```

#### 2. اجرای استعلام

**Endpoint:** `POST /api/v1/businesses/{business_id}/zohal/inquiry/{service_code}`

**Body:**
```json
{
  "card_number": "6362XXXXXXX11"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "success": true,
    "service_name": "استعلام نام صاحب کارت",
    "result": {
      "result": 1,
      "response_body": {
        "data": {
          "name": "نام صاحب کارت"
        },
        "message": "موفق"
      }
    },
    "amount_charged": 1000,
    "remaining_balance": 49000,
    "low_balance_warning": false,
    "log_id": 123
  }
}
```

#### 3. مشاهده تاریخچه

**Endpoint:** `GET /api/v1/businesses/{business_id}/zohal/logs`

**Query Parameters:**
- `service_id` (optional): فیلتر بر اساس سرویس
- `start_date` (optional): تاریخ شروع (ISO format)
- `end_date` (optional): تاریخ پایان (ISO format)
- `limit` (optional): تعداد نتایج (پیش‌فرض: 50)
- `skip` (optional): تعداد نتایج برای رد شدن (پیش‌فرض: 0)

### برای مدیر سیستم

#### 1. مدیریت سرویس‌ها

**لیست سرویس‌ها:**
```
GET /api/v1/admin/zohal/services
```

**فعال/غیرفعال کردن:**
```
PUT /api/v1/admin/zohal/services/{service_id}/toggle
Body: { "is_active": true }
```

**تغییر قیمت:**
```
PUT /api/v1/admin/zohal/services/{service_id}/price
Body: { "base_price": 1500, "currency_id": 1 }
```

#### 2. آمار و گزارش‌ها

**Endpoint:** `GET /api/v1/admin/zohal/statistics`

**Query Parameters:**
- `start_date` (optional): تاریخ شروع
- `end_date` (optional): تاریخ پایان
- `business_id` (optional): فیلتر بر اساس کسب‌وکار
- `service_id` (optional): فیلتر بر اساس سرویس

**Response:**
```json
{
  "success": true,
  "data": {
    "total_requests": 1500,
    "successful_requests": 1450,
    "failed_requests": 50,
    "total_revenue": 1500000,
    "by_service": [
      {
        "service_id": 1,
        "service_name": "استعلام نام صاحب کارت",
        "request_count": 500,
        "revenue": 500000
      }
    ],
    "by_business": [...],
    "daily_usage": [...]
  }
}
```

## 💰 سند حسابداری

هنگامی که یک استعلام موفق انجام می‌شود، به صورت خودکار یک سند حسابداری ایجاد می‌شود:

**نوع سند:** `payment`

**ردیف‌های حسابداری:**
- **بدهکار:** حساب `70903` (هزینه سرویس‌های استعلامات) - مبلغ: قیمت سرویس
- **بستانکار:** حساب `10205` (کیف پول) - مبلغ: قیمت سرویس

## ⚠️ نکات مهم

1. **موجودی کیف پول:** قبل از اجرای استعلام، موجودی کیف پول بررسی می‌شود. اگر موجودی کافی نباشد، خطا برمی‌گردد.

2. **هزینه کسر:** هزینه فقط در صورت موفقیت استعلام کسر می‌شود. اگر استعلام ناموفق باشد، هزینه کسر نمی‌شود.

3. **اخطار موجودی کم:** اگر موجودی کیف پول کمتر از آستانه تعیین شده باشد، در پاسخ لیست سرویس‌ها `low_balance_warning: true` برمی‌گردد.

4. **لاگ‌ها:** تمام درخواست‌ها (موفق یا ناموفق) در جدول `zohal_service_logs` ثبت می‌شوند.

## 🔍 عیب‌یابی

### مشکل: سرویس‌ها بارگذاری نمی‌شوند

- بررسی کنید که فایل `docs/zohal.json` موجود است
- بررسی کنید که ارز IRR در سیستم وجود دارد
- لاگ‌های خطا را بررسی کنید

### مشکل: API Key کار نمی‌کند

- بررسی کنید که API Key در تنظیمات ذخیره شده است
- بررسی کنید که API Key معتبر است
- بررسی کنید که آدرس `base_url` درست است

### مشکل: موجودی کافی نیست

- بررسی کنید که موجودی کیف پول کافی است
- بررسی کنید که قیمت سرویس درست تنظیم شده است

## 📞 پشتیبانی

در صورت بروز مشکل، لطفاً با تیم فنی تماس بگیرید.

