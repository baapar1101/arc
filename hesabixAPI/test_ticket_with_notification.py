#!/usr/bin/env python3
"""
ایجاد تیکت تست و بررسی ارسال نوتیفیکیشن
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def main():
    from adapters.db.session import SessionLocal
    from adapters.db.repositories.support.ticket_repository import TicketRepository
    from adapters.db.repositories.support.message_repository import MessageRepository
    from app.services.notification_service import NotificationService
    from adapters.db.models.notification import NotificationOutbox
    from adapters.db.models.user import User
    from sqlalchemy import select, text
    from datetime import datetime
    
    db = SessionLocal()
    
    try:
        print("=" * 80)
        print("ایجاد تیکت تست و بررسی نوتیفیکیشن")
        print("=" * 80)
        
        # 1. یافتن یک کاربر برای ایجاد تیکت
        print("\n1️⃣ یافتن کاربر...")
        user = db.execute(select(User).where(User.is_active == True)).scalars().first()
        if not user:
            print("❌ هیچ کاربر فعالی یافت نشد!")
            return
        
        print(f"✅ کاربر یافت شد: {user.email} (ID: {user.id})")
        
        # 2. ایجاد تیکت
        print("\n2️⃣ ایجاد تیکت...")
        ticket_repo = TicketRepository(db)
        
        ticket_data = {
            "title": f"تست نوتیفیکیشن - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            "description": "این یک تیکت تست برای بررسی عملکرد سیستم نوتیفیکیشن تلگرام به اپراتورها است.",
            "user_id": user.id,
            "category_id": 1,
            "priority_id": 1,
            "status_id": 1,
            "is_internal": False
        }
        
        ticket = ticket_repo.create(ticket_data)
        db.commit()
        print(f"✅ تیکت #{ticket.id} ایجاد شد")
        
        # 3. ایجاد پیام اولیه
        print("\n3️⃣ ایجاد پیام اولیه...")
        message_repo = MessageRepository(db)
        message = message_repo.create_message(
            ticket_id=ticket.id,
            sender_id=user.id,
            sender_type="user",
            content=ticket_data["description"],
            is_internal=False
        )
        db.commit()
        print(f"✅ پیام ایجاد شد")
        
        # 4. ارسال نوتیفیکیشن به اپراتورها
        print("\n4️⃣ ارسال نوتیفیکیشن به اپراتورها...")
        
        try:
            notification_service = NotificationService(db)
            user_name = f"{user.first_name or ''} {user.last_name or ''}".strip() or user.email or "کاربر"
            
            ticket_with_details = ticket_repo.get_ticket_with_details(ticket.id, user.id)
            
            context = {
                "subject": f"تیکت جدید #{ticket.id}: {ticket.title}",
                "message": f"کاربر {user_name} تیکت جدیدی ایجاد کرده است:\n\n{ticket_data['description']}",
                "ticket_id": ticket.id,
                "ticket_title": ticket.title,
                "user_name": user_name,
                "user_email": user.email or "",
                "category": ticket_with_details.category.name if ticket_with_details.category else "نامشخص",
                "priority": ticket_with_details.priority.name if ticket_with_details.priority else "نامشخص"
            }
            
            print(f"Context: {context}")
            print("\nفراخوانی notify_support_operators...")
            
            notification_service.notify_support_operators(
                event_key="support.ticket_created",
                context=context
            )
            
            print("✅ تابع notify_support_operators اجرا شد")
            
        except Exception as e:
            print(f"❌ خطا در ارسال نوتیفیکیشن: {e}")
            import traceback
            traceback.print_exc()
        
        # 5. بررسی نوتیفیکیشن‌های ارسال شده
        print("\n5️⃣ بررسی نوتیفیکیشن‌های ارسال شده...")
        import time
        time.sleep(1)  # کمی صبر می‌کنیم تا نوتیفیکیشن ثبت شود
        
        notifications = db.execute(
            select(NotificationOutbox).where(
                NotificationOutbox.event_key == 'support.ticket_created'
            ).where(
                text(f"JSON_EXTRACT(payload, '$.ticket_id') = {ticket.id}")
            ).order_by(NotificationOutbox.created_at.desc())
        ).scalars().all()
        
        if not notifications:
            print("❌ هیچ نوتیفیکیشنی برای این تیکت ثبت نشده!")
        else:
            print(f"✅ تعداد {len(notifications)} نوتیفیکیشن ثبت شد:")
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
                    print(f"     تلاش‌ها:")
                    for attempt in attempts:
                        success_icon = "✅" if attempt.success else "❌"
                        print(f"       {success_icon} {attempt.attempted_at}: {attempt.error_message or 'موفق'}")
        
        print("\n" + "=" * 80)
        print(f"تیکت تست #{ticket.id} با موفقیت ایجاد شد")
        print("=" * 80)
        
    except Exception as e:
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()

