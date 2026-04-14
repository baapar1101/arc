-- اسکریپت SQL برای اعمال تنظیمات MySQL برای 10000 کانکشن
-- این فایل شامل دستورات SQL برای تنظیمات Runtime است
-- برای اجرا: mysql -u root -p < apply_mysql_10000_connections.sql

-- ============================================
-- بخش 1: Connection Settings
-- ============================================

-- افزایش max_connections به 10000
SET GLOBAL max_connections = 10000;

-- تنظیم max_user_connections
SET GLOBAL max_user_connections = 5000;

-- تنظیم Timeouts (کاهش برای آزادسازی سریع‌تر connection های idle)
SET GLOBAL wait_timeout = 300;
SET GLOBAL interactive_timeout = 300;
SET GLOBAL connect_timeout = 10;

-- ============================================
-- بخش 2: Threading Settings
-- ============================================

-- افزایش thread_cache_size برای 10000 connection
SET GLOBAL thread_cache_size = 1000;

-- ============================================
-- بخش 3: Table Cache Settings
-- ============================================

-- افزایش table_open_cache
SET GLOBAL table_open_cache = 5000;

-- افزایش table_definition_cache
SET GLOBAL table_definition_cache = 3000;

-- ============================================
-- بخش 4: InnoDB Settings
-- ============================================

-- تنظیم innodb_lock_wait_timeout
SET GLOBAL innodb_lock_wait_timeout = 50;

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
SELECT 
    'Connection Settings' as category,
    @@max_connections as max_connections,
    @@max_user_connections as max_user_connections,
    @@wait_timeout as wait_timeout,
    @@interactive_timeout as interactive_timeout;

-- Threading Settings
SELECT 
    'Threading Settings' as category,
    @@thread_cache_size as thread_cache_size;

-- Table Cache Settings
SELECT 
    'Table Cache Settings' as category,
    @@table_open_cache as table_open_cache,
    @@table_definition_cache as table_definition_cache;

-- InnoDB Settings
SELECT 
    'InnoDB Settings' as category,
    @@innodb_lock_wait_timeout as innodb_lock_wait_timeout;

-- Query Logging
SELECT 
    'Query Logging' as category,
    @@slow_query_log as slow_query_log,
    @@long_query_time as long_query_time;

-- ============================================
-- بخش 7: بررسی وضعیت اتصالات
-- ============================================

-- تعداد اتصالات فعلی
SELECT 
    'Connection Status' as category,
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') as threads_connected,
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') as max_connections,
    ROUND(
        (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') /
        (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') * 100,
        2
    ) as connection_usage_percent;

