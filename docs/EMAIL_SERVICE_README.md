# سرویس ایمیل حسابیکس

## نمای کلی

سرویس ایمیل حسابیکس یک سیستم داخلی برای ارسال ایمیل است که توسعه‌دهندگان می‌توانند به راحتی از آن استفاده کنند. این سرویس از SMTP استفاده می‌کند و تنظیمات اتصال در دیتابیس ذخیره می‌شود.

## ویژگی‌ها

- ✅ ارسال ایمیل با SMTP
- ✅ پشتیبانی از TLS و SSL
- ✅ ذخیره تنظیمات در دیتابیس
- ✅ مدیریت چندین پیکربندی
- ✅ تست اتصال
- ✅ رابط کاربری برای مدیریت
- ✅ پشتیبانی از چندزبانه (فارسی/انگلیسی)
- ✅ امنیت و رمزگذاری

## ساختار فایل‌ها

### Backend

```
hesabixAPI/
├── adapters/db/models/email_config.py          # مدل دیتابیس
├── adapters/db/repositories/email_config_repository.py  # Repository
├── adapters/api/v1/schema_models/email.py      # Schema models
├── adapters/api/v1/admin/email_config.py       # API endpoints
├── app/services/email_service.py               # سرویس اصلی
└── locales/
    ├── fa/LC_MESSAGES/messages.po              # ترجمه‌های فارسی
    └── en/LC_MESSAGES/messages.po              # ترجمه‌های انگلیسی
```

### Frontend

```
hesabixUI/hesabix_ui/lib/
├── models/email_models.dart                    # مدل‌های Flutter
├── services/email_service.dart                 # سرویس Flutter
├── pages/admin/email_settings_page.dart        # صفحه مدیریت
└── l10n/
    ├── app_fa.arb                              # ترجمه‌های فارسی
    └── app_en.arb                              # ترجمه‌های انگلیسی
```

## استفاده برای توسعه‌دهندگان

### 1. ارسال ایمیل ساده

```dart
import 'package:hesabix_ui/services/email_service.dart';

final emailService = EmailService();

// ارسال ایمیل سفارشی
await emailService.sendCustomEmail(
  to: 'user@example.com',
  subject: 'عنوان ایمیل',
  body: 'متن ایمیل',
  htmlBody: '<h1>عنوان</h1><p>متن</p>',
);
```

### 2. ارسال ایمیل خوش‌آمدگویی

```dart
await emailService.sendWelcomeEmail(
  'user@example.com',
  'نام کاربر',
);
```

### 3. ارسال ایمیل بازیابی رمز عبور

```dart
await emailService.sendPasswordResetEmail(
  'user@example.com',
  'https://example.com/reset?token=abc123',
);
```

### 4. ارسال ایمیل اطلاع‌رسانی

```dart
await emailService.sendNotificationEmail(
  'user@example.com',
  'عنوان اطلاع‌رسانی',
  'پیام اطلاع‌رسانی',
);
```

## مدیریت تنظیمات

### 1. دسترسی به صفحه تنظیمات

1. وارد بخش "تنظیمات سیستم" شوید
2. روی "تنظیمات ایمیل" کلیک کنید

### 2. افزودن پیکربندی جدید

1. فرم را پر کنید:
   - **نام پیکربندی**: نام منحصر به فرد
   - **میزبان SMTP**: آدرس سرور SMTP
   - **پورت SMTP**: پورت سرور (معمولاً 587 یا 465)
   - **نام کاربری**: نام کاربری SMTP
   - **رمز عبور**: رمز عبور SMTP
   - **ایمیل فرستنده**: آدرس ایمیل فرستنده
   - **نام فرستنده**: نام نمایشی فرستنده
   - **TLS/SSL**: نوع رمزگذاری

2. روی "ذخیره پیکربندی" کلیک کنید

### 3. تست اتصال

1. پیکربندی مورد نظر را انتخاب کنید
2. روی "تست اتصال" کلیک کنید
3. وضعیت اتصال نمایش داده می‌شود

### 4. ارسال ایمیل تست

1. پیکربندی مورد نظر را انتخاب کنید
2. روی "ارسال ایمیل تست" کلیک کنید
3. ایمیل تست به آدرس "ایمیل فرستنده" ارسال می‌شود

## API Endpoints

### مدیریت پیکربندی‌ها

- `GET /api/v1/admin/email/configs` - دریافت لیست پیکربندی‌ها
- `GET /api/v1/admin/email/configs/{id}` - دریافت پیکربندی خاص
- `POST /api/v1/admin/email/configs` - ایجاد پیکربندی جدید
- `PUT /api/v1/admin/email/configs/{id}` - بروزرسانی پیکربندی
- `DELETE /api/v1/admin/email/configs/{id}` - حذف پیکربندی

### تست و ارسال

- `POST /api/v1/admin/email/configs/{id}/test` - تست اتصال
- `POST /api/v1/admin/email/configs/{id}/activate` - فعال‌سازی پیکربندی
- `POST /api/v1/admin/email/send` - ارسال ایمیل

## امنیت

- رمزهای عبور SMTP در دیتابیس ذخیره می‌شوند (باید رمزگذاری شوند)
- تمام endpoint ها نیاز به احراز هویت دارند
- تست اتصال قبل از فعال‌سازی انجام می‌شود

## چندزبانه

### فارسی
- تمام متن‌ها به فارسی ترجمه شده‌اند
- پشتیبانی از RTL
- فرمت تاریخ شمسی

### انگلیسی
- پشتیبانی کامل از انگلیسی
- فرمت تاریخ میلادی

## عیب‌یابی

### مشکلات رایج

1. **خطا در اتصال SMTP**
   - بررسی صحت آدرس میزبان و پورت
   - بررسی نام کاربری و رمز عبور
   - بررسی تنظیمات TLS/SSL

2. **ایمیل ارسال نمی‌شود**
   - بررسی پیکربندی فعال
   - تست اتصال
   - بررسی لاگ‌های سرور

3. **خطا در رابط کاربری**
   - بررسی اتصال به API
   - بررسی مجوزهای کاربر
   - بررسی ترجمه‌ها

### لاگ‌ها

- لاگ‌های ارسال ایمیل در console نمایش داده می‌شوند
- خطاهای SMTP در response API نمایش داده می‌شوند

## توسعه آینده

### ویژگی‌های پیشنهادی

- [ ] سیستم قالب‌های ایمیل
- [ ] صف ارسال ایمیل
- [ ] آمار ارسال
- [ ] لاگ‌گیری کامل
- [ ] رمزگذاری رمزهای عبور
- [ ] پشتیبانی از چندین ارائه‌دهنده SMTP
- [ ] تست خودکار اتصال

### بهبودهای فنی

- [ ] Cache کردن پیکربندی‌ها
- [ ] Connection pooling
- [ ] Retry mechanism
- [ ] Rate limiting
- [ ] Monitoring و alerting

## پشتیبانی

برای گزارش مشکلات یا درخواست ویژگی‌های جدید، لطفاً با تیم توسعه تماس بگیرید.

---

**نسخه**: 1.0.0  
**تاریخ**: 2025-01-17  
**نویسنده**: تیم توسعه حسابیکس
