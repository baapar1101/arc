# 👨‍💻 راهنمای توسعه‌دهندگان Hesabix V2

## 🏗️ معماری افزونه

### کلاس‌های اصلی

```
Hesabix_V2
├── Hesabix_V2_Loader          # مدیریت hooks
├── Hesabix_V2_i18n            # چندزبانه‌سازی
├── Hesabix_V2_Admin           # مدیریت admin area
│
├── Hesabix_V2_Api             # ارتباط با API
├── Hesabix_V2_Mapper          # تبدیل داده‌ها
├── Hesabix_V2_Validation      # اعتبارسنجی
│
└── Services
    ├── Hesabix_V2_Sync_Service      # همگام‌سازی
    ├── Hesabix_V2_Product_Service   # مدیریت محصولات
    ├── Hesabix_V2_Customer_Service  # مدیریت مشتریان
    ├── Hesabix_V2_Invoice_Service   # مدیریت فاکتورها
    ├── Hesabix_V2_DB_Service        # دیتابیس
    └── Hesabix_V2_Log_Service       # لاگ‌گیری
```

---

## 🔌 Hooks & Filters

### Actions

#### محصولات

```php
// قبل از همگام‌سازی محصول
do_action('hesabix_v2_before_product_sync', $product_id, $variation_id);

// بعد از همگام‌سازی محصول
do_action('hesabix_v2_after_product_sync', $product_id, $variation_id, $hesabix_id);

// قبل از حذف محصول از حسابیکس
do_action('hesabix_v2_before_product_delete', $product_id, $hesabix_id);

// بعد از حذف محصول
do_action('hesabix_v2_after_product_delete', $product_id);
```

#### مشتریان

```php
// قبل از همگام‌سازی مشتری
do_action('hesabix_v2_before_customer_sync', $customer_id);

// بعد از همگام‌سازی مشتری
do_action('hesabix_v2_after_customer_sync', $customer_id, $person_id);
```

#### سفارشات

```php
// قبل از ایجاد فاکتور
do_action('hesabix_v2_before_order_sync', $order_id);

// بعد از ایجاد فاکتور
do_action('hesabix_v2_after_order_sync', $order_id, $invoice_id);

// هنگام تغییر وضعیت سفارش
do_action('hesabix_v2_order_status_changed', $order_id, $old_status, $new_status);
```

### Filters

#### تغییر داده‌های محصول

```php
add_filter('hesabix_v2_product_data', function($data, $product, $wc_id) {
    // تغییر نام محصول
    $data['name_fa'] = 'پیشوند - ' . $data['name_fa'];
    
    // اضافه کردن فیلد سفارشی
    $data['custom_fields']['my_custom_field'] = 'my_value';
    
    return $data;
}, 10, 3);
```

#### تغییر داده‌های مشتری

```php
add_filter('hesabix_v2_customer_data', function($data, $customer, $order) {
    // اضافه کردن فیلد اضافی
    if ($order) {
        $data['custom_fields']['order_count'] = $order->get_customer()->get_order_count();
    }
    
    return $data;
}, 10, 3);
```

#### تغییر داده‌های فاکتور

```php
add_filter('hesabix_v2_invoice_data', function($data, $order) {
    // اضافه کردن توضیحات
    $data['notes'] .= ' - سفارش آنلاین';
    
    // تغییر تاریخ
    // $data['document_date'] = '2024-01-01';
    
    return $data;
}, 10, 2);
```

#### حداکثر اختلاف گرد کردن (جمع خطوط در مقابل مبلغ نهایی سفارش)

اگر اختلاف رُند شده بین جمع `line_total` خطوط و `order_total` ووکامرس از این حد بیشتر باشد، افزونه خودکار اصلاح نمی‌کند و فقط هشدار می‌نویسد (پیش‌فرض: `2` واحد پول).

```php
add_filter('hesabix_v2_invoice_rounding_tolerance', function($tolerance) {
    return 5;
});
```

#### حداکثر اصلاح سربرگ (gross − discount + tax = مبلغ نهایی سفارش)

برای هم‌خوانی بدهکار مشتری در فاکتور با مبلغ سند دریافت، اگر اختلاف گرد کردن بین این فرمول و `order_total` کم باشد، به **`gross`** سربرگ در حد چند واحد پول اضافه/کم می‌شود (پیش‌فرض تحمل `5`).

```php
add_filter('hesabix_v2_invoice_header_totals_tolerance', function($t) {
    return 10;
});
```

#### آرایهٔ پرداخت‌های همراه فاکتور (قبل از ارسال به API)

```php
add_filter('hesabix_v2_invoice_payments', function($payments, $order) {
    return $payments;
}, 10, 2);
```

#### تغییر URL پایه API

```php
add_filter('hesabix_v2_api_base_url', function($url) {
    // استفاده از سرور تست
    return 'https://test-api.hesabix.ir/v1';
});
```

---

## 🗄️ کار با دیتابیس

### ذخیره Mapping جدید

```php
$db = new Hesabix_V2_DB_Service();

$db->save_mapping(
    'product',           // entity_type
    $wc_product_id,     // wc_id
    null,               // wc_parent_id (برای variations)
    $hesabix_id,        // hesabix_id
    'product',          // hesabix_type
    array(              // meta_data
        'synced_at' => current_time('mysql'),
        'custom_field' => 'value'
    )
);
```

### دریافت Mapping

```php
$db = new Hesabix_V2_DB_Service();

// دریافت Hesabix ID
$hesabix_id = $db->get_hesabix_id('product', $wc_product_id);

// دریافت WooCommerce ID
$wc_data = $db->get_wc_id('product', $hesabix_id);
// Returns: ['wc_id' => 123, 'wc_parent_id' => null]

// دریافت mapping کامل
$mapping = $db->get_mapping('product', $wc_product_id);
```

### به‌روزرسانی وضعیت

```php
$db->update_sync_status(
    'product',
    $wc_product_id,
    null,
    'error',
    'پیام خطا'
);
```

---

## 📡 کار با API

### ارسال Request سفارشی

```php
$api = new Hesabix_V2_Api();

// دریافت لیست حساب‌ها (مثال)
$result = $api->request(
    'POST',
    "/accounts/business/{$business_id}/list",
    array(
        'take' => 100,
        'skip' => 0
    )
);

if (isset($result['success']) && $result['success']) {
    $accounts = $result['data']['items'];
    // کار با accounts
}
```

### دریافت اطلاعات کاربر

```php
$api = new Hesabix_V2_Api();
$user_info = $api->get_me();

if ($user_info['success']) {
    $email = $user_info['data']['email'];
    $name = $user_info['data']['first_name'];
}
```

---

## 📝 لاگ‌گیری

### نوشتن لاگ

```php
// Info
Hesabix_V2_Log_Service::info('عملیات انجام شد', array(
    'entity_type' => 'product',
    'entity_id' => 123,
    'details' => 'جزئیات بیشتر'
));

// Warning
Hesabix_V2_Log_Service::warning('هشدار', array(
    'message' => 'این یک هشدار است'
));

// Error
Hesabix_V2_Log_Service::error('خطا رخ داد', array(
    'entity_type' => 'order',
    'entity_id' => 456,
    'error' => 'پیام خطا',
    'request' => $request_data,
    'response' => $response_data
));

// Debug (فقط در debug mode)
Hesabix_V2_Log_Service::debug('اطلاعات debug', array(
    'data' => $debug_data
));
```

### خواندن لاگ‌ها

```php
// دریافت 100 لاگ اخیر
$logs = Hesabix_V2_Log_Service::get_recent_logs(100);

// دریافت فقط خطاها
$errors = Hesabix_V2_Log_Service::get_recent_logs(50, 'error');

// پاکسازی لاگ‌های قدیمی‌تر از 30 روز
Hesabix_V2_Log_Service::clean_old_logs(30);
```

---

## 🔄 Sync Service

### همگام‌سازی دستی

```php
$sync = new Hesabix_V2_Sync_Service();

// همگام‌سازی یک محصول
$result = $sync->sync_product($product_id);

// همگام‌سازی محصول متغیر
$result = $sync->sync_product($product_id, $variation_id);

// همگام‌سازی مشتری
$result = $sync->sync_customer($customer_id, $order_id);

// همگام‌سازی سفارش (ایجاد فاکتور)
$result = $sync->sync_order($order_id);

// همگام‌سازی گروهی
$results = $sync->bulk_sync_products([1, 2, 3, 4, 5]);
```

### پردازش صف (Queue)

```php
// این توسط cron job هر 5 دقیقه اجرا می‌شود
do_action('hesabix_v2_process_queue');
```

---

## 🎨 سفارشی‌سازی UI

### اضافه کردن تب جدید

```php
add_action('hesabix_v2_admin_tabs', function($tabs) {
    $tabs['my_custom_tab'] = __('تب سفارشی', 'my-plugin');
    return $tabs;
});

add_action('hesabix_v2_admin_tab_content_my_custom_tab', function() {
    echo '<h2>محتوای تب سفارشی</h2>';
});
```

### اضافه کردن فیلد به تنظیمات

```php
add_action('hesabix_v2_settings_fields', function() {
    ?>
    <tr>
        <th><?php _e('تنظیم سفارشی', 'my-plugin'); ?></th>
        <td>
            <input type="text" name="my_custom_setting" 
                   value="<?php echo esc_attr(get_option('my_custom_setting')); ?>">
        </td>
    </tr>
    <?php
});

add_action('hesabix_v2_save_settings', function() {
    if (isset($_POST['my_custom_setting'])) {
        update_option('my_custom_setting', sanitize_text_field($_POST['my_custom_setting']));
    }
});
```

---

## 🧪 تست

### تست دستی

```php
// تست ایجاد محصول
$api = new Hesabix_V2_Api();
$result = $api->create_product(array(
    'name_fa' => 'محصول تست',
    'product_type' => 'simple',
    'unit' => 'عدد',
    'sell_price' => 10000,
    'is_service' => false
));

var_dump($result);
```

### تست Mapping

```php
$db = new Hesabix_V2_DB_Service();

// ذخیره
$db->save_mapping('product', 123, null, 456);

// بازیابی
$hesabix_id = $db->get_hesabix_id('product', 123);
echo "Hesabix ID: " . $hesabix_id; // 456
```

---

## 🔧 توابع کمکی

### تبدیل ارز (در صورت نیاز)

```php
function convert_currency($amount, $from, $to) {
    if ($from === 'IRT' && $to === 'IRR') {
        return $amount * 10;
    }
    if ($from === 'IRR' && $to === 'IRT') {
        return $amount / 10;
    }
    return $amount;
}
```

### دریافت تنظیمات همگام‌سازی

```php
$sync_settings = get_option('hesabix_v2_sync_settings', array());

if ($sync_settings['auto_sync_products']) {
    // همگام‌سازی خودکار فعال است
}
```

---

## 🐛 Debug

### فعال کردن Debug Mode

```php
update_option('hesabix_v2_debug_mode', true);
```

در این حالت:
- تمام API requests لاگ می‌شوند
- تمام API responses لاگ می‌شوند
- جزئیات کامل ذخیره می‌شود

### مشاهده لاگ‌های Debug

```bash
tail -f wp-content/uploads/hesabix-v2-logs/$(date +%Y-%m-%d).log
```

---

## 📊 Query های مفید

### محصولات همگام نشده

```sql
SELECT p.ID, p.post_title
FROM wp_posts p
LEFT JOIN wp_hesabix_v2 h 
    ON p.ID = h.wc_id AND h.entity_type = 'product'
WHERE p.post_type = 'product'
  AND p.post_status = 'publish'
  AND h.id IS NULL
LIMIT 100;
```

### خطاهای همگام‌سازی

```sql
SELECT entity_type, wc_id, error_message, retry_count
FROM wp_hesabix_v2
WHERE sync_status = 'error'
ORDER BY updated_at DESC
LIMIT 50;
```

### آمار روزانه

```sql
SELECT 
    DATE(created_at) as date,
    entity_type,
    COUNT(*) as count
FROM wp_hesabix_v2_sync_log
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at), entity_type
ORDER BY date DESC;
```

---

## 🔄 سناریوهای پیشرفته

### همگام‌سازی با شرط

```php
add_filter('hesabix_v2_should_sync_product', function($should_sync, $product) {
    // فقط محصولات با قیمت بالای 10000 تومان
    if ($product->get_price() < 10000) {
        return false;
    }
    return $should_sync;
}, 10, 2);
```

### تغییر mapping category

```php
add_filter('hesabix_v2_category_mapping', function($hesabix_category_id, $wc_category_id) {
    // استفاده از mapping سفارشی
    $custom_mapping = array(
        15 => 100,  // WC category 15 → Hesabix category 100
        16 => 101,
    );
    
    return $custom_mapping[$wc_category_id] ?? $hesabix_category_id;
}, 10, 2);
```

### کنترل retry

```php
add_filter('hesabix_v2_max_retry_count', function($max_retry) {
    return 5; // پیش‌فرض: 3
});

add_filter('hesabix_v2_retry_delay', function($delay, $attempt) {
    // Exponential backoff
    return min(300, pow(2, $attempt) * 10);
}, 10, 2);
```

---

## 🛡️ امنیت

### Validation سفارشی

```php
add_filter('hesabix_v2_validate_national_id', function($is_valid, $national_id) {
    // الگوریتم اعتبارسنجی کد ملی
    if (strlen($national_id) !== 10) {
        return false;
    }
    
    // بررسی checksum
    // ...
    
    return $is_valid;
}, 10, 2);
```

### محدودیت Rate Limiting

```php
add_filter('hesabix_v2_api_rate_limit', function($limit) {
    return 60; // تعداد request در دقیقه
});
```

---

## 🔧 کدهای مفید

### دریافت تمام محصولات بدون mapping

```php
global $wpdb;

$unmapped_products = $wpdb->get_results("
    SELECT p.ID, p.post_title
    FROM {$wpdb->posts} p
    LEFT JOIN {$wpdb->prefix}hesabix_v2 h 
        ON p.ID = h.wc_id 
        AND h.entity_type = 'product'
    WHERE p.post_type = 'product'
      AND p.post_status = 'publish'
      AND h.id IS NULL
");

foreach ($unmapped_products as $product) {
    echo "Product #{$product->ID}: {$product->post_title}\n";
}
```

### همگام‌سازی محصولات بدون mapping

```php
$sync = new Hesabix_V2_Sync_Service();

foreach ($unmapped_products as $product) {
    $result = $sync->sync_product($product->ID);
    
    if ($result['success']) {
        echo "✓ {$product->post_title}\n";
    } else {
        echo "✗ {$product->post_title}: {$result['message']}\n";
    }
}
```

### پاکسازی mapping های قدیمی

```php
global $wpdb;

// حذف mapping های محصولاتی که دیگر وجود ندارند
$wpdb->query("
    DELETE h FROM {$wpdb->prefix}hesabix_v2 h
    LEFT JOIN {$wpdb->posts} p ON h.wc_id = p.ID
    WHERE h.entity_type = 'product'
      AND p.ID IS NULL
");
```

---

## 🎯 Best Practices

### 1. استفاده از Try-Catch

```php
try {
    $sync = new Hesabix_V2_Sync_Service();
    $result = $sync->sync_product($product_id);
    
    if (!$result['success']) {
        Hesabix_V2_Log_Service::error('Sync failed', array(
            'product_id' => $product_id,
            'error' => $result['message']
        ));
    }
} catch (Exception $e) {
    Hesabix_V2_Log_Service::error('Exception', array(
        'error' => $e->getMessage()
    ));
}
```

### 2. بررسی وجود Class

```php
if (class_exists('Hesabix_V2_Api')) {
    $api = new Hesabix_V2_Api();
    // ...
}
```

### 3. استفاده از Nonce

```php
// در فرم
wp_nonce_field('hesabix_v2_action', 'hesabix_v2_nonce');

// در پردازش
if (!wp_verify_nonce($_POST['hesabix_v2_nonce'], 'hesabix_v2_action')) {
    wp_die('Invalid nonce');
}
```

### 4. Sanitization

```php
$product_id = isset($_POST['product_id']) ? intval($_POST['product_id']) : 0;
$name = isset($_POST['name']) ? sanitize_text_field($_POST['name']) : '';
$email = isset($_POST['email']) ? sanitize_email($_POST['email']) : '';
```

---

## 🚀 Performance Tips

### 1. Batch Processing

```php
// به جای sync تک‌تک
foreach ($product_ids as $id) {
    $sync->sync_product($id);
}

// استفاده از bulk
$sync->bulk_sync_products($product_ids);
```

### 2. استفاده از Queue

```php
// برای عملیات سنگین
global $wpdb;
$wpdb->insert($wpdb->prefix . 'hesabix_v2_queue', array(
    'entity_type' => 'product',
    'entity_id' => $product_id,
    'action' => 'sync',
    'priority' => 5,
    'status' => 'pending'
));
```

### 3. Caching

```php
// Cache category mappings
$cache_key = 'hesabix_v2_category_' . $wc_category_id;
$hesabix_id = wp_cache_get($cache_key);

if ($hesabix_id === false) {
    $hesabix_id = $db->get_hesabix_id('category', $wc_category_id);
    wp_cache_set($cache_key, $hesabix_id, '', 3600);
}
```

---

## 📦 ساخت Release

### 1. آماده‌سازی

```bash
cd hesabixwcplugin-v2
rm -rf .git
rm -rf node_modules
```

### 2. ایجاد ZIP

```bash
cd ..
zip -r hesabix-v2.2.0.0.zip hesabixwcplugin-v2/ \
    -x "*.git*" \
    -x "*node_modules*" \
    -x "*.DS_Store" \
    -x "*Thumbs.db"
```

### 3. تست

```bash
# نصب در محیط تست
# بررسی عملکرد
# بررسی compatibility
```

---

## 📚 منابع

- [API Documentation](https://api.hesabix.ir/docs)
- [WooCommerce Developer Docs](https://woocommerce.github.io/code-reference/)
- [WordPress Plugin Handbook](https://developer.wordpress.org/plugins/)

---

**نسخه:** 2.0.0  
**تاریخ:** 2024-12-05

