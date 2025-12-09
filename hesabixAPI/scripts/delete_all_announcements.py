#!/usr/bin/env python3
"""
اسکریپت برای حذف تمام اعلان‌های موجود در دیتابیس
"""
import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import get_db_session
from adapters.db.models.announcement import Announcement, UserAnnouncement
from sqlalchemy import text


def main():
    print("=" * 80)
    print("حذف تمام اعلان‌های موجود در دیتابیس")
    print("=" * 80)
    
    with get_db_session() as db:
        try:
            # 1. بررسی تعداد اعلان‌ها
            print("\n1️⃣ بررسی تعداد اعلان‌های موجود...")
            
            # تعداد announcements
            announcements_count = db.query(Announcement).count()
            print(f"   تعداد اعلان‌ها (announcements): {announcements_count}")
            
            # تعداد user_announcements
            user_announcements_count = db.query(UserAnnouncement).count()
            print(f"   تعداد ارتباطات کاربر-اعلان (user_announcements): {user_announcements_count}")
            
            if announcements_count == 0 and user_announcements_count == 0:
                print("\n✅ هیچ اعلانی در دیتابیس وجود ندارد.")
                return
            
            # 2. نمایش جزئیات اعلان‌ها (اختیاری)
            print("\n2️⃣ جزئیات اعلان‌های موجود:")
            announcements = db.query(Announcement).all()
            for ann in announcements[:10]:  # نمایش حداکثر 10 تای اول
                print(f"   - ID: {ann.id}, Title: {ann.title[:50]}..., Level: {ann.level}, Active: {ann.is_active}")
            if len(announcements) > 10:
                print(f"   ... و {len(announcements) - 10} اعلان دیگر")
            
            # 3. تأیید حذف
            print("\n3️⃣ در حال حذف تمام اعلان‌ها...")
            
            # ابتدا user_announcements را حذف می‌کنیم (به دلیل foreign key constraint)
            deleted_user_ann = db.query(UserAnnouncement).delete()
            print(f"   ✅ {deleted_user_ann} رکورد از user_announcements حذف شد")
            
            # سپس announcements را حذف می‌کنیم
            deleted_ann = db.query(Announcement).delete()
            print(f"   ✅ {deleted_ann} رکورد از announcements حذف شد")
            
            # commit تغییرات
            db.commit()
            
            print("\n✅ تمام اعلان‌ها با موفقیت حذف شدند!")
            
            # 4. بررسی نهایی
            print("\n4️⃣ بررسی نهایی:")
            remaining_ann = db.query(Announcement).count()
            remaining_user_ann = db.query(UserAnnouncement).count()
            print(f"   تعداد باقی‌مانده announcements: {remaining_ann}")
            print(f"   تعداد باقی‌مانده user_announcements: {remaining_user_ann}")
            
            if remaining_ann == 0 and remaining_user_ann == 0:
                print("\n✅ تأیید: تمام اعلان‌ها حذف شدند.")
            else:
                print("\n⚠️  هشدار: برخی از اعلان‌ها هنوز باقی مانده‌اند!")
            
        except Exception as e:
            db.rollback()
            print(f"\n❌ خطا در حذف اعلان‌ها: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)


if __name__ == "__main__":
    main()

