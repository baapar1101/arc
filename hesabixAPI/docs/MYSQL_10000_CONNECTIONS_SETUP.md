# راهنمای تنظیم MySQL برای 10000 کانکشن همزمان

## 📋 خلاصه تغییرات

### تنظیمات اعمال شده:

| تنظیمات | مقدار قبلی | مقدار جدید | دلیل |
|---------|-----------|-----------|------|
| `max_connections` | 2000 | **10000** | پشتیبانی از 10 Worker با 1000 کانکشن هر کدام |
| `max_user_connections` | 1000 | **5000** | افزایش برای هر کاربر |
| `wait_timeout` | 600 | **300** | آزادسازی سریع‌تر connection های idle |
| `interactive_timeout` | 600 | **300** | آزادسازی سریع‌تر connection های idle |
| `thread_cache_size` | 50 | **1000** | برای 10000 connection نیاز به cache بیشتر |
| `table_open_cache` | 4000 | **5000** | افزایش برای پشتیبانی از connection بیشتر |
| `table_definition_cache` | 2000 | **3000** | افزایش برای پشتیبانی از connection بیشتر |
| `open_files_limit` | 10000 | **15000** | باید بیشتر از max_connections باشد |

## 🔧 مراحل اعمال تنظیمات

### روش 1: اعمال Runtime (بدون Restart)

برای اعمال تنظیمات بدون Restart MySQL:

```bash
cd /var/www/ark/hesabixAPI
mysql -u root -p < scripts/apply_mysql_10000_connections.sql
```

**نکته**: این تنظیمات تا Restart MySQL باقی می‌مانند. برای Persistent، باید در `my.cnf` تنظیم شوند.

### روش 2: اعمال Persistent (با Restart)

#### 1. کپی فایل کانفیگ

```bash
# پیدا کردن مسیر my.cnf
mysql --help | grep "Default options" -A 1

# معمولاً در یکی از این مسیرها است:
# - /etc/mysql/my.cnf
# - /etc/my.cnf
# - ~/.my.cnf
```

#### 2. اضافه کردن تنظیمات

فایل `mysql.conf` را کپی کنید یا محتوای آن را به `my.cnf` اضافه کنید:

```bash
# اگر از docker-compose استفاده می‌کنید:
# فایل mysql.conf در پروژه است

# اگر MySQL مستقیماً نصب شده:
sudo cp /var/www/ark/hesabixAPI/mysql.conf /etc/mysql/conf.d/hesabix.conf
```

#### 3. Restart MySQL

```bash
# برای systemd
sudo systemctl restart mysql
# یا
sudo systemctl restart mysqld

# برای docker
docker-compose restart db
```

### روش 3: اعمال از طریق SQL (Runtime)

```sql
-- اعمال تنظیمات runtime
SET GLOBAL max_connections = 10000;
SET GLOBAL max_user_connections = 5000;
SET GLOBAL wait_timeout = 300;
SET GLOBAL interactive_timeout = 300;
SET GLOBAL thread_cache_size = 1000;
SET GLOBAL table_open_cache = 5000;
SET GLOBAL table_definition_cache = 3000;
```

## 📊 بررسی تنظیمات اعمال شده

### 1. بررسی از طریق SQL

```sql
-- بررسی Connection Settings
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'max_user_connections';
SHOW VARIABLES LIKE 'wait_timeout';
SHOW VARIABLES LIKE 'interactive_timeout';

-- بررسی Threading Settings
SHOW VARIABLES LIKE 'thread_cache_size';

-- بررسی Table Cache Settings
SHOW VARIABLES LIKE 'table_open_cache';
SHOW VARIABLES LIKE 'table_definition_cache';

-- بررسی File Limits
SHOW VARIABLES LIKE 'open_files_limit';
```

### 2. بررسی وضعیت اتصالات

```sql
-- تعداد اتصالات فعلی
SHOW STATUS LIKE 'Threads_connected';

-- حداکثر اتصالات استفاده شده
SHOW STATUS LIKE 'Max_used_connections';

-- درصد استفاده از connection pool
SELECT 
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') as current_connections,
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') as max_connections,
    ROUND(
        (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') /
        (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') * 100,
        2
    ) as usage_percent;
```

### 3. بررسی از طریق Command Line

```bash
mysql -u root -p -e "SHOW VARIABLES LIKE 'max_connections';"
mysql -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"
```

## ⚠️ نکات مهم

### 1. Memory Requirements

برای 10000 connection، MySQL به حافظه بیشتری نیاز دارد:

```
هر connection حدود 1-2 MB حافظه مصرف می‌کند
10000 connection = 10-20 GB حافظه (فقط برای connections)
```

**توصیه**: 
- حداقل 32GB RAM برای سرور
- `innodb_buffer_pool_size` را به 70-80% RAM تنظیم کنید

### 2. File Descriptors

برای 10000 connection، باید `open_files_limit` را افزایش دهید:

```bash
# بررسی limit فعلی
ulimit -n

# تنظیم در /etc/security/limits.conf
* soft nofile 20000
* hard nofile 20000

# یا در systemd service
LimitNOFILE=20000
```

### 3. System Limits

بررسی و تنظیم system limits:

```bash
# بررسی limits فعلی
cat /proc/sys/fs/file-max

# اگر نیاز است، افزایش دهید (در /etc/sysctl.conf)
fs.file-max = 20000
```

### 4. Performance Considerations

- ⚠️ افزایش `max_connections` باعث افزایش مصرف حافظه می‌شود
- ⚠️ هر connection thread جداگانه ایجاد می‌کند
- ⚠️ برای 10000 connection، CPU overhead بیشتر می‌شود
- ✅ استفاده از Connection Pooling برای کاهش تعداد connection های واقعی

## 🔍 Troubleshooting

### مشکل: MySQL شروع نمی‌شود

**علت**: ممکن است `open_files_limit` کافی نباشد

**راه‌حل**:
```bash
# بررسی error log
sudo tail -f /var/log/mysql/error.log

# افزایش open_files_limit در my.cnf
open_files_limit = 15000
```

### مشکل: "Too many connections" error

**علت**: `max_connections` به حد رسیده

**راه‌حل**:
1. بررسی تعداد connection های فعال:
```sql
SHOW PROCESSLIST;
```

2. بررسی connection leak در application
3. افزایش `max_connections` اگر واقعاً نیاز است

### مشکل: Performance کاهش یافته

**علت**: تعداد connection های زیاد باعث overhead می‌شود

**راه‌حل**:
1. استفاده از Connection Pooling
2. کاهش `wait_timeout` و `interactive_timeout`
3. بررسی و بهینه‌سازی query ها

## 📈 Monitoring

### 1. Monitoring از طریق API

```bash
# Health check با pool stats
curl http://localhost:8000/api/v1/health | jq .data.connection_pool

# Database health check
curl http://localhost:8000/api/v1/health/database | jq .checks.connection_pool
```

### 2. Monitoring از طریق MySQL

```sql
-- ایجاد view برای monitoring
CREATE OR REPLACE VIEW connection_monitor AS
SELECT 
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') as current_connections,
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') as max_connections,
    ROUND(
        (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') /
        (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') * 100,
        2
    ) as usage_percent,
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Max_used_connections') as max_used_connections;

-- استفاده از view
SELECT * FROM connection_monitor;
```

## 🚀 Best Practices

1. **استفاده از Connection Pooling**: 
   - از Connection Pool استفاده کنید
   - هر Worker نباید بیش از 1000 connection داشته باشد

2. **Monitoring**: 
   - به صورت منظم connection usage را بررسی کنید
   - Alert تنظیم کنید برای usage > 80%

3. **Connection Leak Detection**: 
   - از سیستم monitoring استفاده کنید
   - بررسی لاگ‌ها برای connection leak warnings

4. **بهینه‌سازی Query ها**: 
   - Query های کند را بهینه کنید
   - از Index استفاده کنید

## 📝 خلاصه

✅ **max_connections**: 10000
✅ **max_user_connections**: 5000
✅ **thread_cache_size**: 1000
✅ **table_open_cache**: 5000
✅ **open_files_limit**: 15000
✅ **wait_timeout**: 300 (کاهش برای آزادسازی سریع‌تر)

## 🔄 بعد از اعمال تنظیمات

1. Restart MySQL: `sudo systemctl restart mysql`
2. بررسی تنظیمات: `mysql -u root -p -e "SHOW VARIABLES LIKE 'max_connections';"`
3. تست Connection Pool: بررسی از طریق `/api/v1/health`
4. Monitoring: بررسی connection usage و performance

