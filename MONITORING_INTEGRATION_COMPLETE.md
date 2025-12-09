# ✅ یکپارچه‌سازی Worker نوتیفیکیشن با سیستم Monitoring

تاریخ: 1403/09/16

---

## 🎯 هدف

یکپارچه‌سازی `Notification Moderation Worker` با سیستم Monitoring موجود تا:
1. ✅ قابل مشاهده در پنل مدیر باشد
2. ✅ قابل مدیریت (start/stop/restart) باشد
3. ✅ آمار real-time داشته باشد
4. ✅ لاگ‌ها قابل دسترسی باشند

---

## ✅ کارهای انجام شده

### 1. اضافه کردن به ALLOWED_SERVICES

**فایل**: `adapters/api/v1/admin/system_services.py`

```python
ALLOWED_SERVICES = [
    "hesabix-api",
    "hesabix-rq-worker",
    "hesabix-notification-moderation"  # ✨ جدید
]
```

**نتیجه**: حالا این سرویس قابل مدیریت از طریق API است.

### 2. اضافه کردن متد بررسی در ServiceMonitoringService

**فایل**: `app/services/monitoring_service.py`

```python
def check_notification_moderation_worker(self) -> Dict[str, Any]:
    """بررسی وضعیت Notification Moderation Worker"""
    
    # بررسی systemd service
    is_active = systemctl is-active hesabix-notification-moderation
    
    # دریافت آمار از دیتابیس
    - تعداد در صف (pending)
    - تعداد بررسی شده امروز
    - آخرین فعالیت
    
    return {
        "status": "online" | "offline",
        "queue": {"pending": X, "reviewed_today": Y},
        "last_activity": "ISO datetime"
    }
```

**نتیجه**: وضعیت Worker به صورت real-time قابل دریافت است.

### 3. اضافه کردن به check_all_services

```python
def check_all_services(self):
    services = {}
    # ...
    services["notification_moderation"] = self.check_notification_moderation_worker()  # ✨
    return services
```

**نتیجه**: Worker در لیست سرویس‌ها نمایش داده می‌شود.

### 4. اضافه کردن به Monitoring API

**فایل**: `adapters/api/v1/admin/monitoring.py`

```python
@router.get("/services/{service_name}/status")
def get_service_status(...):
    # ...
    elif service_name == "notification_moderation":  # ✨
        status = service.check_notification_moderation_worker()
    # ...
```

**نتیجه**: Endpoint مخصوص برای این Worker.

### 5. ایجاد Systemd Service File

**فایل**: `deployment/systemd/hesabix-notification-moderation.service`

```ini
[Unit]
Description=Hesabix Notification Moderation Worker
After=network.target mysql.service redis.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/ark/hesabixAPI
ExecStart=/usr/bin/python3 -m app.workers.notification_moderation_worker
Restart=always
StandardOutput=journal

[Install]
WantedBy=multi-user.target
```

**نتیجه**: Worker به عنوان systemd service قابل اجراست.

### 6. اضافه کردن به Background Tasks

**فایل**: `app/main.py`

```python
@application.on_event("startup")
async def _start_background_jobs():
    # ...
    # Notification moderation: هر 60 ثانیه یکبار
    from app.workers.notification_moderation_worker import run_worker_loop
    asyncio.create_task(run_worker_loop(60))  # ✨
    # ...
```

**نتیجه**: Worker به صورت خودکار با API start می‌شود.

---

## 📊 **دو روش اجرا**

### روش 1: Embedded در API (پیش‌فرض)

Worker به صورت خودکار با API اجرا می‌شود:

```bash
# شروع API
systemctl start hesabix-api

# Worker هم شروع می‌شود (background task)
```

**مزایا**:
- راه‌اندازی آسان‌تر
- بدون نیاز به سرویس جداگانه
- مناسب برای development و small deployments

**معایب**:
- اگر API restart شود، Worker هم قطع می‌شود
- منابع مشترک

### روش 2: Standalone Service (توصیه شده برای Production)

Worker به صورت مستقل اجرا می‌شود:

```bash
# کپی فایل service
sudo cp deployment/systemd/hesabix-notification-moderation.service /etc/systemd/system/

# فعال‌سازی
sudo systemctl daemon-reload
sudo systemctl enable hesabix-notification-moderation
sudo systemctl start hesabix-notification-moderation
```

**مزایا**:
- جداسازی concerns
- Scale مستقل
- Restart مستقل از API

**معایب**:
- نیاز به مدیریت جداگانه

---

## 🎛️ **مدیریت از پنل Admin**

### مسیر دسترسی

```
/user/profile/system-settings/monitoring
```

### امکانات پنل

```
┌──────────────────────────────────────────────────┐
│  📊 وضعیت سرویس‌های سیستم                        │
├──────────────────────────────────────────────────┤
│                                                  │
│  🟢 API Server              [فعال] [Restart]    │
│  🟢 Database                [فعال] [Details]    │
│  🟢 Redis                   [فعال] [Details]    │
│  🟢 RQ Workers              [فعال] [Restart]    │
│  🟢 Notification Moderation [فعال] [Restart]    │
│     ├─ صف در انتظار: 3                          │
│     ├─ بررسی شده امروز: 45                      │
│     ├─ آخرین فعالیت: 2 دقیقه پیش                │
│     └─ [مشاهده لاگ] [جزئیات صف]                │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## 📡 **API های قابل استفاده**

### 1. دریافت وضعیت همه سرویس‌ها

```http
GET /api/v1/admin/monitoring/services/status
```

**Response**:
```json
{
  "data": {
    "notification_moderation": {
      "status": "online",
      "is_active": true,
      "queue": {
        "pending": 3,
        "reviewed_today": 45
      },
      "last_activity": "2025-01-06T14:30:00Z",
      "service_name": "hesabix-notification-moderation",
      "last_check": "2025-01-06T14:35:00Z"
    }
  }
}
```

### 2. دریافت وضعیت Worker

```http
GET /api/v1/admin/monitoring/services/notification_moderation/status
```

### 3. Restart کردن Worker

```http
POST /api/v1/admin/system-services/restart?service_name=hesabix-notification-moderation
```

**Response**:
```json
{
  "data": {
    "service": "hesabix-notification-moderation",
    "status": "restarted",
    "is_active": true,
    "message": "سرویس hesabix-notification-moderation با موفقیت restart شد"
  }
}
```

### 4. دریافت لاگ‌ها

```http
GET /api/v1/admin/system-services/logs?service_name=hesabix-notification-moderation&lines=100
```

---

## 🔍 **مثال استفاده در Frontend**

### دریافت وضعیت

```dart
// در صفحه monitoring

class NotificationModerationStatus extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getWorkerStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        
        final status = snapshot.data!;
        final isOnline = status['status'] == 'online';
        final queue = status['queue'];
        
        return Card(
          child: ListTile(
            leading: Icon(
              Icons.auto_awesome,
              color: isOnline ? Colors.green : Colors.red,
            ),
            title: Text('AI Moderation Worker'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('صف در انتظار: ${queue['pending']}'),
                Text('بررسی شده امروز: ${queue['reviewed_today']}'),
              ],
            ),
            trailing: IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () => _restartWorker(),
            ),
          ),
        );
      },
    );
  }
  
  Future<Map<String, dynamic>> _getWorkerStatus() async {
    final response = await apiClient.get(
      '/api/v1/admin/monitoring/services/notification_moderation/status'
    );
    return response.data['data'];
  }
  
  Future<void> _restartWorker() async {
    await apiClient.post(
      '/api/v1/admin/system-services/restart?service_name=hesabix-notification-moderation'
    );
    // Refresh UI
    setState(() {});
  }
}
```

---

## 🔧 **دستورات مفید**

### بررسی وضعیت

```bash
# وضعیت سرویس
sudo systemctl status hesabix-notification-moderation

# آیا فعال است؟
sudo systemctl is-active hesabix-notification-moderation

# آیا enable است؟
sudo systemctl is-enabled hesabix-notification-moderation
```

### مدیریت سرویس

```bash
# شروع
sudo systemctl start hesabix-notification-moderation

# توقف
sudo systemctl stop hesabix-notification-moderation

# Restart
sudo systemctl restart hesabix-notification-moderation

# فعال‌سازی (auto-start)
sudo systemctl enable hesabix-notification-moderation

# غیرفعال‌سازی
sudo systemctl disable hesabix-notification-moderation
```

### مشاهده لاگ‌ها

```bash
# لاگ‌های زنده
sudo journalctl -u hesabix-notification-moderation -f

# 100 خط آخر
sudo journalctl -u hesabix-notification-moderation -n 100

# لاگ‌های امروز
sudo journalctl -u hesabix-notification-moderation --since today

# جستجو
sudo journalctl -u hesabix-notification-moderation | grep "ERROR"
sudo journalctl -u hesabix-notification-moderation | grep "✅"
```

---

## 📈 **Monitoring Metrics**

### نمایش در پنل

| Metric | توضیح | مثال |
|--------|-------|------|
| **Status** | وضعیت سرویس | online/offline |
| **Is Active** | آیا در systemd فعال است | true/false |
| **Pending** | تعداد در صف | 3 |
| **Reviewed Today** | بررسی شده امروز | 45 |
| **Last Activity** | آخرین فعالیت | 2 دقیقه پیش |

### Query های مفید

```sql
-- آمار کلی صف
SELECT 
    status,
    COUNT(*) as count
FROM notification_moderation_queue
GROUP BY status;

-- بررسی‌های امروز
SELECT 
    ai_decision,
    COUNT(*) as count
FROM notification_moderation_queue
WHERE DATE(ai_reviewed_at) = CURDATE()
GROUP BY ai_decision;

-- میانگین زمان بررسی
SELECT 
    AVG(TIMESTAMPDIFF(SECOND, created_at, ai_reviewed_at)) as avg_seconds
FROM notification_moderation_queue
WHERE ai_reviewed_at IS NOT NULL;
```

---

## 🚨 **Alert ها و هشدارها**

### شرایط هشدار

Worker در سیستم monitoring بررسی می‌شود و در صورت بروز مشکل، alert ارسال می‌شود:

| شرط | سطح | پیام |
|-----|------|------|
| Worker offline > 5 min | 🔴 Critical | Worker غیرفعال است |
| صف > 50 | 🟡 Warning | صف بررسی شلوغ است |
| آخرین فعالیت > 10 min | 🟡 Warning | Worker idle است |

---

## 🔄 **سناریوهای مختلف**

### سناریو 1: راه‌اندازی اولیه (Development)

```bash
# فقط API را start کنید
cd /var/www/ark/hesabixAPI
python -m app.main

# Worker به صورت خودکار start می‌شود
# قابل مشاهده در monitoring panel
```

### سناریو 2: راه‌اندازی Production

```bash
# نصب service
sudo cp deployment/systemd/hesabix-notification-moderation.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hesabix-notification-moderation
sudo systemctl start hesabix-notification-moderation

# بررسی
sudo systemctl status hesabix-notification-moderation
```

### سناریو 3: مشکل در Worker

```bash
# 1. بررسی لاگ
sudo journalctl -u hesabix-notification-moderation -n 50

# 2. Restart از پنل Admin
# یا
sudo systemctl restart hesabix-notification-moderation

# 3. بررسی دیتابیس
mysql -u root -p hesabix_db -e "SELECT * FROM notification_moderation_queue WHERE status='pending';"
```

---

## 📱 **نمایش در Frontend**

### کامپوننت Monitoring

```jsx
<ServiceCard
  name="AI Moderation"
  icon="🤖"
  status={workerStatus.status}
  metrics={[
    { label: "در صف", value: workerStatus.queue.pending },
    { label: "امروز", value: workerStatus.queue.reviewed_today },
    { label: "آخرین", value: formatTime(workerStatus.last_activity) }
  ]}
  actions={[
    { label: "Restart", onClick: () => restartWorker() },
    { label: "لاگ‌ها", onClick: () => showLogs() },
    { label: "جزئیات صف", onClick: () => goToModerationQueue() }
  ]}
/>
```

---

## 🎯 **مسیرهای دسترسی**

### در پنل مدیر

1. **Monitoring Overview**:
   ```
   /user/profile/system-settings/monitoring
   ```
   نمایش کلی وضعیت Worker + آمار

2. **Service Management**:
   ```
   /user/profile/system-settings/services
   ```
   مدیریت (start/stop/restart)

3. **Moderation Queue**:
   ```
   /admin/notification-moderation/queue
   ```
   مشاهده صف بررسی

4. **Service Logs**:
   ```
   /user/profile/system-settings/logs
   ```
   مشاهده لاگ‌های Worker

---

## ✅ **Checklist یکپارچه‌سازی**

- [x] اضافه به `ALLOWED_SERVICES`
- [x] ایجاد متد `check_notification_moderation_worker()`
- [x] اضافه به `check_all_services()`
- [x] اضافه به Monitoring API endpoint
- [x] ایجاد Systemd service file
- [x] اضافه به background tasks در `main.py`
- [x] به‌روزرسانی Worker با logging بهتر
- [x] ایجاد مستندات deployment
- [x] تست lint errors (0 خطا)

---

## 🎊 **نتیجه نهایی**

Worker نوتیفیکیشن حالا:

✅ **قابل مشاهده** در `/user/profile/system-settings/monitoring`  
✅ **قابل مدیریت** (restart/stop/start) از پنل  
✅ **آمار real-time** از صف و فعالیت‌ها  
✅ **لاگ‌های جامع** در journalctl  
✅ **یکپارچه** با سایر سرویس‌ها  
✅ **قابل اتکا** با auto-restart  

**همه چیز در یک پنل واحد قابل مدیریت است!** 🚀

---

## 📸 پیش‌نمایش در Monitoring Panel

```
┌─────────────────────────────────────────────────┐
│  Notification AI Moderation Worker              │
├─────────────────────────────────────────────────┤
│  🟢 Online                                      │
│                                                 │
│  📊 آمار:                                       │
│  • در صف: 3 قالب                               │
│  • بررسی شده امروز: 45 قالب                    │
│  • آخرین فعالیت: 2 دقیقه پیش                   │
│                                                 │
│  🎛️ عملیات:                                    │
│  [🔄 Restart] [📋 Logs] [📊 Queue Details]     │
│                                                 │
│  💡 نکات:                                       │
│  • از AIService سیستم استفاده می‌کند           │
│  • رایگان برای کسب‌وکارها                      │
│  • Auto-retry در صورت خطا                      │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

**تکمیل شد!** ✨


