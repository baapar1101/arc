# سناریوی انتقال کاربران از hesabixOld به hesabixpy

## خلاصه اجرایی

این سند سناریوی کامل انتقال کاربران از دیتابیس قدیمی (`hesabixOld`) به دیتابیس جدید (`hesabixpy`) را ارائه می‌دهد. تمرکز اصلی بر روی نحوه انتقال کاربران و مدیریت رمزهای عبور است.

## وضعیت فعلی

### دیتابیس قدیمی (hesabixOld)
- **جدول**: `user`
- **تعداد کاربران**: 4,904 کاربر
- **رمزهای عبور**: bcrypt با فرمت `$2y$13$...`
- **فیلدهای کلیدی**:
  - `id`: شناسه یکتا
  - `email`: ایمیل (unique, not null)
  - `password`: رمز عبور hash شده با bcrypt
  - `full_name`: نام کامل
  - `mobile`: شماره موبایل (nullable)
  - `active`: وضعیت فعال بودن (tinyint)
  - `date_register`: تاریخ ثبت‌نام (varchar timestamp)
  - `verify_code`: کد تأیید
  - `invited_by_id`: شناسه دعوت‌کننده
  - `invate_code`: کد دعوت

### دیتابیس جدید (hesabixpy)
- **جدول**: `users`
- **تعداد کاربران فعلی**: 75 کاربر
- **رمزهای عبور**: Argon2 با فرمت `$argon2id$v=19$...`
- **فیلدهای کلیدی**:
  - `id`: شناسه یکتا
  - `email`: ایمیل (unique, nullable)
  - `mobile`: شماره موبایل (unique, nullable)
  - `first_name`: نام
  - `last_name`: نام خانوادگی
  - `password_hash`: رمز عبور hash شده با Argon2
  - `is_active`: وضعیت فعال بودن (boolean)
  - `email_verified`: تأیید ایمیل (boolean)
  - `mobile_verified`: تأیید موبایل (boolean)
  - `referral_code`: کد معرف (unique, required)
  - `referred_by_user_id`: شناسه معرف
  - `telegram_chat_id`: شناسه چت تلگرام
  - `created_at`: تاریخ ایجاد
  - `updated_at`: تاریخ به‌روزرسانی

### مشکلات شناسایی شده
1. **2 موبایل تکراری** در دیتابیس قدیمی وجود دارد
2. **52 کاربر** از دیتابیس قدیمی در دیتابیس جدید وجود دارند (احتمالاً کاربران تست یا قبلاً منتقل شده)
3. **تفاوت در فرمت رمزهای عبور**: bcrypt vs Argon2
4. **تفاوت در ساختار فیلدها**: `full_name` vs `first_name`/`last_name`

## سناریوی انتقال

### مرحله 1: آماده‌سازی و بررسی

#### 1.1 بررسی داده‌های قدیمی
```sql
-- بررسی کاربران فعال
SELECT COUNT(*) FROM hesabixOld.user WHERE active = 1;

-- بررسی کاربران با ایمیل معتبر
SELECT COUNT(*) FROM hesabixOld.user WHERE email IS NOT NULL AND email != '';

-- بررسی کاربران با موبایل معتبر
SELECT COUNT(*) FROM hesabixOld.user WHERE mobile IS NOT NULL AND mobile != '';

-- بررسی کاربران تکراری (موبایل)
SELECT mobile, COUNT(*) as cnt 
FROM hesabixOld.user 
WHERE mobile IS NOT NULL 
GROUP BY mobile 
HAVING cnt > 1;

-- بررسی کاربران تکراری (ایمیل)
SELECT email, COUNT(*) as cnt 
FROM hesabixOld.user 
WHERE email IS NOT NULL 
GROUP BY email 
HAVING cnt > 1;
```

#### 1.2 شناسایی کاربران موجود در دیتابیس جدید
```sql
-- کاربرانی که در هر دو دیتابیس وجود دارند (بر اساس ایمیل)
SELECT old.id as old_id, old.email, new.id as new_id
FROM hesabixOld.user old
INNER JOIN hesabixpy.users new ON old.email = new.email
WHERE old.active = 1;

-- کاربرانی که در هر دو دیتابیس وجود دارند (بر اساس موبایل)
SELECT old.id as old_id, old.mobile, new.id as new_id
FROM hesabixOld.user old
INNER JOIN hesabixpy.users new ON old.mobile = new.mobile
WHERE old.active = 1 AND old.mobile IS NOT NULL;
```

#### 1.3 ایجاد جدول موقت برای نگهداری mapping
```sql
CREATE TABLE hesabixpy.user_migration_mapping (
    old_user_id INT NOT NULL,
    new_user_id INT NULL,
    migration_status ENUM('pending', 'migrated', 'skipped', 'error') DEFAULT 'pending',
    migration_reason VARCHAR(255) NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (old_user_id),
    INDEX idx_status (migration_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### مرحله 2: استراتژی مدیریت رمزهای عبور

#### 2.1 چالش رمزهای عبور
- **سیستم قدیمی**: bcrypt (`$2y$13$...`)
- **سیستم جدید**: Argon2 (`$argon2id$v=19$...`)
- **مشکل**: Argon2 نمی‌تواند رمزهای bcrypt را verify کند

#### 2.2 راه‌حل‌های پیشنهادی

##### راه‌حل 1: نگهداری رمزهای bcrypt (پیشنهادی)
**مزایا**:
- کاربران می‌توانند با رمز قدیمی خود وارد شوند
- نیاز به تغییر رمز عبور نیست
- تجربه کاربری بهتر

**معایب**:
- نیاز به پشتیبانی از دو الگوریتم hash
- کد پیچیده‌تر می‌شود

**پیاده‌سازی**:
1. رمزهای bcrypt را مستقیماً در `password_hash` ذخیره کنیم
2. تابع `verify_password` را تغییر دهیم تا ابتدا Argon2 را چک کند، سپس bcrypt را
3. هنگام تغییر رمز عبور، رمز جدید را با Argon2 hash کنیم

##### راه‌حل 2: تبدیل به Argon2 (نیاز به رمزهای خام)
**مزایا**:
- یک الگوریتم واحد
- امنیت بهتر (Argon2)

**معایب**:
- نیاز به رمزهای خام کاربران (غیرممکن)
- کاربران باید رمز خود را reset کنند

##### راه‌حل 3: ترکیبی (پیشنهادی برای بلندمدت)
1. در مرحله اول: رمزهای bcrypt را نگه داریم و از هر دو الگوریتم پشتیبانی کنیم
2. در مرحله بعد: هنگام ورود کاربر، اگر رمز bcrypt است، آن را به Argon2 تبدیل کنیم (نیاز به رمز خام)
3. یا: هنگام تغییر رمز، رمز جدید را با Argon2 hash کنیم

**توصیه**: استفاده از راه‌حل 1 برای انتقال اولیه، سپس راه‌حل 3 برای بهینه‌سازی

### مرحله 3: تبدیل و نگاشت داده‌ها

#### 3.1 تبدیل فیلدها

| فیلد قدیمی | فیلد جدید | تبدیل |
|------------|-----------|-------|
| `id` | - | نگه‌داری در mapping table |
| `email` | `email` | مستقیم (normalize: lowercase, trim) |
| `password` | `password_hash` | مستقیم (bcrypt) |
| `full_name` | `first_name`, `last_name` | تقسیم بر اساس فاصله |
| `mobile` | `mobile` | normalize (حذف صفر اول، اضافه کردن +98) |
| `active` | `is_active` | تبدیل boolean |
| `date_register` | `created_at` | تبدیل timestamp به datetime |
| `invited_by_id` | `referred_by_user_id` | نگاشت از mapping table |
| `invate_code` | `referral_code` | استفاده از invate_code یا تولید جدید |

#### 3.2 تبدیل full_name به first_name و last_name

**الگوریتم**:
1. اگر `full_name` خالی است: `first_name = NULL`, `last_name = NULL`
2. اگر `full_name` یک کلمه است: `first_name = full_name`, `last_name = NULL`
3. اگر `full_name` چند کلمه است:
   - کلمه اول: `first_name`
   - بقیه کلمات: `last_name` (با فاصله)

**مثال**:
- `"محسن نقی پور"` → `first_name = "محسن"`, `last_name = "نقی پور"`
- `"محمد"` → `first_name = "محمد"`, `last_name = NULL`
- `"علی"` → `first_name = "علی"`, `last_name = NULL`


#### 3.4 تولید referral_code

**الگوریتم**:
1. اگر `invate_code` در دیتابیس قدیمی وجود دارد و unique است: استفاده از آن
2. در غیر این صورت: تولید کد جدید با الگوریتم سیستم جدید

**تولید کد جدید**:
- طول: 32 کاراکتر
- کاراکترها: حروف بزرگ، حروف کوچک، اعداد
- بررسی unique بودن

#### 3.5 نگاشت referred_by_user_id

**الگوریتم**:
1. اگر `invited_by_id` در دیتابیس قدیمی NULL است: `referred_by_user_id = NULL`
2. در غیر این صورت:
   - جستجو در `user_migration_mapping` برای یافتن `new_user_id`
   - اگر پیدا شد: استفاده از آن
   - اگر پیدا نشد: `referred_by_user_id = NULL` (کاربر معرف هنوز منتقل نشده)

### مرحله 4: الگوریتم انتقال

#### 4.1 فیلتر کاربران برای انتقال

**شرایط انتقال**:
1. کاربر باید `active = 1` باشد
2. کاربر باید حداقل یکی از `email` یا `mobile` را داشته باشد
3. کاربر نباید در دیتابیس جدید وجود داشته باشد (بر اساس email یا mobile)

**SQL برای انتخاب کاربران**:
```sql
SELECT u.*
FROM hesabixOld.user u
WHERE u.active = 1
  AND (u.email IS NOT NULL OR u.mobile IS NOT NULL)
  AND NOT EXISTS (
    SELECT 1 FROM hesabixpy.users new
    WHERE (new.email = u.email AND u.email IS NOT NULL)
       OR (new.mobile = u.mobile AND u.mobile IS NOT NULL)
  )
ORDER BY u.id;
```

#### 4.2 پردازش هر کاربر

**مراحل پردازش**:

1. **بررسی تکراری بودن**:
   - بررسی email در دیتابیس جدید
   - بررسی mobile در دیتابیس جدید
   - اگر تکراری است: skip با reason "duplicate_email" یا "duplicate_mobile"

2. **تبدیل داده‌ها**:
   - تبدیل `full_name` به `first_name` و `last_name`
   - normalize کردن `email` (lowercase, trim)
   - normalize کردن `mobile` (حذف صفر اول، اضافه کردن +98)
   - تبدیل `date_register` به `created_at`
   - تولید یا استفاده از `referral_code`
   - نگاشت `referred_by_user_id`

3. **ایجاد کاربر جدید**:
   - درج در جدول `users`
   - ذخیره `old_user_id` و `new_user_id` در `user_migration_mapping`
   - تنظیم `migration_status = 'migrated'`

4. **مدیریت خطاها**:
   - در صورت خطا: ثبت در `user_migration_mapping` با `migration_status = 'error'`
   - ذخیره پیام خطا در `migration_reason`

#### 4.3 مدیریت کاربران تکراری

**سناریو 1: کاربر در دیتابیس جدید وجود دارد**
- بررسی: آیا کاربر با همان email یا mobile در دیتابیس جدید وجود دارد؟
- عمل: skip کردن با reason "already_exists"
- ثبت در mapping table با `migration_status = 'skipped'`

**سناریو 2: موبایل تکراری در دیتابیس قدیمی**
- بررسی: آیا چند کاربر با همان mobile وجود دارند؟
- عمل: فقط اولین کاربر (بر اساس id) را منتقل کنیم
- سایرین: skip با reason "duplicate_mobile_in_old_db"

### مرحله 5: به‌روزرسانی تابع verify_password

#### 5.1 تغییرات مورد نیاز در `app/core/security.py`

**تابع جدید**:
```python
def verify_password(password: str, password_hash: str) -> bool:
    """
    بررسی رمز عبور با پشتیبانی از Argon2 و bcrypt
    """
    # ابتدا سعی می‌کنیم با Argon2 verify کنیم
    try:
        _ph.verify(password_hash, password)
        return True
    except Exception:
        pass
    
    # اگر Argon2 کار نکرد، سعی می‌کنیم با bcrypt verify کنیم
    try:
        import bcrypt
        # بررسی فرمت bcrypt
        if password_hash.startswith('$2y$') or password_hash.startswith('$2a$') or password_hash.startswith('$2b$'):
            # تبدیل $2y$ به $2b$ برای سازگاری با bcrypt Python
            if password_hash.startswith('$2y$'):
                password_hash = '$2b$' + password_hash[4:]
            return bcrypt.checkpw(password.encode('utf-8'), password_hash.encode('utf-8'))
    except Exception:
        pass
    
    return False
```

**نکته**: نیاز به نصب کتابخانه `bcrypt`:
```bash
pip install bcrypt
```

#### 5.2 بهینه‌سازی: تبدیل خودکار به Argon2

**استراتژی**:
- هنگام ورود موفق کاربر با رمز bcrypt، می‌توانیم رمز را به Argon2 تبدیل کنیم
- اما این نیاز به رمز خام دارد که در دسترس است (از request)
- می‌توانیم در تابع `login_user` این تبدیل را انجام دهیم

**کد پیشنهادی**:
```python
def login_user(...):
    # ... کد موجود ...
    
    if user and verify_password(password, user.password_hash):
        # اگر رمز bcrypt است، آن را به Argon2 تبدیل کن
        if user.password_hash.startswith('$2y$') or user.password_hash.startswith('$2a$') or user.password_hash.startswith('$2b$'):
            user.password_hash = hash_password(password)  # تبدیل به Argon2
            db.commit()
        
        # ... ادامه کد ...
```

### مرحله 6: اسکریپت انتقال

#### 6.1 اسکریپت آماده شده

**فایل**: `scripts/migrate_users_from_old_db.py`

**ویژگی‌ها**:
1. ✅ اتصال به هر دو دیتابیس
2. ✅ خواندن کاربران از دیتابیس قدیمی
3. ✅ تبدیل و نگاشت داده‌ها
4. ✅ درج در دیتابیس جدید
5. ✅ لاگ‌گیری کامل
6. ✅ قابلیت dry-run (تست بدون تغییر)
7. ✅ مدیریت خودکار کاربران تکراری
8. ✅ تبدیل خودکار full_name به first_name/last_name
9. ✅ نگه‌داری رمزهای bcrypt
10. ✅ تولید referral_code یکتا

#### 6.2 پارامترهای اسکریپت

```bash
python scripts/migrate_users_from_old_db.py [OPTIONS]
```

**پارامترها**:
- `--dry-run`: اجرای تست بدون تغییر در دیتابیس (پیشنهاد می‌شود ابتدا این را اجرا کنید)
- `--batch-size`: تعداد کاربران در هر batch (پیش‌فرض: 100)
- `--start-id`: شروع از شناسه خاص
- `--limit`: محدود کردن تعداد کاربران (برای تست)
- `--old-db`: نام دیتابیس قدیمی (پیش‌فرض: hesabixOld)
- `--new-db`: نام دیتابیس جدید (پیش‌فرض: hesabixpy)
- `--db-user`: نام کاربری دیتابیس (پیش‌فرض: root)
- `--db-password`: رمز عبور دیتابیس (پیش‌فرض: 136431)
- `--db-host`: آدرس دیتابیس (پیش‌فرض: localhost)
- `--db-port`: پورت دیتابیس (پیش‌فرض: 3306)

#### 6.3 نحوه استفاده

**1. تست اولیه (dry-run)**:
```bash
cd hesabixAPI
python scripts/migrate_users_from_old_db.py --dry-run --limit 10
```

**2. تست با تعداد محدود**:
```bash
python scripts/migrate_users_from_old_db.py --limit 100
```

**3. اجرای کامل**:
```bash
python scripts/migrate_users_from_old_db.py --batch-size 100
```

#### 6.4 خروجی و گزارش

**گزارش شامل**:
- تعداد کل کاربران پردازش شده
- تعداد کاربران منتقل شده
- تعداد کاربران skip شده (موجود در جدید)
- تعداد کاربران skip شده (بدون identifier)
- تعداد خطاها
- لیست خطاها با جزئیات (حداکثر 10 خطای اول)

### مرحله 7: تست و اعتبارسنجی

#### 7.1 تست‌های واحد

1. **تست تبدیل full_name**:
   - ورودی: `"محسن نقی پور"` → خروجی: `first_name="محسن"`, `last_name="نقی پور"`
   - ورودی: `"محمد"` → خروجی: `first_name="محمد"`, `last_name=NULL`

2. **تست verify_password با bcrypt**:
   - تست با رمز bcrypt قدیمی
   - تست با رمز Argon2 جدید

3. **تست normalize mobile**:
   - `"09180000000"` → `"+989180000000"`
   - `"9180000000"` → `"+989180000000"`

#### 7.2 تست یکپارچگی

1. **تست انتقال نمونه**:
   - انتخاب 10 کاربر نمونه از دیتابیس قدیمی
   - انتقال آنها
   - بررسی صحت داده‌ها

2. **تست ورود**:
   - ورود با رمز قدیمی (bcrypt)
   - بررسی تبدیل خودکار به Argon2

#### 7.3 تست عملکرد

1. **تست سرعت**:
   - اندازه‌گیری زمان انتقال 1000 کاربر
   - بهینه‌سازی در صورت نیاز

2. **تست همزمانی**:
   - بررسی تداخل در صورت اجرای همزمان

### مرحله 8: اجرای نهایی

#### 8.1 آماده‌سازی

1. **پشتیبان‌گیری**:
   - پشتیبان از دیتابیس `hesabixpy`
   - پشتیبان از دیتابیس `hesabixOld`

2. **تست در محیط staging**:
   - اجرای کامل در محیط تست
   - بررسی نتایج

#### 8.2 اجرا

1. **اجرای dry-run**:
   ```bash
   python scripts/migrate_users.py --dry-run --verbose
   ```

2. **بررسی نتایج dry-run**:
   - بررسی تعداد کاربران
   - بررسی خطاها

3. **اجرای واقعی**:
   ```bash
   python scripts/migrate_users.py --batch-size 100 --verbose
   ```

4. **نظارت**:
   - نظارت بر لاگ‌ها
   - بررسی خطاها
   - بررسی عملکرد

#### 8.3 پس از اجرا

1. **اعتبارسنجی**:
   - مقایسه تعداد کاربران
   - تست ورود چند کاربر نمونه
   - بررسی یکپارچگی داده‌ها

2. **پاکسازی**:
   - حذف جدول `user_migration_mapping` (اختیاری)
   - یا نگه‌داری برای audit

## خلاصه مراحل

1. ✅ بررسی و آماده‌سازی داده‌ها
2. ✅ اضافه کردن bcrypt به dependencies
3. ✅ به‌روزرسانی تابع verify_password برای پشتیبانی از bcrypt
4. ✅ به‌روزرسانی login_user برای تبدیل خودکار bcrypt به Argon2
5. ✅ نوشتن اسکریپت انتقال
6. ⏳ تست در محیط staging (با --dry-run)
7. ⏳ پشتیبان‌گیری
8. ⏳ اجرای انتقال
9. ⏳ اعتبارسنجی

## نکات مهم

1. **رمزهای عبور**: رمزهای bcrypt را مستقیماً نگه می‌داریم و از هر دو الگوریتم پشتیبانی می‌کنیم
2. **کاربران تکراری**: فقط کاربران فعال و غیرتکراری را منتقل می‌کنیم
3. **کاربران موجود**: کاربرانی که در دیتابیس جدید وجود دارند را skip می‌کنیم
4. **بهینه‌سازی**: هنگام ورود کاربر با رمز bcrypt، آن را به Argon2 تبدیل می‌کنیم
5. **لاگ‌گیری**: تمام مراحل را لاگ می‌کنیم برای audit و debug

## ریسک‌ها و راه‌حل‌ها

### ریسک 1: از دست رفتن داده‌ها
**راه‌حل**: پشتیبان‌گیری کامل قبل از انتقال

### ریسک 2: خطا در انتقال
**راه‌حل**: استفاده از transaction و rollback در صورت خطا

### ریسک 3: کاربران تکراری
**راه‌حل**: بررسی دقیق قبل از انتقال و skip کردن تکراری‌ها

### ریسک 4: مشکل در verify رمزهای bcrypt
**راه‌حل**: تست کامل تابع verify_password قبل از اجرا

## نتیجه‌گیری

این سناریو راهنمای کامل انتقال کاربران از دیتابیس قدیمی به جدید است. تمرکز اصلی بر روی:
- حفظ رمزهای عبور کاربران (بدون نیاز به reset)
- تبدیل صحیح داده‌ها
- مدیریت کاربران تکراری
- پشتیبانی از هر دو الگوریتم hash (bcrypt و Argon2)

پس از اجرای موفق، کاربران می‌توانند با رمز قدیمی خود وارد شوند و سیستم به تدریج رمزهای آن‌ها را به Argon2 تبدیل می‌کند.

