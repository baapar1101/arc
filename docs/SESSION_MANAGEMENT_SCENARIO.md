# سناریو مدیریت سشن‌های ورود در تنظیمات حساب کاربری

## بررسی وضعیت فعلی

### ساختار دیتابیس
- جدول `api_keys` با فیلدهای زیر برای session keys:
  - `id`: شناسه یکتا
  - `user_id`: شناسه کاربر
  - `key_type`: نوع کلید ("session" یا "personal")
  - `device_id`: شناسه دستگاه (اختیاری)
  - `user_agent`: User Agent مرورگر/اپلیکیشن (اختیاری)
  - `ip`: آدرس IP آخرین استفاده (اختیاری)
  - `last_used_at`: تاریخ و زمان آخرین استفاده
  - `created_at`: تاریخ و زمان ایجاد
  - `revoked_at`: تاریخ و زمان لغو (NULL = فعال)

### وضعیت فعلی
- ✅ Session keys در زمان ورود ایجاد می‌شوند (login_user و verify_login_otp)
- ✅ اطلاعات device_id، user_agent و ip در زمان ورود ذخیره می‌شوند
- ✅ last_used_at در هر درخواست API به‌روزرسانی می‌شود (هر 60 ثانیه)
- ❌ هیچ endpoint برای لیست کردن session keys وجود ندارد
- ❌ هیچ endpoint برای حذف session keys وجود ندارد
- ❌ صفحه تنظیمات حساب کاربری کارتی برای مدیریت sessions ندارد
- ❌ هیچ utility برای تشخیص نام دستگاه از user_agent وجود ندارد

---

## سناریو پیشنهادی

### 1. Backend - API Endpoints

#### 1.1. لیست سشن‌های ورود
**Endpoint:** `GET /api/v1/auth/sessions`

**توضیحات:**
- دریافت لیست تمام session keys فعال کاربر (key_type="session" و revoked_at=NULL)
- مرتب‌سازی بر اساس last_used_at (جدیدترین اول)
- نمایش اطلاعات کامل هر session

**Response Schema:**
```json
{
  "success": true,
  "data": [
    {
      "id": 123,
      "device_name": "Chrome on Windows",
      "device_id": "device-uuid-123",
      "user_agent": "Mozilla/5.0...",
      "ip": "192.168.1.100",
      "location": "تهران، ایران",  // اختیاری - از IP geolocation
      "is_current": true,  // آیا این session فعلی است؟
      "created_at": "2024-01-15T10:30:00Z",
      "last_used_at": "2024-01-20T14:25:00Z",
      "last_used_relative": "2 ساعت پیش"  // فرمت نسبی برای نمایش
    }
  ]
}
```

**ویژگی‌ها:**
- تشخیص نام دستگاه از user_agent (مثلاً "Chrome on Windows", "Safari on iPhone", "Flutter App")
- تشخیص اینکه آیا session فعلی است (مقایسه key_hash با API key فعلی)
- فرمت نسبی تاریخ (مثلاً "2 ساعت پیش"، "3 روز پیش")
- امکان افزودن geolocation از IP (اختیاری - نیاز به سرویس خارجی)

#### 1.2. حذف سشن
**Endpoint:** `DELETE /api/v1/auth/sessions/{session_id}`

**توضیحات:**
- حذف (revoke) یک session خاص
- کاربر نمی‌تواند session فعلی خود را حذف کند (برای جلوگیری از logout ناخواسته)
- اگر session فعلی حذف شود، باید خطا برگرداند

**Response Schema:**
```json
{
  "success": true,
  "message": "سشن با موفقیت حذف شد",
  "data": {
    "ok": true
  }
}
```

**خطاها:**
- 404: Session یافت نشد
- 400: نمی‌توانید session فعلی را حذف کنید
- 403: Session متعلق به کاربر دیگری است

#### 1.3. حذف همه سشن‌های دیگر
**Endpoint:** `DELETE /api/v1/auth/sessions/others`

**توضیحات:**
- حذف تمام session های کاربر به جز session فعلی
- مفید برای logout از همه دستگاه‌ها

**Response Schema:**
```json
{
  "success": true,
  "message": "تمام سشن‌های دیگر حذف شدند",
  "data": {
    "deleted_count": 5
  }
}
```

---

### 2. Backend - Service Layer

#### 2.1. Session Service
**فایل:** `hesabixAPI/app/services/session_service.py`

**توابع:**
```python
def list_user_sessions(db: Session, user_id: int, current_api_key_hash: str) -> list[dict]:
    """
    لیست تمام session keys کاربر
    
    Args:
        db: Session دیتابیس
        user_id: شناسه کاربر
        current_api_key_hash: hash کلید API فعلی برای تشخیص session فعلی
    
    Returns:
        لیست session ها با اطلاعات کامل
    """
    pass

def revoke_session(db: Session, user_id: int, session_id: int, current_api_key_hash: str) -> None:
    """
    حذف یک session
    
    Args:
        db: Session دیتابیس
        user_id: شناسه کاربر
        session_id: شناسه session
        current_api_key_hash: hash کلید API فعلی
    
    Raises:
        ApiError: اگر session فعلی باشد یا یافت نشود
    """
    pass

def revoke_other_sessions(db: Session, user_id: int, current_api_key_hash: str) -> int:
    """
    حذف تمام session های دیگر (به جز فعلی)
    
    Returns:
        تعداد session های حذف شده
    """
    pass
```

#### 2.2. Device Detection Utility
**فایل:** `hesabixAPI/app/utils/device_detection.py`

**توابع:**
```python
def parse_user_agent(user_agent: str | None) -> dict:
    """
    تجزیه user agent و استخراج اطلاعات دستگاه
    
    Returns:
        {
            "device_name": "Chrome on Windows",
            "browser": "Chrome",
            "browser_version": "120.0",
            "os": "Windows",
            "os_version": "10",
            "device_type": "desktop"  # desktop, mobile, tablet
        }
    """
    pass

def format_device_name(user_agent: str | None, device_id: str | None) -> str:
    """
    تولید نام خوانا برای دستگاه
    
    مثال:
        - "Chrome on Windows"
        - "Safari on iPhone 13"
        - "Flutter App (Android)"
        - "دستگاه نامشخص" (اگر اطلاعات کافی نباشد)
    """
    pass
```

**نکته:** می‌توان از کتابخانه‌های Python مثل `user-agents` استفاده کرد.

#### 2.3. Repository Extension
**فایل:** `hesabixAPI/adapters/db/repositories/api_key_repo.py`

**متدهای جدید:**
```python
def get_user_sessions(self, user_id: int) -> list[ApiKey]:
    """دریافت تمام session keys فعال کاربر"""
    pass

def revoke_session(self, session_id: int, user_id: int) -> bool:
    """حذف یک session"""
    pass

def revoke_other_sessions(self, user_id: int, exclude_key_hash: str) -> int:
    """حذف تمام session های دیگر"""
    pass
```

---

### 3. Frontend - UI Components

#### 3.1. صفحه مدیریت سشن‌ها
**فایل:** `hesabixUI/hesabix_ui/lib/pages/profile/sessions_page.dart`

**ویژگی‌ها:**
- لیست تمام session های فعال
- نمایش اطلاعات هر session:
  - نام دستگاه (با آیکون)
  - آخرین استفاده (فرمت نسبی)
  - آخرین IP
  - تاریخ ایجاد
  - نشانگر "این دستگاه" برای session فعلی
- دکمه حذف برای هر session (غیرفعال برای session فعلی)
- دکمه "خروج از همه دستگاه‌ها" (حذف همه به جز فعلی)
- Pull-to-refresh
- Empty state (اگر session ای وجود نداشته باشد)

**Layout:**
```
┌─────────────────────────────────────┐
│  مدیریت سشن‌های ورود                │
├─────────────────────────────────────┤
│  🔒 Chrome on Windows               │
│  این دستگاه                         │
│  آخرین استفاده: 2 ساعت پیش         │
│  IP: 192.168.1.100                  │
│  ایجاد شده: 15 دی 1402              │
│                          [حذف ❌]   │
├─────────────────────────────────────┤
│  📱 Safari on iPhone                │
│  آخرین استفاده: 3 روز پیش           │
│  IP: 185.123.45.67                  │
│  ایجاد شده: 10 دی 1402              │
│                          [حذف ❌]   │
├─────────────────────────────────────┤
│  💻 Flutter App (Android)           │
│  آخرین استفاده: 1 هفته پیش         │
│  IP: 192.168.1.50                   │
│  ایجاد شده: 5 دی 1402               │
│                          [حذف ❌]   │
├─────────────────────────────────────┤
│  [خروج از همه دستگاه‌ها]           │
└─────────────────────────────────────┘
```

#### 3.2. کارت در صفحه تنظیمات
**فایل:** `hesabixUI/hesabix_ui/lib/pages/profile/account_settings_page.dart`

**تغییرات:**
- افزودن کارت جدید برای "سشن‌های ورود" یا "دستگاه‌های متصل"
- آیکون: `Icons.devices` یا `Icons.security`
- رنگ: `Colors.indigo` یا `Colors.cyan`
- مسیر: `/user/profile/sessions`

**کد:**
```dart
_SettingsCard(
  title: 'سشن‌های ورود',
  description: 'مشاهده و مدیریت دستگاه‌های متصل به حساب کاربری',
  icon: Icons.devices,
  color: Colors.indigo,
  onTap: () => context.go('/user/profile/sessions'),
),
```

#### 3.3. Service Layer
**فایل:** `hesabixUI/hesabix_ui/lib/services/session_service.dart`

**کلاس:**
```dart
class SessionService {
  final ApiClient _api;
  
  Future<List<SessionInfo>> listSessions();
  Future<void> revokeSession(int sessionId);
  Future<int> revokeOtherSessions();
}

class SessionInfo {
  final int id;
  final String deviceName;
  final String? deviceId;
  final String? userAgent;
  final String? ip;
  final bool isCurrent;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final String lastUsedRelative;  // "2 ساعت پیش"
}
```

---

### 4. Route Configuration

#### 4.1. Backend Route
**فایل:** `hesabixAPI/adapters/api/v1/auth.py`

**افزودن routes:**
```python
@router.get("/sessions", ...)
def list_sessions(...):
    pass

@router.delete("/sessions/{session_id}", ...)
def revoke_session(...):
    pass

@router.delete("/sessions/others", ...)
def revoke_other_sessions(...):
    pass
```

#### 4.2. Frontend Route
**فایل:** `hesabixUI/hesabix_ui/lib/main.dart`

**افزودن route:**
```dart
GoRoute(
  path: '/user/profile/sessions',
  name: 'profile_sessions',
  builder: (context, state) => SessionsPage(
    authStore: _authStore!,
  ),
),
```

---

### 5. امنیت و محدودیت‌ها

#### 5.1. محدودیت‌های امنیتی
- ✅ کاربر فقط می‌تواند session های خود را ببیند
- ✅ کاربر نمی‌تواند session فعلی را حذف کند
- ✅ حذف session باید با تأیید انجام شود (confirmation dialog)
- ✅ حذف همه session ها باید با تأیید قوی انجام شود

#### 5.2. Rate Limiting
- لیست sessions: بدون محدودیت (فقط احراز هویت)
- حذف session: حداکثر 10 بار در دقیقه

#### 5.3. Logging
- تمام عملیات حذف session باید در activity log ثبت شود
- لاگ شامل: user_id, session_id, ip, user_agent

---

### 6. بهبودهای آینده (اختیاری)

#### 6.1. Geolocation
- استفاده از سرویس IP geolocation برای نمایش موقعیت جغرافیایی
- نمایش شهر و کشور برای هر IP

#### 6.2. اعلان‌ها
- ارسال اعلان (email/SMS) هنگام ورود از دستگاه جدید
- ارسال اعلان هنگام حذف session از دستگاه دیگر

#### 6.3. محدودیت تعداد Sessions
- محدود کردن تعداد session های همزمان (مثلاً 5 session)
- حذف خودکار قدیمی‌ترین session هنگام ایجاد session جدید

#### 6.4. نام‌گذاری Sessions
- امکان نام‌گذاری دستی session ها توسط کاربر
- ذخیره نام در فیلد `name` جدول api_keys

---

### 7. مراحل پیاده‌سازی

#### مرحله 1: Backend Core
1. ✅ ایجاد `device_detection.py` utility
2. ✅ افزودن متدهای repository
3. ✅ ایجاد `session_service.py`
4. ✅ افزودن API endpoints

#### مرحله 2: Backend Testing
1. ✅ تست unit برای device detection
2. ✅ تست integration برای API endpoints
3. ✅ تست امنیت (دسترسی غیرمجاز)

#### مرحله 3: Frontend Core
1. ✅ ایجاد `session_service.dart`
2. ✅ ایجاد `sessions_page.dart`
3. ✅ افزودن route
4. ✅ افزودن کارت در تنظیمات

#### مرحله 4: Frontend Testing
1. ✅ تست UI/UX
2. ✅ تست responsive design
3. ✅ تست error handling

#### مرحله 5: Integration & Polish
1. ✅ تست end-to-end
2. ✅ بهبود UI/UX
3. ✅ افزودن loading states
4. ✅ افزودن error messages

---

## خلاصه

این سناریو شامل:
- ✅ لیست کامل session های ورود
- ✅ نمایش اطلاعات دستگاه (نام، IP، آخرین استفاده)
- ✅ قابلیت حذف session های فردی
- ✅ قابلیت حذف همه session های دیگر
- ✅ تشخیص هوشمند نام دستگاه از user_agent
- ✅ UI/UX مناسب در صفحه تنظیمات
- ✅ امنیت و محدودیت‌های مناسب

**نکته مهم:** این سناریو فقط برای بررسی و برنامه‌ریزی است. هیچ تغییری در کد ایجاد نشده است.

