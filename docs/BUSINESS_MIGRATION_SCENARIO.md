# سناریوی انتقال کسب و کارها از hesabixOld به hesabixpy

## خلاصه اجرایی

این سند سناریوی کامل انتقال کسب و کارها (businesses) از دیتابیس قدیمی (`hesabixOld`) به دیتابیس جدید (`hesabixpy`) را ارائه می‌دهد. تمرکز اصلی بر روی نحوه انتقال کسب و کارها و نگاشت صحیح owner_id به کاربران منتقل شده است.

## وضعیت فعلی

### دیتابیس قدیمی (hesabixOld)
- **جدول**: `business`
- **تعداد کسب و کارها**: 4,473 کسب و کار
- **فیلدهای کلیدی**:
  - `id`: شناسه یکتا
  - `owner_id`: شناسه مالک (ارجاع به جدول user)
  - `name`: نام کسب و کار
  - `legal_name`: نام قانونی
  - `field`: زمینه فعالیت (varchar - مقادیر مختلف)
  - `type`: نوع کسب و کار (varchar - مقادیر: فروشگاه، مغازه، شخصی، شرکت، موسسه، باشگاه، اتحادیه)
  - `shenasemeli`: شناسه ملی
  - `codeeghtesadi`: کد اقتصادی
  - `shomaresabt`: شماره ثبت
  - `country`: کشور
  - `ostan`: استان
  - `shahrestan`: شهرستان
  - `postalcode`: کد پستی
  - `tel`: تلفن
  - `mobile`: موبایل
  - `address`: آدرس
  - `email`: ایمیل
  - `wesite`: وب‌سایت (با typo)
  - و فیلدهای تنظیمات دیگر...

### دیتابیس جدید (hesabixpy)
- **جدول**: `businesses`
- **تعداد کسب و کارهای فعلی**: 63 کسب و کار
- **فیلدهای کلیدی**:
  - `id`: شناسه یکتا
  - `owner_id`: شناسه مالک (ارجاع به جدول users - ForeignKey)
  - `name`: نام کسب و کار
  - `business_type`: نوع کسب و کار (ENUM: شرکت، مغازه، فروشگاه، اتحادیه، باشگاه، موسسه، شخصی)
  - `business_field`: زمینه فعالیت (ENUM: تولیدی، بازرگانی، خدماتی، سایر)
  - `national_id`: شناسه ملی
  - `registration_number`: شماره ثبت
  - `economic_id`: کد اقتصادی
  - `country`: کشور
  - `province`: استان
  - `city`: شهرستان
  - `postal_code`: کد پستی
  - `phone`: تلفن
  - `mobile`: موبایل
  - `address`: آدرس
  - `default_currency_id`: ارز پیش‌فرض
  - `logo_file_id`: شناسه فایل لوگو
  - `stamp_file_id`: شناسه فایل مهر
  - `default_credit_limit`: سقف اعتبار پیش‌فرض
  - `check_credit_enabled_by_default`: بررسی اعتبار به صورت پیش‌فرض
  - `created_at`: تاریخ ایجاد
  - `updated_at`: تاریخ به‌روزرسانی
  - `deleted_at`: تاریخ حذف (soft delete)

### مشکلات شناسایی شده
1. **نگاشت owner_id**: باید از شناسه کاربر قدیمی به شناسه کاربر جدید نگاشت شود
2. **تبدیل type و field**: باید از varchar به ENUM تبدیل شوند
3. **تفاوت در نام فیلدها**: `ostan` → `province`, `shahrestan` → `city`, `tel` → `phone`
4. **فیلدهای جدید**: `default_currency_id`, `logo_file_id`, `stamp_file_id` و... در قدیمی وجود ندارند
5. **37 کسب و کار** از دیتابیس قدیمی در دیتابیس جدید وجود دارند (احتمالاً کسب و کارهای تست)

### آمار و ارقام
- **کل کسب و کارها در قدیمی**: 4,473
- **کسب و کارها با owner_id**: 4,473 (همه کسب و کارها owner دارند)
- **کسب و کارها با owner معتبر**: 4,415 (با کاربر فعال و email/mobile)
- **کسب و کارهای قابل انتقال**: ~4,062 (با owner که در دیتابیس جدید وجود دارد)
- **کسب و کارهای موجود در جدید**: 63

### توزیع نوع کسب و کارها (type)
- مغازه: 1,410
- شرکت: 1,121
- شخصی: 1,003
- فروشگاه: 718
- موسسه: 182
- باشگاه: 26
- اتحادیه: 13

## سناریوی انتقال

### مرحله 1: آماده‌سازی و بررسی

#### 1.1 بررسی داده‌های قدیمی
```sql
-- بررسی کسب و کارها با owner_id معتبر
SELECT COUNT(*) FROM hesabixOld.business WHERE owner_id IS NOT NULL;

-- بررسی کسب و کارها با owner_id که در دیتابیس جدید وجود دارد
SELECT COUNT(*) 
FROM hesabixOld.business old
INNER JOIN hesabixpy.users new ON old.owner_id = (
    SELECT old_user.id 
    FROM hesabixOld.user old_user
    INNER JOIN hesabixpy.users new_user ON old_user.email = new_user.email
    WHERE old_user.id = old.owner_id
    LIMIT 1
);

-- بررسی توزیع type
SELECT type, COUNT(*) as cnt 
FROM hesabixOld.business 
WHERE type IS NOT NULL 
GROUP BY type 
ORDER BY cnt DESC;

-- بررسی توزیع field
SELECT field, COUNT(*) as cnt 
FROM hesabixOld.business 
WHERE field IS NOT NULL 
GROUP BY field 
ORDER BY cnt DESC 
LIMIT 20;
```

#### 1.2 ایجاد جدول mapping برای owner_id
```sql
-- ایجاد جدول موقت برای نگهداری mapping کاربران
CREATE TEMPORARY TABLE user_id_mapping AS
SELECT 
    old.id as old_user_id,
    new.id as new_user_id
FROM hesabixOld.user old
INNER JOIN hesabixpy.users new ON (
    old.email = new.email OR 
    (old.mobile IS NOT NULL AND new.mobile IS NOT NULL AND old.mobile = new.mobile)
)
WHERE old.active = 1;
```

### مرحله 2: تبدیل و نگاشت داده‌ها

#### 2.1 تبدیل فیلدها

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `id` | - | نگه‌داری در mapping table (اختیاری) |
| `owner_id` | `owner_id` | نگاشت از user_id_mapping |
| `name` | `name` | مستقیم |
| `legal_name` | - | حذف (یا در name نگه داریم) |
| `type` | `business_type` | تبدیل به ENUM |
| `field` | `business_field` | تبدیل به ENUM |
| `shenasemeli` | `national_id` | مستقیم |
| `codeeghtesadi` | `economic_id` | مستقیم |
| `shomaresabt` | `registration_number` | مستقیم |
| `country` | `country` | مستقیم |
| `ostan` | `province` | مستقیم |
| `shahrestan` | `city` | مستقیم |
| `postalcode` | `postal_code` | مستقیم |
| `tel` | `phone` | مستقیم |
| `mobile` | `mobile` | مستقیم |
| `address` | `address` | مستقیم |
| `email` | - | حذف (در جدول users است) |
| `wesite` | - | حذف (در صورت نیاز می‌توان در جدول جداگانه نگه داشت) |

#### 2.2 تبدیل type به business_type (ENUM)

**مقادیر قدیمی** → **مقادیر جدید**:
- `"فروشگاه"` → `BusinessType.STORE` (`"فروشگاه"`)
- `"مغازه"` → `BusinessType.SHOP` (`"مغازه"`)
- `"شخصی"` → `BusinessType.INDIVIDUAL` (`"شخصی"`)
- `"شرکت"` → `BusinessType.COMPANY` (`"شرکت"`)
- `"موسسه"` → `BusinessType.INSTITUTE` (`"موسسه"`)
- `"باشگاه"` → `BusinessType.CLUB` (`"باشگاه"`)
- `"اتحادیه"` → `BusinessType.UNION` (`"اتحادیه"`)
- `NULL` یا مقادیر نامعتبر → `BusinessType.SHOP` (پیش‌فرض)

**الگوریتم**:
```python
def convert_business_type(old_type: str | None) -> str:
    mapping = {
        "فروشگاه": "فروشگاه",
        "مغازه": "مغازه",
        "شخصی": "شخصی",
        "شرکت": "شرکت",
        "موسسه": "موسسه",
        "باشگاه": "باشگاه",
        "اتحادیه": "اتحادیه"
    }
    if old_type and old_type in mapping:
        return mapping[old_type]
    return "مغازه"  # پیش‌فرض
```

#### 2.3 تبدیل field به business_field (ENUM)

**مقادیر قدیمی** → **مقادیر جدید**:
- `"تولید"`, `"تولیدی"`, `"تولید کننده"` → `BusinessField.MANUFACTURING` (`"تولیدی"`)
- `"بازرگانی"`, `"فروش"`, `"فروشگاه"` → `BusinessField.TRADING` (`"بازرگانی"`)
- `"خدماتی"` → `BusinessField.SERVICE` (`"خدماتی"`)
- سایر مقادیر → `BusinessField.OTHER` (`"سایر"`)

**الگوریتم**:
```python
def convert_business_field(old_field: str | None) -> str:
    if not old_field:
        return "سایر"
    
    old_field_lower = old_field.lower().strip()
    
    # تولیدی
    if any(keyword in old_field_lower for keyword in ["تولید", "ساخت"]):
        return "تولیدی"
    
    # بازرگانی
    if any(keyword in old_field_lower for keyword in ["بازرگانی", "فروش", "خرید", "تجارت"]):
        return "بازرگانی"
    
    # خدماتی
    if any(keyword in old_field_lower for keyword in ["خدمات", "خدماتی", "مشاوره", "آموزش"]):
        return "خدماتی"
    
    # سایر
    return "سایر"
```

#### 2.4 نگاشت owner_id

**الگوریتم**:
1. جستجو در `user_id_mapping` برای یافتن `new_user_id` بر اساس `old_owner_id`
2. اگر پیدا شد: استفاده از آن
3. اگر پیدا نشد: skip کردن کسب و کار (مالک در دیتابیس جدید وجود ندارد)

**SQL برای ایجاد mapping**:
```sql
-- ایجاد جدول mapping کاربران
CREATE TEMPORARY TABLE user_id_mapping AS
SELECT 
    old.id as old_user_id,
    new.id as new_user_id
FROM hesabixOld.user old
INNER JOIN hesabixpy.users new ON (
    (old.email IS NOT NULL AND new.email IS NOT NULL AND old.email = new.email) OR
    (old.mobile IS NOT NULL AND new.mobile IS NOT NULL AND old.mobile = new.mobile)
)
WHERE old.active = 1;
```

### مرحله 3: الگوریتم انتقال

#### 3.1 فیلتر کسب و کارها برای انتقال

**شرایط انتقال**:
1. کسب و کار باید `owner_id` داشته باشد
2. `owner_id` باید در `user_id_mapping` وجود داشته باشد (یعنی کاربر منتقل شده باشد)
3. کسب و کار نباید در دیتابیس جدید وجود داشته باشد (بر اساس owner_id و name)

**SQL برای انتخاب کسب و کارها**:
```sql
SELECT b.*
FROM hesabixOld.business b
INNER JOIN user_id_mapping m ON b.owner_id = m.old_user_id
WHERE b.owner_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM hesabixpy.businesses new
    WHERE new.owner_id = m.new_user_id
      AND new.name = b.name
  )
ORDER BY b.id;
```

#### 3.2 پردازش هر کسب و کار

**مراحل پردازش**:

1. **بررسی owner_id**:
   - جستجو در `user_id_mapping`
   - اگر پیدا نشد: skip با reason "owner_not_migrated"

2. **تبدیل داده‌ها**:
   - تبدیل `type` به `business_type` (ENUM)
   - تبدیل `field` به `business_field` (ENUM)
   - تبدیل نام فیلدها (`ostan` → `province`, `shahrestan` → `city`, `tel` → `phone`)
   - normalize کردن `mobile` و `phone`
   - تبدیل `date_submit` به `created_at` (اگر وجود دارد)

3. **ایجاد کسب و کار جدید**:
   - درج در جدول `businesses`
   - تنظیم `owner_id` به `new_user_id`
   - تنظیم `created_at` و `updated_at`

4. **مدیریت خطاها**:
   - در صورت خطا: ثبت در لاگ با جزئیات
   - ادامه با کسب و کار بعدی

#### 3.3 مدیریت کسب و کارهای تکراری

**سناریو 1: کسب و کار با همان owner و name در دیتابیس جدید وجود دارد**
- بررسی: آیا کسب و کار با همان `owner_id` و `name` در دیتابیس جدید وجود دارد؟
- عمل: skip کردن با reason "already_exists"
- ثبت در لاگ

**سناریو 2: owner_id در دیتابیس جدید وجود ندارد**
- بررسی: آیا `owner_id` در `user_id_mapping` وجود دارد؟
- عمل: skip کردن با reason "owner_not_migrated"
- ثبت در لاگ

### مرحله 4: فیلدهای اختیاری و پیش‌فرض

#### 4.1 فیلدهای جدید در دیتابیس جدید

**فیلدهایی که در قدیمی وجود ندارند**:
- `default_currency_id`: `NULL` (می‌توان بعداً تنظیم کرد)
- `logo_file_id`: `NULL` (فایل‌ها باید جداگانه منتقل شوند)
- `stamp_file_id`: `NULL` (فایل‌ها باید جداگانه منتقل شوند)
- `default_credit_limit`: `NULL` (می‌توان بعداً تنظیم کرد)
- `check_credit_enabled_by_default`: `false` (پیش‌فرض)

#### 4.2 تبدیل تاریخ‌ها

**الگوریتم**:
- اگر `date_submit` وجود دارد: تبدیل به `datetime` و استفاده در `created_at`
- در غیر این صورت: استفاده از `datetime.utcnow()`
- `updated_at`: همیشه `datetime.utcnow()`

### مرحله 5: اسکریپت انتقال

#### 5.1 ساختار اسکریپت

**فایل**: `scripts/migrate_businesses_from_old_db.py`

**ویژگی‌ها**:
1. اتصال به هر دو دیتابیس
2. ایجاد `user_id_mapping` از کاربران منتقل شده
3. خواندن کسب و کارها از دیتابیس قدیمی
4. تبدیل و نگاشت داده‌ها
5. درج در دیتابیس جدید
6. لاگ‌گیری کامل
7. قابلیت dry-run (تست بدون تغییر)
8. پردازش batch به batch

#### 5.2 پارامترهای اسکریپت

```bash
python scripts/migrate_businesses_from_old_db.py [OPTIONS]
```

**پارامترها**:
- `--dry-run`: اجرای تست بدون تغییر در دیتابیس
- `--batch-size`: تعداد کسب و کارها در هر batch (پیش‌فرض: 100)
- `--start-id`: شروع از شناسه خاص
- `--limit`: محدود کردن تعداد کسب و کارها
- `--old-db`: نام دیتابیس قدیمی (پیش‌فرض: hesabixOld)
- `--new-db`: نام دیتابیس جدید (پیش‌فرض: hesabixpy)
- `--db-user`: نام کاربری دیتابیس (پیش‌فرض: root)
- `--db-password`: رمز عبور دیتابیس (پیش‌فرض: 136431)
- `--db-host`: آدرس دیتابیس (پیش‌فرض: localhost)
- `--db-port`: پورت دیتابیس (پیش‌فرض: 3306)

#### 5.3 خروجی و گزارش

**گزارش شامل**:
- تعداد کل کسب و کارهای پردازش شده
- تعداد کسب و کارهای منتقل شده
- تعداد کسب و کارهای skip شده (با دلایل):
  - `owner_not_migrated`: مالک در دیتابیس جدید وجود ندارد
  - `already_exists`: کسب و کار در دیتابیس جدید وجود دارد
  - `invalid_data`: داده‌های نامعتبر
- تعداد خطاها
- لیست خطاها با جزئیات

### مرحله 6: تست و اعتبارسنجی

#### 6.1 تست‌های واحد

1. **تست تبدیل business_type**:
   - ورودی: `"فروشگاه"` → خروجی: `"فروشگاه"`
   - ورودی: `"مغازه"` → خروجی: `"مغازه"`
   - ورودی: `NULL` → خروجی: `"مغازه"` (پیش‌فرض)

2. **تست تبدیل business_field**:
   - ورودی: `"تولیدی"` → خروجی: `"تولیدی"`
   - ورودی: `"بازرگانی"` → خروجی: `"بازرگانی"`
   - ورودی: `"خدماتی"` → خروجی: `"خدماتی"`
   - ورودی: `"کامپیوتری"` → خروجی: `"سایر"`

3. **تست نگاشت owner_id**:
   - تست با owner_id موجود در mapping
   - تست با owner_id غیرموجود در mapping

#### 6.2 تست یکپارچگی

1. **تست انتقال نمونه**:
   - انتخاب 10 کسب و کار نمونه از دیتابیس قدیمی
   - انتقال آنها
   - بررسی صحت داده‌ها
   - بررسی foreign key constraint (owner_id)

2. **تست تکراری بودن**:
   - تست skip کردن کسب و کارهای تکراری

#### 6.3 تست عملکرد

1. **تست سرعت**:
   - اندازه‌گیری زمان انتقال 1000 کسب و کار
   - بهینه‌سازی در صورت نیاز

### مرحله 7: اجرای نهایی

#### 7.1 آماده‌سازی

1. **پشتیبان‌گیری**:
   - پشتیبان از دیتابیس `hesabixpy`
   - پشتیبان از دیتابیس `hesabixOld`

2. **تست در محیط staging**:
   - اجرای کامل در محیط تست
   - بررسی نتایج

#### 7.2 اجرا

1. **اجرای dry-run**:
   ```bash
   python scripts/migrate_businesses_from_old_db.py --dry-run --verbose
   ```

2. **بررسی نتایج dry-run**:
   - بررسی تعداد کسب و کارها
   - بررسی خطاها
   - بررسی owner_id mapping

3. **اجرای واقعی**:
   ```bash
   python scripts/migrate_businesses_from_old_db.py --batch-size 100 --verbose
   ```

4. **نظارت**:
   - نظارت بر لاگ‌ها
   - بررسی خطاها
   - بررسی عملکرد

#### 7.3 پس از اجرا

1. **اعتبارسنجی**:
   - مقایسه تعداد کسب و کارها
   - بررسی foreign key constraint
   - بررسی یکپارچگی داده‌ها
   - تست ایجاد کسب و کار جدید

2. **پاکسازی**:
   - حذف جدول موقت `user_id_mapping` (خودکار)

## خلاصه مراحل

1. ⏳ بررسی و آماده‌سازی داده‌ها
2. ⏳ ایجاد user_id_mapping
3. ⏳ نوشتن اسکریپت انتقال
4. ⏳ تست در محیط staging (با --dry-run)
5. ⏳ پشتیبان‌گیری
6. ⏳ اجرای انتقال
7. ⏳ اعتبارسنجی

## نکات مهم

1. **نگاشت owner_id**: فقط کسب و کارهایی منتقل می‌شوند که مالک آن‌ها در دیتابیس جدید وجود دارد
2. **تبدیل ENUM**: type و field باید به درستی به ENUM تبدیل شوند
3. **کاربران تکراری**: کسب و کارهایی که در دیتابیس جدید وجود دارند را skip می‌کنیم
4. **فیلدهای جدید**: فیلدهای جدید در دیتابیس جدید با مقادیر پیش‌فرض یا NULL تنظیم می‌شوند
5. **لاگ‌گیری**: تمام مراحل را لاگ می‌کنیم برای audit و debug

## ریسک‌ها و راه‌حل‌ها

### ریسک 1: از دست رفتن داده‌ها
**راه‌حل**: پشتیبان‌گیری کامل قبل از انتقال

### ریسک 2: خطا در انتقال
**راه‌حل**: استفاده از transaction و rollback در صورت خطا

### ریسک 3: کسب و کارهای تکراری
**راه‌حل**: بررسی دقیق قبل از انتقال و skip کردن تکراری‌ها

### ریسک 4: owner_id نامعتبر
**راه‌حل**: بررسی وجود owner_id در user_id_mapping قبل از انتقال

### ریسک 5: تبدیل نامعتبر ENUM
**راه‌حل**: استفاده از مقادیر پیش‌فرض برای مقادیر نامعتبر

## نتیجه‌گیری

این سناریو راهنمای کامل انتقال کسب و کارها از دیتابیس قدیمی به جدید است. تمرکز اصلی بر روی:
- نگاشت صحیح owner_id به کاربران منتقل شده
- تبدیل صحیح type و field به ENUM
- مدیریت کسب و کارهای تکراری
- حفظ یکپارچگی داده‌ها

پس از اجرای موفق، کسب و کارها با مالک‌های صحیح در دیتابیس جدید ایجاد می‌شوند و می‌توانند استفاده شوند.

