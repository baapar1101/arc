#!/usr/bin/env python3
"""
تست ساده نوتیفیکیشن - بدون import های پیچیده
"""
import sys
from sqlalchemy import select, text
from adapters.db.session import get_db
from adapters.db.models.user import User
from adapters.db.models.notification import NotificationOutbox, NotificationDeliveryAttempt

def main():
    db = next(get_db())
    
    print("=" * 80)
    print("بررسی اپراتورها و تست مستقیم نوتیفیکیشن")
    print("=" * 80)
    
    # 1. بررسی اپراتورها
    print("\n1️⃣ بررسی اپراتورهای موجود:")
    operators = db.execute(
        select(User).where(
            text("app_permissions->>'$.support_operator' = 'true'")
        ).where(User.is_active == True)
    ).scalars().all()
    
    if not operators:
        print("❌ هیچ اپراتور فعالی یافت نشد!")
        db.close()
        return
    
    print(f"✅ تعداد {len(operators)} اپراتور فعال:")
    for op in operators:
        telegram_status = f"✅ {op.telegram_chat_id}" if op.telegram_chat_id else "❌ متصل نیست"
        print(f"   - {op.email} (تلگرام: {telegram_status})")
    
    # 2. تست مستقیم ارسال نوتیفیکیشن
    print("\n2️⃣ تست ارسال نوتیفیکیشن:")
    
    # انتخاب اولین اپراتوری که تلگرام دارد
    operator_with_telegram = next((op for op in operators if op.telegram_chat_id), None)
    
    if not operator_with_telegram:
        print("❌ هیچ اپراتوری به تلگرام متصل نیست!")
        db.close()
        return
    
    print(f"✅ ارسال تست به: {operator_with_telegram.email}")
    
    try:
        from app.services.notification_service import NotificationService
        
        notification_service = NotificationService(db)
        
        # تست context
        context = {
            "subject": "تست نوتیفیکیشن تیکت",
            "message": "این یک پیام تست است",
            "ticket_id": 999,
            "ticket_title": "تیکت تست",
            "user_name": "کاربر تست",
            "user_email": "test@test.com",
            "category": "تست",
            "priority": "معمولی"
        }
        
        # ارسال مستقیم به یک اپراتور
        print(f"\n🔔 در حال ارسال به {operator_with_telegram.email}...")
        
        result = notification_service.send(
            user_id=operator_with_telegram.id,
            event_key="support.ticket_created",
            context=context,
            preferred_channels=["telegram", "email", "inapp"],
            locale="fa"
        )
        
        print(f"نتیجه ارسال: {'✅ موفق' if result else '❌ ناموفق'}")
        
        # بررسی notification outbox
        print("\n3️⃣ بررسی Notification Outbox:")
        
        recent_notifications = db.execute(
            select(NotificationOutbox).where(
                NotificationOutbox.user_id == operator_with_telegram.id
            ).order_by(NotificationOutbox.created_at.desc()).limit(5)
        ).scalars().all()
        
        if not recent_notifications:
            print("❌ هیچ نوتیفیکیشنی در outbox یافت نشد!")
        else:
            print(f"✅ {len(recent_notifications)} نوتیفیکیشن اخیر:")
            
            for notif in recent_notifications:
                status_icon = {"sent": "✅", "failed": "❌", "pending": "⏳"}.get(notif.status, "❓")
                print(f"\n   {status_icon} ID: {notif.id}")
                print(f"      کانال: {notif.channel}")
                print(f"      وضعیت: {notif.status}")
                print(f"      Event: {notif.event_key}")
                print(f"      زمان: {notif.created_at}")
                
                if notif.error_message:
                    print(f"      ❌ خطا: {notif.error_message}")
                
                # بررسی attempts
                attempts = db.execute(
                    select(NotificationDeliveryAttempt).where(
                        NotificationDeliveryAttempt.outbox_id == notif.id
                    ).order_by(NotificationDeliveryAttempt.created_at.desc())
                ).scalars().all()
                
                if attempts:
                    print(f"      تلاش‌ها: {len(attempts)}")
                    for att in attempts:
                        att_icon = "✅" if att.success else "❌"
                        print(f"         {att_icon} {att.channel} - {att.created_at}")
                        if att.error_message:
                            print(f"            خطا: {att.error_message}")
        
        print("\n" + "=" * 80)
        print("خلاصه:")
        print("=" * 80)
        
        success_notifications = [n for n in recent_notifications if n.status == "sent"]
        failed_notifications = [n for n in recent_notifications if n.status == "failed"]
        
        if success_notifications:
            print(f"✅ {len(success_notifications)} نوتیفیکیشن موفق")
            print("\n💡 اگر نوتیفیکیشن در تلگرام دریافت نکردید:")
            print("   1. اطمینان حاصل کنید که /start را در ربات زده‌اید")
            print("   2. پروکسی تلگرام را بررسی کنید")
            print("   3. توکن ربات را بررسی کنید")
        
        if failed_notifications:
            print(f"❌ {len(failed_notifications)} نوتیفیکیشن ناموفق")
            print("\n🔍 خطاهای رایج:")
            for n in failed_notifications:
                if n.error_message:
                    print(f"   - {n.error_message}")
        
    except Exception as e:
        print(f"❌ خطا در تست: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()


