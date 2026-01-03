#!/usr/bin/env python3
"""
اسکریپت برای به‌روزرسانی کالاهای موجود و تنظیم is_active = True برای همه
"""
import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from app.core.settings import get_settings

def update_existing_products():
    """به‌روزرسانی کالاهای موجود و تنظیم is_active = True برای همه"""
    settings = get_settings()
    engine = create_engine(settings.postgresql_dsn, echo=False)
    
    with engine.connect() as conn:
        # بررسی وضعیت فعلی
        result = conn.execute(text("""
            SELECT 
                COUNT(*) as total,
                SUM(CASE WHEN is_active = 1 OR is_active IS NULL THEN 1 ELSE 0 END) as should_be_active,
                SUM(CASE WHEN is_active = 0 THEN 1 ELSE 0 END) as inactive_count
            FROM products
        """))
        stats = result.fetchone()
        total = stats[0] if stats else 0
        should_be_active = stats[1] if stats else 0
        inactive_count = stats[2] if stats else 0
        
        print(f"📊 آمار کالاها:")
        print(f"   - کل کالاها: {total}")
        print(f"   - کالاهای فعال یا NULL: {should_be_active}")
        print(f"   - کالاهای غیرفعال: {inactive_count}")
        
        if inactive_count == 0:
            print("✅ همه کالاها از قبل فعال هستند!")
            return True
        
        # به‌روزرسانی کالاهای غیرفعال به فعال
        try:
            print(f"\n🔄 در حال به‌روزرسانی {inactive_count} کالای غیرفعال...")
            result = conn.execute(text("""
                UPDATE products 
                SET is_active = TRUE 
                WHERE is_active = FALSE OR is_active IS NULL
            """))
            conn.commit()
            updated_count = result.rowcount
            print(f"✅ {updated_count} کالا با موفقیت به‌روزرسانی شد!")
            
            # بررسی نهایی
            result = conn.execute(text("""
                SELECT 
                    COUNT(*) as total,
                    SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END) as active_count,
                    SUM(CASE WHEN is_active = 0 THEN 1 ELSE 0 END) as inactive_count
                FROM products
            """))
            final_stats = result.fetchone()
            final_total = final_stats[0] if final_stats else 0
            final_active = final_stats[1] if final_stats else 0
            final_inactive = final_stats[2] if final_stats else 0
            
            print(f"\n📊 آمار نهایی:")
            print(f"   - کل کالاها: {final_total}")
            print(f"   - کالاهای فعال: {final_active}")
            print(f"   - کالاهای غیرفعال: {final_inactive}")
            
            return True
        except Exception as e:
            print(f"❌ خطا در به‌روزرسانی: {e}")
            conn.rollback()
            return False

if __name__ == "__main__":
    success = update_existing_products()
    sys.exit(0 if success else 1)

