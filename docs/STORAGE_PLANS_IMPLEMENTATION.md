# 📦 سیستم فضای ذخیره‌سازی (Storage Plans System)

## 📌 مقدمه

سیستم فضای ذخیره‌سازی به کاربران امکان الصاق فایل‌های مختلف (عکس، فیلم، اسناد و ...) به اسناد حسابداری و سایر بخش‌های نرم‌افزار را می‌دهد. این سیستم با پلن‌های قابل تنظیم و ادغام با کیف پول کار می‌کند.

## 🎯 ویژگی‌های اصلی

1. **پلن‌های قابل تنظیم**: مدیر می‌تواند پلن‌های مختلف با دوره‌های مختلف (ماهانه، سالانه، مادام‌العمر) ایجاد کند
2. **چند پلن همزمان**: کاربران می‌توانند چندین پلن را همزمان فعال کنند (مثلاً بسته 1 گیگ 3 ماهه و بسته 7 گیگ یک ساله)
3. **استفاده اضافی**: در صورت تجاوز از محدودیت، صورتحساب فوری با تمایل کاربر ایجاد می‌شود
4. **ادغام با کیف پول**: تمام صورتحساب‌ها از کیف پول پرداخت می‌شوند
5. **حذف خودکار**: بعد از انقضای اشتراک و تمام شدن grace period، فایل‌ها به صورت خودکار حذف می‌شوند
6. **دانلود ZIP**: کاربران می‌توانند تمام فایل‌های کسب‌وکار خود را به صورت ZIP دانلود کنند

## 📊 ساختار دیتابیس

### جداول جدید

1. **storage_plans**: پلن‌های ذخیره‌سازی
2. **business_storage_subscriptions**: اشتراک‌های کسب‌وکار
3. **storage_invoices**: صورتحساب‌های ذخیره‌سازی
4. **storage_usage_transactions**: تراکنش‌های استفاده

### تغییرات در file_storage

- `business_id`: شناسه کسب‌وکار مالک فایل
- `subscription_id`: پلن فعال در زمان آپلود
- `is_marked_for_deletion`: علامت برای حذف خودکار
- `marked_for_deletion_at`: زمان علامت‌گذاری

## 🔧 سرویس‌ها

### storage_plan_service.py
- `create_storage_plan()`: ایجاد پلن جدید
- `update_storage_plan()`: ویرایش پلن
- `get_storage_plan()`: دریافت جزئیات پلن
- `list_storage_plans()`: لیست پلن‌ها
- `delete_storage_plan()`: حذف/غیرفعال کردن پلن

### storage_subscription_service.py
- `subscribe_to_plan()`: اشتراک به یک پلن
- `get_active_subscriptions()`: دریافت اشتراک‌های فعال
- `calculate_total_storage_limit()`: محاسبه کل محدودیت
- `calculate_storage_usage()`: محاسبه استفاده فعلی
- `check_storage_limit()`: بررسی محدودیت
- `renew_subscription()`: تمدید اشتراک
- `cancel_subscription()`: لغو اشتراک
- `check_expired_subscriptions()`: بررسی انقضای اشتراک‌ها

### storage_invoice_service.py
- `create_subscription_invoice()`: ایجاد صورتحساب اشتراک
- `create_over_usage_invoice()`: ایجاد صورتحساب استفاده اضافی
- `create_renewal_invoice()`: ایجاد صورتحساب تمدید
- `pay_storage_invoice_from_wallet()`: پرداخت از کیف پول
- `list_storage_invoices()`: لیست صورتحساب‌ها
- `get_storage_invoice()`: دریافت جزئیات صورتحساب

### storage_cleanup_service.py
- `mark_files_for_deletion()`: علامت‌گذاری فایل‌ها برای حذف
- `delete_marked_files()`: حذف فایل‌های علامت‌گذاری شده
- `cleanup_expired_files()`: اجرای کامل فرآیند پاک‌سازی

### storage_export_service.py
- `export_business_files_as_zip()`: ایجاد فایل ZIP
- `get_export_info()`: دریافت اطلاعات فایل‌های قابل دانلود

## 🌐 API Endpoints

### Admin Endpoints

#### `POST /api/v1/admin/storage-plans`
ایجاد پلن جدید

**Body:**
```json
{
  "name": "پلن پایه",
  "code": "basic_1gb_3m",
  "storage_limit_gb": 1.0,
  "period": "monthly",
  "period_months": 3,
  "price": 50000,
  "price_per_gb": 10000,
  "is_free": false,
  "currency_id": 1,
  "description": "پلن پایه 1 گیگابایت 3 ماهه",
  "grace_period_days": 30
}
```

#### `PUT /api/v1/admin/storage-plans/{plan_id}`
ویرایش پلن

#### `GET /api/v1/admin/storage-plans`
لیست پلن‌ها

#### `GET /api/v1/admin/storage-plans/{plan_id}`
جزئیات پلن

#### `DELETE /api/v1/admin/storage-plans/{plan_id}`
حذف/غیرفعال کردن پلن

### Business Endpoints

#### `GET /api/v1/business/{business_id}/storage/subscriptions`
لیست اشتراک‌های فعال

#### `POST /api/v1/business/{business_id}/storage/subscribe`
اشتراک به یک پلن

**Body:**
```json
{
  "plan_id": 1,
  "auto_renew": false
}
```

#### `PUT /api/v1/business/{business_id}/storage/subscription/{subscription_id}/renew`
تمدید اشتراک

#### `DELETE /api/v1/business/{business_id}/storage/subscription/{subscription_id}`
لغو اشتراک

#### `GET /api/v1/business/{business_id}/storage/usage`
آمار استفاده

#### `GET /api/v1/business/{business_id}/storage/plans`
لیست پلن‌های قابل اشتراک

#### `GET /api/v1/business/{business_id}/storage/invoices`
لیست صورتحساب‌ها

#### `POST /api/v1/business/{business_id}/storage/invoices/{invoice_id}/pay`
پرداخت صورتحساب از کیف پول

#### `POST /api/v1/business/{business_id}/storage/pay-over-usage`
پرداخت برای استفاده اضافی

**Body:**
```json
{
  "over_usage_gb": 0.5,
  "file_size_bytes": 536870912
}
```

#### `GET /api/v1/business/{business_id}/storage/export-zip`
دانلود ZIP تمام فایل‌ها

**Query Parameters:**
- `module_context` (optional): فیلتر بر اساس module
- `from_date` (optional): از تاریخ
- `to_date` (optional): تا تاریخ

#### `GET /api/v1/business/{business_id}/storage/export-info`
اطلاعات فایل‌های قابل دانلود

## 🔄 Background Jobs

### storage_cleanup_loop
هر 24 ساعت یکبار اجرا می‌شود:
1. بررسی اشتراک‌های منقضی شده
2. علامت‌گذاری فایل‌ها برای حذف
3. حذف فایل‌های علامت‌گذاری شده (بعد از 7 روز)

### storage_subscription_check_loop
هر 6 ساعت یکبار اجرا می‌شود:
1. بررسی اشتراک‌های منقضی شده
2. به‌روزرسانی وضعیت اشتراک‌ها

## 📝 Migration

برای اجرای migration:

```bash
cd hesabixAPI
alembic upgrade head
```

Migration شامل:
- ایجاد جداول جدید
- اضافه کردن فیلدهای جدید به `file_storage`
- ایجاد پلن رایگان پیش‌فرض (1 GB، lifetime)

## 🔗 یکپارچه‌سازی با سیستم موجود

### File Storage Service
`file_storage_service.py` به‌روزرسانی شده تا:
- قبل از آپلود: بررسی محدودیت ذخیره‌سازی
- بعد از آپلود: ثبت `business_id` و `subscription_id`
- ثبت تراکنش استفاده در `storage_usage_transactions`

### Wallet Service
تراکنش‌های ذخیره‌سازی در کیف پول نمایش داده می‌شوند:
- `storage_subscription`: پرداخت اشتراک
- `storage_over_usage`: پرداخت استفاده اضافی
- `storage_renewal`: تمدید اشتراک

## 🎨 Frontend (Flutter)

### صفحات مورد نیاز

1. **Admin:**
   - `storage_plans_admin_page.dart`: مدیریت پلن‌ها

2. **Business:**
   - `storage_subscription_page.dart`: مدیریت اشتراک
   - `storage_plans_page.dart`: لیست پلن‌ها برای اشتراک
   - `storage_invoices_page.dart`: صورتحساب‌ها
   - `storage_files_page.dart`: مدیریت فایل‌ها
   - `storage_export_page.dart`: دانلود ZIP

### ویجت‌ها

- `storage_usage_widget.dart`: نمایش استفاده
- `storage_limit_warning_dialog.dart`: هشدار محدودیت
- `storage_over_usage_dialog.dart`: دیالوگ استفاده اضافی

## ⚠️ نکات مهم

1. **محاسبه حجم**: تبدیل بایت به گیگابایت با دقت 6 رقم اعشار
2. **محدودیت فایل**: حداکثر حجم هر فایل (مثلاً 500MB)
3. **Grace Period**: قابل تنظیم در هر پلن (پیش‌فرض: 30 روز)
4. **چند پلن همزمان**: محدودیت‌ها جمع می‌شوند
5. **استفاده اضافی**: صورتحساب فوری با تمایل کاربر

## 🚀 مراحل بعدی

1. ✅ ایجاد مدل‌ها و migration
2. ✅ ایجاد سرویس‌ها
3. ✅ ایجاد API endpoints
4. ✅ تنظیم background jobs
5. ⏳ پیاده‌سازی Frontend
6. ⏳ تست کامل سیستم

