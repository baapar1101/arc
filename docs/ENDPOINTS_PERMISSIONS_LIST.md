# لیست دقیق Endpoint های قابل تبدیل به دسترسی جزئی

این لیست شامل تمام endpoint هایی است که می‌توانند از `require_business_permission_dep` یا `require_business_permission_by_entity_dep` استفاده کنند.

---

## 📁 1. businesses.py - مدیریت کسب‌وکار

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 268 | PUT | `/{business_id}` | `@require_business_management()` | `settings` | `business` | ویرایش اطلاعات کسب‌وکار - باید به `require_business_access` + dependency تبدیل شود |
| 328 | POST | `/{business_id}/logo` | `@require_business_access` | `settings` | `print` | آپلود لوگو - باید dependency اضافه شود |
| 400 | GET | `/{business_id}/logo` | بدون decorator | `settings` | `view` | دریافت لوگو - باید `@require_business_access` + dependency اضافه شود |
| 426 | POST | `/{business_id}/stamp` | `@require_business_access` | `settings` | `print` | آپلود مهر/امضا - باید dependency اضافه شود |
| 497 | GET | `/{business_id}/stamp` | بدون decorator | `settings` | `view` | دریافت مهر/امضا - باید `@require_business_access` + dependency اضافه شود |
| 567 | GET | `/{business_id}/print-settings` | بدون decorator | `settings` | `view` | دریافت تنظیمات چاپ - باید `@require_business_access` + dependency اضافه شود |
| 589 | PUT | `/{business_id}/print-settings` | `@require_business_management()` | `settings` | `print` | ویرایش تنظیمات چاپ - باید به `require_business_access` + dependency تبدیل شود |

---

## 📁 2. business_users.py - مدیریت کاربران کسب‌وکار

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 102 | GET | `/{business_id}/users/{user_id}` | `@require_business_access` | `settings` | `users` یا `manage_users` | مشاهده جزئیات کاربر - الان manual check دارد |
| 227 | GET | `/{business_id}/users` | `@require_business_access` | `settings` | `users` یا `manage_users` | لیست کاربران - باید dependency اضافه شود |
| 370 | POST | `/{business_id}/users/add` | `@require_business_access` | `settings` | `users` یا `manage_users` | افزودن کاربر - باید dependency اضافه شود |
| 509 | PUT | `/{business_id}/users/{user_id}/permissions` | `@require_business_access` | `settings` | `users` یا `manage_users` | ویرایش دسترسی‌های کاربر - باید dependency اضافه شود |
| 579 | DELETE | `/{business_id}/users/{user_id}` | `@require_business_access` | `settings` | `users` یا `manage_users` | حذف کاربر - باید dependency اضافه شود |

**نکته**: در بخش `settings`، action می‌تواند `users` یا `manage_users` باشد. بررسی کنید کدام یک در سیستم استفاده می‌شود.

---

## 📁 3. invoices.py - فاکتورها

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 55 | POST | `/business/{business_id}` | `@require_business_access` | `invoices` | `add` | ایجاد فاکتور - باید dependency اضافه شود |
| 73 | GET | `/business/{business_id}/{invoice_id}/installments` | `@require_business_access` | `invoices` | `view` | دریافت اقساط فاکتور - باید dependency اضافه شود |
| 86 | POST | `/business/{business_id}/installments/search` | `@require_business_access` | `invoices` | `view` | جستجوی اقساط - باید dependency اضافه شود |
| 113 | POST | `/business/{business_id}/installments/export/excel` | `@require_business_access` | `invoices` | `export` | خروجی Excel اقساط - باید dependency اضافه شود |
| 139 | PUT | `/business/{business_id}/{invoice_id}` | `@require_business_access` | `invoices` | `edit` | ویرایش فاکتور - باید `require_business_permission_by_entity_dep` استفاده شود |
| 164 | DELETE | `/business/{business_id}/{invoice_id}` | `@require_business_access` + manual check | `invoices` | `delete` | **✅ الان dependency دارد** - `require_business_permission_dep("invoices", "delete")` |
| 199 | GET | `/business/{business_id}/{invoice_id}` | `@require_business_access` | `invoices` | `view` | دریافت فاکتور - باید `require_business_permission_by_entity_dep` استفاده شود |
| 215 | GET | `/business/{business_id}/{invoice_id}/pdf` | `@require_business_access` | `invoices` | `view` | PDF فاکتور - باید `require_business_permission_by_entity_dep` استفاده شود |
| 220+ | سایر endpoint های export/list | `@require_business_access` | `invoices` | `view` یا `export` | بسته به نوع endpoint |

**نکته**: endpoint هایی که `invoice_id` در path دارند باید از `require_business_permission_by_entity_dep` با مدل `Document` استفاده کنند.

---

## 📁 4. products.py - محصولات

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 42 | POST | `/business/{business_id}` | `@require_business_access` + manual check | `products` | `add` | **✅ الان manual check دارد** - باید به dependency تبدیل شود |
| 215 | POST | `/business/{business_id}/search` | `@require_business_access` + manual check | `products` | `view` | **✅ الان manual check دارد** - باید به dependency تبدیل شود |
| 239 | GET | `/business/{business_id}/{product_id}` | `@require_business_access` + manual check | `products` | `view` | **✅ الان manual check دارد** - باید به `require_business_permission_by_entity_dep` تبدیل شود |
| 256 | PUT | `/business/{business_id}/{product_id}` | `@require_business_access` + manual check | `products` | `edit` | **✅ الان manual check دارد** - باید به `require_business_permission_by_entity_dep` تبدیل شود |
| 457 | DELETE | `/business/{business_id}/{product_id}` | `@require_business_access` | `products` | `delete` | حذف محصول - باید `require_business_permission_by_entity_dep` اضافه شود |
| سایر | export/list endpoints | `@require_business_access` | `products` | `view` یا `export` | بسته به نوع endpoint |

**نکته**: endpoint های `products.py` الان manual check دارند. بهتر است به dependency تبدیل شوند.

---

## 📁 5. categories.py - دسته‌بندی‌ها

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 16 | POST | `/business/{business_id}` | `@require_business_access` | `categories` | `add` | ایجاد دسته‌بندی - باید dependency اضافه شود |
| 48 | GET | `/business/{business_id}` | `@require_business_access` | `categories` | `view` | لیست دسته‌بندی‌ها - باید dependency اضافه شود |
| 76 | PUT | `/business/{business_id}/{category_id}` | `@require_business_access` | `categories` | `edit` | ویرایش دسته‌بندی - باید `require_business_permission_by_entity_dep` استفاده شود |
| 105 | DELETE | `/business/{business_id}/{category_id}` | `@require_business_access` | `categories` | `delete` | حذف دسته‌بندی - باید `require_business_permission_by_entity_dep` استفاده شود |
| 133 | GET | `/business/{business_id}/{category_id}` | `@require_business_access` | `categories` | `view` | دریافت دسته‌بندی - باید `require_business_permission_by_entity_dep` استفاده شود |

---

## 📁 6. price_lists.py - لیست قیمت‌ها

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 33 | POST | `/business/{business_id}` | `@require_business_access` | `price_lists` | `add` | ایجاد لیست قیمت - باید dependency اضافه شود |
| 48 | GET | `/business/{business_id}` | `@require_business_access` | `price_lists` | `view` | لیست لیست قیمت‌ها - باید dependency اضافه شود |
| 69 | PUT | `/business/{business_id}/{price_list_id}` | `@require_business_access` | `price_lists` | `edit` | ویرایش لیست قیمت - باید `require_business_permission_by_entity_dep` استفاده شود |
| 86 | DELETE | `/business/{business_id}/{price_list_id}` | `@require_business_access` | `price_lists` | `delete` | حذف لیست قیمت - باید `require_business_permission_by_entity_dep` استفاده شود |
| 104 | GET | `/business/{business_id}/{price_list_id}` | `@require_business_access` | `price_lists` | `view` | دریافت لیست قیمت - باید `require_business_permission_by_entity_dep` استفاده شود |
| 119 | POST | `/business/{business_id}/{price_list_id}/products` | `@require_business_access` | `price_lists` | `edit` | ویرایش محصولات لیست قیمت - باید `require_business_permission_by_entity_dep` استفاده شود |
| 135 | POST | `/business/{business_id}/{price_list_id}/copy` | `@require_business_access` | `price_lists` | `add` | کپی لیست قیمت - باید `require_business_permission_by_entity_dep` استفاده شود |
| 152 | POST | `/business/{business_id}/bulk-update` | `@require_business_access` | `price_lists` | `edit` | به‌روزرسانی دسته‌ای - باید dependency اضافه شود |

---

## 📁 7. product_attributes.py - ویژگی‌های محصول

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 28 | POST | `/business/{business_id}` | `@require_business_access` | `product_attributes` | `add` | ایجاد ویژگی محصول - باید dependency اضافه شود |
| 47 | GET | `/business/{business_id}` | `@require_business_access` | `product_attributes` | `view` | لیست ویژگی‌های محصول - باید dependency اضافه شود |
| 72 | PUT | `/business/{business_id}/{attribute_id}` | `@require_business_access` | `product_attributes` | `edit` | ویرایش ویژگی محصول - باید `require_business_permission_by_entity_dep` استفاده شود |
| 89 | DELETE | `/business/{business_id}/{attribute_id}` | `@require_business_access` | `product_attributes` | `delete` | حذف ویژگی محصول - باید `require_business_permission_by_entity_dep` استفاده شود |
| 111 | GET | `/business/{business_id}/{attribute_id}` | `@require_business_access` | `product_attributes` | `view` | دریافت ویژگی محصول - باید `require_business_permission_by_entity_dep` استفاده شود |

---

## 📁 8. warehouses.py - انبارها

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 31 | POST | `/business/{business_id}` | `@require_business_access` | `warehouses` | `add` | ایجاد انبار - باید dependency اضافه شود |
| 46 | GET | `/business/{business_id}` | `@require_business_access` | `warehouses` | `view` | لیست انبارها - باید dependency اضافه شود |
| 60 | GET | `/business/{business_id}/{warehouse_id}` | `@require_business_access` | `warehouses` | `view` | دریافت انبار - باید `require_business_permission_by_entity_dep` استفاده شود |
| 77 | PUT | `/business/{business_id}/{warehouse_id}` | `@require_business_access` | `warehouses` | `edit` | ویرایش انبار - باید `require_business_permission_by_entity_dep` استفاده شود |
| 95 | DELETE | `/business/{business_id}/{warehouse_id}` | `@require_business_access` | `warehouses` | `delete` | حذف انبار - باید `require_business_permission_by_entity_dep` استفاده شود |
| 141 | POST | `/business/{business_id}/search` | `@require_business_access` | `warehouses` | `view` | جستجوی انبارها - باید dependency اضافه شود |

---

## 📁 9. warehouse_docs.py - اسناد انبار

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 103 | POST | `/business/{business_id}` | `@require_business_access` | `warehouse_transfers` | `add` | ایجاد سند انبار - باید dependency اضافه شود |
| 146 | POST | `/business/{business_id}/search` | `@require_business_access` | `warehouse_transfers` | `view` | جستجوی اسناد انبار - باید dependency اضافه شود |
| سایر | GET/PUT/DELETE | `/business/{business_id}/{doc_id}` | `@require_business_access` | `warehouse_transfers` | `view/edit/delete` | باید `require_business_permission_by_entity_dep` استفاده شود |

---

## 📁 10. accounts.py - حساب‌های کل

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 59 | POST | `/business/{business_id}` | `@require_business_access` | `chart_of_accounts` | `add` | ایجاد حساب - باید dependency اضافه شود |
| 101 | GET | `/business/{business_id}` | `@require_business_access` | `chart_of_accounts` | `view` | لیست حساب‌ها - باید dependency اضافه شود |
| 133 | GET | `/business/{business_id}/{account_id}` | `@require_business_access` | `chart_of_accounts` | `view` | دریافت حساب - باید `require_business_permission_by_entity_dep` استفاده شود |
| 169 | PUT | `/business/{business_id}/{account_id}` | `@require_business_access` | `chart_of_accounts` | `edit` | ویرایش حساب - باید `require_business_permission_by_entity_dep` استفاده شود |
| 234 | DELETE | `/business/{business_id}/{account_id}` | `@require_business_access` | `chart_of_accounts` | `delete` | حذف حساب - باید `require_business_permission_by_entity_dep` استفاده شود |

---

## 📁 11. fiscal_years.py - سال‌های مالی

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 16 | GET | `/business/{business_id}` | `@require_business_access` | `settings` | `view` | لیست سال‌های مالی - باید dependency اضافه شود |
| 46 | POST | `/business/{business_id}` | `@require_business_access` | `settings` | `edit` | ایجاد سال مالی - باید dependency اضافه شود |

---

## 📁 12. boms.py - BOM (فهرست مواد)

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 29 | POST | `/business/{business_id}` | `@require_business_access` + manual check | `inventory` | `write` | **✅ الان manual check دارد** - باید به dependency تبدیل شود |
| 44 | GET | `/business/{business_id}` | `@require_business_access` + manual check | `inventory` | `view` | **✅ الان manual check دارد** - باید به dependency تبدیل شود |
| سایر | GET/PUT/DELETE | `/business/{business_id}/{bom_id}` | `@require_business_access` | `inventory` | `view/edit/delete` | باید `require_business_permission_by_entity_dep` استفاده شود |

---

## 📁 13. expense_income.py - هزینه‌ها و درآمدها

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 34 | POST | `/business/{business_id}` | `@require_business_access` + **dependency** | `expenses_income` | `add` | **✅ الان dependency دارد** |
| 56 | POST | `/business/{business_id}/search` | `@require_business_access` | `expenses_income` | `view` | جستجو - باید dependency اضافه شود |
| 141 | PUT | `/{document_id}` | + **dependency** | `expenses_income` | `edit` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |
| 163 | DELETE | `/{document_id}` | + **dependency** | `expenses_income` | `delete` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |
| سایر | export/list | `@require_business_access` | `expenses_income` | `view` یا `export` | بسته به نوع endpoint |

---

## 📁 14. documents.py - اسناد حسابداری

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 46 | POST | `/business/{business_id}` | `@require_business_access` | `accounting_documents` | `add` | ایجاد سند حسابداری - باید dependency اضافه شود |
| 112 | POST | `/business/{business_id}/search` | `@require_business_access` | `accounting_documents` | `view` | جستجوی اسناد - باید dependency اضافه شود |
| 410 | GET | `/{document_id}` | `@require_business_access` | `accounting_documents` | `view` | دریافت سند - باید `require_business_permission_by_entity_dep` استفاده شود |
| 434 | PUT | `/{document_id}` | `@require_business_access` | `accounting_documents` | `edit` | ویرایش سند - باید `require_business_permission_by_entity_dep` استفاده شود |
| 647 | POST | `/business/{business_id}` | `@require_business_access` + **dependency** | `accounting_documents` | `add` | **✅ الان dependency دارد** |
| 737 | PUT | `/{document_id}` | + **dependency** | `accounting_documents` | `edit` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |
| سایر | export/delete | `@require_business_access` | `accounting_documents` | `export/delete` | بسته به نوع endpoint |

---

## 📁 15. opening_balance.py - مانده اولیه

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 57 | PUT | `/{business_id}` | `@require_business_access` + **dependency** | `opening_balance` | `edit` | **✅ الان dependency دارد** |
| 74 | POST | `/{business_id}/preview` | `@require_business_access` + **dependency** | `opening_balance` | `edit` | **✅ الان dependency دارد** |

---

## 📁 16. receipts_payments.py - دریافت/پرداخت

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 44 | POST | `/business/{business_id}` | `@require_business_access` | `people_transactions` | `add` | ایجاد دریافت/پرداخت - باید dependency اضافه شود |
| 102 | POST | `/business/{business_id}/search` | `@require_business_access` | `people_transactions` | `view` | جستجو - باید dependency اضافه شود |
| 109 | POST | `/business/{business_id}` | `@require_business_access` + **dependency** | `people_transactions` | `add` | **✅ الان dependency دارد** |
| 202 | DELETE | `/{document_id}` | + **dependency** | `people_transactions` | `delete` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |
| 240 | PUT | `/{document_id}` | + **dependency** | `people_transactions` | `edit` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |
| سایر | export/list | `@require_business_access` | `people_transactions` | `view` یا `export` | بسته به نوع endpoint |

---

## 📁 17. transfers.py - انتقالات

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 38 | POST | `/business/{business_id}` | `@require_business_access` | `transfers` | `add` | ایجاد انتقال - باید dependency اضافه شود |
| 83 | POST | `/business/{business_id}/search` | `@require_business_access` | `transfers` | `view` | جستجو - باید dependency اضافه شود |
| 90 | POST | `/business/{business_id}` | `@require_business_access` + **dependency** | `transfers` | `add` | **✅ الان dependency دارد** |
| 385 | DELETE | `/{document_id}` | + **dependency** | `transfers` | `delete` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |
| 409 | PUT | `/{document_id}` | + **dependency** | `transfers` | `edit` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |

---

## 📁 18. checks.py - چک‌ها

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 54 | POST | `/business/{business_id}` | `@require_business_access` | `checks` | `add` | ایجاد چک - باید dependency اضافه شود |
| 98 | POST | `/business/{business_id}/search` | `@require_business_access` | `checks` | `view` | جستجو - باید dependency اضافه شود |
| 105 | POST | `/business/{business_id}` | `@require_business_access` + **dependency** | `checks` | `add` | **✅ الان dependency دارد** |
| 356 | PUT | `/{check_id}` | + **dependency** | `checks` | `edit` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |
| 386 | DELETE | `/{check_id}` | + **dependency** | `checks` | `delete` | **✅ الان dependency دارد** - `require_business_permission_by_entity_dep` |

---

## 📁 19. business_dashboard.py - داشبورد

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 79 | GET | `/{business_id}/summary` | `@require_business_access` | `reports` | `view` | خلاصه کسب‌وکار - باید dependency اضافه شود |
| 141 | GET | `/{business_id}/stats` | `@require_business_access` | `reports` | `view` | آمار کسب‌وکار - باید dependency اضافه شود |
| 192 | POST | `/{business_id}/info-with-permissions` | `@require_business_access` | `settings` | `view` | اطلاعات + دسترسی‌ها - باید dependency اضافه شود |
| 253 | سایر endpoint ها | `@require_business_access` | `reports` | `view` | سایر endpoint های dashboard - باید dependency اضافه شود |

---

## 📁 20. report_templates.py - قالب‌های گزارش

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 20 | GET | `/business/{business_id}` | `@require_business_access` | `settings` | `view` | لیست قالب‌های گزارش - باید dependency اضافه شود |
| 67 | POST | `/business/{business_id}` | `@require_business_access` | `settings` | `edit` | ایجاد قالب - باید dependency اضافه شود |
| 109 | GET | `/business/{business_id}/{template_id}` | `@require_business_access` | `settings` | `view` | دریافت قالب - باید `require_business_permission_by_entity_dep` استفاده شود |
| 129 | PUT | `/business/{business_id}/{template_id}` | `@require_business_access` | `settings` | `edit` | ویرایش قالب - باید `require_business_permission_by_entity_dep` استفاده شود |
| سایر | DELETE/Publish | `@require_business_access` | `settings` | `edit` یا `delete` | بسته به عملیات |

---

## 📁 21. kardex.py - کاردکس

| خط | متد | مسیر | وضعیت فعلی | Section پیشنهادی | Action پیشنهادی | توضیحات |
|----|-----|------|------------|------------------|-----------------|---------|
| 25 | POST | `/business/{business_id}` | `@require_business_access` | `reports` | `view` | کاردکس محصول - باید dependency اضافه شود |
| 87 | POST | `/business/{business_id}/export/excel` | `@require_business_access` | `reports` | `export` | خروجی Excel کاردکس - باید dependency اضافه شود |
| 178 | POST | `/business/{business_id}/export/pdf` | `@require_business_access` | `reports` | `export` | خروجی PDF کاردکس - باید dependency اضافه شود |

---

## 📋 خلاصه آماری

### ✅ Endpoint هایی که الان dependency دارند:
- **cash_registers.py**: اکثر endpoint ها ✅
- **petty_cash.py**: اکثر endpoint ها ✅
- **bank_accounts.py**: اکثر endpoint ها ✅
- **persons.py**: اکثر endpoint ها ✅
- **invoices.py**: فقط endpoint حذف ✅
- **expense_income.py**: endpoint های اصلی ✅
- **documents.py**: endpoint های اصلی ✅
- **receipts_payments.py**: endpoint های اصلی ✅
- **transfers.py**: endpoint های اصلی ✅
- **checks.py**: endpoint های اصلی ✅
- **opening_balance.py**: همه endpoint ها ✅

### ❌ Endpoint هایی که نیاز به dependency دارند:
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
- **boms.py**: ~8 endpoint (manual check دارند)
- **business_dashboard.py**: ~10 endpoint
- **report_templates.py**: ~9 endpoint
- **kardex.py**: 3 endpoint

**جمع کل endpoint های نیازمند به dependency: ~120 endpoint**

---

## 🔧 نحوه استفاده

### برای endpoint هایی که `business_id` در path دارند:
```python
@require_business_access("business_id")
async def endpoint_name(
    request: Request,
    business_id: int,
    ...
    _: None = Depends(require_business_permission_dep("section", "action")),
):
    ...
```

### برای endpoint هایی که entity ID در path دارند (مثل `product_id`, `invoice_id`):
```python
@require_business_access("business_id")  # اگر business_id در path باشد
async def endpoint_name(
    request: Request,
    entity_id: int,  # مثل product_id, invoice_id
    ...
    _: None = Depends(require_business_permission_by_entity_dep(
        "section",           # مثل "products", "invoices"
        "action",            # مثل "edit", "delete", "view"
        EntityModel,         # مثل Product, Document
        "entity_id_param"    # مثل "product_id", "invoice_id"
    )),
):
    ...
```

---

## 📝 اولویت‌بندی

### اولویت بالا (امنیت حساس):
1. **business_users.py** - مدیریت کاربران (`settings.users`)
2. **businesses.py** - تنظیمات کسب‌وکار (`settings.business`, `settings.print`)
3. **invoices.py** - فاکتورها (`invoices.*`)

### اولویت متوسط:
4. **products.py** - محصولات (`products.*`)
5. **accounts.py** - حساب‌ها (`chart_of_accounts.*`)
6. **warehouses.py** - انبارها (`warehouses.*`)

### اولویت پایین:
7. سایر endpoint ها

---

**تاریخ تهیه**: 2025-01-XX
**نسخه**: 1.0

