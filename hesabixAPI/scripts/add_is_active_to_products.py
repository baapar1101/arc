#!/usr/bin/env python3
"""
اسکریپت برای افزودن فیلد is_active به جدول products
"""
import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, inspect, text
from app.core.settings import get_settings

def add_is_active_column():
    """افزودن فیلد is_active به جدول products"""
    settings = get_settings()
    engine = create_engine(settings.postgresql_dsn, echo=False)
    
    with engine.connect() as conn:
        inspector = inspect(engine)
        
        # بررسی وجود جدول products
        if 'products' not in inspector.get_table_names():
            print("❌ جدول products یافت نشد!")
            return False
        
        # بررسی وجود فیلد is_active
        columns = [col['name'] for col in inspector.get_columns('products')]
        
        if 'is_active' in columns:
            print("✅ فیلد is_active از قبل وجود دارد.")
            return True
        
        # افزودن فیلد is_active
        try:
            print("🔄 در حال افزودن فیلد is_active به جدول products...")
            conn.execute(text("""
                ALTER TABLE products 
                ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE 
                COMMENT 'آیا محصول فعال است؟'
            """))
            conn.commit()
            print("✅ فیلد is_active با موفقیت اضافه شد!")
            return True
        except Exception as e:
            print(f"❌ خطا در افزودن فیلد: {e}")
            conn.rollback()
            return False

if __name__ == "__main__":
    success = add_is_active_column()
    sys.exit(0 if success else 1)

