# راهنمای پشتیبانی از 1000 کانکشن همزمان

## 📋 خلاصه تغییرات

### 1. افزایش Connection Pool Size
- **قبل**: `DB_POOL_SIZE=100`, `DB_MAX_OVERFLOW=100` (حداکثر 200 کانکشن)
- **بعد**: `DB_POOL_SIZE=500`, `DB_MAX_OVERFLOW=500` (حداکثر 1000 کانکشن)

### 2. رفع مشکل Connection Leak
- **تغییر**: `pool_reset_on_return='commit'` → `pool_reset_on_return='rollback'`
- **دلیل**: استفاده از 'rollback' اطمینان می‌دهد که transaction های باز بسته می‌شوند و connection leak رخ نمی‌دهد

### 3. بهینه‌سازی Pool Recycle
- **تغییر**: `pool_recycle=3600` → `pool_recycle=1800` (30 دقیقه)
- **دلیل**: Recycle سریع‌تر برای جلوگیری از connection leak و اتصالات قدیمی

### 4. اضافه شدن Connection Leak Detection
- **قابلیت جدید**: سیستم monitoring برای تشخیص connection leak
- **Threshold**: اگر connection بیشتر از 5 دقیقه checkout باشد، warning می‌دهد

## 🔧 تنظیمات اعمال شده

### فایل `.env`
```bash
DB_POOL_SIZE=500
DB_MAX_OVERFLOW=500
DB_POOL_TIMEOUT=30
```

### فایل `adapters/db/session.py`
```python
# تغییرات کلیدی:
pool_reset_on_return='rollback'  # جلوگیری از connection leak
pool_recycle=1800  # Recycle هر 30 دقیقه
pool_size=500  # از .env خوانده می‌شود
max_overflow=500  # از .env خوانده می‌شود
```

### فایل `mysql.conf`
```ini
max_connections = 2000  # پشتیبانی از 2000 کانکشن همزمان
max_user_connections = 1000
```

## 📊 محاسبه Connection Pool

### فرمول محاسبه:
```
حداکثر کانکشن = pool_size + max_overflow
```

### برای 1000 کانکشن:
```
pool_size = 500
max_overflow = 500
حداکثر = 500 + 500 = 1000 کانکشن
```

### برای چند Worker:
اگر 5 Worker دارید:
```
هر Worker: 500 + 500 = 1000
5 Worker: 5 * 1000 = 5000 کانکشن (نیاز به max_connections > 5000 در MySQL)
```

## 🔍 Monitoring Connection Leak

### 1. بررسی لاگ‌ها
```bash
# بررسی connection leak warnings
journalctl -u hesabix-api | grep "connection leak"

# بررسی pool usage
journalctl -u hesabix-api | grep "High connection pool usage"
```

### 2. بررسی از طریق API
```bash
# Health check با pool stats
curl http://localhost:8000/api/v1/health | jq .data.connection_pool

# Database health check
curl http://localhost:8000/api/v1/health/database | jq .checks.connection_pool
```

### 3. بررسی مستقیم MySQL
```sql
-- تعداد کانکشن‌های فعال
SHOW STATUS LIKE 'Threads_connected';

-- حداکثر کانکشن‌های استفاده شده
SHOW STATUS LIKE 'Max_used_connections';

-- لیست کانکشن‌های فعال
SHOW PROCESSLIST;
```

## ⚠️ نکات مهم

### 1. Connection Leak Prevention
- ✅ استفاده از `Depends(get_db)` در FastAPI endpoints
- ✅ استفاده از `get_db_session()` در background jobs
- ✅ اطمینان از بسته شدن session در `finally` block
- ✅ استفاده از `pool_reset_on_return='rollback'`

### 2. تنظیمات MySQL
- ✅ `max_connections` باید بیشتر از `(pool_size + max_overflow) * تعداد_workers` باشد
- ✅ برای 5 Worker با 1000 کانکشن هر کدام: `max_connections >= 5000`
- ✅ فعلاً `max_connections = 2000` تنظیم شده (کافی برای 2 Worker)

### 3. Performance Considerations
- ⚠️ افزایش pool size باعث افزایش مصرف حافظه می‌شود
- ⚠️ هر connection حدود 1-2 MB حافظه مصرف می‌کند
- ⚠️ برای 1000 connection: حدود 1-2 GB حافظه نیاز است

## 🚀 راه‌اندازی

### 1. Restart سرویس API
```bash
sudo systemctl restart hesabix-api
```

### 2. بررسی لاگ‌ها
```bash
sudo journalctl -u hesabix-api -f
```

### 3. تست Connection Pool
```bash
# بررسی pool stats
curl http://localhost:8000/api/v1/health | jq .data.connection_pool
```

## 📈 Monitoring و Alerting

### Connection Leak Detection
سیستم به صورت خودکار connection leak را تشخیص می‌دهد:
- اگر connection بیشتر از 5 دقیقه checkout باشد
- Warning در لاگ‌ها ثبت می‌شود
- می‌توانید alert تنظیم کنید

### Pool Usage Monitoring
- اگر pool usage بیش از 80% باشد، warning می‌دهد
- هر 60 ثانیه یکبار warning (rate limiting)
- می‌توانید از `/api/v1/health` برای monitoring استفاده کنید

## 🔧 Troubleshooting

### مشکل: Pool به 100% رسیده
**راه‌حل**:
1. بررسی connection leak در لاگ‌ها
2. افزایش `DB_POOL_SIZE` و `DB_MAX_OVERFLOW`
3. بررسی `max_connections` در MySQL

### مشکل: Connection timeout
**راه‌حل**:
1. افزایش `DB_POOL_TIMEOUT` در `.env`
2. بررسی `max_connections` در MySQL
3. بررسی connection leak

### مشکل: MySQL max_connections رسیده
**راه‌حل**:
1. افزایش `max_connections` در `mysql.conf`
2. Restart MySQL
3. بررسی تعداد Worker ها

## 📝 خلاصه

✅ **Connection Pool**: 500 + 500 = 1000 کانکشن
✅ **Connection Leak Detection**: فعال
✅ **Pool Recycle**: هر 30 دقیقه
✅ **MySQL max_connections**: 2000
✅ **Monitoring**: از طریق `/api/v1/health`

## 🔄 بعد از اعمال تغییرات

1. Restart سرویس API: `sudo systemctl restart hesabix-api`
2. بررسی لاگ‌ها: `journalctl -u hesabix-api -f`
3. تست Health Check: `curl http://localhost:8000/api/v1/health`
4. Monitoring: بررسی pool usage و connection leak warnings

