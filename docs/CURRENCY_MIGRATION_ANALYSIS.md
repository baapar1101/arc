# تحلیل انتقال default_currency_id از hesabixOld به hesabixpy

## خلاصه اجرایی

این سند تحلیل نحوه انتقال `default_currency_id` از دیتابیس قدیمی (`hesabixOld`) به دیتابیس جدید (`hesabixpy`) را ارائه می‌دهد.

## وضعیت فعلی

### دیتابیس قدیمی (hesabixOld)

#### جدول `money`
- **تعداد ارزها**: 4 ارز
- **ساختار**:
  - `id`: شناسه یکتا
  - `name`: نام کد ارز (مثل IRR, USD, AFN, IQD)
  - `label`: نام کامل فارسی
  - `symbol`: نماد ارز
  - `short_name`: نام کوتاه

**داده‌های موجود**:
```
id | name | label              | symbol | short_name
1  | IRR  | ریال ایران        | ریال   | ریال
2  | USD  | دلار آمریکا       | $      | دلار
3  | AFN  | افغانی افغانستان | ؋      | افغانی
4  | IQD  | دینار عراق       | ع.د    | دینار
```

#### جدول `business`
- **فیلد**: `money_id` (ارجاع به `money.id`)
- **توزیع استفاده**:
  - `money_id = 1` (IRR): 4,420 کسب و کار (99.1%)
  - `money_id = 2` (USD): 40 کسب و کار (0.9%)
  - `money_id = 3` (AFN): 10 کسب و کار (0.2%)
  - `money_id = 4` (IQD): 3 کسب و کار (0.07%)
- **کسب و کارهای بدون money_id**: 0 (همه کسب و کارها money_id دارند)

### دیتابیس جدید (hesabixpy)

#### جدول `currencies`
- **تعداد ارزها**: 82 ارز
- **ساختار**:
  - `id`: شناسه یکتا
  - `name`: نام کامل انگلیسی
  - `title`: نام فارسی
  - `symbol`: نماد ارز
  - `code`: کد ارز (unique) - معادل `name` در جدول قدیمی

**ارزهای مربوط به دیتابیس قدیمی**:
```
id | name                | title        | symbol | code
1  | Iranian Rial        | ریال ایران  | ﷼      | IRR
2  | United States Dollar| US Dollar   | $      | USD
20 | Afghan Afghani      | Afghani      | ؋      | AFN
19 | Iraqi Dinar         | Iraqi Dinar  | ع.د    | IQD
```

#### جدول `businesses`
- **فیلد**: `default_currency_id` (ارجاع به `currencies.id`)
- **نوع**: `Integer, ForeignKey, nullable=True`

## استراتژی انتقال

### روش 1: Mapping بر اساس Code (پیشنهادی)

**الگوریتم**:
1. ایجاد جدول mapping بین `money.id` (قدیمی) و `currencies.id` (جدید)
2. Mapping بر اساس `money.name` (قدیمی) = `currencies.code` (جدید)
3. استفاده از mapping برای تبدیل `business.money_id` → `businesses.default_currency_id`

**مزایا**:
- دقیق و قابل اعتماد
- بر اساس استاندارد ISO currency codes
- ساده و قابل پیاده‌سازی

**معایب**:
- نیاز به ایجاد mapping table

### روش 2: جستجوی مستقیم در هر انتقال

**الگوریتم**:
1. برای هر کسب و کار، `money_id` را از دیتابیس قدیمی بخوان
2. `money.name` را از جدول `money` بخوان
3. در جدول `currencies` جستجو کن: `WHERE code = money.name`
4. اگر پیدا شد: استفاده از `currencies.id`
5. اگر پیدا نشد: استفاده از پیش‌فرض (IRR)

**مزایا**:
- نیاز به mapping table ندارد
- ساده برای پیاده‌سازی

**معایب**:
- کندتر (query برای هر کسب و کار)
- نیاز به cache کردن نتایج

### روش 3: استفاده از پیش‌فرض برای همه

**الگوریتم**:
- همه کسب و کارها را با `default_currency_id = 1` (IRR) ایجاد کن

**مزایا**:
- بسیار ساده
- سریع

**معایب**:
- از دست رفتن اطلاعات (40 کسب و کار USD، 10 کسب و کار AFN، 3 کسب و کار IQD)
- نادرست برای کسب و کارهای غیر-IRR

## راه‌حل پیشنهادی: روش 1 (Mapping Table)

### پیاده‌سازی

#### 1. ایجاد Currency Mapping Table

```sql
-- ایجاد جدول موقت برای mapping
CREATE TEMPORARY TABLE currency_id_mapping AS
SELECT 
    old_money.id as old_money_id,
    new_currency.id as new_currency_id,
    old_money.name as code
FROM hesabixOld.money old_money
INNER JOIN hesabixpy.currencies new_currency 
    ON old_money.name = new_currency.code;
```

**نتیجه**:
```
old_money_id | new_currency_id | code
1            | 1               | IRR
2            | 2               | USD
3            | 20              | AFN
4            | 19              | IQD
```

#### 2. استفاده در انتقال کسب و کار

```python
def get_default_currency_id(old_money_id: int, currency_mapping: Dict[int, int]) -> int | None:
    """
    تبدیل money_id قدیمی به default_currency_id جدید
    
    Args:
        old_money_id: شناسه money در دیتابیس قدیمی
        currency_mapping: دیکشنری mapping {old_money_id: new_currency_id}
    
    Returns:
        شناسه currency در دیتابیس جدید یا None
    """
    if not old_money_id:
        return None
    
    new_currency_id = currency_mapping.get(old_money_id)
    if new_currency_id:
        return new_currency_id
    
    # اگر پیدا نشد، از پیش‌فرض IRR استفاده کن
    # جستجو برای IRR در دیتابیس جدید
    return get_irr_currency_id()  # معمولاً 1
```

#### 3. مدیریت موارد خاص

**سناریو 1: money_id پیدا نشد در mapping**
- عمل: استفاده از پیش‌فرض IRR (currency_id = 1)
- لاگ: ثبت در لاگ برای بررسی

**سناریو 2: currency در دیتابیس جدید وجود ندارد**
- عمل: استفاده از پیش‌فرض IRR
- لاگ: ثبت در لاگ با هشدار

**سناریو 3: money_id = NULL**
- عمل: `default_currency_id = NULL` یا پیش‌فرض IRR
- توجه: در دیتابیس قدیمی همه کسب و کارها money_id دارند، پس این حالت نادر است

### کد نمونه

```python
def create_currency_mapping(db_old, db_new) -> Dict[int, int]:
    """
    ایجاد mapping بین money قدیمی و currencies جدید
    """
    # Query برای ایجاد mapping
    query = """
        SELECT 
            old_money.id as old_money_id,
            new_currency.id as new_currency_id
        FROM hesabixOld.money old_money
        INNER JOIN hesabixpy.currencies new_currency 
            ON old_money.name = new_currency.code
    """
    
    results = db_old.execute(text(query)).fetchall()
    
    mapping = {}
    for row in results:
        mapping[row.old_money_id] = row.new_currency_id
    
    return mapping

def get_default_currency_id_for_business(
    old_money_id: int | None,
    currency_mapping: Dict[int, int],
    default_irr_id: int = 1
) -> int | None:
    """
    تبدیل money_id قدیمی به default_currency_id جدید
    """
    if not old_money_id:
        return default_irr_id  # یا None بسته به نیاز
    
    return currency_mapping.get(old_money_id, default_irr_id)
```

## آمار و ارقام

### توزیع استفاده از ارزها

| ارز | تعداد کسب و کار | درصد |
|-----|----------------|------|
| IRR | 4,420 | 99.1% |
| USD | 40 | 0.9% |
| AFN | 10 | 0.2% |
| IQD | 3 | 0.07% |
| **کل** | **4,473** | **100%** |

### Mapping Table

| old_money_id | old_code | new_currency_id | new_code | تطابق |
|--------------|----------|-----------------|----------|--------|
| 1 | IRR | 1 | IRR | ✅ |
| 2 | USD | 2 | USD | ✅ |
| 3 | AFN | 20 | AFN | ✅ |
| 4 | IQD | 19 | IQD | ✅ |

**نتیجه**: همه 4 ارز قدیمی در دیتابیس جدید وجود دارند و می‌توانند به درستی mapping شوند.

**نکته مهم**: به دلیل تفاوت collation بین دو دیتابیس، باید از `BINARY` یا `COLLATE` در query استفاده کرد:
```sql
-- روش صحیح برای mapping
SELECT old_money.id, new_currency.id
FROM hesabixOld.money old_money
INNER JOIN hesabixpy.currencies new_currency 
    ON BINARY old_money.name = BINARY new_currency.code;
```

## مراحل اجرا

### مرحله 1: ایجاد Currency Mapping

```python
# در اسکریپت انتقال کسب و کارها
currency_mapping = create_currency_mapping(old_db, new_db)
# نتیجه: {1: 1, 2: 2, 3: 20, 4: 19}
```

### مرحله 2: استفاده در انتقال

```python
# برای هر کسب و کار
old_money_id = old_business.get('money_id')
default_currency_id = get_default_currency_id_for_business(
    old_money_id,
    currency_mapping,
    default_irr_id=1
)

# درج در دیتابیس جدید
business_data = {
    # ... سایر فیلدها ...
    'default_currency_id': default_currency_id
}
```

### مرحله 3: اعتبارسنجی

```sql
-- بررسی تعداد کسب و کارها با هر ارز
SELECT 
    c.code,
    c.name,
    COUNT(b.id) as business_count
FROM hesabixpy.businesses b
INNER JOIN hesabixpy.currencies c ON b.default_currency_id = c.id
GROUP BY c.id, c.code, c.name
ORDER BY business_count DESC;
```

**انتظار**:
- IRR: ~4,420 کسب و کار
- USD: ~40 کسب و کار
- AFN: ~10 کسب و کار
- IQD: ~3 کسب و کار

## نکات مهم

1. **همه کسب و کارها money_id دارند**: هیچ کسب و کاری بدون money_id نیست
2. **همه ارزهای قدیمی در جدید وجود دارند**: همه 4 ارز می‌توانند mapping شوند
3. **IRR پیش‌فرض است**: در صورت عدم تطابق، از IRR استفاده می‌شود
4. **Mapping بر اساس Code**: استفاده از `money.name` = `currencies.code` برای mapping

## ریسک‌ها و راه‌حل‌ها

### ریسک 1: Currency در دیتابیس جدید وجود ندارد
**احتمال**: بسیار کم (همه 4 ارز موجود هستند)
**راه‌حل**: استفاده از پیش‌فرض IRR و ثبت در لاگ

### ریسک 2: Mapping نادرست
**احتمال**: بسیار کم (بر اساس ISO code)
**راه‌حل**: اعتبارسنجی بعد از انتقال

### ریسک 3: Performance
**احتمال**: کم (فقط 4 ارز)
**راه‌حل**: استفاده از mapping table در memory

## نتیجه‌گیری

**روش پیشنهادی**: استفاده از Mapping Table بر اساس Code

**دلایل**:
1. ✅ دقیق و قابل اعتماد
2. ✅ همه ارزهای قدیمی در جدید وجود دارند
3. ✅ ساده برای پیاده‌سازی
4. ✅ قابل اعتبارسنجی

**پیاده‌سازی**:
- ایجاد `currency_id_mapping` در ابتدای اسکریپت انتقال
- استفاده از mapping در انتقال هر کسب و کار
- استفاده از IRR به عنوان پیش‌فرض در صورت عدم تطابق

**انتظار**:
- 4,420 کسب و کار با IRR
- 40 کسب و کار با USD
- 10 کسب و کار با AFN
- 3 کسب و کار با IQD

