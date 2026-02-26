#!/usr/bin/env python3
"""
بررسی تعداد و لیست رکوردهای جدول صف بررسی قالب‌های نوتیفیکیشن.
اجرا: از پوشه hesabixAPI اجرا شود:
  python -m scripts.check_notification_moderation_queue
"""
import os
import sys

# اضافه کردن مسیر پروژه
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text
from adapters.db.session import SessionLocal


def main():
    db = SessionLocal()
    try:
        # تعداد کل رکوردها
        r = db.execute(text("SELECT COUNT(*) FROM notification_moderation_queue"))
        total = r.scalar()
        print(f"تعداد کل رکوردها در notification_moderation_queue: {total}")

        # لیست همه با وضعیت و template_id
        r = db.execute(text("""
            SELECT id, template_id, business_id, status, priority,
                   ai_decision, admin_decision, created_at, completed_at
            FROM notification_moderation_queue
            ORDER BY created_at DESC
        """))
        rows = r.fetchall()
        if not rows:
            print("هیچ رکوردی یافت نشد.")
            return
        print("\nلیست رکوردها:")
        print("-" * 80)
        for row in rows:
            print(f"  id={row[0]} template_id={row[1]} business_id={row[2]} "
                  f"status={row[3]} priority={row[4]} ai_decision={row[5]} "
                  f"admin_decision={row[6]} created_at={row[7]} completed_at={row[8]}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
