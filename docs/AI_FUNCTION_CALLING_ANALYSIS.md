# تحلیل Function Calling و Endpoint های سیستم

## 📋 Function های فعلی AI

### ✅ Function های موجود (5 function):

1. **get_business_info** (category: business)
   - دریافت اطلاعات کامل کسب‌وکار
   - دسترسی: USER, BUSINESS_OWNER, OPERATOR, ADMIN
   - Permission: ندارد

2. **search_invoices** (category: invoices)
   - جستجو و فیلتر فاکتورها
   - فیلترها: تاریخ، نوع، مشتری، سال مالی
   - دسترسی: USER, BUSINESS_OWNER, OPERATOR, ADMIN
   - Permission: invoices.read

3. **search_products** (category: products)
   - جستجو در محصولات و کالاها
   - فیلترها: نام، کد، دسته‌بندی، نوع
   - دسترسی: USER, BUSINESS_OWNER, OPERATOR, ADMIN
   - Permission: inventory.read

4. **get_product_info** (category: products)
   - دریافت اطلاعات کامل یک محصول
   - دسترسی: USER, BUSINESS_OWNER, OPERATOR, ADMIN
   - Permission: inventory.read

5. **get_customer_info** (category: persons)
   - دریافت اطلاعات مشتری/تامین‌کننده
   - دسترسی: USER, BUSINESS_OWNER, OPERATOR, ADMIN
   - Permission: persons.read

6. **get_financial_summary** (category: financial)
   - دریافت خلاصه مالی کسب‌وکار
   - دسترسی: USER, BUSINESS_OWNER, ADMIN
   - Permission: reports.read

---

## 🌐 Endpoint های موجود در سیستم

### 📦 Products & Inventory (موجود)
- ✅ `GET /api/v1/products` - لیست محصولات
- ✅ `GET /api/v1/products/{id}` - جزئیات محصول
- ✅ `POST /api/v1/products` - ایجاد محصول
- ✅ `PUT /api/v1/products/{id}` - ویرایش محصول
- ✅ `DELETE /api/v1/products/{id}` - حذف محصول
- ✅ `GET /api/v1/warehouses` - لیست انبارها
- ✅ `GET /api/v1/warehouse-docs` - اسناد انبار
- ✅ `GET /api/v1/boms` - Bill of Materials
- ✅ `GET /api/v1/kardex` - کاردکس
- ✅ `GET /api/v1/categories` - دسته‌بندی‌ها
- ✅ `GET /api/v1/price-lists` - لیست قیمت‌ها

### 📄 Invoices & Documents (موجود)
- ✅ `GET /api/v1/invoices` - لیست فاکتورها
- ✅ `POST /api/v1/invoices` - ایجاد فاکتور
- ✅ `PUT /api/v1/invoices/{id}` - ویرایش فاکتور
- ✅ `DELETE /api/v1/invoices/{id}` - حذف فاکتور
- ✅ `GET /api/v1/documents` - لیست اسناد
- ✅ `GET /api/v1/invoices/installments` - اقساط فاکتورها

### 👥 Persons & Customers (موجود)
- ✅ `GET /api/v1/persons` - لیست اشخاص
- ✅ `GET /api/v1/persons/{id}` - جزئیات شخص
- ✅ `POST /api/v1/persons` - ایجاد شخص
- ✅ `PUT /api/v1/persons/{id}` - ویرایش شخص
- ✅ `DELETE /api/v1/persons/{id}` - حذف شخص
- ✅ `GET /api/v1/customers` - لیست مشتریان

### 💰 Financial Operations (موجود)
- ✅ `GET /api/v1/receipts-payments` - دریافت/پرداخت‌ها
- ✅ `POST /api/v1/receipts-payments` - ایجاد دریافت/پرداخت
- ✅ `GET /api/v1/transfers` - انتقالات
- ✅ `POST /api/v1/transfers` - ایجاد انتقال
- ✅ `GET /api/v1/expense-income` - هزینه/درآمد
- ✅ `POST /api/v1/expense-income` - ایجاد هزینه/درآمد
- ✅ `GET /api/v1/bank-accounts` - حساب‌های بانکی
- ✅ `GET /api/v1/cash-registers` - صندوق‌ها
- ✅ `GET /api/v1/petty-cash` - صندوق خرد
- ✅ `GET /api/v1/accounts` - حساب‌های کل
- ✅ `GET /api/v1/fiscal-years` - سال‌های مالی

### 📊 Reports & Analytics (موجود)
- ✅ `GET /api/v1/business-dashboard` - داشبورد کسب‌وکار
- ✅ `GET /api/v1/report-templates` - قالب‌های گزارش
- ✅ `GET /api/v1/persons/debtors` - بدهکاران
- ✅ `GET /api/v1/persons/creditors` - بستانکاران
- ✅ `GET /api/v1/persons/transactions` - تراکنش‌های اشخاص

### 🔧 Other Services (موجود)
- ✅ `GET /api/v1/wallet` - کیف پول
- ✅ `GET /api/v1/checks` - چک‌ها
- ✅ `GET /api/v1/currencies` - ارزها
- ✅ `GET /api/v1/tax-units` - واحدهای مالیاتی
- ✅ `GET /api/v1/tax-types` - انواع مالیات

---

## 🎯 پیشنهاد Function های مهم برای AI (اولویت بالا)

### 1. **Function های خواندن (Read Operations) - اولویت بالا**

#### 1.1. Search Persons (جستجوی اشخاص)
```python
name: "search_persons"
description: "جستجو در مشتریان و تامین‌کنندگان بر اساس نام، کد، تلفن و فیلترهای دیگر"
parameters:
  - search (string, optional): متن جستجو
  - person_type (string, optional): "customer" | "supplier" | "both"
  - city (string, optional): شهر
  - fiscal_year_id (integer, optional): سال مالی
```

#### 1.2. Get Invoice Details (جزئیات فاکتور)
```python
name: "get_invoice_details"
description: "دریافت جزئیات کامل یک فاکتور شامل اقلام، مالیات و پرداخت‌ها"
parameters:
  - invoice_id (integer, required): شناسه فاکتور
```

#### 1.3. Get Inventory Status (وضعیت موجودی)
```python
name: "get_inventory_status"
description: "دریافت وضعیت موجودی محصولات در انبارها"
parameters:
  - product_id (integer, optional): شناسه محصول (اگر مشخص نشود، لیست تمام محصولات)
  - warehouse_id (integer, optional): شناسه انبار
```

#### 1.4. Get Person Balance (موجودی شخص)
```python
name: "get_person_balance"
description: "دریافت موجودی و بدهی/بستانکاری یک مشتری یا تامین‌کننده"
parameters:
  - person_id (integer, required): شناسه شخص
  - fiscal_year_id (integer, optional): سال مالی
```

#### 1.5. Search Receipts Payments (جستجوی دریافت/پرداخت‌ها)
```python
name: "search_receipts_payments"
description: "جستجو در دریافت/پرداخت‌ها بر اساس تاریخ، نوع، شخص و فیلترهای دیگر"
parameters:
  - from_date (string, optional): تاریخ شروع
  - to_date (string, optional): تاریخ پایان
  - person_id (integer, optional): شناسه شخص
  - type (string, optional): "receipt" | "payment"
  - account_type (string, optional): "bank" | "cash" | "petty_cash"
```

#### 1.6. Get Financial Reports (گزارش‌های مالی)
```python
name: "get_debtors_report"
description: "گزارش بدهکاران با جزئیات بدهی و تاریخچه"
parameters:
  - fiscal_year_id (integer, optional): سال مالی
  - min_balance (number, optional): حداقل بدهی
```

```python
name: "get_creditors_report"
description: "گزارش بستانکاران با جزئیات بستانکاری و تاریخچه"
parameters:
  - fiscal_year_id (integer, optional): سال مالی
  - min_balance (number, optional): حداقل بستانکاری
```

#### 1.7. Get Product Kardex (کاردکس محصول)
```python
name: "get_product_kardex"
description: "دریافت کاردکس (گردش موجودی) یک محصول در انبار"
parameters:
  - product_id (integer, required): شناسه محصول
  - warehouse_id (integer, optional): شناسه انبار
  - from_date (string, optional): تاریخ شروع
  - to_date (string, optional): تاریخ پایان
```

---

### 2. **Function های نوشتن (Write Operations) - اولویت متوسط**

#### 2.1. Create Person (ایجاد شخص)
```python
name: "create_person"
description: "ایجاد یک مشتری یا تامین‌کننده جدید"
parameters:
  - name (string, required): نام
  - person_type (string, required): "customer" | "supplier"
  - phone (string, optional): تلفن
  - email (string, optional): ایمیل
  - address (string, optional): آدرس
  - tax_id (string, optional): شناسه ملی/کد اقتصادی
```

#### 2.2. Create Invoice (ایجاد فاکتور)
```python
name: "create_invoice"
description: "ایجاد یک فاکتور جدید (فروش، خرید و غیره)"
parameters:
  - document_type (string, required): نوع فاکتور
  - person_id (integer, optional): شناسه مشتری/تامین‌کننده
  - items (array, required): اقلام فاکتور
    - product_id (integer, required)
    - quantity (number, required)
    - unit_price (number, required)
  - due_date (string, optional): تاریخ سررسید
```

#### 2.3. Create Receipt Payment (ایجاد دریافت/پرداخت)
```python
name: "create_receipt_payment"
description: "ثبت دریافت یا پرداخت نقدی/بانکی"
parameters:
  - type (string, required): "receipt" | "payment"
  - person_id (integer, optional): شناسه شخص
  - amount (number, required): مبلغ
  - account_id (integer, required): حساب بانکی/نقدی
  - description (string, optional): توضیحات
```

#### 2.4. Update Person (ویرایش شخص)
```python
name: "update_person"
description: "ویرایش اطلاعات یک مشتری یا تامین‌کننده"
parameters:
  - person_id (integer, required): شناسه شخص
  - name (string, optional): نام جدید
  - phone (string, optional): تلفن جدید
  - email (string, optional): ایمیل جدید
```

---

### 3. **Function های تحلیل و گزارش (Analytics) - اولویت متوسط**

#### 3.1. Get Sales Report (گزارش فروش)
```python
name: "get_sales_report"
description: "گزارش فروش بر اساس تاریخ، محصول، مشتری"
parameters:
  - from_date (string, required): تاریخ شروع
  - to_date (string, required): تاریخ پایان
  - product_id (integer, optional): فیلتر بر اساس محصول
  - person_id (integer, optional): فیلتر بر اساس مشتری
  - group_by (string, optional): "day" | "month" | "product" | "customer"
```

#### 3.2. Get Purchase Report (گزارش خرید)
```python
name: "get_purchase_report"
description: "گزارش خرید بر اساس تاریخ، محصول، تامین‌کننده"
parameters:
  - from_date (string, required): تاریخ شروع
  - to_date (string, required): تاریخ پایان
  - product_id (integer, optional): فیلتر بر اساس محصول
  - person_id (integer, optional): فیلتر بر اساس تامین‌کننده
```

#### 3.3. Get Inventory Valuation (ارزش موجودی)
```python
name: "get_inventory_valuation"
description: "محاسبه ارزش موجودی کالاها در انبار"
parameters:
  - warehouse_id (integer, optional): فیلتر بر اساس انبار
  - valuation_method (string, optional): "fifo" | "average" | "lifo"
```

#### 3.4. Get Cash Flow (گردش نقدی)
```python
name: "get_cash_flow"
description: "گزارش گردش نقدی (ورودی/خروجی) در دوره زمانی"
parameters:
  - from_date (string, required): تاریخ شروع
  - to_date (string, required): تاریخ پایان
  - account_type (string, optional): "bank" | "cash" | "all"
```

---

### 4. **Function های پیشنهادی برای راحتی بیشتر (Nice to Have)**

#### 4.1. Calculate Tax (محاسبه مالیات)
```python
name: "calculate_tax"
description: "محاسبه مالیات بر اساس مبلغ و نوع"
parameters:
  - amount (number, required): مبلغ
  - tax_type_id (integer, optional): نوع مالیات
  - tax_unit_id (integer, optional): واحد مالیاتی
```

#### 4.2. Get Product Price (قیمت محصول)
```python
name: "get_product_price"
description: "دریافت قیمت محصول از لیست قیمت"
parameters:
  - product_id (integer, required): شناسه محصول
  - price_list_id (integer, optional): شناسه لیست قیمت
  - person_id (integer, optional): برای لیست قیمت اختصاصی مشتری
```

#### 4.3. Search Warehouse Documents (جستجوی اسناد انبار)
```python
name: "search_warehouse_documents"
description: "جستجو در اسناد انبار (ورود، خروج، انتقال)"
parameters:
  - from_date (string, optional): تاریخ شروع
  - to_date (string, optional): تاریخ پایان
  - warehouse_id (integer, optional): شناسه انبار
  - document_type (string, optional): نوع سند
```

---

## 📊 اولویت‌بندی پیشنهادی

### 🔥 اولویت بسیار بالا (باید اضافه شود):
1. ✅ **search_persons** - جستجوی اشخاص
2. ✅ **get_invoice_details** - جزئیات فاکتور
3. ✅ **get_person_balance** - موجودی شخص
4. ✅ **get_inventory_status** - وضعیت موجودی

### ⚡ اولویت بالا (بسیار مفید):
5. ✅ **search_receipts_payments** - جستجوی دریافت/پرداخت
6. ✅ **get_debtors_report** - گزارش بدهکاران
7. ✅ **get_creditors_report** - گزارش بستانکاران
8. ✅ **get_product_kardex** - کاردکس محصول

### 💡 اولویت متوسط (مفید برای عملیات):
9. ✅ **create_person** - ایجاد شخص
10. ✅ **create_invoice** - ایجاد فاکتور
11. ✅ **create_receipt_payment** - ثبت دریافت/پرداخت
12. ✅ **update_person** - ویرایش شخص

### 🌟 اولویت پایین (برای تحلیل پیشرفته):
13. ✅ **get_sales_report** - گزارش فروش
14. ✅ **get_purchase_report** - گزارش خرید
15. ✅ **get_inventory_valuation** - ارزش موجودی
16. ✅ **get_cash_flow** - گردش نقدی

---

## 🎯 نتیجه‌گیری

**Function های فعلی:** 6 function (فقط خواندن)

**Function های پیشنهادی:**
- اولویت بالا: 8 function (خواندن + گزارش)
- اولویت متوسط: 4 function (نوشتن)
- اولویت پایین: 4 function (تحلیل)

**توصیه:** شروع با function های اولویت بالا که بیشترین کاربرد را دارند و AI می‌تواند با آنها کارهای مهم‌تری انجام دهد.

