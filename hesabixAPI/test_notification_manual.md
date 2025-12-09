# راهنمای تست نوتیفیکیشن تلگرام

## مشکل رفع شده:
query دریافت اپراتورهای پشتیبانی اصلاح شد تا به درستی اپراتورها را شناسایی کند.

## برای تست:

### روش 1: از رابط کاربری (UI)
1. وارد سیستم شوید
2. به بخش پشتیبانی بروید
3. یک تیکت جدید ایجاد کنید
4. اپراتوری که دسترسی `support_operator` دارد و به تلگرام متصل است، باید نوتیفیکیشن دریافت کند

### روش 2: بررسی با اسکریپت
پس از ایجاد تیکت تست، این دستور را اجرا کنید:

```bash
cd /var/www/ark/hesabixAPI
source venv/bin/activate
python check_notification_issue.py
```

این اسکریپت به شما نشان می‌دهد:
- ✅ قالب‌های نوتیفیکیشن
- ✅ اپراتورهای پشتیبانی و وضعیت اتصال تلگرام آن‌ها
- ✅ تنظیمات ربات تلگرام
- ✅ آخرین تیکت‌ها و نوتیفیکیشن‌های ارسال شده

### روش 3: بررسی مستقیم در دیتابیس
```sql
-- بررسی آخرین نوتیفیکیشن‌های ارسال شده
SELECT 
    id,
    user_id,
    channel,
    event_key,
    status,
    error_message,
    created_at,
    JSON_EXTRACT(payload, '$.ticket_id') as ticket_id
FROM notification_outbox
WHERE event_key = 'support.ticket_created'
ORDER BY created_at DESC
LIMIT 10;
```

## نکات مهم:

1. **اپراتور باید به ربات تلگرام متصل باشد**
   - اپراتور باید `/start` را به ربات ارسال کرده باشد
   - `telegram_chat_id` اپراتور در دیتابیس ثبت شده باشد

2. **قالب نوتیفیکیشن باید فعال باشد**
   - `event_key`: `support.ticket_created`
   - `channel`: `telegram`
   - `is_active`: `true`

3. **تنظیمات ربات تلگرام**
   - `telegram_bot_token` باید در تنظیمات سیستم وارد شده باشد
   - اگر از پروکسی استفاده می‌کنید، تنظیمات پروکسی باید صحیح باشد

## در صورت بروز مشکل:

اگر همچنان نوتیفیکیشن دریافت نمی‌شود:

1. لاگ‌های سرویس را بررسی کنید:
```bash
journalctl -u hesabix-api -f
```

2. بررسی کنید که اپراتور `support_operator` permission دارد:
```bash
cd /var/www/ark/hesabixAPI
python scripts/grant_operator_permission.py list
```

3. اگر permission ندارد، اضافه کنید:
```bash
python scripts/grant_operator_permission.py operator@example.com grant
```



