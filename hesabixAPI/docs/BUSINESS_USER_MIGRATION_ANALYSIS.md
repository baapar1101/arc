# تحلیل انتقال کاربران عضو کسب و کار

## بررسی جداول

### دیتابیس قدیمی (hesabixOld)

#### 1. جدول `permission` (دسترسی‌های کاربران به کسب و کارها)
- **تعداد رکوردها**: 4,398
- **ساختار**:
  - `id`: int (PK)
  - `user_id`: int (FK به user) - NOT NULL
  - `bid_id`: int (FK به business) - NOT NULL
  - `owner`: tinyint(1) - آیا کاربر owner است؟
  - فیلدهای boolean متعدد برای دسترسی‌های مختلف:
    - `settings`, `person`, `commodity`, `getpay`, `banks`, `bank_transfer`
    - `buy`, `sell`, `cost`, `income`, `accounting`, `report`, `log`
    - `permission`, `salary`, `cashdesk`, `store`, `wallet`
    - `archive_upload`, `archive_mod`, `archive_delete`, `archive_view`
    - `shareholder`, `cheque`, `inquiry`, `ai`
    - و فیلدهای plugin مختلف (plug_noghre_admin, plug_repservice, و غیره)

**نکته**: این جدول دسترسی‌های کاربران به کسب و کارها را با فیلدهای boolean نگه می‌دارد. هر رکورد نشان می‌دهد که یک کاربر چه دسترسی‌هایی در یک کسب و کار دارد.

#### 2. جدول `shareholder` (سهامداران)
- **تعداد رکوردها**: 609
- **ساختار**:
  - `id`: int (PK)
  - `bid_id`: int (FK به business) - NOT NULL
  - `person_id`: int (FK به person) - NOT NULL
  - `percent`: int - درصد سهام

**نکته**: این جدول برای سهامداران است، نه کاربران عضو کسب و کار. سهامداران در جدول `persons` با `person_types` شامل "سهامدار" ذخیره می‌شوند.

### دیتابیس جدید (hesabixpy)

#### جدول `business_permissions` (کاربران عضو کسب و کار)
- **تعداد رکوردها**: 3 (در حال حاضر)
- **ساختار**:
  - `id`: int (PK)
  - `business_id`: int (FK به businesses) - NOT NULL
  - `user_id`: int (FK به users) - NOT NULL
  - `business_permissions`: JSON - nullable (دسترسی‌های کاربر در کسب و کار)
  - `created_at`: datetime - NOT NULL
  - `updated_at`: datetime - NOT NULL

**نکته**: این جدول ارتباط بین کاربران و کسب و کارها را نگه می‌دارد. هر رکورد نشان می‌دهد که یک کاربر عضو یک کسب و کار است و چه دسترسی‌هایی دارد.

## ساختار business_permissions (JSON)

نمونه ساختار JSON در `business_permissions`:

```json
{
  "join": true,
  "invoices": {
    "add": true,
    "edit": true,
    "view": true,
    "draft": true,
    "delete": true,
    "export": true
  },
  "products": {
    "add": true,
    "edit": true,
    "view": true,
    "delete": true,
    "export": true
  },
  "people": {
    "add": true,
    "edit": true,
    "view": true,
    "delete": true
  },
  "settings": {
    "view": true,
    "print": true,
    "users": true,
    "history": true,
    "business": true
  },
  ...
}
```

**فیلدهای مهم**:
- `join`: نشان می‌دهد که کاربر عضو کسب و کار است
- سایر فیلدها: دسترسی‌های مختلف به بخش‌های مختلف سیستم

## نگاشت فیلدها

### انتقال از `permission` → `business_permissions`

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `bid_id` | `business_id` | نگاشت از business_id قدیمی به جدید |
| `user_id` | `user_id` | نگاشت از user_id قدیمی به جدید |
| فیلدهای boolean | `business_permissions` | تبدیل فیلدهای boolean به ساختار JSON |
| - | `created_at` | datetime.utcnow() |
| - | `updated_at` | datetime.utcnow() |

**نکته مهم**: باید فیلدهای boolean را به ساختار JSON جدید تبدیل کنیم. برای مثال:
- `sell = 1` → `{"invoices": {"add": true, "edit": true, "view": true}}`
- `buy = 1` → `{"transfers": {"add": true, "edit": true, "view": true}}`
- `person = 1` → `{"people": {"add": true, "edit": true, "view": true, "delete": true}}`
- و غیره

## چالش‌ها و راه‌حل‌ها

### 1. ساختار متفاوت permission

- در دیتابیس قدیمی: `permission` با فیلدهای boolean متعدد (owner, settings, person, commodity, sell, buy, و غیره)
- در دیتابیس جدید: `business_permissions` با فیلد `business_permissions` (JSON با ساختار سلسله‌مراتبی)

**راه‌حل**: 
- باید یک تابع تبدیل بنویسیم که فیلدهای boolean قدیمی را به ساختار JSON جدید تبدیل کند
- نگاشت فیلدها:
  - `owner = 1`: کاربر owner است، نیازی به رکورد در `business_permissions` ندارد
  - `owner = 0`: کاربر عضو است، باید رکورد ایجاد شود
  - `sell = 1` → `invoices: {add, edit, view, delete, export}`
  - `buy = 1` → `transfers: {add, edit, view, delete}`
  - `person = 1` → `people: {add, edit, view, delete}`
  - `commodity = 1` → `products: {add, edit, view, delete, export}`
  - `banks = 1` → `bank_accounts: {add, edit, view, delete}`
  - `cashdesk = 1` → `cash: {add, edit, view, delete}` و `petty_cash: {add, edit, view, delete}`
  - `cheque = 1` → `checks: {add, edit, view, delete, return, collect, transfer}`
  - `settings = 1` → `settings: {view, print, users, history, business}`
  - `report = 1` → `reports: {view, export}`
  - و غیره

### 2. تکراری بودن (business_id, user_id)

- در دیتابیس قدیمی: ممکن است چند رکورد `permission` برای یک `(bid_id, user_id)` وجود داشته باشد
- در دیتابیس جدید: باید یک رکورد `business_permissions` برای هر `(business_id, user_id)` وجود داشته باشد

**راه‌حل**: 
- اگر چند رکورد `permission` برای یک `(bid_id, user_id)` وجود داشت، باید آنها را merge کنیم
- یا فقط یک رکورد ایجاد کنیم و بقیه را در `developer_data` ذخیره کنیم

### 3. عدم وجود permission برای owner

- در دیتابیس قدیمی: `owner_id` در جدول `business` ذخیره می‌شود
- در دیتابیس جدید: `owner_id` در جدول `businesses` ذخیره می‌شود
- **نکته**: owner نیازی به رکورد در `business_permissions` ندارد (چون owner است)

### 4. تبدیل فیلدهای boolean به JSON

- فیلدهای boolean در دیتابیس قدیمی (owner, settings, person, commodity, sell, buy, و غیره)
- `business_permissions` در دیتابیس جدید یک JSON object با ساختار سلسله‌مراتبی است

**راه‌حل**: 
- باید یک تابع تبدیل بنویسیم که:
  1. فیلدهای boolean را بخواند
  2. آنها را به ساختار JSON جدید تبدیل کند
  3. اگر فیلدی true بود، دسترسی‌های مربوطه را در JSON فعال کند
  4. اگر فیلدی false یا NULL بود، دسترسی‌های مربوطه را غیرفعال کند یا نادیده بگیرد

## آمار و توزیع

### دیتابیس قدیمی
- **permission**: 4,398 رکورد
  - کسب و کارهای منحصر به فرد: 4,137
  - کاربران منحصر به فرد: 3,949
  - رکوردهای با `owner = 1`: 4,137 (کاربران owner - نیازی به انتقال ندارند)
  - رکوردهای با `owner = 0`: 261 (کاربران عضو - باید منتقل شوند)
  - موارد تکراری: 1 مورد (bid_id=407, user_id=691)
- **shareholder**: 609 رکورد (316 کسب و کار) - این برای سهامداران است، نه کاربران عضو

### دیتابیس جدید
- **business_permissions**: 3 رکورد (3 کسب و کار، 3 کاربر)

## مراحل اجرا

1. بررسی جدول `permission` در دیتابیس قدیمی
2. ایجاد mapping بین `business_id` قدیمی و جدید
3. ایجاد mapping بین `user_id` قدیمی و جدید
4. تبدیل `name` به ساختار JSON (یا ذخیره در developer_data)
5. مدیریت موارد تکراری (merge کردن)
6. انتقال `permission` → `business_permissions`

## نکات مهم

1. **Owner**: 
   - کاربران با `owner = 1` در دیتابیس قدیمی، owner کسب و کار هستند
   - owner نیازی به رکورد در `business_permissions` ندارد (چون owner است)
   - فقط کاربران با `owner = 0` باید منتقل شوند (261 رکورد)

2. **سهامداران**: 
   - سهامداران در جدول `persons` با `person_types` شامل "سهامدار" ذخیره می‌شوند
   - جدول `shareholder` برای سهامداران است، نه کاربران عضو کسب و کار
   - سهامداران نیازی به رکورد در `business_permissions` ندارند

3. **دسترسی‌ها**: 
   - ساختار دسترسی‌ها در دیتابیس جدید بسیار پیچیده‌تر است (JSON با ساختار سلسله‌مراتبی)
   - باید فیلدهای boolean قدیمی را به ساختار JSON جدید تبدیل کنیم
   - نگاشت کامل فیلدها باید مشخص شود

4. **تکراری بودن**: 
   - فقط 1 مورد تکراری وجود دارد (bid_id=407, user_id=691)
   - باید مدیریت شود (merge کردن یا انتخاب یکی)

5. **فیلد join**: 
   - در دیتابیس جدید، فیلد `join: true` در JSON نشان می‌دهد که کاربر عضو کسب و کار است
   - باید برای همه کاربران عضو این فیلد را true قرار دهیم

