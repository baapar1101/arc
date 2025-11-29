# راهنمای جامع بهبود مقیاس‌پذیری پایگاه داده - Hesabix

## 📋 فهرست مطالب

1. [تحلیل مشکلات فعلی](#تحلیل-مشکلات-فعلی)
2. [راه‌حل‌های پیشنهادی](#راه‌حل‌های-پیشنهادی)
3. [بهینه‌سازی Connection Pool](#بهینه‌سازی-connection-pool)
4. [پیاده‌سازی Read Replicas](#پیاده‌سازی-read-replicas)
5. [Partitioning جداول بزرگ](#partitioning-جداول-بزرگ)
6. [بهینه‌سازی MySQL Configuration](#بهینه‌سازی-mysql-configuration)
7. [Monitoring و Metrics](#monitoring-و-metrics)
8. [Migration Plan](#migration-plan)

---

## 🔍 تحلیل مشکلات فعلی

### 1. Connection Pool محدود

#### وضعیت فعلی:
```python
# hesabixAPI/app/core/settings.py
db_pool_size: int = 20          # اتصالات پایه
db_max_overflow: int = 30       # اتصالات اضافی
# حداکثر: 50 اتصال per worker
```

#### مشکل:
- با 17 worker: `17 * 50 = 850` اتصال حداکثر
- برای میلیون‌ها کاربر، این عدد کافی نیست
- در Peak Times، احتمال Connection Exhaustion وجود دارد

### 2. Single Database Instance

#### مشکل:
- تمام Read و Write queries به یک دیتابیس می‌روند
- در Scale بالا، Write Operations باعث Lock می‌شوند
- Read Operations تحت تأثیر Write Operations قرار می‌گیرند

### 3. عدم استفاده از Replication

#### مشکل:
- Single Point of Failure
- عدم توزیع بار بین چند دیتابیس
- عدم امکان Horizontal Scaling

### 4. جداول بزرگ بدون Partitioning

#### جداول مشکل‌دار:
- `documents`: با رشد بالا
- `activity_logs`: با تعداد زیاد رکورد
- `file_storage`: با حجم بالا

#### مشکل:
- Query های کند روی جداول بزرگ
- Index Maintenance سنگین
- Backup و Restore زمان‌بر

### 5. MySQL Configuration بهینه نیست

#### مشکلات:
- `max_connections` پیش‌فرض (151) بسیار پایین است
- `innodb_buffer_pool_size` بهینه نشده
- Query Cache غیرفعال یا ناکافی

---

## ✅ راه‌حل‌های پیشنهادی

### راه‌حل 1: بهینه‌سازی Connection Pool (Quick Win)

#### 1.1 افزایش Pool Size

**فایل**: `hesabixAPI/app/core/settings.py`

```python
# تنظیمات پیشنهادی برای Production
class Settings(BaseSettings):
    # Connection Pool برای Production
    # محاسبه: (تعداد Worker ها * اتصالات مورد نیاز per Worker) + Buffer
    # مثال: 5 Workers * 100 اتصال = 500 + 300 buffer = 800
    db_pool_size: int = 100  # افزایش از 20
    db_max_overflow: int = 100  # افزایش از 30
    db_pool_timeout: int = 30  # افزایش از 10
    db_pool_recycle: int = 3600  # Recycle هر ساعت
    db_pool_pre_ping: bool = True  # Health check قبل از استفاده
```

#### 1.2 بهبود Session Management

**فایل**: `hesabixAPI/adapters/db/session.py`

```python
from sqlalchemy import create_engine, event
from sqlalchemy.pool import QueuePool

settings = get_settings()

# Engine با تنظیمات بهینه شده
engine = create_engine(
    settings.mysql_dsn,
    echo=settings.sqlalchemy_echo,
    poolclass=QueuePool,  # استفاده از QueuePool برای بهتر control
    pool_pre_ping=True,  # بررسی سلامت اتصالات
    pool_recycle=settings.db_pool_recycle,  # Recycle اتصالات قدیمی
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_timeout=settings.db_pool_timeout,
    connect_args={
        "connect_timeout": 10,
        "read_timeout": 60,  # افزایش برای Query های طولانی
        "write_timeout": 60,
        "charset": "utf8mb4",
        "init_command": "SET sql_mode='STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO'",
    },
    # بهینه‌سازی برای Performance
    pool_reset_on_return='commit',  # Reset connection بعد از return
    isolation_level="READ COMMITTED",  # برای بهتر Concurrency
)

# Event Listener برای Logging Pool Statistics
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_conn, connection_record):
    """تنظیمات MySQL برای هر Connection"""
    try:
        with dbapi_conn.cursor() as cursor:
            # بهینه‌سازی Query Cache
            cursor.execute("SET SESSION query_cache_type = ON")
            # بهینه‌سازی برای InnoDB
            cursor.execute("SET SESSION innodb_lock_wait_timeout = 50")
            # بهینه‌سازی برای Read Performance
            cursor.execute("SET SESSION transaction_isolation = 'READ-COMMITTED'")
    except Exception as e:
        logger.warning(f"Error setting MySQL session variables: {e}")

# Logging Pool Statistics
@event.listens_for(engine.pool, "connect")
def receive_connect(dbapi_conn, connection_record):
    logger.debug(f"New database connection created. Pool size: {engine.pool.size()}, "
                f"Checked out: {engine.pool.checkedout()}")

@event.listens_for(engine.pool, "checkout")
def receive_checkout(dbapi_conn, connection_record, connection_proxy):
    logger.debug(f"Connection checked out. Pool size: {engine.pool.size()}, "
                f"Checked out: {engine.pool.checkedout()}")

@event.listens_for(engine.pool, "checkin")
def receive_checkin(dbapi_conn, connection_record):
    logger.debug(f"Connection checked in. Pool size: {engine.pool.size()}, "
                f"Checked out: {engine.pool.checkedout()}")
```

#### 1.3 Connection Pool Monitoring

**فایل جدید**: `hesabixAPI/app/core/db_pool_monitor.py`

```python
"""
Connection Pool Monitoring
برای مانیتورینگ وضعیت Connection Pool
"""
from sqlalchemy import event, inspect
from adapters.db.session import engine
import logging
import time
from typing import Dict

logger = logging.getLogger(__name__)

class ConnectionPoolMonitor:
    """Monitor برای Connection Pool"""
    
    @staticmethod
    def get_pool_stats() -> Dict[str, int]:
        """دریافت آمار Connection Pool"""
        pool = engine.pool
        return {
            "pool_size": pool.size(),
            "checked_out": pool.checkedout(),
            "overflow": pool.overflow(),
            "checked_in": pool.size() - pool.checkedout(),
        }
    
    @staticmethod
    def log_pool_stats():
        """Log آمار Connection Pool"""
        stats = ConnectionPoolMonitor.get_pool_stats()
        logger.info(f"Connection Pool Stats: {stats}")
        
        # Alert در صورت Full Pool
        if stats["checked_out"] >= (stats["pool_size"] + stats.get("overflow", 0)) * 0.9:
            logger.warning(f"Connection Pool nearly exhausted! {stats}")

# Event Listener برای Monitoring
@event.listens_for(engine.pool, "checkout")
def on_checkout(dbapi_conn, connection_record, connection_proxy):
    stats = ConnectionPoolMonitor.get_pool_stats()
    if stats["checked_out"] >= stats["pool_size"] * 0.8:
        logger.warning(f"High connection pool usage: {stats}")

# Periodic monitoring (می‌توان در Background Job اضافه کرد)
```

---

### راه‌حل 2: پیاده‌سازی Read Replicas (High Impact)

#### 2.1 ساختار Database Routing

**فایل جدید**: `hesabixAPI/adapters/db/routing.py`

```python
"""
Database Routing برای Read/Write Splitting
"""
from typing import Generator
from contextlib import contextmanager
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
import random
import logging

from app.core.settings import get_settings

logger = logging.getLogger(__name__)

class DatabaseRouter:
    """Router برای توزیع Read/Write Queries"""
    
    def __init__(self):
        self.settings = get_settings()
        self._write_engine = None
        self._read_engines = []
        self._read_sessions = []
        
    @property
    def write_engine(self):
        """Engine برای Write Operations"""
        if self._write_engine is None:
            self._write_engine = self._create_engine(
                host=self.settings.db_host,
                port=self.settings.db_port,
                user=self.settings.db_user,
                password=self.settings.db_password,
                database=self.settings.db_name,
                pool_size=self.settings.db_pool_size,
                max_overflow=self.settings.db_max_overflow,
            )
        return self._write_engine
    
    @property
    def read_engines(self):
        """Engines برای Read Operations"""
        if not self._read_engines:
            # خواندن لیست Read Replicas از Settings
            read_hosts = self._get_read_replicas()
            for host_config in read_hosts:
                engine = self._create_engine(
                    host=host_config["host"],
                    port=host_config.get("port", self.settings.db_port),
                    user=host_config.get("user", self.settings.db_user),
                    password=host_config.get("password", self.settings.db_password),
                    database=self.settings.db_name,
                    pool_size=self.settings.db_pool_size // 2,  # نصف Write Pool
                    max_overflow=self.settings.db_max_overflow // 2,
                )
                self._read_engines.append(engine)
        
        return self._read_engines
    
    def _create_engine(self, host, port, user, password, database, pool_size, max_overflow):
        """ایجاد Engine با تنظیمات مشخص"""
        dsn = f"mysql+pymysql://{user}:{password}@{host}:{port}/{database}"
        return create_engine(
            dsn,
            pool_pre_ping=True,
            pool_recycle=3600,
            pool_size=pool_size,
            max_overflow=max_overflow,
            pool_timeout=30,
            connect_args={
                "connect_timeout": 10,
                "read_timeout": 60,
                "write_timeout": 60,
            },
        )
    
    def _get_read_replicas(self) -> list:
        """دریافت لیست Read Replicas از Settings"""
        # می‌توان از Environment Variables یا Settings استفاده کرد
        read_replicas_str = getattr(self.settings, 'db_read_replicas', '')
        if not read_replicas_str:
            # اگر Read Replica تعریف نشده، از Write استفاده می‌کنیم
            return [{"host": self.settings.db_host}]
        
        replicas = []
        for replica_str in read_replicas_str.split(','):
            parts = replica_str.strip().split(':')
            replica = {"host": parts[0]}
            if len(parts) > 1:
                replica["port"] = int(parts[1])
            replicas.append(replica)
        
        return replicas
    
    def get_read_engine(self):
        """دریافت یک Read Engine به صورت Random (Load Balancing)"""
        engines = self.read_engines
        if not engines:
            # Fallback به Write Engine اگر Read Replica نباشد
            return self.write_engine
        return random.choice(engines)
    
    @contextmanager
    def get_read_session(self) -> Generator[Session, None, None]:
        """Context Manager برای Read Session"""
        engine = self.get_read_engine()
        session = sessionmaker(bind=engine, autoflush=False, autocommit=False)()
        try:
            yield session
        finally:
            session.close()
    
    @contextmanager
    def get_write_session(self) -> Generator[Session, None, None]:
        """Context Manager برای Write Session"""
        session = sessionmaker(bind=self.write_engine, autoflush=False, autocommit=False)()
        try:
            yield session
        finally:
            session.close()

# Global Router Instance
_router = None

def get_router() -> DatabaseRouter:
    """Get global database router"""
    global _router
    if _router is None:
        _router = DatabaseRouter()
    return _router

def get_read_db() -> Generator[Session, None, None]:
    """Dependency برای FastAPI - Read Database"""
    router = get_router()
    with router.get_read_session() as session:
        yield session

def get_write_db() -> Generator[Session, None, None]:
    """Dependency برای FastAPI - Write Database"""
    router = get_router()
    with router.get_write_session() as session:
        yield session
```

#### 2.2 افزودن Settings برای Read Replicas

**فایل**: `hesabixAPI/app/core/settings.py`

```python
class Settings(BaseSettings):
    # ... existing settings ...
    
    # Database Read Replicas
    # فرمت: host1:port1,host2:port2,host3:port3
    # مثال: replica1.example.com:3306,replica2.example.com:3306
    db_read_replicas: str = ""  # لیست Read Replicas (comma-separated)
    
    # Separate credentials for read replicas (optional)
    db_read_user: str | None = None
    db_read_password: str | None = None
```

#### 2.3 استفاده از Read Replicas در Endpoints

**مثال**: `hesabixAPI/adapters/api/v1/products.py`

```python
from adapters.db.routing import get_read_db, get_write_db
from sqlalchemy.orm import Session

# برای Read Operations (GET)
@router.get("/products")
async def list_products(
    db: Session = Depends(get_read_db),  # استفاده از Read Replica
    ...
):
    # Read operations
    ...

# برای Write Operations (POST, PUT, DELETE)
@router.post("/products")
async def create_product(
    db: Session = Depends(get_write_db),  # استفاده از Master
    ...
):
    # Write operations
    ...
```

---

### راه‌حل 3: Partitioning جداول بزرگ

#### 3.1 Partitioning Strategy

**Migration File**: `hesabixAPI/migrations/versions/add_partitioning.py`

```python
"""Partitioning جداول بزرگ برای بهبود Performance"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import text

def upgrade():
    """
    اضافه کردن Partitioning برای جداول بزرگ
    """
    
    # 1. Partitioning برای documents بر اساس business_id
    # استفاده از HASH Partitioning برای توزیع یکنواخت
    try:
        op.execute(text("""
            ALTER TABLE documents 
            PARTITION BY HASH(business_id) 
            PARTITIONS 16
        """))
        print("✅ Partitioning added to documents table")
    except Exception as e:
        print(f"⚠️  Warning: Could not partition documents: {e}")
    
    # 2. Partitioning برای activity_logs بر اساس created_at
    # استفاده از RANGE Partitioning برای جداول زمانی
    try:
        op.execute(text("""
            ALTER TABLE activity_logs 
            PARTITION BY RANGE (TO_DAYS(created_at)) (
                PARTITION p_2024_q1 VALUES LESS THAN (TO_DAYS('2024-04-01')),
                PARTITION p_2024_q2 VALUES LESS THAN (TO_DAYS('2024-07-01')),
                PARTITION p_2024_q3 VALUES LESS THAN (TO_DAYS('2024-10-01')),
                PARTITION p_2024_q4 VALUES LESS THAN (TO_DAYS('2025-01-01')),
                PARTITION p_future VALUES LESS THAN MAXVALUE
            )
        """))
        print("✅ Partitioning added to activity_logs table")
    except Exception as e:
        print(f"⚠️  Warning: Could not partition activity_logs: {e}")
    
    # 3. Partitioning برای file_storage (اختیاری)
    # اگر جدول خیلی بزرگ شد، می‌توان Partitioning اضافه کرد

def downgrade():
    """
    حذف Partitioning (احتیاط: ممکن است زمان‌بر باشد)
    """
    try:
        op.execute(text("ALTER TABLE documents REMOVE PARTITIONING"))
        print("✅ Partitioning removed from documents table")
    except Exception as e:
        print(f"⚠️  Warning: {e}")
    
    try:
        op.execute(text("ALTER TABLE activity_logs REMOVE PARTITIONING"))
        print("✅ Partitioning removed from activity_logs table")
    except Exception as e:
        print(f"⚠️  Warning: {e}")
```

#### 3.2 Partition Maintenance Script

**فایل جدید**: `hesabixAPI/scripts/maintain_partitions.py`

```python
"""
Script برای نگهداری Partitions
- اضافه کردن Partitions جدید
- حذف Partitions قدیمی
"""
from sqlalchemy import create_engine, text
from app.core.settings import get_settings
from datetime import datetime, timedelta

def add_monthly_partitions(connection, table_name: str, months_ahead: int = 3):
    """
    اضافه کردن Partitions ماهانه برای جداول زمانی
    """
    for i in range(months_ahead):
        month_date = datetime.now() + timedelta(days=30 * (i + 1))
        month_start = month_date.replace(day=1)
        next_month_start = (month_start + timedelta(days=32)).replace(day=1)
        
        partition_name = f"p_{month_start.strftime('%Y_%m')}"
        
        try:
            connection.execute(text(f"""
                ALTER TABLE {table_name}
                REORGANIZE PARTITION p_future INTO (
                    PARTITION {partition_name} VALUES LESS THAN (TO_DAYS('{next_month_start.strftime('%Y-%m-%d')}')),
                    PARTITION p_future VALUES LESS THAN MAXVALUE
                )
            """))
            print(f"✅ Added partition {partition_name} to {table_name}")
        except Exception as e:
            print(f"⚠️  Warning: {e}")

def drop_old_partitions(connection, table_name: str, months_to_keep: int = 12):
    """
    حذف Partitions قدیمی تر از X ماه
    """
    cutoff_date = datetime.now() - timedelta(days=30 * months_to_keep)
    
    # Query برای پیدا کردن Partitions قدیمی
    result = connection.execute(text(f"""
        SELECT PARTITION_NAME 
        FROM INFORMATION_SCHEMA.PARTITIONS 
        WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = '{table_name}'
        AND PARTITION_NAME IS NOT NULL
        AND PARTITION_NAME != 'p_future'
    """))
    
    for row in result:
        partition_name = row[0]
        # Extract date from partition name (format: p_YYYY_MM)
        try:
            year_month = partition_name.split('_')[1:]
            if len(year_month) >= 2:
                year, month = int(year_month[0]), int(year_month[1])
                partition_date = datetime(year, month, 1)
                
                if partition_date < cutoff_date:
                    connection.execute(text(f"""
                        ALTER TABLE {table_name} DROP PARTITION {partition_name}
                    """))
                    print(f"✅ Dropped old partition {partition_name}")
        except Exception as e:
            print(f"⚠️  Warning: Could not process partition {partition_name}: {e}")

if __name__ == "__main__":
    settings = get_settings()
    engine = create_engine(settings.mysql_dsn)
    
    with engine.connect() as connection:
        # اضافه کردن Partitions جدید
        add_monthly_partitions(connection, "activity_logs", months_ahead=3)
        
        # حذف Partitions قدیمی (نگه داشتن 12 ماه)
        drop_old_partitions(connection, "activity_logs", months_to_keep=12)
    
    print("✅ Partition maintenance completed")
```

---

### راه‌حل 4: بهینه‌سازی MySQL Configuration

#### 4.1 MySQL Configuration File

**فایل**: `mysql.conf` (برای Production)

```ini
[mysqld]
# Connection Settings
max_connections = 2000  # افزایش از پیش‌فرض 151
max_user_connections = 1000
connect_timeout = 10
wait_timeout = 600
interactive_timeout = 600

# InnoDB Settings
innodb_buffer_pool_size = 70% RAM  # مثال: برای 32GB RAM = 22GB
innodb_buffer_pool_instances = 8  # برای RAM > 1GB
innodb_log_file_size = 512M
innodb_log_buffer_size = 64M
innodb_flush_log_at_trx_commit = 2  # بهتر برای Performance (trade-off با Durability)
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_read_io_threads = 8
innodb_write_io_threads = 8

# Query Cache (MySQL 5.7 - در 8.0 حذف شده)
# query_cache_type = 1
# query_cache_size = 256M
# query_cache_limit = 2M

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

# Binary Logging (برای Replication)
log_bin = /var/log/mysql/mysql-bin.log
binlog_format = ROW
expire_logs_days = 7
max_binlog_size = 500M

# Slow Query Log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow-query.log
long_query_time = 2  # Log queries > 2 seconds

# Error Log
log_error = /var/log/mysql/error.log

# Character Set
character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci

# MyISAM (اگر استفاده نمی‌کنید)
key_buffer_size = 32M

# Threading
thread_cache_size = 50
thread_stack = 256K

# Network
max_allowed_packet = 64M

# Performance Schema (برای Monitoring)
performance_schema = ON
```

#### 4.2 Docker Compose برای Production

**فایل**: `docker-compose.prod.yml`

```yaml
version: "3.9"

services:
  db-master:
    image: mysql:8.4
    container_name: hesabix-mysql-master
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - db_master_data:/var/lib/mysql
      - ./mysql.conf:/etc/mysql/conf.d/custom.cnf:ro
      - ./mysql-init:/docker-entrypoint-initdb.d:ro
    ports:
      - "3306:3306"
    command: --server-id=1 --log-bin=mysql-bin --binlog-format=ROW
    restart: unless-stopped

  db-replica-1:
    image: mysql:8.4
    container_name: hesabix-mysql-replica-1
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - db_replica1_data:/var/lib/mysql
      - ./mysql.conf:/etc/mysql/conf.d/custom.cnf:ro
    ports:
      - "3307:3306"
    command: --server-id=2 --relay-log=mysql-relay-bin --read-only=1
    depends_on:
      - db-master
    restart: unless-stopped

  db-replica-2:
    image: mysql:8.4
    container_name: hesabix-mysql-replica-2
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - db_replica2_data:/var/lib/mysql
      - ./mysql.conf:/etc/mysql/conf.d/custom.cnf:ro
    ports:
      - "3308:3306"
    command: --server-id=3 --relay-log=mysql-relay-bin --read-only=1
    depends_on:
      - db-master
    restart: unless-stopped

volumes:
  db_master_data:
  db_replica1_data:
  db_replica2_data:
```

#### 4.3 Setup Replication Script

**فایل جدید**: `scripts/setup_replication.sh`

```bash
#!/bin/bash
# Script برای راه‌اندازی MySQL Replication

MASTER_HOST="${MASTER_HOST:-db-master}"
MASTER_PORT="${MASTER_PORT:-3306}"
REPLICA_HOST="${REPLICA_HOST:-db-replica-1}"
REPLICA_PORT="${REPLICA_PORT:-3306}"
REPLICA_USER="${REPLICA_USER:-replica}"
REPLICA_PASSWORD="${REPLICA_PASSWORD:-replica_password}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"

echo "🔧 Setting up MySQL Replication..."

# 1. Create replication user on Master
mysql -h ${MASTER_HOST} -P ${MASTER_PORT} -uroot -p${MYSQL_ROOT_PASSWORD} <<EOF
CREATE USER IF NOT EXISTS '${REPLICA_USER}'@'%' IDENTIFIED BY '${REPLICA_PASSWORD}';
GRANT REPLICATION SLAVE ON *.* TO '${REPLICA_USER}'@'%';
FLUSH PRIVILEGES;
SHOW MASTER STATUS;
EOF

# 2. Get Master Status
MASTER_STATUS=$(mysql -h ${MASTER_HOST} -P ${MASTER_PORT} -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW MASTER STATUS\G")
BINLOG_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
BINLOG_POS=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')

echo "📊 Master Status:"
echo "  Binlog File: ${BINLOG_FILE}"
echo "  Binlog Position: ${BINLOG_POS}"

# 3. Configure Replica
mysql -h ${REPLICA_HOST} -P ${REPLICA_PORT} -uroot -p${MYSQL_ROOT_PASSWORD} <<EOF
CHANGE MASTER TO
  MASTER_HOST='${MASTER_HOST}',
  MASTER_PORT=${MASTER_PORT},
  MASTER_USER='${REPLICA_USER}',
  MASTER_PASSWORD='${REPLICA_PASSWORD}',
  MASTER_LOG_FILE='${BINLOG_FILE}',
  MASTER_LOG_POS=${BINLOG_POS};

START SLAVE;
SHOW SLAVE STATUS\G
EOF

echo "✅ Replication setup completed!"
```

---

### راه‌حل 5: Monitoring و Metrics

#### 5.1 Database Health Check Endpoint

**فایل**: `hesabixAPI/adapters/api/v1/health.py` (بهبود یافته)

```python
from sqlalchemy import text
from adapters.db.session import engine, get_db
from adapters.db.routing import get_router
import logging

logger = logging.getLogger(__name__)

@router.get("/health/database")
async def database_health(request: Request, db: Session = Depends(get_db)):
    """بررسی سلامت پایگاه داده و Connection Pool"""
    
    health_status = {
        "status": "healthy",
        "checks": {}
    }
    
    # 1. Check Master Connection
    try:
        result = db.execute(text("SELECT 1")).scalar()
        health_status["checks"]["master"] = {
            "status": "ok" if result == 1 else "error",
            "response_time_ms": 0  # می‌توان time اضافه کرد
        }
    except Exception as e:
        health_status["checks"]["master"] = {
            "status": "error",
            "error": str(e)
        }
        health_status["status"] = "unhealthy"
    
    # 2. Check Connection Pool
    pool = engine.pool
    pool_stats = {
        "pool_size": pool.size(),
        "checked_out": pool.checkedout(),
        "overflow": pool.overflow(),
        "available": pool.size() - pool.checkedout(),
        "usage_percent": (pool.checkedout() / (pool.size() + pool.overflow())) * 100 if (pool.size() + pool.overflow()) > 0 else 0
    }
    
    health_status["checks"]["connection_pool"] = pool_stats
    
    # Alert اگر Pool بیش از 90% استفاده شده
    if pool_stats["usage_percent"] > 90:
        logger.warning(f"Connection pool usage high: {pool_stats}")
        health_status["status"] = "degraded"
    
    # 3. Check Read Replicas
    try:
        router = get_router()
        read_replicas_status = []
        for i, replica_engine in enumerate(router.read_engines):
            try:
                with replica_engine.connect() as conn:
                    result = conn.execute(text("SELECT 1")).scalar()
                    read_replicas_status.append({
                        "replica_id": i + 1,
                        "status": "ok" if result == 1 else "error"
                    })
            except Exception as e:
                read_replicas_status.append({
                    "replica_id": i + 1,
                    "status": "error",
                    "error": str(e)
                })
        
        health_status["checks"]["read_replicas"] = read_replicas_status
        
        # اگر هیچ Replica سالم نباشد، degraded
        if all(r["status"] != "ok" for r in read_replicas_status):
            health_status["status"] = "degraded"
    except Exception as e:
        health_status["checks"]["read_replicas"] = {
            "error": "Not configured",
            "message": str(e)
        }
    
    # 4. Check Database Size
    try:
        result = db.execute(text("""
            SELECT 
                table_schema AS 'Database',
                ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
            FROM information_schema.TABLES
            WHERE table_schema = DATABASE()
            GROUP BY table_schema
        """))
        size_info = result.fetchone()
        health_status["checks"]["database_size"] = {
            "size_mb": float(size_info[1]) if size_info else 0
        }
    except Exception as e:
        health_status["checks"]["database_size"] = {
            "error": str(e)
        }
    
    # 5. Check Slow Queries Count
    try:
        result = db.execute(text("""
            SELECT COUNT(*) 
            FROM information_schema.processlist 
            WHERE command != 'Sleep' 
            AND time > 5
        """))
        slow_queries = result.scalar()
        health_status["checks"]["slow_queries"] = {
            "count": slow_queries or 0
        }
        if slow_queries and slow_queries > 10:
            health_status["status"] = "degraded"
    except Exception:
        pass  # ممکن است دسترسی نداشته باشیم
    
    status_code = 200 if health_status["status"] == "healthy" else 503
    return JSONResponse(status_code=status_code, content=health_status)
```

---

## 📋 Migration Plan

### Phase 1: Quick Wins (1-2 هفته)

1. ✅ **افزایش Connection Pool**
   - به‌روزرسانی `settings.py`
   - افزایش `max_connections` در MySQL
   - تست و Monitoring

2. ✅ **بهینه‌سازی MySQL Configuration**
   - ایجاد `mysql.conf`
   - Restart MySQL
   - Monitoring Performance

3. ✅ **Connection Pool Monitoring**
   - پیاده‌سازی `db_pool_monitor.py`
   - اضافه کردن Metrics به Health Check

### Phase 2: Read Replicas (3-4 هفته)

1. ✅ **Setup Read Replicas**
   - نصب و Configure MySQL Replicas
   - Setup Replication
   - تست Replication

2. ✅ **پیاده‌سازی Database Routing**
   - ایجاد `routing.py`
   - Update Settings
   - Migration Endpoints به Read/Write

3. ✅ **Testing و Rollout**
   - تست Read Replicas
   - Monitoring Replication Lag
   - Rollout تدریجی

### Phase 3: Partitioning (4-6 هفته)

1. ✅ **تحلیل جداول**
   - شناسایی جداول بزرگ
   - تحلیل Query Patterns
   - انتخاب Partitioning Strategy

2. ✅ **پیاده‌سازی Partitioning**
   - ایجاد Migration
   - Test در Staging
   - اجرا در Production (Off-peak hours)

3. ✅ **Partition Maintenance**
   - ایجاد Maintenance Scripts
   - Setup Cron Jobs
   - Monitoring

---

## 📊 Metrics برای Monitoring

### Connection Pool Metrics
- `pool_size`: اندازه Pool
- `checked_out`: تعداد اتصالات در حال استفاده
- `overflow`: تعداد اتصالات اضافی
- `usage_percent`: درصد استفاده

### Database Metrics
- `connection_count`: تعداد کل اتصالات
- `slow_query_count`: تعداد Query های کند
- `replication_lag`: تأخیر Replication (ثانیه)
- `database_size_mb`: اندازه دیتابیس

### Query Metrics
- `avg_query_time`: میانگین زمان Query
- `p95_query_time`: P95 زمان Query
- `query_count_per_second`: تعداد Query در ثانیه

---

## ⚠️ نکات مهم

1. **Backup قبل از هر تغییری**: همیشه Backup کامل بگیرید
2. **Test در Staging**: هر تغییری ابتدا در Staging تست شود
3. **Rollout تدریجی**: تغییرات را به صورت تدریجی Rollout کنید
4. **Monitoring**: همیشه Metrics را Monitor کنید
5. **Documentation**: تمام تغییرات را Document کنید

---

**آماده برای پیاده‌سازی!** 🚀

