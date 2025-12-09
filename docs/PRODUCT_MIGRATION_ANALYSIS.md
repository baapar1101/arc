# تحلیل انتقال کالا و خدمات از hesabixOld به hesabixpy

## خلاصه اجرایی

این سند تحلیل نحوه انتقال کالا و خدمات (commodities/products) از دیتابیس قدیمی (`hesabixOld`) به دیتابیس جدید (`hesabixpy`) را ارائه می‌دهد.

## وضعیت فعلی

### دیتابیس قدیمی (hesabixOld)

#### جدول `commodity`
- **تعداد کالا/خدمات**: 213,565
- **تعداد کسب و کارهای دارای کالا**: 2,371
- **ساختار**:
  - `id`: شناسه یکتا
  - `bid_id`: شناسه کسب و کار (ارجاع به `business.id`)
  - `name`: نام کالا/خدمت
  - `code`: کد کالا/خدمت
  - `des`: توضیحات
  - `price_buy`: قیمت خرید (varchar)
  - `price_sell`: قیمت فروش (varchar)
  - `khadamat`: نوع (0 = کالا، 1 = خدمت، NULL = کالا)
  - `cat_id`: شناسه دسته‌بندی (ارجاع به `commodity_cat.id`)
  - `unit_id`: شناسه واحد (ارجاع به `commodity_unit.id`)
  - `order_point`: نقطه سفارش
  - `commodity_count_check`: بررسی موجودی
  - `min_order_count`: حداقل تعداد سفارش
  - `day_loading`: روز بارگذاری
  - `speed_access`: دسترسی سریع
  - `without_tax`: بدون مالیات
  - `barcodes`: بارکدها (longtext)
  - `tax_code`: کد مالیاتی
  - `tax_type`: نوع مالیات
  - `tax_unit`: واحد مالیات
  - `custom_code`: کد سفارشی
  - `tags`: تگ‌ها (JSON)

**توزیع نوع**:
- کالا (khadamat = 0): 206,291 (کل) / 196,246 (قابل انتقال - 96.6%)
- خدمت (khadamat = 1): 7,269 (کل) / 6,867 (قابل انتقال - 3.4%)
- NULL: 5 (کل) / 4 (قابل انتقال)

**دسته‌بندی (قابل انتقال)**:
- کالا/خدمات با دسته‌بندی: 68,710 (33.8%)
- کالا/خدمات بدون دسته‌بندی: 134,407 (66.2%)

**واحد**:
- همه کالا/خدمات واحد دارند (213,565)

#### جدول `commodity_cat`
- **ساختار**:
  - `id`: شناسه یکتا
  - `bid_id`: شناسه کسب و کار
  - `name`: نام دسته‌بندی
  - `upper`: دسته‌بندی والد
  - `root`: آیا ریشه است؟

#### جدول `commodity_unit`
- **ساختار**:
  - `id`: شناسه یکتا
  - `name`: نام واحد (مثل "عدد", "کیلوگرم", "لیتر")
  - `float_number`: تعداد اعشار

### دیتابیس جدید (hesabixpy)

#### جدول `products`
- **تعداد کالا/خدمات فعلی**: 3,453
- **ساختار**:
  - `id`: شناسه یکتا
  - `business_id`: شناسه کسب و کار (ارجاع به `businesses.id`)
  - `item_type`: نوع آیتم (ENUM: "کالا", "خدمت")
  - `code`: کد یکتا در هر کسب و کار
  - `name`: نام
  - `description`: توضیحات
  - `category_id`: شناسه دسته‌بندی (ارجاع به `categories.id`)
  - `main_unit`: واحد اصلی (varchar - نام واحد)
  - `secondary_unit`: واحد فرعی (varchar)
  - `unit_conversion_factor`: ضریب تبدیل واحد
  - `base_sales_price`: قیمت فروش پایه (decimal)
  - `base_purchase_price`: قیمت خرید پایه (decimal)
  - `track_inventory`: ردیابی موجودی (boolean)
  - `reorder_point`: نقطه سفارش مجدد (integer)
  - `min_order_qty`: حداقل تعداد سفارش (integer)
  - `lead_time_days`: زمان تحویل (integer)
  - `is_sales_taxable`: مالیات‌پذیر فروش (boolean)
  - `is_purchase_taxable`: مالیات‌پذیر خرید (boolean)
  - `sales_tax_rate`: نرخ مالیات فروش (decimal)
  - `purchase_tax_rate`: نرخ مالیات خرید (decimal)
  - `tax_type_id`: شناسه نوع مالیات
  - `tax_code`: کد مالیاتی
  - `tax_unit_id`: شناسه واحد مالیات
  - `inventory_mode`: حالت موجودی (varchar - پیش‌فرض: "bulk")
  - `track_serial`: ردیابی سریال (boolean)
  - `track_barcode`: ردیابی بارکد (boolean)
  - `created_at`: تاریخ ایجاد
  - `updated_at`: تاریخ به‌روزرسانی

#### جدول `categories`
- **ساختار**:
  - `id`: شناسه یکتا
  - `business_id`: شناسه کسب و کار
  - `parent_id`: شناسه دسته‌بندی والد
  - `title_translations`: عناوین چندزبانه (JSON - {"fa": "...", "en": "..."})
  - `description`: توضیحات
  - `sort_order`: ترتیب نمایش
  - `is_active`: فعال بودن
  - `created_at`: تاریخ ایجاد
  - `updated_at`: تاریخ به‌روزرسانی

## استراتژی انتقال

### تبدیل فیلدها

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `id` | - | نگه‌داری در mapping table (اختیاری) |
| `bid_id` | `business_id` | نگاشت از business_id_mapping |
| `name` | `name` | مستقیم |
| `code` | `code` | مستقیم |
| `des` | `description` | مستقیم |
| `price_buy` | `base_purchase_price` | تبدیل varchar به decimal |
| `price_sell` | `base_sales_price` | تبدیل varchar به decimal |
| `khadamat` | `item_type` | 0 یا NULL → "کالا", 1 → "خدمت" |
| `cat_id` | `category_id` | نگاشت از category_id_mapping |
| `unit_id` | `main_unit` | نگاشت از unit_id به unit name |
| `order_point` | `reorder_point` | تبدیل varchar به integer |
| `commodity_count_check` | `track_inventory` | تبدیل boolean |
| `min_order_count` | `min_order_qty` | تبدیل varchar به integer |
| `day_loading` | `lead_time_days` | تبدیل varchar به integer |
| `without_tax` | `is_sales_taxable`, `is_purchase_taxable` | معکوس boolean |
| `barcodes` | - | حذف (یا در جدول جداگانه) |
| `tax_code` | `tax_code` | مستقیم |
| `tax_type` | `tax_type_id` | نیاز به mapping |
| `tax_unit` | `tax_unit_id` | نیاز به mapping |
| `tags` | - | حذف (یا در جدول جداگانه) |

### تبدیل khadamat به item_type

**الگوریتم**:
```python
def convert_khadamat_to_item_type(khadamat: int | None) -> str:
    """
    تبدیل khadamat به item_type
    
    Args:
        khadamat: مقدار khadamat از دیتابیس قدیمی (0 = کالا، 1 = خدمت، NULL = کالا)
    
    Returns:
        "کالا" یا "خدمت"
    """
    if khadamat == 1:
        return "خدمت"
    return "کالا"  # پیش‌فرض برای 0 و NULL
```

### تبدیل قیمت‌ها

**الگوریتم**:
```python
def convert_price(price_str: str | None) -> Decimal | None:
    """
    تبدیل قیمت از varchar به decimal
    
    Args:
        price_str: قیمت به صورت string (مثل "5250000" یا "0")
    
    Returns:
        Decimal یا None
    """
    if not price_str or not price_str.strip():
        return None
    
    try:
        # حذف فاصله و کاراکترهای غیرعددی (به جز نقطه و منفی)
        cleaned = price_str.strip().replace(',', '').replace(' ', '')
        if not cleaned or cleaned == '0':
            return None
        return Decimal(cleaned)
    except (ValueError, InvalidOperation):
        return None
```

### نگاشت category_id

**چالش**: 
- در قدیمی: `commodity_cat` با `bid_id` و `name`
- در جدید: `categories` با `business_id` و `title_translations` (JSON)

**راه‌حل**:
1. برای هر کسب و کار، دسته‌بندی‌های قدیمی را بخوان
2. در دیتابیس جدید جستجو کن (بر اساس business_id و name)
3. اگر پیدا نشد: ایجاد کن با `title_translations = {"fa": name, "en": name}`
4. mapping را ذخیره کن

**الگوریتم**:
```python
def get_or_create_category(
    old_cat_id: int | None,
    old_cat_name: str | None,
    new_business_id: int,
    category_mapping: Dict[int, int]
) -> int | None:
    """
    دریافت یا ایجاد دسته‌بندی
    
    Returns:
        شناسه دسته‌بندی جدید یا None
    """
    if not old_cat_id or not old_cat_name:
        return None
    
    # بررسی mapping
    if old_cat_id in category_mapping:
        return category_mapping[old_cat_id]
    
    # جستجو در دیتابیس جدید
    query = text("""
        SELECT id FROM categories
        WHERE business_id = :business_id
        AND JSON_EXTRACT(title_translations, '$.fa') = :name
        LIMIT 1
    """)
    result = db.execute(query, {
        "business_id": new_business_id,
        "name": old_cat_name
    }).fetchone()
    
    if result:
        category_mapping[old_cat_id] = result[0]
        return result[0]
    
    # ایجاد دسته‌بندی جدید
    query = text("""
        INSERT INTO categories (
            business_id, title_translations,
            sort_order, is_active,
            created_at, updated_at
        ) VALUES (
            :business_id, :title_translations,
            0, 1,
            :created_at, :updated_at
        )
    """)
    
    title_translations = json.dumps({"fa": old_cat_name, "en": old_cat_name})
    db.execute(query, {
        "business_id": new_business_id,
        "title_translations": title_translations,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    })
    db.commit()
    
    # دریافت شناسه جدید
    new_cat_id = db.lastrowid
    category_mapping[old_cat_id] = new_cat_id
    return new_cat_id
```

### نگاشت unit_id به main_unit

**چالش**:
- در قدیمی: `unit_id` (ارجاع به `commodity_unit.id`)
- در جدید: `main_unit` (varchar - نام واحد)

**راه‌حل**:
1. ایجاد mapping بین `unit_id` و `unit.name`
2. استفاده از نام واحد به عنوان `main_unit`

**الگوریتم**:
```python
def create_unit_mapping() -> Dict[int, str]:
    """ایجاد mapping بین unit_id و unit name"""
    query = text("SELECT id, name FROM hesabixOld.commodity_unit")
    results = old_db.execute(query).fetchall()
    
    mapping = {}
    for row in results:
        mapping[row.id] = row.name
    
    return mapping
```

### تبدیل سایر فیلدها

**order_point → reorder_point**:
```python
def convert_order_point(order_point: str | None) -> int | None:
    if not order_point or not order_point.strip():
        return None
    try:
        return int(float(order_point.strip()))
    except (ValueError, TypeError):
        return None
```

**commodity_count_check → track_inventory**:
```python
def convert_track_inventory(check: int | None) -> bool:
    return bool(check) if check is not None else False
```

**without_tax → is_sales_taxable/is_purchase_taxable**:
```python
def convert_taxable(without_tax: int | None) -> tuple[bool, bool]:
    """
    تبدیل without_tax به is_sales_taxable و is_purchase_taxable
    
    Returns:
        (is_sales_taxable, is_purchase_taxable)
    """
    if without_tax == 1:
        return (False, False)  # بدون مالیات
    return (True, True)  # با مالیات (پیش‌فرض)
```

## الگوریتم انتقال

### مرحله 1: آماده‌سازی

1. **ایجاد business_id_mapping**: از انتقال کسب و کارها
2. **ایجاد unit_mapping**: mapping بین unit_id و unit name
3. **ایجاد category_mapping**: برای هر کسب و کار

### مرحله 2: فیلتر کالا/خدمات برای انتقال

**شرایط انتقال**:
1. کالا/خدمت باید `bid_id` داشته باشد
2. `bid_id` باید در `business_id_mapping` وجود داشته باشد
3. کالا/خدمت نباید در دیتابیس جدید وجود داشته باشد (بر اساس business_id و code)

**SQL برای انتخاب**:
```sql
SELECT c.*
FROM hesabixOld.commodity c
INNER JOIN business_id_mapping m ON c.bid_id = m.old_business_id
WHERE NOT EXISTS (
    SELECT 1 FROM hesabixpy.products new
    WHERE new.business_id = m.new_business_id
      AND new.code = c.code
)
ORDER BY c.bid_id, c.id;
```

### مرحله 3: پردازش هر کالا/خدمت

**مراحل**:
1. نگاشت `bid_id` → `business_id`
2. تبدیل `khadamat` → `item_type`
3. تبدیل `price_buy` و `price_sell` → `base_purchase_price` و `base_sales_price`
4. نگاشت `cat_id` → `category_id` (با ایجاد در صورت نیاز)
5. نگاشت `unit_id` → `main_unit` (نام واحد)
6. تبدیل سایر فیلدها
7. درج در دیتابیس جدید

### مرحله 4: مدیریت موارد خاص

**سناریو 1: category_id نامعتبر**
- عمل: `category_id = NULL`
- لاگ: ثبت در لاگ

**سناریو 2: unit_id نامعتبر**
- عمل: `main_unit = NULL` یا پیش‌فرض "عدد"
- لاگ: ثبت در لاگ

**سناریو 3: قیمت‌های نامعتبر**
- عمل: `base_sales_price = NULL` یا `base_purchase_price = NULL`
- لاگ: ثبت در لاگ

**سناریو 4: کد تکراری**
- عمل: skip کردن با reason "duplicate_code"
- لاگ: ثبت در لاگ

## آمار و ارقام

### توزیع داده‌ها

- **کل کالا/خدمات**: 213,565
- **کالا (khadamat = 0)**: 206,291 (96.6%)
- **خدمت (khadamat = 1)**: 7,269 (3.4%)
- **کالا/خدمات با دسته‌بندی**: 77,160 (36.1%)
- **کالا/خدمات بدون دسته‌بندی**: 136,405 (63.9%)
- **کسب و کارهای دارای کالا**: 2,371

### قابل انتقال

- **کسب و کارهای منتقل شده**: 3,812
- **کسب و کارهای دارای کالا که منتقل شده‌اند**: 2,146
- **کالا/خدمات قابل انتقال**: 203,117
- **کالا/خدمات غیرقابل انتقال**: 10,448 (کسب و کار owner منتقل نشده)

## نکات مهم

1. **حجم زیاد داده**: 213,565 کالا/خدمات - نیاز به پردازش batch به batch
2. **دسته‌بندی‌ها**: باید برای هر کسب و کار ایجاد شوند
3. **واحدها**: باید از ID به نام تبدیل شوند
4. **قیمت‌ها**: باید از varchar به decimal تبدیل شوند
5. **کد یکتا**: کد باید در هر کسب و کار یکتا باشد

## ریسک‌ها و راه‌حل‌ها

### ریسک 1: حجم زیاد داده
**راه‌حل**: پردازش batch به batch با اندازه مناسب (100-500 در هر batch)

### ریسک 2: دسته‌بندی‌های تکراری
**راه‌حل**: بررسی وجود قبل از ایجاد

### ریسک 3: کدهای تکراری
**راه‌حل**: بررسی unique constraint قبل از درج

### ریسک 4: قیمت‌های نامعتبر
**راه‌حل**: تبدیل با مدیریت خطا و استفاده از NULL

### ریسک 5: واحدهای نامعتبر
**راه‌حل**: استفاده از پیش‌فرض "عدد" در صورت عدم وجود

## نتیجه‌گیری

انتقال کالا و خدمات نیاز به:
- ✅ نگاشت business_id
- ✅ تبدیل item_type
- ✅ تبدیل قیمت‌ها
- ✅ ایجاد/نگاشت دسته‌بندی‌ها
- ✅ تبدیل واحدها
- ✅ پردازش batch به batch به دلیل حجم زیاد

**تخمین زمان**: با batch size 500، حدود 406 batch نیاز است که می‌تواند 30-60 دقیقه طول بکشد.

**آمار دقیق قابل انتقال**:
- کالا: 196,246
- خدمت: 6,867
- با دسته‌بندی: 68,710
- بدون دسته‌بندی: 134,407
- کسب و کارهای دارای کالا: 2,146

