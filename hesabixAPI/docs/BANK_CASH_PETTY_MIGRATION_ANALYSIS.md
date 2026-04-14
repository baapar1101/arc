# تحلیل انتقال بانک، صندوق و تنخواه

## بررسی جداول

### دیتابیس قدیمی (hesabixOld)

#### 1. جدول `bank_account` (حساب‌های بانکی)
- **تعداد رکوردها**: 2,879
- **ساختار**:
  - `id`: int (PK)
  - `bid_id`: int (FK به business)
  - `name`: varchar(255) - نام حساب (NOT NULL نیست اما همه رکوردها مقدار دارند)
  - `card_num`: varchar(255) - شماره کارت
  - `shaba`: varchar(255) - شماره شبا
  - `account_num`: varchar(255) - شماره حساب
  - `owner`: varchar(255) - نام صاحب حساب
  - `shobe`: varchar(255) - شعبه
  - `pos_num`: varchar(255) - شماره POS
  - `des`: varchar(255) - توضیحات
  - `mobile_internet_bank`: varchar(25) - موبایل/اینترنت بانک
  - `code`: varchar(255) - کد (NOT NULL)
  - `balance`: varchar(255) - موجودی (استفاده نمی‌شود)
  - `money_id`: int (FK به money) - ارز

#### 2. جدول `cashdesk` (صندوق)
- **تعداد رکوردها**: 1,327
- **ساختار**:
  - `id`: int (PK)
  - `bid_id`: int (FK به business) - NOT NULL
  - `name`: varchar(255) - نام (NOT NULL)
  - `des`: longtext - توضیحات
  - `code`: varchar(255) - کد (NOT NULL)
  - `balance`: varchar(255) - موجودی (استفاده نمی‌شود)
  - `money_id`: int (FK به money) - ارز

**نکته مهم**: جدول `cashdesk` شامل صندوق‌ها است:
- همه رکوردها باید به `cash_registers` منتقل شوند
- هیچ موردی از `cashdesk` نباید به `petty_cash` منتقل شود

#### 3. جدول `salary` (تنخواه/تنخواه گردان)
- **تعداد رکوردها**: 395
- **ساختار**:
  - `id`: int (PK)
  - `bid_id`: int (FK به business) - NOT NULL
  - `name`: varchar(255) - نام (NOT NULL)
  - `des`: longtext - توضیحات
  - `code`: varchar(255) - کد (NOT NULL)
  - `balance`: varchar(255) - موجودی (استفاده نمی‌شود)
  - `money_id`: int (FK به money) - ارز

**نکته مهم**: جدول `salary` شامل تنخواه/تنخواه گردان‌ها است:
- همه رکوردها باید به `petty_cash` منتقل شوند
- تنخواه و تنخواه گردان یکسان هستند و تفاوتی بین آنها نیست

### دیتابیس جدید (hesabixpy)

#### 1. جدول `bank_accounts` (حساب‌های بانکی)
- `id`: int (PK)
- `business_id`: int (FK)
- `code`: varchar(50) - nullable
- `name`: varchar(255) - NOT NULL
- `description`: varchar(500) - nullable
- `branch`: varchar(255) - nullable (شعبه)
- `account_number`: varchar(50) - nullable
- `sheba_number`: varchar(30) - nullable
- `card_number`: varchar(20) - nullable
- `owner_name`: varchar(255) - nullable
- `pos_number`: varchar(50) - nullable
- `payment_id`: varchar(100) - nullable
- `currency_id`: int (FK) - NOT NULL
- `is_active`: boolean (default: true)
- `is_default`: boolean (default: false)
- `created_at`: datetime
- `updated_at`: datetime

#### 2. جدول `cash_registers` (صندوق)
- `id`: int (PK)
- `business_id`: int (FK)
- `code`: varchar(50) - nullable
- `name`: varchar(255) - NOT NULL
- `description`: varchar(500) - nullable
- `currency_id`: int (FK) - NOT NULL
- `is_active`: boolean (default: true)
- `is_default`: boolean (default: false)
- `payment_switch_number`: varchar(100) - nullable
- `payment_terminal_number`: varchar(100) - nullable
- `merchant_id`: varchar(100) - nullable
- `created_at`: datetime
- `updated_at`: datetime

#### 3. جدول `petty_cash` (تنخواه گردان)
- `id`: int (PK)
- `business_id`: int (FK)
- `code`: varchar(50) - nullable
- `name`: varchar(255) - NOT NULL
- `description`: varchar(500) - nullable
- `currency_id`: int (FK) - NOT NULL
- `is_active`: boolean (default: true)
- `is_default`: boolean (default: false)
- `created_at`: datetime
- `updated_at`: datetime

## نگاشت فیلدها

### 1. انتقال `bank_account` → `bank_accounts`

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `bid_id` | `business_id` | نگاشت از business_id قدیمی به جدید |
| `code` | `code` | مستقیم (محدود به 50 کاراکتر) |
| `name` | `name` | مستقیم |
| `des` | `description` | مستقیم (محدود به 500 کاراکتر) |
| `shobe` | `branch` | مستقیم |
| `account_num` | `account_number` | مستقیم (محدود به 50 کاراکتر) |
| `shaba` | `sheba_number` | مستقیم (محدود به 30 کاراکتر) |
| `card_num` | `card_number` | مستقیم (محدود به 20 کاراکتر) |
| `owner` | `owner_name` | مستقیم |
| `pos_num` | `pos_number` | مستقیم (محدود به 50 کاراکتر) |
| `mobile_internet_bank` | `payment_id` | مستقیم (محدود به 100 کاراکتر) |
| `money_id` | `currency_id` | نگاشت از money_id قدیمی به currency_id جدید |
| - | `is_active` | پیش‌فرض: true |
| - | `is_default` | پیش‌فرض: false |

**نکات**:
- فیلد `balance` در دیتابیس قدیمی استفاده نمی‌شود و منتقل نمی‌شود
- همه فیلدهای رشته‌ای باید به طول مجاز محدود شوند
- `code` در دیتابیس قدیمی NOT NULL است اما در جدید nullable است

### 2. انتقال `cashdesk` → `cash_registers`

- همه رکوردهای `cashdesk` باید به `cash_registers` منتقل شوند
- هیچ موردی از `cashdesk` نباید به `petty_cash` منتقل شود

### 3. انتقال `salary` → `petty_cash`

- همه رکوردهای `salary` باید به `petty_cash` منتقل شوند
- تنخواه و تنخواه گردان یکسان هستند و تفاوتی بین آنها نیست

#### نگاشت فیلدها برای `cash_registers`:

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `bid_id` | `business_id` | نگاشت از business_id قدیمی به جدید |
| `code` | `code` | مستقیم (محدود به 50 کاراکتر) |
| `name` | `name` | مستقیم |
| `des` | `description` | مستقیم (محدود به 500 کاراکتر) |
| `money_id` | `currency_id` | نگاشت از money_id قدیمی به currency_id جدید |
| - | `is_active` | پیش‌فرض: true |
| - | `is_default` | پیش‌فرض: false |
| - | `payment_switch_number` | NULL |
| - | `payment_terminal_number` | NULL |
| - | `merchant_id` | NULL |

#### نگاشت فیلدها برای `petty_cash` (از `salary`):

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `bid_id` | `business_id` | نگاشت از business_id قدیمی به جدید |
| `code` | `code` | مستقیم (محدود به 50 کاراکتر) |
| `name` | `name` | مستقیم |
| `des` | `description` | مستقیم (محدود به 500 کاراکتر) |
| `money_id` | `currency_id` | نگاشت از money_id قدیمی به currency_id جدید |
| - | `is_active` | پیش‌فرض: true |
| - | `is_default` | پیش‌فرض: false |

**نکته**: تنخواه و تنخواه گردان یکسان هستند و هر دو به `petty_cash` منتقل می‌شوند.

## نگاشت ارز (money_id → currency_id)

از تحلیل قبلی می‌دانیم:
- `money_id = 1` → `currency_id = 1` (IRR)
- `money_id = 2` → `currency_id = 2` (USD)
- `money_id = 3` → `currency_id = 20` (AFN)
- `money_id = 4` → `currency_id = 19` (IQD)

**توزیع در bank_account**:
- `money_id = 1`: 2,604 مورد (90.4%)
- `money_id = 2`: 9 مورد (0.3%)
- `money_id = 3`: 4 مورد (0.1%)
- `NULL`: 262 مورد (9.1%)

**توزیع در cashdesk**:
- `money_id = 1`: 1,117 مورد (84.2%)
- `money_id = 2`: 35 مورد (2.6%)
- `money_id = 3`: 8 مورد (0.6%)
- `NULL`: 167 مورد (12.6%)

**توزیع در salary**:
- `money_id = 1`: 342 مورد (86.6%)
- `money_id = 2`: 10 مورد (2.5%)
- `money_id = 3`: 1 مورد (0.3%)
- `NULL`: 42 مورد (10.6%)

**نکته**: برای مواردی که `money_id` NULL است، باید از ارز پیش‌فرض کسب و کار استفاده کنیم.

## چالش‌ها و راه‌حل‌ها

### 1. محدودیت طول فیلدها
- `code`: در قدیمی varchar(255)، در جدید varchar(50) → ✅ حداکثر 4 کاراکتر (مشکلی ندارد)
- `description`: در قدیمی varchar(255) یا longtext، در جدید varchar(500) → باید truncate شود (اگر بیش از 500 کاراکتر باشد)
- `sheba_number`: در قدیمی varchar(255)، در جدید varchar(30) → ⚠️ حداکثر 51 کاراکتر (باید truncate شود)
- `card_number`: در قدیمی varchar(255)، در جدید varchar(20) → ⚠️ حداکثر 53 کاراکتر (باید truncate شود)
- `account_number`: در قدیمی varchar(255)، در جدید varchar(50) → ⚠️ حداکثر 157 کاراکتر (باید truncate شود)

### 2. تشخیص صندوق از تنخواه
- جدول `cashdesk` → `cash_registers` (همه موارد - هیچ موردی به `petty_cash` نمی‌رود)
- جدول `salary` → `petty_cash` (همه موارد)
- **نکته مهم**: تنخواه و تنخواه گردان یکسان هستند و تفاوتی بین آنها نیست

### 3. مدیریت NULL در money_id
- اگر `money_id` NULL باشد، از `default_currency_id` کسب و کار استفاده می‌کنیم
- اگر کسب و کار `default_currency_id` نداشته باشد، از IRR (currency_id = 1) استفاده می‌کنیم

### 4. تکراری بودن code
- در دیتابیس قدیمی، `code` در هر کسب و کار ممکن است تکراری باشد
- در دیتابیس جدید، `(business_id, code)` باید unique باشد
- باید بررسی کنیم که آیا code تکراری وجود دارد یا نه

### 5. bid_id NULL در cashdesk
- ✅ بررسی شده: هیچ رکوردی با `bid_id` NULL وجود ندارد
- همه رکوردها قابل انتقال هستند

### 6. تکراری بودن code در هر کسب و کار
- ✅ بررسی شده: هیچ code تکراری در هر کسب و کار وجود ندارد
- همه رکوردها قابل انتقال هستند

## آمار کلی

- **حساب‌های بانکی**: 2,879 رکورد → `bank_accounts`
- **صندوق (cashdesk)**: 1,327 رکورد → `cash_registers` (همه موارد)
- **تنخواه/تنخواه گردان (salary)**: 395 رکورد → `petty_cash`

**نکته مهم**: 
- هیچ موردی از `cashdesk` به `petty_cash` منتقل نمی‌شود
- تنخواه و تنخواه گردان یکسان هستند و هر دو به `petty_cash` منتقل می‌شوند

## مراحل اجرا

1. ایجاد mapping بین `business_id` قدیمی و جدید
2. ایجاد mapping بین `money_id` قدیمی و `currency_id` جدید
3. انتقال `bank_account` → `bank_accounts`
4. انتقال `cashdesk` → `cash_registers` (همه موارد - هیچ موردی به `petty_cash` نمی‌رود)
5. انتقال `salary` → `petty_cash` (همه موارد - تنخواه و تنخواه گردان یکسان هستند)
7. بررسی و مدیریت موارد تکراری
8. بررسی و مدیریت موارد با `bid_id` NULL (✅ همه رکوردها bid_id دارند)

