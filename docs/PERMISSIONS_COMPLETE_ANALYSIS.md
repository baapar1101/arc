# تحلیل کامل دسترسی‌ها و Endpoint ها

این فایل شامل:
1. دسترسی‌های موجود در UI
2. دسترسی‌هایی که نیاز هستند اما در UI نیستند
3. هر endpoint چه دسترسی باید داشته باشد
4. وضعیت پیاده‌سازی (پیاده‌سازی شده یا نه)

---

## 📋 دسترسی‌های موجود در UI (users_permissions_page.dart)

### ✅ بخش‌های موجود:

| Section | Actions موجود در UI | توضیحات |
|---------|---------------------|---------|
| `people` | add, view, edit, delete | ✅ موجود |
| `people_transactions` | add, view, edit, delete, draft | ✅ موجود |
| `products` | add, view, edit, delete | ✅ موجود |
| `price_lists` | add, view, edit, delete | ✅ موجود |
| `categories` | add, view, edit, delete | ✅ موجود |
| `product_attributes` | add, view, edit, delete | ✅ موجود |
| `bank_accounts` | add, view, edit, delete | ✅ موجود |
| `cash` | add, view, edit, delete | ✅ موجود |
| `petty_cash` | add, view, edit, delete | ✅ موجود |
| `checks` | add, view, edit, delete, collect, transfer, return | ✅ موجود |
| `wallet` | view, charge | ✅ موجود |
| `transfers` | add, view, edit, delete, draft | ✅ موجود |
| `invoices` | add, view, edit, delete, draft | ✅ موجود |
| `expenses_income` | add, view, edit, delete, draft | ✅ موجود |
| `accounting_documents` | add, view, edit, delete, draft | ✅ موجود |
| `chart_of_accounts` | add, view, edit, delete | ✅ موجود |
| `opening_balance` | view, edit | ✅ موجود |
| `warehouses` | add, view, edit, delete | ✅ موجود |
| `warehouse_transfers` | add, view, edit, delete, draft | ✅ موجود |
| `settings` | business, print, history, users | ✅ موجود |
| `storage` | view, delete | ✅ موجود |
| `sms` | history, templates | ✅ موجود |
| `marketplace` | view, buy, invoices | ✅ موجود |

---

## ❌ دسترسی‌های مورد نیاز که در UI نیستند

### 🔴 بخش‌های جدید که باید به UI اضافه شوند:

| Section | Actions مورد نیاز | توضیحات | استفاده در |
|---------|-------------------|---------|------------|
| `reports` | view, export | گزارش‌ها و داشبورد | kardex.py, business_dashboard.py, products.py (reports), invoices.py (reports) |
| `fiscal_years` | view, add, edit, delete | سال‌های مالی | fiscal_years.py |
| `boms` | add, view, edit, delete | فهرست مواد (BOM) | boms.py |
| `invoices` | export | ❌ موجود نیست - باید اضافه شود | invoices.py (export endpoints) |
| `products` | export | ❌ موجود نیست - باید اضافه شود | products.py (export endpoints) |

---

## 📊 لیست کامل Endpoint ها با دسترسی مورد نیاز

### 🔴 اولویت بالا - امنیت حساس

#### 1. businesses.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| PUT | `/{business_id}` | `settings.business` | ❌ ندارد | الان `@require_business_management()` - باید به `require_business_access` + dependency تبدیل شود |
| POST | `/{business_id}/logo` | `settings.print` | ❌ ندارد | الان فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/{business_id}/logo` | `settings.print` یا `view` | ❌ ندارد | بدون decorator - باید `@require_business_access` + dependency اضافه شود |
| POST | `/{business_id}/stamp` | `settings.print` | ❌ ندارد | الان فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/{business_id}/stamp` | `settings.print` یا `view` | ❌ ندارد | بدون decorator - باید `@require_business_access` + dependency اضافه شود |
| GET | `/{business_id}/print-settings` | `settings.print` | ❌ ندارد | بدون decorator - باید `@require_business_access` + dependency اضافه شود |
| PUT | `/{business_id}/print-settings` | `settings.print` | ❌ ندارد | الان `@require_business_management()` - باید به `require_business_access` + dependency تبدیل شود |

#### 2. business_users.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| GET | `/{business_id}/users/{user_id}` | `settings.users` | ⚠️ manual check | الان manual check دارد - باید به dependency تبدیل شود |
| GET | `/{business_id}/users` | `settings.users` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| POST | `/{business_id}/users/add` | `settings.users` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| PUT | `/{business_id}/users/{user_id}/permissions` | `settings.users` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| DELETE | `/{business_id}/users/{user_id}` | `settings.users` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |

**نکته**: در UI از `settings.users` استفاده می‌شود، نه `settings.manage_users`

---

### 🟡 اولویت متوسط

#### 3. invoices.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `invoices.add` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}/{invoice_id}` | `invoices.view` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| PUT | `/business/{business_id}/{invoice_id}` | `invoices.edit` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| DELETE | `/business/{business_id}/{invoice_id}` | `invoices.delete` | ✅ دارد | **پیاده‌سازی شده** - `require_business_permission_dep("invoices", "delete")` |
| GET | `/business/{business_id}/{invoice_id}/pdf` | `invoices.view` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| POST | `/business/{business_id}/installments/search` | `invoices.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| POST | `/business/{business_id}/installments/export/excel` | `invoices.export` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| سایر export/list | - | `invoices.view` یا `export` | ❌ ندارد | بسته به نوع endpoint |

**نکته**: برای endpoint هایی با `invoice_id` باید از `require_business_permission_by_entity_dep("invoices", "action", Document, "invoice_id")` استفاده شود.

#### 4. products.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `products.add` | ⚠️ manual check | **manual check دارد** - باید به dependency تبدیل شود |
| POST | `/business/{business_id}/search` | `products.view` | ⚠️ manual check | **manual check دارد** - باید به dependency تبدیل شود |
| GET | `/business/{business_id}/{product_id}` | `products.view` | ⚠️ manual check | **manual check دارد** - باید به `require_business_permission_by_entity_dep` تبدیل شود |
| PUT | `/business/{business_id}/{product_id}` | `products.edit` | ⚠️ manual check | **manual check دارد** - باید به `require_business_permission_by_entity_dep` تبدیل شود |
| DELETE | `/business/{business_id}/{product_id}` | `products.delete` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` اضافه شود |
| export endpoints | - | `products.export` | ❌ ندارد | action `export` باید به UI اضافه شود |

#### 5. categories.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `categories.add` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}` | `categories.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}/{category_id}` | `categories.view` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| PUT | `/business/{business_id}/{category_id}` | `categories.edit` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| DELETE | `/business/{business_id}/{category_id}` | `categories.delete` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |

#### 6. price_lists.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `price_lists.add` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}` | `price_lists.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}/{price_list_id}` | `price_lists.view` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| PUT | `/business/{business_id}/{price_list_id}` | `price_lists.edit` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| DELETE | `/business/{business_id}/{price_list_id}` | `price_lists.delete` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| POST | `/business/{business_id}/{price_list_id}/products` | `price_lists.edit` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| POST | `/business/{business_id}/{price_list_id}/copy` | `price_lists.add` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |

#### 7. product_attributes.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `product_attributes.add` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}` | `product_attributes.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}/{attribute_id}` | `product_attributes.view` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| PUT | `/business/{business_id}/{attribute_id}` | `product_attributes.edit` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| DELETE | `/business/{business_id}/{attribute_id}` | `product_attributes.delete` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |

#### 8. warehouses.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `warehouses.add` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}` | `warehouses.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}/{warehouse_id}` | `warehouses.view` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| PUT | `/business/{business_id}/{warehouse_id}` | `warehouses.edit` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| DELETE | `/business/{business_id}/{warehouse_id}` | `warehouses.delete` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |

#### 9. warehouse_docs.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `warehouse_transfers.add` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| POST | `/business/{business_id}/search` | `warehouse_transfers.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET/PUT/DELETE | `/business/{business_id}/{doc_id}` | `warehouse_transfers.view/edit/delete` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |

#### 10. accounts.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `chart_of_accounts.add` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}` | `chart_of_accounts.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/business/{business_id}/{account_id}` | `chart_of_accounts.view` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| PUT | `/business/{business_id}/{account_id}` | `chart_of_accounts.edit` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |
| DELETE | `/business/{business_id}/{account_id}` | `chart_of_accounts.delete` | ❌ ندارد | فقط `@require_business_access` - باید `require_business_permission_by_entity_dep` استفاده شود |

---

### 🟢 اولویت پایین

#### 11. fiscal_years.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| GET | `/{business_id}/fiscal-years` | `fiscal_years.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/{business_id}/fiscal-years/current` | `fiscal_years.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |

**⚠️ نکته**: بخش `fiscal_years` در UI نیست - باید اضافه شود.

#### 12. boms.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/business/{business_id}` | `boms.add` | ⚠️ manual check | **manual check دارد** (`inventory.write`) - باید به dependency تبدیل شود |
| GET | `/business/{business_id}` | `boms.view` | ⚠️ manual check | **manual check دارد** (`inventory.view`) - باید به dependency تبدیل شود |
| سایر endpoints | - | `boms.view/edit/delete` | ❌ ندارد | باید `require_business_permission_by_entity_dep` استفاده شود |

**⚠️ نکته**: بخش `boms` در UI نیست - باید اضافه شود. یا می‌تواند از `products` استفاده کند.

#### 13. kardex.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| POST | `/businesses/{business_id}/lines` | `reports.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| POST | `/businesses/{business_id}/lines/export/excel` | `reports.export` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| POST | `/businesses/{business_id}/lines/export/pdf` | `reports.export` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |

**⚠️ نکته**: بخش `reports` در UI نیست - باید اضافه شود.

#### 14. business_dashboard.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| GET | `/{business_id}/summary` | `reports.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET | `/{business_id}/stats` | `reports.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| POST | `/{business_id}/info-with-permissions` | `settings.view` یا `reports.view` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| سایر dashboard endpoints | - | `reports.view` | ❌ ندارد | باید dependency اضافه شود |

#### 15. report_templates.py

| متد | مسیر | دسترسی مورد نیاز | وضعیت پیاده‌سازی | توضیحات |
|-----|------|------------------|-------------------|---------|
| GET | `/business/{business_id}` | `settings.edit` یا بخش جداگانه | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| POST | `/business/{business_id}` | `settings.edit` | ❌ ندارد | فقط `@require_business_access` - باید dependency اضافه شود |
| GET/PUT/DELETE | `/business/{business_id}/{template_id}` | `settings.edit` | ❌ ندارد | باید `require_business_permission_by_entity_dep` استفاده شود |

**نکته**: می‌تواند از `settings.edit` استفاده کند یا بخش جداگانه `report_templates` اضافه شود.

---

## ✅ Endpoint هایی که الان dependency دارند

### فایل‌های کامل:
- ✅ `cash_registers.py` - اکثر endpoint ها
- ✅ `petty_cash.py` - اکثر endpoint ها
- ✅ `bank_accounts.py` - اکثر endpoint ها
- ✅ `persons.py` - اکثر endpoint ها
- ✅ `receipts_payments.py` - endpoint های اصلی
- ✅ `transfers.py` - endpoint های اصلی
- ✅ `checks.py` - endpoint های اصلی
- ✅ `expense_income.py` - endpoint های اصلی
- ✅ `documents.py` - endpoint های اصلی
- ✅ `opening_balance.py` - همه endpoint ها

### فایل‌های جزئی:
- ⚠️ `invoices.py` - فقط endpoint حذف دارد dependency
- ⚠️ `products.py` - manual check دارد (باید به dependency تبدیل شود)
- ⚠️ `boms.py` - manual check دارد (باید به dependency تبدیل شود)

---

## 📝 دسترسی‌هایی که باید به UI اضافه شوند

### 1. بخش `reports` (جدید)

```json
{
  "reports": {
    "view": true,
    "export": true
  }
}
```

**استفاده در:**
- `kardex.py` - تمام endpoint ها
- `business_dashboard.py` - تمام endpoint ها
- گزارش‌های مختلف در سایر فایل‌ها

**Actions:**
- `view`: مشاهده گزارش‌ها و داشبورد
- `export`: خروجی Excel/PDF گزارش‌ها

---

### 2. بخش `fiscal_years` (جدید)

```json
{
  "fiscal_years": {
    "view": true,
    "add": true,
    "edit": true,
    "delete": true
  }
}
```

**استفاده در:**
- `fiscal_years.py` - تمام endpoint ها

**Actions:**
- `view`: مشاهده سال‌های مالی
- `add`: ایجاد سال مالی جدید
- `edit`: ویرایش سال مالی
- `delete`: حذف سال مالی

---

### 3. بخش `boms` (جدید - اختیاری)

```json
{
  "boms": {
    "add": true,
    "view": true,
    "edit": true,
    "delete": true
  }
}
```

**استفاده در:**
- `boms.py` - تمام endpoint ها

**یا می‌تواند از بخش `products` استفاده کند** چون BOM مربوط به محصولات است.

**Actions:**
- `add`: ایجاد BOM
- `view`: مشاهده BOM ها
- `edit`: ویرایش BOM
- `delete`: حذف BOM

---

### 4. Action `export` برای بخش‌های موجود

باید به این بخش‌ها action `export` اضافه شود:

| Section | Action جدید | استفاده در |
|---------|------------|------------|
| `invoices` | `export` | invoices.py - export endpoints |
| `products` | `export` | products.py - export endpoints |
| سایر بخش‌ها | `export` | export endpoints مختلف |

---

## 📊 خلاصه آماری

### Endpoint های نیازمند dependency:
- **businesses.py**: 7 endpoint
- **business_users.py**: 5 endpoint
- **invoices.py**: ~15 endpoint (فقط 1 تا دارد)
- **products.py**: ~10 endpoint (manual check دارند)
- **categories.py**: 5 endpoint
- **price_lists.py**: 8 endpoint
- **product_attributes.py**: 5 endpoint
- **warehouses.py**: 6 endpoint
- **warehouse_docs.py**: ~15 endpoint
- **accounts.py**: 5 endpoint
- **fiscal_years.py**: 2 endpoint
- **boms.py**: ~8 endpoint
- **kardex.py**: 3 endpoint
- **business_dashboard.py**: ~10 endpoint
- **report_templates.py**: ~9 endpoint

**جمع کل: ~113 endpoint نیازمند dependency**

### Endpoint های با dependency:
- ✅ ~40 endpoint (در فایل‌های cash_registers, petty_cash, bank_accounts, persons و...)

### Endpoint های با manual check:
- ⚠️ ~15 endpoint (در products.py, boms.py) - باید به dependency تبدیل شوند

---

## 🔧 توصیه‌های پیاده‌سازی

### 1. اضافه کردن بخش‌های جدید به UI

در فایل `users_permissions_page.dart` در تابع `_getAllPermissions` باید اضافه شود:

```dart
'reports': {
  'view': '${t.view} ${t.reports}',
  'export': '${t.export} ${t.reports}',
},
'fiscal_years': {
  'view': '${t.view} ${t.fiscalYears}',
  'add': '${t.add} ${t.fiscalYears}',
  'edit': '${t.edit} ${t.fiscalYears}',
  'delete': '${t.delete} ${t.fiscalYears}',
},
'boms': {  // اختیاری - می‌تواند از products استفاده کند
  'add': '${t.add} ${t.boms}',
  'view': '${t.view} ${t.boms}',
  'edit': '${t.edit} ${t.boms}',
  'delete': '${t.delete} ${t.boms}',
},
```

و به `sectionConfigs` اضافه شود:

```dart
{
  'title': 'گزارش‌ها',
  'icon': Icons.assessment,
  'sections': ['reports'],
},
{
  'title': 'سال‌های مالی',
  'icon': Icons.calendar_today,
  'sections': ['fiscal_years'],
},
```

### 2. اضافه کردن action `export` به بخش‌های موجود

باید به این بخش‌ها action `export` اضافه شود:
- `invoices`
- `products`
- و سایر بخش‌هایی که export دارند

### 3. اصلاح endpoint ها

1. **تبدیل manual check ها به dependency**
   - `products.py`
   - `boms.py`

2. **اضافه کردن dependency به endpoint های بدون dependency**
   - استفاده از `require_business_permission_dep` برای endpoint هایی با `business_id`
   - استفاده از `require_business_permission_by_entity_dep` برای endpoint هایی با entity ID

3. **تغییر از `@require_business_management()` به `@require_business_access` + dependency**
   - `businesses.py` - ویرایش کسب‌وکار و تنظیمات چاپ

---

## ✅ اولویت‌بندی نهایی

### فاز 1 - اولویت بالا (امنیت):
1. ✅ `business_users.py` - مدیریت کاربران (`settings.users`)
2. ✅ `businesses.py` - تنظیمات کسب‌وکار (`settings.business`, `settings.print`)
3. ✅ `invoices.py` - فاکتورها (`invoices.*`)

### فاز 2 - اولویت متوسط:
4. ✅ `products.py` - محصولات (`products.*`)
5. ✅ `accounts.py` - حساب‌ها (`chart_of_accounts.*`)
6. ✅ `warehouses.py` - انبارها (`warehouses.*`)
7. ✅ `categories.py`, `price_lists.py`, `product_attributes.py`

### فاز 3 - اولویت پایین:
8. ✅ `kardex.py`, `business_dashboard.py` - گزارش‌ها (`reports.*`)
9. ✅ `fiscal_years.py` - سال‌های مالی (`fiscal_years.*`)
10. ✅ `boms.py` - BOM (`boms.*` یا از `products` استفاده کند)
11. ✅ `report_templates.py` - قالب‌های گزارش

---

**تاریخ تهیه**: 2025-01-XX
**نسخه**: 1.0

