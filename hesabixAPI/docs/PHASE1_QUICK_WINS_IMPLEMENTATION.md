# Phase 1: Quick Wins Implementation - راهنمای پیاده‌سازی

## ✅ کارهای انجام شده

### 1. افزایش Connection Pool

#### تغییرات در `app/core/settings.py`:
- `db_pool_size`: افزایش از 20 به **50**
- `db_max_overflow`: افزایش از 30 به **50**
- `db_pool_timeout`: افزایش از 10 به **30** ثانیه
- اضافه شدن `db_pool_recycle`: 3600 ثانیه

**نتیجه**: افزایش حداکثر اتصالات از 50 به 100 per worker

#### تغییرات در `adapters/db/session.py`:
- استفاده از `QueuePool` برای کنترل بهتر
- اضافه شدن Event Listeners برای Monitoring
- بهبود تنظیمات Connection با Session Parameters
- اضافه شدن Logging برای Pool Statistics

### 2. Connection Pool Monitoring

#### فایل جدید: `app/core/db_pool_monitor.py`
- کلاس `ConnectionPoolMonitor` برای مانیتورینگ Pool
- متدهای:
  - `get_pool_stats()`: دریافت آمار Pool
  - `log_pool_stats()`: Log آمار Pool
  - `get_pool_health()`: دریافت وضعیت سلامت Pool

### 3. بهبود Health Check Endpoints

#### تغییرات در `adapters/api/v1/health.py`:
- اضافه شدن Connection Pool Stats به `/api/v1/health`
- Endpoint جدید `/api/v1/health/database` با جزئیات کامل:
  - Master Connection Check
  - Connection Pool Stats
  - Database Size
  - Active Connections
  - Slow Queries Count

### 4. MySQL Configuration

#### فایل جدید: `mysql.conf`
- تنظیمات بهینه‌سازی شده MySQL برای Production
- افزایش `max_connections` به 2000
- بهینه‌سازی InnoDB Buffer Pool
- Slow Query Log فعال
- Performance Schema فعال

#### تغییرات در `docker-compose.yml`:
- اضافه شدن Volume برای `mysql.conf`
- اضافه شدن Volume برای MySQL Logs

### 5. به‌روزرسانی Environment Variables

#### تغییرات در `env.example`:
- به‌روزرسانی تنظیمات Connection Pool
- اضافه شدن توضیحات

---

## 🚀 نحوه استفاده

### 1. به‌روزرسانی Environment Variables

در فایل `.env` خود تنظیمات زیر را به‌روزرسانی کنید:

```env
DB_POOL_SIZE=50
DB_MAX_OVERFLOW=50
DB_POOL_TIMEOUT=30
DB_POOL_RECYCLE=3600
```

### 2. تنظیم MySQL Configuration

#### Option A: استفاده از Docker Compose

فایل `mysql.conf` آماده است. فقط دایرکتوری `mysql-logs` را ایجاد کنید:

```bash
mkdir -p hesabixAPI/mysql-logs
```

سپس Docker Compose را restart کنید:

```bash
cd hesabixAPI
docker-compose down
docker-compose up -d
```

#### Option B: تنظیم دستی MySQL

اگر MySQL به صورت دستی نصب شده، فایل `mysql.conf` را در مسیر زیر کپی کنید:

```bash
sudo cp mysql.conf /etc/mysql/conf.d/hesabix-optimization.cnf
sudo systemctl restart mysql
```

### 3. بررسی Health Check

بعد از Restart، Health Check را بررسی کنید:

```bash
# Health Check عمومی
curl http://localhost:8000/api/v1/health

# Health Check Database با جزئیات
curl http://localhost:8000/api/v1/health/database
```

### 4. Monitoring Connection Pool

برای Monitoring Pool در Logs:

```python
from app.core.db_pool_monitor import ConnectionPoolMonitor

# دریافت آمار
stats = ConnectionPoolMonitor.get_pool_stats()
print(stats)

# Log آمار
ConnectionPoolMonitor.log_pool_stats()

# دریافت وضعیت سلامت
health = ConnectionPoolMonitor.get_pool_health()
print(health)
```

---

## 📊 مثال Response از Health Endpoints

### GET `/api/v1/health`

```json
{
  "success": true,
  "message": "سرویس در دسترس است",
  "data": {
    "status": "ok",
    "timestamp": "2025-01-27T12:00:00Z",
    "services": {
      "database": "ok",
      "redis": "disabled"
    },
    "version": "0.1.0",
    "connection_pool": {
      "status": "healthy",
      "usage_percent": 15.5,
      "checked_out": 15,
      "total_capacity": 100
    }
  }
}
```

### GET `/api/v1/health/database`

```json
{
  "status": "healthy",
  "timestamp": "2025-01-27T12:00:00Z",
  "checks": {
    "master": {
      "status": "ok",
      "response_time_ms": 2.5
    },
    "connection_pool": {
      "status": "healthy",
      "stats": {
        "pool_size": 50,
        "max_overflow": 50,
        "checked_out": 15,
        "available": 35,
        "overflow_used": 0,
        "total_capacity": 100,
        "usage_percent": 15.0,
        "status": "healthy"
      },
      "healthy": true,
      "recommendations": []
    },
    "database_size": {
      "size_mb": 1024.5
    },
    "active_connections": {
      "total": 20,
      "running_queries": 5
    },
    "slow_queries": {
      "count": 0
    }
  }
}
```

---

## 🔍 Monitoring در Production

### 1. بررسی Logs

```bash
# Logs Connection Pool
docker-compose logs -f api | grep "Connection Pool"

# Logs MySQL
docker-compose logs -f db
```

### 2. بررسی Metrics از API

```bash
# Health Check هر 30 ثانیه
watch -n 30 'curl -s http://localhost:8000/api/v1/health | jq .data.connection_pool'
```

### 3. Alert در صورت Critical Pool

در Logs، اگر Pool بیش از 90% استفاده شود، Warning Log می‌شود:

```
🚨 CRITICAL: Connection Pool nearly exhausted! Usage: 95.0%, Available: 5
```

---

## ⚠️ نکات مهم

### 1. افزایش max_connections در MySQL

باید `max_connections` در MySQL را افزایش دهید. در `mysql.conf` به 2000 تنظیم شده است.

برای بررسی:

```sql
SHOW VARIABLES LIKE 'max_connections';
```

### 2. محاسبه Connection Pool مناسب

فرمول:
```
تعداد Worker ها × (pool_size + max_overflow) ≤ max_connections MySQL
```

مثال:
- 5 Workers
- pool_size = 50
- max_overflow = 50
- حداکثر: 5 × 100 = 500 اتصال
- باید `max_connections` ≥ 500 باشد

### 3. Monitoring در Production

- هر روز Health Check را بررسی کنید
- Logs Connection Pool را Monitor کنید
- در صورت Warning/Critical، Pool را افزایش دهید

---

## 📈 بهبودهای حاصل شده

### قبل از Phase 1:
- Pool Size: 20 + 30 overflow = 50 max per worker
- با 5 Workers: 250 اتصال حداکثر
- عدم Monitoring Pool

### بعد از Phase 1:
- Pool Size: 50 + 50 overflow = 100 max per worker
- با 5 Workers: 500 اتصال حداکثر (افزایش 100%)
- Monitoring کامل Pool با Health Checks
- Alerts برای Critical Situations

---

## ✅ Checklist برای Deploy

- [ ] به‌روزرسانی `.env` با تنظیمات جدید
- [ ] ایجاد دایرکتوری `mysql-logs` (برای Docker)
- [ ] Restart Docker Compose یا MySQL
- [ ] بررسی Health Check Endpoints
- [ ] بررسی Logs برای Errors
- [ ] تست Application با بار معمولی
- [ ] Monitor Connection Pool برای چند روز
- [ ] تنظیم Alerts در Production Monitoring

---

## 🔗 منابع بیشتر

- [Database Scalability Guide](./DATABASE_SCALABILITY_GUIDE.md)
- [MySQL Documentation](https://dev.mysql.com/doc/)
- [SQLAlchemy Pool Documentation](https://docs.sqlalchemy.org/en/14/core/pooling.html)

---

**Phase 1 تکمیل شد!** 🎉

مرحله بعد: Phase 2 - Read Replicas

