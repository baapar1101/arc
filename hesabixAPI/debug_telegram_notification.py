#!/usr/bin/env python3
"""
اسکریپت جامع برای بررسی مشکل ارسال پیام تلگرام به اپراتورها
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlalchemy import select, text, and_
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
        print("بررسی جامع مشکل ارسال پیام تلگرام به اپراتورها")
        print("=" * 80)
        
        # 1. بررسی اپراتورها
        print("\n1️⃣ بررسی اپراتورهای پشتیبانی:")
        print("-" * 80)
        
        operators = db.execute(
            select(User).where(
                text("JSON_EXTRACT(app_permissions, '$.support_operator') = true")
            ).where(User.is_active == True)
        ).scalars().all()
        
        if not operators:
            print("❌ هیچ اپراتور پشتیبانی فعالی یافت نشد!")
            print("\n💡 راه حل: باید حداقل یک کاربر را به عنوان اپراتور تعیین کنید")
        else:
            print(f"✅ تعداد {len(operators)} اپراتور فعال یافت شد:")
            operators_with_telegram = []
            for op in operators:
                telegram_status = f"✅ chat_id={op.telegram_chat_id}" if op.telegram_chat_id else "❌ متصل نیست"
                print(f"   - {op.email} (ID: {op.id})")
                print(f"     تلگرام: {telegram_status}")
                if op.telegram_chat_id:
                    operators_with_telegram.append(op)
            
            if not operators_with_telegram:
                print("\n⚠️ هیچ اپراتوری به تلگرام متصل نیست!")
                print("💡 اپراتورها باید از طریق رابط کاربری به ربات تلگرام متصل شوند")
        
        # 2. بررسی قالب‌های نوتیفیکیشن
        print("\n2️⃣ بررسی قالب‌های نوتیفیکیشن:")
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
            print(f"✅ قالب تلگرام یافت شد:")
            print(f"   ID: {telegram_template.id}")
            print(f"   Locale: {telegram_template.locale or 'default'}")
            print(f"   Subject: {telegram_template.subject or 'N/A'}")
            print(f"   Body: {telegram_template.body[:100]}..." if len(telegram_template.body) > 100 else f"   Body: {telegram_template.body}")
        else:
            print("❌ قالب تلگرام برای support.ticket_created یافت نشد!")
            print("💡 سیستم از context.get('message') استفاده خواهد کرد")
        
        # 3. بررسی تنظیمات تلگرام
        print("\n3️⃣ بررسی تنظیمات تلگرام:")
        print("-" * 80)
        
        try:
            notify_cfg = get_effective_notifications_settings(db)
            telegram_token = notify_cfg.get("telegram_bot_token")
            telegram_proxy = notify_cfg.get("telegram_proxy")
            
            if not telegram_token:
                print("❌ توکن ربات تلگرام تنظیم نشده است!")
                print("💡 در تنظیمات سیستم، توکن ربات تلگرام را وارد کنید")
            else:
                token_preview = telegram_token[:10] + "..." + telegram_token[-10:] if len(telegram_token) > 20 else "***"
                print(f"✅ توکن ربات: {token_preview}")
                
            if telegram_proxy and telegram_proxy.get("enabled"):
                proxy_url = telegram_proxy.get("base_url", "تنظیم نشده")
                print(f"✅ پروکسی فعال: {proxy_url}")
            else:
                print("ℹ️ پروکسی تلگرام غیرفعال است (استفاده مستقیم)")
        except Exception as e:
            print(f"❌ خطا در دریافت تنظیمات: {e}")
            import traceback
            traceback.print_exc()
        
        # 4. بررسی آخرین تیکت‌ها و نوتیفیکیشن‌ها
        print("\n4️⃣ بررسی آخرین تیکت‌ها و نوتیفیکیشن‌ها:")
        print("-" * 80)
        
        latest_tickets = db.execute(
            select(Ticket).order_by(Ticket.created_at.desc()).limit(5)
        ).scalars().all()
        
        if not latest_tickets:
            print("ℹ️ هیچ تیکتی در سیستم وجود ندارد")
        else:
            print(f"✅ {len(latest_tickets)} تیکت اخیر:")
            for ticket in latest_tickets:
                print(f"\n   تیکت #{ticket.id}: {ticket.title}")
                print(f"   زمان ایجاد: {ticket.created_at}")
                
                # بررسی نوتیفیکیشن‌های مرتبط
                notifications = db.execute(
                    select(NotificationOutbox).where(
                        NotificationOutbox.event_key == 'support.ticket_created'
                    ).where(
                        text(f"JSON_EXTRACT(payload, '$.ticket_id') = {ticket.id}")
                    ).order_by(NotificationOutbox.created_at.desc())
                ).scalars().all()
                
                if not notifications:
                    print("     ❌ هیچ نوتیفیکیشنی برای این تیکت ارسال نشده!")
                else:
                    print(f"     ✅ تعداد {len(notifications)} نوتیفیکیشن:")
                    for notif in notifications:
                        status_icon = {"sent": "✅", "failed": "❌", "pending": "⏳"}.get(notif.status, "❓")
                        print(f"        {status_icon} [{notif.channel}] {notif.status} - User ID: {notif.user_id}")
                        if notif.error_message:
                            print(f"           خطا: {notif.error_message}")
                        
                        # بررسی تلاش‌های ارسال
                        attempts = db.execute(
                            select(NotificationDeliveryAttempt).where(
                                NotificationDeliveryAttempt.outbox_id == notif.id
                            ).order_by(NotificationDeliveryAttempt.created_at.desc())
                        ).scalars().all()
                        
                        if attempts:
                            print(f"           تلاش‌های ارسال:")
                            for attempt in attempts:
                                attempt_icon = "✅" if attempt.success else "❌"
                                print(f"              {attempt_icon} {attempt.created_at}: {attempt.error_message or 'موفق'}")
        
        # 5. بررسی آخرین نوتیفیکیشن‌های تلگرام
        print("\n5️⃣ بررسی آخرین نوتیفیکیشن‌های تلگرام:")
        print("-" * 80)
        
        telegram_notifications = db.execute(
            select(NotificationOutbox).where(
                NotificationOutbox.channel == 'telegram'
            ).where(
                NotificationOutbox.event_key == 'support.ticket_created'
            ).order_by(NotificationOutbox.created_at.desc()).limit(10)
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
        
        # 6. خلاصه مشکلات
        print("\n" + "=" * 80)
        print("خلاصه مشکلات:")
        print("=" * 80)
        
        issues = []
        if not operators:
            issues.append("❌ هیچ اپراتور پشتیبانی تعریف نشده")
        elif not operators_with_telegram:
            issues.append("❌ هیچ اپراتور فعالی به تلگرام متصل نیست")
        
        if not notify_cfg.get("telegram_bot_token"):
            issues.append("❌ توکن ربات تلگرام تنظیم نشده")
        
        if not telegram_template:
            issues.append("⚠️ قالب تلگرام برای support.ticket_created وجود ندارد (اما از context استفاده می‌شود)")
        
        if issues:
            print("\n🔴 مشکلات یافت شده:")
            for issue in issues:
                print(f"   {issue}")
        else:
            print("\n✅ همه چیز به نظر درست است!")
            print("\n💡 اگر همچنان نوتیفیکیشن دریافت نمی‌کنید:")
            print("   1. بررسی کنید که اپراتورها telegram_chat_id دارند")
            print("   2. بررسی کنید که قالب تلگرام درست است")
            print("   3. لاگ‌های سیستم را بررسی کنید")
            print("   4. یک تیکت تست جدید ایجاد کنید و دوباره بررسی کنید")
        
    except Exception as e:
        print(f"❌ خطا در اجرای اسکریپت: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()



