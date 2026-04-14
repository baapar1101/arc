# بررسی تطبیق دسترسی‌های UI با Endpoint ها

این فایل شامل بررسی کامل دسترسی‌هایی است که در endpoint ها استفاده شده و مقایسه با آنچه در UI موجود است.

---

## ✅ دسترسی‌های استفاده شده در Endpoint ها

### 1. businesses.py
- ✅ `settings.business` - ویرایش کسب‌وکار
- ✅ `settings.print` - آپلود/دریافت لوگو و مهر، تنظیمات چاپ

**در UI موجود**: ✅ `settings.business` و `settings.print` موجود هستند

---

### 2. business_users.py
- ✅ `settings.users` - مدیریت کاربران (get, add, update, delete)

**در UI موجود**: ✅ `settings.users` موجود است

---

### 3. invoices.py
- ✅ `invoices.add` - ایجاد فاکتور
- ✅ `invoices.view` - مشاهده فاکتور
- ✅ `invoices.edit` - ویرایش فاکتور
- ✅ `invoices.delete` - حذف فاکتور
- ✅ `invoices.export` - خروجی Excel/PDF

**در UI موجود**: 
- ✅ `invoices.add` موجود است
- ✅ `invoices.view` موجود است
- ✅ `invoices.edit` موجود است
- ✅ `invoices.delete` موجود است
- ✅ `invoices.export` موجود است (اضافه شده)

---

### 4. products.py
- ✅ `products.add` - ایجاد محصول
- ✅ `products.view` - مشاهده محصول
- ✅ `products.edit` - ویرایش محصول
- ✅ `products.delete` - حذف محصول
- ✅ `products.export` - خروجی Excel/PDF
- ✅ `reports.view` - گزارش گردش کالا، فروش به تفکیک کالا، کاردکس موجودی
- ✅ `reports.export` - خروجی Excel گزارش‌ها

**در UI موجود**:
- ✅ `products.add` موجود است
- ✅ `products.view` موجود است
- ✅ `products.edit` موجود است
- ✅ `products.delete` موجود است
- ✅ `products.export` موجود است (اضافه شده)
- ✅ `reports.view` موجود است (اضافه شده)
- ✅ `reports.export` موجود است (اضافه شده)

---

### 5. categories.py
- ✅ `categories.add` - ایجاد دسته‌بندی
- ✅ `categories.view` - مشاهده دسته‌بندی
- ✅ `categories.edit` - ویرایش دسته‌بندی
- ✅ `categories.delete` - حذف دسته‌بندی

**در UI موجود**: 
- ✅ همه موجود هستند

---

### 6. price_lists.py
- ✅ `price_lists.add` - ایجاد لیست قیمت
- ✅ `price_lists.view` - مشاهده لیست قیمت
- ✅ `price_lists.edit` - ویرایش لیست قیمت
- ✅ `price_lists.delete` - حذف لیست قیمت

**در UI موجود**: 
- ✅ همه موجود هستند

---

### 7. product_attributes.py
- ✅ `product_attributes.add` - ایجاد ویژگی محصول
- ✅ `product_attributes.view` - مشاهده ویژگی محصول
- ✅ `product_attributes.edit` - ویرایش ویژگی محصول
- ✅ `product_attributes.delete` - حذف ویژگی محصول

**در UI موجود**: 
- ✅ همه موجود هستند

---

### 8. warehouses.py
- ✅ `warehouses.add` - ایجاد انبار
- ✅ `warehouses.view` - مشاهده انبار
- ✅ `warehouses.edit` - ویرایش انبار
- ✅ `warehouses.delete` - حذف انبار

**در UI موجود**: 
- ✅ همه موجود هستند

---

### 9. accounts.py (chart_of_accounts)
- ✅ `chart_of_accounts.add` - ایجاد حساب
- ✅ `chart_of_accounts.view` - مشاهده حساب
- ✅ `chart_of_accounts.edit` - ویرایش حساب
- ✅ `chart_of_accounts.delete` - حذف حساب

**در UI موجود**: 
- ✅ همه موجود هستند

---

### 10. fiscal_years.py (نیاز به بررسی)
- ✅ `fiscal_years.view` - مشاهده سال‌های مالی
- ✅ `fiscal_years.add` - ایجاد سال مالی (نیاز به بررسی وجود endpoint)
- ✅ `fiscal_years.edit` - ویرایش سال مالی (نیاز به بررسی وجود endpoint)
- ✅ `fiscal_years.delete` - حذف سال مالی (نیاز به بررسی وجود endpoint)

**در UI موجود**: 
- ✅ `fiscal_years.view` موجود است (اضافه شده)
- ✅ `fiscal_years.add` موجود است (اضافه شده)
- ✅ `fiscal_years.edit` موجود است (اضافه شده)
- ✅ `fiscal_years.delete` موجود است (اضافه شده)

**⚠️ نکته**: باید بررسی شود که endpoint های add/edit/delete برای fiscal_years وجود دارند یا نه.

---

## 📋 لیست کامل دسترسی‌های موجود در UI

### بخش‌های موجود در `_getAllPermissions`:

1. ✅ `people` - add, view, edit, delete
2. ✅ `people_transactions` - add, view, edit, delete, draft
3. ✅ `products` - add, view, edit, delete, **export** ✅
4. ✅ `price_lists` - add, view, edit, delete
5. ✅ `categories` - add, view, edit, delete
6. ✅ `product_attributes` - add, view, edit, delete
7. ✅ `bank_accounts` - add, view, edit, delete
8. ✅ `cash` - add, view, edit, delete
9. ✅ `petty_cash` - add, view, edit, delete
10. ✅ `checks` - add, view, edit, delete, collect, transfer, return
11. ✅ `wallet` - view, charge
12. ✅ `transfers` - add, view, edit, delete, draft
13. ✅ `invoices` - add, view, edit, delete, draft, **export** ✅
14. ✅ `expenses_income` - add, view, edit, delete, draft
15. ✅ `accounting_documents` - add, view, edit, delete, draft
16. ✅ `chart_of_accounts` - add, view, edit, delete
17. ✅ `opening_balance` - view, edit
18. ✅ `warehouses` - add, view, edit, delete
19. ✅ `warehouse_transfers` - add, view, edit, delete, draft
20. ✅ `settings` - business, print, history, users
21. ✅ `storage` - view, delete
22. ✅ `sms` - history, templates
23. ✅ `marketplace` - view, buy, invoices
24. ✅ `reports` - **view, export** ✅ (اضافه شده)
25. ✅ `fiscal_years` - **view, add, edit, delete** ✅ (اضافه شده)

---

## ✅ بخش‌های موجود در `sectionConfigs`

1. ✅ **اشخاص** - people, people_transactions
2. ✅ **کالا و خدمات** - products, price_lists, categories, product_attributes
3. ✅ **بانکداری** - bank_accounts, cash, petty_cash, checks, wallet, transfers
4. ✅ **فاکتورها و هزینه‌ها** - invoices, expenses_income
5. ✅ **حسابداری** - accounting_documents, chart_of_accounts, opening_balance
6. ✅ **انبارداری** - warehouses, warehouse_transfers
7. ✅ **گزارش‌ها** - reports ✅ (اضافه شده)
8. ✅ **تنظیمات** - settings, storage, sms, marketplace, fiscal_years ✅ (اضافه شده)

---

## ✅ Action های موجود در `_localizeAction`

- ✅ `add` - اضافه کردن
- ✅ `view` - مشاهده
- ✅ `edit` - ویرایش
- ✅ `delete` - حذف
- ✅ `draft` - پیش‌نویس
- ✅ `export` - خروجی ✅ (اضافه شده)
- ✅ `buy` - خرید
- ✅ `invoices` - فاکتورها
- ✅ `templates` - قالب‌ها
- ✅ `history` - تاریخچه
- ✅ `print` - چاپ
- ✅ `users` - کاربران
- ✅ `business` - کسب‌وکار
- ✅ `collect` - وصول
- ✅ `transfer` - انتقال
- ✅ `charge` - شارژ
- ✅ `return` - برگشت

---

## ✅ نتیجه نهایی

### همه دسترسی‌های استفاده شده در endpoint ها در UI موجود هستند:

1. ✅ **settings.business** - موجود در UI
2. ✅ **settings.print** - موجود در UI
3. ✅ **settings.users** - موجود در UI
4. ✅ **invoices.*** - همه actions موجود هستند (شامل export)
5. ✅ **products.*** - همه actions موجود هستند (شامل export)
6. ✅ **categories.*** - همه actions موجود هستند
7. ✅ **price_lists.*** - همه actions موجود هستند
8. ✅ **product_attributes.*** - همه actions موجود هستند
9. ✅ **warehouses.*** - همه actions موجود هستند
10. ✅ **chart_of_accounts.*** - همه actions موجود هستند
11. ✅ **reports.view** - موجود در UI (اضافه شده)
12. ✅ **reports.export** - موجود در UI (اضافه شده)
13. ✅ **fiscal_years.*** - همه actions موجود هستند (اضافه شده)

---

## ✅ خلاصه

**همه دسترسی‌های استفاده شده در endpoint های اصلاح شده در UI موجود هستند و می‌توانند به کاربران اختصاص داده شوند.**

**تاریخ بررسی**: 2025-01-XX

