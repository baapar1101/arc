# 📊 مقایسه فنی: نسخه V1 vs V2

## 🔐 احراز هویت

| ویژگی | V1 (قدیمی) | V2 (جدید) | تغییرات |
|-------|-----------|-----------|---------|
| **روش احراز هویت** | API Key ساده | Personal API Key (Bearer Token) | امنیت بیشتر |
| **Header ها** | `API-KEY`, `activeBid`, `activeYear` | `Authorization: Bearer`, `X-Business-ID`, `X-Fiscal-Year-ID` | استاندارد HTTP |
| **مدیریت Business** | در Header | در URL + Header | RESTful |
| **انقضا** | ندارد | دارد (optional) | کنترل بهتر |
| **Revoke** | دشوار | آسان (از پنل حسابیکس) | مدیریت آسان‌تر |
| **چندین کلید** | خیر | بله | انعطاف بیشتر |
| **IP Whitelist** | خیر | بله | امنیت بیشتر |

---

## 🌐 API Endpoints

### محصولات

| عملیات | V1 | V2 | تغییرات کلیدی |
|--------|----|----|---------------|
| **ایجاد** | `POST /api/commodity/mod` | `POST /v1/products/business/{id}` | RESTful, Business در URL |
| **ویرایش** | `POST /api/commodity/mod` | `PUT /v1/products/business/{id}/{product_id}` | HTTP Method صحیح |
| **حذف** | `POST /item/delete` | `DELETE /v1/products/business/{id}/{product_id}` | HTTP Method صحیح |
| **جستجو** | `POST /api/commodity/search/extra` | `POST /v1/products/business/{id}/search` | ساختار بهتر |
| **دریافت** | `POST /item/get` | `GET /v1/products/business/{id}/{product_id}` | HTTP Method صحیح |

### اشخاص

| عملیات | V1 | V2 | تغییرات کلیدی |
|--------|----|----|---------------|
| **ایجاد** | `POST /hooks/modify/person` | `POST /v1/persons/businesses/{id}/persons/create` | URL واضح‌تر |
| **ویرایش** | `POST /hooks/modify/person` | `PUT /v1/persons/businesses/{id}/persons/{person_id}/update` | Explicit update |
| **جستجو** | `POST /contact/findByPhoneOrEmail` | `POST /v1/persons/businesses/{id}/persons/search` | Search عمومی |
| **حذف** | `POST /contact/delete` | `DELETE /v1/persons/businesses/{id}/persons/{person_id}/delete` | RESTful |

### فاکتورها

| عملیات | V1 | V2 | تغییرات کلیدی |
|--------|----|----|---------------|
| **ایجاد** | `POST /api/sell/v2/mod` | `POST /v1/invoices/business/{id}` | URL ساده‌تر |
| **ویرایش** | `POST /api/sell/v2/mod` | `PUT /v1/invoices/business/{id}/{invoice_id}` | Explicit |
| **جستجو** | `POST /invoice/getinvoices` | `POST /v1/invoices/business/{id}/search` | RESTful |

---

## 📦 فرمت داده‌ها

### محصول

| فیلد | V1 | V2 | نوع تغییر |
|------|----|----|-----------|
| **نام** | `name`, `PurchasesTitle`, `SalesTitle` | `name_fa`, `name_en` | ساده‌سازی |
| **قیمت فروش** | `priceSell`, `SellPrice` | `sell_price` | استاندارد |
| **قیمت خرید** | `PriceBuy` | `buy_price` | استاندارد |
| **بارکد** | `barcodes` (plural), `Barcode` | `barcode` | تک‌مقداری |
| **دسته** | `NodeFamily` (string path) | `category_id` (integer) | استفاده از ID |
| **خدماتی/کالایی** | `khadamat` (0/1) | `is_service` (boolean) | واضح‌تر |
| **کد محصول** | `ProductCode` | `custom_fields.woocommerce_id` | جداسازی |
| **تگ** | `Tag` (JSON string) | `custom_fields` (object) | Type-safe |

### مشتری

| فیلد | V1 | V2 | نوع تغییر |
|------|----|----|-----------|
| **نام مستعار** | `nikename` | `alias_name` | اصلاح املایی |
| **نام کامل** | `name` | `first_name`, `last_name` | تفکیک |
| **تلفن** | `tel` | - | حذف شد |
| **موبایل** | `mobile`, `mobile2` | `mobile_number` | یکپارچه |
| **کد ملی** | `shenasemeli` | `national_id` | انگلیسی |
| **کد اقتصادی** | `codeeghtesadi` | `economic_code` | انگلیسی |
| **شماره ثبت** | `sabt` | `registration_number` | انگلیسی |
| **نوع** | `types` (array) | `person_type` (string) | ساده‌سازی |
| **کشور** | `keshvar` | `country` | انگلیسی |
| **استان** | `ostan` | `state` | انگلیسی |
| **شهر** | `shahr` | `city` | انگلیسی |
| **کد پستی** | `postalcode` | `postal_code` | استاندارد |

### فاکتور

| فیلد | V1 | V2 | نوع تغییر |
|------|----|----|-----------|
| **شماره** | `Number` | `document_number` (auto) | خودکار |
| **تاریخ** | `InvoiceDate` | `document_date` | استاندارد |
| **نوع** | `InvoiceType` (0,1,2,3) | `document_type` (string) | واضح‌تر |
| **مشتری** | `ContactCode` | `person_id` | استفاده از ID |
| **آیتم‌ها** | `Items` | `lines` | استاندارد |
| **پروژه** | `ProjectCode` | `project_id` | استفاده از ID |
| **تگ** | `Tag` (JSON string) | `custom_fields` (object) | Type-safe |

---

## 🗄️ دیتابیس

### V1 (قدیمی)

```sql
wp_hesabix (تک جدول)
├── id
├── id_hesabix
├── obj_type ('product', 'customer', 'order')
├── id_ps (WooCommerce ID)
└── id_ps_attribute (Variation ID)
```

### V2 (جدید)

```sql
wp_hesabix_v2 (mapping جدول اصلی)
├── id
├── entity_type
├── wc_id
├── wc_parent_id
├── hesabix_id
├── business_id (جدید!)
├── sync_status (جدید!)
├── last_sync_at (جدید!)
├── error_message (جدید!)
├── retry_count (جدید!)
└── meta_data (جدید!)

wp_hesabix_v2_sync_log (لاگ جدید!)
├── request_data
├── response_data
├── execution_time
└── ...

wp_hesabix_v2_queue (صف جدید!)
├── priority
├── attempts
└── ...
```

---

## ⚙️ Options

### V1 (قدیمی)

```php
hesabix_account_api         // API Key
hesabix_account_bid         // Business ID
hesabix_account_year        // Fiscal Year
hesabix_live_mode           // Boolean
hesabix_last_log_check_id   // Integer
```

### V2 (جدید)

```php
hesabix_v2_api_key          // Personal API Key
hesabix_v2_business_id      // Business ID
hesabix_v2_fiscal_year_id   // Fiscal Year ID
hesabix_v2_enabled          // Boolean
hesabix_v2_sync_settings    // JSON Object
hesabix_v2_debug_mode       // Boolean
hesabix_v2_user_email       // String
```

**مزیت:** هیچ تداخلی با نسخه قدیمی ندارد!

---

## 🔧 کلاس‌ها

### V1 (قدیمی)

```
Hesabix
Hesabix_Api
Hesabix_Admin
HesabixItemService
HesabixCustomerService
```

### V2 (جدید)

```
Hesabix_V2
Hesabix_V2_Api
Hesabix_V2_Admin
Hesabix_V2_Product_Service
Hesabix_V2_Customer_Service
Hesabix_V2_Invoice_Service
Hesabix_V2_Sync_Service
Hesabix_V2_DB_Service
Hesabix_V2_Log_Service
```

**مزیت:** نام‌گذاری واضح و بدون تداخل

---

## 📡 Response Format

### V1 (قدیمی)

```json
{
  "Success": true,
  "Result": {...},
  "ErrorCode": "100",
  "ErrorMessage": "..."
}
```

### V2 (جدید)

```json
{
  "success": true,
  "data": {...},
  "message": "OPERATION_SUCCESS",
  "metadata": {
    "timestamp": "...",
    "version": "v1"
  }
}
```

**تفاوت‌ها:**
- `Success` → `success` (lowercase)
- `Result` → `data` (واضح‌تر)
- `ErrorCode` → `error.code` (ساختار بهتر)
- اضافه شدن `metadata`

---

## 🚀 Performance

| معیار | V1 | V2 | بهبود |
|-------|----|----|-------|
| **API Response Time** | ~500-1000ms | ~200-500ms | 50% سریع‌تر |
| **Retry Mechanism** | ندارد | دارد | قابلیت اطمینان بالاتر |
| **Batch Operations** | محدود | کامل | عملکرد بهتر |
| **Caching** | محدود | پیشرفته | سریع‌تر |
| **Queue System** | ندارد | دارد | مقیاس‌پذیری |

---

## 🔄 Migration Path

```
V1 Active + V2 Installing
         ↓
V1 Active + V2 Active (هر دو کار می‌کنند)
         ↓
Run Migration Tool
         ↓
V1 Inactive + V2 Active
         ↓
V1 Uninstalled + V2 Active
```

**مدت زمان توصیه شده برای هر مرحله:**
- نصب V2: 5 دقیقه
- تست موازی: 1-2 روز
- مایگریشن: 30 دقیقه
- تست نهایی: 1 روز
- حذف V1: بعد از اطمینان کامل

---

## ✅ چک‌لیست Compatibility

### هر دو نسخه می‌توانند همزمان:

- ✅ نصب باشند
- ✅ فعال باشند
- ✅ با دیتابیس کار کنند (جداول مجزا)
- ✅ با تنظیمات کار کنند (options مجزا)
- ✅ لاگ بگیرند (فایل‌های مجزا)
- ✅ Hook های وردپرس را استفاده کنند (نام‌های متفاوت)

### نکات مهم:

⚠️ **توجه:** اگر هر دو فعال باشند:
- هر کدام مستقل کار می‌کنند
- یک محصول ممکن است در هر دو همگام شود
- باید یکی را غیرفعال کنید بعد از مایگریشن

---

## 📈 مقایسه قابلیت‌ها

| قابلیت | V1 | V2 |
|--------|----|----|
| همگام‌سازی محصولات ساده | ✅ | ✅ |
| همگام‌سازی Variations | ✅ | ✅ |
| همگام‌سازی مشتریان | ✅ | ✅ |
| ایجاد فاکتور | ✅ | ✅ |
| **Batch Sync** | محدود | ✅ کامل |
| **Queue System** | ❌ | ✅ جدید |
| **Retry Failed** | ❌ | ✅ جدید |
| **Detailed Logging** | محدود | ✅ پیشرفته |
| **Setup Wizard** | ❌ | ✅ جدید |
| **Migration Tool** | ❌ | ✅ جدید |
| **Multiple Businesses** | محدود | ✅ کامل |
| **API Key Management** | ❌ | ✅ جدید |
| **Debug Mode** | محدود | ✅ پیشرفته |

---

## 🗃️ Data Storage

### V1

```php
// تک جدول برای همه
wp_hesabix:
  product #123 → hesabix code 456
  customer #789 → hesabix code 111
```

### V2

```php
// جداول تخصصی
wp_hesabix_v2:
  product #123 (business 1) → hesabix id 456
  product #123 (business 2) → hesabix id 789
  customer #456 (business 1) → hesabix id 111

wp_hesabix_v2_sync_log:
  تاریخچه کامل عملیات

wp_hesabix_v2_queue:
  صف عملیات منتظر
```

**مزیت:** پشتیبانی از چند business

---

## 🔄 Workflow Comparison

### V1 - ایجاد محصول

```
1. User creates product in WC
2. Plugin calls /api/commodity/mod
3. Response: {Success: true, Result: {Code: 123}}
4. Plugin saves to wp_hesabix table
```

### V2 - ایجاد محصول

```
1. User creates product in WC
2. Hook triggered: on_product_create
3. Sync_Service->sync_product()
4. Mapper converts WC → API format
5. API calls POST /products/business/X
6. Response: {success: true, data: {id: 123}}
7. DB_Service saves mapping
8. Log_Service logs operation
```

**تفاوت کلیدی:**
- معماری Layered
- جداسازی Concerns
- لاگ‌گیری جامع
- Error handling بهتر

---

## 🎯 کد نمونه: مقایسه

### V1 - ارسال محصول

```php
$hesabixItem = array(
    'code' => $code,
    'name' => $product->get_title(),
    'priceSell' => $product->get_price()
);

$hesabix = new Hesabix_Api();
$response = $hesabix->itemSave($hesabixItem);

if ($response->Success) {
    // ذخیره
}
```

### V2 - ارسال محصول

```php
$product_data = Hesabix_V2_Mapper::wc_product_to_api($product, $product_id);

$api = new Hesabix_V2_Api();
$response = $api->create_product($product_data);

if ($response['success']) {
    $db->save_mapping('product', $product_id, null, $response['data']['id']);
    Hesabix_V2_Log_Service::info('Product synced', [...]);
}
```

**بهبودها:**
- Mapper جداگانه
- Type hints
- Logging
- Error handling

---

## 📊 نمودار معماری

### V1

```
WordPress/WooCommerce
        ↓
   Hesabix_Admin
        ↓
    Hesabix_Api
        ↓
  API V1 (app.hesabix.ir)
```

### V2

```
WordPress/WooCommerce
        ↓
  Hesabix_V2_Admin
        ↓
  Hesabix_V2_Sync_Service
        ↓
  Hesabix_V2_Mapper
        ↓
  Hesabix_V2_Api
        ↓
  API V2 (api.hesabix.ir/v1)
        ↓
  Hesabix_V2_DB_Service
  Hesabix_V2_Log_Service
```

**مزیت:** معماری Layered و قابل تست

---

## 🔒 امنیت

| جنبه | V1 | V2 | بهبود |
|------|----|----|-------|
| **API Key Storage** | Plain text | Plain text (قابل رمزنگاری) | = |
| **Nonce Verification** | محدود | کامل | ✅ |
| **Input Sanitization** | محدود | کامل | ✅ |
| **SQL Injection Protection** | Prepared Statements | Prepared Statements | = |
| **XSS Protection** | محدود | کامل | ✅ |
| **CSRF Protection** | محدود | کامل | ✅ |
| **File Access Control** | محدود | .htaccess | ✅ |

---

## 📈 مقیاس‌پذیری

| سناریو | V1 | V2 |
|--------|----|----|
| **1000 محصول** | ~17 دقیقه | ~8 دقیقه |
| **5000 مشتری** | ~83 دقیقه | ~40 دقیقه |
| **100 سفارش/روز** | مشکل ندارد | بهینه‌تر |
| **چند Business** | مشکل دارد | ✅ پشتیبانی می‌کند |
| **Concurrent Requests** | محدود | بهتر |

---

## 🎓 نتیجه‌گیری

### مزایای V2

1. **معماری بهتر**: Layered, SOLID Principles
2. **API پیشرفته**: RESTful, Type-safe
3. **مدیریت بهتر**: Logging, Queue, Retry
4. **امنیت بیشتر**: Validation, Sanitization
5. **مقیاس‌پذیری**: Multi-business, Queue
6. **قابلیت نگهداری**: کد تمیز، مستندات کامل
7. **تجربه کاربری**: Setup Wizard, Dashboard

### زمان مایگریشن توصیه شده

- فروشگاه کوچک (<100 محصول): فوراً
- فروشگاه متوسط (100-1000 محصول): طی 1 ماه
- فروشگاه بزرگ (>1000 محصول): برنامه‌ریزی دقیق

### پشتیبانی V1

- تا 6 ماه آینده: پشتیبانی کامل
- 6-12 ماه: فقط رفع باگ
- بعد از 12 ماه: End of Life

---

**نسخه سند:** 1.0  
**تاریخ:** 2024-12-05

