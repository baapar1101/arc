# تحلیل انتقال سال‌های مالی از hesabixOld به hesabixpy

## خلاصه اجرایی

این سند تحلیل نحوه انتقال سال‌های مالی (fiscal years) از دیتابیس قدیمی (`hesabixOld`) به دیتابیس جدید (`hesabixpy`) را ارائه می‌دهد.

## وضعیت فعلی

### دیتابیس قدیمی (hesabixOld)

#### جدول `year`
- **تعداد سال‌های مالی**: 4,473 سال مالی
- **ساختار**:
  - `id`: شناسه یکتا
  - `bid_id`: شناسه کسب و کار (ارجاع به `business.id`)
  - `label`: عنوان سال مالی (مثل "سال مالی منتهی به 1403/2/27")
  - `head`: آیا سال مالی فعال است؟ (tinyint - 1 = فعال، 0 = غیرفعال)
  - `start`: تاریخ شروع (varchar timestamp - مثل "1684322286")
  - `end`: تاریخ پایان (varchar timestamp - مثل "1715858286")
  - `now`: تاریخ فعلی (varchar timestamp - معمولاً NULL)

**ویژگی‌ها**:
- هر کسب و کار فقط **یک سال مالی** دارد
- همه سال‌های مالی `head = 1` دارند (همه فعال هستند)
- `start` و `end` به صورت timestamp (Unix timestamp) ذخیره شده‌اند
- `now` همیشه `NULL` است
- همه تاریخ‌ها معتبر هستند (هیچ NULL یا خالی نیست)

**نمونه داده**:
```
id | bid_id | label                        | head | start      | end        | now
2  | 4      | سال مالی منتهی به 1403/2/27 | 1    | 1684322286 | 1715858286 | NULL
```

### دیتابیس جدید (hesabixpy)

#### جدول `fiscal_years`
- **تعداد سال‌های مالی فعلی**: 64 سال مالی
- **ساختار**:
  - `id`: شناسه یکتا
  - `business_id`: شناسه کسب و کار (ارجاع به `businesses.id` - ForeignKey)
  - `title`: عنوان سال مالی
  - `start_date`: تاریخ شروع (DATE)
  - `end_date`: تاریخ پایان (DATE)
  - `is_last`: آیا آخرین سال مالی فعال است؟ (boolean)
  - `inventory_valuation_method`: روش ارزیابی انبار (varchar - پیش‌فرض: "FIFO")
  - `created_at`: تاریخ ایجاد
  - `updated_at`: تاریخ به‌روزرسانی

**ویژگی‌ها**:
- یک کسب و کار می‌تواند **چندین سال مالی** داشته باشد
- فقط یک سال مالی می‌تواند `is_last = true` باشد
- تاریخ‌ها به صورت DATE ذخیره می‌شوند (نه timestamp)
- فیلد `inventory_valuation_method` جدید است (پیش‌فرض: "FIFO")

## استراتژی انتقال

### تبدیل فیلدها

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `id` | - | نگه‌داری در mapping table (اختیاری) |
| `bid_id` | `business_id` | نگاشت از business_id_mapping |
| `label` | `title` | مستقیم |
| `head` | `is_last` | تبدیل boolean (1 → true, 0 → false) |
| `start` | `start_date` | تبدیل timestamp به DATE |
| `end` | `end_date` | تبدیل timestamp به DATE |
| `now` | - | حذف (همیشه NULL است) |
| - | `inventory_valuation_method` | پیش‌فرض: "FIFO" |
| - | `created_at` | `datetime.utcnow()` |
| - | `updated_at` | `datetime.utcnow()` |

### تبدیل timestamp به DATE

**الگوریتم**:
```python
def convert_timestamp_to_date(timestamp_str: str | None) -> date | None:
    """
    تبدیل timestamp string به date
    
    Args:
        timestamp_str: timestamp به صورت string (مثل "1684322286")
    
    Returns:
        date object یا None
    """
    if not timestamp_str or not timestamp_str.strip():
        return None
    
    try:
        # تبدیل string به int
        timestamp = int(timestamp_str.strip())
        # تبدیل timestamp به datetime
        dt = datetime.fromtimestamp(timestamp)
        # تبدیل به date
        return dt.date()
    except (ValueError, TypeError, OSError):
        return None
```

**مثال**:
- `"1684322286"` → `date(2023, 5, 17)`
- `"1715858286"` → `date(2024, 5, 16)`

### تبدیل head به is_last

**الگوریتم**:
```python
def convert_head_to_is_last(head: int | None) -> bool:
    """
    تبدیل head به is_last
    
    Args:
        head: مقدار head از دیتابیس قدیمی (1 = فعال، 0 = غیرفعال)
    
    Returns:
        boolean (true = آخرین سال مالی فعال)
    """
    return bool(head) if head is not None else False
```

**نکته**: در دیتابیس قدیمی همه سال‌های مالی `head = 1` دارند، پس همه `is_last = true` خواهند بود.

### نگاشت business_id

**الگوریتم**:
1. استفاده از `business_id_mapping` که در انتقال کسب و کارها ایجاد شده
2. جستجو برای `old_business_id = bid_id`
3. اگر پیدا شد: استفاده از `new_business_id`
4. اگر پیدا نشد: skip کردن سال مالی (کسب و کار منتقل نشده)

**SQL برای ایجاد mapping**:
```sql
-- استفاده از business_id_mapping از انتقال کسب و کارها
-- یا ایجاد مجدد:
SELECT 
    old_business.id as old_business_id,
    new_business.id as new_business_id
FROM hesabixOld.business old_business
INNER JOIN hesabixOld.user old_user ON old_business.owner_id = old_user.id
INNER JOIN hesabixpy.users new_user ON (
    (old_user.email IS NOT NULL AND new_user.email IS NOT NULL AND old_user.email = new_user.email) OR
    (old_user.mobile IS NOT NULL AND new_user.mobile IS NOT NULL AND old_user.mobile = new_user.mobile)
)
INNER JOIN hesabixpy.businesses new_business ON (
    new_business.owner_id = new_user.id 
    AND new_business.name = old_business.name
);
```

## الگوریتم انتقال

### مرحله 1: فیلتر سال‌های مالی برای انتقال

**شرایط انتقال**:
1. سال مالی باید `bid_id` داشته باشد
2. `bid_id` باید در `business_id_mapping` وجود داشته باشد (کسب و کار منتقل شده باشد)
3. `start` و `end` باید معتبر باشند (نه NULL و نه خالی)
4. سال مالی نباید در دیتابیس جدید وجود داشته باشد (بر اساس business_id و title)

**SQL برای انتخاب سال‌های مالی**:
```sql
SELECT y.*
FROM hesabixOld.year y
INNER JOIN business_id_mapping m ON y.bid_id = m.old_business_id
WHERE y.start IS NOT NULL 
  AND y.end IS NOT NULL
  AND y.start != ''
  AND y.end != ''
  AND NOT EXISTS (
    SELECT 1 FROM hesabixpy.fiscal_years new
    WHERE new.business_id = m.new_business_id
      AND new.title = y.label
  )
ORDER BY y.id;
```

### مرحله 2: پردازش هر سال مالی

**مراحل پردازش**:

1. **بررسی business_id**:
   - جستجو در `business_id_mapping`
   - اگر پیدا نشد: skip با reason "business_not_migrated"

2. **تبدیل داده‌ها**:
   - تبدیل `start` (timestamp) به `start_date` (DATE)
   - تبدیل `end` (timestamp) به `end_date` (DATE)
   - تبدیل `head` به `is_last` (boolean)
   - استفاده از `label` به عنوان `title`

3. **ایجاد سال مالی جدید**:
   - درج در جدول `fiscal_years`
   - تنظیم `business_id` به `new_business_id`
   - تنظیم `inventory_valuation_method` به "FIFO" (پیش‌فرض)
   - تنظیم `created_at` و `updated_at`

4. **مدیریت خطاها**:
   - در صورت خطا: ثبت در لاگ با جزئیات
   - ادامه با سال مالی بعدی

### مرحله 3: مدیریت موارد خاص

**سناریو 1: business_id در دیتابیس جدید وجود ندارد**
- بررسی: آیا `bid_id` در `business_id_mapping` وجود دارد؟
- عمل: skip کردن با reason "business_not_migrated"
- ثبت در لاگ

**سناریو 2: تاریخ‌های نامعتبر**
- بررسی: آیا `start` و `end` قابل تبدیل به date هستند؟
- عمل: skip کردن با reason "invalid_dates"
- ثبت در لاگ

**سناریو 3: سال مالی تکراری**
- بررسی: آیا سال مالی با همان `business_id` و `title` در دیتابیس جدید وجود دارد؟
- عمل: skip کردن با reason "already_exists"
- ثبت در لاگ

## آمار و ارقام

### توزیع داده‌ها

- **کل سال‌های مالی**: 4,473
- **سال‌های مالی با head = 1**: 4,473 (100%)
- **سال‌های مالی با تاریخ معتبر**: 4,473 (100%)
- **سال‌های مالی با now = NULL**: 4,473 (100%)
- **حداکثر سال مالی برای هر کسب و کار**: 1

### Mapping

- **کسب و کارهای قابل انتقال**: ~4,062 (با owner که در دیتابیس جدید وجود دارد)
- **سال‌های مالی قابل انتقال**: 4,062 (با کسب و کار که owner در دیتابیس جدید دارد)
- **سال‌های مالی غیرقابل انتقال**: 411 (کسب و کار owner در دیتابیس جدید ندارد)

## کد نمونه

```python
def convert_timestamp_to_date(timestamp_str: str | None) -> date | None:
    """تبدیل timestamp string به date"""
    if not timestamp_str or not timestamp_str.strip():
        return None
    
    try:
        timestamp = int(timestamp_str.strip())
        dt = datetime.fromtimestamp(timestamp)
        return dt.date()
    except (ValueError, TypeError, OSError):
        return None

def migrate_fiscal_year(
    old_year: Dict[str, Any],
    business_id_mapping: Dict[int, int]
) -> Optional[int]:
    """انتقال یک سال مالی"""
    try:
        # نگاشت business_id
        old_business_id = old_year.get('bid_id')
        new_business_id = business_id_mapping.get(old_business_id)
        
        if not new_business_id:
            return None  # کسب و کار منتقل نشده
        
        # تبدیل تاریخ‌ها
        start_date = convert_timestamp_to_date(old_year.get('start'))
        end_date = convert_timestamp_to_date(old_year.get('end'))
        
        if not start_date or not end_date:
            return None  # تاریخ‌های نامعتبر
        
        # تبدیل head به is_last
        is_last = bool(old_year.get('head', 0))
        
        # درج در دیتابیس جدید
        query = text("""
            INSERT INTO fiscal_years (
                business_id, title, start_date, end_date,
                is_last, inventory_valuation_method,
                created_at, updated_at
            ) VALUES (
                :business_id, :title, :start_date, :end_date,
                :is_last, :inventory_valuation_method,
                :created_at, :updated_at
            )
        """)
        
        db.execute(query, {
            "business_id": new_business_id,
            "title": old_year.get('label'),
            "start_date": start_date,
            "end_date": end_date,
            "is_last": is_last,
            "inventory_valuation_method": "FIFO",
            "created_at": datetime.utcnow(),
            "updated_at": datetime.utcnow()
        })
        
        db.commit()
        return new_business_id
        
    except Exception as e:
        db.rollback()
        raise e
```

## نکات مهم

1. **هر کسب و کار یک سال مالی**: در دیتابیس قدیمی هر کسب و کار فقط یک سال مالی دارد
2. **همه سال‌های مالی فعال**: همه `head = 1` دارند، پس همه `is_last = true` خواهند بود
3. **تبدیل timestamp**: باید از timestamp string به DATE تبدیل شود
4. **فیلد now**: همیشه NULL است و نیازی به انتقال ندارد
5. **inventory_valuation_method**: پیش‌فرض "FIFO" برای همه

## ریسک‌ها و راه‌حل‌ها

### ریسک 1: business_id نامعتبر
**احتمال**: متوسط (بسته به تعداد کسب و کارهای منتقل شده)
**راه‌حل**: بررسی وجود در `business_id_mapping` قبل از انتقال

### ریسک 2: تاریخ‌های نامعتبر
**احتمال**: بسیار کم (همه تاریخ‌ها معتبر هستند)
**راه‌حل**: بررسی و skip کردن در صورت نامعتبر بودن

### ریسک 3: تبدیل timestamp
**احتمال**: کم
**راه‌حل**: استفاده از try-except و مدیریت خطا

### ریسک 4: سال مالی تکراری
**احتمال**: کم (اگر کسب و کار قبلاً منتقل شده باشد)
**راه‌حل**: بررسی وجود قبل از درج

## مراحل اجرا

### مرحله 1: ایجاد Business ID Mapping
```python
# استفاده از mapping از انتقال کسب و کارها
business_id_mapping = get_business_id_mapping()
```

### مرحله 2: خواندن سال‌های مالی
```python
old_years = get_old_fiscal_years(business_id_mapping)
```

### مرحله 3: انتقال
```python
for old_year in old_years:
    migrate_fiscal_year(old_year, business_id_mapping)
```

### مرحله 4: اعتبارسنجی
```sql
-- بررسی تعداد سال‌های مالی
SELECT COUNT(*) FROM hesabixpy.fiscal_years;

-- بررسی سال‌های مالی با is_last = true
SELECT COUNT(*) FROM hesabixpy.fiscal_years WHERE is_last = 1;

-- بررسی کسب و کارها با سال مالی
SELECT business_id, COUNT(*) as year_count
FROM hesabixpy.fiscal_years
GROUP BY business_id
HAVING year_count > 1;
```

## نتیجه‌گیری

**خلاصه**:
- ✅ همه سال‌های مالی قابل انتقال هستند (همه تاریخ‌ها معتبر)
- ✅ تبدیل timestamp به DATE ساده است
- ✅ همه سال‌های مالی `is_last = true` خواهند بود
- ✅ نیاز به `business_id_mapping` از انتقال کسب و کارها

**انتظار**:
- ~4,062 سال مالی منتقل می‌شوند (متناسب با کسب و کارها)
- همه با `is_last = true`
- همه با `inventory_valuation_method = "FIFO"`

**وابستگی**:
- باید ابتدا کسب و کارها منتقل شوند
- نیاز به `business_id_mapping` برای نگاشت `bid_id` → `business_id`

