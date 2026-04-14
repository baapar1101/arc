# سناریو نهایی: سیستم ناتیفیکیشن تیکت‌های پشتیبانی

## 📋 خلاصه اجرایی

این سناریو پیاده‌سازی سیستم کامل ناتیفیکیشن برای تیکت‌های پشتیبانی را پوشش می‌دهد که شامل:
- ارسال ناتیفیکیشن به اپراتورها هنگام ایجاد تیکت جدید توسط کاربر
- ارسال ناتیفیکیشن به اپراتورها هنگام پاسخ کاربر به تیکت
- ارسال ناتیفیکیشن به کاربر هنگام پاسخ اپراتور
- مدیریت کامل قالب‌ها و تنظیمات ناتیفیکیشن توسط مدیر سیستم

---

## 🎯 Event Keys پیشنهادی

### 1. `support.ticket_created`
**زمان:** وقتی کاربر تیکت جدید ایجاد می‌کند  
**گیرنده:** تمام اپراتورهای پشتیبانی  
**کانال‌ها:** `["inapp", "email", "telegram", "sms"]`

### 2. `support.user_reply`
**زمان:** وقتی کاربر به تیکت موجود پاسخ می‌دهد  
**گیرنده:** 
- اپراتور تخصیص‌یافته (اگر تیکت به اپراتور خاصی تخصیص شده)
- یا تمام اپراتورها (اگر تیکت هنوز تخصیص نشده)  
**کانال‌ها:** `["inapp", "email", "telegram", "sms"]`

### 3. `support.operator_reply`
**زمان:** وقتی اپراتور به تیکت پاسخ می‌دهد  
**گیرنده:** کاربر صاحب تیکت  
**کانال‌ها:** `["inapp", "email", "telegram", "sms"]`

---

## 📍 نقاط پیاده‌سازی در بکند

### 1. ایجاد تیکت جدید (`create_ticket`)

**فایل:** `hesabixAPI/adapters/api/v1/support/tickets.py`  
**تابع:** `create_ticket` (خطوط 97-137)

**تغییرات مورد نیاز:**
- بعد از ایجاد تیکت و پیام اولیه (بعد از خط 128)
- دریافت لیست تمام اپراتورهای پشتیبانی
- ارسال ناتیفیکیشن به هر اپراتور با `event_key: "support.ticket_created"`

**Context پیشنهادی:**
```python
context = {
    "subject": f"تیکت جدید #{ticket.id}: {ticket.title}",
    "message": f"کاربر {user.first_name} {user.last_name} تیکت جدیدی ایجاد کرده است:\n\n{ticket.description[:200]}...",
    "ticket_id": ticket.id,
    "ticket_title": ticket.title,
    "user_name": f"{user.first_name} {user.last_name}",
    "user_email": user.email,
    "category": ticket.category.name if ticket.category else "نامشخص",
    "priority": ticket.priority.name if ticket.priority else "نامشخص"
}
```

---

### 2. پاسخ کاربر به تیکت (`send_message`)

**فایل:** `hesabixAPI/adapters/api/v1/support/tickets.py`  
**تابع:** `send_message` (خطوط 164-197)

**تغییرات مورد نیاز:**
- بعد از ایجاد پیام (بعد از خط 191)
- بررسی اینکه `sender_type == "user"` و `is_internal == False`
- اگر تیکت به اپراتور خاصی تخصیص شده: ارسال فقط به آن اپراتور
- اگر تیکت تخصیص نشده: ارسال به تمام اپراتورها
- استفاده از `event_key: "support.user_reply"`

**Context پیشنهادی:**
```python
context = {
    "subject": f"پاسخ جدید به تیکت #{ticket.id}",
    "message": f"کاربر {user.first_name} {user.last_name} به تیکت شما پاسخ داد:\n\n{message.content[:200]}...",
    "ticket_id": ticket.id,
    "ticket_title": ticket.title,
    "user_name": f"{user.first_name} {user.last_name}",
    "user_email": user.email,
    "message_preview": message.content[:200]
}
```

---

### 3. پاسخ اپراتور به تیکت (`send_operator_message`)

**فایل:** `hesabixAPI/adapters/api/v1/support/operator.py`  
**تابع:** `send_operator_message` (خطوط 198-236)

**تغییرات مورد نیاز:**
- بعد از ایجاد پیام (بعد از خط 226)
- بررسی اینکه `sender_type == "operator"` و `is_internal == False`
- ارسال ناتیفیکیشن به کاربر صاحب تیکت (`ticket.user_id`)
- استفاده از `event_key: "support.operator_reply"`

**Context پیشنهادی:**
```python
context = {
    "subject": f"پاسخ جدید به تیکت #{ticket.id}",
    "message": f"اپراتور پشتیبانی به تیکت شما پاسخ داد:\n\n{message.content[:200]}...",
    "ticket_id": ticket.id,
    "ticket_title": ticket.title,
    "operator_name": f"{current_user.first_name} {current_user.last_name}" if hasattr(current_user, 'first_name') else "اپراتور پشتیبانی",
    "message_preview": message.content[:200]
}
```

---

### 4. پاسخ خودکار AI (`ai_auto_reply`)

**فایل:** `hesabixAPI/adapters/api/v1/support/ai_tickets.py`  
**تابع:** `ai_auto_reply` (خطوط 115-151)

**تغییرات مورد نیاز:**
- بعد از ایجاد پیام (بعد از خط 137)
- همان منطق `send_operator_message` را اعمال کنید
- استفاده از `event_key: "support.operator_reply"`

---

## 🔧 توابع کمکی مورد نیاز

### 1. دریافت لیست اپراتورهای پشتیبانی

**ایجاد تابع جدید در:** `hesabixAPI/adapters/db/repositories/user_repo.py`

```python
def get_support_operators(self) -> List[User]:
    """دریافت لیست تمام اپراتورهای پشتیبانی"""
    from sqlalchemy import text
    stmt = select(User).where(
        text("app_permissions->>'support_operator' = 'true'")
    ).where(User.is_active == True)
    return list(self.db.execute(stmt).scalars().all())
```

---

### 2. تابع کمکی ارسال ناتیفیکیشن به اپراتورها

**ایجاد تابع جدید در:** `hesabixAPI/app/services/notification_service.py` یا فایل جداگانه

```python
def notify_support_operators(
    self,
    event_key: str,
    context: Dict[str, Any],
    assigned_operator_id: Optional[int] = None,
    locale: Optional[str] = None
) -> None:
    """
    ارسال ناتیفیکیشن به اپراتورهای پشتیبانی
    
    Args:
        event_key: کلید رویداد (مثلاً "support.ticket_created")
        context: داده‌های context برای قالب
        assigned_operator_id: اگر مشخص باشد، فقط به این اپراتور ارسال می‌شود
        locale: زبان مورد نظر (اختیاری)
    """
    from adapters.db.repositories.user_repo import UserRepository
    user_repo = UserRepository(self.db)
    
    if assigned_operator_id:
        # ارسال فقط به اپراتور تخصیص‌یافته
        operator = user_repo.get_by_id(assigned_operator_id)
        if operator and operator.is_active:
            self.send(
                user_id=operator.id,
                event_key=event_key,
                context=context,
                preferred_channels=["inapp", "email", "telegram", "sms"],
                locale=locale
            )
    else:
        # ارسال به تمام اپراتورها
        operators = user_repo.get_support_operators()
        for operator in operators:
            try:
                self.send(
                    user_id=operator.id,
                    event_key=event_key,
                    context=context,
                    preferred_channels=["inapp", "email", "telegram", "sms"],
                    locale=locale
                )
            except Exception:
                # در صورت خطا، ادامه می‌دهیم تا به سایر اپراتورها ارسال شود
                pass
```

---

## 🎨 مدیریت قالب‌های ناتیفیکیشن

### سیستم موجود

سیستم مدیریت قالب‌ها از قبل در `hesabixAPI/adapters/api/v1/admin/notification_templates.py` پیاده‌سازی شده است.

**Endpoint های موجود:**
- `GET /api/v1/admin/notification-templates` - لیست قالب‌ها
- `POST /api/v1/admin/notification-templates` - ایجاد قالب جدید
- `PUT /api/v1/admin/notification-templates/{template_id}` - ویرایش قالب
- `DELETE /api/v1/admin/notification-templates/{template_id}` - حذف قالب
- `POST /api/v1/admin/notification-templates/preview` - پیش‌نمایش قالب

### قالب‌های پیشنهادی برای ایجاد

#### 1. قالب `support.ticket_created` - Email
```json
{
  "event_key": "support.ticket_created",
  "channel": "email",
  "locale": "fa",
  "subject": "تیکت جدید: {{ ticket_title }}",
  "body": "کاربر {{ user_name }} ({{ user_email }}) تیکت جدیدی ایجاد کرده است:\n\n{{ message }}\n\nشماره تیکت: #{{ ticket_id }}\nدسته‌بندی: {{ category }}\nاولویت: {{ priority }}",
  "is_active": true
}
```

#### 2. قالب `support.ticket_created` - Telegram
```json
{
  "event_key": "support.ticket_created",
  "channel": "telegram",
  "locale": "fa",
  "subject": null,
  "body": "🔔 تیکت جدید\n\nکاربر: {{ user_name }}\nموضوع: {{ ticket_title }}\n\n{{ message }}\n\n#{{ ticket_id }}",
  "is_active": true
}
```

#### 3. قالب `support.user_reply` - Email
```json
{
  "event_key": "support.user_reply",
  "channel": "email",
  "locale": "fa",
  "subject": "پاسخ جدید به تیکت #{{ ticket_id }}",
  "body": "کاربر {{ user_name }} به تیکت شما پاسخ داد:\n\n{{ message_preview }}\n\nبرای مشاهده کامل پاسخ، به پنل پشتیبانی مراجعه کنید.",
  "is_active": true
}
```

#### 4. قالب `support.operator_reply` - Email
```json
{
  "event_key": "support.operator_reply",
  "channel": "email",
  "locale": "fa",
  "subject": "پاسخ جدید به تیکت #{{ ticket_id }}",
  "body": "اپراتور {{ operator_name }} به تیکت شما پاسخ داد:\n\n{{ message_preview }}\n\nبرای مشاهده کامل پاسخ، به پنل پشتیبانی مراجعه کنید.",
  "is_active": true
}
```

#### 5. قالب `support.operator_reply` - InApp
```json
{
  "event_key": "support.operator_reply",
  "channel": "inapp",
  "locale": "fa",
  "subject": "پاسخ جدید به تیکت #{{ ticket_id }}",
  "body": "اپراتور به تیکت شما پاسخ داد: {{ message_preview }}",
  "is_active": true
}
```

---

## 📝 مراحل پیاده‌سازی

### مرحله 1: افزودن تابع دریافت اپراتورها
- [ ] افزودن متد `get_support_operators()` به `UserRepository`

### مرحله 2: افزودن تابع ارسال به اپراتورها
- [ ] افزودن متد `notify_support_operators()` به `NotificationService`

### مرحله 3: پیاده‌سازی در `create_ticket`
- [ ] Import کردن `NotificationService`
- [ ] دریافت لیست اپراتورها
- [ ] ارسال ناتیفیکیشن با `event_key: "support.ticket_created"`

### مرحله 4: پیاده‌سازی در `send_message`
- [ ] Import کردن `NotificationService`
- [ ] بررسی `sender_type == "user"` و `is_internal == False`
- [ ] ارسال ناتیفیکیشن با `event_key: "support.user_reply"`

### مرحله 5: پیاده‌سازی در `send_operator_message`
- [ ] Import کردن `NotificationService`
- [ ] بررسی `sender_type == "operator"` و `is_internal == False`
- [ ] ارسال ناتیفیکیشن به کاربر با `event_key: "support.operator_reply"`

### مرحله 6: پیاده‌سازی در `ai_auto_reply`
- [ ] Import کردن `NotificationService`
- [ ] ارسال ناتیفیکیشن به کاربر با `event_key: "support.operator_reply"`

### مرحله 7: ایجاد قالب‌های پیش‌فرض
- [ ] ایجاد قالب‌های پیشنهادی در دیتابیس (یا migration)

---

## ⚠️ نکات مهم

### 1. مدیریت خطا
- ارسال ناتیفیکیشن نباید باعث شکست فرآیند اصلی شود
- استفاده از `try/except` برای هر ارسال ناتیفیکیشن
- در صورت خطا، لاگ ثبت شود اما فرآیند ادامه یابد

### 2. بهینه‌سازی
- برای ارسال به چند اپراتور، می‌توان از background task استفاده کرد (اختیاری)
- محدود کردن طول `message_preview` به 200 کاراکتر

### 3. تنظیمات کاربر
- سیستم از قبل از `UserNotificationSetting` پشتیبانی می‌کند
- کاربران می‌توانند کانال‌های ناتیفیکیشن را فعال/غیرفعال کنند
- مدیر سیستم می‌تواند قالب‌ها را مدیریت کند

### 4. پیام‌های داخلی
- ناتیفیکیشن فقط برای پیام‌های غیرداخلی (`is_internal == False`) ارسال می‌شود

### 5. زبان (Locale)
- در صورت نیاز، می‌توان locale کاربر را از تنظیمات کاربر دریافت کرد
- قالب‌ها می‌توانند برای زبان‌های مختلف تعریف شوند

---

## 🔍 تست و بررسی

### سناریوهای تست:

1. **کاربر تیکت جدید ایجاد می‌کند:**
   - ✅ ناتیفیکیشن به تمام اپراتورها ارسال می‌شود
   - ✅ قالب‌های مختلف (email, telegram, inapp) کار می‌کنند

2. **کاربر به تیکت پاسخ می‌دهد:**
   - ✅ اگر تیکت تخصیص شده: فقط به اپراتور تخصیص‌یافته ارسال می‌شود
   - ✅ اگر تیکت تخصیص نشده: به تمام اپراتورها ارسال می‌شود

3. **اپراتور به تیکت پاسخ می‌دهد:**
   - ✅ ناتیفیکیشن به کاربر صاحب تیکت ارسال می‌شود
   - ✅ قالب‌های مختلف کار می‌کنند

4. **پیام داخلی:**
   - ✅ ناتیفیکیشن ارسال نمی‌شود

5. **مدیریت قالب‌ها:**
   - ✅ مدیر می‌تواند قالب‌ها را ایجاد، ویرایش و حذف کند
   - ✅ پیش‌نمایش قالب کار می‌کند

---

## 📚 فایل‌های مورد تغییر

### فایل‌های بکند:
1. `hesabixAPI/adapters/db/repositories/user_repo.py` - افزودن `get_support_operators()`
2. `hesabixAPI/app/services/notification_service.py` - افزودن `notify_support_operators()`
3. `hesabixAPI/adapters/api/v1/support/tickets.py` - افزودن ناتیفیکیشن در `create_ticket` و `send_message`
4. `hesabixAPI/adapters/api/v1/support/operator.py` - افزودن ناتیفیکیشن در `send_operator_message`
5. `hesabixAPI/adapters/api/v1/support/ai_tickets.py` - افزودن ناتیفیکیشن در `ai_auto_reply`

### فایل‌های فرانت:
- **نیازی به تغییر نیست** - سیستم ناتیفیکیشن از قبل در فرانت پیاده‌سازی شده است

---

## 🎯 نتیجه‌گیری

این سناریو یک سیستم کامل و قابل مدیریت برای ناتیفیکیشن تیکت‌های پشتیبانی ارائه می‌دهد که:
- ✅ تمام سناریوهای مورد نیاز را پوشش می‌دهد
- ✅ قابل مدیریت توسط مدیر سیستم است
- ✅ از قالب‌های قابل تنظیم استفاده می‌کند
- ✅ از تنظیمات کاربر برای کانال‌های ناتیفیکیشن پشتیبانی می‌کند
- ✅ خطاها را به درستی مدیریت می‌کند

