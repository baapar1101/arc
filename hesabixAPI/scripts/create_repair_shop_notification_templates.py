"""
اسکریپت مثال برای ایجاد قالب‌های نوتیفیکیشن تعمیرگاه

این اسکریپت نشان می‌دهد چگونه یک کسب‌وکار می‌تواند قالب‌های سفارشی ایجاد کند

استفاده:
    python scripts/create_repair_shop_notification_templates.py --business-id 1 --user-id 1
"""
import sys
import os
import argparse

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import get_db_session
from adapters.db.repositories.business_notification_repo import (
    BusinessNotificationTemplateRepository,
    NotificationModerationQueueRepository
)


def create_templates(business_id: int, user_id: int):
    """ایجاد قالب‌های نمونه برای تعمیرگاه"""
    db = next(get_db_session())
    
    try:
        template_repo = BusinessNotificationTemplateRepository(db)
        queue_repo = NotificationModerationQueueRepository(db)
        
        print("=" * 80)
        print(f"🚀 ایجاد قالب‌های نوتیفیکیشن برای کسب‌وکار {business_id}")
        print("=" * 80)
        
        templates_data = [
            {
                "code": "repair_received_sms",
                "name": "پیامک دریافت کالا - تعمیرگاه",
                "description": "ارسال پیامک به مشتری هنگام دریافت کالا",
                "event_type": "repair_shop.received",
                "channel": "sms",
                "recipient_type": "customer",
                "body": "سلام {{ customer_name }} عزیز، {{ product_name }} شما با کد {{ repair_code }} دریافت شد. تاریخ تحویل تقریبی: {{ estimated_delivery }}. {{ business_name }} - {{ business_phone }}",
                "daily_limit": 200,
                "is_automated": True
            },
            {
                "code": "repair_ready_sms",
                "name": "پیامک آماده تحویل - تعمیرگاه",
                "description": "ارسال پیامک هنگام آماده بودن کالا برای تحویل",
                "event_type": "repair_shop.ready",
                "channel": "sms",
                "recipient_type": "customer",
                "body": "سلام {{ customer_name }}، {{ product_name }} شما (کد {{ repair_code }}) آماده تحویل است. هزینه: {{ final_cost | format_currency }}. {{ business_name }} - {{ business_phone }}",
                "daily_limit": 200,
                "is_automated": True
            },
            {
                "code": "repair_ready_email",
                "name": "ایمیل آماده تحویل - تعمیرگاه",
                "description": "ارسال ایمیل هنگام آماده بودن کالا",
                "event_type": "repair_shop.ready",
                "channel": "email",
                "recipient_type": "customer",
                "subject": "کالای شما آماده تحویل است - {{ repair_code }}",
                "body": """سلام {{ customer_name }} عزیز،

کالای شما ({{ product_name }}) با کد رسید {{ repair_code }} تعمیر شده و آماده تحویل می‌باشد.

هزینه نهایی: {{ final_cost | format_currency }}

لطفاً برای دریافت کالای خود به {{ business_name }} مراجعه فرمایید.

آدرس: {{ business_address }}
تلفن: {{ business_phone }}

با تشکر،
{{ business_name }}""",
                "daily_limit": 200,
                "is_automated": True
            }
        ]
        
        created_count = 0
        
        for template_data in templates_data:
            # بررسی تکراری نبودن
            existing = template_repo.get_by_code(business_id, template_data['code'])
            if existing:
                print(f"⏭️  {template_data['code']} - قبلاً وجود دارد")
                continue
            
            # ایجاد قالب
            template_data.update({
                "business_id": business_id,
                "created_by_user_id": user_id,
                "status": "draft",
                "is_active": False,
                "approval_status": "pending"
            })
            
            template = template_repo.create(template_data)
            print(f"✅ {template.code} - ایجاد شد (ID: {template.id})")
            
            # ارسال برای تایید
            queue_data = {
                "template_id": template.id,
                "business_id": business_id,
                "status": "pending",
                "priority": 0
            }
            queue_item = queue_repo.create(queue_data)
            
            # به‌روزرسانی وضعیت
            template_repo.update(template, {"status": "pending_approval"})
            
            print(f"   📋 ارسال شد به صف بررسی (Queue ID: {queue_item.id})")
            created_count += 1
        
        db.commit()
        
        print("\n" + "=" * 80)
        print(f"✅ تمام شد! {created_count} قالب ایجاد و ارسال شد")
        print("=" * 80)
        print("\n💡 مرحله بعدی:")
        print("   1. اجرای Worker برای بررسی خودکار:")
        print("      python -m app.workers.notification_moderation_worker")
        print("\n   2. یا بررسی دستی در پنل مدیر سیستم:")
        print("      /admin/notification-moderation/queue")
        
    except Exception as e:
        db.rollback()
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='ایجاد قالب‌های نوتیفیکیشن تعمیرگاه')
    parser.add_argument('--business-id', type=int, required=True, help='شناسه کسب‌وکار')
    parser.add_argument('--user-id', type=int, required=True, help='شناسه کاربر')
    
    args = parser.parse_args()
    
    create_templates(args.business_id, args.user_id)


