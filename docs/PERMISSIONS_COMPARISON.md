# مقایسه دسترسی‌های Endpoint ها با UI

این فایل شامل مقایسه دقیق دسترسی‌هایی است که در endpoint ها استفاده شده با آنچه در UI موجود است.

---

## ✅ دسترسی‌های استفاده شده در Endpoint های اصلاح شده

### 1. businesses.py
**استفاده شده:**
- ✅ `settings.business` - ویرایش کسب‌وکار
- ✅ `settings.print` - آپلود/دریافت لوگو و مهر، تنظیمات چاپ

**موجود در UI:**
- ✅ `settings.business` ✅
- ✅ `settings.print` ✅

**نتیجه**: ✅ همه موجود هستند

---

### 2. business_users.py
**استفاده شده:**
- ✅ `settings.users` - تمام endpoint ها

**موجود در UI:**
- ✅ `settings.users` ✅

**نتیجه**: ✅ موجود است

---

### 3. invoices.py
**استفاده شده:**
- ✅ `invoices.add` - POST /business/{business_id}
- ✅ `invoices.view` - GET /business/{business_id}/{invoice_id}, GET PDF, GET installments, POST search
- ✅ `invoices.edit` - PUT /business/{business_id}/{invoice_id}
- ✅ `invoices.delete` - DELETE /business/{business_id}/{invoice_id}
- ✅ `invoices.export` - POST /business/{business_id}/installments/export/excel

**موجود در UI:**
- ✅ `invoices.add` ✅
- ✅ `invoices.view` ✅
- ✅ `invoices.edit` ✅
- ✅ `invoices.delete` ✅
- ✅ `invoices.export` ✅ (اضافه شده)

**نتیجه**: ✅ همه موجود هستند

---

### 4. products.py
**استفاده شده:**
- ✅ `products.add` - POST /business/{business_id}
- ✅ `products.view` - POST /business/{business_id}/search, GET /business/{business_id}/{product_id}
- ✅ `products.edit` - PUT /business/{business_id}/{product_id}
- ✅ `products.delete` - DELETE /business/{business_id}/{product_id}, POST /business/{business_id}/bulk-delete
- ✅ `products.export` - POST /business/{business_id}/export/excel, POST /business/{business_id}/export/pdf
- ✅ `reports.view` - POST /businesses/{business_id}/reports/item-movements, POST /businesses/{business_id}/reports/sales-by-product, POST /businesses/{business_id}/reports/inventory-kardex
- ✅ `reports.export` - POST /businesses/{business_id}/reports/*/export/excel

**موجود در UI:**
- ✅ `products.add` ✅
- ✅ `products.view` ✅
- ✅ `products.edit` ✅
- ✅ `products.delete` ✅
- ✅ `products.export` ✅ (اضافه شده)
- ✅ `reports.view` ✅ (اضافه شده)
- ✅ `reports.export` ✅ (اضافه شده)

**نتیجه**: ✅ همه موجود هستند

---

### 5. categories.py
**استفاده شده:**
- ✅ `categories.add` - POST /business/{business_id}
- ✅ `categories.view` - POST /business/{business_id}/tree, POST /business/{business_id}/search
- ✅ `categories.edit` - POST /business/{business_id}/update, POST /business/{business_id}/move
- ✅ `categories.delete` - POST /business/{business_id}/delete

**موجود در UI:**
- ✅ همه موجود هستند

**نتیجه**: ✅ همه موجود هستند

---

### 6. price_lists.py
**استفاده شده:**
- ✅ `price_lists.add` - POST /business/{business_id}
- ✅ `price_lists.view` - POST /business/{business_id}/search, GET /business/{business_id}/{price_list_id}, GET /business/{business_id}/{price_list_id}/items
- ✅ `price_lists.edit` - PUT /business/{business_id}/{price_list_id}, POST /business/{business_id}/{price_list_id}/items
- ✅ `price_lists.delete` - DELETE /business/{business_id}/{price_list_id}, DELETE /business/{business_id}/items/{item_id}

**موجود در UI:**
- ✅ همه موجود هستند

**نتیجه**: ✅ همه موجود هستند

---

### 7. product_attributes.py
**استفاده شده:**
- ✅ `product_attributes.add` - POST /business/{business_id}
- ✅ `product_attributes.view` - POST /business/{business_id}/search, GET /business/{business_id}/{attribute_id}
- ✅ `product_attributes.edit` - PUT /business/{business_id}/{attribute_id}
- ✅ `product_attributes.delete` - DELETE /business/{business_id}/{attribute_id}

**موجود در UI:**
- ✅ همه موجود هستند

**نتیجه**: ✅ همه موجود هستند

---

### 8. warehouses.py
**استفاده شده:**
- ✅ `warehouses.add` - POST /business/{business_id}
- ✅ `warehouses.view` - GET /business/{business_id}, GET /business/{business_id}/{warehouse_id}, POST /business/{business_id}/query, POST /business/{business_id}/stock-report
- ✅ `warehouses.edit` - PUT /business/{business_id}/{warehouse_id}
- ✅ `warehouses.delete` - DELETE /business/{business_id}/{warehouse_id}

**موجود در UI:**
- ✅ همه موجود هستند

**نتیجه**: ✅ همه موجود هستند

---

### 9. accounts.py (chart_of_accounts)
**استفاده شده:**
- ✅ `chart_of_accounts.view` - GET /business/{business_id}/tree, GET /business/{business_id}, GET /business/{business_id}/account/{account_id}, POST /business/{business_id}
- ✅ `chart_of_accounts.add` - POST /business/{business_id}/create
- ✅ `chart_of_accounts.edit` - PUT /account/{account_id}
- ✅ `chart_of_accounts.delete` - DELETE /account/{account_id}

**موجود در UI:**
- ✅ همه موجود هستند

**نتیجه**: ✅ همه موجود هستند

---

### 10. fiscal_years.py
**استفاده شده:**
- ✅ `fiscal_years.view` - GET /business/{business_id}/fiscal-years, GET /business/{business_id}/fiscal-years/current
- ⚠️ `fiscal_years.add` - **وجود ندارد** (endpoint ندارد)
- ⚠️ `fiscal_years.edit` - **وجود ندارد** (endpoint ندارد)
- ⚠️ `fiscal_years.delete` - **وجود ندارد** (endpoint ندارد)

**موجود در UI:**
- ✅ `fiscal_years.view` ✅ (اضافه شده)
- ✅ `fiscal_years.add` ✅ (اضافه شده - اما endpoint ندارد)
- ✅ `fiscal_years.edit` ✅ (اضافه شده - اما endpoint ندارد)
- ✅ `fiscal_years.delete` ✅ (اضافه شده - اما endpoint ندارد)

**نتیجه**: ⚠️ actions در UI اضافه شده اما endpoint های مربوطه وجود ندارند. باید endpoint ها را اضافه کنیم یا actions را از UI حذف کنیم.

---

## 📊 خلاصه نهایی

### دسترسی‌های استفاده شده در endpoint ها و موجود در UI:

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
12. ⚠️ **fiscal_years.view** - موجود در UI (اضافه شده)
13. ⚠️ **fiscal_years.add/edit/delete** - در UI موجود است اما endpoint ندارد

---

## ⚠️ نکات مهم

1. **fiscal_years**: endpoint های add/edit/delete وجود ندارند، اما در UI اضافه شده‌اند. باید:
   - یا endpoint ها را اضافه کنیم
   - یا actions را از UI حذف کنیم (فقط view نگه داریم)

2. **همه دسترسی‌های استفاده شده در endpoint های اصلاح شده در UI موجود هستند** ✅

3. **action `export`** برای invoices و products اضافه شده است ✅

4. **بخش `reports`** اضافه شده است ✅

---

**تاریخ بررسی**: 2025-01-XX

