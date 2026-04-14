# سناریو کنترل دسترسی ایجاد کسب و کار بر اساس تایید ایمیل/موبایل

## مقدمه

این سند سناریوی کامل پیاده‌سازی کنترل دسترسی ایجاد کسب و کار را شرح می‌دهد که مدیر سیستم می‌تواند تعیین کند چه کاربرانی می‌توانند کسب و کار ایجاد کنند بر اساس وضعیت تایید ایمیل و شماره موبایل.

---

## 1. گزینه‌های کنترل دسترسی

مدیر سیستم می‌تواند یکی از گزینه‌های زیر را انتخاب کند:

### گزینه‌های موجود:
1. **بدون محدودیت** (`none`):
   - هیچ محدودیتی وجود ندارد
   - همه کاربران می‌توانند کسب و کار ایجاد کنند
   - پیش‌فرض سیستم

2. **فقط ایمیل تایید شده** (`email_only`):
   - کاربر باید ایمیل تایید شده داشته باشد
   - شماره موبایل تایید شده یا نشده مهم نیست

3. **فقط شماره موبایل تایید شده** (`mobile_only`):
   - کاربر باید شماره موبایل تایید شده داشته باشد
   - ایمیل تایید شده یا نشده مهم نیست

4. **هر دو (ایمیل و موبایل تایید شده)** (`both`):
   - کاربر باید هم ایمیل و هم شماره موبایل تایید شده داشته باشد
   - هر دو باید تایید شده باشند

5. **هر کدام (ایمیل یا موبایل تایید شده)** (`either`):
   - کاربر باید حداقل یکی از دو مورد را تایید کرده باشد
   - یا ایمیل تایید شده باشد یا شماره موبایل (یا هر دو)

---

## 2. تغییرات Backend

### 2.1. افزودن تنظیم جدید در System Settings

**کلید جدید:**
```python
SYSTEM_CONFIG_BUSINESS_CREATION_VERIFICATION_REQUIREMENT = "system_config_business_creation_verification_requirement"
```

**مقادیر ممکن:**
- `"none"`: بدون محدودیت
- `"email_only"`: فقط ایمیل تایید شده
- `"mobile_only"`: فقط شماره موبایل تایید شده
- `"both"`: هر دو (ایمیل و موبایل)
- `"either"`: هر کدام (ایمیل یا موبایل)

**مقدار پیش‌فرض:** `"none"`

### 2.2. تابع بررسی دسترسی

**تابع جدید در `business_service.py`:**
```python
def check_business_creation_permission(db: Session, user_id: int) -> tuple[bool, str | None]:
    """
    بررسی اینکه آیا کاربر می‌تواند کسب و کار ایجاد کند یا نه
    
    Args:
        db: Database session
        user_id: شناسه کاربر
        
    Returns:
        Tuple[bool, str | None]:
        - (True, None): اجازه ایجاد دارد
        - (False, "پیام خطا"): اجازه ایجاد ندارد
    """
    from app.services.system_settings_service import get_business_creation_verification_requirement
    from adapters.db.models.user import User
    
    requirement = get_business_creation_verification_requirement(db)
    
    # بدون محدودیت
    if requirement == "none":
        return True, None
    
    # دریافت اطلاعات کاربر
    user = db.get(User, user_id)
    if not user:
        return False, "کاربر یافت نشد"
    
    email_verified = getattr(user, "email_verified", False)
    mobile_verified = getattr(user, "mobile_verified", False)
    
    # بررسی بر اساس requirement
    if requirement == "email_only":
        if not email_verified:
            return False, "برای ایجاد کسب و کار، شما باید ایمیل خود را تایید کنید"
        return True, None
    
    elif requirement == "mobile_only":
        if not mobile_verified:
            return False, "برای ایجاد کسب و کار، شما باید شماره موبایل خود را تایید کنید"
        return True, None
    
    elif requirement == "both":
        if not email_verified or not mobile_verified:
            missing = []
            if not email_verified:
                missing.append("ایمیل")
            if not mobile_verified:
                missing.append("شماره موبایل")
            return False, f"برای ایجاد کسب و کار، شما باید {' و '.join(missing)} خود را تایید کنید"
        return True, None
    
    elif requirement == "either":
        if not email_verified and not mobile_verified:
            return False, "برای ایجاد کسب و کار، شما باید حداقل ایمیل یا شماره موبایل خود را تایید کنید"
        return True, None
    
    # حالت پیش‌فرض: بدون محدودیت
    return True, None
```

### 2.3. اضافه کردن به `business_service.py`

**تغییر در `create_business()`:**
```python
def create_business(db: Session, business_data: BusinessCreateRequest, owner_id: int) -> Dict[str, Any]:
    """ایجاد کسب و کار جدید"""
    from app.core.responses import ApiError
    
    # بررسی دسترسی ایجاد کسب و کار
    can_create, error_message = check_business_creation_permission(db, owner_id)
    if not can_create:
        raise ApiError(
            "BUSINESS_CREATION_NOT_ALLOWED",
            error_message or "شما اجازه ایجاد کسب و کار را ندارید",
            http_status=403
        )
    
    # ادامه کد موجود...
```

### 2.4. افزودن به `system_settings_service.py`

**تابع جدید:**
```python
def get_business_creation_verification_requirement(db: Session) -> str:
    """
    دریافت تنظیمات کنترل دسترسی ایجاد کسب و کار
    
    Returns:
        str: یکی از مقادیر: "none", "email_only", "mobile_only", "both", "either"
        پیش‌فرض: "none"
    """
    requirement = _get_setting(db, SYSTEM_CONFIG_BUSINESS_CREATION_VERIFICATION_REQUIREMENT)
    if requirement and requirement.value_string:
        valid_values = ["none", "email_only", "mobile_only", "both", "either"]
        if requirement.value_string in valid_values:
            return requirement.value_string
    return "none"  # پیش‌فرض


def set_business_creation_verification_requirement(db: Session, requirement: str) -> None:
    """
    تنظیم کنترل دسترسی ایجاد کسب و کار
    
    Args:
        db: Database session
        requirement: یکی از مقادیر: "none", "email_only", "mobile_only", "both", "either"
    """
    valid_values = ["none", "email_only", "mobile_only", "both", "either"]
    if requirement not in valid_values:
        raise ValueError(f"Invalid requirement value. Must be one of: {valid_values}")
    
    _upsert_setting_string(db, SYSTEM_CONFIG_BUSINESS_CREATION_VERIFICATION_REQUIREMENT, requirement)
    cache = get_cache()
    cache.delete("system:business_creation_verification_requirement")
```

### 2.5. اضافه کردن به `get_system_configuration()` و `set_system_configuration()`

**در `get_system_configuration()`:**
```python
business_creation_requirement = get_business_creation_verification_requirement(db)

return {
    # ... سایر فیلدها
    "business_creation_verification_requirement": business_creation_requirement,
}
```

**در `set_system_configuration()`:**
```python
if business_creation_verification_requirement is not None:
    set_business_creation_verification_requirement(db, business_creation_verification_requirement)
```

### 2.6. به‌روزرسانی Schema در API

**در `SystemConfigurationPayload`:**
```python
business_creation_verification_requirement: Optional[str] = Field(
    default=None,
    description="کنترل دسترسی ایجاد کسب و کار: none, email_only, mobile_only, both, either"
)
```

---

## 3. تغییرات Frontend

### 3.1. به‌روزرسانی صفحه تنظیمات سیستم

**افزودن فیلد جدید در `system_configuration_page.dart`:**

```dart
String _businessCreationRequirement = 'none';

// در _loadConfiguration:
_businessCreationRequirement = data['business_creation_verification_requirement']?.toString() ?? 'none';

// در UI:
_buildDropdownField(
  label: 'محدودیت ایجاد کسب و کار',
  value: _businessCreationRequirement,
  items: [
    DropdownMenuItem(
      value: 'none',
      child: Text('بدون محدودیت (همه کاربران)'),
    ),
    DropdownMenuItem(
      value: 'email_only',
      child: Text('فقط ایمیل تایید شده'),
    ),
    DropdownMenuItem(
      value: 'mobile_only',
      child: Text('فقط شماره موبایل تایید شده'),
    ),
    DropdownMenuItem(
      value: 'both',
      child: Text('هر دو (ایمیل و موبایل)'),
    ),
    DropdownMenuItem(
      value: 'either',
      child: Text('هر کدام (ایمیل یا موبایل)'),
    ),
  ],
  onChanged: (value) => setState(() => _businessCreationRequirement = value!),
),
// افزودن توضیحات
Padding(
  padding: const EdgeInsets.only(top: 8, bottom: 16),
  child: Text(
    'این تنظیم تعیین می‌کند که چه کاربرانی می‌توانند کسب و کار جدید ایجاد کنند.',
    style: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  ),
),
```

### 3.2. بررسی در صفحه ایجاد کسب و کار

**در `new_business_page.dart`:**

**در `initState()` یا قبل از نمایش فرم:**
```dart
Future<void> _checkCreationPermission() async {
  try {
    // دریافت تنظیمات سیستم
    final systemConfig = await AdminSystemSettingsService(ApiClient()).getSystemConfiguration();
    final requirement = systemConfig['business_creation_verification_requirement']?.toString() ?? 'none';
    
    if (requirement == 'none') {
      // بدون محدودیت - ادامه
      return;
    }
    
    // دریافت اطلاعات کاربر
    final userInfo = await VerificationService(ApiClient()).getUserInfo();
    final emailVerified = userInfo['email_verified'] == true;
    final mobileVerified = userInfo['mobile_verified'] == true;
    
    // بررسی دسترسی
    bool canCreate = false;
    String? errorMessage;
    
    switch (requirement) {
      case 'email_only':
        canCreate = emailVerified;
        errorMessage = 'برای ایجاد کسب و کار، باید ایمیل خود را تایید کنید.';
        break;
      case 'mobile_only':
        canCreate = mobileVerified;
        errorMessage = 'برای ایجاد کسب و کار، باید شماره موبایل خود را تایید کنید.';
        break;
      case 'both':
        canCreate = emailVerified && mobileVerified;
        List<String> missing = [];
        if (!emailVerified) missing.add('ایمیل');
        if (!mobileVerified) missing.add('شماره موبایل');
        errorMessage = 'برای ایجاد کسب و کار، باید ${missing.join(' و ')} خود را تایید کنید.';
        break;
      case 'either':
        canCreate = emailVerified || mobileVerified;
        errorMessage = 'برای ایجاد کسب و کار، باید حداقل ایمیل یا شماره موبایل خود را تایید کنید.';
        break;
    }
    
    if (!canCreate && mounted) {
      // نمایش Dialog راهنما
      _showVerificationRequiredDialog(errorMessage ?? 'شما اجازه ایجاد کسب و کار را ندارید');
    }
  } catch (e) {
    // خطا در بررسی - اجازه می‌دهیم ادامه دهد (fail open)
  }
}
```

**Dialog راهنما:**
```dart
Future<void> _showVerificationRequiredDialog(String message) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange),
          SizedBox(width: 8),
          Text('تایید مورد نیاز'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 16),
          const Text(
            'برای تایید ایمیل و شماره موبایل، به بخش تنظیمات حساب کاربری بروید.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('بعداً'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(ctx).pop(true);
            context.go('/user/profile/verification');
          },
          icon: const Icon(Icons.verified_user),
          label: const Text('رفتن به تایید'),
        ),
      ],
    ),
  );
  
  if (result == true && mounted) {
    // هدایت به صفحه تایید
    context.go('/user/profile/verification');
  }
}
```

**بررسی در endpoint (Backend):**

```python
@router.post("", ...)
def create_new_business(
    request: Request,
    business_data: BusinessCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """ایجاد کسب و کار جدید"""
    from app.services.business_service import check_business_creation_permission
    from app.core.responses import ApiError
    
    owner_id = ctx.get_user_id()
    
    # بررسی دسترسی
    can_create, error_message = check_business_creation_permission(db, owner_id)
    if not can_create:
        raise ApiError(
            "BUSINESS_CREATION_NOT_ALLOWED",
            error_message or "شما اجازه ایجاد کسب و کار را ندارید",
            http_status=403
        )
    
    business = create_business(db, business_data, owner_id)
    formatted_data = format_datetime_fields(business, request)
    return success_response(formatted_data, request)
```

---

## 4. پیام‌های راهنما

### 4.1. پیام‌های خطا برای کاربر

#### حالت 1: فقط ایمیل تایید شده لازم است
```
❌ برای ایجاد کسب و کار، شما باید ایمیل خود را تایید کنید.

لطفاً به بخش "تایید شماره موبایل و ایمیل" در تنظیمات حساب کاربری بروید و ایمیل خود را تایید کنید.

[بعداً] [رفتن به تایید]
```

#### حالت 2: فقط شماره موبایل تایید شده لازم است
```
❌ برای ایجاد کسب و کار، شما باید شماره موبایل خود را تایید کنید.

لطفاً به بخش "تایید شماره موبایل و ایمیل" در تنظیمات حساب کاربری بروید و شماره موبایل خود را تایید کنید.

[بعداً] [رفتن به تایید]
```

#### حالت 3: هر دو لازم است
```
❌ برای ایجاد کسب و کار، شما باید ایمیل و شماره موبایل خود را تایید کنید.

لطفاً به بخش "تایید شماره موبایل و ایمیل" در تنظیمات حساب کاربری بروید و هر دو را تایید کنید.

[بعداً] [رفتن به تایید]
```

#### حالت 4: هر کدام لازم است
```
❌ برای ایجاد کسب و کار، شما باید حداقل ایمیل یا شماره موبایل خود را تایید کنید.

لطفاً به بخش "تایید شماره موبایل و ایمیل" در تنظیمات حساب کاربری بروید و حداقل یکی را تایید کنید.

[بعداً] [رفتن به تایید]
```

### 4.2. پیام‌های توضیحی در تنظیمات

**در صفحه تنظیمات سیستم:**

```
┌─────────────────────────────────────────────────┐
│ محدودیت ایجاد کسب و کار                        │
│ [Dropdown: انتخاب گزینه]                       │
│                                                 │
│ توضیحات:                                        │
│ این تنظیم تعیین می‌کند که چه کاربرانی می‌توانند│
│ کسب و کار جدید ایجاد کنند:                     │
│                                                 │
│ • بدون محدودیت: همه کاربران                    │
│ • فقط ایمیل تایید شده: فقط کاربران با ایمیل   │
│   تایید شده                                     │
│ • فقط شماره موبایل تایید شده: فقط کاربران با  │
│   شماره موبایل تایید شده                       │
│ • هر دو: کاربر باید هم ایمیل و هم شماره موبایل│
│   تایید شده داشته باشد                         │
│ • هر کدام: کاربر باید حداقل یکی از دو را      │
│   تایید کرده باشد                               │
└─────────────────────────────────────────────────┘
```

---

## 5. جریان کاربری

### 5.1. کاربر عادی که می‌خواهد کسب و کار ایجاد کند

**سناریو 1: دسترسی دارد**
1. کاربر به صفحه ایجاد کسب و کار می‌رود
2. فرم را پر می‌کند
3. روی "ایجاد" کلیک می‌کند
4. کسب و کار ایجاد می‌شود ✅

**سناریو 2: دسترسی ندارد**
1. کاربر به صفحه ایجاد کسب و کار می‌رود
2. سیستم بررسی می‌کند:
   - تنظیمات سیستم چیست؟
   - وضعیت تایید کاربر چیست؟
3. اگر دسترسی ندارد:
   - نمایش Dialog راهنما
   - پیام خطا با توضیحات
   - دکمه "رفتن به تایید"
4. کاربر روی "رفتن به تایید" کلیک می‌کند
5. به صفحه `/user/profile/verification` هدایت می‌شود
6. کاربر تایید می‌کند
7. دوباره به صفحه ایجاد کسب و کار برمی‌گردد
8. کسب و کار ایجاد می‌شود ✅

### 5.2. مدیر سیستم که تنظیمات را تغییر می‌دهد

1. مدیر به صفحه تنظیمات سیستم می‌رود
2. در بخش "محدودیت ایجاد کسب و کار" گزینه مورد نظر را انتخاب می‌کند
3. روی "ذخیره" کلیک می‌کند
4. تنظیمات ذخیره می‌شود
5. از این به بعد، تمام کاربران بر اساس این تنظیم بررسی می‌شوند

---

## 6. بررسی‌های امنیتی

### 6.1. در Backend

- ✅ بررسی دسترسی در endpoint ایجاد کسب و کار
- ✅ بررسی دسترسی در service layer
- ✅ اعتبارسنجی مقدار requirement
- ✅ Cache برای بهبود عملکرد

### 6.2. در Frontend

- ✅ بررسی دسترسی قبل از نمایش فرم (اختیاری - برای UX بهتر)
- ✅ نمایش پیام خطا از Backend
- ✅ راهنمایی کاربر برای تایید

---

## 7. حالت‌های Edge Case

### 7.1. کاربر ایمیل/موبایل ندارد

**در حالت `email_only`:**
- اگر کاربر ایمیل ندارد → خطا: "شما باید ابتدا ایمیل خود را ثبت کنید"

**در حالت `mobile_only`:**
- اگر کاربر شماره موبایل ندارد → خطا: "شما باید ابتدا شماره موبایل خود را ثبت کنید"

### 7.2. تنظیمات تغییر می‌کند در حین ایجاد کسب و کار

- بررسی در زمان درخواست (نه در زمان بارگذاری صفحه)
- Backend همیشه آخرین تنظیمات را بررسی می‌کند

### 7.3. کاربر SuperAdmin

- SuperAdmin همیشه می‌تواند کسب و کار ایجاد کند (یا می‌تواند محدود شود - بر اساس تصمیم)

---

## 8. تغییرات در API

### 8.1. Endpoint دریافت تنظیمات

```
GET /api/v1/admin/system/configuration

Response:
{
    "success": true,
    "data": {
        ...
        "business_creation_verification_requirement": "email_only"
    }
}
```

### 8.2. Endpoint تنظیم تنظیمات

```
POST /api/v1/admin/system/configuration

Body:
{
    ...
    "business_creation_verification_requirement": "email_only"
}
```

### 8.3. Endpoint ایجاد کسب و کار

**خطای جدید:**
```
POST /api/v1/businesses

Error Response (403):
{
    "success": false,
    "error": {
        "code": "BUSINESS_CREATION_NOT_ALLOWED",
        "message": "برای ایجاد کسب و کار، شما باید ایمیل خود را تایید کنید"
    }
}
```

---

## 9. Migration Plan

### Phase 1: Backend
1. اضافه کردن کلید جدید به `system_settings_service.py`
2. ایجاد تابع `check_business_creation_permission()`
3. اضافه کردن بررسی در `create_business()`
4. اضافه کردن به `get_system_configuration()` و `set_system_configuration()`
5. به‌روزرسانی Schema ها

### Phase 2: Frontend - تنظیمات
1. اضافه کردن فیلد به `system_configuration_page.dart`
2. به‌روزرسانی Service برای ارسال/دریافت تنظیمات

### Phase 3: Frontend - ایجاد کسب و کار
1. اضافه کردن بررسی در `new_business_page.dart`
2. ایجاد Dialog راهنما
3. اضافه کردن لینک به صفحه تایید

### Phase 4: Testing & Documentation
1. تست تمام حالات
2. تست پیام‌های خطا
3. تست راهنمایی کاربر

---

## 10. UI/UX Considerations

### 10.1. نمایش راهنما در صفحه ایجاد کسب و کار

**اگر کاربر دسترسی ندارد:**

```
┌────────────────────────────────────────────┐
│ ⚠️  برای ایجاد کسب و کار، باید یکی از موارد│
│    زیر را تایید کنید:                      │
│                                            │
│    ✓ ایمیل تایید شده                      │
│    ✗ شماره موبایل تایید شده               │
│                                            │
│    [رفتن به تایید شماره موبایل و ایمیل]   │
└────────────────────────────────────────────┘
```

### 10.2. نمایش وضعیت در تنظیمات سیستم

```
┌────────────────────────────────────────────┐
│ محدودیت ایجاد کسب و کار:                  │
│ [Dropdown: هر کدام (ایمیل یا موبایل)]    │
│                                            │
│ ℹ️  کاربران باید حداقل ایمیل یا شماره     │
│    موبایل خود را تایید کرده باشند         │
└────────────────────────────────────────────┘
```

---

## 11. منطق بررسی

### 11.1. نمودار جریان

```
کاربر می‌خواهد کسب و کار ایجاد کند
    ↓
دریافت تنظیمات سیستم
    ↓
requirement چیست؟
    ↓
┌─────────────────────────────────────────┐
│ none → ✅ اجازه                         │
│ email_only → بررسی email_verified      │
│ mobile_only → بررسی mobile_verified    │
│ both → بررسی هر دو                     │
│ either → بررسی حداقل یکی               │
└─────────────────────────────────────────┘
    ↓
اجازه دارد؟ → ✅ ایجاد کسب و کار
    ↓
اجازه ندارد؟ → ❌ خطا + راهنمایی
```

### 11.2. جدول تصمیم‌گیری

| Requirement | email_verified | mobile_verified | نتیجه |
|------------|----------------|-----------------|--------|
| none | - | - | ✅ اجازه |
| email_only | ✅ | - | ✅ اجازه |
| email_only | ❌ | - | ❌ خطا |
| mobile_only | - | ✅ | ✅ اجازه |
| mobile_only | - | ❌ | ❌ خطا |
| both | ✅ | ✅ | ✅ اجازه |
| both | ❌ | ✅ | ❌ خطا |
| both | ✅ | ❌ | ❌ خطا |
| both | ❌ | ❌ | ❌ خطا |
| either | ✅ | ✅ | ✅ اجازه |
| either | ✅ | ❌ | ✅ اجازه |
| either | ❌ | ✅ | ✅ اجازه |
| either | ❌ | ❌ | ❌ خطا |

---

## 12. پیام‌های خطا و راهنما

### 12.1. پیام‌های خطا از Backend

```python
ERROR_MESSAGES = {
    "none": None,  # بدون خطا
    "email_only": "برای ایجاد کسب و کار، شما باید ایمیل خود را تایید کنید. لطفاً به بخش 'تایید شماره موبایل و ایمیل' در تنظیمات حساب کاربری بروید.",
    "mobile_only": "برای ایجاد کسب و کار، شما باید شماره موبایل خود را تایید کنید. لطفاً به بخش 'تایید شماره موبایل و ایمیل' در تنظیمات حساب کاربری بروید.",
    "both": "برای ایجاد کسب و کار، شما باید هم ایمیل و هم شماره موبایل خود را تایید کنید. لطفاً به بخش 'تایید شماره موبایل و ایمیل' در تنظیمات حساب کاربری بروید.",
    "either": "برای ایجاد کسب و کار، شما باید حداقل ایمیل یا شماره موبایل خود را تایید کنید. لطفاً به بخش 'تایید شماره موبایل و ایمیل' در تنظیمات حساب کاربری بروید.",
}
```

### 12.2. راهنمایی در Dialog

**قالب Dialog:**
```
┌────────────────────────────────────────────┐
│ ℹ️  تایید مورد نیاز                       │
├────────────────────────────────────────────┤
│                                            │
│ [پیام خطا از Backend]                      │
│                                            │
│ 📋 راهنما:                                 │
│ 1. به بخش "تنظیمات حساب کاربری" بروید    │
│ 2. روی "تایید شماره موبایل و ایمیل" کلیک│
│    کنید                                    │
│ 3. ایمیل/شماره موبایل خود را تایید کنید  │
│ 4. دوباره به این صفحه برگردید             │
│                                            │
│ [بستن]  [رفتن به تایید]                   │
└────────────────────────────────────────────┘
```

---

## 13. تست‌های مورد نیاز

### 13.1. Unit Tests

- تست تابع `check_business_creation_permission()` برای هر حالت
- تست اعتبارسنجی requirement
- تست حالت‌های edge case

### 13.2. Integration Tests

- تست endpoint ایجاد کسب و کار با هر requirement
- تست تغییر requirement توسط مدیر
- تست تاثیر بر کاربران مختلف

### 13.3. UI Tests

- تست نمایش Dialog راهنما
- تست هدایت به صفحه تایید
- تست بررسی در Frontend

---

## خلاصه

این سناریو یک راه‌حل جامع برای کنترل دسترسی ایجاد کسب و کار ارائه می‌دهد که:

✅ انعطاف‌پذیر است (5 گزینه مختلف)
✅ امن است (بررسی در Backend)
✅ کاربرپسند است (راهنمایی و Dialog)
✅ قابل مدیریت است (تنظیمات توسط مدیر)
✅ قابل توسعه است (می‌توان گزینه‌های جدید اضافه کرد)

**مزایا:**
- کنترل کامل توسط مدیر سیستم
- راهنمایی کامل برای کاربران
- امنیت بالا
- UX مناسب

