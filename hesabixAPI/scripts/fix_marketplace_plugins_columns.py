#!/usr/bin/env python3
"""اسکریپت برای اضافه کردن ستون‌های trial به جداول marketplace_plugins و business_plugins"""
import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text, inspect
from adapters.db.session import engine, SessionLocal

def main():
    """اضافه کردن ستون‌های trial"""
    db = SessionLocal()
    try:
        inspector = inspect(engine)
        
        # ========== marketplace_plugins ==========
        print("بررسی جدول marketplace_plugins...")
        marketplace_columns = [col['name'] for col in inspector.get_columns('marketplace_plugins')]
        
        # اضافه کردن trial_days در صورت عدم وجود
        if 'trial_days' not in marketplace_columns:
            print("  اضافه کردن ستون trial_days...")
            db.execute(text("ALTER TABLE marketplace_plugins ADD COLUMN trial_days INT NULL"))
            db.commit()
            print("  ✓ ستون trial_days اضافه شد")
        else:
            print("  ✓ ستون trial_days از قبل وجود دارد")
        
        # اضافه کردن trial_allowed در صورت عدم وجود
        if 'trial_allowed' not in marketplace_columns:
            print("  اضافه کردن ستون trial_allowed...")
            db.execute(text("ALTER TABLE marketplace_plugins ADD COLUMN trial_allowed BOOLEAN NOT NULL DEFAULT 0"))
            db.commit()
            print("  ✓ ستون trial_allowed اضافه شد")
        else:
            print("  ✓ ستون trial_allowed از قبل وجود دارد")
        
        # ========== business_plugins ==========
        print("\nبررسی جدول business_plugins...")
        business_columns = [col['name'] for col in inspector.get_columns('business_plugins')]
        
        # اضافه کردن is_trial در صورت عدم وجود
        if 'is_trial' not in business_columns:
            print("  اضافه کردن ستون is_trial...")
            db.execute(text("ALTER TABLE business_plugins ADD COLUMN is_trial BOOLEAN NOT NULL DEFAULT 0"))
            db.commit()
            print("  ✓ ستون is_trial اضافه شد")
        else:
            print("  ✓ ستون is_trial از قبل وجود دارد")
        
        # اضافه کردن trial_started_at در صورت عدم وجود
        if 'trial_started_at' not in business_columns:
            print("  اضافه کردن ستون trial_started_at...")
            db.execute(text("ALTER TABLE business_plugins ADD COLUMN trial_started_at DATETIME NULL"))
            db.commit()
            print("  ✓ ستون trial_started_at اضافه شد")
        else:
            print("  ✓ ستون trial_started_at از قبل وجود دارد")
        
        print("\n✓ همه ستون‌ها با موفقیت اضافه شدند")
        
    except Exception as e:
        db.rollback()
        print(f"\n✗ خطا: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        db.close()

if __name__ == "__main__":
    main()

