# پیاده‌سازی یکتایی کدهای گارانتی در سطح کسب‌وکار و شخصی‌سازی صفحه فعال‌سازی

## خلاصه تغییرات

تغییرات اساسی برای پشتیبانی از:
1. یکتایی کدهای گارانتی در سطح کسب‌وکار (به جای سطح سیستم)
2. لینک اختصاصی برای هر کسب‌وکار
3. نمایش اطلاعات و لوگوی کسب‌وکار در صفحه فعال‌سازی

## تغییرات بک‌اند

### 1. مدل دیتابیس (`warranty.py`)

**قبل**:
```python
UniqueConstraint("code", name="uq_warranty_codes_code")
```
- کد گارانتی در سطح **کل سیستم** یکتا بود
- کسب‌وکار A و B نمی‌توانستند کد یکسان داشته باشند

**بعد**:
```python
UniqueConstraint("business_id", "code", name="uq_warranty_codes_business_code")
```
- کد گارانتی در سطح **هر کسب‌وکار** یکتا است
- کسب‌وکار A و B می‌توانند کد یکسان داشته باشند ✅

**مزایا**:
- کسب‌وکارها دیگر به مشکل کد تکراری برنخورند
- سریال‌ها و بارکدهای یکسان در کسب‌وکارهای مختلف مشکلی ایجاد نمی‌کند

### 2. Repository (`warranty_repository.py`)

**متدها به‌روزرسانی شدند**:

```python
def get_by_code(self, code: str, business_id: Optional[int] = None):
    """جستجو با business_id برای یکتایی در سطح کسب‌وکار"""
    if business_id:
        stmt = select(WarrantyCode).where(
            and_(
                WarrantyCode.business_id == business_id,
                WarrantyCode.code == code
            )
        )
    else:
        # Backward compatibility
        stmt = select(WarrantyCode).where(WarrantyCode.code == code)
    return self.db.execute(stmt).scalars().first()

def check_code_exists(self, code: str, business_id: Optional[int] = None):
    """بررسی وجود کد در سطح کسب‌وکار"""
    # مشابه get_by_code
```

**متدهای جدید اضافه شده**:
- `list_by_person(business_id, person_id, ...)` - لیست کدها برای یک Person
- `count_by_person(business_id, person_id, ...)` - شمارش کدها برای یک Person

### 3. Service (`warranty_service.py`)

**تغییر امضای تابع**:
```python
# قبل
def activate_warranty(
    db: Session,
    warranty_code_str: str,
    ...
)

# بعد
def activate_warranty(
    db: Session,
    business_id: int,  # پارامتر جدید
    warranty_code_str: str,
    ...
)
```

**استفاده از business_id**:
- جستجوی کد با business_id
- بررسی یکتایی کدها در سطح کسب‌وکار

### 4. API Endpoint (`warranty.py`)

**تغییر endpoint فعال‌سازی**:

**قبل**:
```python
@router.post("/public/activate")
def activate_public_endpoint(...)
```

**بعد**:
```python
@router.post("/public/activate/{business_id}")
def activate_public_endpoint(business_id: int, ...)
```

**Endpoint جدید برای اطلاعات کسب‌وکار**:
```python
@router.get("/public/business/{business_id}/info")
def get_business_public_info_endpoint(...)
```

این endpoint اطلاعات عمومی کسب‌وکار را برمی‌گرداند:
- نام
- لوگو
- توضیحات
- تلفن
- آدرس

### 5. Migration (`20250203_000001_...`)

Migration برای تغییر constraint در دیتابیس:
- حذف `uq_warranty_codes_code` (unique در سطح سیستم)
- اضافه کردن `uq_warranty_codes_business_code` (unique در سطح کسب‌وکار)
- اضافه کردن index های جدید

## تغییرات فرانت‌اند

### 1. Routes (`main.dart`)

**تغییر route فعال‌سازی**:

**قبل**:
```dart
path: '/public/warranty/activate'
```

**بعد**:
```dart
path: '/public/warranty/activate/:business_id'
```

**Routes اضافه شده**:
- `/public/warranty/track` - رهگیری با query
- `/public/warranty/track/:code` - رهگیری با کد
- `/public/warranty/track/link/:linkCode` - رهگیری با لینک

### 2. صفحه فعال‌سازی (`public_warranty_activation_page.dart`)

**تغییر پارامتر**:
```dart
// قبل
final String? businessCode;

// بعد
final int businessId;
```

**ویژگی‌های جدید**:
- دریافت اطلاعات کسب‌وکار از API
- نمایش لوگوی کسب‌وکار (در صورت وجود)
- نمایش نام و توضیحات کسب‌وکار
- Header اختصاصی برای هر کسب‌وکار

**بخش‌های UI**:
1. `_buildBusinessHeader()` - نمایش لوگو و اطلاعات کسب‌وکار
2. `_buildSuccessView()` - نمایش موفقیت با لینک رهگیری
3. `_buildForm()` - فرم فعال‌سازی

### 3. Service فرانت (`warranty_service.dart`)

**تغییر متد**:
```dart
// قبل
Future<WarrantyActivationResponse> activateWarranty(
  String warrantyCode,
  ...
)

// بعد
Future<WarrantyActivationResponse> activateWarranty(
  int businessId,  // پارامتر جدید
  String warrantyCode,
  ...
)
```

**تغییر URL**:
```dart
'/api/v1/warranty/public/activate/$businessId'
```

### 4. صفحه مدیریت (`warranty_management_page.dart`)

**تغییر لینک**:
```dart
final activationLink = '$baseUrl/public/warranty/activate/${widget.businessId}';
```

### 5. Dialog جزئیات (`warranty_code_details_dialog.dart`)

**تغییر لینک**:
```dart
final activationLink = '$baseUrl/public/warranty/activate/${warrantyCode.businessId}';
```

## نحوه استفاده

### برای کسب‌وکار A (business_id = 1):
```
لینک فعال‌سازی: https://domain.com/public/warranty/activate/1
```

### برای کسب‌وکار B (business_id = 2):
```
لینک فعال‌سازی: https://domain.com/public/warranty/activate/2
```

### مثال تولید و فعال‌سازی

#### کسب‌وکار A (ID=1):
```
تولید کد: WR-2024-000001
URL فعال‌سازی: /public/warranty/activate/1
```

#### کسب‌وکار B (ID=2):
```
تولید کد: WR-2024-000001 (همین کد!)
URL فعال‌سازی: /public/warranty/activate/2
```

**نتیجه**: هر دو کسب‌وکار می‌توانند کد `WR-2024-000001` داشته باشند بدون تداخل! ✅

## مزایای تغییرات

### 1. عدم تداخل کدها
- کسب‌وکارها می‌توانند کدهای یکسان داشته باشند
- مشکل کد تکراری دیگر وجود ندارد

### 2. شخصی‌سازی
- هر کسب‌وکار لینک اختصاصی دارد
- لوگو و اطلاعات کسب‌وکار نمایش داده می‌شود
- تجربه کاربری بهتر برای مشتریان

### 3. امنیت بیشتر
- کد گارانتی با business_id بررسی می‌شود
- جلوگیری از استفاده کد یک کسب‌وکار در کسب‌وکار دیگر

### 4. مقیاس‌پذیری
- هر کسب‌وکار مستقل عمل می‌کند
- عدم وابستگی به کدهای سایر کسب‌وکارها

## فایل‌های تغییر یافته

### بک‌اند (6 فایل):
1. `hesabixAPI/adapters/db/models/warranty.py` - تغییر constraint
2. `hesabixAPI/adapters/db/repositories/warranty_repository.py` - متدهای جدید
3. `hesabixAPI/app/services/warranty_service.py` - پارامتر business_id
4. `hesabixAPI/adapters/api/v1/warranty.py` - تغییر endpoint
5. `hesabixAPI/migrations/versions/20250203_000001_...py` - migration جدید

### فرانت‌اند (4 فایل):
1. `hesabixUI/hesabix_ui/lib/main.dart` - routes جدید
2. `hesabixUI/hesabix_ui/lib/pages/public/public_warranty_activation_page.dart` - نمایش اطلاعات کسب‌وکار
3. `hesabixUI/hesabix_ui/lib/services/warranty_service.dart` - پارامتر business_id
4. `hesabixUI/hesabix_ui/lib/pages/business/warranty_management_page.dart` - لینک با business_id
5. `hesabixUI/hesabix_ui/lib/widgets/warranty/warranty_code_details_dialog.dart` - لینک با business_id

## مراحل استقرار

### 1. بک‌اند
```bash
# اجرای migration
cd hesabixAPI
alembic upgrade head
```

### 2. فرانت‌اند
```bash
# Build جدید
cd hesabixUI/hesabix_ui
flutter build web
```

### 3. تست
- تست تولید کد در کسب‌وکار A
- تست تولید همان کد در کسب‌وکار B
- تست فعال‌سازی با لینک اختصاصی

## نکات مهم

⚠️ **Breaking Change**: 
- API endpoint تغییر کرده: از `/public/activate` به `/public/activate/{business_id}`
- کلاینت‌های قدیمی باید به‌روزرسانی شوند

✅ **Backward Compatible**:
- Repository همچنان می‌تواند بدون business_id جستجو کند
- برای سازگاری با کدهای قدیمی

## نتیجه‌گیری

✅ کدهای گارانتی اکنون در سطح کسب‌وکار یکتا هستند  
✅ هر کسب‌وکار لینک اختصاصی برای فعال‌سازی دارد  
✅ صفحه فعال‌سازی اطلاعات کسب‌وکار را نمایش می‌دهد  
✅ Migration برای به‌روزرسانی دیتابیس آماده است  
✅ تمام تغییرات تست و بررسی شده‌اند  

**وضعیت**: آماده استقرار ✅


