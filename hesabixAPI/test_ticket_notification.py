#!/usr/bin/env python3
"""
اسکریپت تست ایجاد تیکت و بررسی ارسال نوتیفیکیشن
"""
import sys
from sqlalchemy.orm import Session
from adapters.db.session import get_db
from adapters.db.models.user import User
from adapters.db.repositories.support.ticket_repository import TicketRepository
from adapters.db.repositories.support.message_repository import MessageRepository
from app.services.notification_service import NotificationService
from sqlalchemy import select

def main():
    db = next(get_db())
    
    print("=" * 80)
    print("تست ایجاد تیکت و ارسال نوتیفیکیشن")
    print("=" * 80)
    
    # پیدا کردن یک کاربر برای تست
    test_user = db.execute(
        select(User).where(User.is_active == True).limit(1)
    ).scalar_one_or_none()
    
    if not test_user:
        print("❌ کاربری برای تست یافت نشد!")
        db.close()
        return
    
    print(f"\n✅ کاربر تست: {test_user.email}")
    
    # ایجاد تیکت
    try:
        ticket_repo = TicketRepository(db)
        ticket_data = {
            "title": "تست نوتیفیکیشن تلگرام",
            "description": "این یک تیکت تست برای بررسی ارسال نوتیفیکیشن به تلگرام است.",
            "user_id": test_user.id,
            "category_id": 1,
            "priority_id": 1,
            "status_id": 1,
            "is_internal": False
        }
        
        ticket = ticket_repo.create(ticket_data)
        print(f"✅ تیکت #{ticket.id} ایجاد شد")
        
        # ایجاد پیام اولیه
        message_repo = MessageRepository(db)
        message = message_repo.create_message(
            ticket_id=ticket.id,
            sender_id=test_user.id,
            sender_type="user",
            content="این یک پیام تست برای بررسی نوتیفیکیشن است.",
            is_internal=False
        )
        print(f"✅ پیام اولیه ایجاد شد")
        
        # ارسال ناتیفیکیشن
        print("\n🔔 در حال ارسال نوتیفیکیشن به اپراتورها...")
        
        notification_service = NotificationService(db)
        user_name = f"{test_user.first_name or ''} {test_user.last_name or ''}".strip() or test_user.email or "کاربر"
        
        context = {
            "subject": f"تیکت جدید #{ticket.id}: {ticket.title}",
            "message": f"کاربر {user_name} تیکت جدیدی ایجاد کرده است:\n\n{ticket.description}",
            "ticket_id": ticket.id,
            "ticket_title": ticket.title,
            "user_name": user_name,
            "user_email": test_user.email or "",
            "category": "تست",
            "priority": "معمولی"
        }
        
        try:
            notification_service.notify_support_operators(
                event_key="support.ticket_created",
                context=context
            )
            print("✅ متد notify_support_operators فراخوانی شد")
            
            # بررسی نوتیفیکیشن‌های ارسال شده
            from adapters.db.models.notification import NotificationOutbox
            from sqlalchemy import text
            
            notifications = db.execute(
                select(NotificationOutbox).where(
                    text(f"JSON_EXTRACT(payload, '$.ticket_id') = {ticket.id}")
                ).order_by(NotificationOutbox.created_at.desc())
            ).scalars().all()
            
            print(f"\n📊 تعداد نوتیفیکیشن‌های ایجاد شده: {len(notifications)}")
            
            for notif in notifications:
                status_icon = {"sent": "✅", "failed": "❌", "pending": "⏳"}.get(notif.status, "❓")
                user = db.get(User, notif.user_id)
                user_info = f"{user.email}" if user else f"User #{notif.user_id}"
                
                print(f"\n{status_icon} کاربر: {user_info}")
                print(f"   کانال: {notif.channel}")
                print(f"   وضعیت: {notif.status}")
                print(f"   Event Key: {notif.event_key}")
                
                if notif.error_message:
                    print(f"   ❌ خطا: {notif.error_message}")
                    
                # بررسی تلاش‌های ارسال
                from adapters.db.models.notification import NotificationDeliveryAttempt
                
                attempts = db.execute(
                    select(NotificationDeliveryAttempt).where(
                        NotificationDeliveryAttempt.outbox_id == notif.id
                    )
                ).scalars().all()
                
                if attempts:
                    print(f"   تلاش‌های ارسال: {len(attempts)}")
                    for attempt in attempts:
                        attempt_status = "✅ موفق" if attempt.success else "❌ ناموفق"
                        print(f"      {attempt_status} - {attempt.created_at}")
                        if attempt.error_message:
                            print(f"         خطا: {attempt.error_message}")
            
            if notifications:
                print("\n" + "=" * 80)
                print("نتیجه:")
                success_count = sum(1 for n in notifications if n.status == "sent")
                failed_count = sum(1 for n in notifications if n.status == "failed")
                
                if success_count > 0:
                    print(f"✅ {success_count} نوتیفیکیشن با موفقیت ارسال شد!")
                    print("\n💡 اکنون باید نوتیفیکیشن را در تلگرام دریافت کرده باشید.")
                
                if failed_count > 0:
                    print(f"❌ {failed_count} نوتیفیکیشن ناموفق بود.")
                    print("\n🔍 دلایل احتمالی:")
                    print("   1. مشکل در اتصال به تلگرام یا پروکسی")
                    print("   2. توکن ربات نامعتبر است")
                    print("   3. کاربر به ربات تلگرام متصل نیست")
            else:
                print("\n❌ هیچ نوتیفیکیشنی ایجاد نشد!")
                print("\n🔍 بررسی کنید:")
                print("   1. آیا اپراتوری تعریف شده است؟")
                print("   2. آیا قالب نوتیفیکیشن برای support.ticket_created وجود دارد؟")
                
        except Exception as e:
            print(f"❌ خطا در ارسال نوتیفیکیشن: {e}")
            import traceback
            traceback.print_exc()
            
    except Exception as e:
        print(f"❌ خطا در ایجاد تیکت: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()


