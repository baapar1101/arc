# 🚀 راه‌اندازی Notification Moderation Worker

---

## 📋 مقدمه

این Worker به صورت خودکار قالب‌های نوتیفیکیشن را بررسی و تایید می‌کند.

**قابلیت‌ها**:
- ✅ بررسی خودکار با AI (از طریق AIService سیستم)
- ✅ قابل مدیریت از پنل مدیر سیستم
- ✅ قابل مشاهده در بخش Monitoring
- ✅ لاگ‌گیری از طریق journalctl

---

## 🛠️ راه‌اندازی با Systemd

### مرحله 1: کپی فایل سرویس

```bash
# کپی فایل service به systemd
sudo cp /var/www/ark/hesabixAPI/deployment/systemd/hesabix-notification-moderation.service \
    /etc/systemd/system/

# تنظیم مجوزها
sudo chmod 644 /etc/systemd/system/hesabix-notification-moderation.service
```

### مرحله 2: Reload و فعال‌سازی

```bash
# Reload daemon
sudo systemctl daemon-reload

# فعال‌سازی سرویس (اجرا خودکار در startup)
sudo systemctl enable hesabix-notification-moderation

# شروع سرویس
sudo systemctl start hesabix-notification-moderation
```

### مرحله 3: بررسی وضعیت

```bash
# بررسی وضعیت
sudo systemctl status hesabix-notification-moderation

# مشاهده لاگ‌های زنده
sudo journalctl -u hesabix-notification-moderation -f

# مشاهده 100 خط آخر لاگ
sudo journalctl -u hesabix-notification-moderation -n 100
```

**خروجی مورد انتظار**:
```
● hesabix-notification-moderation.service - Hesabix Notification Moderation Worker
   Loaded: loaded (/etc/systemd/system/hesabix-notification-moderation.service; enabled)
   Active: active (running) since ...
```

---

## 🎛️ مدیریت از پنل Admin

### دسترسی به بخش Monitoring

```
مسیر: /user/profile/system-settings/monitoring
```

### قابلیت‌های پنل

```
┌──────────────────────────────────────────┐
│  📊 سرویس‌های سیستم                      │
├──────────────────────────────────────────┤
│                                          │
│  🟢 API Server           [فعال]         │
│  🟢 Database            [فعال]         │
│  🟢 Redis               [فعال]         │
│  🟢 RQ Workers          [فعال]         │
│  🟢 Notification Moderation [فعال]     │
│     • صف در انتظار: 3                  │
│     • بررسی شده امروز: 45              │
│     • آخرین فعالیت: 2 دقیقه پیش        │
│     [Restart] [Logs] [Details]         │
│                                          │
└──────────────────────────────────────────┘
```

---

## 🔧 دستورات مدیریت

### Start/Stop/Restart

```bash
# شروع
sudo systemctl start hesabix-notification-moderation

# توقف
sudo systemctl stop hesabix-notification-moderation

# Restart
sudo systemctl restart hesabix-notification-moderation

# بررسی وضعیت
sudo systemctl is-active hesabix-notification-moderation
```

### Enable/Disable

```bash
# فعال‌سازی (اجرا خودکار در startup)
sudo systemctl enable hesabix-notification-moderation

# غیرفعال‌سازی
sudo systemctl disable hesabix-notification-moderation
```

### مشاهده لاگ‌ها

```bash
# لاگ‌های زنده
sudo journalctl -u hesabix-notification-moderation -f

# لاگ‌های امروز
sudo journalctl -u hesabix-notification-moderation --since today

# لاگ‌های یک ساعت اخیر
sudo journalctl -u hesabix-notification-moderation --since "1 hour ago"

# جستجو در لاگ‌ها
sudo journalctl -u hesabix-notification-moderation | grep "ERROR"
```

---

## 📡 API های مدیریت

### دریافت وضعیت همه سرویس‌ها

```http
GET /api/v1/admin/monitoring/services/status
Authorization: Bearer {token}
```

**Response**:
```json
{
  "data": {
    "api_server": {"status": "online", ...},
    "database": {"status": "online", ...},
    "redis": {"status": "online", ...},
    "workers": {"status": "online", ...},
    "notification_moderation": {
      "status": "online",
      "is_active": true,
      "queue": {
        "pending": 3,
        "reviewed_today": 45
      },
      "last_activity": "2025-01-06T10:30:00Z"
    }
  }
}
```

### دریافت وضعیت Worker

```http
GET /api/v1/admin/monitoring/services/notification_moderation/status
Authorization: Bearer {token}
```

### Restart کردن Worker

```http
POST /api/v1/admin/system-services/restart?service_name=hesabix-notification-moderation
Authorization: Bearer {token}
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

### دریافت لاگ‌ها

```http
GET /api/v1/admin/system-services/logs?service_name=hesabix-notification-moderation&lines=100
Authorization: Bearer {token}
```

---

## 🔍 Troubleshooting

### Worker اجرا نمی‌شود

```bash
# بررسی خطا
sudo systemctl status hesabix-notification-moderation
sudo journalctl -u hesabix-notification-moderation -n 50

# مشکلات رایج:
# 1. مسیر اشتباه
# 2. دسترسی‌های فایل
# 3. مشکل در اتصال به دیتابیس
```

### Database connection error

```bash
# بررسی دیتابیس فعال است
sudo systemctl status mysql

# بررسی environment variables
sudo systemctl cat hesabix-notification-moderation
```

### Worker متوقف می‌شود

```bash
# افزایش memory limit
sudo systemctl edit hesabix-notification-moderation

# اضافه کردن:
[Service]
MemoryLimit=1G
```

---

## 📊 Monitoring Metrics

### آمار Worker

```sql
-- صف در انتظار
SELECT COUNT(*) as pending
FROM notification_moderation_queue
WHERE status IN ('pending', 'ai_reviewing');

-- بررسی شده امروز
SELECT COUNT(*) as reviewed_today
FROM notification_moderation_queue
WHERE DATE(completed_at) = CURDATE()
  AND status = 'completed';

-- میانگین زمان بررسی
SELECT AVG(TIMESTAMPDIFF(SECOND, created_at, completed_at)) as avg_seconds
FROM notification_moderation_queue
WHERE completed_at IS NOT NULL
  AND DATE(completed_at) = CURDATE();
```

### لاگ‌های Worker

```bash
# تعداد بررسی‌های موفق
sudo journalctl -u hesabix-notification-moderation --since today | grep "✅ بررسی قالب" | wc -l

# تعداد خطاها
sudo journalctl -u hesabix-notification-moderation --since today | grep "ERROR" | wc -l
```

---

## ⚙️ تنظیمات پیشرفته

### تغییر Interval بررسی

**فایل**: `app/workers/notification_moderation_worker.py`

```python
# خط 167
async def run_worker_loop(interval_seconds: int = 60):  # پیش‌فرض: 60 ثانیه
```

برای تغییر، باید Worker را با argument اجرا کرد:

```python
# در فایل service:
ExecStart=/usr/bin/python3 -c "import asyncio; from app.workers.notification_moderation_worker import run_worker_loop; asyncio.run(run_worker_loop(interval_seconds=30))"
```

### محدودیت منابع

```bash
# ویرایش سرویس
sudo systemctl edit hesabix-notification-moderation

# اضافه کردن محدودیت‌ها:
[Service]
MemoryLimit=512M
CPUQuota=50%
TasksMax=10
```

---

## 📈 بهینه‌سازی Performance

### کاهش Load دیتابیس

```python
# در worker، افزایش interval:
await asyncio.sleep(120)  # هر 2 دقیقه یک بار
```

### Batch Processing

```python
# افزایش تعداد آیتم‌های پردازش شده:
pending_items = self.queue_repo.get_pending(status='pending', limit=20)
```

---

## ✅ Checklist راه‌اندازی

- [ ] کپی فایل `.service` به `/etc/systemd/system/`
- [ ] `systemctl daemon-reload`
- [ ] `systemctl enable hesabix-notification-moderation`
- [ ] `systemctl start hesabix-notification-moderation`
- [ ] بررسی وضعیت: `systemctl status ...`
- [ ] مشاهده لاگ: `journalctl -u ... -f`
- [ ] تست از پنل Admin
- [ ] بررسی Monitoring در `/user/profile/system-settings/monitoring`

---

## 🎯 یکپارچگی با Monitoring

### دسترسی از پنل

```
1. ورود به پنل مدیر
2. Profile → System Settings → Monitoring
3. مشاهده "Notification Moderation Worker"
4. قابلیت‌ها:
   ✅ مشاهده وضعیت (online/offline)
   ✅ مشاهده آمار صف
   ✅ Restart کردن
   ✅ مشاهده لاگ‌ها
   ✅ فعال/غیرفعال کردن
```

### API های در دسترس

| Endpoint | Method | عملیات |
|----------|--------|--------|
| `/admin/monitoring/services/status` | GET | وضعیت همه سرویس‌ها |
| `/admin/monitoring/services/notification_moderation/status` | GET | وضعیت Worker |
| `/admin/system-services/restart?service_name=hesabix-notification-moderation` | POST | Restart |
| `/admin/system-services/logs?service_name=hesabix-notification-moderation` | GET | لاگ‌ها |
| `/admin/system-services/status/all` | GET | وضعیت تمام سرویس‌ها |

---

## 🎉 نتیجه

Worker نوتیفیکیشن حالا:
- ✅ به عنوان یک سرویس systemd اجرا می‌شود
- ✅ در پنل Monitoring قابل مشاهده است
- ✅ از طریق API قابل مدیریت است
- ✅ لاگ‌های آن در journalctl ذخیره می‌شود
- ✅ می‌توان آن را restart/stop/start کرد
- ✅ آمار real-time از صف نمایش داده می‌شود

**همه چیز یکپارچه است!** 🎊


