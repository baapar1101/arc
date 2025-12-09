# 📱 سیستم نوتیفیکیشن جامع کسب‌وکارها

## 📋 فهرست مطالب
1. [مقدمه](#مقدمه)
2. [معماری سیستم](#معماری-سیستم)
3. [جداول دیتابیس](#جداول-دیتابیس)
4. [نحوه استفاده](#نحوه-استفاده)
5. [مثال‌ها](#مثالها)
6. [API Documentation](#api-documentation)

---

## 🎯 مقدمه

این سیستم یک راهکار جامع برای ارسال نوتیفیکیشن (پیامک و ایمیل) به مشتریان است که:

✅ **برای هر کسب‌وکار**: قالب‌های سفارشی  
✅ **برای هر رویداد**: فاکتور، تعمیر، پرداخت، و...  
✅ **تایید خودکار با AI**: جلوگیری از spam  
✅ **بدون نیاز به اعتبار**: AI مدیریت می‌شود توسط سیستم  
✅ **قابل استفاده در همه بخش‌ها**: فاکتور، تعمیرگاه، انبار، و...  

---

## 🏗️ معماری سیستم

### مراحل ارسال نوتیفیکیشن

```
┌─────────────┐
│  رویداد     │  مثلاً: ثبت فاکتور جدید
│ (Event)     │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────┐
│ جستجوی قالب فعال           │
│ - business_id               │
│ - event_type                │
│ - channel (sms/email)       │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│ بررسی محدودیت روزانه       │
│ - daily_limit check         │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│ رندر قالب                   │
│ - جایگزینی {{ متغیرها }}   │
│ - اعمال فیلترها             │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│ ارسال پیام                  │
│ - SMS Provider              │
│ - Email Provider            │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│ ثبت لاگ و آمار              │
│ - notification_send_logs    │
│ - notification_daily_stats  │
└─────────────────────────────┘
```

### Flow تایید قالب‌ها

```
[کسب‌وکار] ایجاد قالب
    ↓
[وضعیت: draft]
    ↓
ارسال برای تایید
    ↓
[وضعیت: pending_approval]
[صف: pending]
    ↓
────────────────────────────────
    AI Worker (هر 60 ثانیه)
────────────────────────────────
    ↓
بررسی محتوا:
  • Rule-based checks
  • Spam detection
  • LLM analysis
    ↓
┌─────────┬──────────┬───────────┐
│         │          │           │
│ Score>90│ 40<Score<90│ Score<40│
│         │          │           │
▼         ▼          ▼
[Approve] [Review]   [Reject]
[AI]      [Admin]    [Auto]
│         │          │
│         ▼          │
│    [مدیر سیستم]   │
│    تایید/رد       │
│         │          │
└─────────┴──────────┘
         │
         ▼
    [فعال شدن قالب]
    [is_active = TRUE]
```

---

## 📊 جداول دیتابیس

### 1. `notification_event_types`
تعریف انواع رویدادها و متغیرهای قابل استفاده

**مثال رکوردها**:
| code | name | category | requires_approval |
|------|------|----------|-------------------|
| invoice.created | ثبت فاکتور فروش | sales | TRUE |
| repair_shop.received | دریافت کالا | repair_shop | TRUE |
| payment.received | دریافت پرداخت | financial | TRUE |

### 2. `business_notification_templates`
قالب‌های هر کسب‌وکار

**وضعیت‌های قالب**:
- `draft`: پیش‌نویس (غیرفعال)
- `pending_approval`: در صف بررسی
- `approved`: تایید شده (فعال)
- `rejected`: رد شده
- `suspended`: تعلیق شده

**وضعیت تایید**:
- `pending`: در انتظار بررسی
- `ai_approved`: تایید شده توسط AI
- `admin_approved`: تایید شده توسط مدیر
- `rejected`: رد شده

### 3. `notification_moderation_queue`
صف بررسی قالب‌ها

**فیلدهای کلیدی**:
- `ai_decision`: approve, reject, review_required
- `ai_confidence`: 0-100
- `ai_flags`: لیست مشکلات یافت شده
- `admin_decision`: approve, reject

### 4. `notification_send_logs`
لاگ کامل تمام ارسال‌ها

**برای**:
- ردیابی ارسال‌ها
- گزارش‌گیری
- Debugging

### 5. `notification_daily_stats`
آمار روزانه برای Rate Limiting

---

## 🚀 نحوه استفاده

### مرحله 1: ایجاد Event Types

```bash
python scripts/seed_notification_event_types.py
```

این اسکریپت 7 event type اولیه ایجاد می‌کند.

### مرحله 2: اجرای Migration

```bash
alembic upgrade head
```

### مرحله 3: ایجاد قالب توسط کسب‌وکار

**API Call**:
```http
POST /api/v1/business-notifications/businesses/1/templates

{
  "code": "invoice_created_sms",
  "name": "پیامک ثبت فاکتور",
  "event_type": "invoice.created",
  "channel": "sms",
  "body": "سلام {{ customer_name }}، فاکتور {{ invoice_number }} به مبلغ {{ amount | format_currency }} ثبت شد. {{ business_name }}",
  "daily_limit": 100,
  "is_automated": true
}
```

**Response**:
```json
{
  "data": {
    "id": 123,
    "code": "invoice_created_sms",
    "status": "draft",
    "message": "قالب ایجاد شد. برای فعال‌سازی باید آن را برای تایید ارسال کنید."
  }
}
```

### مرحله 4: ارسال برای تایید

```http
POST /api/v1/business-notifications/businesses/1/templates/123/submit-for-approval
```

قالب وارد صف می‌شود و:
- ✅ اگر AI Worker فعال باشد → بررسی خودکار (کمتر از 1 دقیقه)
- ⏳ اگر نیاز به بررسی داشته باشد → صف مدیر سیستم

### مرحله 5: بررسی توسط AI Worker

```bash
# اجرای یک بار (تست)
python -m app.workers.notification_moderation_worker

# اجرای مداوم (production)
# این worker باید در background اجرا شود
```

**خروجی**:
```
🚀 شروع Notification Moderation Worker
✅ بررسی قالب 123 تکمیل شد
   Decision: approve
   Confidence: 95.0
   Flags: []
```

### مرحله 6: ارسال نوتیفیکیشن

```python
from app.services.business_notification_service import BusinessNotificationService

service = BusinessNotificationService(db)

result = service.send_to_person(
    business_id=1,
    person_id=customer.id,
    event_type="invoice.created",
    context={
        "invoice_number": "INV-2025-001",
        "customer_name": "علی احمدی",
        "amount": 1500000,
        "invoice_date": "1403/12/15",
        "due_date": "1403/12/30",
        "business_name": "فروشگاه پارس",
        "business_phone": "021-12345678"
    },
    triggered_by_user_id=user_id
)
```

---

## 💡 مثال‌های کاربردی

### مثال 1: ارسال پیامک هنگام ثبت فاکتور

```python
# در invoice_service.py، بعد از ایجاد فاکتور:

from app.services.business_notification_service import BusinessNotificationService

def create_invoice(...):
    # ... ایجاد فاکتور
    
    # ارسال نوتیفیکیشن
    try:
        notif_service = BusinessNotificationService(db)
        notif_service.send_to_person(
            business_id=business_id,
            person_id=invoice.person_id,
            event_type="invoice.created",
            context={
                "invoice_number": invoice.code,
                "customer_name": customer.name,
                "amount": float(invoice.total_amount),
                "invoice_date": invoice.document_date.isoformat(),
                "due_date": invoice.due_date.isoformat() if invoice.due_date else "",
            },
            triggered_by_user_id=user_id
        )
    except Exception as e:
        logger.error(f"خطا در ارسال نوتیفیکیشن: {e}")
        # ادامه می‌دهیم - عدم ارسال نوتیفیکیشن نباید مانع ثبت فاکتور شود
```

### مثال 2: پیش‌نمایش قالب قبل از ذخیره

```python
service = BusinessNotificationService(db)

preview = service.preview_template(
    business_id=1,
    template_id=123,
    sample_context={
        "customer_name": "علی احمدی",
        "invoice_number": "INV-001",
        "amount": 1500000
    }
)

print("متن نهایی:")
print(preview["rendered"]["body"])
# خروجی: سلام علی احمدی، فاکتور INV-001 به مبلغ 1,500,000 تومان ثبت شد.
```

### مثال 3: ایجاد قالب با فیلترهای Jinja2

```python
body = """
سلام {{ customer_name }} عزیز،

فاکتور شماره {{ invoice_number }} در تاریخ {{ invoice_date | format_date('%Y/%m/%d') }} ثبت شد.

مبلغ: {{ amount | format_currency('تومان') }}
سررسید: {{ due_date | format_date }}

لطفاً تا {{ days_remaining }} روز دیگر پرداخت فرمایید.

{{ business_name }}
"""

# فیلترهای موجود:
# - format_number: 1500000 → 1,500,000
# - format_date: datetime → 1403/12/15
# - format_currency: 1500000 → 1,500,000 تومان
```

---

## 🔐 امنیت و جلوگیری از Spam

### سطوح بررسی

#### 1️⃣ **Rule-based Checks**
- طول محتوا (10-1000 کاراکتر)
- استفاده صحیح از متغیرها
- Syntax قالب

#### 2️⃣ **Spam Detection**
کلمات ممنوع:
- تخفیف ویژه، فقط امروز، رایگان
- کلیک کنید، همین حالا، محدود
- جایزه، مسابقه، قرعه‌کشی

Pattern های مشکوک:
- `\d+%\s*تخفیف` → 50% تخفیف
- `فقط\s+\d+\s+روز` → فقط 3 روز
- تعداد زیاد لینک
- استفاده بیش از حد از emoji/علامت تعجب

#### 3️⃣ **AI Review (با LLM)**
- تشخیص محتوای تبلیغاتی
- شناسایی spam patterns پیچیده
- بررسی تطابق با event_type
- پیشنهادات بهبود

### تصمیم‌گیری خودکار

| Score | Confidence | تصمیم AI | اقدام نهایی |
|-------|-----------|---------|-------------|
| > 90 | High | ✅ Approve | فعال‌سازی خودکار |
| 70-90 | Medium | ⏳ Review | ارسال به مدیر |
| 40-70 | Low | ⚠️ Review | ارسال به مدیر با اولویت |
| < 40 | Very Low | ❌ Reject | رد خودکار |

---

## 📡 API Documentation

### برای کسب‌وکار

#### دریافت لیست event types
```http
GET /api/v1/business-notifications/event-types?category=sales
```

#### لیست قالب‌ها
```http
GET /api/v1/business-notifications/businesses/{business_id}/templates
```

#### ایجاد قالب
```http
POST /api/v1/business-notifications/businesses/{business_id}/templates
Content-Type: application/json

{
  "code": "unique_code",
  "name": "نام قالب",
  "event_type": "invoice.created",
  "channel": "sms",
  "body": "محتوا با {{ متغیرها }}",
  "daily_limit": 100
}
```

#### پیش‌نمایش قالب
```http
POST /api/v1/business-notifications/businesses/{business_id}/templates/{id}/preview
Content-Type: application/json

{
  "sample_context": {
    "customer_name": "علی احمدی",
    "invoice_number": "INV-001"
  }
}
```

#### ارسال نوتیفیکیشن
```http
POST /api/v1/business-notifications/businesses/{business_id}/send
Content-Type: application/json

{
  "person_id": 123,
  "event_type": "invoice.created",
  "context": {
    "invoice_number": "INV-001",
    "amount": 1500000
  }
}
```

#### مشاهده لاگ‌ها
```http
GET /api/v1/business-notifications/businesses/{business_id}/logs?channel=sms&status=sent
```

### برای مدیر سیستم

#### صف بررسی
```http
GET /api/v1/admin/notification-moderation/queue?status=admin_reviewing
```

#### آمار صف
```http
GET /api/v1/admin/notification-moderation/queue/stats
```

#### تایید قالب
```http
POST /api/v1/admin/notification-moderation/queue/{queue_id}/approve
Content-Type: application/json

{
  "notes": "قالب مناسب است"
}
```

#### رد قالب
```http
POST /api/v1/admin/notification-moderation/queue/{queue_id}/reject
Content-Type: application/json

{
  "reason": "محتوا تبلیغاتی است",
  "notes": "از کلمات 'تخفیف ویژه' استفاده نکنید"
}
```

---

## 🔧 تنظیمات و راه‌اندازی

### تنظیمات AI (استفاده از AIService موجود)

**توجه مهم**: این سیستم از `AIService` موجود در نرم‌افزار استفاده می‌کند.

✅ **مزایا**:
- یکپارچه با سیستم موجود
- استفاده از تنظیمات OpenAI موجود
- بدون نیاز به نصب Ollama
- مدیریت یکپارچه اعتبار

✅ **نحوه کار**:
- از اعتبار سیستم استفاده می‌کند (نه کاربر)
- تنها superadmin ها بدون محدودیت از AI استفاده می‌کنند
- هزینه moderation بر عهده سیستم است (رایگان برای کسب‌وکارها)

✅ **پیش‌نیاز**:
- تنظیمات AI در پنل مدیر فعال باشد
- حداقل یک کاربر superadmin وجود داشته باشد

### راه‌اندازی Worker

```bash
# در production، با supervisor یا systemd:

[program:notification_moderation_worker]
command=python -m app.workers.notification_moderation_worker
directory=/var/www/ark/hesabixAPI
autostart=true
autorestart=true
user=www-data
```

---

## 📈 گزارشات و آمار

### آمار روزانه
```python
from adapters.db.repositories.business_notification_repo import NotificationDailyStatRepository
from datetime import date, timedelta

stat_repo = NotificationDailyStatRepository(db)
stats = stat_repo.get_stats(
    business_id=1,
    from_date=date.today() - timedelta(days=30),
    to_date=date.today()
)

for stat in stats:
    print(f"{stat.date}: {stat.total_sent} sent, {stat.total_failed} failed")
```

### لاگ‌های ارسال
```python
from adapters.db.repositories.business_notification_repo import NotificationSendLogRepository

log_repo = NotificationSendLogRepository(db)
logs, total = log_repo.list_by_business(
    business_id=1,
    filters={"status": "failed", "channel": "sms"},
    offset=0,
    limit=50
)
```

---

## 🛡️ امنیت

### محدودیت‌ها

1. **Daily Limit**: هر قالب حداکثر X ارسال در روز
2. **Template Approval**: قالب‌ها قبل از فعال شدن بررسی می‌شوند
3. **Content Filtering**: محتوای تبلیغاتی و spam فیلتر می‌شود
4. **Audit Trail**: تمام ارسال‌ها ثبت می‌شوند

### Best Practices

✅ **DO**:
- از متغیرها استفاده کنید: `{{ customer_name }}`
- پیام‌های کوتاه و واضح بنویسید
- اطلاعات تماس کسب‌وکار را اضافه کنید

❌ **DON'T**:
- از کلمات تبلیغاتی استفاده نکنید
- محتوای طولانی ننویسید (SMS < 200 کاراکتر)
- لینک‌های زیاد نگذارید

---

## 🔄 یکپارچه‌سازی با بخش‌های دیگر

### فاکتور (Invoice)
```python
# در invoice_service.py

from app.services.business_notification_service import BusinessNotificationService

def create_invoice(...):
    # ... ایجاد فاکتور
    
    # ارسال نوتیفیکیشن
    notif_service = BusinessNotificationService(db)
    notif_service.send_to_person(
        business_id=business_id,
        person_id=invoice.person_id,
        event_type="invoice.created",
        context={...},
        triggered_by_user_id=user_id
    )
```

### تعمیرگاه (Repair Shop)
```python
# در repair_shop_service.py

from app.services.repair_shop_notification import send_repair_notification

def create_repair_order(...):
    # ... ایجاد سفارش
    
    # ارسال نوتیفیکیشن
    send_repair_notification(
        db=db,
        business_id=business_id,
        repair_order=order,
        event_type="repair_shop.received",
        triggered_by_user_id=user_id
    )
```

### پرداخت (Payment)
```python
from app.services.business_notification_service import BusinessNotificationService

def record_payment(...):
    # ... ثبت پرداخت
    
    notif_service = BusinessNotificationService(db)
    notif_service.send_to_person(
        business_id=business_id,
        person_id=payment.person_id,
        event_type="payment.received",
        context={...}
    )
```

---

## 🎨 متغیرها و فیلترها

### متغیرهای رایج

| متغیر | توضیح | مثال |
|-------|-------|------|
| `{{ customer_name }}` | نام مشتری | علی احمدی |
| `{{ business_name }}` | نام کسب‌وکار | فروشگاه پارس |
| `{{ business_phone }}` | تلفن کسب‌وکار | 021-12345678 |
| `{{ invoice_number }}` | شماره فاکتور | INV-2025-001 |
| `{{ amount }}` | مبلغ | 1500000 |

### فیلترهای Jinja2

| فیلتر | کاربرد | مثال |
|-------|---------|------|
| `format_number` | جداکننده هزارگان | `{{ 1500000 \| format_number }}` → 1,500,000 |
| `format_currency` | فرمت مبلغ با ارز | `{{ amount \| format_currency }}` → 1,500,000 تومان |
| `format_date` | فرمت تاریخ | `{{ date \| format_date('%Y/%m/%d') }}` → 1403/12/15 |

---

## 🐛 Troubleshooting

### قالب تایید نمی‌شود
1. بررسی لاگ‌های Worker
2. اجرای دستی Worker برای debug
3. بررسی صف در پنل مدیر

### پیام ارسال نمی‌شود
1. بررسی وجود قالب فعال
2. بررسی محدودیت روزانه
3. بررسی لاگ‌های ارسال
4. بررسی تنظیمات SMS Provider

### خطای Template Syntax
- از `{{ variable }}` استفاده کنید (نه `{ variable }`)
- متغیرها case-sensitive هستند
- از پیش‌نمایش استفاده کنید

---

## 📞 پشتیبانی

برای سوالات و مشکلات:
1. بررسی این مستند
2. بررسی لاگ‌های سیستم
3. تماس با تیم پشتیبانی

