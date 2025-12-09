#!/usr/bin/env python3
"""
تست ارسال نوتیفیکیشن به اپراتورها
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

def main():
    from adapters.db.session import SessionLocal
    
    db = SessionLocal()
    
    try:
        print("=" * 80)
        print("تست ارسال نوتیفیکیشن به اپراتورها")
        print("=" * 80)
        
        # 1. بررسی اپراتورها
        print("\n1️⃣ بررسی اپراتورها...")
        from adapters.db.repositories.user_repo import UserRepository
        user_repo = UserRepository(db)
        operators = user_repo.get_support_operators()
        
        print(f"تعداد اپراتورها: {len(operators)}")
        for op in operators:
            print(f"  - {op.email}: telegram_chat_id={op.telegram_chat_id}, is_active={op.is_active}")
        
        if not operators:
            print("❌ هیچ اپراتوری یافت نشد!")
            return
        
        # 2. ایجاد سرویس نوتیفیکیشن
        print("\n2️⃣ ایجاد NotificationService...")
        from app.services.notification_service import NotificationService
        notification_service = NotificationService(db)
        print("✅ NotificationService ایجاد شد")
        
        # 3. ارسال نوتیفیکیشن تست
        print("\n3️⃣ ارسال نوتیفیکیشن تست...")
        
        context = {
            "subject": "تست تیکت جدید",
            "message": "این یک تیکت تست برای بررسی نوتیفیکیشن است",
            "ticket_id": 999,
            "ticket_title": "تیکت تست نوتیفیکیشن",
            "user_name": "کاربر تست",
            "user_email": "test@test.com",
            "category": "عمومی",
            "priority": "متوسط"
        }
        
        print(f"Context: {context}")
        print("\nفراخوانی notify_support_operators...")
        
        notification_service.notify_support_operators(
            event_key="support.ticket_created",
            context=context
        )
        
        print("✅ تابع notify_support_operators با موفقیت اجرا شد")
        
        # 4. بررسی نوتیفیکیشن‌های ارسال شده
        print("\n4️⃣ بررسی نوتیفیکیشن‌های ارسال شده...")
        from adapters.db.models.notification import NotificationOutbox
        from sqlalchemy import select, text
        
        notifications = db.execute(
            select(NotificationOutbox).where(
                NotificationOutbox.event_key == 'support.ticket_created'
            ).where(
                text("JSON_EXTRACT(payload, '$.ticket_id') = 999")
            ).order_by(NotificationOutbox.created_at.desc())
        ).scalars().all()
        
        print(f"تعداد نوتیفیکیشن‌های ثبت شده: {len(notifications)}")
        for notif in notifications:
            status_icon = {"sent": "✅", "failed": "❌", "pending": "⏳"}.get(notif.status, "❓")
            print(f"  {status_icon} [{notif.channel}] {notif.status} - user_id={notif.user_id}")
            if notif.error_message:
                print(f"     خطا: {notif.error_message}")
            
            # بررسی attempt ها
            from adapters.db.models.notification import NotificationDeliveryAttempt
            attempts = db.execute(
                select(NotificationDeliveryAttempt).where(
                    NotificationDeliveryAttempt.outbox_id == notif.id
                ).order_by(NotificationDeliveryAttempt.attempted_at.desc())
            ).scalars().all()
            
            if attempts:
                print(f"     تلاش‌ها: {len(attempts)}")
                for attempt in attempts:
                    success_icon = "✅" if attempt.success else "❌"
                    print(f"       {success_icon} {attempt.attempted_at}: {attempt.error_message or 'موفق'}")
        
        print("\n" + "=" * 80)
        print("تست کامل شد")
        print("=" * 80)
        
    except Exception as e:
        logger.error(f"خطا در تست: {e}", exc_info=True)
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()



