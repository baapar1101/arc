# راهنمای اعمال تنظیمات MySQL - Phase 1

این راهنما نحوه اعمال تنظیمات بهینه‌سازی MySQL را روی MySQL نصب شده شرح می‌دهد.

---

## 📋 پیش‌نیازها

1. دسترسی Root یا Super User به MySQL
2. دسترسی Write به فایل کانفیگ MySQL (برای تنظیمات Persistent)
3. MySQL نسخه 5.7 یا بالاتر

---

## 🚀 روش 1: استفاده از اسکریپت Bash (پیشنهادی)

### اجرای اسکریپت

```bash
cd /var/www/ark/hesabixAPI
chmod +x scripts/apply_mysql_config.sh

# روش 1: استفاده از Environment Variables
export DB_HOST=localhost
export DB_PORT=3306
export DB_USER=root
export DB_PASSWORD=your_password
./scripts/apply_mysql_config.sh

# روش 2: اجرای مستقیم (رمز عبور را وارد می‌کند)
./scripts/apply_mysql_config.sh
```

### آنچه اسکریپت انجام می‌دهد:

1. ✅ **تنظیمات Runtime** (بدون نیاز به Restart):
   - افزایش `max_connections` به 2000
   - تنظیم `wait_timeout` و `interactive_timeout`
   - تنظیم `innodb_lock_wait_timeout`
   - فعال‌سازی Slow Query Log

2. ✅ **ایجاد فایل کانفیگ Persistent**:
   - پیدا کردن فایل کانفیگ MySQL
   - ایجاد Backup از فایل موجود
   - اضافه کردن تنظیمات Hesabix به فایل کانفیگ

3. ✅ **نمایش تنظیمات اعمال شده**:
   - بررسی و نمایش تمام تنظیمات جدید
   - نمایش وضعیت اتصالات فعلی

---

## 🗄️ روش 2: استفاده از فایل SQL

اگر می‌خواهید دستی تنظیمات را اعمال کنید:

```bash
# اجرای فایل SQL
mysql -u root -p < scripts/apply_mysql_config_sql.sql

# یا با مشخص کردن Host و Port
mysql -h localhost -P 3306 -u root -p < scripts/apply_mysql_config_sql.sql
```

### محتوای فایل SQL:

- تنظیمات Connection (max_connections, timeouts)
- تنظیمات InnoDB
- فعال‌سازی Slow Query Log
- بررسی و نمایش تنظیمات

---

## 🔍 روش 3: بررسی تنظیمات فعلی

برای بررسی تنظیمات MySQL بدون اعمال تغییرات:

```bash
cd /var/www/ark/hesabixAPI
python3 scripts/check_mysql_config.py
```

یا به صورت مستقیم:

```bash
python3 -c "
import sys
sys.path.insert(0, '/var/www/ark/hesabixAPI')
from scripts.check_mysql_config import check_mysql_config
check_mysql_config()
"
```

---

## 📝 اعمال تنظیمات Persistent (دستی)

### پیدا کردن فایل کانفیگ MySQL

```bash
# بررسی مسیرهای معمول
ls -la /etc/mysql/my.cnf
ls -la /etc/my.cnf
ls -la /usr/local/mysql/my.cnf

# یا پیدا کردن با دستور mysqld
mysqld --help --verbose | grep -A 1 "Default options"
```

### اضافه کردن تنظیمات

1. **کپی فایل mysql.conf**:

```bash
cd /var/www/ark/hesabixAPI

# برای MySQL در Docker:
# (این قبلاً در docker-compose.yml تنظیم شده است)

# برای MySQL نصب شده روی سیستم:
sudo cp mysql.conf /etc/mysql/conf.d/hesabix-optimization.cnf

# یا اضافه کردن به فایل اصلی:
sudo nano /etc/mysql/my.cnf
# محتوای mysql.conf را اضافه کنید
```

2. **تست فایل کانفیگ**:

```bash
# تست Syntax
sudo mysqld --help --verbose | head -n 1

# یا در MySQL 8.0
mysql --validate-config
```

3. **Restart MySQL**:

```bash
# برای systemd:
sudo systemctl restart mysql

# یا برای service:
sudo service mysql restart

# برای Docker:
docker-compose restart db
```

---

## ⚙️ تنظیمات مهم

### 1. max_connections

```sql
-- بررسی مقدار فعلی
SHOW VARIABLES LIKE 'max_connections';

-- افزایش Runtime (بدون Restart)
SET GLOBAL max_connections = 2000;

-- بررسی جدید
SHOW VARIABLES LIKE 'max_connections';
```

**برای Persistent** (در my.cnf):
```ini
[mysqld]
max_connections = 2000
```

### 2. innodb_buffer_pool_size

این تنظیم **حتماً نیاز به Restart** دارد.

**محاسبه مقدار مناسب**:
```
70-80% از RAM سیستم
مثال: برای 32GB RAM = 22-25GB
```

```bash
# بررسی RAM سیستم
free -h

# محاسبه مقدار (مثال برای 32GB RAM)
# 32GB * 0.7 = 22.4GB = 22400M
```

**تنظیم در my.cnf**:
```ini
[mysqld]
innodb_buffer_pool_size = 22400M
innodb_buffer_pool_instances = 8
```

### 3. Slow Query Log

```sql
-- فعال‌سازی Runtime
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;

-- بررسی مسیر Log File
SHOW VARIABLES LIKE 'slow_query_log_file';

-- مشاهده Slow Queries
SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;
```

---

## 🔍 بررسی تنظیمات اعمال شده

### بررسی تنظیمات مهم:

```sql
-- Connection Settings
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'wait_timeout';
SHOW VARIABLES LIKE 'interactive_timeout';

-- InnoDB Settings
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_buffer_pool_instances';
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';

-- Query Logging
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'slow_query_log_file';

-- Performance Schema
SHOW VARIABLES LIKE 'performance_schema';
```

### بررسی وضعیت اتصالات:

```sql
-- تعداد اتصالات فعلی
SHOW STATUS LIKE 'Threads_connected';

-- تعداد اتصالات حداکثر
SHOW VARIABLES LIKE 'max_connections';

-- نمایش اتصالات فعال
SELECT 
    id,
    user,
    host,
    db,
    command,
    time,
    state,
    LEFT(info, 100) as query_preview
FROM information_schema.processlist
WHERE command != 'Sleep'
ORDER BY time DESC;
```

---

## 📊 مثال خروجی اسکریپت

```
🚀 شروع اعمال تنظیمات MySQL Phase 1...
✅ اتصال به MySQL برقرار شد
📊 بررسی نسخه MySQL...
   نسخه MySQL: 8.4.0

📋 تنظیمات فعلی MySQL:
   max_connections: 151
   innodb_buffer_pool_size: 134217728 (128MB)

🔧 اعمال تنظیمات Runtime (بدون نیاز به Restart)...
   افزایش max_connections از 151 به 2000...
   ✅ max_connections به 2000 افزایش یافت
   ✅ Timeouts تنظیم شد
   ✅ Slow Query Log فعال شد

📝 ایجاد فایل کانفیگ برای تنظیمات Persistent...
   فایل کانفیگ پیدا شد: /etc/mysql/my.cnf
   ✅ Backup ایجاد شد: /etc/mysql/my.cnf.backup.20250127_120000
   ✅ تنظیمات به فایل کانفیگ اضافه شد
   ⚠️  برای اعمال کامل تنظیمات، MySQL را Restart کنید

✅ بررسی تنظیمات اعمال شده:
   max_connections: 2000
   wait_timeout: 600
   slow_query_log: ON

✅ اعمال تنظیمات MySQL Phase 1 تکمیل شد!
```

---

## ⚠️ نکات مهم

### 1. Backup قبل از تغییرات

**همیشه قبل از تغییر کانفیگ MySQL، Backup بگیرید**:

```bash
# Backup فایل کانفیگ
sudo cp /etc/mysql/my.cnf /etc/mysql/my.cnf.backup.$(date +%Y%m%d)

# Backup Database
mysqldump -u root -p --all-databases > backup_$(date +%Y%m%d).sql
```

### 2. تست تنظیمات

بعد از اعمال تنظیمات:

1. ✅ بررسی MySQL Start می‌شود
2. ✅ بررسی Application به MySQL متصل می‌شود
3. ✅ بررسی Performance بهبود یافته است

### 3. Monitoring

بعد از اعمال تنظیمات، وضعیت را Monitor کنید:

```bash
# بررسی Health Check
curl http://localhost:8000/api/v1/health/database

# بررسی Logs
tail -f /var/log/mysql/slow-query.log

# بررسی Connection Pool
curl http://localhost:8000/api/v1/health | jq .data.connection_pool
```

---

## 🐳 برای MySQL در Docker

اگر از Docker استفاده می‌کنید:

### روش 1: استفاده از Volume (پیشنهادی)

در `docker-compose.yml`:
```yaml
services:
  db:
    volumes:
      - ./mysql.conf:/etc/mysql/conf.d/custom.cnf:ro
```

سپس:
```bash
docker-compose restart db
```

### روش 2: اجرای دستورات در Container

```bash
# ورود به Container
docker exec -it hesabix-mysql bash

# اجرای دستورات SQL
mysql -u root -p < /path/to/apply_mysql_config_sql.sql

# یا به صورت مستقیم
docker exec -i hesabix-mysql mysql -u root -p < scripts/apply_mysql_config_sql.sql
```

---

## ❓ عیب‌یابی

### مشکل 1: MySQL Start نمی‌شود

```bash
# بررسی Logs
sudo tail -f /var/log/mysql/error.log

# تست Syntax Config
sudo mysqld --help --verbose | head -n 1

# حذف تنظیمات مشکل‌دار از my.cnf
```

### مشکل 2: تنظیمات اعمال نمی‌شوند

```sql
-- بررسی اینکه آیا تنظیمات از Config File خوانده می‌شوند
SHOW VARIABLES LIKE 'max_connections';

-- اگر مقدار تغییر نکرده، MySQL را Restart کنید
```

### مشکل 3: دسترسی به MySQL

```bash
# بررسی اینکه MySQL در حال اجراست
sudo systemctl status mysql

# Restart MySQL
sudo systemctl restart mysql
```

---

## 📚 منابع بیشتر

- [MySQL Documentation](https://dev.mysql.com/doc/)
- [MySQL Performance Tuning](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- [Phase 1 Implementation Guide](./PHASE1_QUICK_WINS_IMPLEMENTATION.md)

---

**موفق باشید!** 🚀

