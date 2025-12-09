-- اسکریپت SQL برای اعمال تنظیمات MySQL برای 5500 کانکشن
-- این فایل شامل دستورات SQL برای تنظیمات Runtime است
-- برای اجرا: mysql -u root -p < apply_mysql_5500_connections.sql

-- ============================================
-- بخش 1: Connection Settings
-- ============================================

-- افزایش max_connections به 5500 (برای 50 worker با 100 connection هر کدام)
SET GLOBAL max_connections = 5500;

-- تنظیم max_user_connections
SET GLOBAL max_user_connections = 5500;

-- تنظیم Timeouts (کاهش برای آزادسازی سریع‌تر connection های idle)
SET GLOBAL wait_timeout = 300;
SET GLOBAL interactive_timeout = 300;
SET GLOBAL connect_timeout = 10;

-- ============================================
-- بخش 2: Threading Settings
-- ============================================

-- افزایش thread_cache_size برای 5500 connection
SET GLOBAL thread_cache_size = 550;

-- ============================================
-- بخش 3: Table Cache Settings
-- ============================================

-- افزایش table_open_cache
SET GLOBAL table_open_cache = 3000;

-- افزایش table_definition_cache
SET GLOBAL table_definition_cache = 3000;

-- ============================================
-- بخش 4: InnoDB Settings
-- ============================================

-- تنظیم innodb_lock_wait_timeout
SET GLOBAL innodb_lock_wait_timeout = 50;

-- نکته: innodb_buffer_pool_size نیاز به Restart MySQL دارد
-- مقدار جدید: 18G (56% از 32GB RAM)
-- این تنظیم در فایل /etc/mysql/conf.d/hesabix.conf اعمال شده است
-- پس از اجرای این اسکریپت، MySQL را restart کنید

-- ============================================
-- بخش 5: Query Logging
-- ============================================

-- فعال‌سازی Slow Query Log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;

-- نمایش مسیر Slow Query Log
SELECT @@slow_query_log_file as slow_query_log_file;

-- ============================================
-- بخش 6: بررسی تنظیمات اعمال شده
-- ============================================

-- Connection Settings
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'max_user_connections';
SHOW VARIABLES LIKE 'wait_timeout';
SHOW VARIABLES LIKE 'interactive_timeout';
SHOW VARIABLES LIKE 'connect_timeout';

-- Threading Settings
SHOW VARIABLES LIKE 'thread_cache_size';

-- Table Cache Settings
SHOW VARIABLES LIKE 'table_open_cache';
SHOW VARIABLES LIKE 'table_definition_cache';

-- InnoDB Settings (innodb_buffer_pool_size نیاز به restart دارد)
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';

