#!/usr/bin/env python3
"""
اسکریپت تست اتصال برای migration
این اسکریپت فقط اتصالات را تست می‌کند و هیچ تغییری در دیتابیس ایجاد نمی‌کند
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from urllib.parse import quote_plus

# تنظیمات
MYSQL_CONFIG = {
    'host': '185.8.172.57',
    'user': 'root',
    'password': '136431',
    'database': 'hesabixpy',
    'port': 3306,
}

POSTGRES_CONFIG = {
    'host': 'localhost',
    'user': 'hesabix',
    'password': '@@babaK24055',
    'database': 'hesabix',
    'port': 5432,
}

def test_mysql_connection():
    """تست اتصال به MySQL"""
    print("🔍 تست اتصال به MySQL...")
    try:
        mysql_dsn = f"mysql+pymysql://{MYSQL_CONFIG['user']}:{MYSQL_CONFIG['password']}@{MYSQL_CONFIG['host']}:{MYSQL_CONFIG['port']}/{MYSQL_CONFIG['database']}"
        engine = create_engine(mysql_dsn, echo=False, pool_pre_ping=True, connect_args={'connect_timeout': 10})
        
        with engine.connect() as conn:
            result = conn.execute(text("SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = :schema"), 
                                {'schema': MYSQL_CONFIG['database']})
            table_count = result.scalar()
            print(f"  ✅ اتصال موفق! تعداد جداول: {table_count}")
            return True
    except Exception as e:
        print(f"  ❌ خطا در اتصال به MySQL: {e}")
        return False

def test_postgres_connection():
    """تست اتصال به PostgreSQL"""
    print("\n🔍 تست اتصال به PostgreSQL...")
    try:
        postgres_dsn = f"postgresql+psycopg2://{POSTGRES_CONFIG['user']}:{quote_plus(POSTGRES_CONFIG['password'])}@{POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}"
        engine = create_engine(postgres_dsn, echo=False, pool_pre_ping=True, connect_args={'connect_timeout': 10})
        
        with engine.connect() as conn:
            result = conn.execute(text("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"))
            table_count = result.scalar()
            print(f"  ✅ اتصال موفق! تعداد جداول: {table_count}")
            return True
    except Exception as e:
        print(f"  ❌ خطا در اتصال به PostgreSQL: {e}")
        return False

def test_table_comparison():
    """مقایسه جداول بین MySQL و PostgreSQL"""
    print("\n🔍 مقایسه جداول...")
    try:
        # MySQL
        mysql_dsn = f"mysql+pymysql://{MYSQL_CONFIG['user']}:{MYSQL_CONFIG['password']}@{MYSQL_CONFIG['host']}:{MYSQL_CONFIG['port']}/{MYSQL_CONFIG['database']}"
        mysql_engine = create_engine(mysql_dsn, echo=False, pool_pre_ping=True, connect_args={'connect_timeout': 10})
        
        # PostgreSQL
        postgres_dsn = f"postgresql+psycopg2://{POSTGRES_CONFIG['user']}:{quote_plus(POSTGRES_CONFIG['password'])}@{POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}"
        postgres_engine = create_engine(postgres_dsn, echo=False, pool_pre_ping=True, connect_args={'connect_timeout': 10})
        
        with mysql_engine.connect() as mysql_conn:
            mysql_result = mysql_conn.execute(text("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = :schema 
                AND table_name != 'alembic_version'
                ORDER BY table_name
            """), {'schema': MYSQL_CONFIG['database']})
            mysql_tables = {row[0] for row in mysql_result}
        
        with postgres_engine.connect() as postgres_conn:
            postgres_result = postgres_conn.execute(text("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_type = 'BASE TABLE'
                AND table_name != 'alembic_version'
                ORDER BY table_name
            """))
            postgres_tables = {row[0] for row in postgres_result}
        
        common_tables = mysql_tables & postgres_tables
        only_mysql = mysql_tables - postgres_tables
        only_postgres = postgres_tables - mysql_tables
        
        print(f"  📊 جداول مشترک: {len(common_tables)}")
        print(f"  📊 فقط در MySQL: {len(only_mysql)}")
        print(f"  📊 فقط در PostgreSQL: {len(only_postgres)}")
        
        if only_mysql:
            print(f"  ⚠️ جداول فقط در MySQL (نمونه): {list(only_mysql)[:5]}")
        if only_postgres:
            print(f"  ⚠️ جداول فقط در PostgreSQL (نمونه): {list(only_postgres)[:5]}")
        
        return True
    except Exception as e:
        print(f"  ❌ خطا در مقایسه جداول: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    print("="*60)
    print("🧪 تست اتصالات برای Migration")
    print("="*60)
    
    mysql_ok = test_mysql_connection()
    postgres_ok = test_postgres_connection()
    
    if mysql_ok and postgres_ok:
        test_table_comparison()
        print("\n" + "="*60)
        print("✅ همه تست‌ها موفق بودند!")
        print("="*60)
    else:
        print("\n" + "="*60)
        print("❌ برخی تست‌ها ناموفق بودند")
        print("="*60)
        sys.exit(1)

