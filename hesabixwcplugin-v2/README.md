# Hesabix V2: WooCommerce Plugin

نسخه جدید افزونه اتصال ووکامرس به حسابیکس با پشتیبانی از API نسخه 2

## 🎯 ویژگی‌ها

### احراز هویت پیشرفته
- ✅ استفاده از Personal API Keys (به جای JWT Token)
- ✅ مدیریت چندین کلید API با دسترسی‌های مختلف
- ✅ IP Whitelist برای امنیت بیشتر
- ✅ تاریخ انقضای اختیاری برای کلیدها

### همگام‌سازی هوشمند
- ✅ همگام‌سازی خودکار محصولات (ساده و متغیر)
- ✅ همگام‌سازی خودکار مشتریان
- ✅ ایجاد خودکار فاکتور در حسابیکس
- ✅ صف پردازش برای sync های بزرگ
- ✅ Retry mechanism برای خطاها

### ساختار دیتابیس مجزا
- ✅ جداول مستقل با prefix `hesabix_v2`
- ✅ Options مجزا با prefix `hesabix_v2_`
- ✅ قابلیت نصب همزمان با نسخه قدیمی

### لاگ‌گیری پیشرفته
- ✅ لاگ فایل روزانه
- ✅ لاگ دیتابیس برای query سریع
- ✅ حالت Debug برای توسعه‌دهندگان
- ✅ پاک‌سازی خودکار لاگ‌های قدیمی

## 📋 نیازمندی‌ها

- WordPress 5.8+
- WooCommerce 6.0+
- PHP 7.4+
- MySQL 5.7+ یا MariaDB 10.2+

## 🚀 نصب و راه‌اندازی

### 1. نصب افزونه

```bash
# آپلود فایل zip از طریق WordPress Admin
# یا کپی مستقیم پوشه به wp-content/plugins/
```

### 2. فعال‌سازی

افزونه را از بخش Plugins فعال کنید. به طور خودکار Setup Wizard باز می‌شود.

### 3. پیکربندی اولیه (Setup Wizard)

**مرحله 1: ورود به حساب حسابیکس**
- ایمیل و رمز عبور خود را وارد کنید
- سیستم به حسابیکس متصل می‌شود

**مرحله 2: انتخاب کسب‌وکار**
- از لیست کسب‌وکارهای خود یکی را انتخاب کنید
- سال مالی فعال را انتخاب کنید

**مرحله 3: ایجاد API Key**
- سیستم به طور خودکار یک Personal API Key ایجاد می‌کند
- این کلید برای تمام عملیات استفاده می‌شود

**مرحله 4: تنظیمات همگام‌سازی**
- انتخاب موارد برای همگام‌سازی خودکار
- تنظیم رفتارهای پیش‌فرض

## 🗄️ ساختار دیتابیس

### جدول اصلی: `wp_hesabix_v2`

```sql
- id: شناسه یکتا
- entity_type: نوع موجودیت (product, customer, order, variation)
- wc_id: ID در ووکامرس
- wc_parent_id: ID والد (برای variations)
- hesabix_id: ID در حسابیکس
- business_id: شناسه کسب‌وکار
- sync_status: وضعیت (synced, pending, error)
- last_sync_at: زمان آخرین همگام‌سازی
- error_message: پیام خطا (در صورت وجود)
- retry_count: تعداد تلاش مجدد
- meta_data: داده‌های اضافی (JSON)
```

### جدول لاگ: `wp_hesabix_v2_sync_log`

```sql
- id: شناسه یکتا
- entity_type: نوع موجودیت
- entity_id: شناسه موجودیت
- action: عملیات (create, update, delete)
- status: وضعیت (success, error)
- request_data: داده‌های درخواست (JSON)
- response_data: داده‌های پاسخ (JSON)
- execution_time: زمان اجرا (ثانیه)
```

### جدول صف: `wp_hesabix_v2_queue`

```sql
- id: شناسه یکتا
- entity_type: نوع موجودیت
- entity_id: شناسه موجودیت
- action: عملیات
- priority: اولویت (1-10)
- payload: داده‌ها (JSON)
- status: وضعیت (pending, processing, completed, failed)
- attempts: تعداد تلاش
```

## 🔧 تنظیمات WordPress Options

```php
hesabix_v2_api_key              // Personal API Key
hesabix_v2_business_id          // Business ID
hesabix_v2_fiscal_year_id       // Fiscal Year ID
hesabix_v2_enabled              // فعال/غیرفعال
hesabix_v2_debug_mode           // حالت Debug
hesabix_v2_api_base_url         // Base URL
hesabix_v2_sync_settings        // تنظیمات همگام‌سازی (JSON)
hesabix_v2_setup_completed      // وضعیت راه‌اندازی
```

## 📡 API Endpoints استفاده شده

### Authentication
- `POST /v1/auth/login` - ورود و دریافت session token
- `GET /v1/auth/me` - اطلاعات کاربر
- `POST /v1/auth/api-keys` - ایجاد Personal API Key

### Products
- `POST /v1/products/business/{id}` - ایجاد محصول
- `PUT /v1/products/business/{id}/{product_id}` - ویرایش محصول
- `GET /v1/products/business/{id}/{product_id}` - دریافت محصول
- `POST /v1/products/business/{id}/search` - جستجوی محصولات
- `DELETE /v1/products/business/{id}/{product_id}` - حذف محصول

### Persons (Customers)
- `POST /v1/persons/businesses/{id}/persons/create` - ایجاد شخص
- `PUT /v1/persons/businesses/{id}/persons/{person_id}/update` - ویرایش
- `POST /v1/persons/businesses/{id}/persons/search` - جستجو

### Invoices
- `POST /v1/invoices/business/{id}` - ایجاد فاکتور
- `PUT /v1/invoices/business/{id}/{invoice_id}` - ویرایش فاکتور
- `POST /v1/invoices/business/{id}/search` - جستجوی فاکتورها

## 🔄 تبدیل داده‌ها (Data Mapping)

### محصول ووکامرس → حسابیکس

```php
WooCommerce → Hesabix V2
----------------------------------------
get_title()           → name_fa
get_price()           → sell_price
get_sku()             → barcode
is_virtual()          → is_service
managing_stock()      → track_inventory
get_category_ids()    → category_id
```

### مشتری ووکامرس → حسابیکس

```php
WooCommerce → Hesabix V2
----------------------------------------
get_first_name()      → first_name
get_last_name()       → last_name
get_billing_phone()   → mobile_number
get_email()           → email
get_billing_address() → address
```

### سفارش ووکامرس → فاکتور حسابیکس

```php
WooCommerce → Hesabix V2
----------------------------------------
get_order_number()    → custom_fields.order_number
get_items()           → lines[]
get_shipping_total()  → lines[] (shipping product)
get_customer_id()     → person_id (via mapping)
```

## 🔒 امنیت

### API Key Storage
- API Key در دیتابیس رمزنگاری نمی‌شود (قابل رمزنگاری در آینده)
- دسترسی محدود به admin
- قابلیت revoke در هر زمان

### File Permissions
- لاگ‌ها با .htaccess محافظت می‌شوند
- دسترسی مستقیم غیرممکن است

### Validation
- اعتبارسنجی تمام ورودی‌ها
- Sanitization داده‌های خروجی
- استفاده از Prepared Statements

## 🐛 Debug Mode

برای فعال‌سازی حالت Debug:

```php
update_option('hesabix_v2_debug_mode', true);
```

در این حالت:
- تمام API Requests لاگ می‌شوند
- تمام API Responses لاگ می‌شوند
- جزئیات بیشتری در لاگ‌ها ذخیره می‌شود

## 📊 مانیتورینگ

### مشاهده آمار
```php
$db_service = new Hesabix_V2_DB_Service();
$stats = $db_service->get_sync_stats();
```

### مشاهده لاگ‌ها
```php
$logs = Hesabix_V2_Log_Service::get_recent_logs(100, 'error');
```

## 🔄 مایگریشن از نسخه قدیمی

افزونه ابزار مایگریشن دارد که:
1. داده‌های نسخه قدیمی را می‌خواند
2. به فرمت جدید تبدیل می‌کند
3. در حسابیکس V2 ایجاد می‌کند
4. mapping های جدید را ذخیره می‌کند

⚠️ **توجه:** هر دو افزونه می‌توانند همزمان نصب باشند.

## 👨‍💻 توسعه‌دهندگان

### Hooks

#### Actions
```php
// Before product sync
do_action('hesabix_v2_before_product_sync', $product_id);

// After product sync
do_action('hesabix_v2_after_product_sync', $product_id, $hesabix_id);

// Before order sync
do_action('hesabix_v2_before_order_sync', $order_id);

// After order sync
do_action('hesabix_v2_after_order_sync', $order_id, $invoice_id);
```

#### Filters
```php
// Modify product data before sending
add_filter('hesabix_v2_product_data', function($data, $product) {
    // Modify $data
    return $data;
}, 10, 2);

// Modify customer data
add_filter('hesabix_v2_customer_data', function($data, $customer) {
    // Modify $data
    return $data;
}, 10, 2);
```

## 📝 Changelog

### Version 2.0.0 (2024-12-05)
- 🎉 نسخه اولیه با پشتیبانی کامل از API V2
- ✨ Personal API Keys
- ✨ Setup Wizard
- ✨ Sync Queue System
- ✨ Advanced Logging
- ✨ جداول مستقل از نسخه قدیمی

## 🤝 مشارکت

برای گزارش باگ یا درخواست ویژگی جدید به [hesabix.ir/support](https://hesabix.ir/support) مراجعه کنید.

## 📄 License

GPL-3.0+

## 🙏 Credits

**Developer:** Hesabix Team  
**Website:** [hesabix.ir](https://hesabix.ir)

