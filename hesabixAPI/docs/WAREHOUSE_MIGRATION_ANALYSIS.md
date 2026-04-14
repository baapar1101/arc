# تحلیل انتقال بخش انبارها

## 1. بررسی ساختار جداول

### 1.1. دیتابیس قدیمی (hesabixOld)

#### جدول `storeroom` (انبارها)
- **id**: شناسه انبار
- **bid_id**: شناسه کسب و کار
- **name**: نام انبار
- **manager**: نام انباردار
- **adr**: آدرس
- **tel**: تلفن
- **active**: فعال/غیرفعال

**آمار:**
- تعداد کل انبارها: **1,185**
- تعداد کسب و کارهای دارای انبار: **924**

#### جدول `storeroom_ticket` (اسناد انبار)
- **id**: شناسه سند
- **bid_id**: شناسه کسب و کار
- **submitter_id**: شناسه کاربر ایجادکننده
- **person_id**: شناسه شخص (مشتری/تامین‌کننده)
- **doc_id**: شناسه فاکتور مرتبط
- **year_id**: شناسه سال مالی
- **storeroom_id**: شناسه انبار
- **transfer_type_id**: شناسه نوع انتقال (ارجاع به `storeroom_transfer_type`)
- **date**: تاریخ سند (فرمت: 1402/08/27)
- **date_submit**: تاریخ ثبت (timestamp)
- **transfer**: نام انتقال‌دهنده
- **receiver**: نام دریافت‌کننده
- **code**: کد سند
- **type**: نوع سند (`input` یا `output`)
- **referral**: ارجاع
- **type_string**: نوع سند به فارسی (مثل "حواله ورود"، "حواله خروج")
- **des**: توضیحات
- **sender_tel**: تلفن فرستنده
- **can_share**: قابل اشتراک‌گذاری
- **import_workflow_code**: کد workflow واردات
- **activation_code**: کد فعال‌سازی
- **is_preview**: پیش‌نمایش
- **is_approved**: تایید شده
- **completed**: تکمیل شده
- **completed_at**: تاریخ تکمیل
- **approved_by_id**: شناسه تاییدکننده
- **completed_by_id**: شناسه تکمیل‌کننده

**آمار:**
- تعداد کل اسناد: **4,564**
  - `input`: 1,511
  - `output`: 3,053

#### جدول `storeroom_item` (آیتم‌های سند انبار)
- **id**: شناسه آیتم
- **ticket_id**: شناسه سند انبار
- **commodity_id**: شناسه کالا
- **bid_id**: شناسه کسب و کار
- **storeroom_id**: شناسه انبار
- **type**: نوع (`input` یا `output`)
- **count**: تعداد (varchar)
- **des**: توضیحات
- **referal**: ارجاع

**آمار:**
- تعداد کل آیتم‌ها: **12,645**
  - `input`: 5,359
  - `output`: 7,286

#### جدول `storeroom_transfer_type` (نوع انتقال)
- **id**: شناسه
- **name**: نام (مثل "تحویل درب انبار"، "پست عادی"، "پست پیشتاز"، "باربری"، "اتوبوس"، "تیپاکس"، "پیک")

### 1.2. دیتابیس جدید (hesabixpy)

#### جدول `warehouses` (انبارها)
- **id**: شناسه انبار
- **business_id**: شناسه کسب و کار
- **code**: کد یکتا در هر کسب و کار (varchar(64))
- **name**: نام انبار (varchar(255))
- **description**: توضیحات (text)
- **warehouse_keeper**: نام انباردار (varchar(255))
- **phone**: تلفن (varchar(32))
- **address**: آدرس (text)
- **postal_code**: کد پستی (varchar(16))
- **is_default**: انبار پیش‌فرض (boolean)
- **created_at**: تاریخ ایجاد
- **updated_at**: تاریخ به‌روزرسانی

**محدودیت‌ها:**
- `UNIQUE(business_id, code)`: کد باید در هر کسب و کار یکتا باشد

#### جدول `warehouse_documents` (اسناد انبار)
- **id**: شناسه سند
- **business_id**: شناسه کسب و کار
- **fiscal_year_id**: شناسه سال مالی
- **code**: کد سند (varchar(64), UNIQUE)
- **document_date**: تاریخ سند (date)
- **status**: وضعیت (`draft`|`posted`|`cancelled`)
- **doc_type**: نوع سند (`receipt`|`issue`|`transfer`|`production_in`|`production_out`|`adjustment`)
- **warehouse_id_from**: شناسه انبار مبدا (برای transfer)
- **warehouse_id_to**: شناسه انبار مقصد (برای transfer)
- **source_type**: نوع منبع (`invoice`|`manual`|`api`)
- **source_document_id**: شناسه سند منبع
- **extra_info**: اطلاعات اضافی (JSON)
- **created_by_user_id**: شناسه کاربر ایجادکننده
- **created_at**: تاریخ ایجاد
- **updated_at**: تاریخ به‌روزرسانی

#### جدول `warehouse_document_lines` (خطوط سند انبار)
- **id**: شناسه خط
- **warehouse_document_id**: شناسه سند انبار
- **product_id**: شناسه کالا
- **warehouse_id**: شناسه انبار
- **movement**: نوع حرکت (`in`|`out`)
- **quantity**: تعداد (decimal(18,6))
- **cost_price**: قیمت تمام شده (decimal(18,6))
- **cogs_amount**: مبلغ COGS (decimal(18,6))
- **extra_info**: اطلاعات اضافی (JSON)
- **instance_ids**: لیست ID کالاهای یونیک (JSON)

## 2. نگاشت فیلدها

### 2.1. انبارها (storeroom → warehouses)

| فیلد قدیمی | فیلد جدید | توضیحات |
|------------|-----------|---------|
| `id` | - | استفاده نمی‌شود (ایجاد جدید) |
| `bid_id` | `business_id` | نیاز به mapping |
| `name` | `name` | مستقیم |
| `manager` | `warehouse_keeper` | مستقیم |
| `adr` | `address` | مستقیم |
| `tel` | `phone` | مستقیم |
| `active` | - | فقط انبارهای active منتقل می‌شوند |
| - | `code` | باید تولید شود (مثلاً از name یا id) |
| - | `description` | می‌تواند از name یا address استفاده کند |
| - | `postal_code` | NULL |
| - | `is_default` | اولین انبار هر کسب و کار = true |

### 2.2. اسناد انبار (storeroom_ticket → warehouse_documents)

| فیلد قدیمی | فیلد جدید | توضیحات |
|------------|-----------|---------|
| `id` | - | استفاده نمی‌شود |
| `bid_id` | `business_id` | نیاز به mapping |
| `submitter_id` | `created_by_user_id` | نیاز به mapping |
| `person_id` | - | در `extra_info` ذخیره می‌شود |
| `doc_id` | `source_document_id` | نیاز به mapping (اگر فاکتور مرتبط باشد) |
| `year_id` | `fiscal_year_id` | نیاز به mapping |
| `storeroom_id` | `warehouse_id_from` یا `warehouse_id_to` | بستگی به `type` دارد |
| `transfer_type_id` | - | در `extra_info` ذخیره می‌شود |
| `date` | `document_date` | تبدیل از شمسی به میلادی |
| `date_submit` | `created_at` | تبدیل از timestamp به datetime |
| `code` | `code` | مستقیم (با بررسی یکتایی) |
| `type` | `doc_type` | تبدیل: `input` → `receipt`, `output` → `issue` |
| `type_string` | - | در `extra_info` ذخیره می‌شود |
| `des` | - | در `extra_info` ذخیره می‌شود |
| `transfer` | - | در `extra_info` ذخیره می‌شود |
| `receiver` | - | در `extra_info` ذخیره می‌شود |
| `sender_tel` | - | در `extra_info` ذخیره می‌شود |
| `referral` | - | در `extra_info` ذخیره می‌شود |
| - | `status` | بر اساس `completed` و `is_approved`: `completed=1` → `posted`, در غیر این صورت `draft` |
| - | `warehouse_id_from` | برای `transfer` (اگر `type_string` شامل "انتقال" باشد) |
| - | `warehouse_id_to` | برای `transfer` |
| - | `source_type` | اگر `doc_id` وجود داشته باشد → `invoice`, در غیر این صورت `manual` |

### 2.3. آیتم‌های سند (storeroom_item → warehouse_document_lines)

| فیلد قدیمی | فیلد جدید | توضیحات |
|------------|-----------|---------|
| `id` | - | استفاده نمی‌شود |
| `ticket_id` | `warehouse_document_id` | نیاز به mapping |
| `commodity_id` | `product_id` | نیاز به mapping |
| `storeroom_id` | `warehouse_id` | نیاز به mapping |
| `type` | `movement` | تبدیل: `input` → `in`, `output` → `out` |
| `count` | `quantity` | تبدیل از varchar به decimal |
| `des` | - | در `extra_info` ذخیره می‌شود |
| `referal` | - | در `extra_info` ذخیره می‌شود |
| - | `cost_price` | NULL (می‌تواند از قیمت کالا محاسبه شود) |
| - | `cogs_amount` | NULL |
| - | `instance_ids` | NULL |

## 3. تبدیل‌های مورد نیاز

### 3.1. تبدیل نوع سند (type → doc_type)

```python
def convert_doc_type(old_type: str, type_string: str | None) -> str:
    """
    تبدیل type قدیمی به doc_type جدید
    
    Args:
        old_type: 'input' یا 'output'
        type_string: نوع سند به فارسی (مثل "حواله ورود")
    
    Returns:
        doc_type جدید: 'receipt'|'issue'|'transfer'|'production_in'|'production_out'|'adjustment'
    """
    if old_type == "input":
        # بررسی type_string برای تشخیص نوع دقیق
        if type_string and "انتقال" in type_string:
            return "transfer"
        elif type_string and "تولید" in type_string:
            return "production_in"
        else:
            return "receipt"
    elif old_type == "output":
        if type_string and "انتقال" in type_string:
            return "transfer"
        elif type_string and "تولید" in type_string:
            return "production_out"
        else:
            return "issue"
    else:
        return "adjustment"  # پیش‌فرض
```

### 3.2. تبدیل وضعیت (completed/is_approved → status)

```python
def convert_status(completed: int | None, is_approved: int | None) -> str:
    """
    تبدیل وضعیت قدیمی به status جدید
    
    Returns:
        'draft'|'posted'|'cancelled'
    """
    if completed == 1:
        return "posted"
    elif is_approved == 0:
        return "cancelled"
    else:
        return "draft"
```

### 3.3. تبدیل تاریخ

- **date**: از فرمت شمسی (1402/08/27) به `date`
- **date_submit**: از timestamp به `datetime`

### 3.4. تبدیل تعداد (count → quantity)

```python
def convert_quantity(count_str: str | None) -> Decimal | None:
    """
    تبدیل count از varchar به decimal
    """
    if not count_str or not count_str.strip():
        return None
    try:
        cleaned = count_str.strip().replace(',', '').replace(' ', '').replace('،', '')
        if not cleaned or cleaned == '0':
            return None
        return Decimal(cleaned)
    except (ValueError, InvalidOperation, TypeError):
        return None
```

### 3.5. تولید کد انبار (code)

```python
def generate_warehouse_code(name: str, existing_codes: set) -> str:
    """
    تولید کد یکتا برای انبار
    """
    # استفاده از name (با محدودیت 64 کاراکتر)
    base_code = name[:64].strip()
    
    # اگر تکراری است، اضافه کردن شماره
    code = base_code
    counter = 1
    while code in existing_codes:
        suffix = f"_{counter}"
        code = (base_code[:64-len(suffix)] + suffix)
        counter += 1
    
    return code
```

## 4. روابط و وابستگی‌ها

### 4.1. وابستگی‌های انبارها
- **business_id**: نیاز به mapping از `bid_id` قدیمی به `business_id` جدید
- **code**: باید یکتا در هر کسب و کار باشد

### 4.2. وابستگی‌های اسناد انبار
- **business_id**: نیاز به mapping
- **fiscal_year_id**: نیاز به mapping از `year_id`
- **warehouse_id_from/warehouse_id_to**: نیاز به mapping از `storeroom_id`
- **created_by_user_id**: نیاز به mapping از `submitter_id`
- **source_document_id**: نیاز به mapping از `doc_id` (اگر فاکتور مرتبط باشد)
- **code**: باید یکتا باشد (UNIQUE)

### 4.3. وابستگی‌های خطوط سند
- **warehouse_document_id**: نیاز به mapping از `ticket_id`
- **product_id**: نیاز به mapping از `commodity_id`
- **warehouse_id**: نیاز به mapping از `storeroom_id`

## 5. چالش‌ها و راه‌حل‌ها

### 5.1. یکتایی کد سند (code)
- **مشکل**: `code` در `warehouse_documents` باید یکتا باشد
- **راه‌حل**: اگر تکراری است، اضافه کردن suffix (مثلاً `_1`, `_2`)

### 5.2. تشخیص نوع سند (transfer vs receipt/issue)
- **مشکل**: `type` فقط `input`/`output` است، اما باید `transfer` را تشخیص دهیم
- **راه‌حل**: استفاده از `type_string` برای تشخیص

### 5.3. mapping فاکتورها (doc_id → source_document_id)
- **مشکل**: `doc_id` در دیتابیس قدیمی به فاکتورها اشاره می‌کند که هنوز منتقل نشده‌اند
- **راه‌حل**: اگر فاکتورها منتقل نشده‌اند، `source_document_id` را NULL بگذاریم و `source_type` را `manual` کنیم

### 5.4. انبار پیش‌فرض (is_default)
- **راه‌حل**: اولین انبار هر کسب و کار را `is_default = true` کنیم

### 5.5. تبدیل تاریخ شمسی
- **راه‌حل**: استفاده از کتابخانه `jdatetime` برای تبدیل تاریخ شمسی به میلادی

## 6. مراحل انتقال

1. **انتقال انبارها (warehouses)**
   - ایجاد mapping بین `storeroom_id` قدیمی و `warehouse_id` جدید
   - فقط انبارهای `active = 1` را منتقل کنیم

2. **انتقال اسناد انبار (warehouse_documents)**
   - ایجاد mapping بین `ticket_id` قدیمی و `warehouse_document_id` جدید
   - تبدیل `type` به `doc_type`
   - تبدیل تاریخ‌ها
   - تبدیل وضعیت

3. **انتقال خطوط سند (warehouse_document_lines)**
   - استفاده از mapping های ایجاد شده
   - تبدیل `count` به `quantity`
   - تبدیل `type` به `movement`

## 7. آمار کلی

- **انبارها**: 1,185
- **اسناد انبار**: 4,564
  - ورود: 1,511
  - خروج: 3,053
- **آیتم‌های سند**: 12,645
  - ورود: 5,359
  - خروج: 7,286
- **کسب و کارهای دارای انبار**: 924

