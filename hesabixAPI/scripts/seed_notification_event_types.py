"""
اسکریپت seed برای ایجاد انواع رویدادهای نوتیفیکیشن

این اسکریپت event types اولیه را در دیتابیس ایجاد می‌کند
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.repositories.business_notification_repo import NotificationEventTypeRepository
from adapters.db.seed_data.notification_event_types_seed import NOTIFICATION_EVENT_TYPES_ROWS

EVENT_TYPES = NOTIFICATION_EVENT_TYPES_ROWS


def main():
    """ایجاد event types در دیتابیس"""
    from adapters.db.session import SessionLocal
    db = SessionLocal()
    
    try:
        repo = NotificationEventTypeRepository(db)
        
        print("=" * 80)
        print("🚀 شروع seed کردن event types")
        print("=" * 80)
        
        created_count = 0
        skipped_count = 0
        
        for event_data in EVENT_TYPES:
            # بررسی اینکه قبلاً وجود نداشته باشد
            existing = repo.get_by_code(event_data['code'])
            
            if existing:
                print(f"⏭️  {event_data['code']} - قبلاً وجود دارد")
                skipped_count += 1
                continue
            
            # ایجاد
            event_type = repo.create(event_data)
            print(f"✅ {event_type.code} - ایجاد شد")
            created_count += 1
        
        db.commit()
        
        print("\n" + "=" * 80)
        print(f"✅ تمام شد!")
        print(f"   ایجاد شده: {created_count}")
        print(f"   نادیده گرفته شده: {skipped_count}")
        print(f"   کل: {len(EVENT_TYPES)}")
        print("=" * 80)
        
    except Exception as e:
        db.rollback()
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    finally:
        db.close()


if __name__ == "__main__":
    main()

