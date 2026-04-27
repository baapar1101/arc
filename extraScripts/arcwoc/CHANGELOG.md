# Changelog

تمام تغییرات مهم در این پروژه در این فایل مستند می‌شود.

## [2.0.0] - 2024-12-05

### 🎉 Added - موارد جدید

#### معماری
- ✨ ساختار کاملاً جدید با معماری Layered
- ✨ جداسازی کامل از نسخه V1 (جداول، options، کلاس‌ها)
- ✨ پشتیبانی از نصب همزمان با نسخه قدیمی

#### احراز هویت
- ✨ استفاده از Personal API Keys به جای API Key ساده
- ✨ پشتیبانی از Bearer Token Authentication
- ✨ Setup Wizard برای راه‌اندازی آسان و سریع
- ✨ مدیریت چندین API Key
- ✨ IP Whitelist Support

#### API Integration
- ✨ اتصال کامل به API V2 حسابیکس
- ✨ پشتیبانی از تمام RESTful endpoints جدید
- ✨ Headers استاندارد (Authorization, X-Business-ID, X-Fiscal-Year-ID)
- ✨ Error handling پیشرفته
- ✨ Timeout management

#### Database
- ✨ جدول `wp_hesabix_v2` با ساختار بهبود یافته
- ✨ جدول `wp_hesabix_v2_sync_log` برای لاگ‌گیری
- ✨ جدول `wp_hesabix_v2_queue` برای صف پردازش
- ✨ پشتیبانی از چندین Business در یک نصب
- ✨ ذخیره metadata برای هر mapping
- ✨ ردیابی sync_status و retry_count

#### همگام‌سازی
- ✨ Sync Service جدید با معماری تمیز
- ✨ Batch/Bulk sync برای عملیات گروهی
- ✨ Queue System برای پردازش background
- ✨ Retry mechanism با exponential backoff
- ✨ پشتیبانی کامل از Product Variations
- ✨ همگام‌سازی خودکار محصولات، مشتریان و سفارشات

#### Data Mapping
- ✨ Mapper Classes تخصصی
- ✨ تبدیل خودکار فرمت V1 به V2
- ✨ Validation پیشرفته
- ✨ Custom Fields برای داده‌های اضافی
- ✨ پشتیبانی از Guest Customers

#### لاگ‌گیری
- ✨ Log Service پیشرفته با 4 سطح (info, warning, error, debug)
- ✨ لاگ فایلی روزانه
- ✨ لاگ دیتابیس برای query سریع
- ✨ Debug Mode کامل
- ✨ پاکسازی خودکار لاگ‌های قدیمی
- ✨ ذخیره request/response برای debug
- ✨ محاسبه execution time

#### رابط کاربری
- ✨ Dashboard جدید با آمار لحظه‌ای
- ✨ صفحه تنظیمات پیشرفته
- ✨ صفحه همگام‌سازی با امکان bulk operations
- ✨ Logs Viewer با فیلتر
- ✨ Migration Tool
- ✨ RTL و فارسی کامل

#### مستندات
- ✨ README.md جامع
- ✨ INSTALLATION.md با راهنمای گام به گام
- ✨ DEVELOPER_GUIDE.md برای توسعه‌دهندگان
- ✨ TECHNICAL_COMPARISON.md
- ✨ Comments کامل در کد

#### امنیت
- ✨ Nonce verification در تمام فرم‌ها
- ✨ Input sanitization کامل
- ✨ Output escaping
- ✨ Prepared statements
- ✨ محافظت از لاگ‌ها با .htaccess
- ✨ CSRF Protection

#### عملکرد
- ✨ بهینه‌سازی Query ها
- ✨ استفاده از Indexes در جداول
- ✨ Lazy loading
- ✨ Caching (آماده برای پیاده‌سازی)

### 🔄 Changed - تغییرات

#### API Calls
- 🔄 تغییر از `POST /api/commodity/mod` به `POST /v1/products/business/{id}`
- 🔄 تغییر از `POST /hooks/modify/person` به `POST /v1/persons/businesses/{id}/persons/create`
- 🔄 تغییر از `POST /api/sell/v2/mod` به `POST /v1/invoices/business/{id}`

#### Data Format
- 🔄 `name` → `name_fa`, `name_en`
- 🔄 `priceSell` → `sell_price`
- 🔄 `barcodes` → `barcode`
- 🔄 `NodeFamily` → `category_id`
- 🔄 `Tag` → `custom_fields`
- 🔄 `ContactCode` → `person_id`
- 🔄 Response format: `{Success, Result}` → `{success, data}`

#### Options
- 🔄 `hesabix_*` → `hesabix_v2_*`
- 🔄 ساختار options از flat به nested (JSON)

#### کلاس‌ها
- 🔄 نام‌گذاری: `Hesabix_*` → `Hesabix_V2_*`

### ❌ Removed - موارد حذف شده

- ❌ وابستگی به API V1
- ❌ استفاده از API-KEY header ساده
- ❌ فیلدهای فارسی در API (`shenasemeli`, `codeeghtesadi`, ...)

### 🐛 Fixed - رفع مشکلات

- 🐛 مشکل همگام‌سازی همزمان چند محصول
- 🐛 خطای timeout در bulk operations
- 🐛 مشکل character encoding در نام‌های فارسی
- 🐛 مشکل variations بدون SKU

### 🔒 Security

- 🔒 تمام ورودی‌ها sanitize می‌شوند
- 🔒 استفاده از Prepared Statements
- 🔒 Nonce verification در همه جا
- 🔒 محافظت از لاگ‌ها

---

## [1.0.4] - قبلی (نسخه قدیمی)

آخرین نسخه V1 قبل از شروع توسعه V2

---

## 🔮 Planned - برنامه‌های آینده

### [2.1.0] - Q1 2025

- [ ] Webhook Support برای همگام‌سازی دوطرفه
- [ ] Real-time sync با WebSocket
- [ ] پشتیبانی از WooCommerce Subscriptions
- [ ] پشتیبانی از Multi-Currency
- [ ] گزارش‌های پیشرفته
- [ ] Export/Import تنظیمات

### [2.2.0] - Q2 2025

- [ ] WP-CLI Commands
- [ ] REST API برای اتصال اپلیکیشن‌های شخص ثالث
- [ ] GraphQL Support
- [ ] Advanced Caching
- [ ] Redis Support

### [3.0.0] - Q3 2025

- [ ] بازنویسی کامل با PHP 8.2+
- [ ] استفاده از Composer
- [ ] Unit Tests کامل
- [ ] CI/CD Pipeline
- [ ] Docker Support

---

## 🤝 مشارکت

برای مشارکت در توسعه:

1. Fork کنید
2. Feature branch ایجاد کنید
3. Commit های واضح بزنید
4. Pull Request ارسال کنید

## 📄 Versioning

این پروژه از [Semantic Versioning](https://semver.org/) استفاده می‌کند:

- **MAJOR**: تغییرات breaking
- **MINOR**: قابلیت‌های جدید backward-compatible
- **PATCH**: رفع باگ backward-compatible

---

**تاریخ به‌روزرسانی:** 2024-12-05  
**نگهدارنده:** Hesabix Team

