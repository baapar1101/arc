# تحلیل بخش‌ها و Endpointهای بدون دسترسی

این فایل شامل لیست بخش‌ها و endpointهای سطح کسب و کار است که:
1. **دسترسی تعریف نشده دارند** (permission check ندارند یا از dependency مناسب استفاده نمی‌کنند)
2. **در بخش مدیریت دسترسی‌ها تعریف نشده‌اند** (بخش‌ها در سیستم permissions تعریف نشده‌اند)

---

## بخش‌های موجود در سیستم Permissions

بر اساس `business_dashboard.py` و `README.md`:

### ✅ بخش‌های تعریف شده:
- `people`: add, view, edit, delete
- `people_receipts`: add, view, edit, delete, draft
- `people_payments`: add, view, edit, delete, draft
- `people_transactions`: add, view, edit, delete, draft
- `products`: add, view, edit, delete
- `price_lists`: add, view, edit, delete
- `categories`: add, view, edit, delete
- `product_attributes`: add, view, edit, delete
- `bank_accounts`: add, view, edit, delete
- `cash`: add, view, edit, delete
- `petty_cash`: add, view, edit, delete
- `checks`: add, view, edit, delete, collect, transfer, return
- `wallet`: view, charge
- `transfers`: add, view, edit, delete, draft
- `invoices`: add, view, edit, delete, draft
- `expenses_income`: add, view, edit, delete, draft
- `accounting_documents`: add, view, edit, delete, draft
- `chart_of_accounts`: add, view, edit, delete
- `opening_balance`: view, edit
- `warehouses`: add, view, edit, delete
- `warehouse_transfers`: add, view, edit, delete, draft
- `settings`: business, print, history, users
- `storage`: view, delete
- `sms`: history, templates
- `marketplace`: view, buy, invoices

---

## ❌ بخش‌ها و Endpointهای بدون دسترسی یا Section نامناسب

### 1. **Accounts (حساب‌ها) - `chart_of_accounts`**

**فایل:** `adapters/api/v1/accounts.py`

**مشکل:** 
- ✅ Section `chart_of_accounts` در permissions تعریف شده است
- ❌ اما endpointها **permission check ندارند** - فقط `require_business_access` دارند

**Endpointهای نیازمند تغییر:**
- `GET /accounts/business/{business_id}/tree` → نیاز به `chart_of_accounts.view`
- `GET /accounts/business/{business_id}` → نیاز به `chart_of_accounts.view`
- `GET /accounts/business/{business_id}/account/{account_id}` → نیاز به `chart_of_accounts.view`
- `POST /accounts/business/{business_id}` → نیاز به `chart_of_accounts.view` (search)
- `POST /accounts/business/{business_id}` → نیاز به `chart_of_accounts.add` (create)
- `PUT /accounts/business/{business_id}/account/{account_id}` → نیاز به `chart_of_accounts.edit`
- `DELETE /accounts/business/{business_id}/account/{account_id}` → نیاز به `chart_of_accounts.delete`

---

### 2. **Fiscal Years (سال‌های مالی)**

**فایل:** `adapters/api/v1/fiscal_years.py`

**مشکل:**
- ❌ **Section تعریف نشده** در permissions
- ❌ endpointها **permission check ندارند** - فقط `require_business_access` دارند

**Endpointهای نیازمند تغییر:**
- `GET /business/{business_id}/fiscal-years` → نیاز به section جدید مثل `fiscal_years.view`
- `GET /business/{business_id}/fiscal-years/current` → نیاز به section جدید مثل `fiscal_years.view`

**راه‌حل پیشنهادی:**
- اضافه کردن section `fiscal_years` به permissions با actions: `view`, `add`, `edit`, `delete`

---

### 3. **Kardex (کاردکس)**

**فایل:** `adapters/api/v1/kardex.py`

**مشکل:**
- ❌ **Section تعریف نشده** در permissions (یا باید `reports` باشد)
- ❌ endpointها **permission check ندارند** - فقط `require_business_access` دارند

**Endpointهای نیازمند تغییر:**
- `POST /kardex/businesses/{business_id}/lines` → نیاز به `reports.view` یا section جدید

**راه‌حل پیشنهادی:**
- استفاده از section `reports` با action `view` یا اضافه کردن section `kardex` با action `view`

---

### 4. **Report Templates (قالب‌های گزارش)**

**فایل:** `adapters/api/v1/report_templates.py`

**مشکل:**
- ❌ **Section `report_templates` در permissions تعریف نشده**
- ✅ اما endpointها permission check دارند (از `report_templates.write` استفاده می‌کنند)

**Endpointهای نیازمند تغییر:**
- تمام endpointها از section `report_templates` استفاده می‌کنند که باید به permissions اضافه شود

**راه‌حل پیشنهادی:**
- اضافه کردن section `report_templates` به permissions با actions: `view`, `write`, `delete`

---

### 5. **Business Dashboard (داشبورد کسب و کار)**

**فایل:** `adapters/api/v1/business_dashboard.py`

**مشکل:**
- ❌ **Section مناسب تعریف نشده**
- ❌ endpointها **permission check ندارند** - فقط `require_business_access` دارند

**Endpointهای نیازمند تغییر:**
- `POST /business/{business_id}/dashboard` → احتمالاً نیاز به `reports.view` یا section عمومی
- `POST /business/{business_id}/info-with-permissions` → نیاز به دسترسی عمومی (همه اعضا می‌توانند ببینند)
- endpointهای مربوط به widgets → نیاز به `settings.view` یا `reports.view`

**راه‌حل پیشنهادی:**
- استفاده از section `settings.view` برای داشبورد یا اضافه کردن section `dashboard` با action `view`

---

### 6. **Business Users (کاربران کسب و کار)**

**فایل:** `adapters/api/v1/business_users.py`

**مشکل:**
- ✅ Section `settings.manage_users` در permissions تعریف شده است
- ❌ اما endpointها **permission check ندارند** - فقط `require_business_access` دارند

**Endpointهای نیازمند تغییر:**
- `GET /business/{business_id}/users/{user_id}` → نیاز به `settings.manage_users`
- `GET /business/{business_id}/users` → نیاز به `settings.manage_users`
- `POST /business/{business_id}/users/add` → نیاز به `settings.manage_users`
- `POST /business/{business_id}/users/{user_id}/permissions` → نیاز به `settings.manage_users`
- `DELETE /business/{business_id}/users/{user_id}` → نیاز به `settings.manage_users`

---

### 7. **Products (محصولات)**

**فایل:** `adapters/api/v1/products.py`

**مشکل:**
- ✅ Section `products` در permissions تعریف شده است
- ⚠️ اما از section `inventory` استفاده می‌کند (نامناسب)

**Endpointهای نیازمند تغییر:**
- تمام endpointها باید از section `products` به جای `inventory` استفاده کنند

**Endpointهای نیازمند بررسی:**
- `POST /products/business/{business_id}` → از `inventory.write` استفاده می‌کند (باید `products.add` باشد)
- سایر endpointها نیاز به بررسی دارند

---

### 8. **Warehouses (انبارها)**

**فایل:** `adapters/api/v1/warehouses.py`

**مشکل:**
- ✅ Section `warehouses` در permissions تعریف شده است
- ⚠️ اما از section `inventory` استفاده می‌کند (نامناسب)

**Endpointهای نیازمند تغییر:**
- تمام endpointها باید از section `warehouses` به جای `inventory` استفاده کنند

---

### 9. **Warehouse Documents (اسناد انبار)**

**فایل:** `adapters/api/v1/warehouse_docs.py`

**مشکل:**
- ✅ Section `warehouse_transfers` در permissions تعریف شده است
- ❌ اما endpointها **permission check ندارند** - فقط `require_business_access` دارند

**Endpointهای نیازمند بررسی:**
- باید permission check با section مناسب اضافه شود (`warehouse_transfers`)

---

### 10. **Price Lists (لیست قیمت‌ها)**

**فایل:** `adapters/api/v1/price_lists.py`

**مشکل:**
- ✅ Section `price_lists` در permissions تعریف شده است
- ⚠️ اما از section `inventory` استفاده می‌کند (نامناسب)

**Endpointهای نیازمند تغییر:**
- تمام endpointها باید از section `price_lists` به جای `inventory` استفاده کنند

---

### 11. **Categories (دسته‌بندی‌ها)**

**فایل:** `adapters/api/v1/categories.py`

**مشکل:**
- ✅ Section `categories` در permissions تعریف شده است
- ✅ endpointها permission check دارند

**وضعیت:** ✅ **درست است**

---

### 12. **Product Attributes (ویژگی‌های محصول)**

**فایل:** `adapters/api/v1/product_attributes.py`

**مشکل:**
- ✅ Section `product_attributes` در permissions تعریف شده است
- ✅ endpointها permission check دارند

**وضعیت:** ✅ **درست است**

---

### 13. **BOMs (Bill of Materials)**

**فایل:** `adapters/api/v1/boms.py`

**مشکل:**
- ✅ Section `products` یا `inventory` در permissions تعریف شده است
- ⚠️ اما از section `inventory` استفاده می‌کند

**Endpointهای نیازمند بررسی:**
- احتمالاً باید section جداگانه `boms` داشته باشد یا از `products` استفاده کند

---

## خلاصه مشکلات

### بخش‌های بدون تعریف در Permissions:
1. ❌ **`fiscal_years`** - سال‌های مالی
2. ❌ **`report_templates`** - قالب‌های گزارش
3. ❌ **`kardex`** - کاردکس (یا باید از `reports` استفاده کند)
4. ❌ **`dashboard`** - داشبورد (یا باید از `reports` یا `settings` استفاده کند)

### Endpointهای بدون Permission Check:
1. ❌ **`accounts.py`** - تمام endpointها
2. ❌ **`fiscal_years.py`** - تمام endpointها
3. ❌ **`kardex.py`** - تمام endpointها
4. ❌ **`business_dashboard.py`** - تمام endpointها
5. ❌ **`business_users.py`** - تمام endpointها
6. ❌ **`warehouse_docs.py`** - تمام endpointها

### Endpointهای با Section نامناسب:
1. ⚠️ **`products.py`** - از `inventory` استفاده می‌کند (باید `products` باشد)
2. ⚠️ **`warehouses.py`** - از `inventory` استفاده می‌کند (باید `warehouses` باشد)
3. ⚠️ **`price_lists.py`** - از `inventory` استفاده می‌کند (باید `price_lists` باشد)
4. ⚠️ **`boms.py`** - از `inventory` استفاده می‌کند (باید `products` یا `boms` باشد)

---

## راه‌حل پیشنهادی

### 1. اضافه کردن بخش‌های جدید به Permissions:
```json
{
  "fiscal_years": {
    "view": true,
    "add": true,
    "edit": true,
    "delete": true
  },
  "report_templates": {
    "view": true,
    "write": true,
    "delete": true
  },
  "reports": {
    "view": true,
    "export": true
  }
}
```

### 2. اضافه کردن Permission Check به Endpointها:
- استفاده از `require_business_permission_dep` برای endpointهایی که `business_id` دارند
- استفاده از `require_business_permission_by_entity_dep` برای endpointهایی که entity ID دارند

### 3. اصلاح Section‌های نامناسب:
- تغییر از `inventory` به section مناسب (`products`, `warehouses`, `price_lists`)

---

## اولویت‌بندی

### اولویت بالا (امنیت):
1. ✅ **`accounts.py`** - دسترسی به حساب‌ها مهم است
2. ✅ **`business_users.py`** - مدیریت کاربران بسیار مهم است
3. ✅ **`fiscal_years.py`** - سال‌های مالی مهم هستند

### اولویت متوسط:
4. ⚠️ **`warehouse_docs.py`** - اسناد انبار
5. ⚠️ **`kardex.py`** - کاردکس
6. ⚠️ **`business_dashboard.py`** - داشبورد

### اولویت پایین (اصلاح Section):
7. 🔧 **`products.py`** - تغییر section از `inventory` به `products`
8. 🔧 **`warehouses.py`** - تغییر section از `inventory` به `warehouses`
9. 🔧 **`price_lists.py`** - تغییر section از `inventory` به `price_lists`

