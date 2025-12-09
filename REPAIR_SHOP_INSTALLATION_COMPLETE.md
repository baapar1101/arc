# ✅ نصب کامل افزونه مدیریت تعمیرگاه

## وضعیت نصب

### ✅ دیتابیس (Database)

**جداول ایجاد شده:**
- ✅ `repair_shop_settings` - تنظیمات تعمیرگاه
- ✅ `repair_technicians` - تعمیرکاران  
- ✅ `repair_orders` - سفارشات تعمیر
- ✅ `repair_order_parts` - قطعات استفاده شده
- ✅ `repair_order_statuses` - تاریخچه وضعیت‌ها
- ✅ `repair_order_attachments` - ضمائم و تصاویر
- ✅ `repair_invoices` - لینک به فاکتورها

**Marketplace:**
- ✅ افزونه ثبت شده (ID: 3)
- ✅ کد: `repair_shop_management`
- ✅ نام: مدیریت تعمیرگاه
- ✅ Trial: 14 روز رایگان
- ✅ پلن ماهانه: 500,000 تومان
- ✅ پلن سالانه: 5,000,000 تومان

### ✅ Backend (کد)

**فایل‌های ایجاد شده:**
1. ✅ Models: `/adapters/db/models/repair_shop.py`
2. ✅ Repositories: `/adapters/db/repositories/repair_shop_repository.py`
3. ✅ Services: 
   - `/app/services/repair_shop_service.py`
   - `/app/services/repair_shop_operations.py`
   - `/app/services/repair_shop_accounting.py`
4. ✅ API: `/adapters/api/v1/repair_shop.py`
5. ✅ Schemas: `/adapters/api/v1/schema_models/repair_shop.py`
6. ✅ Core: `/app/core/repair_shop_plugin_dependency.py`
7. ✅ Migrations:
   - `/migrations/versions/20250205_000001_create_repair_shop_tables.py`
   - `/migrations/versions/20250205_000002_seed_repair_shop_plugin.py`
8. ✅ Scripts:
   - `/scripts/add_repair_shop_plugin.py`
   - `/scripts/insert_repair_shop_plugin.py`
   - `/scripts/check_repair_shop_plugin.py`

### ✅ API Endpoints

**تعداد کل**: 20+ endpoint

**دسترسی از**:
```
http://localhost:8000/docs#/Repair%20Shop
```

---

## 🚀 نحوه استفاده

### 1. فعال‌سازی افزونه برای کسب‌وکار

#### روش A: شروع Trial (14 روز رایگان)

```bash
POST /api/v1/marketplace/business/{business_id}/plugins/3/start-trial
```

#### روش B: خرید مستقیم

```bash
POST /api/v1/marketplace/business/{business_id}/purchase
{
  "plugin_id": 3,
  "plan_id": 1  # یا 2 برای سالانه
}
```

### 2. ثبت اولین تعمیرکار

```bash
POST /api/v1/repair-shop/businesses/{business_id}/technicians
{
  "person_id": 1,
  "commission_type": "percentage",
  "commission_value": 30
}
```

### 3. ثبت اولین سفارش تعمیر

```bash
POST /api/v1/repair-shop/businesses/{business_id}/orders
{
  "customer_person_id": 1,
  "product_name": "لپتاپ ایسوس",
  "problem_description": "روشن نمی‌شود",
  "estimated_cost": 1500000
}
```

### 4. پیگیری جریان تعمیر

```bash
# اختصاص تعمیرکار
POST /orders/{order_id}/assign-technician {"technician_id": 1}

# شروع تعمیر
POST /orders/{order_id}/update-status {"status": "in_progress"}

# افزودن قطعات
POST /orders/{order_id}/add-parts {"parts": [...]}

# محاسبه هزینه
POST /orders/{order_id}/calculate-costs {"labor_cost": 1000000}

# اتمام تعمیر
POST /orders/{order_id}/complete {"is_fixed": true}

# صدور فاکتور
POST /orders/{order_id}/create-invoice

# تحویل
POST /orders/{order_id}/deliver
```

---

## 📊 یکپارچگی‌های فعال

✅ **Marketplace Plugin System** - افزونه باید فعال باشد  
✅ **Permission System** - دسترسی‌های جداگانه (read, write, delete, manage)  
✅ **Product System** - استفاده از محصولات و خدمات موجود  
✅ **Accounting Integration** - ثبت خودکار فاکتور و اسناد حسابداری  
✅ **Warehouse Integration** - حواله خروج خودکار + بررسی موجودی  
✅ **Storage Integration** - بررسی پلن فعال برای آپلود تصاویر  
✅ **Warranty Integration** - تاریخچه تعمیرات براساس کد گارانتی  

---

## 🎯 مراحل بعدی (Frontend)

سیستم Backend به طور کامل آماده است. برای استفاده کامل، نیاز به پیاده‌سازی موارد زیر در Flutter است:

### صفحات ضروری:
1. صفحه لیست سفارشات تعمیر
2. صفحه ثبت سفارش جدید
3. صفحه جزئیات و کارتابل
4. صفحه مدیریت تعمیرکاران
5. صفحه تنظیمات

### ویجت‌های مورد نیاز:
1. Kanban Board برای کارتابل
2. Timeline برای تاریخچه وضعیت‌ها
3. Cost Calculator
4. Parts Selector
5. Image Upload

---

## 📞 پشتیبانی

در صورت بروز مشکل:

1. **بررسی لاگ‌ها**:
   ```bash
   tail -f /var/log/hesabix/api.log
   ```

2. **بررسی وضعیت افزونه**:
   ```bash
   python3 scripts/check_repair_shop_plugin.py
   ```

3. **تست API**:
   ```
   http://localhost:8000/docs
   ```

---

**تاریخ نصب**: 2025-02-05  
**نسخه**: 1.0.0  
**وضعیت**: ✅ کامل و آماده استفاده




