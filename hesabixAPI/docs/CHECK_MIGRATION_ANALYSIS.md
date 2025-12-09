# تحلیل انتقال چک‌ها از hesabixOld به hesabixpy

## بررسی جداول

### دیتابیس قدیمی (hesabixOld)

#### جدول `cheque` (چک‌ها)
- **تعداد رکوردها**: 1,872
- **ساختار**:
  - `id`: int (PK)
  - `bid_id`: int (FK به business) - NOT NULL
  - `submitter_id`: int (FK به user) - NOT NULL
  - `bank_id`: int (FK به bank_account) - nullable
  - `person_id`: int (FK به person) - nullable
  - `ref_id`: int (FK - احتمالاً به document یا invoice) - nullable
  - `date_submit`: varchar(50) - تاریخ ثبت (timestamp)
  - `type`: varchar(20) - نوع چک ("input" یا "output")
  - `sayad_num`: varchar(50) - شماره صیاد - nullable
  - `des`: varchar(255) - توضیحات - nullable
  - `date_stamp`: varchar(50) - تاریخ چک (timestamp) - NOT NULL
  - `pay_date`: varchar(50) - تاریخ پرداخت (string) - nullable
  - `number`: varchar(255) - شماره چک - NOT NULL
  - `bank_oncheque`: varchar(255) - نام بانک روی چک - NOT NULL
  - `amount`: varchar(255) - مبلغ (string) - NOT NULL
  - `status`: varchar(255) - وضعیت (string) - nullable
  - `locked`: tinyint(1) - قفل شده - nullable
  - `date`: varchar(255) - تاریخ (string) - nullable
  - `rejected`: tinyint(1) - رد شده - nullable
  - `money_id`: int (FK به money) - nullable
  - `transfered`: tinyint(1) - منتقل شده - nullable
  - `transfer_date`: varchar(25) - تاریخ انتقال - nullable

### دیتابیس جدید (hesabixpy)

#### جدول `checks` (چک‌ها)
- `id`: int (PK)
- `business_id`: int (FK) - NOT NULL
- `type`: ENUM('RECEIVED', 'TRANSFERRED') - NOT NULL
- `person_id`: int (FK به persons) - nullable
- `issue_date`: datetime - NOT NULL (تاریخ چک)
- `due_date`: datetime - NOT NULL (تاریخ سررسید)
- `check_number`: varchar(50) - NOT NULL
- `sayad_code`: varchar(16) - nullable
- `bank_name`: varchar(255) - nullable
- `branch_name`: varchar(255) - nullable
- `amount`: numeric(18, 2) - NOT NULL
- `currency_id`: int (FK) - NOT NULL
- `status`: ENUM('RECEIVED_ON_HAND', 'TRANSFERRED_ISSUED', 'DEPOSITED', 'CLEARED', 'ENDORSED', 'RETURNED', 'BOUNCED', 'CANCELLED') - nullable
- `status_at`: datetime - nullable
- `current_holder_type`: ENUM('BUSINESS', 'BANK', 'PERSON') - nullable
- `current_holder_id`: int - nullable
- `last_action_document_id`: int (FK به documents) - nullable
- `developer_data`: JSON - nullable
- `created_at`: datetime - NOT NULL
- `updated_at`: datetime - NOT NULL

## آمار و توزیع داده‌ها

### نوع چک (type)
- `input`: 1,319 مورد (70.5%) → `RECEIVED`
- `output`: 553 مورد (29.5%) → `TRANSFERRED`

### وضعیت چک (status)
- `وصول نشده`: 1,227 مورد (65.6%)
- `واگذار شده`: 299 مورد (16.0%)
- `وصول`: 298 مورد (15.9%)
- `پاس نشده`: 38 مورد (2.0%)
- `پاس شده`: 9 مورد (0.5%)
- `برگشت خورده`: 1 مورد (0.1%)

### ارز (money_id)
- `money_id = 1` (IRR): 1,812 مورد (96.8%)
- `NULL`: 60 مورد (3.2%)

### سایر فیلدها
- چک‌های دارای `person_id`: 1,843 مورد (98.5%)
- چک‌های بدون `person_id`: 29 مورد (1.5%)
- چک‌های دارای `bank_id`: 307 مورد (16.4%)
- چک‌های دارای `sayad_num`: 1,869 مورد (99.8%)
- حداکثر طول `sayad_num`: 48 کاراکتر (باید truncate شود به 16)
- حداکثر طول `number`: 34 کاراکتر (مشکلی ندارد)
- حداکثر `amount`: 4,500,000,000,000 (در محدوده numeric(18,2) است)

### فیلدهای boolean
- `locked = 1`: 606 مورد (32.4%)
- `locked = 0`: 1,266 مورد (67.6%)
- `transfered = 1`: 299 مورد (16.0%)
- `transfered = NULL`: 1,573 مورد (84.0%)
- `rejected = 1`: 1 مورد (0.1%)
- `rejected = 0`: 59 مورد (3.2%)
- `rejected = NULL`: 1,812 مورد (96.8%)

### تکراری بودن
- چک‌های با `number` تکراری در یک کسب و کار: وجود دارد (باید مدیریت شود)
- چک‌های با `sayad_num` تکراری در یک کسب و کار: وجود دارد (باید مدیریت شود)

## نگاشت فیلدها

### نگاشت اصلی

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `bid_id` | `business_id` | نگاشت از business_id قدیمی به جدید |
| `type` | `type` | "input" → "RECEIVED", "output" → "TRANSFERRED" |
| `person_id` | `person_id` | نگاشت از person_id قدیمی به جدید |
| `date_stamp` | `issue_date` | تبدیل timestamp به datetime |
| `pay_date` | `due_date` | تبدیل string به datetime (یا از date_stamp استفاده) |
| `number` | `check_number` | مستقیم (محدود به 50 کاراکتر) |
| `sayad_num` | `sayad_code` | مستقیم (محدود به 16 کاراکتر - باید truncate شود) |
| `bank_oncheque` | `bank_name` | مستقیم |
| `amount` | `amount` | تبدیل string به numeric(18,2) |
| `money_id` | `currency_id` | نگاشت از money_id قدیمی به currency_id جدید |
| `status` | `status` | تبدیل status فارسی به ENUM انگلیسی |
| - | `branch_name` | NULL (اطلاعاتی در دیتابیس قدیمی نیست) |
| - | `status_at` | از date_submit یا date_stamp استفاده می‌شود |
| - | `current_holder_type` | از status و transfered محاسبه می‌شود |
| - | `current_holder_id` | از bank_id یا person_id استفاده می‌شود |
| - | `last_action_document_id` | از ref_id استفاده می‌شود (اگر document باشد) |

### فیلدهای حذف شده
- `submitter_id`: در دیتابیس جدید وجود ندارد
- `bank_id`: به `current_holder_id` تبدیل می‌شود (اگر `current_holder_type = 'BANK'`)
- `ref_id`: ممکن است به `last_action_document_id` تبدیل شود
- `des`: در دیتابیس جدید وجود ندارد (می‌توان در `developer_data` ذخیره کرد)
- `locked`: در دیتابیس جدید وجود ندارد
- `rejected`: در status لحاظ می‌شود
- `transfered`: در status و `current_holder_type` لحاظ می‌شود
- `transfer_date`: در دیتابیس جدید وجود ندارد
- `date`: در دیتابیس جدید وجود ندارد
- `date_submit`: ممکن است به `status_at` تبدیل شود

## تبدیل‌های پیچیده

### 1. تبدیل type

```python
def convert_type(old_type: str) -> str:
    if old_type == "input":
        return "RECEIVED"
    elif old_type == "output":
        return "TRANSFERRED"
    else:
        raise ValueError(f"Unknown type: {old_type}")
```

### 2. تبدیل status

| وضعیت قدیمی | وضعیت جدید | توضیحات |
|-------------|-------------|----------|
| `وصول نشده` | `RECEIVED_ON_HAND` | چک دریافتی در دست (برای input) |
| `وصول نشده` | `TRANSFERRED_ISSUED` | چک پرداختنی صادر شده (برای output) |
| `واگذار شده` | `ENDORSED` | واگذار شده به شخص ثالث |
| `وصول` | `CLEARED` | پاس/وصول شده |
| `پاس نشده` | `DEPOSITED` | سپرده به بانک (در جریان وصول) |
| `پاس شده` | `CLEARED` | پاس/وصول شده |
| `برگشت خورده` | `BOUNCED` | برگشت خورده |

**نکته**: تبدیل status به `type` چک بستگی دارد:
- برای `input` (RECEIVED):
  - `وصول نشده` → `RECEIVED_ON_HAND`
  - `واگذار شده` → `ENDORSED`
  - `وصول` → `CLEARED`
  - `پاس نشده` → `DEPOSITED`
  - `پاس شده` → `CLEARED`
  - `برگشت خورده` → `BOUNCED`
- برای `output` (TRANSFERRED):
  - `وصول نشده` → `TRANSFERRED_ISSUED`
  - `واگذار شده` → `ENDORSED`
  - `وصول` → `CLEARED`
  - `پاس نشده` → `DEPOSITED`
  - `پاس شده` → `CLEARED`
  - `برگشت خورده` → `BOUNCED`

### 3. تبدیل تاریخ‌ها

- `date_stamp`: timestamp (varchar) → `issue_date` (datetime)
- `pay_date`: string (مثل "1403/10/05") → `due_date` (datetime)
  - اگر `pay_date` معتبر نباشد، از `date_stamp` استفاده می‌شود
- `date_submit`: timestamp (varchar) → `status_at` (datetime)

### 4. تبدیل amount

- `amount`: varchar(255) → numeric(18,2)
- باید string را به عدد تبدیل کنیم
- حداکثر مقدار: 4,500,000,000,000 (در محدوده است)

### 5. تبدیل sayad_code

- `sayad_num`: varchar(50) → `sayad_code`: varchar(16)
- باید truncate شود به 16 کاراکتر
- حداکثر طول در دیتابیس قدیمی: 48 کاراکتر

### 6. نگاشت bank_id

- `bank_id` در دیتابیس قدیمی به `bank_account` اشاره می‌کند
- در دیتابیس جدید، باید به `bank_accounts` نگاشت شود
- اگر `bank_id` وجود داشت و `transfered = 1`، `current_holder_type = 'BANK'` و `current_holder_id` = new_bank_account_id

### 7. نگاشت person_id

- `person_id` در دیتابیس قدیمی به `person` اشاره می‌کند
- در دیتابیس جدید، باید به `persons` نگاشت شود
- اگر `person_id` وجود داشت و `transfered = 1`، `current_holder_type = 'PERSON'` و `current_holder_id` = new_person_id

### 8. محاسبه current_holder_type و current_holder_id

```python
def calculate_holder(old_cheque: Dict) -> Tuple[str | None, int | None]:
    if old_cheque.get('transfered') == 1:
        if old_cheque.get('bank_id'):
            return ('BANK', new_bank_account_id)
        elif old_cheque.get('person_id'):
            return ('PERSON', new_person_id)
        else:
            return ('BUSINESS', new_business_id)
    else:
        # اگر transfered نباشد، در دست کسب و کار است
        return ('BUSINESS', new_business_id)
```

## نگاشت ارز (money_id → currency_id)

از تحلیل قبلی می‌دانیم:
- `money_id = 1` → `currency_id = 1` (IRR)
- `money_id = 2` → `currency_id = 2` (USD)
- `money_id = 3` → `currency_id = 20` (AFN)
- `money_id = 4` → `currency_id = 19` (IQD)

**نکته**: برای مواردی که `money_id` NULL است، باید از ارز پیش‌فرض کسب و کار استفاده کنیم.

## چالش‌ها و راه‌حل‌ها

### 1. تکراری بودن check_number

- در دیتابیس قدیمی، `check_number` ممکن است در یک کسب و کار تکراری باشد
- در دیتابیس جدید، `(business_id, check_number)` باید unique باشد
- **راه‌حل**: اگر تکراری بود، باید skip شود یا یک suffix اضافه شود

### 2. تکراری بودن sayad_code

- در دیتابیس قدیمی، `sayad_num` ممکن است در یک کسب و کار تکراری باشد
- در دیتابیس جدید، `(business_id, sayad_code)` باید unique باشد (چند NULL مجاز است)
- **راه‌حل**: اگر تکراری بود، باید skip شود یا NULL شود

### 3. تبدیل pay_date

- `pay_date` در دیتابیس قدیمی string است (مثل "1403/10/05")
- باید به datetime تبدیل شود
- **راه‌حل**: استفاده از کتابخانه تاریخ شمسی برای تبدیل

### 4. محدودیت sayad_code

- `sayad_num` در دیتابیس قدیمی varchar(50) است
- در دیتابیس جدید varchar(16) است
- **راه‌حل**: truncate به 16 کاراکتر

### 5. نگاشت bank_id

- `bank_id` در دیتابیس قدیمی به `bank_account` اشاره می‌کند
- باید به `bank_accounts` جدید نگاشت شود
- **راه‌حل**: ایجاد mapping بین bank_account قدیمی و جدید

### 6. نگاشت person_id

- `person_id` در دیتابیس قدیمی به `person` اشاره می‌کند
- باید به `persons` جدید نگاشت شود
- **راه‌حل**: ایجاد mapping بین person قدیمی و جدید

### 7. فیلدهای حذف شده

- `submitter_id`, `des`, `locked`, `rejected`, `transfer_date`, `date` در دیتابیس جدید وجود ندارند
- **راه‌حل**: 
  - `des` می‌تواند در `developer_data` ذخیره شود
  - سایر فیلدها نادیده گرفته می‌شوند

### 8. ref_id

- `ref_id` ممکن است به document یا invoice اشاره کند
- در دیتابیس جدید، `last_action_document_id` به `documents` اشاره می‌کند
- **راه‌حل**: اگر `ref_id` به document اشاره می‌کند، نگاشت می‌شود، در غیر این صورت NULL می‌شود

## مراحل اجرا

1. ایجاد mapping بین `business_id` قدیمی و جدید
2. ایجاد mapping بین `money_id` قدیمی و `currency_id` جدید
3. ایجاد mapping بین `person_id` قدیمی و جدید
4. ایجاد mapping بین `bank_id` قدیمی (bank_account) و جدید (bank_accounts)
5. تبدیل `type` از "input"/"output" به "RECEIVED"/"TRANSFERRED"
6. تبدیل `status` از فارسی به ENUM انگلیسی
7. تبدیل تاریخ‌ها از timestamp/string به datetime
8. تبدیل `amount` از string به numeric
9. محاسبه `current_holder_type` و `current_holder_id`
10. مدیریت موارد تکراری (check_number و sayad_code)
11. انتقال چک‌ها

## آمار کلی

- **چک‌ها**: 1,872 رکورد
  - چک‌های دریافتی (input): 1,319 مورد (70.5%)
  - چک‌های پرداختنی (output): 553 مورد (29.5%)
- **وضعیت‌ها**: 6 وضعیت مختلف
- **ارز**: اکثراً IRR (96.8%)

