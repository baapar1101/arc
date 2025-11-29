# راهنمای نصب و راه‌اندازی RQ Worker

## فهرست مطالب

1. [مقدمه](#مقدمه)
2. [RQ Worker چیست؟](#rq-worker-چیست)
3. [نصب و راه‌اندازی](#نصب-و-راه‌اندازی)
4. [مدیریت سرویس](#مدیریت-سرویس)
5. [بررسی و مانیتورینگ](#بررسی-و-مانیتورینگ)
6. [عیب‌یابی](#عیب‌یابی)
7. [ساخت سرویس Systemd](#ساخت-سرویس-systemd)
8. [سوالات متداول](#سوالات-متداول)

---

## مقدمه

RQ (Redis Queue) Worker یک سرویس Background است که برای اجرای کارهای زمان‌بر و غیرهمزمان (Asynchronous) در پس‌زمینه استفاده می‌شود. این سرویس باعث می‌شود که API Server مسدود نشود و کارهای سنگین در پس‌زمینه اجرا شوند.

---

## RQ Worker چیست؟

### تعریف

**RQ Worker** یک پردازش‌گر Background است که:
- کارهای زمان‌بر را از Redis Queue دریافت می‌کند
- آنها را به ترتیب اولویت اجرا می‌کند
- نتیجه را در Redis ذخیره می‌کند
- امکان Retry برای کارهای ناموفق را فراهم می‌کند

### کاربردهای RQ Worker

1. **ارسال ایمیل** (`email` queue)
   - ارسال ایمیل‌های تایید
   - اطلاع‌رسانی‌ها
   - گزارش‌های دوره‌ای

2. **تولید گزارش** (`reports` queue)
   - گزارش‌های PDF/Excel
   - گزارش‌های حسابداری
   - آمار و تحلیل‌ها

3. **Export داده‌ها** (`exports` queue)
   - Export به Excel
   - Export به CSV
   - Export داده‌های حجیم

4. **کارهای با اولویت بالا** (`high` queue)
   - کارهای فوری
   - پردازش‌های مهم

5. **کارهای عادی** (`default` queue)
   - کارهای معمولی
   - پردازش‌های استاندارد

6. **کارهای با اولویت پایین** (`low` queue)
   - کارهای غیرضروری
   - پاک‌سازی و بهینه‌سازی

### مزایا

- ✅ جلوگیری از Block شدن API
- ✅ اجرای همزمان چند کار
- ✅ اولویت‌بندی کارها
- ✅ Retry خودکار برای کارهای ناموفق
- ✅ مانیتورینگ و Logging
- ✅ مقیاس‌پذیری (چند Worker)

---

## نصب و راه‌اندازی

### پیش‌نیازها

1. **Redis** باید نصب و فعال باشد
2. **Python 3.8+** و Virtual Environment
3. **RQ Package** در requirements
4. **دسترسی به Redis** از Worker

### مرحله 1: بررسی Redis

```bash
# بررسی وضعیت Redis
systemctl status redis

# یا
redis-cli ping
# باید پاسخ "PONG" بدهد
```

اگر Redis فعال نیست:

```bash
# نصب Redis (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install redis-server

# راه‌اندازی Redis
sudo systemctl start redis
sudo systemctl enable redis

# بررسی
redis-cli ping
```

### مرحله 2: بررسی Dependencies

```bash
cd /var/www/ark/hesabixAPI
source venv/bin/activate

# بررسی نصب RQ
pip list | grep rq

# اگر نصب نیست:
pip install rq redis
```

### مرحله 3: ساخت سرویس Systemd

فایل سرویس قبلاً ایجاد شده است: `/etc/systemd/system/hesabix-rq-worker.service`

اگر نیاز به ساخت مجدد دارید، به بخش [ساخت سرویس Systemd](#ساخت-سرویس-systemd) مراجعه کنید.

### مرحله 4: فعال‌سازی سرویس

```bash
# Reload systemd
sudo systemctl daemon-reload

# فعال کردن startup خودکار
sudo systemctl enable hesabix-rq-worker

# راه‌اندازی سرویس
sudo systemctl start hesabix-rq-worker

# بررسی وضعیت
sudo systemctl status hesabix-rq-worker
```

### مرحله 5: بررسی لاگ‌ها

```bash
# مشاهده لاگ‌های real-time
sudo journalctl -u hesabix-rq-worker -f

# مشاهده آخرین لاگ‌ها
sudo journalctl -u hesabix-rq-worker -n 50

# مشاهده لاگ‌های امروز
sudo journalctl -u hesabix-rq-worker --since today
```

---

## مدیریت سرویس

### دستورات پایه

```bash
# راه‌اندازی
sudo systemctl start hesabix-rq-worker

# متوقف کردن
sudo systemctl stop hesabix-rq-worker

# راه‌اندازی مجدد
sudo systemctl restart hesabix-rq-worker

# مشاهده وضعیت
sudo systemctl status hesabix-rq-worker

# فعال کردن startup خودکار
sudo systemctl enable hesabix-rq-worker

# غیرفعال کردن startup خودکار
sudo systemctl disable hesabix-rq-worker
```

### مشاهده Logs

```bash
# Real-time logs
sudo journalctl -u hesabix-rq-worker -f

# آخرین 100 خط
sudo journalctl -u hesabix-rq-worker -n 100

# Logs با timestamp
sudo journalctl -u hesabix-rq-worker --since "1 hour ago"

# Logs با grep
sudo journalctl -u hesabix-rq-worker | grep ERROR

# Export logs به فایل
sudo journalctl -u hesabix-rq-worker > /tmp/rq-worker.log
```

---

## بررسی و مانیتورینگ

### روش 1: بررسی از طریق Systemd

```bash
# وضعیت سرویس
sudo systemctl status hesabix-rq-worker

# بررسی فعال بودن
systemctl is-active hesabix-rq-worker
# باید "active" باشد

# بررسی فعال بودن در startup
systemctl is-enabled hesabix-rq-worker
# باید "enabled" باشد
```

### روش 2: بررسی از طریق Process

```bash
# بررسی process
ps aux | grep rq_worker

# یا
pgrep -af rq_worker
```

### روش 3: بررسی از طریق Redis

```bash
# اتصال به Redis
redis-cli

# مشاهده Workers
KEYS rq:*
SMEMBERS rq:workers

# مشاهده Queues
KEYS rq:queue:*
LLEN rq:queue:default
LLEN rq:queue:high
LLEN rq:queue:email

# مشاهده Jobs
KEYS rq:job:*

# خروج
exit
```

### روش 4: بررسی از طریق Monitoring UI

در صفحه **مانیتورینگ سیستم**:
1. به تب **سرویس‌ها** بروید
2. وضعیت **Workers** باید "online" باشد
3. تعداد Workers و اطلاعات Queues نمایش داده می‌شود

### روش 5: تست دستی Worker

```bash
cd /var/www/ark/hesabixAPI
source venv/bin/activate

# اجرای دستی Worker
python rq_worker.py
```

اگر Worker به درستی کار کند، باید پیامی شبیه این ببینید:
```
Starting RQ worker for queues: high, default, email, reports, exports, low
```

---

## عیب‌یابی

### مشکل 1: Worker شروع نمی‌شود

**علائم:**
```
● hesabix-rq-worker.service - Hesabix RQ Worker
   Loaded: loaded (/etc/systemd/system/hesabix-rq-worker.service)
   Active: failed (Result: exit-code)
```

**راه‌حل:**

```bash
# بررسی لاگ‌های خطا
sudo journalctl -u hesabix-rq-worker -n 50

# بررسی دسترسی فایل
ls -la /var/www/ark/hesabixAPI/rq_worker.py
ls -la /var/www/ark/hesabixAPI/venv/bin/python

# بررسی دسترسی کاربر
sudo -u www-data ls -la /var/www/ark/hesabixAPI/rq_worker.py

# تست دستی
sudo -u www-data /var/www/ark/hesabixAPI/venv/bin/python /var/www/ark/hesabixAPI/rq_worker.py
```

### مشکل 2: Redis Connection Error

**علائم:**
```
Error: Redis connection not available. Please check Redis configuration.
```

**راه‌حل:**

```bash
# بررسی Redis
systemctl status redis
redis-cli ping

# بررسی تنظیمات Redis در سیستم
# در تنظیمات سیستم → Redis Configuration

# تست Connection از Python
cd /var/www/ark/hesabixAPI
source venv/bin/activate
python -c "from app.core.queue import get_redis_connection; conn = get_redis_connection(); print('OK' if conn else 'FAILED')"
```

### مشکل 3: Worker متوقف می‌شود (Crash)

**علائم:**
- Worker مدام restart می‌شود
- Logs خطا نشان می‌دهد

**راه‌حل:**

```bash
# بررسی لاگ‌های خطا
sudo journalctl -u hesabix-rq-worker -n 200 | grep -i error

# بررسی Memory
free -h

# بررسی Disk Space
df -h

# بررسی Jobs ناموفق
redis-cli
> SMEMBERS rq:failed
```

### مشکل 4: Worker کند است

**علائم:**
- Jobs مدت زمان زیادی در Queue می‌مانند
- Worker CPU/Memory بالایی مصرف می‌کند

**راه‌حل:**

```bash
# بررسی تعداد Jobs در Queue
redis-cli
> LLEN rq:queue:default
> LLEN rq:queue:high

# بررسی تعداد Workers
SMEMBERS rq:workers

# اگر تعداد Workers کم است، چند Worker دیگر اضافه کنید
# (راهنمای اضافه کردن چند Worker در زیر آمده است)
```

### مشکل 5: Permission Denied

**علائم:**
```
PermissionError: [Errno 13] Permission denied
```

**راه‌حل:**

```bash
# بررسی مالکیت فایل‌ها
ls -la /var/www/ark/hesabixAPI/

# تنظیم مالکیت
sudo chown -R www-data:www-data /var/www/ark/hesabixAPI/

# بررسی دسترسی
sudo -u www-data ls -la /var/www/ark/hesabixAPI/
```

---

## ساخت سرویس Systemd

### فایل سرویس Systemd

فایل سرویس در مسیر `/etc/systemd/system/hesabix-rq-worker.service` ذخیره می‌شود:

```ini
[Unit]
Description=Hesabix RQ Worker (Background Jobs)
Documentation=https://github.com/miguelgrinberg/python-rq
After=network.target redis.service mysql.service
Wants=redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/ark/hesabixAPI
Environment=PATH=/var/www/ark/hesabixAPI/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=/var/www/ark/hesabixAPI/venv/bin/python /var/www/ark/hesabixAPI/rq_worker.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/www/ark/hesabixAPI

[Install]
WantedBy=multi-user.target
```

### توضیحات بخش‌های فایل

#### [Unit]
- **Description**: توضیحات سرویس
- **After**: سرویس‌هایی که باید قبل از این سرویس شروع شوند
- **Wants**: سرویس‌های اختیاری (اگر نباشند، سرویس شروع می‌شود)

#### [Service]
- **Type=simple**: نوع سرویس (simple برای script های معمولی)
- **User/Group**: کاربر و گروه که سرویس با آن اجرا می‌شود
- **WorkingDirectory**: مسیر کاری
- **Environment**: متغیرهای محیطی
- **ExecStart**: دستور اجرای سرویس
- **Restart=always**: همیشه restart شود در صورت crash
- **RestartSec=10**: 10 ثانیه صبر قبل از restart
- **StandardOutput/Error**: خروجی به journal برود

#### [Install]
- **WantedBy**: سرویس در چه target ای فعال شود

### ایجاد دستی سرویس

```bash
# ایجاد فایل سرویس
sudo nano /etc/systemd/system/hesabix-rq-worker.service

# یا استفاده از cat
sudo tee /etc/systemd/system/hesabix-rq-worker.service > /dev/null <<'EOF'
[Unit]
Description=Hesabix RQ Worker (Background Jobs)
After=network.target redis.service mysql.service
Wants=redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/ark/hesabixAPI
Environment=PATH=/var/www/ark/hesabixAPI/venv/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=/var/www/ark/hesabixAPI/venv/bin/python /var/www/ark/hesabixAPI/rq_worker.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# تنظیم دسترسی
sudo chmod 644 /etc/systemd/system/hesabix-rq-worker.service

# Reload systemd
sudo systemctl daemon-reload

# فعال کردن
sudo systemctl enable hesabix-rq-worker
sudo systemctl start hesabix-rq-worker
```

### اجرای چند Worker

برای اجرای چند Worker (برای کارایی بیشتر):

```bash
# ایجاد سرویس‌های متعدد
sudo cp /etc/systemd/system/hesabix-rq-worker.service /etc/systemd/system/hesabix-rq-worker-1.service
sudo cp /etc/systemd/system/hesabix-rq-worker.service /etc/systemd/system/hesabix-rq-worker-2.service

# تغییر Description و نام سرویس
sudo sed -i 's/Hesabix RQ Worker/Hesabix RQ Worker 1/g' /etc/systemd/system/hesabix-rq-worker-1.service
sudo sed -i 's/hesabix-rq-worker/hesabix-rq-worker-1/g' /etc/systemd/system/hesabix-rq-worker-1.service

# راه‌اندازی
sudo systemctl daemon-reload
sudo systemctl enable hesabix-rq-worker-1 hesabix-rq-worker-2
sudo systemctl start hesabix-rq-worker-1 hesabix-rq-worker-2
```

یا استفاده از **Supervisor** برای مدیریت چند Worker.

---

## سوالات متداول

### Q1: چه تعداد Worker نیاز دارم؟

**پاسخ:** 
- برای شروع: **1 Worker** کافی است
- برای بار متوسط: **2-3 Worker**
- برای بار بالا: **5-10 Worker**
- **توجه**: تعداد Worker نباید بیشتر از تعداد CPU Cores باشد

### Q2: Worker چقدر Memory مصرف می‌کند؟

**پاسخ:**
- هر Worker معمولاً **50-200 MB** Memory مصرف می‌کند
- بستگی به نوع Jobs دارد

### Q3: چگونه Worker را متوقف کنم؟

**پاسخ:**
```bash
sudo systemctl stop hesabix-rq-worker
```

### Q4: اگر Worker متوقف شود، Jobs چه می‌شوند؟

**پاسخ:**
- Jobs در Redis Queue باقی می‌مانند
- وقتی Worker دوباره شروع شود، Jobs را پردازش می‌کند
- Jobs ناموفق در `rq:failed` ذخیره می‌شوند

### Q5: چگونه Jobs ناموفق را دوباره اجرا کنم؟

**پاسخ:**
```python
# از طریق Python
from rq import Queue, Worker
from app.core.queue import get_redis_connection

redis_conn = get_redis_connection()
failed_queue = Queue('failed', connection=redis_conn)

# مشاهده Jobs ناموفق
failed_jobs = failed_queue.get_jobs()

# Retry یک Job
job = failed_queue.get_job(job_id)
job.retry()
```

### Q6: چگونه Worker را برای Queue خاص تنظیم کنم؟

**پاسخ:**
ویرایش فایل `rq_worker.py`:
```python
queues = [
    QUEUE_EMAIL,  # فقط email
    # یا
    QUEUE_HIGH_PRIORITY,  # فقط high priority
]
```

---

## منابع بیشتر

- [RQ Documentation](https://python-rq.org/)
- [Systemd Service Files](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Redis Documentation](https://redis.io/documentation)
- [Python RQ GitHub](https://github.com/rq/rq)

---

## پشتیبانی

در صورت بروز مشکل:
1. لاگ‌ها را بررسی کنید
2. مستندات را مطالعه کنید
3. با تیم توسعه تماس بگیرید

---

**آخرین به‌روزرسانی:** 2025-11-28

