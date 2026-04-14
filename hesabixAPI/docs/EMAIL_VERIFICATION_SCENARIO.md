# سناریو پیاده‌سازی Email Verification

## سناریو کلی

### 1. ثبت‌نام کاربر
- کاربر با ایمیل و رمز عبور ثبت‌نام می‌کند
- اگر `enable_email_verification` فعال باشد:
  - یک verification token ایجاد می‌شود
  - یک ایمیل verification با لینک فعال‌سازی ارسال می‌شود
  - فیلد `email_verified` در User به `False` تنظیم می‌شود
  - کاربر می‌تواند login کند اما با محدودیت‌های خاص

### 2. ارسال ایمیل Verification
- ایمیل شامل:
  - لینک فعال‌سازی: `/api/v1/auth/verify-email?token=xxx`
  - توضیحات: "برای فعال‌سازی حساب کاربری خود روی لینک کلیک کنید"
  - زمان انقضا: 24 ساعت

### 3. فعال‌سازی ایمیل
- کاربر روی لینک کلیک می‌کند
- سیستم token را بررسی می‌کند:
  - معتبر بودن token
  - عدم انقضای token
  - تعلق token به کاربر
- در صورت معتبر بودن:
  - `email_verified` به `True` تنظیم می‌شود
  - token حذف می‌شود
  - پیام موفقیت برمی‌گردد

### 4. محدودیت‌های کاربر غیرفعال‌سازی شده
- کاربر می‌تواند login کند
- اما دسترسی به برخی endpoint ها محدود است:
  - ایجاد کسب‌وکار جدید
  - تغییر ایمیل
  - برخی عملیات حساس

### 5. ارسال مجدد ایمیل Verification
- اگر کاربر ایمیل را دریافت نکرده باشد
- endpoint: `/api/v1/auth/resend-verification`
- بررسی: حداکثر 3 بار در ساعت

### 6. بررسی در Login
- اگر `enable_email_verification` فعال باشد و `email_verified = False`:
  - کاربر می‌تواند login کند
  - اما یک flag در response برمی‌گردد: `email_verified: false`
  - فرانت‌اند باید صفحه verification را نمایش دهد

## ساختار داده

### User Model
- `email_verified: bool = False` - وضعیت تایید ایمیل

### EmailVerificationToken Model
- `id: int`
- `user_id: int` (FK to users)
- `token: str` (unique, hashed)
- `email: str` - ایمیل مورد نظر برای verification
- `expires_at: datetime` - زمان انقضا (24 ساعت)
- `created_at: datetime`
- `used_at: datetime | None` - زمان استفاده (اگر استفاده شده باشد)

## Endpoints

1. `POST /api/v1/auth/verify-email?token=xxx`
   - بررسی و فعال‌سازی ایمیل
   - Response: success message

2. `POST /api/v1/auth/resend-verification`
   - ارسال مجدد ایمیل verification
   - نیاز به authentication
   - Response: success message

## Service Functions

1. `create_email_verification_token(db, user_id, email) -> str`
   - ایجاد token و ذخیره در DB
   - ارسال ایمیل
   - بازگرداندن token (برای تست)

2. `verify_email_token(db, token) -> User`
   - بررسی معتبر بودن token
   - فعال‌سازی email_verified
   - حذف token

3. `can_resend_verification(db, user_id) -> bool`
   - بررسی امکان ارسال مجدد (rate limiting)

4. `send_verification_email(db, user_id, token) -> bool`
   - ارسال ایمیل verification

## تغییرات در Register
- اگر `enable_email_verification` فعال باشد:
  - `email_verified = False` تنظیم می‌شود
  - verification token ایجاد می‌شود
  - ایمیل ارسال می‌شود

## تغییرات در Login
- Response شامل `email_verified` می‌شود
- اگر `email_verified = False`:
  - فرانت‌اند باید صفحه verification را نمایش دهد



