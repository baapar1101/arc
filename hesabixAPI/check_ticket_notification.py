#!/usr/bin/env python3
"""
بررسی دقیق مشکل ارسال ناتیفیکیشن برای تیکت جدید
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlalchemy import select, text, and_, desc
from adapters.db.session import SessionLocal
from adapters.db.models.user import User
from adapters.db.models.notification_config import NotificationTemplate
from adapters.db.models.notification import NotificationOutbox, NotificationDeliveryAttempt
from adapters.db.models.support import Ticket
from app.services.system_settings_service import get_effective_notifications_settings

def main():
    db = SessionLocal()
    
    try:
        print("=" * 80)
        print("بررسی مشکل ارسال ناتیفیکیشن برای تیکت جدید")
        print("=" * 80)
        
        # 1. بررسی آخرین تیکت
        print("\n1️⃣ بررسی آخرین تیکت:")
        print("-" * 80)
        
        latest_ticket = db.execute(
            select(Ticket).order_by(desc(Ticket.created_at)).limit(1)
        ).scalar_one_or_none()
        
        if not latest_ticket:
            print("❌ هیچ تیکتی در سیستم وجود ندارد!")
            return
        
        print(f"✅ آخرین تیکت:")
        print(f"   ID: {latest_ticket.id}")
        print(f"   عنوان: {latest_ticket.title}")
        print(f"   زمان ایجاد: {latest_ticket.created_at}")
        print(f"   کاربر: {latest_ticket.user_id}")
        
        # 2. بررسی اپراتورها
        print("\n2️⃣ بررسی اپراتورهای پشتیبانی:")
        print("-" * 80)
        
        operators = db.execute(
            select(User).where(
                text("JSON_EXTRACT(app_permissions, '$.support_operator') = true")
            ).where(User.is_active == True)
        ).scalars().all()
        
        if not operators:
            print("❌ هیچ اپراتور پشتیبانی فعالی یافت نشد!")
            print("💡 باید حداقل یک کاربر را به عنوان اپراتور تعیین کنید")
        else:
            print(f"✅ تعداد {len(operators)} اپراتور فعال:")
            operators_with_telegram = []
            for op in operators:
                telegram_status = f"✅ chat_id={op.telegram_chat_id}" if op.telegram_chat_id else "❌ متصل نیست"
                print(f"   - {op.email} (ID: {op.id})")
                print(f"     تلگرام: {telegram_status}")
                if op.telegram_chat_id:
                    operators_with_telegram.append(op)
            
            if not operators_with_telegram:
                print("\n⚠️ هیچ اپراتوری به تلگرام متصل نیست!")
        
        # 3. بررسی نوتیفیکیشن‌های این تیکت
        print("\n3️⃣ بررسی نوتیفیکیشن‌های تیکت #{}:".format(latest_ticket.id))
        print("-" * 80)
        
        notifications = db.execute(
            select(NotificationOutbox).where(
                NotificationOutbox.event_key == 'support.ticket_created'
            ).where(
                text(f"JSON_EXTRACT(payload, '$.ticket_id') = {latest_ticket.id}")
            ).order_by(desc(NotificationOutbox.created_at))
        ).scalars().all()
        
        if not notifications:
            print("❌ هیچ نوتیفیکیشنی برای این تیکت ارسال نشده!")
            print("\n🔍 بررسی علت:")
            print("   - آیا notify_support_operators فراخوانی شده است؟")
            print("   - آیا خطایی در لاگ‌ها وجود دارد؟")
        else:
            print(f"✅ تعداد {len(notifications)} نوتیفیکیشن یافت شد:")
            for notif in notifications:
                status_icon = {"sent": "✅", "failed": "❌", "pending": "⏳"}.get(notif.status, "❓")
                print(f"\n   {status_icon} [{notif.channel}] User ID: {notif.user_id}")
                print(f"      Status: {notif.status}")
                print(f"      زمان: {notif.created_at}")
                if notif.error_message:
                    print(f"      ❌ خطا: {notif.error_message}")
                
                # بررسی تلاش‌های ارسال
                attempts = db.execute(
                    select(NotificationDeliveryAttempt).where(
                        NotificationDeliveryAttempt.outbox_id == notif.id
                    ).order_by(desc(NotificationDeliveryAttempt.created_at))
                ).scalars().all()
                
                if attempts:
                    print(f"      تلاش‌های ارسال ({len(attempts)}):")
                    for attempt in attempts:
                        attempt_icon = "✅" if attempt.success else "❌"
                        print(f"         {attempt_icon} {attempt.created_at}: {attempt.error_message or 'موفق'}")
        
        # 4. بررسی آخرین نوتیفیکیشن‌های تلگرام
        print("\n4️⃣ بررسی آخرین نوتیفیکیشن‌های تلگرام:")
        print("-" * 80)
        
        telegram_notifications = db.execute(
            select(NotificationOutbox).where(
                and_(
                    NotificationOutbox.channel == 'telegram',
                    NotificationOutbox.event_key == 'support.ticket_created'
                )
            ).order_by(desc(NotificationOutbox.created_at)).limit(5)
        ).scalars().all()
        
        if not telegram_notifications:
            print("ℹ️ هیچ نوتیفیکیشن تلگرامی برای support.ticket_created یافت نشد")
        else:
            print(f"✅ {len(telegram_notifications)} نوتیفیکیشن تلگرام اخیر:")
            for notif in telegram_notifications:
                status_icon = {"sent": "✅", "failed": "❌", "pending": "⏳"}.get(notif.status, "❓")
                ticket_id = notif.payload.get("ticket_id", "N/A") if isinstance(notif.payload, dict) else "N/A"
                print(f"   {status_icon} تیکت #{ticket_id} - User ID: {notif.user_id} - Status: {notif.status}")
                if notif.error_message:
                    print(f"      خطا: {notif.error_message}")
        
        # 5. بررسی تنظیمات
        print("\n5️⃣ بررسی تنظیمات:")
        print("-" * 80)
        
        try:
            notify_cfg = get_effective_notifications_settings(db)
            telegram_token = notify_cfg.get("telegram_bot_token")
            
            if not telegram_token:
                print("❌ توکن ربات تلگرام تنظیم نشده است!")
            else:
                token_preview = telegram_token[:10] + "..." + telegram_token[-10:] if len(telegram_token) > 20 else "***"
                print(f"✅ توکن ربات: {token_preview}")
        except Exception as e:
            print(f"❌ خطا در دریافت تنظیمات: {e}")
        
        # 6. بررسی قالب
        print("\n6️⃣ بررسی قالب تلگرام:")
        print("-" * 80)
        
        telegram_template = db.execute(
            select(NotificationTemplate).where(
                and_(
                    NotificationTemplate.event_key == 'support.ticket_created',
                    NotificationTemplate.channel == 'telegram',
                    NotificationTemplate.is_active == True
                )
            )
        ).scalar_one_or_none()
        
        if telegram_template:
            print(f"✅ قالب یافت شد (ID: {telegram_template.id})")
            print(f"   Body: {telegram_template.body[:100]}..." if len(telegram_template.body) > 100 else f"   Body: {telegram_template.body}")
        else:
            print("⚠️ قالب تلگرام یافت نشد (از context استفاده می‌شود)")
        
        # 7. خلاصه و راهنمایی
        print("\n" + "=" * 80)
        print("خلاصه:")
        print("=" * 80)
        
        if not notifications:
            print("\n🔴 مشکل: هیچ نوتیفیکیشنی ارسال نشده است!")
            print("\n💡 بررسی کنید:")
            print("   1. آیا notify_support_operators در create_ticket فراخوانی شده است؟")
            print("   2. آیا خطایی در لاگ‌های سیستم وجود دارد؟")
            print("   3. آیا exception handling در create_ticket خطا را خاموش کرده است؟")
        elif all(n.status == "failed" for n in notifications):
            print("\n🔴 مشکل: همه نوتیفیکیشن‌ها با خطا مواجه شده‌اند!")
            print("\n💡 بررسی کنید:")
            for notif in notifications:
                if notif.error_message:
                    print(f"   - {notif.error_message}")
        elif any(n.status == "sent" for n in notifications):
            print("\n✅ برخی نوتیفیکیشن‌ها با موفقیت ارسال شده‌اند")
        else:
            print("\n⚠️ نوتیفیکیشن‌ها در وضعیت pending هستند")
        
    except Exception as e:
        print(f"❌ خطا در اجرای اسکریپت: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()



