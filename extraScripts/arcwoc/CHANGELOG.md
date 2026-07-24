# Changelog

تمام تغییرات مهم در این پروژه در این فایل مستند می‌شود.

## [4.7.2] - 2026-07-25

### Fixed
- همگام‌سازی خودکار محصولات متغیر: واریانت‌ها به‌صورت کالاهای جداگانه ارسال می‌شوند؛ والد دیگر به‌عنوان محصول ساده ساخته نمی‌شود
- هوک‌های ایجاد/به‌روزرسانی واریانت (`woocommerce_new/update_product_variation`) برای همگام‌سازی تکی واریانت
- آرگومان‌های اشتباه lazy-sync واریانت هنگام ساخت فاکتور از سفارش
- باگ `$cref` تعریف‌نشده در مسیر bulk-upsert کالا که نگاشت پاسخ API را خراب می‌کرد
- حذف نگاشت‌های واریانت هنگام حذف محصول والد یا خود واریانت

### Changed
- `sync_product` برای محصول متغیر همهٔ فرزندان را گسترش می‌دهد؛ محصول متغیر خالی دیگر به‌عنوان ساده ارسال نمی‌شود
- پاک‌سازی نگاشت محلی یتیم «والد متغیر به‌عنوان ساده» هنگام همگام‌سازی صحیح واریانت‌ها (با ثبت در رجیستری برای پاک‌سازی بعدی)

### Added
- ابزار پاک‌سازی امن کالاهای یتیم والد متغیر در صفحهٔ محصولات (اسکن، پیش‌نمایش، حذف استفاده‌نشده / غیرفعال‌سازی در-استفاده)
- رجیستری محلی `hesabix_v2_orphan_parent_products` برای نگهداشت شناسهٔ کالاهای یتیم پس از قطع نگاشت
- API حسابیکس: `GET /products/business/{id}/{product_id}/usage-check`
- تقویت گارد حذف کالا برای اسناد هزینه/درآمد کالا و قطعات تعمیر

## [4.7.1] - 2026-07-21

### Fixed
- جلوگیری از همگام‌سازی محصولات پیش‌نویس (از جمله کپی/داپلیکیت منتشرنشده) به حسابیکس
- رفع فریز شدن نام محصول پس از کپی→تغییرنام→انتشار در سیاست حسابداری‌محور (نام اکنون در به‌روزرسانی همگام می‌شود)

### Changed
- سیاست حسابداری‌محور: هویت فروشگاهی (`name`) از ووکامرس همگام می‌شود؛ قیمت خرید و داده‌های مالی همچنان محافظت می‌شوند
- همگام‌سازی خودکار و دسته‌ای فقط وضعیت‌های مجاز (پیش‌فرض: `publish`) را پوشش می‌دهند

### Added
- فیلتر واقعی `hesabix_v2_should_sync_product` و `hesabix_v2_syncable_product_statuses`
- لاگ رد شدن همگام‌سازی به‌خاطر وضعیت/فیلتر و فیلدهای ارسال‌شده در به‌روزرسانی

## [4.7.0] - 2026-07-19

### Fixed
- رفع پاک شدن قیمت خرید و سایر داده‌های حسابداری هنگام به‌روزرسانی محصول از ووکامرس
- جلوگیری از بازنویسی `is_active` در به‌روزرسانی‌های خودکار

### Added
- سیاست‌های همگام‌سازی محصول: ایمپورت اولیه، حسابداری‌محور (پیش‌فرض)، فروشگاه زنده، پیشرفته
- تنظیمات جزئی‌تر برای نام، توضیحات و بارکد در حالت پیشرفته
- کلاس `Hesabix_V2_Product_Sync_Payload` برای تفکیک CREATE/UPDATE

### Changed
- قیمت خرید (`base_purchase_price`) دیگر از ووکامرس به حسابیکس ارسال نمی‌شود
- فیلتر `hesabix_v2_product_data` در مسیر sync واقعاً اعمال می‌شود

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

