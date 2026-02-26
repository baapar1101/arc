"""
اسکریپت seed برای ایجاد انواع رویدادهای نوتیفیکیشن

این اسکریپت event types اولیه را در دیتابیس ایجاد می‌کند
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import get_db_session
from adapters.db.repositories.business_notification_repo import NotificationEventTypeRepository


# تعریف event types اولیه
EVENT_TYPES = [
    {
        "code": "invoice.created",
        "name": "ثبت فاکتور فروش",
        "description": "هنگامی که فاکتور فروش جدیدی ثبت می‌شود",
        "category": "sales",
        "available_variables": [
            {"key": "invoice_number", "type": "string", "description": "شماره فاکتور"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "invoice_date", "type": "date", "description": "تاریخ فاکتور"},
            {"key": "amount", "type": "number", "description": "مبلغ کل فاکتور"},
            {"key": "due_date", "type": "date", "description": "تاریخ سررسید"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"}
        ],
        "default_sms_template": "سلام {{ customer_name }} عزیز، فاکتور شماره {{ invoice_number }} به مبلغ {{ amount | format_currency }} برای شما ثبت شد. با تشکر، {{ business_name }}",
        "default_email_template": """سلام {{ customer_name }} عزیز،

فاکتور شماره {{ invoice_number }} به تاریخ {{ invoice_date | format_date }} برای شما ثبت شد.

مبلغ کل: {{ amount | format_currency }}
تاریخ سررسید: {{ due_date | format_date }}

با تشکر،
{{ business_name }}
تلفن: {{ business_phone }}""",
        "default_email_subject": "فاکتور جدید - {{ invoice_number }}",
        "is_active": True,
        "requires_approval": True
    },
    {
        "code": "repair_shop.received",
        "name": "دریافت کالا در تعمیرگاه",
        "description": "هنگامی که کالای مشتری برای تعمیر دریافت می‌شود",
        "category": "repair_shop",
        "available_variables": [
            {"key": "repair_code", "type": "string", "description": "کد رسید تعمیر"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "product_name", "type": "string", "description": "نام کالا"},
            {"key": "received_date", "type": "date", "description": "تاریخ دریافت"},
            {"key": "estimated_delivery", "type": "date", "description": "تاریخ تحویل تقریبی"},
            {"key": "business_name", "type": "string", "description": "نام تعمیرگاه"},
            {"key": "business_phone", "type": "string", "description": "تلفن تعمیرگاه"}
        ],
        "default_sms_template": "سلام {{ customer_name }} عزیز، {{ product_name }} شما با کد {{ repair_code }} دریافت شد. تاریخ تحویل تقریبی: {{ estimated_delivery | format_date }}. {{ business_name }}",
        "default_email_subject": "دریافت کالا - {{ repair_code }}",
        "is_active": True,
        "requires_approval": True
    },
    {
        "code": "repair_shop.ready",
        "name": "آماده تحویل از تعمیرگاه",
        "description": "هنگامی که کالای تعمیر شده آماده تحویل است",
        "category": "repair_shop",
        "available_variables": [
            {"key": "repair_code", "type": "string", "description": "کد رسید تعمیر"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "product_name", "type": "string", "description": "نام کالا"},
            {"key": "final_cost", "type": "number", "description": "هزینه نهایی"},
            {"key": "status", "type": "string", "description": "وضعیت (تعمیر موفق/غیرقابل تعمیر)"},
            {"key": "business_name", "type": "string", "description": "نام تعمیرگاه"},
            {"key": "business_phone", "type": "string", "description": "تلفن تعمیرگاه"}
        ],
        "default_sms_template": "سلام {{ customer_name }}، {{ product_name }} شما (کد {{ repair_code }}) آماده تحویل است. هزینه: {{ final_cost | format_currency }}. {{ business_name }} - {{ business_phone }}",
        "default_email_subject": "کالای شما آماده تحویل است - {{ repair_code }}",
        "is_active": True,
        "requires_approval": True
    },
    {
        "code": "payment.received",
        "name": "دریافت پرداخت",
        "description": "هنگامی که پرداختی از مشتری دریافت می‌شود",
        "category": "financial",
        "available_variables": [
            {"key": "receipt_number", "type": "string", "description": "شماره رسید"},
            {"key": "customer_name", "type": "string", "description": "نام پرداخت‌کننده"},
            {"key": "amount", "type": "number", "description": "مبلغ دریافتی"},
            {"key": "payment_date", "type": "date", "description": "تاریخ پرداخت"},
            {"key": "payment_method", "type": "string", "description": "روش پرداخت"},
            {"key": "remaining_balance", "type": "number", "description": "مانده حساب"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"}
        ],
        "default_sms_template": "سلام {{ customer_name }}، پرداخت شما به مبلغ {{ amount | format_currency }} با موفقیت دریافت شد. رسید: {{ receipt_number }}. با تشکر، {{ business_name }}",
        "default_email_subject": "رسید پرداخت - {{ receipt_number }}",
        "is_active": True,
        "requires_approval": True
    },
    {
        "code": "payment.reminder",
        "name": "یادآوری پرداخت",
        "description": "یادآوری سررسید پرداخت به مشتری",
        "category": "financial",
        "available_variables": [
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "invoice_number", "type": "string", "description": "شماره فاکتور"},
            {"key": "amount", "type": "number", "description": "مبلغ بدهی"},
            {"key": "due_date", "type": "date", "description": "تاریخ سررسید"},
            {"key": "days_overdue", "type": "number", "description": "تعداد روز تأخیر"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"}
        ],
        "default_sms_template": "سلام {{ customer_name }}، یادآوری: فاکتور {{ invoice_number }} به مبلغ {{ amount | format_currency }} در تاریخ {{ due_date | format_date }} سررسید دارد. {{ business_name }}",
        "default_email_subject": "یادآوری سررسید پرداخت - {{ invoice_number }}",
        "is_active": True,
        "requires_approval": True
    },
    {
        "code": "order.shipped",
        "name": "ارسال سفارش",
        "description": "هنگامی که سفارش مشتری ارسال می‌شود",
        "category": "sales",
        "available_variables": [
            {"key": "order_number", "type": "string", "description": "شماره سفارش"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "tracking_code", "type": "string", "description": "کد رهگیری"},
            {"key": "courier_name", "type": "string", "description": "نام پیک/پست"},
            {"key": "estimated_delivery", "type": "date", "description": "تاریخ تحویل تقریبی"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"}
        ],
        "default_sms_template": "سلام {{ customer_name }}، سفارش شما ({{ order_number }}) ارسال شد. کد رهگیری: {{ tracking_code }}. تحویل تقریبی: {{ estimated_delivery | format_date }}. {{ business_name }}",
        "default_email_subject": "سفارش شما ارسال شد - {{ order_number }}",
        "is_active": True,
        "requires_approval": True
    },
    {
        "code": "warranty.expires_soon",
        "name": "اتمام گارانتی",
        "description": "یادآوری اتمام گارانتی محصول",
        "category": "warranty",
        "available_variables": [
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "product_name", "type": "string", "description": "نام محصول"},
            {"key": "warranty_code", "type": "string", "description": "کد گارانتی"},
            {"key": "expiry_date", "type": "date", "description": "تاریخ اتمام"},
            {"key": "days_remaining", "type": "number", "description": "روزهای باقی‌مانده"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"}
        ],
        "default_sms_template": "سلام {{ customer_name }}، گارانتی {{ product_name }} شما (کد {{ warranty_code }}) در تاریخ {{ expiry_date | format_date }} به پایان می‌رسد. {{ business_name }}",
        "default_email_subject": "یادآوری اتمام گارانتی - {{ product_name }}",
        "is_active": True,
        "requires_approval": True
    },
    {
        "code": "person_share_link.sms",
        "name": "ارسال لینک کارت حساب به مشتری",
        "description": "ارسال لینک مشاهده کارت حساب (و در صورت تنظیم، فاکتورها) به مشتری از طریق پیامک",
        "category": "people",
        "available_variables": [
            {"key": "share_link", "type": "string", "description": "لینک کوتاه کارت حساب"},
            {"key": "customer_name", "type": "string", "description": "نام مشتری"},
            {"key": "customer_mobile", "type": "string", "description": "شماره موبایل مشتری"},
            {"key": "business_name", "type": "string", "description": "نام کسب‌وکار"},
            {"key": "business_phone", "type": "string", "description": "تلفن کسب‌وکار"}
        ],
        "default_sms_template": "سلام {{ customer_name }}، لینک کارت حساب شما: {{ share_link }} — {{ business_name }}",
        "default_email_subject": "لینک کارت حساب — {{ business_name }}",
        "is_active": True,
        "requires_approval": True
    }
]


def main():
    """ایجاد event types در دیتابیس"""
    from adapters.db.session import SessionLocal
    db = SessionLocal()
    
    try:
        repo = NotificationEventTypeRepository(db)
        
        print("=" * 80)
        print("🚀 شروع seed کردن event types")
        print("=" * 80)
        
        created_count = 0
        skipped_count = 0
        
        for event_data in EVENT_TYPES:
            # بررسی اینکه قبلاً وجود نداشته باشد
            existing = repo.get_by_code(event_data['code'])
            
            if existing:
                print(f"⏭️  {event_data['code']} - قبلاً وجود دارد")
                skipped_count += 1
                continue
            
            # ایجاد
            event_type = repo.create(event_data)
            print(f"✅ {event_type.code} - ایجاد شد")
            created_count += 1
        
        db.commit()
        
        print("\n" + "=" * 80)
        print(f"✅ تمام شد!")
        print(f"   ایجاد شده: {created_count}")
        print(f"   نادیده گرفته شده: {skipped_count}")
        print(f"   کل: {len(EVENT_TYPES)}")
        print("=" * 80)
        
    except Exception as e:
        db.rollback()
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    finally:
        db.close()


if __name__ == "__main__":
    main()

