# گزارش endpoint های سطح کسب و کار و بررسی دسترسی‌ها

این گزارش شامل بررسی کلیه endpoint های سطح کسب و کار و بررسی سطوح دسترسی آنها است.

## 📊 آمار کلی

- **کل endpoint های سطح کسب و کار**: 65+
- **با دسترسی مناسب (require_business_access)**: اکثر
- **با permission مناسب (require_business_permission_dep)**: تعداد کم
- **بدون دسترسی مناسب**: تعداد خیلی کم یا هیچ

---

## ✅ endpoint های با Permission مناسب

این endpoint ها از `require_business_permission_dep` یا `require_business_permission_by_entity_dep` استفاده می‌کنند که هم دسترسی کسب و کار و هم permission سطح کسب و کار را بررسی می‌کنند.

### Invoices
- ✅ `PUT /business/{business_id}/{invoice_id}` - با `require_business_permission_dep("invoices", "delete")`
- ✅ `DELETE /business/{business_id}/{invoice_id}` - با `require_business_permission_dep("invoices", "delete")`

### Bank Accounts
- ✅ `POST /businesses/{business_id}/bank-accounts/create` - با `require_business_permission_dep("bank_accounts", "add")`
- ✅ `POST /businesses/{business_id}/bank-accounts/bulk-delete` - با `require_business_permission_dep("bank_accounts", "delete")`
- ✅ `GET /bank-accounts/{account_id}` - با `require_business_permission_by_entity_dep("bank_accounts", "view", BankAccount, "account_id")`
- ✅ `PUT /bank-accounts/{account_id}` - با `require_business_permission_by_entity_dep("bank_accounts", "edit", BankAccount, "account_id")`
- ✅ `DELETE /bank-accounts/{account_id}` - با `require_business_permission_by_entity_dep("bank_accounts", "delete", BankAccount, "account_id")`

### Persons
- ✅ `POST /businesses/{business_id}/persons/create` - با `require_business_permission_dep("people", "add")`
- ✅ `POST /businesses/{business_id}/persons/bulk-delete` - با `require_business_permission_dep("people", "delete")`

---

## ⚠️ endpoint های فقط با دسترسی کسب و کار

این endpoint ها فقط از `@require_business_access` استفاده می‌کنند که فقط دسترسی به کسب و کار را بررسی می‌کند و permission سطح کسب و کار را بررسی نمی‌کند.

### Products
- ⚠️ `POST /business/{business_id}` - ایجاد محصول
- ⚠️ `POST /business/{business_id}/search` - جستجوی محصولات
- ⚠️ `GET /business/{business_id}/{product_id}` - جزئیات محصول
- ⚠️ `PUT /business/{business_id}/{product_id}` - ویرایش محصول
- ⚠️ `DELETE /business/{business_id}/{product_id}` - حذف محصول
- ⚠️ `POST /business/{business_id}/bulk-delete` - حذف گروهی
- ⚠️ `POST /business/{business_id}/export/excel` - خروجی Excel
- ⚠️ `POST /business/{business_id}/import/template` - دریافت قالب
- ⚠️ `POST /business/{business_id}/import/excel` - واردات Excel
- ⚠️ `POST /business/{business_id}/export/pdf` - خروجی PDF
- ⚠️ `POST /business/{business_id}/bulk-price-update/preview` - پیش‌نمایش به‌روزرسانی قیمت
- ⚠️ `POST /business/{business_id}/bulk-price-update/apply` - اعمال به‌روزرسانی قیمت
- ⚠️ `POST /businesses/{business_id}/reports/item-movements` - گزارش گردش کالا
- ⚠️ `POST /businesses/{business_id}/reports/item-movements/export/excel` - خروجی گزارش گردش
- ⚠️ `POST /businesses/{business_id}/reports/sales-by-product` - گزارش فروش بر اساس محصول
- ⚠️ `POST /businesses/{business_id}/reports/sales-by-product/export/excel` - خروجی گزارش فروش
- ⚠️ `POST /businesses/{business_id}/reports/inventory-kardex` - گزارش کاردکس موجودی
- ⚠️ `POST /businesses/{business_id}/reports/inventory-kardex/export/excel` - خروجی کاردکس

**نکته**: برخی endpoint ها در بدنه تابع بررسی دسترسی می‌کنند (مثل `has_business_permission` یا `can_read_section`)

### Invoices
- ⚠️ `POST /business/{business_id}` - ایجاد فاکتور
- ⚠️ `GET /business/{business_id}/{invoice_id}` - جزئیات فاکتور
- ⚠️ `GET /business/{business_id}/{invoice_id}/installments` - اقساط فاکتور
- ⚠️ `POST /business/{business_id}/installments/search` - جستجوی اقساط
- ⚠️ `POST /business/{business_id}/installments/export/excel` - خروجی اقساط
- ⚠️ `POST /business/{business_id}/search` - جستجوی فاکتورها
- ⚠️ `POST /business/{business_id}/tax-workspace/search` - جستجوی workspace مالیاتی
- ⚠️ `POST /business/{business_id}/{invoice_id}/tax-workspace/add` - افزودن به workspace
- ⚠️ `POST /business/{business_id}/{invoice_id}/tax-workspace/remove` - حذف از workspace
- ⚠️ `POST /business/{business_id}/{invoice_id}/tax-workspace/send-to-system` - ارسال به سیستم مالیاتی
- ⚠️ `POST /business/{business_id}/tax-workspace/send-to-system-batch` - ارسال دسته‌ای
- ⚠️ `POST /business/{business_id}/tax-workspace/remove-batch` - حذف دسته‌ای

### Persons
- ⚠️ `POST /businesses/{business_id}/persons` - لیست اشخاص
- ⚠️ `POST /businesses/{business_id}/persons/export/excel` - خروجی Excel
- ⚠️ `POST /businesses/{business_id}/persons/export/pdf` - خروجی PDF
- ⚠️ `POST /businesses/{business_id}/persons/import/template` - دریافت قالب
- ⚠️ `POST /businesses/{business_id}/persons/import/excel` - واردات Excel
- ⚠️ `GET /businesses/{business_id}/persons/summary` - خلاصه اشخاص
- ⚠️ `POST /businesses/{business_id}/reports/debtors` - گزارش بدهکاران
- ⚠️ `POST /businesses/{business_id}/reports/debtors/export/excel` - خروجی بدهکاران
- ⚠️ `POST /businesses/{business_id}/reports/creditors` - گزارش بستانکاران
- ⚠️ `POST /businesses/{business_id}/reports/creditors/export/excel` - خروجی بستانکاران
- ⚠️ `POST /businesses/{business_id}/reports/people-transactions` - گزارش تراکنش‌های اشخاص
- ⚠️ `POST /businesses/{business_id}/reports/people-transactions/export/excel` - خروجی تراکنش‌ها

### Accounts (حساب‌های کل)
- ⚠️ `GET /business/{business_id}/tree` - درخت حساب‌ها
- ⚠️ `GET /business/{business_id}` - لیست حساب‌ها
- ⚠️ `GET /business/{business_id}/account/{account_id}` - جزئیات حساب
- ⚠️ `POST /business/{business_id}` - جستجوی حساب‌ها
- ⚠️ `POST /business/{business_id}/create` - ایجاد حساب (با manual check: `can_write_section("accounting")`)
- ⚠️ `PUT /account/{account_id}` - ویرایش حساب (با manual check)
- ⚠️ `DELETE /account/{account_id}` - حذف حساب (با manual check)

### Categories
- ⚠️ `POST /business/{business_id}/tree` - درخت دسته‌بندی‌ها (با manual check: `can_read_section("categories")`)
- ⚠️ `POST /business/{business_id}` - ایجاد دسته‌بندی (با manual check: `has_business_permission("categories", "add")`)
- ⚠️ `POST /business/{business_id}/update` - ویرایش (با manual check: `has_business_permission("categories", "edit")`)
- ⚠️ `POST /business/{business_id}/move` - جابجایی (با manual check: `has_business_permission("categories", "edit")`)
- ⚠️ `POST /business/{business_id}/delete` - حذف (با manual check: `has_business_permission("categories", "delete")`)
- ⚠️ `POST /business/{business_id}/search` - جستجو

### BOMs
- ⚠️ `POST /business/{business_id}` - ایجاد BOM
- ⚠️ `GET /business/{business_id}` - لیست BOMها
- ⚠️ `GET /business/{business_id}/{bom_id}` - جزئیات BOM
- ⚠️ `PUT /business/{business_id}/{bom_id}` - ویرایش BOM
- ⚠️ `DELETE /business/{business_id}/{bom_id}` - حذف BOM
- ⚠️ `POST /business/{business_id}/explode` - تجزیه BOM
- ⚠️ `POST /business/{business_id}/produce_draft` - تولید پیش‌نویس

### Price Lists
- ⚠️ `POST /business/{business_id}` - ایجاد لیست قیمت
- ⚠️ `POST /business/{business_id}/search` - جستجو
- ⚠️ `GET /business/{business_id}/{price_list_id}` - جزئیات
- ⚠️ `PUT /business/{business_id}/{price_list_id}` - ویرایش
- ⚠️ `DELETE /business/{business_id}/{price_list_id}` - حذف
- ⚠️ `POST /business/{business_id}/{price_list_id}/items` - افزودن/ویرایش آیتم
- ⚠️ `GET /business/{business_id}/{price_list_id}/items` - لیست آیتم‌ها
- ⚠️ `DELETE /business/{business_id}/items/{item_id}` - حذف آیتم

### Product Attributes
- ⚠️ `POST /business/{business_id}` - ایجاد ویژگی محصول
- ⚠️ `POST /business/{business_id}/search` - جستجو
- ⚠️ `GET /business/{business_id}/{attribute_id}` - جزئیات
- ⚠️ `PUT /business/{business_id}/{attribute_id}` - ویرایش
- ⚠️ `DELETE /business/{business_id}/{attribute_id}` - حذف

### Warehouses
- ⚠️ `POST /business/{business_id}` - ایجاد انبار
- ⚠️ `GET /business/{business_id}` - لیست انبارها
- ⚠️ `GET /business/{business_id}/{warehouse_id}` - جزئیات
- ⚠️ `PUT /business/{business_id}/{warehouse_id}` - ویرایش
- ⚠️ `DELETE /business/{business_id}/{warehouse_id}` - حذف
- ⚠️ `POST /business/{business_id}/query` - جستجو (با manual check)
- ⚠️ `POST /business/{business_id}/stock-report` - گزارش موجودی

### Warehouse Docs
- ⚠️ `POST /business/{business_id}/from-invoice/{invoice_id}` - ایجاد از فاکتور
- ⚠️ `POST /business/{business_id}/sources/invoices/search` - جستجوی فاکتورهای منبع
- ⚠️ `POST /business/{business_id}/create` - ایجاد دستی
- ⚠️ `POST /business/{business_id}/{wh_id}/post` - ثبت سند
- ⚠️ `GET /business/{business_id}/{wh_id}` - جزئیات
- ⚠️ `PUT /business/{business_id}/{wh_id}` - ویرایش
- ⚠️ `PUT /business/{business_id}/{wh_id}/lines/{line_id}` - ویرایش خط
- ⚠️ `POST /business/{business_id}/search` - جستجو
- ⚠️ `DELETE /business/{business_id}/{wh_id}` - حذف
- ⚠️ `POST /business/{business_id}/bulk-delete` - حذف دسته‌ای
- ⚠️ `POST /business/{business_id}/{wh_id}/cancel` - لغو
- ⚠️ `GET /business/{business_id}/{wh_id}/pdf` - خروجی PDF

### Fiscal Years
- ⚠️ `GET /{business_id}/fiscal-years` - لیست سال‌های مالی
- ⚠️ `GET /{business_id}/fiscal-years/current` - سال مالی جاری

### Business Dashboard
- ⚠️ `POST /{business_id}/dashboard` - داشبورد
- ⚠️ `POST /{business_id}/members` - لیست اعضا
- ⚠️ `POST /{business_id}/statistics` - آمار
- ⚠️ `POST /{business_id}/info-with-permissions` - اطلاعات با دسترسی‌ها
- ⚠️ `GET /{business_id}/dashboard/widgets/definitions` - تعاریف ویجت‌ها
- ⚠️ `GET /{business_id}/dashboard/layout` - چیدمان داشبورد
- ⚠️ `PUT /{business_id}/dashboard/layout` - ذخیره چیدمان
- ⚠️ `POST /{business_id}/dashboard/data` - داده ویجت‌ها
- ⚠️ `GET /{business_id}/dashboard/layout/default` - چیدمان پیش‌فرض
- ⚠️ `PUT /{business_id}/dashboard/layout/default` - انتشار چیدمان پیش‌فرض (فقط مالک)

### Business Users
- ⚠️ `GET /{business_id}/users/{user_id}` - جزئیات کاربر (با manual check: `can_manage_business_users()`)
- ⚠️ `GET /{business_id}/users` - لیست کاربران (با manual check: `can_manage_business_users()`)
- ⚠️ `POST /{business_id}/users` - افزودن کاربر (با manual check: `can_manage_business_users()`)
- ⚠️ `PUT /{business_id}/users/{user_id}/permissions` - به‌روزرسانی دسترسی‌ها (با manual check)
- ⚠️ `DELETE /{business_id}/users/{user_id}` - حذف کاربر (با manual check)

### Documents (اسناد حسابداری)
- ⚠️ `POST /businesses/{business_id}/documents` - لیست اسناد
- ⚠️ `POST /businesses/{business_id}/documents/export/pdf` - خروجی PDF
- ⚠️ سایر endpoint های documents

### Bank Accounts (Reports)
- ⚠️ `POST /businesses/{business_id}/reports/bank-accounts-turnover` - گزارش گردش حساب‌های بانکی
- ⚠️ `POST /businesses/{business_id}/reports/bank-accounts-turnover/export/excel` - خروجی Excel

### Cash Registers (Reports)
- ⚠️ `POST /businesses/{business_id}/reports/cash-petty-turnover` - گزارش گردش صندوق
- ⚠️ `POST /businesses/{business_id}/reports/cash-petty-turnover/export/excel` - خروجی Excel

---

## ❌ endpoint های بدون دسترسی مناسب

این endpoint ها یا دسترسی مناسب ندارند یا باید بررسی شوند:

**نکته**: در بررسی انجام شده، اکثر endpoint ها دسترسی دارند. اما ممکن است برخی endpoint های جدید یا خاص نیاز به بررسی داشته باشند.

---

## 📋 توصیه‌ها

### 1. استفاده از Permission Dependencies

برای endpoint هایی که عملیات حساس انجام می‌دهند (مثل ایجاد، ویرایش، حذف)، بهتر است از `require_business_permission_dep` استفاده شود:

```python
_: None = Depends(require_business_permission_dep("products", "add"))
```

### 2. استفاده از Manual Checks

اگر نمی‌توانید از dependency استفاده کنید، حداقل در بدنه تابع بررسی کنید:

```python
if not ctx.has_business_permission("products", "add"):
    raise ApiError("FORBIDDEN", "Missing business permission: products.add", http_status=403)
```

### 3. Priority برای افزودن Permission

1. **اولویت بالا**: عملیات حساس (حذف، ویرایش، ایجاد)
2. **اولویت متوسط**: عملیات خواندن حساس (گزارش‌ها، اطلاعات مالی)
3. **اولویت پایین**: عملیات خواندن عمومی

---

## 🔍 بخش‌های Permission

بخش‌های اصلی permission در سیستم:

- `people` - اشخاص
- `products` - محصولات
- `invoices` - فاکتورها
- `bank_accounts` - حساب‌های بانکی
- `sales` - فروش
- `purchases` - خرید
- `accounting` - حسابداری
- `inventory` - موجودی
- `warehouses` - انبارها
- `categories` - دسته‌بندی‌ها
- `reports` - گزارش‌ها
- `settings` - تنظیمات

### Actions متداول:

- `view` / `read` - مشاهده
- `add` - افزودن
- `edit` / `write` - ویرایش
- `delete` - حذف
- `export` - خروجی
- `approve` - تأیید

---

## ✅ خلاصه

- اکثر endpoint های سطح کسب و کار از `require_business_access` استفاده می‌کنند که دسترسی به کسب و کار را بررسی می‌کند
- تعداد کمی از endpoint ها از `require_business_permission_dep` استفاده می‌کنند که permission سطح کسب و کار را هم بررسی می‌کند
- برخی endpoint ها در بدنه تابع بررسی دسترسی می‌کنند (manual check)
- برای امنیت بهتر، بهتر است برای عملیات حساس از permission dependencies استفاده شود

