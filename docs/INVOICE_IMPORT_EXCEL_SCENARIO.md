# سناریوی ایمپورت فاکتورها از اکسل

## 📋 خلاصه
این سند سناریوی پیاده‌سازی قابلیت ایمپورت فاکتورها از فایل Excel را بررسی می‌کند. این قابلیت به کاربران امکان می‌دهد تا فاکتورهای متعدد را به صورت دسته‌ای از طریق فایل Excel وارد سیستم کنند.

---

## 🔍 بررسی ساختار فعلی

### ساختار Backend

#### 1. مدل‌های دیتابیس
- **Document**: سند اصلی فاکتور
  - `id`, `code`, `business_id`, `fiscal_year_id`, `currency_id`
  - `document_date`, `document_type`, `is_proforma`
  - `description`, `extra_info` (JSON)
  
- **InvoiceItemLine**: ردیف‌های فاکتور
  - `id`, `document_id`, `product_id`, `quantity`
  - `description`, `extra_info` (JSON)

#### 2. سرویس‌های موجود
- **`create_invoice`** در `app/services/invoice_service.py`:
  - دریافت `payload` شامل:
    - `invoice_type`: نوع فاکتور (sales, purchase, etc.)
    - `document_date`: تاریخ فاکتور
    - `currency_id`: شناسه ارز
    - `is_proforma`: پیش‌فاکتور یا قطعی
    - `description`: توضیحات
    - `extra_info`: اطلاعات اضافی (person_id, totals, etc.)
    - `lines`: لیست ردیف‌های فاکتور
    - `payments`: تراکنش‌های پرداخت (اختیاری)

#### 3. انواع فاکتورهای پشتیبانی شده
```python
INVOICE_SALES = "invoice_sales"
INVOICE_SALES_RETURN = "invoice_sales_return"
INVOICE_PURCHASE = "invoice_purchase"
INVOICE_PURCHASE_RETURN = "invoice_purchase_return"
INVOICE_DIRECT_CONSUMPTION = "invoice_direct_consumption"
INVOICE_PRODUCTION = "invoice_production"
INVOICE_WASTE = "invoice_waste"
```

#### 4. الگوی موجود برای ایمپورت
در پروژه قابلیت ایمپورت برای **محصولات** و **اشخاص** پیاده‌سازی شده است:
- **محصولات**: `/api/v1/products/business/{business_id}/import/excel`
- **اشخاص**: `/api/v1/persons/businesses/{business_id}/persons/import/excel`

هر دو دارای:
- Endpoint دانلود تمپلیت: `/import/template`
- Endpoint ایمپورت: `/import/excel` با پارامترهای:
  - `file`: فایل Excel
  - `dry_run`: اعتبارسنجی بدون ذخیره
  - `match_by`: روش تطبیق (code/name)
  - `conflict_policy`: سیاست برخورد با تکراری‌ها

### ساختار Frontend

#### 1. ویجت‌های ایمپورت موجود
- **`ProductImportDialog`**: ویجت ایمپورت محصولات
  - انتخاب فایل Excel
  - دانلود تمپلیت
  - تنظیمات (dry_run, match_by, conflict_policy)
  - نمایش نتایج

- **`PersonImportDialog`**: ویجت ایمپورت اشخاص
  - مشابه ProductImportDialog

#### 2. صفحه لیست فاکتورها
- **`InvoicesListPage`**: صفحه اصلی لیست فاکتورها
  - فیلترها (نوع فاکتور، تاریخ، پیش‌فاکتور)
  - دکمه افزودن فاکتور جدید
  - جدول فاکتورها

#### 3. سرویس‌های Frontend
- **`InvoiceService`**: سرویس ارتباط با API فاکتورها
  - `createInvoice`: ایجاد فاکتور جدید
  - `updateInvoice`: ویرایش فاکتور
  - `getInvoice`: دریافت فاکتور

---

## 📊 ساختار فایل Excel برای ایمپورت فاکتورها

### ساختار پیشنهادی

#### Sheet 1: Header Information (اطلاعات هدر فاکتور)
هر ردیف = یک فاکتور

| ستون | نام | نوع | الزامی | توضیحات |
|------|-----|-----|--------|---------|
| invoice_type | نوع فاکتور | String | ✅ | sales, purchase, sales_return, purchase_return, direct_consumption, production, waste |
| document_date | تاریخ فاکتور | Date | ✅ | YYYY-MM-DD یا YYYY/MM/DD |
| currency_code | کد ارز | String | ✅ | کد ارز (مثلاً IRR, USD) |
| is_proforma | پیش‌فاکتور | Boolean | ❌ | true/false (پیش‌فرض: false) |
| description | توضیحات | String | ❌ | توضیحات فاکتور |
| person_code | کد مشتری/تامین‌کننده | String | ⚠️ | برای فاکتورهای sales/purchase الزامی |
| seller_code | کد فروشنده/بازاریاب | String | ❌ | برای محاسبه کارمزد |
| due_date | تاریخ سررسید | Date | ❌ | برای فاکتورهای فروش |
| post_inventory | ثبت انبار | Boolean | ❌ | true/false (پیش‌فرض: true) |

#### Sheet 2: Line Items (ردیف‌های فاکتور)
هر ردیف = یک ردیف فاکتور

| ستون | نام | نوع | الزامی | توضیحات |
|------|-----|-----|--------|---------|
| invoice_number | شماره فاکتور | String | ✅ | برای ارتباط با Sheet 1 |
| product_code | کد کالا/خدمت | String | ✅ | کد محصول |
| quantity | تعداد | Decimal | ✅ | مقدار |
| unit | واحد | String | ❌ | main/secondary (پیش‌فرض: main) |
| unit_price | قیمت واحد | Decimal | ✅ | قیمت به ازای واحد انتخابی |
| discount_type | نوع تخفیف | String | ❌ | percent/amount (پیش‌فرض: amount) |
| discount_value | مقدار تخفیف | Decimal | ❌ | درصد یا مبلغ |
| tax_rate | نرخ مالیات | Decimal | ❌ | درصد (پیش‌فرض: 0) |
| description | توضیحات ردیف | String | ❌ | توضیحات ردیف |
| movement | جهت حرکت | String | ⚠️ | in/out (برای فاکتور تولید الزامی) |
| warehouse_code | کد انبار | String | ❌ | کد انبار |

#### Sheet 3: Payments (پرداخت‌ها) - اختیاری
هر ردیف = یک تراکنش پرداخت

| ستون | نام | نوع | الزامی | توضیحات |
|------|-----|-----|--------|---------|
| invoice_number | شماره فاکتور | String | ✅ | برای ارتباط با Sheet 1 |
| transaction_type | نوع تراکنش | String | ✅ | cash, bank, check, etc. |
| amount | مبلغ | Decimal | ✅ | مبلغ پرداخت |
| transaction_date | تاریخ تراکنش | Date | ✅ | تاریخ پرداخت |
| account_code | کد حساب | String | ❌ | کد حساب بانکی/صندوق |
| check_number | شماره چک | String | ❌ | برای تراکنش چک |
| description | توضیحات | String | ❌ | توضیحات پرداخت |

### ساختار جایگزین (ساده‌تر)
اگر ساختار چند Sheet پیچیده باشد، می‌توان از یک Sheet استفاده کرد:

#### Single Sheet Structure
هر ردیف = یک ردیف فاکتور (فاکتورهای متعدد با invoice_number گروه‌بندی می‌شوند)

| ستون | نام | نوع | الزامی | توضیحات |
|------|-----|-----|--------|---------|
| invoice_number | شماره فاکتور | String | ✅ | شناسه یکتا برای هر فاکتور |
| invoice_type | نوع فاکتور | String | ✅ | sales, purchase, etc. |
| document_date | تاریخ فاکتور | Date | ✅ | |
| currency_code | کد ارز | String | ✅ | |
| is_proforma | پیش‌فاکتور | Boolean | ❌ | |
| description | توضیحات فاکتور | String | ❌ | |
| person_code | کد مشتری/تامین‌کننده | String | ⚠️ | |
| seller_code | کد فروشنده | String | ❌ | |
| due_date | تاریخ سررسید | Date | ❌ | |
| product_code | کد کالا/خدمت | String | ✅ | |
| quantity | تعداد | Decimal | ✅ | |
| unit_price | قیمت واحد | Decimal | ✅ | |
| discount_type | نوع تخفیف | String | ❌ | |
| discount_value | مقدار تخفیف | Decimal | ❌ | |
| tax_rate | نرخ مالیات | Decimal | ❌ | |
| line_description | توضیحات ردیف | String | ❌ | |
| movement | جهت حرکت | String | ❌ | |
| warehouse_code | کد انبار | String | ❌ | |

**نکته**: در این ساختار، اطلاعات هدر فاکتور در هر ردیف تکرار می‌شود. سیستم باید ردیف‌های با `invoice_number` یکسان را گروه‌بندی کند.

---

## 🎯 سناریوی پیاده‌سازی

### مرحله 1: Backend - Endpoint دانلود تمپلیت

**مسیر**: `POST /api/v1/invoices/business/{business_id}/import/template`

**عملکرد**:
1. ایجاد فایل Excel با ساختار تعریف شده
2. پر کردن Header row با نام ستون‌ها
3. اضافه کردن یک ردیف نمونه (اختیاری)
4. بازگرداندن فایل به عنوان Response

**کد نمونه** (مشابه `download_products_import_template`):
```python
@router.post("/business/{business_id}/import/template")
async def download_invoices_import_template(...):
    wb = Workbook()
    ws = wb.active
    ws.title = "Invoices"
    
    headers = [
        "invoice_number", "invoice_type", "document_date", "currency_code",
        "is_proforma", "description", "person_code", "seller_code",
        "due_date", "product_code", "quantity", "unit_price",
        "discount_type", "discount_value", "tax_rate", "line_description",
        "movement", "warehouse_code"
    ]
    
    # اضافه کردن header و نمونه
    # ...
    
    return Response(content=buf.getvalue(), ...)
```

### مرحله 2: Backend - Endpoint ایمپورت

**مسیر**: `POST /api/v1/invoices/business/{business_id}/import/excel`

**پارامترها**:
- `file`: فایل Excel (UploadFile)
- `dry_run`: اعتبارسنجی بدون ذخیره (default: true)
- `create_mode`: حالت ایجاد (single/multiple) - برای آینده

**فرآیند پردازش**:

1. **خواندن فایل Excel**
   - اعتبارسنجی فرمت فایل (.xlsx)
   - بارگذاری workbook با openpyxl

2. **پارس کردن داده‌ها**
   - خواندن Sheet اول
   - استخراج Header row
   - خواندن Data rows
   - گروه‌بندی ردیف‌ها بر اساس `invoice_number`

3. **اعتبارسنجی داده‌ها**
   - بررسی فیلدهای الزامی
   - اعتبارسنجی نوع فاکتور
   - بررسی وجود محصولات (بر اساس product_code)
   - بررسی وجود اشخاص (بر اساس person_code)
   - بررسی وجود ارز (بر اساس currency_code)
   - محاسبه و اعتبارسنجی Totals
   - اعتبارسنجی قوانین کسب‌وکار (مثل اعتبار مشتری)

4. **تبدیل به Payload**
   - تبدیل هر گروه به یک payload فاکتور
   - تبدیل ردیف‌ها به `lines`
   - ساخت `extra_info` از فیلدهای اضافی

5. **ایجاد فاکتورها** (اگر dry_run=false)
   - فراخوانی `create_invoice` برای هر فاکتور
   - مدیریت خطاها و Rollback در صورت نیاز

6. **بازگرداندن نتیجه**
   - خلاصه (total, valid, invalid, created, errors)
   - لیست خطاها با شماره ردیف

**ساختار Response**:
```json
{
  "success": true,
  "data": {
    "summary": {
      "total": 10,
      "valid": 8,
      "invalid": 2,
      "created": 8,
      "dry_run": true
    },
    "errors": [
      {
        "row": 3,
        "invoice_number": "INV-001",
        "errors": ["product_code not found: P123"]
      }
    ],
    "warnings": [
      {
        "row": 5,
        "invoice_number": "INV-002",
        "message": "Credit limit exceeded but ignored"
      }
    ]
  }
}
```

### مرحله 3: Frontend - ویجت ایمپورت

**فایل جدید**: `lib/widgets/invoice/invoice_import_dialog.dart`

**عملکرد**:
- مشابه `ProductImportDialog`
- انتخاب فایل Excel
- دانلود تمپلیت
- تنظیمات (dry_run)
- نمایش نتایج

**استفاده**:
- اضافه کردن دکمه "ایمپورت از اکسل" در `InvoicesListPage`
- باز کردن Dialog با کلیک روی دکمه

### مرحله 4: Frontend - سرویس ایمپورت

**افزودن به `InvoiceService`**:
```dart
Future<Map<String, dynamic>> importInvoicesFromExcel({
  required int businessId,
  required List<int> fileBytes,
  required String filename,
  required bool dryRun,
}) async {
  final form = FormData.fromMap({
    'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    'dry_run': dryRun.toString(),
  });
  
  final res = await _api.post<Map<String, dynamic>>(
    '/api/v1/invoices/business/$businessId/import/excel',
    data: form,
    options: Options(contentType: 'multipart/form-data'),
  );
  
  return Map<String, dynamic>.from(res.data?['data'] ?? const {});
}

Future<void> downloadImportTemplate({
  required int businessId,
}) async {
  // مشابه محصولات
}
```

---

## ⚠️ نکات مهم و چالش‌ها

### 1. اعتبارسنجی داده‌ها
- **محصولات**: باید بر اساس `product_code` پیدا شوند
- **اشخاص**: باید بر اساس `person_code` پیدا شوند
- **ارز**: باید بر اساس `currency_code` پیدا شود
- **انبار**: باید بر اساس `warehouse_code` پیدا شود (اختیاری)

### 2. محاسبه Totals
- سیستم باید Totals را از ردیف‌ها محاسبه کند
- یا می‌توان از کاربر خواست Totals را در Excel وارد کند (برای اعتبارسنجی)

### 3. مدیریت خطاها
- خطاهای اعتبارسنجی باید با شماره ردیف Excel مشخص شوند
- در صورت خطا در یک فاکتور، سایر فاکتورها باید پردازش شوند (یا همه Rollback شوند؟)

### 4. فاکتور تولید
- فاکتور تولید نیاز به ردیف‌های با `movement: "in"` و `movement: "out"` دارد
- باید اعتبارسنجی شود که حداقل یک ردیف از هر نوع وجود دارد

### 5. اعتبار مشتری
- برای فاکتورهای فروش، باید اعتبار مشتری بررسی شود
- در صورت نیاز، می‌توان `ignore_credit_check` را در Excel اضافه کرد

### 6. تراکنش‌های پرداخت
- پرداخت‌ها می‌توانند در Sheet جداگانه یا در همان Sheet باشند
- باید با `invoice_number` مرتبط شوند

### 7. پیش‌فاکتور vs قطعی
- پیش‌فاکتورها نیاز به پرداخت ندارند
- فاکتورهای قطعی می‌توانند پرداخت داشته باشند

### 8. تاریخ‌ها
- پشتیبانی از فرمت‌های مختلف تاریخ (YYYY-MM-DD, YYYY/MM/DD, Jalali)
- تبدیل تاریخ شمسی به میلادی در صورت نیاز

### 9. واحدها
- پشتیبانی از واحد اصلی و فرعی
- تبدیل خودکار بر اساس `unit_conversion_factor`

### 10. Performance
- برای فایل‌های بزرگ (مثلاً 1000+ فاکتور)، باید پردازش به صورت Batch انجام شود
- نمایش Progress bar در Frontend

---

## 📝 فیلدهای مورد نیاز در Excel

### فیلدهای هدر فاکتور (در هر ردیف یا Sheet جداگانه)
- `invoice_number`: شناسه یکتا فاکتور (برای گروه‌بندی)
- `invoice_type`: نوع فاکتور
- `document_date`: تاریخ فاکتور
- `currency_code`: کد ارز
- `is_proforma`: پیش‌فاکتور (true/false)
- `description`: توضیحات فاکتور
- `person_code`: کد مشتری/تامین‌کننده (برای sales/purchase)
- `seller_code`: کد فروشنده (اختیاری)
- `due_date`: تاریخ سررسید (اختیاری)
- `post_inventory`: ثبت انبار (true/false)

### فیلدهای ردیف فاکتور
- `invoice_number`: برای ارتباط با هدر
- `product_code`: کد محصول
- `quantity`: تعداد
- `unit`: واحد (main/secondary)
- `unit_price`: قیمت واحد
- `discount_type`: نوع تخفیف (percent/amount)
- `discount_value`: مقدار تخفیف
- `tax_rate`: نرخ مالیات (درصد)
- `description`: توضیحات ردیف
- `movement`: جهت حرکت (in/out) - برای فاکتور تولید
- `warehouse_code`: کد انبار (اختیاری)

### فیلدهای پرداخت (اختیاری)
- `invoice_number`: برای ارتباط با فاکتور
- `transaction_type`: نوع تراکنش
- `amount`: مبلغ
- `transaction_date`: تاریخ تراکنش
- `account_code`: کد حساب (اختیاری)
- `check_number`: شماره چک (اختیاری)
- `description`: توضیحات (اختیاری)

---

## 🔄 جریان کار (Workflow)

1. **کاربر** روی دکمه "ایمپورت از اکسل" کلیک می‌کند
2. **سیستم** Dialog ایمپورت را نمایش می‌دهد
3. **کاربر** می‌تواند تمپلیت را دانلود کند
4. **کاربر** فایل Excel را پر می‌کند
5. **کاربر** فایل را انتخاب می‌کند
6. **کاربر** روی "بررسی (Dry Run)" کلیک می‌کند
7. **سیستم** فایل را پردازش و اعتبارسنجی می‌کند
8. **سیستم** نتایج را نمایش می‌دهد (خطاها، هشدارها)
9. **کاربر** خطاها را برطرف می‌کند
10. **کاربر** روی "ایمپورت واقعی" کلیک می‌کند
11. **سیستم** فاکتورها را ایجاد می‌کند
12. **سیستم** نتایج نهایی را نمایش می‌دهد

---

## 🎨 UI/UX پیشنهادی

### Dialog ایمپورت
- **تب 1: انتخاب فایل**
  - دکمه انتخاب فایل
  - نمایش نام فایل انتخاب شده
  - دکمه دانلود تمپلیت

- **تب 2: تنظیمات**
  - Checkbox: Dry Run (پیش‌فرض: فعال)
  - توضیحات درباره Dry Run

- **تب 3: نتایج**
  - خلاصه (total, valid, invalid, created)
  - لیست خطاها با قابلیت فیلتر
  - دکمه Export خطاها به Excel

### صفحه لیست فاکتورها
- دکمه "ایمپورت از اکسل" در کنار دکمه "افزودن فاکتور"
- آیکون: `Icons.upload_file` یا `Icons.file_upload`

---

## 📚 منابع و مراجع

- کد موجود: `hesabixAPI/adapters/api/v1/products.py` (ایمپورت محصولات)
- کد موجود: `hesabixAPI/adapters/api/v1/persons.py` (ایمپورت اشخاص)
- ویجت موجود: `hesabixUI/hesabix_ui/lib/widgets/product/product_import_dialog.dart`
- سرویس فاکتور: `hesabixAPI/app/services/invoice_service.py`
- API فاکتور: `hesabixAPI/adapters/api/v1/invoices.py`

---

## ✅ چک‌لیست پیاده‌سازی

### Backend
- [ ] Endpoint دانلود تمپلیت
- [ ] Endpoint ایمپورت
- [ ] پارس کردن فایل Excel
- [ ] اعتبارسنجی داده‌ها
- [ ] تبدیل به Payload
- [ ] ایجاد فاکتورها
- [ ] مدیریت خطاها
- [ ] تست‌های واحد

### Frontend
- [ ] ویجت InvoiceImportDialog
- [ ] افزودن به InvoiceService
- [ ] دکمه در InvoicesListPage
- [ ] نمایش نتایج
- [ ] مدیریت خطاها
- [ ] تست UI

### مستندات
- [ ] مستندات API
- [ ] راهنمای کاربر
- [ ] نمونه فایل Excel

---

## 🚀 مراحل بعدی

1. **تایید سناریو**: بررسی و تایید این سناریو توسط تیم
2. **تصمیم‌گیری ساختار Excel**: انتخاب ساختار Single Sheet یا Multi Sheet
3. **پیاده‌سازی Backend**: شروع با Endpoint تمپلیت
4. **پیاده‌سازی Frontend**: ایجاد ویجت ایمپورت
5. **تست**: تست با فایل‌های نمونه
6. **مستندسازی**: نوشتن راهنمای کاربر

---

**تاریخ ایجاد**: 2024
**آخرین به‌روزرسانی**: 2024

