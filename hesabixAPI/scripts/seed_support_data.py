#!/usr/bin/env python3
"""
Script برای اضافه کردن داده‌های اولیه سیستم پشتیبانی
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from adapters.db.session import get_db
from adapters.db.models.support.category import Category
from adapters.db.models.support.priority import Priority
from adapters.db.models.support.status import Status


def seed_support_data():
    """اضافه کردن داده‌های اولیه سیستم پشتیبانی"""
    db = next(get_db())
    
    try:
        # اضافه کردن دسته‌بندی‌ها
        categories = [
            Category(name="مشکل فنی", description="مشکلات فنی و باگ‌ها", is_active=True),
            Category(name="درخواست ویژگی", description="درخواست ویژگی‌های جدید", is_active=True),
            Category(name="سوال", description="سوالات عمومی", is_active=True),
            Category(name="شکایت", description="شکایات و انتقادات", is_active=True),
            Category(name="سایر", description="سایر موارد", is_active=True),
        ]
        
        for category in categories:
            existing = db.query(Category).filter(Category.name == category.name).first()
            if not existing:
                db.add(category)
        
        # اضافه کردن اولویت‌ها
        priorities = [
            Priority(name="کم", description="اولویت کم", color="#28a745", order=1),
            Priority(name="متوسط", description="اولویت متوسط", color="#ffc107", order=2),
            Priority(name="بالا", description="اولویت بالا", color="#fd7e14", order=3),
            Priority(name="فوری", description="اولویت فوری", color="#dc3545", order=4),
        ]
        
        for priority in priorities:
            existing = db.query(Priority).filter(Priority.name == priority.name).first()
            if not existing:
                db.add(priority)
        
        # اضافه کردن وضعیت‌ها
        statuses = [
            Status(name="باز", description="تیکت باز و در انتظار پاسخ", color="#007bff", is_final=False),
            Status(name="در حال پیگیری", description="تیکت در حال بررسی", color="#6f42c1", is_final=False),
            Status(name="در انتظار کاربر", description="در انتظار پاسخ کاربر", color="#17a2b8", is_final=False),
            Status(name="بسته", description="تیکت بسته شده", color="#6c757d", is_final=True),
            Status(name="حل شده", description="مشکل حل شده", color="#28a745", is_final=True),
        ]
        
        for status in statuses:
            existing = db.query(Status).filter(Status.name == status.name).first()
            if not existing:
                db.add(status)
        
        db.commit()
        print("✅ داده‌های اولیه سیستم پشتیبانی با موفقیت اضافه شدند")
        
    except Exception as e:
        db.rollback()
        print(f"❌ خطا در اضافه کردن داده‌های اولیه: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    seed_support_data()
