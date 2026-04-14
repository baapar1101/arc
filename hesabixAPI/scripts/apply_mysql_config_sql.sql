-- اسکریپت SQL برای اعمال تنظیمات MySQL Phase 1
-- این فایل شامل دستورات SQL برای تنظیمات Runtime است
-- برای اجرا: mysql -u root -p < apply_mysql_config_sql.sql

-- ============================================
-- بخش 1: Connection Settings
-- ============================================

-- افزایش max_connections (اگر کمتر از 2000 باشد)
SET GLOBAL max_connections = 2000;

-- تنظیم max_user_connections (اگر پشتیبانی شود)
-- SET GLOBAL max_user_connections = 1000;  -- ممکن است در برخی نسخه‌ها کار نکند

-- تنظیم Timeouts
SET GLOBAL wait_timeout = 600;
SET GLOBAL interactive_timeout = 600;
SET GLOBAL connect_timeout = 10;

-- ============================================
-- بخش 2: InnoDB Settings
-- ============================================

-- تنظیم innodb_lock_wait_timeout
SET GLOBAL innodb_lock_wait_timeout = 50;

-- تنظیم innodb_buffer_pool_instances (نیاز به Restart)
-- این تنظیمات باید در my.cnf اضافه شوند
-- innodb_buffer_pool_instances = 8

-- ============================================
-- بخش 3: Query Logging
-- ============================================

-- فعال‌سازی Slow Query Log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;

-- نمایش مسیر Slow Query Log
SELECT @@slow_query_log_file as slow_query_log_file;

-- ============================================
-- بخش 4: Performance Schema
-- ============================================

-- بررسی وضعیت Performance Schema
SELECT @@performance_schema as performance_schema_enabled;

-- Performance Schema را نمی‌توان runtime فعال کرد
-- باید در my.cnf تنظیم شود: performance_schema = ON
-- و سپس MySQL را Restart کنید

-- ============================================
-- بخش 5: بررسی تنظیمات اعمال شده
-- ============================================

-- نمایش تنظیمات Connection
SELECT 
    'max_connections' as variable_name,
    @@max_connections as current_value,
    2000 as recommended_value;

SELECT 
    'wait_timeout' as variable_name,
    @@wait_timeout as current_value,
    600 as recommended_value;

SELECT 
    'interactive_timeout' as variable_name,
    @@interactive_timeout as current_value,
    600 as recommended_value;

-- نمایش تنظیمات InnoDB
SELECT 
    'innodb_lock_wait_timeout' as variable_name,
    @@innodb_lock_wait_timeout as current_value,
    50 as recommended_value;

SELECT 
    'innodb_buffer_pool_size' as variable_name,
    ROUND(@@innodb_buffer_pool_size / 1024 / 1024, 0) as current_value_mb,
    '70% of RAM' as recommended_value;

SELECT 
    'innodb_buffer_pool_instances' as variable_name,
    @@innodb_buffer_pool_instances as current_value,
    8 as recommended_value;

-- نمایش تنظیمات Slow Query Log
SELECT 
    'slow_query_log' as variable_name,
    @@slow_query_log as current_value,
    'ON' as recommended_value;

SELECT 
    'long_query_time' as variable_name,
    @@long_query_time as current_value,
    2 as recommended_value;

-- نمایش وضعیت Performance Schema
SELECT 
    'performance_schema' as variable_name,
    @@performance_schema as current_value,
    'ON' as recommended_value;

-- ============================================
-- بخش 6: بررسی اتصالات فعلی
-- ============================================

SELECT 
    'Total Connections' as metric,
    COUNT(*) as value
FROM information_schema.processlist;

SELECT 
    'Active Queries' as metric,
    SUM(CASE WHEN command != 'Sleep' THEN 1 ELSE 0 END) as value
FROM information_schema.processlist;

SELECT 
    'Sleeping Connections' as metric,
    SUM(CASE WHEN command = 'Sleep' THEN 1 ELSE 0 END) as value
FROM information_schema.processlist;

-- نمایش اتصالات فعال با جزئیات
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
ORDER BY time DESC
LIMIT 10;

