#!/usr/bin/env python3
"""
اسکریپت پاک کردن همه داده‌ها از PostgreSQL (به جز ساختار جداول)
این اسکریپت فقط داده‌ها را پاک می‌کند و ساختار جداول را حفظ می‌کند
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text, inspect
from urllib.parse import quote_plus

POSTGRES_CONFIG = {
    'host': 'localhost',
    'user': 'postgres',
    'password': 'babaK24055',
    'database': 'hesabix',
    'port': 5432,
}

def clear_all_data():
    """پاک کردن همه داده‌ها از جداول"""
    postgres_dsn = f"postgresql+psycopg2://{POSTGRES_CONFIG['user']}:{quote_plus(POSTGRES_CONFIG['password'])}@{POSTGRES_CONFIG['host']}:{POSTGRES_CONFIG['port']}/{POSTGRES_CONFIG['database']}"
    engine = create_engine(postgres_dsn, echo=False, pool_pre_ping=True)
    
    with engine.connect() as conn:
        # دریافت لیست همه جداول
        inspector = inspect(engine)
        tables = inspector.get_table_names()
        
        print(f"📊 پیدا کردن {len(tables)} جدول...")
        
        # غیرفعال کردن Foreign Keys موقتاً
        conn.execute(text("SET session_replication_role = 'replica'"))
        conn.commit()
        
        total_deleted = 0
        for table in tables:
            try:
                # پاک کردن داده‌های جدول
                result = conn.execute(text(f'DELETE FROM "{table}"'))
                deleted = result.rowcount
                conn.commit()
                if deleted > 0:
                    print(f"  ✅ {table}: {deleted:,} ردیف پاک شد")
                    total_deleted += deleted
            except Exception as e:
                print(f"  ⚠️ {table}: خطا - {e}")
                conn.rollback()
        
        # فعال کردن مجدد Foreign Keys
        conn.execute(text("SET session_replication_role = 'origin'"))
        conn.commit()
        
        print(f"\n✅ تمام داده‌ها پاک شدند (مجموع: {total_deleted:,} ردیف)")
    
    engine.dispose()

if __name__ == '__main__':
    print("="*60)
    print("🧹 پاک کردن همه داده‌ها از PostgreSQL")
    print("="*60)
    print("\n⚠️ هشدار: این کار همه داده‌ها را پاک می‌کند!")
    response = input("آیا مطمئن هستید؟ (yes/no): ")
    if response.lower() == 'yes':
        clear_all_data()
    else:
        print("❌ عملیات لغو شد")
