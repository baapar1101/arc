# نحوه تشخیص کسب‌وکار در فعال‌سازی گارانتی

## سوال
در صفحه فعال‌سازی عمومی گارانتی که endpoint آن business_id ندارد، سیستم چطور می‌فهمد که این کد گارانتی مربوط به کدام کسب‌وکار است؟

## پاسخ

سیستم به صورت **خودکار و هوشمند** کسب‌وکار را تشخیص می‌دهد.

## مکانیزم تشخیص

### مرحله 1: ارسال اطلاعات از فرانت‌اند

**Endpoint عمومی**: `POST /api/v1/warranty/public/activate`

**Request Body**:
```json
{
  "warranty_code": "WR-ABC12345",
  "warranty_serial": "XYZ789012",
  "customer_name": "علی احمدی",
  "customer_phone": "09123456789"
}
```

**نکته مهم**: در این request هیچ اطلاعاتی از `business_id` ارسال نمی‌شود!

### مرحله 2: جستجوی کد گارانتی در دیتابیس

**فایل**: `hesabixAPI/app/services/warranty_service.py` (خط 433-438)

```python
def activate_warranty(...):
    repo = WarrantyCodeRepository(db)
    
    # یافتن کد گارانتی
    warranty_code = repo.get_by_code(warranty_code_str)
    if not warranty_code:
        raise ApiError("WARRANTY_CODE_NOT_FOUND", "کد گارانتی یافت نشد")
```

**Repository Query**:
```python
def get_by_code(self, code: str) -> Optional[WarrantyCode]:
    stmt = select(WarrantyCode).where(WarrantyCode.code == code)
    return self.db.execute(stmt).scalars().first()
```

### مرحله 3: استخراج business_id از رکورد کد گارانتی

**نکته کلیدی**: جدول `warranty_codes` دارای فیلد `business_id` است:

```python
class WarrantyCode(Base):
    __tablename__ = "warranty_codes"
    
    id: Mapped[int] = mapped_column(primary_key=True)
    business_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("businesses.id", ondelete="CASCADE"), 
        nullable=False, 
        index=True
    )
    code: Mapped[str] = mapped_column(String(50), nullable=False)
    # ... سایر فیلدها
```

**ویژگی‌های مهم**:
- `code` در سطح **کل سیستم یکتا** است (UniqueConstraint)
- هر کد گارانتی متعلق به **یک کسب‌وکار** است

### مرحله 4: استفاده از business_id

پس از پیدا کردن کد گارانتی، `business_id` از همان رکورد استخراج و استفاده می‌شود:

```python
# بررسی فعال بودن پلاگین برای کسب و کار
if not _check_warranty_plugin_active(db, warranty_code.business_id):
    raise ApiError("PLUGIN_NOT_ACTIVE", ...)

# دریافت تنظیمات
settings = _get_or_create_warranty_settings(db, warranty_code.business_id)

# جستجوی ProductInstance
product_instance = db.query(ProductInstance).filter(
    and_(
        ProductInstance.business_id == warranty_code.business_id,
        # ...
    )
).first()

# جستجوی Person
person = _find_person_by_phone(db, warranty_code.business_id, customer_phone)
```

## فلوچارت فرآیند

```
مشتری وارد می‌کند:
  ↓
  warranty_code = "WR-ABC12345"
  ↓
سیستم جستجو می‌کند در دیتابیس:
  ↓
  SELECT * FROM warranty_codes WHERE code = 'WR-ABC12345'
  ↓
رکورد پیدا می‌شود:
  {
    id: 123,
    business_id: 5,  ← این مقدار استخراج می‌شود
    code: "WR-ABC12345",
    warranty_serial: "XYZ789012",
    product_id: 100,
    ...
  }
  ↓
استفاده از warranty_code.business_id:
  - بررسی فعال بودن پلاگین
  - دریافت تنظیمات گارانتی
  - جستجوی Person
  - جستجوی ProductInstance
```

## چرا این روش کار می‌کند؟

### 1. کد گارانتی یکتای جهانی (Global Unique)

```python
UniqueConstraint("code", name="uq_warranty_codes_code")
```

کد گارانتی در **سطح کل سیستم** یکتا است، نه فقط در سطح کسب‌وکار.

مثال:
- کسب‌وکار A: کد `WR-ABC12345`
- کسب‌وکار B: نمی‌تواند کد `WR-ABC12345` داشته باشد ❌
- کسب‌وکار B: باید کد دیگری مثل `WR-XYZ67890` داشته باشد ✅

### 2. رابطه Foreign Key

```python
business_id: Mapped[int] = mapped_column(
    Integer, 
    ForeignKey("businesses.id", ondelete="CASCADE")
)
```

هر کد گارانتی به **یک کسب‌وکار** متصل است و این ارتباط در دیتابیس حفظ می‌شود.

### 3. مزایای این طراحی

✅ **سادگی برای مشتری**: 
- مشتری فقط کد گارانتی را وارد می‌کند
- نیازی به وارد کردن نام کسب‌وکار یا business_id نیست

✅ **امنیت**:
- کد گارانتی یکتا است و قابل جعل نیست
- ارتباط با کسب‌وکار در دیتابیس محافظت شده است

✅ **انعطاف‌پذیری**:
- هر کسب‌وکار می‌تواند تنظیمات خود را داشته باشد
- سیستم به صورت خودکار تنظیمات مربوطه را اعمال می‌کند

## مثال عملی

### کسب‌وکار A (business_id = 1):
تولید کد: `WR-2024-000001`
```sql
INSERT INTO warranty_codes (business_id, code, warranty_serial, ...)
VALUES (1, 'WR-2024-000001', 'SERIAL-123', ...)
```

### کسب‌وکار B (business_id = 2):
تولید کد: `WR-2024-000002`
```sql
INSERT INTO warranty_codes (business_id, code, warranty_serial, ...)
VALUES (2, 'WR-2024-000002', 'SERIAL-456', ...)
```

### مشتری فعال‌سازی می‌کند:
```
POST /api/v1/warranty/public/activate
{
  "warranty_code": "WR-2024-000001"
}
```

### سیستم:
1. جستجو می‌کند: `SELECT * FROM warranty_codes WHERE code = 'WR-2024-000001'`
2. رکورد را پیدا می‌کند با `business_id = 1`
3. از تنظیمات کسب‌وکار 1 استفاده می‌کند
4. Person را در کسب‌وکار 1 جستجو می‌کند
5. ProductInstance را در کسب‌وکار 1 جستجو می‌کند

## نقش businessCode در صفحه فعال‌سازی

**سوال**: اگر `businessCode` به عنوان parameter به `PublicWarrantyActivationPage` پاس می‌شود، چه استفاده‌ای دارد؟

**پاسخ**: 

در حال حاضر `businessCode` **استفاده نمی‌شود**:

```dart
class PublicWarrantyActivationPage extends StatefulWidget {
  final String? businessCode;  // ⚠️ استفاده نمی‌شود
  
  const PublicWarrantyActivationPage({
    super.key,
    this.businessCode,
  });
}
```

**استفاده‌های احتمالی آینده**:
1. نمایش لوگو یا نام کسب‌وکار
2. Pre-validation قبل از ارسال به API
3. نمایش تنظیمات خاص کسب‌وکار
4. Custom branding

اما در پیاده‌سازی فعلی، **business_id به صورت خودکار از کد گارانتی استخراج می‌شود**.

## خلاصه

سیستم از **کد گارانتی یکتا** برای تشخیص کسب‌وکار استفاده می‌کند:

1. کد گارانتی در سطح سیستم یکتا است
2. هر کد گارانتی business_id خود را در دیتابیس دارد
3. سیستم پس از پیدا کردن کد، business_id را از رکورد می‌خواند
4. تمام عملیات بعدی با business_id استخراج شده انجام می‌شود

**نتیجه**: مشتری فقط باید کد گارانتی را وارد کند و سیستم به صورت خودکار کسب‌وکار را تشخیص می‌دهد.

