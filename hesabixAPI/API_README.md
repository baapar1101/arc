# Hesabix API Documentation

## 🔗 دسترسی به مستندات

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **OpenAPI Schema**: http://localhost:8000/openapi.json

## 🚀 شروع سریع

### 1. نصب و راه‌اندازی

```bash
# کلون کردن پروژه
git clone https://github.com/hesabix/api.git
cd hesabix-api

# نصب dependencies
pip install -r requirements.txt

# راه‌اندازی دیتابیس
alembic upgrade head

# اجرای سرور
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. اولین درخواست

```bash
# بررسی وضعیت API
curl http://localhost:8000/api/v1/health

# دریافت کپچا
curl -X POST http://localhost:8000/api/v1/auth/captcha

# ثبت‌نام
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali" \
  -d '{
    "first_name": "احمد",
    "last_name": "احمدی",
    "email": "ahmad@example.com",
    "password": "password123",
    "captcha_id": "captcha_id_from_previous_step",
    "captcha_code": "12345"
  }'
```

## 🔐 احراز هویت

### کلیدهای API

تمام endpoint های محافظت شده نیاز به کلید API دارند:

```bash
Authorization: Bearer sk_your_api_key_here
```

### نحوه دریافت کلید

1. **ثبت‌نام**: `POST /api/v1/auth/register`
2. **ورود**: `POST /api/v1/auth/login`
3. **کلیدهای شخصی**: `POST /api/v1/auth/api-keys`

### مثال کامل

```bash
# 1. دریافت کپچا
curl -X POST http://localhost:8000/api/v1/auth/captcha

# 2. ورود
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali" \
  -d '{
    "identifier": "user@example.com",
    "password": "password123",
    "captcha_id": "captcha_id_from_step_1",
    "captcha_code": "12345"
  }'

# 3. استفاده از API
curl -X GET http://localhost:8000/api/v1/auth/me \
  -H "Authorization: Bearer sk_1234567890abcdef" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali"
```

## 🌍 چندزبانه

### هدرهای زبان

```bash
Accept-Language: fa    # فارسی (پیش‌فرض)
Accept-Language: en    # انگلیسی
Accept-Language: fa-IR # فارسی ایران
Accept-Language: en-US # انگلیسی آمریکا
```

## 📅 تقویم

### هدرهای تقویم

```bash
X-Calendar-Type: jalali    # تقویم شمسی (پیش‌فرض)
X-Calendar-Type: gregorian # تقویم میلادی
```

## 🛡️ مجوزهای دسترسی

### مجوزهای اپلیکیشن

- `user_management`: مدیریت کاربران
- `superadmin`: دسترسی کامل
- `business_management`: مدیریت کسب و کارها
- `system_settings`: تنظیمات سیستم

### endpoint های محافظت شده

- `/api/v1/users/*` → نیاز به `user_management`
- `/api/v1/auth/me` → نیاز به احراز هویت
- `/api/v1/auth/api-keys/*` → نیاز به احراز هویت

## 📊 فرمت پاسخ‌ها

### پاسخ موفق

```json
{
  "success": true,
  "message": "عملیات با موفقیت انجام شد",
  "data": {
    // داده‌های اصلی
  }
}
```

### پاسخ خطا

```json
{
  "success": false,
  "message": "پیام خطا",
  "error_code": "ERROR_CODE",
  "details": {
    // جزئیات خطا
  }
}
```

### کدهای خطا

| کد | معنی |
|----|------|
| 200 | موفقیت |
| 400 | خطا در اعتبارسنجی |
| 401 | احراز هویت نشده |
| 403 | دسترسی غیرمجاز |
| 404 | منبع یافت نشد |
| 422 | خطا در اعتبارسنجی |
| 500 | خطای سرور |

## 🔒 امنیت

### کپچا

برای عملیات حساس:

```bash
# دریافت کپچا
curl -X POST http://localhost:8000/api/v1/auth/captcha

# استفاده در ثبت‌نام/ورود
{
  "captcha_id": "captcha_id_from_previous_step",
  "captcha_code": "12345"
}
```

### رمزگذاری

- رمزهای عبور: bcrypt
- کلیدهای API: SHA-256

## 📝 مثال‌های کاربردی

### مدیریت کاربران

```bash
# لیست کاربران (نیاز به مجوز usermanager)
curl -X GET http://localhost:8000/api/v1/users \
  -H "Authorization: Bearer sk_your_api_key" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali"

# جستجوی پیشرفته کاربران
curl -X POST http://localhost:8000/api/v1/users/search \
  -H "Authorization: Bearer sk_your_api_key" \
  -H "Content-Type: application/json" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali" \
  -d '{
    "take": 10,
    "skip": 0,
    "search": "احمد",
    "search_fields": ["first_name", "last_name", "email"],
    "filters": [
      {
        "property": "is_active",
        "operator": "=",
        "value": true
      }
    ]
  }'

# دریافت اطلاعات یک کاربر
curl -X GET http://localhost:8000/api/v1/users/1 \
  -H "Authorization: Bearer sk_your_api_key" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali"

# آمار کاربران
curl -X GET http://localhost:8000/api/v1/users/stats/summary \
  -H "Authorization: Bearer sk_your_api_key" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali"
```

### مدیریت معرفی‌ها

```bash
# آمار معرفی‌ها
curl -X GET "http://localhost:8000/api/v1/auth/referrals/stats?start=2024-01-01&end=2024-12-31" \
  -H "Authorization: Bearer sk_your_api_key" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali"

# لیست معرفی‌ها
curl -X POST http://localhost:8000/api/v1/auth/referrals/list \
  -H "Authorization: Bearer sk_your_api_key" \
  -H "Content-Type: application/json" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali" \
  -d '{
    "take": 10,
    "skip": 0,
    "sort_by": "created_at",
    "sort_desc": true
  }'

# خروجی PDF
curl -X POST http://localhost:8000/api/v1/auth/referrals/export/pdf \
  -H "Authorization: Bearer sk_your_api_key" \
  -H "Content-Type: application/json" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali" \
  -d '{
    "take": 100,
    "skip": 0
  }' \
  --output referrals.pdf

# خروجی Excel
curl -X POST http://localhost:8000/api/v1/auth/referrals/export/excel \
  -H "Authorization: Bearer sk_your_api_key" \
  -H "Content-Type: application/json" \
  -H "Accept-Language: fa" \
  -H "X-Calendar-Type: jalali" \
  -d '{
    "take": 100,
    "skip": 0
  }' \
  --output referrals.xlsx
```

## 🛠️ توسعه

### ساختار پروژه

```
hesabixAPI/
├── app/
│   ├── core/           # تنظیمات اصلی
│   ├── services/       # سرویس‌ها
│   └── main.py         # نقطه ورود
├── adapters/
│   ├── api/v1/         # API endpoints
│   └── db/             # دیتابیس
├── migrations/         # مهاجرت‌های دیتابیس
└── tests/             # تست‌ها
```

### اجرای تست‌ها

```bash
pytest tests/
```

### مهاجرت دیتابیس

```bash
# ایجاد migration جدید
alembic revision --autogenerate -m "description"

# اعمال migrations
alembic upgrade head

# بازگشت به migration قبلی
alembic downgrade -1
```

## 📞 پشتیبانی

- **ایمیل**: support@hesabix.com
- **مستندات**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **GitHub**: https://github.com/hesabix/api

## 📄 مجوز

این پروژه تحت مجوز MIT منتشر شده است. برای جزئیات بیشتر به فایل [LICENSE](LICENSE) مراجعه کنید.
