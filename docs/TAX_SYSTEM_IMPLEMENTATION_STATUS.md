# وضعیت پیاده‌سازی سامانه مودیان مالیاتی (نسخه جدید)

این مستندات وضعیت فعلی پیاده‌سازی سامانه مودیان مالیاتی در نسخه جدید (Python + Flutter) را بررسی می‌کند.

**تاریخ بررسی**: 2025-01-XX

---

## خلاصه اجرایی

### ✅ بخش‌های پیاده‌سازی شده

1. **کارپوشه مودیان (Tax Workspace)**
   - ✅ اضافه کردن فاکتور به کارپوشه
   - ✅ حذف فاکتور از کارپوشه
   - ✅ جستجو و فیلتر فاکتورهای کارپوشه
   - ✅ نمایش وضعیت فاکتورها
   - ✅ ارسال تکی و گروهی (شبیه‌سازی شده)

2. **فرانت‌اند (Flutter)**
   - ✅ صفحه کارپوشه مودیان (`tax_workspace_page.dart`)
   - ✅ نمایش لیست فاکتورها با فیلتر
   - ✅ دکمه‌های ارسال تکی و گروهی
   - ✅ دکمه‌های حذف از کارپوشه

3. **بکند (Python/FastAPI)**
   - ✅ API endpoints برای کارپوشه
   - ✅ ذخیره وضعیت در `extra_info` فاکتور
   - ✅ مدیریت وضعیت‌های مالیاتی

### ❌ بخش‌های ناقص یا پیاده‌سازی نشده

1. **ارتباط واقعی با سامانه مودیان**
   - ❌ کتابخانه Moadian نصب نشده
   - ❌ ارسال واقعی به سامانه انجام نمی‌شود (فقط شبیه‌سازی)
   - ❌ دریافت کلید عمومی سازمان مالیاتی
   - ❌ لاگین به سامانه
   - ❌ استعلام وضعیت از سامانه

2. **تنظیمات مالیاتی**
   - ❌ جدول تنظیمات مالیاتی وجود ندارد
   - ❌ API برای ذخیره تنظیمات وجود ندارد
   - ❌ صفحه تنظیمات در فرانت وجود ندارد
   - ❌ تولید کلید خصوصی/عمومی
   - ❌ تولید CSR

3. **اعتبارسنجی فاکتور**
   - ❌ بررسی کد مالیاتی کالاها
   - ❌ بررسی واحد مالیاتی کالاها
   - ❌ بررسی اعشار در مالیات
   - ❌ بررسی هزینه حمل

4. **ساخت DTO فاکتور**
   - ❌ تبدیل فاکتور به فرمت Moadian
   - ❌ ساخت Header فاکتور
   - ❌ ساخت Body فاکتور
   - ❌ محاسبه VRA (نرخ مالیات)

5. **مدیریت خطاها**
   - ❌ نمایش خطاهای سامانه
   - ❌ امکان ارسال مجدد فاکتورهای خطا دار
   - ❌ ذخیره پاسخ سامانه

6. **سایر قابلیت‌ها**
   - ❌ استعلام وضعیت فاکتورهای ارسال شده
   - ❌ اعتبارسنجی اطلاعات خریدار
   - ❌ پشتیبانی از Sandbox/Production

---

## جزئیات پیاده‌سازی

### 1. کارپوشه مودیان (Tax Workspace)

#### Backend (Python)

**فایل**: `hesabixAPI/adapters/api/v1/invoices.py`

**Endpoints پیاده‌سازی شده**:

```python
# اضافه کردن فاکتور به کارپوشه
POST /business/{business_id}/{invoice_id}/tax-workspace/add

# حذف فاکتور از کارپوشه
POST /business/{business_id}/{invoice_id}/tax-workspace/remove

# جستجو در کارپوشه
POST /business/{business_id}/tax-workspace/search

# ارسال تکی به سامانه (شبیه‌سازی)
POST /business/{business_id}/{invoice_id}/tax-workspace/send-to-system

# ارسال گروهی به سامانه (شبیه‌سازی)
POST /business/{business_id}/tax-workspace/send-to-system-batch

# حذف گروهی از کارپوشه
POST /business/{business_id}/tax-workspace/remove-batch
```

**ذخیره‌سازی داده‌ها**:
- وضعیت در `Document.extra_info` به صورت JSON ذخیره می‌شود:
  ```json
  {
    "tax_workspace": true,
    "tax_status": "not_sent|sent|finalized|failed",
    "tax_tracking_code": "SIM-123-...",
    "tax_last_send_at": "2025-01-01T12:00:00"
  }
  ```

**محدودیت‌ها**:
- فقط فاکتورهای فروش و برگشت از فروش قابل اضافه شدن هستند
- فاکتورهای Proforma قابل اضافه شدن نیستند
- فاکتورهای `finalized` قابل حذف نیستند

#### Frontend (Flutter)

**فایل**: `hesabixUI/hesabix_ui/lib/pages/business/tax_workspace_page.dart`

**قابلیت‌های پیاده‌سازی شده**:
- ✅ نمایش لیست فاکتورهای کارپوشه
- ✅ فیلتر بر اساس نوع فاکتور (فروش/برگشت)
- ✅ فیلتر بر اساس وضعیت مالیاتی
- ✅ فیلتر بر اساس بازه تاریخ
- ✅ انتخاب چندتایی فاکتورها
- ✅ ارسال تکی به سامانه
- ✅ ارسال گروهی به سامانه
- ✅ حذف تکی از کارپوشه
- ✅ حذف گروهی از کارپوشه

**ستون‌های نمایش**:
- کد فاکتور
- نوع فاکتور
- تاریخ فاکتور
- مبلغ کل
- وضعیت مالیاتی
- کد رهگیری
- تاریخ آخرین ارسال

---

### 2. ارسال به سامانه (ناقص)

#### وضعیت فعلی

**فایل**: `hesabixAPI/adapters/api/v1/invoices.py` (خط 1719-1732)

```python
def _simulate_send_to_tax_system(doc: Document, db: Session) -> None:
    """
    شبیه‌سازی ارسال فاکتور به سامانه مودیان.
    در این نسخه اولیه، فقط وضعیت و کد رهگیری آزمایشی ذخیره می‌شود.
    """
    extra = dict(doc.extra_info or {})
    now = datetime.datetime.utcnow().isoformat()
    extra["tax_workspace"] = True
    extra["tax_status"] = "sent"
    extra["tax_tracking_code"] = extra.get("tax_tracking_code") or f"SIM-{doc.id}-{int(datetime.datetime.utcnow().timestamp())}"
    extra["tax_last_send_at"] = now
    extra.pop("tax_error_message", None)
    doc.extra_info = extra
    db.add(doc)
```

**مشکلات**:
- ❌ هیچ ارتباط واقعی با سامانه برقرار نمی‌شود
- ❌ کد رهگیری شبیه‌سازی شده است (`SIM-...`)
- ❌ هیچ اعتبارسنجی انجام نمی‌شود
- ❌ هیچ تبدیل به فرمت Moadian انجام نمی‌شود

---

### 3. تنظیمات مالیاتی (ناقص)

#### وضعیت فعلی

**در نسخه قدیمی**:
- جدول `plugin_taxsettings_key` وجود داشت
- API برای ذخیره تنظیمات وجود داشت
- صفحه تنظیمات در فرانت وجود داشت

**در نسخه جدید**:
- ❌ هیچ جدول تنظیمات وجود ندارد
- ❌ هیچ API برای تنظیمات وجود ندارد
- ❌ هیچ صفحه تنظیمات در فرانت وجود ندارد

**نیاز به پیاده‌سازی**:
1. ایجاد جدول `tax_settings` در دیتابیس
2. ایجاد Model در SQLAlchemy
3. ایجاد API endpoints برای:
   - دریافت تنظیمات
   - ذخیره تنظیمات
   - تولید کلید خصوصی/عمومی
   - تولید CSR
4. ایجاد صفحه تنظیمات در Flutter

---

### 4. اعتبارسنجی فاکتور (ناقص)

#### وضعیت فعلی

**در نسخه قدیمی**:
- بررسی وجود اقلام
- بررسی کد مالیاتی هر کالا
- بررسی واحد مالیاتی هر کالا
- بررسی اعشار در مالیات
- بررسی هزینه حمل

**در نسخه جدید**:
- ❌ هیچ اعتبارسنجی انجام نمی‌شود
- ✅ کد مالیاتی و واحد مالیاتی در جدول `products` وجود دارد (`tax_code`, `tax_unit_id`)
- ✅ جدول `tax_types` و `tax_units` وجود دارد

**نیاز به پیاده‌سازی**:
1. تابع اعتبارسنجی فاکتور قبل از ارسال
2. بررسی وجود کد مالیاتی برای همه کالاها
3. بررسی وجود واحد مالیاتی برای همه کالاها
4. بررسی اعشار در مبلغ مالیات
5. بررسی هزینه حمل (باید صفر باشد)

---

### 5. ساخت DTO فاکتور (ناقص)

#### وضعیت فعلی

**در نسخه قدیمی**:
- تبدیل کامل فاکتور به فرمت Moadian
- ساخت Header (سربرگ)
- ساخت Body (بدنه - اقلام)
- ساخت Payment (پرداخت)
- محاسبه VRA (نرخ مالیات)

**در نسخه جدید**:
- ❌ هیچ تبدیل انجام نمی‌شود
- ❌ هیچ DTO ساخته نمی‌شود

**نیاز به پیاده‌سازی**:
1. نصب کتابخانه Moadian برای Python
2. تابع تبدیل فاکتور به InvoiceDto
3. ساخت Header با تمام فیلدهای مورد نیاز
4. ساخت Body برای هر قلم فاکتور
5. محاسبه VRA برای هر قلم
6. ساخت Payment

---

## کارهای لازم برای تکمیل

### اولویت 1: تنظیمات مالیاتی

#### Backend

1. **ایجاد Migration برای جدول تنظیمات**:
   ```python
   # migrations/versions/xxxx_create_tax_settings.py
   - business_id (INT, FK)
   - user_id (INT, FK)
   - tax_memory_id (VARCHAR)
   - economic_code (VARCHAR)
   - private_key (TEXT)
   - public_key (TEXT, nullable)
   - certificate (TEXT, nullable)
   - sandbox_mode (BOOLEAN, default=False)
   - created_at, updated_at
   ```

2. **ایجاد Model**:
   ```python
   # adapters/db/models/tax_setting.py
   class TaxSetting(Base):
       __tablename__ = "tax_settings"
       # ...
   ```

3. **ایجاد API Endpoints**:
   ```python
   # adapters/api/v1/tax_settings.py
   GET  /business/{business_id}/tax-settings
   POST /business/{business_id}/tax-settings
   POST /business/{business_id}/tax-settings/generate-keys
   POST /business/{business_id}/tax-settings/generate-csr
   ```

#### Frontend

1. **ایجاد صفحه تنظیمات**:
   ```dart
   # lib/pages/business/tax_settings_page.dart
   - فرم ورود شناسه حافظه مالیاتی
   - فرم ورود کد اقتصادی
   - فرم ورود کلید خصوصی
   - دکمه تولید کلید
   - دکمه تولید CSR
   - دکمه ذخیره
   ```

2. **ایجاد Service**:
   ```dart
   # lib/services/tax_settings_service.dart
   - getTaxSettings()
   - saveTaxSettings()
   - generateKeys()
   - generateCSR()
   ```

---

### اولویت 2: نصب و راه‌اندازی کتابخانه Moadian

#### نصب کتابخانه

```bash
# بررسی کتابخانه‌های موجود برای Python
# احتمالاً باید از کتابخانه PHP استفاده شده در نسخه قدیمی الهام گرفت
# یا کتابخانه Python معادل پیدا کرد

# گزینه 1: استفاده از کتابخانه موجود
pip install moadian-python  # اگر وجود دارد

# گزینه 2: پیاده‌سازی مستقیم API
# استفاده از httpx برای ارتباط مستقیم با API سامانه
```

#### ایجاد Service برای ارتباط با سامانه

```python
# app/services/tax_system_service.py
class TaxSystemService:
    def __init__(self, tax_memory_id: str, private_key: str, economic_code: str, sandbox: bool = False):
        self.tax_memory_id = tax_memory_id
        self.private_key = private_key
        self.economic_code = economic_code
        self.base_url = "https://sandboxrc.tax.gov.ir/" if sandbox else "https://tp.tax.gov.ir/"
    
    def get_server_information(self) -> dict:
        """دریافت اطلاعات سرور و کلید عمومی"""
        pass
    
    def login(self) -> str:
        """لاگین و دریافت Token"""
        pass
    
    def send_invoices(self, invoices: list) -> dict:
        """ارسال فاکتورها به سامانه"""
        pass
    
    def inquire_status(self, reference_numbers: list) -> dict:
        """استعلام وضعیت فاکتورها"""
        pass
```

---

### اولویت 3: اعتبارسنجی فاکتور

#### ایجاد تابع اعتبارسنجی

```python
# app/services/tax_validation_service.py
class TaxValidationService:
    @staticmethod
    def validate_invoice_for_tax(db: Session, invoice: Document) -> dict:
        """
        اعتبارسنجی فاکتور قبل از ارسال به سامانه
        
        Returns:
            {
                "valid": bool,
                "errors": list[str],
                "warnings": list[str]
            }
        """
        errors = []
        warnings = []
        
        # 1. بررسی وجود اقلام
        if not invoice.product_lines:
            errors.append("فاکتور فاقد اقلام است")
            return {"valid": False, "errors": errors, "warnings": warnings}
        
        # 2. بررسی کد مالیاتی
        for line in invoice.product_lines:
            product = line.product
            if not product.tax_code:
                errors.append(f"کالا {product.name}: کد مالیاتی تعریف نشده است")
        
        # 3. بررسی واحد مالیاتی
        for line in invoice.product_lines:
            product = line.product
            if not product.tax_unit_id:
                errors.append(f"کالا {product.name}: واحد مالیاتی تعریف نشده است")
        
        # 4. بررسی اعشار در مالیات
        total_tax = sum(line.tax_amount for line in invoice.product_lines)
        if total_tax % 1 != 0:
            errors.append("مبلغ مالیات بر ارزش افزوده نباید اعشار داشته باشد")
        
        # 5. بررسی هزینه حمل
        # (باید از extra_info خوانده شود)
        shipping_cost = (invoice.extra_info or {}).get("shipping_cost", 0)
        if shipping_cost > 0:
            errors.append("هزینه حمل باید صفر باشد")
        
        return {
            "valid": len(errors) == 0,
            "errors": errors,
            "warnings": warnings
        }
```

---

### اولویت 4: ساخت DTO فاکتور

#### ایجاد تابع تبدیل

```python
# app/services/tax_dto_builder.py
from typing import Optional
from app.services.tax_system_service import TaxSystemService

class TaxDtoBuilder:
    @staticmethod
    def build_invoice_dto(
        db: Session,
        invoice: Document,
        tax_service: TaxSystemService,
        economic_code: str
    ) -> Optional[dict]:
        """
        تبدیل فاکتور به فرمت Moadian
        
        Returns:
            InvoiceDto compatible dict
        """
        # 1. استخراج اطلاعات فاکتور
        invoice_data = _extract_invoice_data(invoice)
        
        # 2. ساخت Header
        header = _build_header(invoice, invoice_data, economic_code, tax_service)
        
        # 3. ساخت Body (اقلام)
        body_items = []
        for line in invoice.product_lines:
            body_item = _build_body_item(line, invoice)
            body_items.append(body_item)
        
        # 4. ساخت Payment
        payment = _build_payment(invoice)
        
        return {
            "header": header,
            "body": body_items,
            "payments": [payment]
        }
    
    @staticmethod
    def _build_header(invoice, invoice_data, economic_code, tax_service):
        """ساخت Header فاکتور"""
        # محاسبه Tax ID
        tax_id = tax_service.generate_tax_id(invoice.created_at, invoice.id)
        
        # محاسبه Invoice Number
        invoice_number = tax_service.normalize_invoice_number(invoice.id)
        
        # تعیین نوع فاکتور
        invoice_type = 2  # ساده (پیش‌فرض)
        if invoice_data.get("buyer_national_id") and invoice_data.get("buyer_economic_code"):
            invoice_type = 1  # عادی
        
        # تعیین نوع شخص خریدار
        person_type = 1  # حقوقی (پیش‌فرض)
        if len(invoice_data.get("buyer_national_id", "")) == 11:
            person_type = 2  # حقیقی
        
        return {
            "taxid": tax_id,
            "indati2m": int(invoice.created_at.timestamp() * 1000),
            "indatim": int(invoice.created_at.timestamp() * 1000),
            "inty": invoice_type,
            "inno": invoice_number,
            "irtaxid": None,
            "inp": 1,
            "ins": 1,
            "tins": economic_code,
            "tob": person_type,
            "bid": invoice_data.get("buyer_national_id"),
            "tinb": invoice_data.get("buyer_economic_code"),
            "bpc": invoice_data.get("buyer_postal_code"),
            "tprdis": invoice_data["total_before_discount"],
            "tdis": invoice_data["total_discount"],
            "tadis": invoice_data["total_after_discount"],
            "tvam": invoice_data["total_tax"],
            "todam": invoice_data.get("shipping_cost", 0),
            "tbill": invoice_data["final_total"],
            "setm": 1 if invoice_type == 1 else None,
        }
    
    @staticmethod
    def _build_body_item(line, invoice):
        """ساخت Body برای یک قلم"""
        product = line.product
        
        # محاسبه VRA
        vra = _calculate_vra(line.total, line.tax_amount, invoice)
        
        # محاسبه مقادیر
        prdis = line.quantity * line.unit_price
        adis = prdis - line.discount_amount
        vam = (adis * vra) / 100
        tsstam = adis + vam
        
        return {
            "sstid": product.tax_code,
            "sstt": product.name,
            "am": line.quantity,
            "mu": product.tax_unit.code,  # کد واحد مالیاتی
            "fee": line.unit_price,
            "prdis": prdis,
            "dis": line.discount_amount,
            "adis": adis,
            "vra": vra,
            "vam": vam,
            "tsstam": tsstam,
        }
    
    @staticmethod
    def _calculate_vra(item_total: float, item_tax: float, invoice) -> int:
        """محاسبه نرخ مالیات (VRA)"""
        if item_total <= 0 or item_tax <= 0:
            return 0
        
        vra = round((item_tax / item_total) * 100, 2)
        tax_percent = invoice.tax_rate or 9
        expected_vra = int(tax_percent)
        
        if vra > 0 and abs(vra - expected_vra) <= 1:
            return expected_vra
        
        return int(vra)
```

---

### اولویت 5: ارسال واقعی به سامانه

#### بروزرسانی تابع ارسال

```python
# adapters/api/v1/invoices.py
@router.post("/business/{business_id}/{invoice_id}/tax-workspace/send-to-system")
async def send_invoice_to_tax_system(...):
    # 1. دریافت تنظیمات مالیاتی
    tax_settings = get_tax_settings(db, business_id, user_id)
    if not tax_settings:
        raise ApiError("TAX_SETTINGS_NOT_FOUND", "Tax settings not configured")
    
    # 2. اعتبارسنجی فاکتور
    validation = TaxValidationService.validate_invoice_for_tax(db, doc)
    if not validation["valid"]:
        raise ApiError("TAX_VALIDATION_FAILED", "; ".join(validation["errors"]))
    
    # 3. ایجاد سرویس ارتباط با سامانه
    tax_service = TaxSystemService(
        tax_memory_id=tax_settings.tax_memory_id,
        private_key=tax_settings.private_key,
        economic_code=tax_settings.economic_code,
        sandbox=tax_settings.sandbox_mode
    )
    
    # 4. دریافت اطلاعات سرور و لاگین
    server_info = tax_service.get_server_information()
    token = tax_service.login()
    
    # 5. ساخت DTO
    invoice_dto = TaxDtoBuilder.build_invoice_dto(
        db, doc, tax_service, tax_settings.economic_code
    )
    
    # 6. ارسال به سامانه
    response = tax_service.send_invoices([invoice_dto])
    
    # 7. بروزرسانی وضعیت
    if response.get("result") and response["result"][0].get("referenceNumber"):
        extra = dict(doc.extra_info or {})
        extra["tax_status"] = "sent"
        extra["tax_tracking_code"] = response["result"][0]["referenceNumber"]
        extra["tax_last_send_at"] = datetime.utcnow().isoformat()
        extra["tax_response_data"] = json.dumps(response)
        doc.extra_info = extra
        db.commit()
        
        return success_response(...)
    else:
        # خطا در ارسال
        extra = dict(doc.extra_info or {})
        extra["tax_status"] = "failed"
        error_msg = response.get("result", [{}])[0].get("error", "Unknown error")
        extra["tax_error_message"] = json.dumps({"error": error_msg})
        doc.extra_info = extra
        db.commit()
        
        raise ApiError("TAX_SEND_FAILED", error_msg)
```

---

### اولویت 6: استعلام وضعیت

#### ایجاد Endpoint استعلام

```python
# adapters/api/v1/invoices.py
@router.post("/business/{business_id}/tax-workspace/inquire-status")
async def inquire_tax_status(...):
    """استعلام وضعیت فاکتورهای ارسال شده"""
    reference_numbers = body.get("reference_numbers", [])
    
    # دریافت تنظیمات
    tax_settings = get_tax_settings(db, business_id, user_id)
    tax_service = TaxSystemService(...)
    
    # استعلام از سامانه
    response = tax_service.inquire_status(reference_numbers)
    
    # بروزرسانی وضعیت فاکتورها
    for item in response.get("result", {}).get("data", []):
        reference_number = item.get("referenceNumber")
        status = item.get("status")
        
        # پیدا کردن فاکتور
        doc = find_document_by_tracking_code(db, business_id, reference_number)
        if doc:
            extra = dict(doc.extra_info or {})
            if status == "SUCCESS":
                extra["tax_status"] = "finalized"
            elif status == "FAILED":
                extra["tax_status"] = "failed"
                extra["tax_error_message"] = json.dumps(item.get("data", {}))
            doc.extra_info = extra
            db.add(doc)
    
    db.commit()
    return success_response(...)
```

---

## خلاصه کارهای لازم

### Backend (Python)

1. ✅ کارپوشه مودیان (پیاده‌سازی شده)
2. ❌ جدول تنظیمات مالیاتی
3. ❌ API تنظیمات مالیاتی
4. ❌ نصب کتابخانه Moadian یا پیاده‌سازی API
5. ❌ Service ارتباط با سامانه
6. ❌ اعتبارسنجی فاکتور
7. ❌ ساخت DTO فاکتور
8. ❌ ارسال واقعی به سامانه
9. ❌ استعلام وضعیت
10. ❌ مدیریت خطاها

### Frontend (Flutter)

1. ✅ صفحه کارپوشه مودیان (پیاده‌سازی شده)
2. ❌ صفحه تنظیمات مالیاتی
3. ❌ Service تنظیمات مالیاتی
4. ❌ نمایش خطاهای سامانه
5. ❌ دکمه استعلام وضعیت

---

## مراحل پیاده‌سازی پیشنهادی

### فاز 1: تنظیمات (1-2 روز)
1. ایجاد جدول تنظیمات
2. ایجاد API endpoints
3. ایجاد صفحه تنظیمات در Flutter

### فاز 2: ارتباط با سامانه (2-3 روز)
1. نصب/پیاده‌سازی کتابخانه Moadian
2. ایجاد Service ارتباط با سامانه
3. تست اتصال و لاگین

### فاز 3: اعتبارسنجی و DTO (2-3 روز)
1. پیاده‌سازی اعتبارسنجی
2. پیاده‌سازی ساخت DTO
3. تست تبدیل فاکتور

### فاز 4: ارسال واقعی (2-3 روز)
1. جایگزینی شبیه‌سازی با ارسال واقعی
2. مدیریت خطاها
3. تست ارسال

### فاز 5: استعلام و مدیریت خطا (1-2 روز)
1. پیاده‌سازی استعلام وضعیت
2. نمایش خطاها در فرانت
3. امکان ارسال مجدد

**کل زمان تخمینی**: 8-13 روز کاری

---

## نکات مهم

1. **کتابخانه Moadian**: باید بررسی شود که آیا کتابخانه Python معادل وجود دارد یا باید از API مستقیماً استفاده کرد.

2. **امنیت**: کلید خصوصی باید به صورت امن ذخیره شود (رمزنگاری شده).

3. **Sandbox**: باید امکان تست در محیط Sandbox وجود داشته باشد.

4. **خطاها**: باید تمام خطاهای سامانه به درستی مدیریت و نمایش داده شوند.

5. **لاگ**: باید تمام عملیات ارسال لاگ شوند.

---

**تاریخ به‌روزرسانی**: 2025-01-XX

