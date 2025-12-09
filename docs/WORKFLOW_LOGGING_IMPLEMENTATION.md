# 📊 مستندات پیاده‌سازی سیستم لاگ‌برداری و خطایابی Workflow

## 📅 تاریخ پیاده‌سازی
**تاریخ:** 2025-12-04  
**نسخه:** 1.0.0

---

## 🎯 خلاصه اجرایی

این سند شامل جزئیات کامل پیاده‌سازی سیستم لاگ‌برداری پیشرفته و خطایابی برای بخش اتوماسیون (Workflow) است. پیاده‌سازی در 4 فاز اصلی انجام شده است.

---

## 📦 فایل‌های تغییر یافته

### 1. فایل‌های اصلی تغییر یافته:
- ✅ `/hesabixAPI/app/services/workflow/workflow_engine.py` - اضافه کردن logging پیشرفته
- ✅ `/hesabixAPI/app/services/workflow/logging_decorators.py` - **فایل جدید** - Decorators برای logging
- ✅ `/hesabixAPI/app/services/workflow/actions/communication_actions.py` - اعمال decorators
- ✅ `/hesabixAPI/app/services/workflow/actions/utility_actions.py` - اعمال decorators  
- ✅ `/hesabixAPI/app/services/workflow/actions/document_actions.py` - اعمال decorators
- ✅ `/hesabixAPI/adapters/api/v1/workflows.py` - اضافه کردن API endpoints جدید

---

## 🚀 فاز 1: Core Logging Improvements

### تغییرات اعمال شده:

#### 1.1. اضافه کردن Correlation ID

**مکان:** `WorkflowEngine.__init__`

```python
def __init__(self, db: Session, business_id: int, user_id: Optional[int] = None):
    # ... کدهای قبلی
    self.correlation_id = str(uuid.uuid4())  # ✅ جدید
```

**مزایا:**
- امکان trace کردن یک workflow در تمام لاگ‌ها
- debugging آسان‌تر در محیط‌های production
- ارتباط دادن لاگ‌های مختلف به یک اجرای واحد

#### 1.2. اضافه کردن Performance Metrics

**مکان:** `WorkflowEngine._execute_workflow_internal`

**تغییرات:**
- اضافه کردن `node_start_time` برای هر node
- محاسبه `duration_ms` برای هر node
- لاگ کردن زمان اجرا در هر node

**نمونه لاگ:**
```json
{
  "node_id": "action_send_email",
  "node_type": "action",
  "node_label": "ارسال ایمیل به مشتری",
  "duration_ms": 234.56,
  "correlation_id": "a1b2c3d4-...",
  "success": true
}
```

#### 1.3. اضافه کردن Stack Trace

**مکان:** همه بخش‌های error handling

**تغییرات:**
```python
"stack_trace": traceback.format_exc()  # ✅ جدید
```

**مزایا:**
- دیدن دقیق محل خطا
- debugging سریع‌تر
- شناسایی ریشه مشکل

---

## 🎨 فاز 2: Structured Logging با Decorators

### فایل جدید: `logging_decorators.py`

این فایل شامل 3 decorator اصلی است:

#### 2.1. `@log_action_execution`

**کاربرد:** لاگ خودکار اجرای تمام Actions

**ویژگی‌ها:**
- ✅ ثبت زمان شروع و پایان
- ✅ محاسبه duration_ms
- ✅ ثبت خطاها با stack trace
- ✅ اضافه کردن correlation_id

**نحوه استفاده:**
```python
class SendEmailAction(ActionHandler):
    @log_action_execution  # ✅ اضافه کردن decorator
    def execute(self, context, config, node_results):
        # ... کد action
```

#### 2.2. `@log_trigger_execution`

**کاربرد:** لاگ خودکار اجرای تمام Triggers

**مشابه log_action_execution اما برای triggers**

#### 2.3. `@log_node_execution`

**کاربرد:** Decorator factory برای انواع مختلف nodeها

**نحوه استفاده:**
```python
@log_node_execution("condition")
def execute_condition(self, ...):
    # ... کد
```

### Actions به‌روز شده با Decorators:

✅ **Communication Actions:**
- `SendEmailAction`
- `SendTelegramAction`
- `CreateNotificationAction`

✅ **Utility Actions:**
- `SetVariableAction`
- `LogAction`
- `HttpRequestAction`

✅ **Document Actions:**
- `CreateDocumentAction`
- `CreateInvoiceAction`
- `UpdateInventoryAction`

---

## 📈 فاز 3: Analytics API Endpoints

### 3.1. Workflow Errors Analytics

**Endpoint:**
```
GET /businesses/{business_id}/workflows/analytics/errors
```

**Parameters:**
- `days`: تعداد روزهای گذشته (1-90، پیش‌فرض: 7)
- `workflow_id`: فیلتر بر اساس workflow خاص (اختیاری)

**Response Example:**
```json
{
  "total_errors": 42,
  "unique_error_types": 5,
  "period_days": 7,
  "errors_by_type": [
    {
      "error_type": "ValueError",
      "count": 15,
      "percentage": 35.71,
      "last_occurrence": "2025-12-04T10:30:00Z",
      "first_occurrence": "2025-12-01T08:15:00Z"
    }
  ]
}
```

**کاربردها:**
- شناسایی رایج‌ترین خطاها
- تحلیل روند خطاها
- اولویت‌بندی رفع باگ‌ها

### 3.2. Workflow Performance Analytics

**Endpoint:**
```
GET /businesses/{business_id}/workflows/analytics/performance
```

**Parameters:**
- `days`: تعداد روزهای گذشته (1-365، پیش‌فرض: 30)
- `workflow_id`: فیلتر بر اساس workflow خاص (اختیاری)

**Response Example:**
```json
{
  "period_days": 30,
  "workflows": [
    {
      "workflow_id": 123,
      "workflow_name": "ارسال ایمیل خوشامدگویی",
      "workflow_status": "فعال",
      "total_executions": 1250,
      "successful": 1230,
      "failed": 20,
      "success_rate": 98.4,
      "avg_duration_seconds": 2.34,
      "min_duration_seconds": 1.12,
      "max_duration_seconds": 8.56
    }
  ]
}
```

**کاربردها:**
- نظارت بر عملکرد workflows
- شناسایی workflows کند
- محاسبه نرخ موفقیت

### 3.3. Execution Timeline

**Endpoint:**
```
GET /businesses/{business_id}/workflows/{workflow_id}/executions/{execution_id}/timeline
```

**Response Example:**
```json
{
  "execution": {
    "id": 456,
    "workflow_id": 123,
    "workflow_name": "ارسال ایمیل خوشامدگویی",
    "status": "تکمیل شده",
    "duration_seconds": 2.34
  },
  "timeline": [
    {
      "timestamp": "2025-12-04T10:30:00Z",
      "level": "info",
      "message": "Workflow started",
      "node_id": null,
      "data": {...}
    }
  ],
  "node_statistics": [
    {
      "node_id": "trigger_1",
      "node_type": "trigger",
      "executions": 1,
      "errors": 0,
      "total_duration_ms": 45.23,
      "avg_duration_ms": 45.23
    }
  ],
  "summary": {
    "total_logs": 15,
    "total_nodes": 5,
    "error_count": 0
  }
}
```

**کاربردها:**
- debugging دقیق اجرای workflow
- شناسایی bottleneck ها
- بررسی flow اجرا

---

## 🔔 فاز 4: Alert System

### پیاده‌سازی هوشمند هشدار

**مکان:** `WorkflowEngine._send_error_alert`

### ویژگی‌ها:

#### 4.1. کانال‌های هشدار

سیستم از 3 کانال پشتیبانی می‌کند:

1. **In-App Notification** (پیش‌فرض)
   - ارسال notification به داخل سیستم
   - قابل مشاهده در بخش notifications

2. **Email**
   - ارسال ایمیل به owner کسب‌وکار
   - شامل جزئیات کامل خطا

3. **Telegram**
   - ارسال پیام به تلگرام owner
   - نیاز به اتصال تلگرام دارد

#### 4.2. تنظیمات Alert

تنظیمات در فیلد `settings` جدول `workflows` ذخیره می‌شود:

```json
{
  "alerts": {
    "enabled": true,
    "channels": ["inapp", "email", "telegram"]
  }
}
```

#### 4.3. محتوای هشدار

```
⚠️ خطا در اجرای workflow: نام Workflow

📋 Workflow: ارسال ایمیل خوشامدگویی
🔢 Execution ID: 456
🔗 Correlation ID: a1b2c3d4-...
⚠️ خطا: Failed to send email: Connection timeout

🕒 زمان: 2025-12-04 10:30:00 UTC

جزئیات بیشتر در بخش لاگ‌های workflow موجود است.
```

#### 4.4. Error Handling در Alert System

- ✅ عدم ارسال alert نباید workflow را متوقف کند
- ✅ تمام خطاها لاگ می‌شوند
- ✅ در صورت فعال نبودن، alert ارسال نمی‌شود

---

## 🔍 نحوه استفاده

### 1. فعال‌سازی Alert برای یک Workflow

```python
# هنگام ایجاد یا به‌روزرسانی workflow
workflow.settings = {
    "alerts": {
        "enabled": True,
        "channels": ["inapp", "email"]  # یا ["telegram"]
    }
}
```

### 2. مشاهده Analytics

**Frontend:**
```typescript
// دریافت آمار خطاها
const errors = await api.get(`/businesses/${businessId}/workflows/analytics/errors?days=7`);

// دریافت آمار عملکرد
const performance = await api.get(`/businesses/${businessId}/workflows/analytics/performance?days=30`);

// دریافت timeline
const timeline = await api.get(
  `/businesses/${businessId}/workflows/${workflowId}/executions/${executionId}/timeline`
);
```

### 3. استفاده از Correlation ID برای Debugging

تمام لاگ‌های یک workflow دارای یک `correlation_id` یکسان هستند:

```python
# در لاگ‌ها
logger.info(
    "Action executed",
    extra={
        "correlation_id": self.correlation_id,
        # ...
    }
)
```

**جستجو در لاگ‌ها:**
```bash
grep "correlation_id.*a1b2c3d4" /var/log/hesabix-api.log
```

---

## 📊 متریک‌های قابل نظارت

### 1. Performance Metrics

- ✅ `duration_ms` - زمان اجرای هر node (میلی‌ثانیه)
- ✅ `total_duration_ms` - زمان کل اجرای workflow
- ✅ `avg_duration_seconds` - میانگین زمان اجرا
- ✅ `min_duration_seconds` - کمترین زمان
- ✅ `max_duration_seconds` - بیشترین زمان

### 2. Success Metrics

- ✅ `total_executions` - تعداد کل اجراها
- ✅ `successful` - تعداد اجراهای موفق
- ✅ `failed` - تعداد اجراهای ناموفق
- ✅ `success_rate` - نرخ موفقیت (درصد)

### 3. Error Metrics

- ✅ `error_type` - نوع خطا
- ✅ `error_count` - تعداد خطاها
- ✅ `error_percentage` - درصد خطا
- ✅ `last_occurrence` - آخرین زمان وقوع
- ✅ `first_occurrence` - اولین زمان وقوع

---

## 🎯 Best Practices

### 1. استفاده از Correlation ID

```python
# همیشه correlation_id را در لاگ‌ها قرار دهید
logger.info(
    "Processing started",
    extra={
        "correlation_id": context.get("correlation_id"),
        "business_id": context.get("business_id")
    }
)
```

### 2. Error Handling

```python
# همیشه error_type و stack_trace را لاگ کنید
except Exception as e:
    logger.error(
        "Operation failed",
        extra={
            "error_type": type(e).__name__,
            "error_message": str(e),
            "stack_trace": traceback.format_exc()
        },
        exc_info=True
    )
```

### 3. Performance Monitoring

```python
# زمان عملیات‌های مهم را اندازه بگیرید
start_time = time.time()
# ... انجام عملیات
duration_ms = (time.time() - start_time) * 1000

logger.info(
    "Operation completed",
    extra={"duration_ms": round(duration_ms, 2)}
)
```

---

## 🔧 تنظیمات پیشنهادی

### 1. تنظیمات Logging در Production

```python
# در settings.py یا config
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'json': {
            '()': 'pythonjsonlogger.jsonlogger.JsonFormatter',
            'format': '%(asctime)s %(name)s %(levelname)s %(correlation_id)s %(message)s'
        }
    },
    'handlers': {
        'file': {
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': '/var/log/hesabix-workflows.log',
            'maxBytes': 104857600,  # 100MB
            'backupCount': 10,
            'formatter': 'json'
        }
    },
    'loggers': {
        'app.services.workflow': {
            'handlers': ['file'],
            'level': 'INFO',
            'propagate': False
        }
    }
}
```

### 2. تنظیمات Alert

```json
{
  "alerts": {
    "enabled": true,
    "channels": ["inapp", "email"],
    "throttle": {
      "enabled": true,
      "max_alerts_per_hour": 10
    }
  }
}
```

---

## 🧪 تست‌ها

### 1. تست Logging

```python
def test_workflow_logging():
    """تست لاگینگ workflow"""
    engine = WorkflowEngine(db, business_id=1, user_id=1)
    
    # بررسی correlation_id
    assert engine.correlation_id is not None
    assert len(engine.correlation_id) == 36  # UUID format
    
    # اجرای workflow
    execution = engine.execute_workflow(workflow, trigger_data)
    
    # بررسی لاگ‌ها
    logs = db.query(WorkflowLog).filter_by(execution_id=execution.id).all()
    assert len(logs) > 0
    
    # بررسی وجود correlation_id در لاگ‌ها
    for log in logs:
        if log.data:
            assert log.data.get("correlation_id") == engine.correlation_id
```

### 2. تست Alert System

```python
def test_alert_system():
    """تست سیستم هشدار"""
    # فعال کردن alerts
    workflow.settings = {
        "alerts": {
            "enabled": True,
            "channels": ["inapp"]
        }
    }
    
    # ایجاد خطای عمدی
    with pytest.raises(Exception):
        engine.execute_workflow(workflow, invalid_data)
    
    # بررسی ارسال notification
    notifications = db.query(Notification).filter_by(
        user_id=business.owner_id,
        event_key="workflow.error"
    ).all()
    
    assert len(notifications) > 0
```

---

## 📚 مراجع و منابع

### 1. فایل‌های مرتبط

- `workflow_engine.py` - موتور اصلی
- `logging_decorators.py` - Decorators
- `workflows.py` - API endpoints
- `workflow.py` - Models

### 2. مستندات مرتبط

- [Workflow System Overview](./WORKFLOW_IMPROVEMENTS_PROPOSAL.md)
- [Workflow Trigger Fix](../WORKFLOW_TRIGGER_FIX.md)
- [Visual Editor Scenario](./WORKFLOW_VISUAL_EDITOR_SCENARIO.md)

### 3. ابزارهای توصیه شده

- **ELK Stack** - برای log aggregation
- **Grafana** - برای visualization
- **Prometheus** - برای metrics
- **Sentry** - برای error tracking

---

## 🎉 نتیجه‌گیری

این پیاده‌سازی شامل موارد زیر است:

✅ **فاز 1:** Correlation ID, Duration Metrics, Stack Traces  
✅ **فاز 2:** Logging Decorators برای تمام Actions  
✅ **فاز 3:** 3 API Endpoint برای Analytics  
✅ **فاز 4:** Alert System کامل با 3 کانال  

### مزایای کلی:

- 🔍 **Debugging آسان‌تر** با correlation_id
- 📊 **Monitoring بهتر** با analytics endpoints
- ⚡ **Performance Tracking** با duration metrics
- 🔔 **هشدار سریع** با alert system
- 📈 **تحلیل بهتر** با structured logging

---

**نسخه:** 1.0.0  
**تاریخ:** 2025-12-04  
**نویسنده:** Hesabix Development Team


