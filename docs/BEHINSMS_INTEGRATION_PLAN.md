# طرح ادغام پیامک بهین اس ام اس (Behin SMS Integration Plan)

## خلاصه

این مستند راهنمای کامل برای ادغام سرویس پیامک بهین اس ام اس (Behin SMS) در سیستم Hesabix است. بر اساس راهنمای ارائه شده، این طرح نحوه پیاده‌سازی و استفاده از API بهین اس ام اس را شرح می‌دهد.

### موارد استفاده از پیامک در این طرح:

1. **ارسال ناتیفیکیشن به کاربران سیستم** - از طریق سیستم Notification موجود
2. **ارسال پیامک به مشتریان و طرف‌های حساب** - برای اطلاع‌رسانی و ارتباط
3. **تایید شماره موبایل** - در زمان ثبت‌نام یا تغییر شماره موبایل
4. **بازیابی کلمه عبور** - از طریق ارسال OTP به موبایل
5. **ورود با OTP** - امکان ورود بدون نیاز به رمز عبور
6. **احراز هویت دو مرحله‌ای (2FA)** - افزایش امنیت حساب کاربری

## ساختار فعلی سیستم

### 1. ساختار SMS Provider

سیستم فعلی یک `SmsProvider` پایه دارد که در مسیر زیر قرار دارد:
- **Backend**: `hesabixAPI/app/services/providers/sms_provider.py`
- این Provider فعلاً یک stub است و فقط `send_text()` را به صورت placeholder پیاده‌سازی کرده است.

### 2. ساختار تنظیمات سیستم

تنظیمات SMS در بخش زیر ذخیره می‌شوند:
- **کلیدهای تنظیمات** (در `system_settings_service.py`):
  - `NOTIFY_SMS_PROVIDER` = "sms_provider_name"
  - `NOTIFY_SMS_API_KEY` = "sms_api_key" 
  - `NOTIFY_SMS_SENDER` = "sms_sender"

- **API Endpoint برای مدیر سیستم**:
  - `GET /api/v1/admin/system-settings/notifications` - دریافت تنظیمات
  - `PUT /api/v1/admin/system-settings/notifications` - ذخیره تنظیمات

- **UI صفحه تنظیمات**:
  - `hesabixUI/hesabix_ui/lib/pages/profile/notifications_settings_page.dart`
  - در بخش Advanced، فیلدهای SMS Provider، API Key و Sender موجود است.

### 3. ساختار اطلاعات تماس

اطلاعات تماس مشتریان و طرف‌های حساب در مدل `Person` ذخیره می‌شود:
- **مدل**: `hesabixAPI/adapters/db/models/person.py`
- **فیلدهای مرتبط**:
  - `mobile: Mapped[str | None]` - شماره موبایل
  - `phone: Mapped[str | None]` - تلفن ثابت
  - `email: Mapped[str | None]` - ایمیل

## نیازمندی‌های ادغام

### 1. تنظیمات اضافی برای بهین اس ام اس

بر اساس راهنما، بهین اس ام اس نیاز به پارامترهای زیر دارد:
- **UserName** (نام کاربری)
- **Password** (کلمه عبور)
- **SpecialNumber** (شماره اختصاصی - همان `sms_sender` است)

**پیشنهاد**: 
- می‌توانیم `sms_api_key` را برای ذخیره UserName و Password استفاده کنیم (به صورت JSON یا format خاص)
- یا فیلدهای جداگانه اضافه کنیم:
  - `sms_provider_username`
  - `sms_provider_password`
  - `sms_sender` (قبلاً موجود است)

**توصیه**: بهتر است فیلدهای جداگانه اضافه شود تا امنیت و خوانایی بهتر شود.

### 2. تنظیمات اختیاری

- **IsFlashMessage**: آیا پیامک به صورت Flash ارسال شود (پیش‌فرض: False)
- **CheckingMessageID**: شناسه منحصر به فرد برای ردیابی (اختیاری)

## طرح پیاده‌سازی

### Phase 1: تکمیل تنظیمات سیستم

#### 1.1 به‌روزرسانی Backend Settings

**فایل**: `hesabixAPI/app/services/system_settings_service.py`

**تغییرات مورد نیاز**:
1. افزودن کلیدهای جدید:
   ```python
   NOTIFY_SMS_PROVIDER_USERNAME = "sms_provider_username"
   NOTIFY_SMS_PROVIDER_PASSWORD = "sms_provider_password"
   NOTIFY_SMS_IS_FLASH = "sms_is_flash"  # اختیاری
   ```

2. به‌روزرسانی `get_notifications_settings()` برای خواندن فیلدهای جدید

3. به‌روزرسانی `set_notifications_settings()` برای ذخیره فیلدهای جدید

4. به‌روزرسانی `get_effective_notifications_settings()` برای merge با env variables

#### 1.2 به‌روزرسانی API Endpoints

**فایل**: `hesabixAPI/adapters/api/v1/admin/system_settings.py`

**تغییرات مورد نیاز**:
1. به‌روزرسانی `NotificationsConfigPayload` برای شامل کردن:
   - `sms_provider_username: str | None`
   - `sms_provider_password: str | None`
   - `sms_is_flash: bool | None` (اختیاری)

2. به‌روزرسانی `put_notifications_settings_endpoint()` برای پاس دادن فیلدهای جدید

#### 1.3 به‌روزرسانی UI تنظیمات

**فایل**: `hesabixUI/hesabix_ui/lib/pages/profile/notifications_settings_page.dart`

**تغییرات مورد نیاز**:
1. افزودن `TextEditingController` برای:
   - `_smsUsernameCtrl`
   - `_smsPasswordCtrl` (با `obscureText: true`)

2. افزودن `SwitchListTile` برای Flash Message (اختیاری)

3. به‌روزرسانی `_collectAdvancedPayload()` برای شامل کردن فیلدهای جدید

4. به‌روزرسانی `_load()` برای خواندن فیلدهای جدید

### Phase 2: پیاده‌سازی Behin SMS Provider

#### 2.1 ایجاد کلاس BehinSmsProvider

**فایل جدید**: `hesabixAPI/app/services/providers/behin_sms_provider.py`

**ساختار کلی**:
```python
class BehinSmsProvider:
    BASE_URL = "https://panel.behinsms.com/smsws/HttpService.ashx"
    
    def __init__(self, username: str, password: str, sender: str):
        self.username = username
        self.password = password
        self.sender = sender
    
    def send_text(self, to_phone: str, text: str, 
                  is_flash: bool = False, 
                  checking_message_id: str | None = None) -> tuple[bool, str | None]:
        """
        ارسال پیامک به یک یا چند شماره
        Returns: (success: bool, message_id: str | None or error_code: str)
        """
        # استفاده از متد SendArray
        pass
    
    def send_bulk(self, recipient_numbers: list[str], text: str,
                  is_flash: bool = False) -> tuple[bool, list[str] | None]:
        """
        ارسال پیامک به چند شماره (تا 1000 شماره)
        """
        pass
    
    def get_credit(self) -> tuple[bool, float | None, str | None]:
        """
        دریافت اعتبار باقیمانده
        Returns: (success, credit_amount, error_message)
        """
        pass
    
    def get_message_status(self, message_id: str) -> tuple[bool, int | None, str | None]:
        """
        دریافت وضعیت پیامک
        Returns: (success, status_code, error_message)
        """
        pass
```

**متدهای پیاده‌سازی شده بر اساس راهنما**:

1. **SendArray**: برای ارسال عادی
2. **GetCredit**: برای بررسی اعتبار
3. **GetMessageStatus**: برای ردیابی وضعیت (اختیاری)

**متدهای پیشرفته (برای آینده)**:
- SendArraySchedule: برای زمانبندی
- GetInboxMessage: برای دریافت پیامک‌های ورودی
- SendNumberGroup: برای ارسال به گروه‌ها

#### 2.2 به‌روزرسانی SmsProvider اصلی

**فایل**: `hesabixAPI/app/services/providers/sms_provider.py`

**تغییرات**:
```python
class SmsProvider:
    def __init__(self, *, provider_name: str | None = None, 
                 api_key: str | None = None, 
                 sender: str | None = None,
                 username: str | None = None,
                 password: str | None = None,
                 is_flash: bool = False):
        # ...
        # تشخیص Provider و استفاده از کلاس مناسب
        if provider_name == "behinsms":
            self._provider = BehinSmsProvider(
                username=username or "",
                password=password or "",
                sender=sender or ""
            )
        else:
            self._provider = None
    
    def send_text(self, *, to_phone: str, text: str) -> bool:
        if not self.is_configured():
            return False
        if self._provider:
            success, _ = self._provider.send_text(to_phone, text, is_flash=self.is_flash)
            return success
        return False
```

#### 2.3 به‌روزرسانی NotificationService

**فایل**: `hesabixAPI/app/services/notification_service.py`

**تغییرات**:
```python
notify_cfg = get_effective_notifications_settings(db)
self.sms = SmsProvider(
    provider_name=notify_cfg.get("sms_provider_name"),
    api_key=notify_cfg.get("sms_api_key"),  # ممکن است استفاده نشود
    sender=notify_cfg.get("sms_sender"),
    username=notify_cfg.get("sms_provider_username"),
    password=notify_cfg.get("sms_provider_password"),
    is_flash=notify_cfg.get("sms_is_flash", False),
)
```

### Phase 3: فرمت‌سازی شماره تلفن

بر اساس راهنما، شماره‌ها باید به فرمت‌های زیر باشد:
- `0912???????` (یازده کاراکتر) - پیشنهادی
- `98912???????` (دوازده کاراکتر)
- `912???????` (ده کاراکتر)

**نیاز به Utility Function**:
```python
def normalize_phone_number(phone: str) -> str:
    """
    نرمال‌سازی شماره تلفن به فرمت استاندارد بهین اس ام اس
    """
    # حذف فاصله، خط تیره و ...
    phone = re.sub(r'[\s\-\(\)]', '', phone)
    
    # حذف + و 00
    if phone.startswith('+98'):
        phone = '0' + phone[3:]
    elif phone.startswith('0098'):
        phone = '0' + phone[4:]
    elif phone.startswith('98'):
        phone = '0' + phone[2:]
    
    # اطمینان از شروع با 0
    if not phone.startswith('0'):
        phone = '0' + phone
    
    # بررسی طول (باید 11 رقم باشد)
    if len(phone) == 11 and phone.startswith('09'):
        return phone
    
    raise ValueError(f"فرمت شماره نامعتبر: {phone}")
```

### Phase 4: مدیریت خطاها

بر اساس راهنما، کدهای خطا عددی هستند (کمتر از 1000 یا بزرگتر از 50).

**نیاز به Error Mapping**:
```python
BEHINSMS_ERROR_CODES = {
    51: "نام کاربری یا رمز عبور اشتباه است",
    52: "نام کاربری یا رمز عبور خالی است",
    54: "کلید RecipientNumber خالی است",
    61: "شماره اختصاصی نامعتبر است",
    63: "این IP اجازه دسترسی ندارد",
    70: "کاربر غیر فعال شده است",
    203: "به علت کمبود اعتبار پیام کوتاه شما توانایی ارسال ندارید",
    # ...
}
```

### Phase 5: ارسال پیامک به مشتریان و طرف‌های حساب

#### 5.1 ایجاد API Endpoint جدید

**فایل**: `hesabixAPI/adapters/api/v1/business/persons.py` (یا فایل مشابه)

**Endpoint پیشنهادی**:
```python
@router.post("/persons/{person_id}/send-sms")
def send_sms_to_person(
    person_id: int,
    payload: SendSmsPayload,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    ارسال پیامک به یک شخص (مشتری/طرف حساب)
    """
    # 1. بررسی دسترسی کاربر به business
    # 2. دریافت Person از دیتابیس
    # 3. بررسی وجود شماره موبایل
    # 4. نرمال‌سازی شماره
    # 5. ارسال پیامک از طریق SmsProvider
    # 6. ثبت در لاگ/تاریخچه
    pass
```

**Payload**:
```python
class SendSmsPayload(BaseModel):
    message: str
    is_flash: bool = False
```

#### 5.2 ایجاد UI برای ارسال پیامک

**مکان‌های پیشنهادی**:

1. **صفحه جزئیات Person**:
   - دکمه "ارسال پیامک" در کنار شماره موبایل
   - Dialog برای نوشتن پیام

2. **صفحه لیست Persons**:
   - Action menu برای هر ردیف
   - امکان انتخاب چند Person و ارسال گروهی

3. **صفحه فاکتور (Invoice)**:
   - دکمه "ارسال پیامک به مشتری" پس از ثبت فاکتور
   - قالب پیش‌فرض پیامک (مثلاً "فاکتور شماره {invoice_number} به مبلغ {amount} ثبت شد")

#### 5.3 ایجاد Service Layer

**فایل جدید**: `hesabixAPI/app/services/person_sms_service.py`

```python
class PersonSmsService:
    def __init__(self, db: Session):
        self.db = db
        # دریافت تنظیمات SMS
        notify_cfg = get_effective_notifications_settings(db)
        self.sms_provider = SmsProvider(...)
    
    def send_to_person(self, person_id: int, message: str, 
                       is_flash: bool = False, 
                       business_id: int | None = None) -> dict:
        """
        ارسال پیامک به یک Person
        """
        # 1. دریافت Person
        # 2. بررسی شماره موبایل
        # 3. نرمال‌سازی
        # 4. ارسال
        # 5. ثبت در تاریخچه (اختیاری)
        pass
    
    def send_to_multiple(self, person_ids: list[int], message: str,
                         is_flash: bool = False) -> dict:
        """
        ارسال به چند Person (تا 1000)
        """
        pass
```

### Phase 6: ثبت تاریخچه و لاگ

#### 6.1 ایجاد مدل برای تاریخچه ارسال پیامک

**فایل جدید**: `hesabixAPI/adapters/db/models/person_sms_history.py`

```python
class PersonSmsHistory(Base):
    __tablename__ = "person_sms_history"
    
    id: Mapped[int]
    business_id: Mapped[int]
    person_id: Mapped[int]
    sent_by_user_id: Mapped[int]
    recipient_number: Mapped[str]
    message_text: Mapped[str]
    message_id: Mapped[str | None]  # از بهین اس ام اس
    status: Mapped[str]  # pending, sent, failed
    is_flash: Mapped[bool]
    error_message: Mapped[str | None]
    sent_at: Mapped[datetime]
    # ...
```

#### 6.2 ایجاد API برای مشاهده تاریخچه

```python
@router.get("/persons/{person_id}/sms-history")
def get_person_sms_history(...):
    """
    دریافت تاریخچه پیامک‌های ارسالی به یک Person
    """
    pass
```

### Phase 7: استفاده از SMS برای احراز هویت و تایید موبایل

این بخش استفاده از پیامک بهین اس ام اس برای موارد احراز هویت و امنیتی را پوشش می‌دهد.

#### 7.1 تایید شماره موبایل (Mobile Verification)

مشابه Email Verification، باید سیستم تایید شماره موبایل هم پیاده‌سازی شود.

##### 7.1.1 ایجاد مدل Mobile Verification

**فایل جدید**: `hesabixAPI/adapters/db/models/mobile_verification.py`

```python
class MobileVerificationToken(Base):
    __tablename__ = "mobile_verification_tokens"
    
    id: Mapped[int]
    user_id: Mapped[int]
    mobile: Mapped[str]  # شماره موبایل برای تایید
    otp_code: Mapped[str]  # کد 4 یا 6 رقمی
    otp_hash: Mapped[str]  # Hash شده برای امنیت
    expires_at: Mapped[datetime]
    verified_at: Mapped[datetime | None]
    attempts: Mapped[int]  # تعداد تلاش‌های ناموفق
    created_at: Mapped[datetime]
```

**مشابه**: `EmailVerificationToken` اما با OTP به جای token.

##### 7.1.2 افزودن فیلد mobile_verified به User

**Migration جدید**:
```python
# افزودن فیلد mobile_verified به جدول users
op.add_column('users', sa.Column('mobile_verified', sa.Boolean(), 
    nullable=False, server_default='0'))
```

##### 7.1.3 Service برای Mobile Verification

**فایل جدید**: `hesabixAPI/app/services/mobile_verification_service.py`

```python
class MobileVerificationService:
    def __init__(self, db: Session):
        self.db = db
        notify_cfg = get_effective_notifications_settings(db)
        self.sms_provider = SmsProvider(...)
    
    def generate_otp(self) -> str:
        """تولید کد OTP 6 رقمی"""
        import random
        return str(random.randint(100000, 999999))
    
    def create_mobile_verification(self, user_id: int, mobile: str) -> str:
        """
        ایجاد کد OTP و ارسال پیامک
        Returns: OTP code (فقط برای تست، در production نباید برگردانده شود)
        """
        # 1. بررسی Rate Limiting (مثلاً حداکثر 3 بار در ساعت)
        # 2. تولید OTP
        # 3. Hash کردن OTP
        # 4. ذخیره در دیتابیس
        # 5. نرمال‌سازی شماره موبایل
        # 6. ارسال پیامک
        # 7. بازگرداندن OTP (برای تست)
        pass
    
    def verify_mobile_otp(self, user_id: int, otp_code: str) -> bool:
        """
        تایید کد OTP
        """
        # 1. دریافت آخرین token فعال
        # 2. بررسی انقضا
        # 3. بررسی تعداد تلاش‌ها (حداکثر 5 تلاش)
        # 4. Hash و مقایسه OTP
        # 5. در صورت موفقیت: mark as verified و به‌روزرسانی mobile_verified
        pass
    
    def resend_otp(self, user_id: int) -> str:
        """
        ارسال مجدد OTP
        """
        # مشابه create_mobile_verification اما با بررسی Rate Limiting
        pass
```

##### 7.1.4 API Endpoints

**فایل**: `hesabixAPI/adapters/api/v1/auth.py`

```python
@router.post("/auth/send-mobile-verification")
def send_mobile_verification(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    ارسال کد تایید به شماره موبایل کاربر
    """
    # 1. دریافت شماره موبایل از user
    # 2. بررسی وجود شماره موبایل
    # 3. فراخوانی MobileVerificationService
    # 4. ارسال پیامک
    pass

@router.post("/auth/verify-mobile")
def verify_mobile(
    payload: VerifyMobilePayload,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    تایید شماره موبایل با کد OTP
    """
    pass

@router.post("/auth/resend-mobile-verification")
def resend_mobile_verification(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    ارسال مجدد کد تایید موبایل
    """
    pass
```

##### 7.1.5 به‌روزرسانی ثبت‌نام

**فایل**: `hesabixAPI/app/services/auth_service.py`

```python
def register_user(...):
    # ...
    # پس از ایجاد user
    if mobile_n and is_mobile_verification_enabled(db):
        # ایجاد mobile verification token
        # ارسال OTP به شماره موبایل
        # mobile_verified = False
    else:
        mobile_verified = True  # اگر verification غیرفعال باشد
    
    user = repo.create(
        # ...
        mobile_verified=mobile_verified
    )
```

##### 7.1.6 قالب پیامک OTP

```
کد تایید شما: {otp_code}
این کد تا {expires_minutes} دقیقه اعتبار دارد.
```

#### 7.2 بازیابی کلمه عبور از طریق SMS

در حال حاضر بازیابی کلمه عبور فقط از طریق ایمیل انجام می‌شود. باید از طریق SMS هم امکان‌پذیر باشد.

##### 7.2.1 به‌روزرسانی Password Reset Service

**فایل**: `hesabixAPI/app/services/auth_service.py`

```python
def create_password_reset(*, db: Session, identifier: str, ...):
    # ...
    # پس از ایجاد token
    # اگر identifier موبایل است:
    if mobile_n:
        # ارسال پیامک با لینک reset یا OTP
        send_password_reset_sms(db, user.id, mobile_n, token)
    else:
        # ارسال ایمیل (کد فعلی)
        send_password_reset_email(...)
```

##### 7.2.2 استفاده از OTP برای Reset Password

**گزینه 1: استفاده از لینک در پیامک**
```
برای بازیابی کلمه عبور روی لینک زیر کلیک کنید:
{reset_link}

یا از کد زیر استفاده کنید: {token}
```

**گزینه 2: استفاده از OTP (بهتر)**
- به جای token، یک OTP 6 رقمی ارسال شود
- کاربر OTP را وارد کند
- سپس کلمه عبور جدید را تنظیم کند

```python
def create_password_reset_with_otp(*, db: Session, identifier: str, ...):
    # ...
    if mobile_n:
        # تولید OTP
        otp = generate_otp()
        # ذخیره OTP hash
        # ارسال OTP به موبایل
        send_password_reset_otp_sms(mobile_n, otp)
    # ...
```

##### 7.2.3 API Endpoint جدید

```python
@router.post("/auth/password-reset/verify-otp")
def verify_password_reset_otp(
    payload: VerifyResetOtpPayload,
    db: Session = Depends(get_db),
):
    """
    تایید OTP بازیابی کلمه عبور
    پس از تایید، یک token برگردانده می‌شود که کاربر می‌تواند با آن رمز جدید تنظیم کند
    """
    pass
```

#### 7.3 ورود با OTP (Login with OTP)

امکان ورود به سیستم بدون نیاز به رمز عبور، فقط با دریافت OTP از طریق SMS.

##### 7.3.1 ایجاد Service

**فایل جدید**: `hesabixAPI/app/services/otp_login_service.py`

```python
class OtpLoginService:
    def __init__(self, db: Session):
        self.db = db
        # ...
    
    def send_login_otp(self, mobile: str) -> tuple[bool, str | None]:
        """
        ارسال OTP برای ورود
        Returns: (success, session_id)
        """
        # 1. نرمال‌سازی شماره موبایل
        # 2. بررسی وجود کاربر با این شماره
        # 3. Rate Limiting
        # 4. تولید OTP
        # 5. ایجاد session برای login
        # 6. ارسال OTP
        # 7. بازگرداندن session_id
        pass
    
    def verify_login_otp(self, session_id: str, otp_code: str) -> tuple[bool, User | None]:
        """
        تایید OTP و ورود کاربر
        Returns: (success, user)
        """
        # 1. بررسی session
        # 2. بررسی OTP
        # 3. بررسی انقضا
        # 4. ایجاد API Key (مانند login عادی)
        # 5. بازگرداندن user و api_key
        pass
```

##### 7.3.2 مدل برای Login Session

**فایل جدید**: `hesabixAPI/adapters/db/models/otp_login_session.py`

```python
class OtpLoginSession(Base):
    __tablename__ = "otp_login_sessions"
    
    id: Mapped[int]
    session_id: Mapped[str]  # شناسه منحصر به فرد session
    mobile: Mapped[str]
    user_id: Mapped[int | None]  # بعد از شناسایی کاربر
    otp_code_hash: Mapped[str]
    attempts: Mapped[int]
    expires_at: Mapped[datetime]
    verified_at: Mapped[datetime | None]
    ip_address: Mapped[str | None]
    user_agent: Mapped[str | None]
    created_at: Mapped[datetime]
```

##### 7.3.3 API Endpoints

```python
@router.post("/auth/login/send-otp")
def send_login_otp(
    payload: SendLoginOtpPayload,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    ارسال OTP برای ورود
    """
    pass

@router.post("/auth/login/verify-otp")
def verify_login_otp(
    payload: VerifyLoginOtpPayload,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    تایید OTP و ورود
    """
    pass
```

##### 7.3.4 قالب پیامک Login OTP

```
کد ورود شما: {otp_code}
این کد تا 5 دقیقه اعتبار دارد.
```

#### 7.4 احراز هویت دو مرحله‌ای (2FA)

افزودن 2FA برای امنیت بیشتر حساب کاربری.

##### 7.4.1 افزودن فیلد به User

**Migration**:
```python
# فعال/غیرفعال بودن 2FA
op.add_column('users', sa.Column('two_factor_enabled', sa.Boolean(), 
    nullable=False, server_default='0'))
# شماره موبایل برای 2FA (ممکن است با mobile اصلی متفاوت باشد)
op.add_column('users', sa.Column('two_factor_mobile', sa.String(32), nullable=True))
```

##### 7.4.2 Service برای 2FA

**فایل جدید**: `hesabixAPI/app/services/two_factor_service.py`

```python
class TwoFactorService:
    def enable_2fa(self, user_id: int, mobile: str) -> bool:
        """
        فعال‌سازی 2FA برای کاربر
        """
        # 1. تایید شماره موبایل
        # 2. فعال کردن 2FA
        # 3. ذخیره شماره موبایل 2FA
        pass
    
    def send_2fa_otp(self, user_id: int) -> bool:
        """
        ارسال OTP برای 2FA در هنگام ورود
        """
        # 1. دریافت شماره موبایل 2FA
        # 2. تولید OTP
        # 3. ارسال پیامک
        pass
    
    def verify_2fa_otp(self, user_id: int, otp_code: str) -> bool:
        """
        تایید OTP برای 2FA
        """
        pass
```

##### 7.4.3 به‌روزرسانی Login Flow

**فایل**: `hesabixAPI/app/services/auth_service.py`

```python
def login_user(...):
    # ...
    # پس از بررسی رمز عبور
    if user.two_factor_enabled:
        # ارسال OTP 2FA
        # برگرداندن session برای 2FA verification
        return {
            "requires_2fa": True,
            "session_id": "...",
            "message": "لطفاً کد تایید ارسالی به موبایل را وارد کنید"
        }
    else:
        # ورود عادی
        # ...
```

##### 7.4.4 API Endpoints

```python
@router.post("/auth/2fa/enable")
def enable_2fa(
    payload: Enable2FAPayload,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    فعال‌سازی 2FA
    """
    pass

@router.post("/auth/2fa/verify")
def verify_2fa(
    payload: Verify2FAPayload,
    db: Session = Depends(get_db),
):
    """
    تایید 2FA پس از ورود
    """
    pass
```

#### 7.5 تغییر شماره موبایل

امکان تغییر شماره موبایل کاربر با تایید OTP.

##### 7.5.1 Service

```python
def change_mobile(self, user_id: int, new_mobile: str) -> str:
    """
    تغییر شماره موبایل کاربر
    """
    # 1. نرمال‌سازی شماره جدید
    # 2. بررسی تکراری نبودن
    # 3. ارسال OTP به شماره جدید
    # 4. ذخیره در session موقت
    pass

def confirm_mobile_change(self, user_id: int, otp_code: str) -> bool:
    """
    تایید تغییر شماره موبایل با OTP
    """
    # 1. بررسی OTP
    # 2. به‌روزرسانی شماره موبایل
    # 3. غیرفعال کردن mobile_verified (باید دوباره تایید شود)
    pass
```

##### 7.5.2 API Endpoint

```python
@router.post("/auth/change-mobile")
def change_mobile(
    payload: ChangeMobilePayload,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    درخواست تغییر شماره موبایل
    """
    pass

@router.post("/auth/confirm-mobile-change")
def confirm_mobile_change(
    payload: ConfirmMobileChangePayload,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    تایید تغییر شماره موبایل با OTP
    """
    pass
```

#### 7.6 Rate Limiting و امنیت

##### 7.6.1 Rate Limiting برای OTP

- **ارسال OTP**: حداکثر 3 بار در ساعت برای هر شماره موبایل
- **تایید OTP**: حداکثر 5 تلاش ناموفق قبل از بلاک شدن
- **بازیابی رمز**: حداکثر 3 بار در 24 ساعت

##### 7.6.2 ذخیره‌سازی OTP

- OTP باید به صورت **Hash** ذخیره شود (نه Plain Text)
- استفاده از `hashlib` یا `bcrypt` برای hash کردن

```python
def hash_otp(otp: str) -> str:
    settings = get_settings()
    return hashlib.sha256(f"{settings.captcha_secret}:{otp}".encode()).hexdigest()
```

##### 7.6.3 زمان انقضای OTP

- **Mobile Verification OTP**: 10 دقیقه
- **Password Reset OTP**: 15 دقیقه
- **Login OTP**: 5 دقیقه
- **2FA OTP**: 5 دقیقه

#### 7.7 قالب‌های پیامک

##### قالب‌های پیشنهادی:

1. **Mobile Verification**:
```
کد تایید شماره موبایل شما: {otp_code}
اعتبار: {expires_minutes} دقیقه
```

2. **Password Reset**:
```
کد بازیابی کلمه عبور: {otp_code}
این کد تا {expires_minutes} دقیقه اعتبار دارد.
```

3. **Login OTP**:
```
کد ورود شما: {otp_code}
اعتبار: {expires_minutes} دقیقه
```

4. **2FA**:
```
کد تایید دو مرحله‌ای: {otp_code}
اعتبار: {expires_minutes} دقیقه
```

#### 7.8 فایل‌های مورد نیاز

### Backend:

1. ✅ `adapters/db/models/mobile_verification.py` - **جدید**
2. ✅ `adapters/db/models/otp_login_session.py` - **جدید**
3. ✅ `adapters/db/repositories/mobile_verification_repo.py` - **جدید**
4. ✅ `adapters/db/repositories/otp_login_repo.py` - **جدید**
5. ✅ `app/services/mobile_verification_service.py` - **جدید**
6. ✅ `app/services/otp_login_service.py` - **جدید**
7. ✅ `app/services/two_factor_service.py` - **جدید**
8. ✅ `adapters/api/v1/auth.py` - به‌روزرسانی (افزودن Endpointهای جدید)
9. ✅ `app/services/auth_service.py` - به‌روزرسانی (پشتیبانی از SMS)
10. ✅ Migration برای افزودن فیلدهای جدید

### Frontend:

1. ✅ صفحه تایید موبایل (Mobile Verification Page)
2. ✅ Dialog برای وارد کردن OTP
3. ✅ صفحه تنظیمات امنیتی (Security Settings)
4. ✅ فعال/غیرفعال کردن 2FA
5. ✅ صفحه ورود با OTP
6. ✅ صفحه تغییر شماره موبایل

### Phase 8: ویژگی‌های پیشرفته (آینده)

#### 8.1 دریافت وضعیت پیامک (Delivery Status)

با استفاده از `GetMessageStatus` می‌توان وضعیت پیامک‌ها را بررسی کرد.

**پیشنهاد**: یک Background Job برای به‌روزرسانی وضعیت پیامک‌های pending

#### 7.2 دریافت پیامک‌های ورودی (Inbox)

با استفاده از `GetInboxMessage` یا `TrafficRelay` می‌توان پیامک‌های دریافتی را دریافت کرد.

**نیاز به**:
- API Endpoint برای دریافت webhook از بهین اس ام اس
- ذخیره پیامک‌های دریافتی در دیتابیس
- نمایش در UI

#### 7.3 قالب‌های پیامک (Templates)

ایجاد سیستم قالب برای پیامک‌های رایج:
- "فاکتور شماره {number} به مبلغ {amount} ثبت شد"
- "واریز مبلغ {amount} انجام شد"
- "یادآوری بدهی: مبلغ {balance} تومان"

## جریان کار (Workflow)

### 1. تنظیم اولیه توسط مدیر سیستم

1. مدیر وارد صفحه تنظیمات سیستم می‌شود
2. در بخش Notifications > Advanced
3. SMS Provider را "behinsms" انتخاب می‌کند
4. UserName و Password بهین اس ام اس را وارد می‌کند
5. شماره اختصاصی (Sender) را وارد می‌کند
6. تنظیمات را ذخیره می‌کند

### 2. ارسال پیامک از طریق سیستم ناتیفیکیشن

1. سیستم می‌خواهد ناتیفیکیشن ارسال کند
2. `NotificationService.send()` فراخوانی می‌شود
3. اگر SMS در لیست کانال‌ها باشد
4. `SmsProvider.send_text()` فراخوانی می‌شود
5. `BehinSmsProvider` پیامک را از طریق API بهین اس ام اس ارسال می‌کند

### 3. ارسال پیامک به مشتری توسط کاربر

1. کاربر وارد صفحه جزئیات مشتری می‌شود
2. روی دکمه "ارسال پیامک" کلیک می‌کند
3. Dialog باز می‌شود برای نوشتن پیام
4. پیام را می‌نویسد و ارسال می‌کند
5. Backend:
   - شماره موبایل را دریافت می‌کند
   - نرمال‌سازی می‌کند
   - از طریق `PersonSmsService` ارسال می‌کند
   - در تاریخچه ثبت می‌کند
6. نتیجه (موفقیت/خطا) به کاربر نمایش داده می‌شود

### 4. تایید شماره موبایل در ثبت‌نام

1. کاربر با شماره موبایل ثبت‌نام می‌کند
2. پس از ثبت‌نام، یک کد OTP به شماره موبایل ارسال می‌شود
3. کاربر کد را دریافت می‌کند
4. در صفحه تایید موبایل، کد را وارد می‌کند
5. Backend:
   - کد را بررسی می‌کند
   - در صورت صحیح بودن، `mobile_verified` را به `True` تنظیم می‌کند
6. کاربر می‌تواند به حساب کاربری دسترسی کامل داشته باشد

### 5. بازیابی کلمه عبور از طریق SMS

1. کاربر روی "فراموشی کلمه عبور" کلیک می‌کند
2. شماره موبایل یا ایمیل خود را وارد می‌کند
3. اگر شماره موبایل وارد شده:
   - یک کد OTP 6 رقمی به موبایل ارسال می‌شود
   - کاربر کد را وارد می‌کند
   - پس از تایید، می‌تواند کلمه عبور جدید تنظیم کند
4. اگر ایمیل وارد شده:
   - لینک بازیابی به ایمیل ارسال می‌شود (مشابه قبل)

### 6. ورود با OTP

1. کاربر در صفحه ورود، گزینه "ورود با کد یکبار مصرف" را انتخاب می‌کند
2. شماره موبایل خود را وارد می‌کند
3. یک کد OTP به موبایل ارسال می‌شود
4. کاربر کد را وارد می‌کند
5. Backend:
   - کد را بررسی می‌کند
   - در صورت صحیح بودن، یک API Key برای کاربر ایجاد می‌کند
   - کاربر وارد سیستم می‌شود

### 7. احراز هویت دو مرحله‌ای (2FA)

1. کاربر در تنظیمات امنیتی، 2FA را فعال می‌کند
2. شماره موبایل برای دریافت کدهای 2FA را وارد می‌کند
3. یک کد تایید به موبایل ارسال می‌شود
4. پس از تایید، 2FA فعال می‌شود
5. در ورود‌های بعدی:
   - کاربر رمز عبور را وارد می‌کند
   - یک کد 2FA به موبایل ارسال می‌شود
   - کاربر کد را وارد می‌کند
   - سپس وارد سیستم می‌شود

## نکات مهم امنیتی

1. **رمز عبور**: باید در دیتابیس به صورت encrypted ذخیره شود
2. **API Key**: در UI با `obscureText` نمایش داده شود
3. **Rate Limiting**: برای جلوگیری از سوء استفاده، محدودیت تعداد ارسال در روز
4. **IP Whitelist**: در تنظیمات بهین اس ام اس، IP سرور باید اضافه شود
5. **لاگ‌گذاری**: تمام ارسال‌های پیامک باید لاگ شوند (بدون ذخیره متن کامل در صورت حساس بودن)

## تست و اعتبارسنجی

### مراحل تست:

1. **تست تنظیمات**: اتصال به API بهین اس ام اس با تنظیمات وارد شده
2. **تست GetCredit**: دریافت اعتبار برای اطمینان از اتصال
3. **تست SendArray**: ارسال یک پیامک تست
4. **تست GetMessageStatus**: بررسی وضعیت پیامک ارسالی
5. **تست فرمت شماره**: نرمال‌سازی شماره‌های مختلف
6. **تست خطاها**: بررسی رفتار سیستم در صورت خطا

## مستندات مورد نیاز

1. **مستند API**: توضیح Endpointهای جدید
2. **مستند کاربری**: راهنمای استفاده برای مدیر سیستم
3. **مستند توسعه‌دهنده**: نحوه اضافه کردن Provider جدید

## نکات پیاده‌سازی

### استفاده از HTTP Client

برای فراخوانی API بهین اس ام اس، می‌توان از `requests` یا `httpx` استفاده کرد:

```python
import httpx

async def send_array(...):
    async with httpx.AsyncClient() as client:
        params = {
            "service": "SendArray",
            "username": self.username,
            "password": self.password,
            "to": recipient_numbers_str,  # comma-separated
            "message": text,
            "from": self.sender,
            "IsFlashMessage": "true" if is_flash else "false",
        }
        if checking_message_id:
            params["chkMessageId"] = checking_message_id
        
        response = await client.get(self.BASE_URL, params=params)
        # Parse response
```

### مدیریت خطاها

```python
def parse_response(response_text: str) -> tuple[bool, str | None, str | None]:
    """
    Parse response from Behin SMS API
    Returns: (is_success, message_id_or_code, error_message)
    """
    try:
        # اگر عدد است
        result = int(response_text.strip())
        if result < 50:
            # کد خطا
            error_msg = BEHINSMS_ERROR_CODES.get(result, "خطای نامشخص")
            return False, str(result), error_msg
        elif result >= 1000:
            # MessageID موفق
            return True, str(result), None
        else:
            # وضعیت نامشخص
            return False, str(result), "وضعیت نامشخص"
    except ValueError:
        # ممکن است چند MessageID با کاما جدا شده باشد
        parts = response_text.split(",")
        if all(part.strip().isdigit() for part in parts):
            # همه MessageID هستند
            return True, response_text, None
        else:
            return False, None, "فرمت پاسخ نامعتبر"
```

## خلاصه تغییرات فایل‌ها

### Backend (Python):

**Provider و تنظیمات:**
1. ✅ `app/services/providers/sms_provider.py` - به‌روزرسانی
2. ✅ `app/services/providers/behin_sms_provider.py` - **جدید**
3. ✅ `app/services/system_settings_service.py` - اضافه کردن فیلدها
4. ✅ `adapters/api/v1/admin/system_settings.py` - به‌روزرسانی Payload

**ارسال پیامک به مشتریان:**
5. ✅ `adapters/api/v1/business/persons.py` - اضافه کردن Endpoint ارسال پیامک
6. ✅ `app/services/person_sms_service.py` - **جدید**
7. ✅ `adapters/db/models/person_sms_history.py` - **جدید**

**احراز هویت و تایید موبایل:**
8. ✅ `adapters/db/models/mobile_verification.py` - **جدید**
9. ✅ `adapters/db/models/otp_login_session.py` - **جدید**
10. ✅ `adapters/db/repositories/mobile_verification_repo.py` - **جدید**
11. ✅ `adapters/db/repositories/otp_login_repo.py` - **جدید**
12. ✅ `app/services/mobile_verification_service.py` - **جدید**
13. ✅ `app/services/otp_login_service.py` - **جدید**
14. ✅ `app/services/two_factor_service.py` - **جدید**
15. ✅ `app/services/auth_service.py` - به‌روزرسانی (پشتیبانی از SMS)

**API Endpoints:**
16. ✅ `adapters/api/v1/auth.py` - افزودن Endpointهای احراز هویت

**Migrations:**
17. ✅ Migration برای افزودن `mobile_verified` به User
18. ✅ Migration برای افزودن `two_factor_enabled` و `two_factor_mobile` به User
19. ✅ Migration برای ایجاد جداول mobile_verification_tokens و otp_login_sessions
20. ✅ Migration برای ایجاد جدول person_sms_history

### Frontend (Flutter):

**تنظیمات:**
1. ✅ `lib/pages/profile/notifications_settings_page.dart` - اضافه کردن فیلدها
2. ✅ `lib/pages/profile/security_settings_page.dart` - **جدید** (تنظیمات امنیتی، 2FA)

**ارسال پیامک به مشتریان:**
3. ✅ `lib/pages/business/person_detail_page.dart` - اضافه کردن دکمه ارسال پیامک
4. ✅ `lib/pages/business/persons_list_page.dart` - اضافه کردن action menu
5. ✅ `lib/services/person_sms_service.dart` - **جدید** (Service برای فراخوانی API)
6. ✅ `lib/widgets/sms/send_sms_dialog.dart` - **جدید** (Dialog برای ارسال پیامک)

**احراز هویت و تایید موبایل:**
7. ✅ `lib/pages/auth/mobile_verification_page.dart` - **جدید** (تایید شماره موبایل)
8. ✅ `lib/pages/auth/otp_login_page.dart` - **جدید** (ورود با OTP)
9. ✅ `lib/pages/auth/verify_otp_page.dart` - **جدید** (صفحه عمومی برای تایید OTP)
10. ✅ `lib/widgets/auth/otp_input_dialog.dart` - **جدید** (Dialog برای وارد کردن OTP)
11. ✅ `lib/services/mobile_verification_service.dart` - **جدید**
12. ✅ `lib/services/otp_login_service.dart` - **جدید**
13. ✅ `lib/services/two_factor_service.dart` - **جدید**

## اولویت‌بندی پیاده‌سازی

### اولویت بالا (MVP):
1. Phase 1: تکمیل تنظیمات سیستم
2. Phase 2: پیاده‌سازی Behin SMS Provider
3. Phase 3: فرمت‌سازی شماره تلفن
4. Phase 4: مدیریت خطاها
5. Phase 7.1: تایید شماره موبایل (Mobile Verification)
6. Phase 7.2: بازیابی کلمه عبور از طریق SMS

### اولویت متوسط:
1. Phase 5.1 و 5.3: API و Service برای ارسال به Person
2. Phase 5.2: UI برای ارسال پیامک
3. Phase 6: ثبت تاریخچه
4. Phase 7.3: ورود با OTP (Login with OTP)

### اولویت پایین (Future):
1. Phase 7.4: احراز هویت دو مرحله‌ای (2FA)
2. Phase 7.5: تغییر شماره موبایل
3. Phase 8: ویژگی‌های پیشرفته (Delivery Status, Inbox, Templates)

---

**نویسنده**: AI Assistant  
**تاریخ**: 2024  
**وضعیت**: Draft - آماده برای بررسی و پیاده‌سازی

