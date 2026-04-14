#!/usr/bin/env python3
"""
اسکریپت بررسی مشکل نوتیفیکیشن تیکت‌های جدید
"""
import sys
from sqlalchemy import select, text
from adapters.db.session import get_db
from adapters.db.models.user import User
from adapters.db.models.notification_config import NotificationTemplate
from app.services.system_settings_service import get_effective_notifications_settings

def main():
    db = next(get_db())
    
    print("=" * 80)
    print("بررسی مشکل نوتیفیکیشن تیکت‌های جدید")
    print("=" * 80)
    
    # 1. بررسی قالب‌های نوتیفیکیشن
    print("\n1️⃣ بررسی قالب‌های نوتیفیکیشن:")
    print("-" * 80)
    
    templates = db.execute(
        select(NotificationTemplate).where(
            NotificationTemplate.event_key.like('%support%')
        ).order_by(NotificationTemplate.event_key, NotificationTemplate.channel)
    ).scalars().all()
    
    if not templates:
        print("❌ هیچ قالب نوتیفیکیشنی برای رویدادهای support یافت نشد!")
        print("\n💡 راه حل: باید قالب‌های زیر را ایجاد کنید:")
        print("   - support.ticket_created (تلگرام)")
        print("   - support.ticket_created (ایمیل)")
        print("   - support.user_reply (تلگرام)")
        print("   - support.operator_reply (تلگرام)")
    else:
        print(f"✅ تعداد {len(templates)} قالب یافت شد:")
        for tpl in templates:
            status = "✅ فعال" if tpl.is_active else "❌ غیرفعال"
            print(f"   {status} - {tpl.event_key} [{tpl.channel}] {f'({tpl.locale})' if tpl.locale else ''}")
            if tpl.event_key == 'support.ticket_created' and tpl.channel == 'telegram':
                print(f"      متن: {tpl.body[:100]}...")
    
    # 2. بررسی اپراتورهای پشتیبانی
    print("\n2️⃣ بررسی اپراتورهای پشتیبانی:")
    print("-" * 80)
    
    operators = db.execute(
        select(User).where(
            text("JSON_EXTRACT(app_permissions, '$.support_operator') = true")
        )
    ).scalars().all()
    
    if not operators:
        print("❌ هیچ اپراتور پشتیبانی یافت نشد!")
        print("\n💡 راه حل: باید حداقل یک کاربر را به عنوان اپراتور تعیین کنید:")
        print("   cd /var/www/ark/hesabixAPI")
        print("   python scripts/grant_operator_permission.py <email> grant")
    else:
        print(f"✅ تعداد {len(operators)} اپراتور یافت شد:")
        for op in operators:
            active = "✅ فعال" if op.is_active else "❌ غیرفعال"
            telegram = f"✅ {op.telegram_chat_id}" if op.telegram_chat_id else "❌ متصل نیست"
            print(f"   {active} - {op.email} ({op.first_name or ''} {op.last_name or ''})")
            print(f"      تلگرام: {telegram}")
    
    # 3. بررسی تنظیمات تلگرام
    print("\n3️⃣ بررسی تنظیمات تلگرام:")
    print("-" * 80)
    
    try:
        notify_cfg = get_effective_notifications_settings(db)
        telegram_token = notify_cfg.get("telegram_bot_token")
        telegram_proxy = notify_cfg.get("telegram_proxy")
        
        if not telegram_token:
            print("❌ توکن ربات تلگرام تنظیم نشده است!")
            print("\n💡 راه حل: در تنظیمات سیستم، توکن ربات تلگرام را وارد کنید")
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
    
    # 4. بررسی آخرین تیکت‌ها و اطلاعات نوتیفیکیشن آن‌ها
    print("\n4️⃣ بررسی آخرین تیکت‌ها:")
    print("-" * 80)
    
    try:
        from adapters.db.models.support import Ticket
        from adapters.db.models.notification import NotificationOutbox
        
        latest_tickets = db.execute(
            select(Ticket).order_by(Ticket.created_at.desc()).limit(5)
        ).scalars().all()
        
        if not latest_tickets:
            print("ℹ️ هیچ تیکتی در سیستم وجود ندارد")
        else:
            print(f"✅ {len(latest_tickets)} تیکت اخیر:")
            for ticket in latest_tickets:
                print(f"   - تیکت #{ticket.id}: {ticket.title}")
                print(f"     زمان ایجاد: {ticket.created_at}")
                
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
                        print(f"        {status_icon} [{notif.channel}] {notif.status}")
                        if notif.error_message:
                            print(f"           خطا: {notif.error_message}")
                            
    except Exception as e:
        print(f"❌ خطا در بررسی تیکت‌ها: {e}")
        import traceback
        traceback.print_exc()
    
    # خلاصه نتیجه
    print("\n" + "=" * 80)
    print("خلاصه نتایج:")
    print("=" * 80)
    
    issues = []
    if not templates:
        issues.append("❌ قالب نوتیفیکیشن برای support.ticket_created وجود ندارد")
    if not operators:
        issues.append("❌ هیچ اپراتور پشتیبانی تعریف نشده")
    else:
        operators_with_telegram = [op for op in operators if op.telegram_chat_id and op.is_active]
        if not operators_with_telegram:
            issues.append("❌ هیچ اپراتور فعالی به تلگرام متصل نیست")
    
    if not notify_cfg.get("telegram_bot_token"):
        issues.append("❌ توکن ربات تلگرام تنظیم نشده")
    
    if issues:
        print("\n🔴 مشکلات یافت شده:")
        for issue in issues:
            print(f"   {issue}")
    else:
        print("\n✅ همه چیز به نظر درست است!")
        print("\n💡 اگر همچنان نوتیفیکیشن دریافت نمی‌کنید، لطفاً:")
        print("   1. یک تیکت تست ایجاد کنید")
        print("   2. این اسکریپت را دوباره اجرا کنید تا نوتیفیکیشن‌ها را بررسی کند")
    
    db.close()

if __name__ == "__main__":
    main()


