#!/usr/bin/env python3
"""بررسی وجود جدول quick_sales_settings در دیتابیس"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text, inspect
from app.core.settings import get_settings

def main():
    settings = get_settings()
    engine = create_engine(settings.mysql_dsn, echo=False)
    
    with engine.connect() as conn:
        inspector = inspect(engine)
        tables = inspector.get_table_names()
        
        print("=" * 60)
        print("بررسی وجود جدول quick_sales_settings")
        print("=" * 60)
        
        if 'quick_sales_settings' in tables:
            print("✅ جدول quick_sales_settings وجود دارد")
            
            # بررسی ساختار جدول
            columns = inspector.get_columns('quick_sales_settings')
            print(f"\n📋 تعداد ستون‌ها: {len(columns)}")
            print("\nستون‌های جدول:")
            for col in columns:
                print(f"  - {col['name']}: {col['type']}")
            
            # بررسی تعداد رکوردها
            result = conn.execute(text("SELECT COUNT(*) as count FROM quick_sales_settings"))
            count = result.fetchone()[0]
            print(f"\n📊 تعداد رکوردها: {count}")
            
            # بررسی indexes
            indexes = inspector.get_indexes('quick_sales_settings')
            print(f"\n🔍 تعداد ایندکس‌ها: {len(indexes)}")
            for idx in indexes:
                print(f"  - {idx['name']}: {idx['column_names']}")
                
        else:
            print("❌ جدول quick_sales_settings وجود ندارد")
            print("\nجدول‌های موجود:")
            for table in sorted(tables):
                print(f"  - {table}")

if __name__ == '__main__':
    main()

