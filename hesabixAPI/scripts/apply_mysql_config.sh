#!/bin/bash
# اسکریپت برای اعمال تنظیمات MySQL Phase 1
# این اسکریپت تنظیمات بهینه‌سازی را روی MySQL موجود اعمال می‌کند

set -e  # در صورت خطا، script متوقف می‌شود

# رنگ‌ها برای output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 شروع اعمال تنظیمات MySQL Phase 1...${NC}"

# دریافت اطلاعات اتصال
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_NAME="${DB_NAME:-hesabix}"

# دریافت رمز عبور
if [ -z "$DB_PASSWORD" ]; then
    echo -e "${YELLOW}⚠️  رمز عبور MySQL را وارد کنید (یا از متغیر محیطی DB_PASSWORD استفاده کنید):${NC}"
    read -s DB_PASSWORD
    echo
fi

MYSQL_CMD="mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} -p${DB_PASSWORD}"

echo -e "${GREEN}✅ اتصال به MySQL برقرار شد${NC}"

# بررسی نسخه MySQL
echo -e "${YELLOW}📊 بررسی نسخه MySQL...${NC}"
MYSQL_VERSION=$(${MYSQL_CMD} -se "SELECT VERSION();")
echo -e "${GREEN}   نسخه MySQL: ${MYSQL_VERSION}${NC}"

# بررسی تنظیمات فعلی
echo -e "\n${YELLOW}📋 تنظیمات فعلی MySQL:${NC}"
echo -e "${YELLOW}   max_connections:${NC}"
${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'max_connections';"

echo -e "${YELLOW}   innodb_buffer_pool_size:${NC}"
${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"

echo -e "${YELLOW}   innodb_buffer_pool_instances:${NC}"
${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'innodb_buffer_pool_instances';"

# ============================================
# بخش 1: تنظیمات Runtime (بدون نیاز به Restart)
# ============================================
echo -e "\n${GREEN}🔧 اعمال تنظیمات Runtime (بدون نیاز به Restart)...${NC}"

# افزایش max_connections (اگر کمتر از 2000 باشد)
CURRENT_MAX_CONN=$(${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'max_connections';" | awk '{print $2}')
if [ "$CURRENT_MAX_CONN" -lt 2000 ]; then
    echo -e "${YELLOW}   افزایش max_connections از ${CURRENT_MAX_CONN} به 2000...${NC}"
    ${MYSQL_CMD} -e "SET GLOBAL max_connections = 2000;"
    echo -e "${GREEN}   ✅ max_connections به 2000 افزایش یافت${NC}"
else
    echo -e "${GREEN}   ✅ max_connections قبلاً ${CURRENT_MAX_CONN} است (کافی است)${NC}"
fi

# تنظیم max_user_connections
echo -e "${YELLOW}   تنظیم max_user_connections به 1000...${NC}"
${MYSQL_CMD} -e "SET GLOBAL max_user_connections = 1000;" 2>/dev/null || echo -e "${YELLOW}   ⚠️  max_user_connections تنظیم نشد (ممکن است در نسخه شما پشتیبانی نشود)${NC}"

# تنظیم wait_timeout و interactive_timeout
echo -e "${YELLOW}   تنظیم wait_timeout و interactive_timeout...${NC}"
${MYSQL_CMD} -e "SET GLOBAL wait_timeout = 600;"
${MYSQL_CMD} -e "SET GLOBAL interactive_timeout = 600;"
echo -e "${GREEN}   ✅ Timeouts تنظیم شد${NC}"

# تنظیم innodb_lock_wait_timeout
echo -e "${YELLOW}   تنظیم innodb_lock_wait_timeout...${NC}"
${MYSQL_CMD} -e "SET GLOBAL innodb_lock_wait_timeout = 50;"
echo -e "${GREEN}   ✅ innodb_lock_wait_timeout تنظیم شد${NC}"

# فعال‌سازی Slow Query Log
echo -e "${YELLOW}   فعال‌سازی Slow Query Log...${NC}"
${MYSQL_CMD} -e "SET GLOBAL slow_query_log = 'ON';"
${MYSQL_CMD} -e "SET GLOBAL long_query_time = 2;"
echo -e "${GREEN}   ✅ Slow Query Log فعال شد${NC}"

# فعال‌سازی Performance Schema
echo -e "${YELLOW}   بررسی Performance Schema...${NC}"
PERF_SCHEMA=$(${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'performance_schema';" | awk '{print $2}')
if [ "$PERF_SCHEMA" = "ON" ]; then
    echo -e "${GREEN}   ✅ Performance Schema قبلاً فعال است${NC}"
else
    echo -e "${YELLOW}   ⚠️  Performance Schema فعال نیست (نیاز به Restart برای فعال‌سازی)${NC}"
fi

# ============================================
# بخش 2: تنظیمات Persistent (نیاز به Restart)
# ============================================
echo -e "\n${YELLOW}📝 ایجاد فایل کانفیگ برای تنظیمات Persistent...${NC}"

# پیدا کردن مسیر کانفیگ MySQL
if command -v mysqld &> /dev/null; then
    MYSQLD_PATH=$(which mysqld)
    MYSQL_VERSION_INFO=$(${MYSQL_CMD} -se "SELECT VERSION();")
    echo -e "${GREEN}   MySQL Path: ${MYSQLD_PATH}${NC}"
    echo -e "${GREEN}   MySQL Version: ${MYSQL_VERSION_INFO}${NC}"
fi

# پیدا کردن مسیر my.cnf یا my.ini
MYSQL_CNF_PATH=""
if [ -f "/etc/mysql/my.cnf" ]; then
    MYSQL_CNF_PATH="/etc/mysql/my.cnf"
elif [ -f "/etc/my.cnf" ]; then
    MYSQL_CNF_PATH="/etc/my.cnf"
elif [ -f "/usr/local/mysql/my.cnf" ]; then
    MYSQL_CNF_PATH="/usr/local/mysql/my.cnf"
elif [ -f "~/.my.cnf" ]; then
    MYSQL_CNF_PATH="~/.my.cnf"
fi

if [ -n "$MYSQL_CNF_PATH" ]; then
    echo -e "${GREEN}   فایل کانفیگ پیدا شد: ${MYSQL_CNF_PATH}${NC}"
    
    # بررسی اینکه آیا تنظیمات Hesabix قبلاً اضافه شده است
    if grep -q "# Hesabix Phase 1 Optimization" "$MYSQL_CNF_PATH" 2>/dev/null; then
        echo -e "${YELLOW}   ⚠️  تنظیمات Hesabix قبلاً در فایل کانفیگ موجود است${NC}"
        read -p "   آیا می‌خواهید دوباره اضافه شود؟ (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}   ✅ تنظیمات موجود حفظ شد${NC}"
        else
            # حذف بخش قبلی
            sed -i '/# Hesabix Phase 1 Optimization/,/# End Hesabix Phase 1 Optimization/d' "$MYSQL_CNF_PATH"
            echo -e "${YELLOW}   تنظیمات قدیمی حذف شد${NC}"
        fi
    fi
    
    # بررسی اینکه آیا باید تنظیمات را اضافه کنیم
    if ! grep -q "# Hesabix Phase 1 Optimization" "$MYSQL_CNF_PATH" 2>/dev/null; then
        echo -e "${YELLOW}   اضافه کردن تنظیمات Hesabix به فایل کانفیگ...${NC}"
        
        # ایجاد backup
        sudo cp "$MYSQL_CNF_PATH" "${MYSQL_CNF_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${GREEN}   ✅ Backup ایجاد شد: ${MYSQL_CNF_PATH}.backup.$(date +%Y%m%d_%H%M%S)${NC}"
        
        # اضافه کردن تنظیمات
        cat >> "$MYSQL_CNF_PATH" << 'EOF'

# Hesabix Phase 1 Optimization - Database Scalability
[mysqld]
# Connection Settings
max_connections = 2000
max_user_connections = 1000
connect_timeout = 10
wait_timeout = 600
interactive_timeout = 600

# InnoDB Settings
innodb_lock_wait_timeout = 50
innodb_buffer_pool_instances = 8

# Slow Query Log
slow_query_log = 1
long_query_time = 2

# Performance Schema
performance_schema = ON

# Table Cache
table_open_cache = 4000
table_definition_cache = 2000

# Temporary Tables
tmp_table_size = 256M
max_heap_table_size = 256M

# Sort and Join
sort_buffer_size = 4M
join_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 4M

# Network
max_allowed_packet = 64M

# Threading
thread_cache_size = 50
thread_stack = 256K

# End Hesabix Phase 1 Optimization
EOF
        
        echo -e "${GREEN}   ✅ تنظیمات به فایل کانفیگ اضافه شد${NC}"
        echo -e "${YELLOW}   ⚠️  برای اعمال کامل تنظیمات، MySQL را Restart کنید:${NC}"
        echo -e "${YELLOW}      sudo systemctl restart mysql${NC}"
        echo -e "${YELLOW}      یا${NC}"
        echo -e "${YELLOW}      sudo service mysql restart${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️  فایل کانفیگ MySQL پیدا نشد${NC}"
    echo -e "${YELLOW}   فایل mysql.conf در دایرکتوری hesabixAPI ایجاد شده است${NC}"
    echo -e "${YELLOW}   لطفاً آن را به مسیر مناسب کپی کنید:${NC}"
    echo -e "${YELLOW}      sudo cp hesabixAPI/mysql.conf /etc/mysql/conf.d/hesabix-optimization.cnf${NC}"
fi

# ============================================
# بخش 3: بررسی و نمایش تنظیمات جدید
# ============================================
echo -e "\n${GREEN}✅ بررسی تنظیمات اعمال شده:${NC}"

echo -e "\n${YELLOW}📊 تنظیمات جدید:${NC}"
echo -e "${YELLOW}   max_connections:${NC}"
${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'max_connections';"

echo -e "${YELLOW}   wait_timeout:${NC}"
${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'wait_timeout';"

echo -e "${YELLOW}   slow_query_log:${NC}"
${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'slow_query_log';"

echo -e "${YELLOW}   long_query_time:${NC}"
${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'long_query_time';"

# بررسی اتصالات فعال
echo -e "\n${YELLOW}📊 وضعیت اتصالات فعلی:${NC}"
${MYSQL_CMD} -e "
SELECT 
    'Total Connections' as metric,
    COUNT(*) as value
FROM information_schema.processlist
UNION ALL
SELECT 
    'Active Queries',
    SUM(CASE WHEN command != 'Sleep' THEN 1 ELSE 0 END)
FROM information_schema.processlist
UNION ALL
SELECT 
    'Sleeping Connections',
    SUM(CASE WHEN command = 'Sleep' THEN 1 ELSE 0 END)
FROM information_schema.processlist;"

# ============================================
# بخش 4: توصیه‌ها
# ============================================
echo -e "\n${GREEN}💡 توصیه‌ها:${NC}"

# بررسی innodb_buffer_pool_size
CURRENT_BUFFER_POOL=$(${MYSQL_CMD} -se "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" | awk '{print $2}')
BUFFER_POOL_MB=$((CURRENT_BUFFER_POOL / 1024 / 1024))

echo -e "${YELLOW}   1. innodb_buffer_pool_size:${NC}"
echo -e "      فعلی: ${BUFFER_POOL_MB} MB"

# محاسبه مقدار پیشنهادی (70% RAM)
if command -v free &> /dev/null; then
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    RECOMMENDED_BUFFER_MB=$((TOTAL_RAM_MB * 70 / 100))
    
    if [ "$BUFFER_POOL_MB" -lt "$RECOMMENDED_BUFFER_MB" ]; then
        echo -e "${YELLOW}      پیشنهادی: ${RECOMMENDED_BUFFER_MB} MB (70% RAM)${NC}"
        echo -e "${YELLOW}      برای تنظیم، به فایل کانفیگ اضافه کنید:${NC}"
        echo -e "${YELLOW}      innodb_buffer_pool_size = ${RECOMMENDED_BUFFER_MB}M${NC}"
    else
        echo -e "${GREEN}      ✅ مقدار فعلی کافی است${NC}"
    fi
fi

echo -e "\n${YELLOW}   2. برای اعمال کامل تمام تنظیمات (خصوصاً innodb_buffer_pool_size):${NC}"
echo -e "${YELLOW}      MySQL را Restart کنید${NC}"

echo -e "\n${YELLOW}   3. برای بررسی تنظیمات بعد از Restart:${NC}"
echo -e "${YELLOW}      ${MYSQL_CMD} -e 'SHOW VARIABLES LIKE \"max_connections\";'${NC}"

echo -e "\n${GREEN}✅ اعمال تنظیمات MySQL Phase 1 تکمیل شد!${NC}"
echo -e "${YELLOW}⚠️  توجه: برخی تنظیمات (خصوصاً innodb_buffer_pool_size) نیاز به Restart MySQL دارند${NC}"

