# 🚀 راهنمای سریع شروع - افزونه مدیریت تعمیرگاه

## مرحله 1: اجرای Migration

```bash
cd /var/www/ark/hesabixAPI

# فعال‌سازی محیط مجازی (اگر دارید)
source venv/bin/activate

# اجرای migration
alembic upgrade head
```

## مرحله 2: ثبت افزونه در Marketplace

```bash
python scripts/add_repair_shop_plugin.py
```

خروجی مورد انتظار:
```
✅ افزونه ایجاد شد (ID: X)
   ✅ پلن اشتراک ماهانه ایجاد شد (500,000 تومان)
   ✅ پلن اشتراک سالانه ایجاد شد (5,000,000 تومان)

============================================================
✅ افزونه مدیریت تعمیرگاه با موفقیت ثبت شد!
============================================================
```

## مرحله 3: تست API ها

### 3.1 بررسی وضعیت افزونه

```bash
curl -X GET "http://localhost:8000/api/v1/repair-shop/businesses/1/plugin-status" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### 3.2 دریافت تنظیمات

```bash
curl -X GET "http://localhost:8000/api/v1/repair-shop/businesses/1/settings" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### 3.3 ایجاد تعمیرکار

```bash
curl -X POST "http://localhost:8000/api/v1/repair-shop/businesses/1/technicians" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "person_id": 1,
    "commission_type": "percentage",
    "commission_value": 30
  }'
```

### 3.4 ایجاد سفارش تعمیر

```bash
curl -X POST "http://localhost:8000/api/v1/repair-shop/businesses/1/orders" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_person_id": 1,
    "product_name": "لپتاپ ایسوس",
    "problem_description": "روشن نمی‌شود"
  }'
```

## مرحله 4: سناریوی کامل

### سناریو: تعمیر یک لپتاپ

```bash
# 1. ایجاد سفارش
ORDER_ID=$(curl -X POST "..." | jq -r '.data.id')

# 2. اختصاص تعمیرکار
curl -X POST ".../orders/$ORDER_ID/assign-technician" \
  -d '{"technician_id": 1}'

# 3. تغییر وضعیت به "در حال تعمیر"
curl -X POST ".../orders/$ORDER_ID/update-status" \
  -d '{"status": "in_progress"}'

# 4. افزودن قطعات
curl -X POST ".../orders/$ORDER_ID/add-parts" \
  -d '{
    "parts": [
      {
        "product_id": 10,
        "quantity": 1,
        "warehouse_id": 1
      }
    ]
  }'

# 5. محاسبه هزینه‌ها
curl -X POST ".../orders/$ORDER_ID/calculate-costs" \
  -d '{"labor_cost": 1000000}'

# 6. تکمیل تعمیر
curl -X POST ".../orders/$ORDER_ID/complete" \
  -d '{"is_fixed": true}'

# 7. صدور فاکتور
curl -X POST ".../orders/$ORDER_ID/create-invoice"

# 8. تحویل کالا
curl -X POST ".../orders/$ORDER_ID/deliver"
```

## مرحله 5: بررسی در Swagger

مراجعه کنید به:
```
http://localhost:8000/docs
```

و بخش **Repair Shop** را مشاهده کنید.

## نکات مهم

### ✅ افزونه باید فعال باشد
قبل از استفاده، کسب‌وکار باید افزونه را خریداری یا trial کند:

```bash
# شروع trial
curl -X POST "http://localhost:8000/api/v1/marketplace/business/1/plugins/PLUGIN_ID/start-trial" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### ✅ محصول خدمات تعمیر
برای صدور فاکتور، یک محصول با مشخصات زیر ایجاد کنید:
- نوع: `service`
- کد: `SRV-REPAIR`
- نام: "خدمات تعمیر"

### ✅ انبار پیش‌فرض
در تنظیمات، انبار پیش‌فرض را مشخص کنید.

## خطاهای رایج

### خطا: `PLUGIN_NOT_ACTIVE`
**حل**: افزونه را فعال کنید (خرید یا trial)

### خطا: `INSUFFICIENT_STOCK`
**حل**: موجودی قطعه را در انبار بررسی کنید

### خطا: `NO_ACTIVE_STORAGE_PLAN`
**حل**: برای آپلود تصاویر، پلن ذخیره‌سازی فعال کنید

### خطا: `INVOICE_ALREADY_EXISTS`
**حل**: هر سفارش فقط یک فاکتور دارد

## پشتیبانی

در صورت بروز مشکل:
1. لاگ‌های سرور را بررسی کنید
2. وضعیت migration را چک کنید
3. وضعیت افزونه را بررسی کنید

---

✅ **موفق باشید!**




