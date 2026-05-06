# فاز 4: Background Job Queue

## خلاصه

این فاز سیستم Background Job Queue را با استفاده از **RQ (Redis Queue)** پیاده‌سازی می‌کند. این سیستم امکان اجرای کارهای زمان‌بر را در پس‌زمینه فراهم می‌کند و از blocking شدن API جلوگیری می‌کند.

## قابلیت‌های پیاده‌سازی شده

### 1. Queue Service (`app/core/queue.py`)
- مدیریت queues با RQ
- پشتیبانی از چندین queue با اولویت‌های مختلف:
  - `high`: کارهای با اولویت بالا
  - `default`: کارهای عادی
  - `email`: ارسال ایمیل
  - `reports`: تولید گزارش
  - `exports`: export داده‌ها
  - `low`: کارهای با اولویت پایین
- مدیریت job ها: enqueue, get, cancel, delete
- آمارگیری از queues

### 2. Job Manager به‌روزرسانی شده (`app/services/job_manager.py`)
- سازگاری با QueueService
- پشتیبانی از memory-based jobs (fallback)
- تبدیل وضعیت RQ jobs به JobStatus

### 3. Background Jobs
- **Email Job** (`app/services/jobs/email_job.py`): ارسال ایمیل
- **Report Job** (`app/services/jobs/report_job.py`): تولید گزارش
- **Export Job** (`app/services/jobs/export_job.py`): export داده‌ها

### 4. RQ Worker (`rq_worker.py`)
- Worker script برای اجرای jobs
- پشتیبانی از تمام queues با اولویت‌بندی

### 5. API Endpoints (`adapters/api/v1/jobs.py`)
- `GET /api/v1/jobs/{job_id}`: دریافت وضعیت job
- `DELETE /api/v1/jobs/{job_id}`: لغو یا حذف job
- `GET /api/v1/jobs/queue/stats`: آمار queues
- `GET /api/v1/jobs/failed`: لیست jobs ناموفق

## نصب و راه‌اندازی

### 1. نصب Dependencies

```bash
cd hesabixAPI
source .venv/bin/activate
pip install -e .
```

### 2. راه‌اندازی Redis

Redis باید نصب و راه‌اندازی شده باشد. برای راهنمای نصب Redis، به `docs/REDIS_SETUP.md` مراجعه کنید.

### 3. راه‌اندازی RQ Worker

#### دستی:
```bash
cd hesabixAPI
source .venv/bin/activate
python rq_worker.py
```

#### با systemd (از طریق deploy.sh):
```bash
sudo systemctl start hesabix-rq-worker
sudo systemctl enable hesabix-rq-worker
```

### 4. بررسی وضعیت Worker

```bash
# بررسی وضعیت service
sudo systemctl status hesabix-rq-worker

# مشاهده لاگ‌ها
sudo journalctl -u hesabix-rq-worker -f
```

برای مشاهدهٔ همان لاگ از پنل ادمین (**تنظیمات سیستم → لاگ‌های سرویس‌ها**) و محدودیت‌های میزبان/Docker، به [SERVICE_LOGS_ADMIN_API.md](./SERVICE_LOGS_ADMIN_API.md) مراجعه کنید.

## استفاده

### Enqueue کردن Job

```python
from app.core.queue import get_queue_service, QUEUE_EMAIL
from app.services.jobs import send_email_job

queue_service = get_queue_service()

# Enqueue کردن job
job = queue_service.enqueue(
    send_email_job,
    to_email="user@example.com",
    subject="Test Email",
    body="This is a test email",
    queue_name=QUEUE_EMAIL,
    timeout=300,
    result_ttl=3600
)

if job:
    print(f"Job ID: {job.id}")
```

### بررسی وضعیت Job

```python
from app.services.job_manager import JobManager

job_manager = JobManager.instance()
status = job_manager.get(job_id)

if status:
    print(f"State: {status.state}")
    print(f"Progress: {status.progress}%")
    print(f"Message: {status.message}")
```

### استفاده در API Endpoints

```python
from app.core.queue import get_queue_service, QUEUE_REPORTS
from app.services.jobs import generate_report_job

@router.post("/reports/generate")
async def create_report(...):
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        raise ApiError("QUEUE_DISABLED", "Queue service is disabled")
    
    job = queue_service.enqueue(
        generate_report_job,
        report_type="sales",
        business_id=business_id,
        user_id=user_id,
        queue_name=QUEUE_REPORTS
    )
    
    return {"job_id": job.id}
```

## Queues و اولویت‌ها

Worker به ترتیب اولویت از queues استفاده می‌کند:
1. `high` - کارهای با اولویت بالا
2. `default` - کارهای عادی
3. `email` - ارسال ایمیل
4. `reports` - تولید گزارش
5. `exports` - export داده‌ها
6. `low` - کارهای با اولویت پایین

## Monitoring

### آمار Queues

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8000/api/v1/jobs/queue/stats
```

### Jobs ناموفق

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8000/api/v1/jobs/failed?limit=10
```

## Troubleshooting

### Worker شروع نمی‌شود

1. بررسی کنید Redis در حال اجرا است:
   ```bash
   sudo systemctl status redis
   ```

2. بررسی تنظیمات Redis در پنل مدیریت سیستم

3. بررسی لاگ‌های worker:
   ```bash
   sudo journalctl -u hesabix-rq-worker -n 50
   ```

### Jobs اجرا نمی‌شوند

1. بررسی کنید worker در حال اجرا است:
   ```bash
   sudo systemctl status hesabix-rq-worker
   ```

2. بررسی کنید Redis در دسترس است:
   ```bash
   redis-cli ping
   ```

3. بررسی آمار queues:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:8000/api/v1/jobs/queue/stats
   ```

### Jobs در queue می‌مانند

1. بررسی کنید worker در حال اجرا است
2. بررسی لاگ‌های worker برای خطاها
3. بررسی failed jobs:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:8000/api/v1/jobs/failed
   ```

## Best Practices

1. **Timeout مناسب**: برای هر job یک timeout مناسب تنظیم کنید
2. **Result TTL**: برای jobs با نتیجه بزرگ، TTL کوتاه‌تری تنظیم کنید
3. **Queue مناسب**: از queue مناسب برای هر نوع job استفاده کنید
4. **Error Handling**: در job functions خطاها را به درستی handle کنید
5. **Monitoring**: به طور منظم آمار queues و failed jobs را بررسی کنید

## مقیاس‌پذیری

برای مقیاس‌پذیری بیشتر:
- می‌توانید چندین worker اجرا کنید
- می‌توانید worker های جداگانه برای هر queue ایجاد کنید
- می‌توانید از Redis Cluster برای مقیاس‌پذیری بیشتر استفاده کنید

## Migration از BackgroundTasks

اگر از FastAPI BackgroundTasks استفاده می‌کردید، می‌توانید به تدریج به RQ migrate کنید:

1. Job های زمان‌بر را به RQ منتقل کنید
2. Job های سریع را می‌توانید در BackgroundTasks نگه دارید
3. از QueueService برای enqueue کردن استفاده کنید

## منابع

- [RQ Documentation](https://python-rq.org/)
- [Redis Documentation](https://redis.io/docs/)

