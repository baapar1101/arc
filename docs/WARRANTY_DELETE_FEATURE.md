# قابلیت حذف ایمن کدهای گارانتی

## خلاصه

این قابلیت امکان حذف ایمن کدهای گارانتی (تکی و گروهی) را در افزونه گارانتی فراهم می‌کند. حذف به گونه‌ای طراحی شده است که بدون ایجاد مشکل در دیتای برنامه انجام شود.

## ویژگی‌های اصلی

### 1. حذف ایمن
- قبل از حذف، وضعیت کد بررسی می‌شود
- کدهای فعال شده تنها با استفاده از پارامتر `force=true` حذف می‌شوند
- تمام رکوردهای مرتبط (رویدادها، لینک‌ها، فعال‌سازی‌ها) به صورت خودکار حذف می‌شوند

### 2. حذف گروهی هوشمند
- قابلیت حذف چندین کد به صورت همزمان
- گزارش دقیق از موفق، رد شده و خطا
- عملیات ناقص باعث Rollback نمی‌شود

### 3. رابط کاربری کاربرپسند
- دیالوگ تأیید با هشدارهای واضح
- نمایش تعداد موارد انتخاب شده
- نمایش نتایج حذف گروهی در دیالوگ جداگانه

## تغییرات بکند

### 1. `warranty_service.py`

دو تابع اصلی اضافه شد:

#### `delete_warranty_code()`
```python
def delete_warranty_code(
    db: Session,
    business_id: int,
    code_id: int,
    force: bool = False
) -> Dict[str, Any]
```

**پارامترها:**
- `business_id`: شناسه کسب و کار
- `code_id`: شناسه کد گارانتی
- `force`: حذف اجباری کدهای فعال شده (پیش‌فرض: False)

**خروجی:**
```json
{
  "success": true,
  "message": "کد گارانتی با موفقیت حذف شد",
  "deleted_code": {
    "id": 123,
    "code": "WR-2025-001234",
    "warranty_serial": "ABC123XYZ456",
    "status": "generated"
  }
}
```

#### `delete_warranty_codes_bulk()`
```python
def delete_warranty_codes_bulk(
    db: Session,
    business_id: int,
    code_ids: List[int],
    force: bool = False
) -> Dict[str, Any]
```

**پارامترها:**
- `business_id`: شناسه کسب و کار
- `code_ids`: لیست شناسه‌های کدها
- `force`: حذف اجباری کدهای فعال شده (پیش‌فرض: False)

**خروجی:**
```json
{
  "success": true,
  "message": "عملیات حذف گروهی انجام شد",
  "summary": {
    "total_requested": 10,
    "deleted": 8,
    "skipped": 1,
    "failed": 1
  },
  "deleted_codes": [...],
  "skipped_codes": [
    {
      "id": 125,
      "code": "WR-2025-001236",
      "status": "activated",
      "reason": "کد فعال شده است"
    }
  ],
  "failed_codes": [
    {
      "id": 999,
      "reason": "کد گارانتی یافت نشد"
    }
  ]
}
```

### 2. `warranty.py` (API Endpoints)

دو endpoint جدید:

#### DELETE `/api/v1/warranty/business/{business_id}/codes/{code_id}`
حذف یک کد گارانتی

**Query Parameters:**
- `force` (bool, optional): حذف اجباری

**نیازمندیها:**
- احراز هویت
- دسترسی به کسب و کار
- پلاگین گارانتی فعال
- مجوز `warranty.delete`

#### POST `/api/v1/warranty/business/{business_id}/codes/bulk-delete`
حذف گروهی کدهای گارانتی

**Request Body:**
```json
{
  "code_ids": [123, 124, 125],
  "force": false
}
```

**نیازمندیها:**
- احراز هویت
- دسترسی به کسب و کار
- پلاگین گارانتی فعال
- مجوز `warranty.delete`

## تغییرات فرانت‌اند

### 1. `warranty_service.dart`

دو متد جدید:

```dart
Future<WarrantyDeleteResponse> deleteCode(
  int businessId,
  int codeId, {
  bool force = false,
})

Future<WarrantyBulkDeleteResponse> deleteCodes(
  int businessId,
  List<int> codeIds, {
  bool force = false,
})
```

دو کلاس Response:
- `WarrantyDeleteResponse`
- `WarrantyBulkDeleteResponse`

### 2. `warranty_management_page.dart`

**قابلیت‌های جدید:**
- انتخاب چندگانه کدها با Checkbox
- دکمه حذف در AppBar (فقط برای موارد انتخاب شده)
- دکمه حذف در منوی Actions هر ردیف
- نوار اطلاعاتی تعداد موارد انتخاب شده
- دیالوگ تأیید حذف تکی با هشدار برای کدهای فعال
- دیالوگ تأیید حذف گروهی
- دیالوگ نمایش نتایج حذف گروهی

**متدهای اضافه شده:**
- `_confirmSingleDelete()`: نمایش دیالوگ تأیید حذف تکی
- `_deleteSingleCode()`: انجام حذف تکی
- `_confirmBulkDelete()`: نمایش دیالوگ تأیید حذف گروهی
- `_deleteBulkCodes()`: انجام حذف گروهی
- `_showBulkDeleteResult()`: نمایش نتایج حذف گروهی
- `_buildSummaryRow()`: ساخت ردیف خلاصه

## نحوه استفاده

### حذف تکی از UI

1. در صفحه مدیریت گارانتی، روی منوی 3 نقطه هر کد کلیک کنید
2. گزینه "حذف" را انتخاب کنید
3. دیالوگ تأیید را تأیید کنید

### حذف گروهی از UI

1. Checkbox های کدهای مورد نظر را انتخاب کنید
2. روی دکمه سطل زباله در AppBar کلیک کنید
3. دیالوگ تأیید را تأیید کنید
4. نتایج حذف را در دیالوگ جداگانه مشاهده کنید

### استفاده از API

#### حذف تکی:
```bash
curl -X DELETE \
  "https://api.example.com/api/v1/warranty/business/1/codes/123?force=false" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### حذف گروهی:
```bash
curl -X POST \
  "https://api.example.com/api/v1/warranty/business/1/codes/bulk-delete" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "code_ids": [123, 124, 125],
    "force": true
  }'
```

## امنیت

### بررسی‌های امنیتی:
1. **احراز هویت:** تمام endpoint ها نیاز به احراز هویت دارند
2. **دسترسی:** بررسی تعلق کد به کسب و کار
3. **مجوزها:** نیاز به مجوز `warranty.delete`
4. **پلاگین:** بررسی فعال بودن پلاگین گارانتی
5. **Force Flag:** کدهای فعال شده تنها با `force=true` حذف می‌شوند

### رکوردهای حذف شده:
- `WarrantyTracking`: تمام رویدادهای رهگیری
- `WarrantyTrackingLink`: تمام لینک‌های رهگیری
- `WarrantyActivation`: رکورد فعال‌سازی
- `WarrantyCode`: خود کد گارانتی

## یکپارچگی داده

حذف به صورت transaction-based انجام می‌شود:
- اگر حذف یک رکورد مرتبط ناموفق باشد، کل عملیات Rollback می‌شود
- در حذف گروهی، خطا در یک کد باعث توقف حذف سایر کدها نمی‌شود
- هر کد به صورت مستقل پردازش و گزارش می‌شود

## مثال‌ها

### مثال 1: حذف موفق تکی
```json
{
  "status": "success",
  "data": {
    "success": true,
    "message": "کد گارانتی با موفقیت حذف شد",
    "deleted_code": {
      "id": 123,
      "code": "WR-2025-001234",
      "warranty_serial": "ABC123XYZ456",
      "status": "generated"
    }
  }
}
```

### مثال 2: خطا در حذف کد فعال شده بدون force
```json
{
  "status": "error",
  "error": {
    "code": "WARRANTY_CODE_ACTIVE",
    "message": "این کد گارانتی فعال شده است. برای حذف از پارامتر force استفاده کنید.",
    "http_status": 400
  }
}
```

### مثال 3: حذف گروهی با نتایج متفاوت
```json
{
  "status": "success",
  "data": {
    "success": true,
    "message": "عملیات حذف گروهی انجام شد",
    "summary": {
      "total_requested": 5,
      "deleted": 3,
      "skipped": 1,
      "failed": 1
    },
    "deleted_codes": [
      {"id": 123, "code": "WR-001", "status": "generated"},
      {"id": 124, "code": "WR-002", "status": "generated"},
      {"id": 125, "code": "WR-003", "status": "generated"}
    ],
    "skipped_codes": [
      {
        "id": 126,
        "code": "WR-004",
        "status": "activated",
        "reason": "کد فعال شده است"
      }
    ],
    "failed_codes": [
      {
        "id": 999,
        "reason": "کد گارانتی یافت نشد"
      }
    ]
  }
}
```

## تست

### تست‌های پیشنهادی:

1. **حذف تکی:**
   - حذف کد generated بدون force
   - حذف کد activated بدون force (باید خطا دهد)
   - حذف کد activated با force
   - حذف کد متعلق به کسب و کار دیگر (باید خطا دهد)

2. **حذف گروهی:**
   - حذف چند کد generated
   - حذف ترکیبی از کدهای generated و activated بدون force
   - حذف ترکیبی از کدهای generated و activated با force
   - حذف با شناسه‌های نامعتبر

3. **بررسی یکپارچگی:**
   - اطمینان از حذف تمام رکوردهای مرتبط
   - بررسی rollback در صورت خطا
   - اطمینان از عدم تأثیر بر سایر کسب و کارها

## نکات مهم

1. **استفاده از force با احتیاط:** حذف کدهای فعال شده می‌تواند بر داده‌های مشتریان تأثیر بگذارد

2. **پشتیبان‌گیری:** قبل از حذف گروهی، از دیتابیس backup تهیه کنید

3. **Audit Log:** در آینده می‌توان سیستم logging برای حذف‌ها اضافه کرد

4. **Soft Delete:** در صورت نیاز می‌توان به جای حذف فیزیکی، از soft delete استفاده کرد

## نکات فنی پیاده‌سازی

### مدیریت Selection در DataTableWidget

از آنجایی که `DataTableWidget` از index های ردیف برای selection استفاده می‌کند (نه id ها)، راه‌حل زیر پیاده‌سازی شده است:

1. **نگهداری دو لیست:**
   - `_selectedRowIndices`: Set از index های ردیف‌های انتخاب شده (برای UI)
   - `_currentPageCodes`: لیست کدهای صفحه فعلی (برای تبدیل index به id)

2. **مدیریت بارگذاری مجدد:**
   - استفاده از flag `_isFirstRowInNewLoad` برای تشخیص شروع بارگذاری جدید
   - پاک کردن `_currentPageCodes` در ابتدای هر بارگذاری

3. **تبدیل index به id:**
   - در `_deleteBulkCodes()`, index های انتخاب شده به id های واقعی تبدیل می‌شوند
   - بررسی null برای جلوگیری از خطا

### مدیریت Null Safety

- `WarrantyCode.id` به صورت `int?` تعریف شده است
- قبل از ارسال به API، بررسی null انجام می‌شود
- استفاده از null assertion operator (`!`) پس از بررسی

## نسخه

- **تاریخ:** 2025-01-20
- **نسخه:** 1.0.1
- **توسعه‌دهنده:** هسابیکس تیم
- **تغییرات v1.0.1:** رفع خطاهای کامپایل و بهبود مدیریت selection

