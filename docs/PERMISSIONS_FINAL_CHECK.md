# بررسی نهایی دسترسی‌ها - UI vs Endpoint ها

این فایل شامل بررسی نهایی دسترسی‌هایی است که در endpoint ها استفاده شده و مقایسه با آنچه در UI موجود است.

---

## ✅ دسترسی‌های استفاده شده در Endpoint های اصلاح شده

### 📋 فهرست کامل:

| Section | Action | استفاده در Endpoint | موجود در UI | وضعیت |
|---------|--------|---------------------|-------------|--------|
| `settings` | `business` | businesses.py - PUT | ✅ موجود | ✅ |
| `settings` | `print` | businesses.py - logo/stamp/print-settings | ✅ موجود | ✅ |
| `settings` | `users` | business_users.py - تمام endpoint ها | ✅ موجود | ✅ |
| `invoices` | `add` | invoices.py - POST | ✅ موجود | ✅ |
| `invoices` | `view` | invoices.py - GET | ✅ موجود | ✅ |
| `invoices` | `edit` | invoices.py - PUT | ✅ موجود | ✅ |
| `invoices` | `delete` | invoices.py - DELETE | ✅ موجود | ✅ |
| `invoices` | `export` | invoices.py - export/excel | ✅ موجود | ✅ اضافه شده |
| `products` | `add` | products.py - POST | ✅ موجود | ✅ |
| `products` | `view` | products.py - GET/POST search | ✅ موجود | ✅ |
| `products` | `edit` | products.py - PUT | ✅ موجود | ✅ |
| `products` | `delete` | products.py - DELETE | ✅ موجود | ✅ |
| `products` | `export` | products.py - export/excel/pdf | ✅ موجود | ✅ اضافه شده |
| `categories` | `add` | categories.py - POST | ✅ موجود | ✅ |
| `categories` | `view` | categories.py - POST tree/search | ✅ موجود | ✅ |
| `categories` | `edit` | categories.py - POST update/move | ✅ موجود | ✅ |
| `categories` | `delete` | categories.py - POST delete | ✅ موجود | ✅ |
| `price_lists` | `add` | price_lists.py - POST | ✅ موجود | ✅ |
| `price_lists` | `view` | price_lists.py - GET/POST search | ✅ موجود | ✅ |
| `price_lists` | `edit` | price_lists.py - PUT/POST items | ✅ موجود | ✅ |
| `price_lists` | `delete` | price_lists.py - DELETE | ✅ موجود | ✅ |
| `product_attributes` | `add` | product_attributes.py - POST | ✅ موجود | ✅ |
| `product_attributes` | `view` | product_attributes.py - GET/POST search | ✅ موجود | ✅ |
| `product_attributes` | `edit` | product_attributes.py - PUT | ✅ موجود | ✅ |
| `product_attributes` | `delete` | product_attributes.py - DELETE | ✅ موجود | ✅ |
| `warehouses` | `add` | warehouses.py - POST | ✅ موجود | ✅ |
| `warehouses` | `view` | warehouses.py - GET/POST query/stock-report | ✅ موجود | ✅ |
| `warehouses` | `edit` | warehouses.py - PUT | ✅ موجود | ✅ |
| `warehouses` | `delete` | warehouses.py - DELETE | ✅ موجود | ✅ |
| `chart_of_accounts` | `add` | accounts.py - POST create | ✅ موجود | ✅ |
| `chart_of_accounts` | `view` | accounts.py - GET tree/list/account | ✅ موجود | ✅ |
| `chart_of_accounts` | `edit` | accounts.py - PUT | ✅ موجود | ✅ |
| `chart_of_accounts` | `delete` | accounts.py - DELETE | ✅ موجود | ✅ |
| `reports` | `view` | products.py - reports endpoints | ✅ موجود | ✅ اضافه شده |
| `reports` | `export` | products.py - reports export/excel | ✅ موجود | ✅ اضافه شده |
| `fiscal_years` | `view` | fiscal_years.py - GET list/current | ✅ موجود | ✅ اضافه شده |

---

## ✅ بخش‌های موجود در UI

### 1. `_getAllPermissions` در `users_permissions_page.dart`:

✅ همه بخش‌های استفاده شده در endpoint ها موجود هستند:
- ✅ `settings` - business, print, history, users
- ✅ `invoices` - add, view, edit, delete, draft, **export** ✅
- ✅ `products` - add, view, edit, delete, **export** ✅
- ✅ `categories` - add, view, edit, delete
- ✅ `price_lists` - add, view, edit, delete
- ✅ `product_attributes` - add, view, edit, delete
- ✅ `warehouses` - add, view, edit, delete
- ✅ `chart_of_accounts` - add, view, edit, delete
- ✅ `reports` - **view, export** ✅ (اضافه شده)
- ✅ `fiscal_years` - **view** ✅ (اضافه شده - فقط view چون endpoint add/edit/delete ندارد)

### 2. `sectionConfigs` در `users_permissions_page.dart`:

✅ همه بخش‌ها در گروه‌های مناسب قرار گرفته‌اند:
- ✅ **اشخاص** - people, people_transactions
- ✅ **کالا و خدمات** - products, price_lists, categories, product_attributes
- ✅ **بانکداری** - bank_accounts, cash, petty_cash, checks, wallet, transfers
- ✅ **فاکتورها و هزینه‌ها** - invoices, expenses_income
- ✅ **حسابداری** - accounting_documents, chart_of_accounts, opening_balance
- ✅ **انبارداری** - warehouses, warehouse_transfers
- ✅ **گزارش‌ها** - reports ✅ (اضافه شده)
- ✅ **تنظیمات** - settings, storage, sms, marketplace, fiscal_years ✅ (اضافه شده)

### 3. `_localizeAction` در `users_permissions_page.dart`:

✅ همه actions موجود هستند:
- ✅ `add`, `view`, `edit`, `delete`, `draft`
- ✅ `export` ✅ (اضافه شده)
- ✅ `business`, `print`, `users`
- ✅ سایر actions...

### 4. `_getSectionTitle` و `_inferCurrentSectionKey`:

✅ همه بخش‌ها عنوان و شناسایی دارند:
- ✅ `reports` ✅ (اضافه شده)
- ✅ `fiscal_years` ✅ (اضافه شده)

---

## ✅ نتیجه نهایی

### همه دسترسی‌های استفاده شده در endpoint های اصلاح شده در UI موجود هستند ✅

1. ✅ **settings.business** - موجود در UI
2. ✅ **settings.print** - موجود در UI
3. ✅ **settings.users** - موجود در UI
4. ✅ **invoices.add/view/edit/delete/export** - همه موجود در UI
5. ✅ **products.add/view/edit/delete/export** - همه موجود در UI
6. ✅ **categories.add/view/edit/delete** - همه موجود در UI
7. ✅ **price_lists.add/view/edit/delete** - همه موجود در UI
8. ✅ **product_attributes.add/view/edit/delete** - همه موجود در UI
9. ✅ **warehouses.add/view/edit/delete** - همه موجود در UI
10. ✅ **chart_of_accounts.add/view/edit/delete** - همه موجود در UI
11. ✅ **reports.view/export** - موجود در UI (اضافه شده)
12. ✅ **fiscal_years.view** - موجود در UI (اضافه شده)

---

## 📝 تغییرات اعمال شده

### Backend:
1. ✅ همه endpoint های اصلاح شده dependency دارند
2. ✅ همه manual check ها حذف شدند
3. ✅ `fiscal_years.py` dependency اضافه شد

### Frontend:
1. ✅ بخش `reports` اضافه شد (view, export)
2. ✅ بخش `fiscal_years` اضافه شد (فقط view - چون endpoint add/edit/delete ندارد)
3. ✅ action `export` به `invoices` و `products` اضافه شد
4. ✅ همه بخش‌ها در `sectionConfigs` قرار گرفتند
5. ✅ همه actions در `_localizeAction` موجود هستند

---

## ✅ تأیید نهایی

**همه دسترسی‌های استفاده شده در endpoint های اصلاح شده در UI موجود هستند و قابل اعمال برای کاربران هستند.** ✅

**تاریخ بررسی**: 2025-01-XX

