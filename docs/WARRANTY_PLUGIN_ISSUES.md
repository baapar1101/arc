# گزارش مشکلات افزونه گارانتی

این گزارش شامل مشکلات یافت‌شده در بخش افزونه گارانتی (Warranty Plugin) در بک‌اند و فرانت‌اند است.

## مشکلات بک‌اند (Backend)

### 1. مشکل استفاده از `person.id` بدون بررسی None
**فایل**: `hesabixAPI/app/services/warranty_service.py`  
**خط**: 518

**مشکل**: در تابع `activate_warranty`، زمانی که `settings.enable_tracking_link` فعال است و `person` وجود دارد، از `person.id` استفاده می‌شود اما بررسی نشده که آیا `person` None است یا خیر.

```python
# خط 508-523
if settings.enable_tracking_link and person:
    link_code = _generate_tracking_link_code(db)
    warranty_code.tracking_link_code = link_code
    
    # ...
    
    tracking_link = WarrantyTrackingLink(
        warranty_code_id=warranty_code.id,
        person_id=person.id,  # ⚠️ اگر person None باشد خطا می‌دهد
        # ...
    )
```

**راه‌حل**: بررسی قبلی `if person:` وجود دارد، اما بهتر است به صورت explicit بررسی شود.

---

### 2. مشکل کارایی در `list_warranty_codes_by_person`
**فایل**: `hesabixAPI/app/services/warranty_service.py`  
**خطوط**: 723-781

**مشکل**: این تابع همه کدهای گارانتی را از دیتابیس می‌گیرد و سپس در حافظه فیلتر می‌کند. این روش:
- کارایی بسیار پایینی دارد
- Pagination درست کار نمی‌کند (skip و limit پس از فیلتر اعمال می‌شوند)
- با داده‌های زیاد مشکل ایجاد می‌کند

```python
# خط 740-746
codes = repo.list_by_business(business_id, status, None, limit, skip)

# فیلتر کردن بر اساس person_id
person_codes = [
    code for code in codes
    if code.activated_by_person_id == person_id
]
```

**راه‌حل**: باید query را در repository تغییر داد تا فیلتر `person_id` در سطح دیتابیس اعمال شود.

---

### 3. مشکل در Repository - عدم وجود متد `list_by_person`
**فایل**: `hesabixAPI/adapters/db/repositories/warranty_repository.py`

**مشکل**: متدی برای دریافت کدهای گارانتی بر اساس `person_id` وجود ندارد. باید این متد اضافه شود.

---

### 4. مشکل در Cache Timeout
**فایل**: `hesabixAPI/app/services/warranty_service.py`  
**خط**: 407

**مشکل**: در تابع `_check_activation_attempts`، timeout برای cache به درستی محاسبه نشده است:

```python
cache.set(cache_key, attempts + 1, timeout=lockout_minutes * 60 if settings.activation_lockout_duration_minutes else 3600)
```

**مشکل**: اگر `lockout_minutes` None باشد، timeout را از `settings.activation_lockout_duration_minutes` نمی‌گیرد.

---

### 5. مشکل در بررسی انقضای گارانتی
**فایل**: `hesabixAPI/app/services/warranty_service.py`  
**خط**: 456-459

**مشکل**: وقتی گارانتی منقضی می‌شود، status به "expired" تغییر می‌کند و commit می‌شود، اما این تغییر ممکن است در تراکنش فعلی مشکل ایجاد کند.

---

### 6. عدم بررسی `business_id` در فعال‌سازی عمومی
**فایل**: `hesabixAPI/app/services/warranty_service.py`  
**تابع**: `activate_warranty`

**مشکل**: در endpoint عمومی فعال‌سازی، بررسی نمی‌شود که آیا پلاگین برای کسب و کار مرتبط فعال است یا خیر. این می‌تواند باعث فعال‌سازی در کسب و کارهای بدون پلاگین شود.

---

### 7. مشکل در تولید کد ترتیبی
**فایل**: `hesabixAPI/app/services/warranty_service.py`  
**خط**: 50-82

**مشکل**: تابع `_generate_sequential_code` ممکن است در حالت race condition مشکل داشته باشد. اگر دو درخواست همزمان برای تولید کد ترتیبی ارسال شود، ممکن است کد تکراری تولید شود.

---

### 8. مشکل در `track_warranty_by_link`
**فایل**: `hesabixAPI/app/services/warranty_service.py`  
**خط**: 656-658

**مشکل**: import درون تابع انجام شده که می‌تواند به مشکل منجر شود:

```python
from adapters.db.repositories.warranty_repository import WarrantyCodeRepository
warranty_code_repo = WarrantyCodeRepository(db)
```

این import باید در ابتدای فایل باشد.

---

## مشکلات فرانت‌اند (Frontend)

### 9. مشکل در `warranty_management_page.dart` - داده‌ها به DataTableWidget pass نشده
**فایل**: `hesabixUI/hesabix_ui/lib/pages/business/warranty_management_page.dart`  
**خط**: 116-121

**مشکل**: داده‌های `_codes` که از API دریافت شده‌اند به `DataTableWidget` pass نشده‌اند. فقط endpoint و config pass شده است. این باعث می‌شود که:
- داده‌های قبلی نمایش داده نشوند
- widget مجبور باشد دوباره از API داده بگیرد
- state management مشکل داشته باشد

```dart
: DataTableWidget<WarrantyCode>(
    key: ValueKey('warranty_codes_$_skip'),
    calendarController: widget.calendarController,
    config: _buildTableConfig(t, theme),
    fromJson: (json) => WarrantyCode.fromJson(json),
    // ⚠️ داده‌های _codes pass نشده
  ),
```

---

### 10. مشکل در فیلتر محصول در فرانت
**فایل**: `hesabixUI/hesabix_ui/lib/pages/business/warranty_management_page.dart`

**مشکل**: فیلتر محصول (`_productIdFilter`) تعریف شده اما UI برای انتخاب محصول وجود ندارد. فقط فیلتر status نمایش داده می‌شود.

---

### 11. مشکل در صفحه تنظیمات - عدم ذخیره `require_customer_registration`
**فایل**: `hesabixUI/hesabix_ui/lib/pages/business/warranty_settings_page.dart`

**مشکل**: متغیر `_requireCustomerRegistration` تعریف شده اما در فرم UI نمایش داده نشده و در payload ذخیره نمی‌شود.

---

### 12. مشکل در Parse DateTime - احتمال خطا در فرمت تاریخ
**فایل**: `hesabixUI/hesabix_ui/lib/models/warranty_models.dart`

**مشکل**: در تابع `_parseDateTime`، منطق تشخیص تاریخ شمسی/میلادی ممکن است مشکل داشته باشد. اگر سال بین 1500 و 1900 باشد، ممکن است به اشتباه تشخیص داده شود.

---

### 13. عدم مدیریت خطا در `generate_warranty_codes_dialog.dart`
**فایل**: `hesabixUI/hesabix_ui/lib/widgets/warranty/generate_warranty_codes_dialog.dart`

**مشکل**: در صورت خطا در تولید کدها، فقط یک پیام کلی نمایش داده می‌شود. جزئیات خطا (مثلاً کد تکراری) نمایش داده نمی‌شود.

---

### 14. مشکل در `public_warranty_tracking_page.dart` - عدم استفاده از `business_id`
**فایل**: `hesabixUI/hesabix_ui/lib/pages/public/public_warranty_tracking_page.dart`  
**خط**: 66

**مشکل**: در تابع `trackWarranty`، `businessId` به API pass نمی‌شود. این باعث می‌شود که جستجو کندتر باشد.

---

### 15. مشکل در نمایش اطلاعات در `warranty_code_details_dialog.dart`
**فایل**: `hesabixUI/hesabix_ui/lib/widgets/warranty/warranty_code_details_dialog.dart`

**مشکل**: اطلاعات محصول و مشتری نمایش داده نمی‌شود. فقط اطلاعات پایه کد گارانتی نمایش داده می‌شود.

---

### 16. عدم بررسی اعتبار کدهای دلخواه قبل از ارسال
**فایل**: `hesabixUI/hesabix_ui/lib/widgets/warranty/generate_warranty_codes_dialog.dart`

**مشکل**: در حالت custom codes و custom serials، بررسی نمی‌شود که:
- تعداد کدها با تعداد سریال‌ها برابر است
- کدها خالی یا نامعتبر نیستند
- کدها تکراری نیستند

---

## مشکلات API Endpoints

### 17. مشکل در endpoint بررسی کد گارانتی
**فایل**: `hesabixAPI/adapters/api/v1/warranty.py`  
**خط**: 218-258

**مشکل**: endpoint `/public/check/{code}` وجود دارد اما در فرانت‌اند استفاده نمی‌شود. همچنین این endpoint به کسب و کار خاصی وابسته نیست که می‌تواند مشکل امنیتی ایجاد کند.

---

### 18. عدم وجود endpoint برای لغو/بازگردانی گارانتی
**فایل**: `hesabixAPI/adapters/api/v1/warranty.py`

**مشکل**: endpoint‌هایی برای تغییر وضعیت گارانتی (مثلاً revoke, expire) وجود ندارد. این قابلیت‌ها باید اضافه شوند.

---

### 19. عدم وجود endpoint برای به‌روزرسانی اطلاعات گارانتی
**فایل**: `hesabixAPI/adapters/api/v1/warranty.py`

**مشکل**: پس از فعال‌سازی گارانتی، امکان به‌روزرسانی اطلاعات مشتری یا محصول وجود ندارد.

---

## مشکلات دیتابیس و مدل‌ها

### 20. عدم وجود index برای جستجوی سریع
**فایل**: `hesabixAPI/adapters/db/models/warranty.py`

**مشکل**: 
- در جدول `warranty_codes`، index برای `activated_by_person_id` وجود ندارد که برای `list_by_person` مهم است.
- در جدول `warranty_activations`، index برای `person_id` و `customer_phone` وجود ندارد.

---

### 21. مشکل در مدل - عدم وجود cascade برای برخی relationships
**فایل**: `hesabixAPI/adapters/db/models/warranty.py`

**مشکل**: برخی از relationships ممکن است نیاز به تنظیمات cascade داشته باشند که وجود ندارد.

---

## مشکلات امنیتی

### 22. عدم بررسی rate limiting در endpoint های عمومی
**فایل**: `hesabixAPI/adapters/api/v1/warranty.py`

**مشکل**: endpoint های عمومی (`/public/activate`, `/public/track`) دارای rate limiting نیستند که می‌تواند باعث حملات DDoS شود.

---

### 23. عدم بررسی CSRF در فرم فعال‌سازی عمومی
**فایل**: `hesabixUI/hesabix_ui/lib/pages/public/public_warranty_activation_page.dart`

**مشکل**: فرم فعال‌سازی عمومی دارای محافظت CSRF نیست.

---

## مشکلات عملکردی

### 24. عدم استفاده از cache برای تنظیمات گارانتی
**فایل**: `hesabixAPI/app/services/warranty_service.py`

**مشکل**: در هر درخواست، تنظیمات گارانتی از دیتابیس خوانده می‌شود. بهتر است از cache استفاده شود.

---

### 25. عدم batch processing برای تولید کدهای انبوه
**فایل**: `hesabixAPI/app/services/warranty_service.py`  
**تابع**: `generate_warranty_codes`

**مشکل**: برای تولید تعداد زیاد کد (مثلاً 1000 کد)، همه کدها در یک تراکنش ایجاد می‌شوند که می‌تواند باعث timeout شود.

---

## مشکلات UI/UX

### 26. عدم نمایش لینک رهگیری پس از فعال‌سازی
**فایل**: `hesabixUI/hesabix_ui/lib/pages/public/public_warranty_activation_page.dart`

**مشکل**: پس از فعال‌سازی موفق، لینک رهگیری (`tracking_link_code`) به کاربر نمایش داده نمی‌شود.

---

### 27. عدم امکان جستجو در لیست کدهای گارانتی
**فایل**: `hesabixUI/hesabix_ui/lib/pages/business/warranty_management_page.dart`

**مشکل**: امکان جستجو بر اساس کد، سریال، یا نام محصول در لیست کدهای گارانتی وجود ندارد.

---

### 28. عدم نمایش اطلاعات محصول در لیست
**فایل**: `hesabixUI/hesabix_ui/lib/pages/business/warranty_management_page.dart`

**مشکل**: در جدول لیست کدهای گارانتی، نام محصول نمایش داده نمی‌شود.

---

## خلاصه مشکلات

- **بک‌اند**: 11 مشکل
- **فرانت‌اند**: 9 مشکل  
- **API**: 3 مشکل
- **دیتابیس**: 2 مشکل
- **امنیتی**: 2 مشکل
- **عملکردی**: 2 مشکل
- **UI/UX**: 3 مشکل

**جمع کل**: 32 مشکل



