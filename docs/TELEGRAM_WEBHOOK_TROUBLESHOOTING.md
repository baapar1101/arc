# راهنمای عیب‌یابی اتصال ربات تلگرام

## مشکلات رایج و راه‌حل‌ها

### 1. ربات تلگرام به پیام‌ها پاسخ نمی‌دهد

#### بررسی تنظیمات اولیه

1. **بررسی توکن ربات:**
   - از پنل ادمین به بخش "تنظیمات سیستم" > "نوتیفیکیشن‌ها" بروید
   - مطمئن شوید که "توکن ربات" تنظیم شده است
   - توکن باید از BotFather دریافت شده باشد (فرمت: `123456789:ABC...`)

2. **بررسی رمز Webhook:**
   - در همان بخش، مطمئن شوید که "رمز وب‌هوک" تنظیم شده است
   - این رمز باید یک رشته تصادفی و امن باشد

3. **بررسی نام کاربری ربات:**
   - "نام کاربری ربات" را تنظیم کنید (بدون @)
   - این برای ساخت لینک اتصال استفاده می‌شود

#### ثبت Webhook

**مهم:** بعد از تنظیم توکن و رمز webhook، باید webhook را ثبت کنید:

1. **از طریق پنل ادمین:**
   - در بخش "تنظیمات سیستم" > "نوتیفیکیشن‌ها"
   - روی دکمه "ثبت Webhook" کلیک کنید
   - پیام موفقیت یا خطا را بررسی کنید

2. **از طریق API:**
   ```bash
   POST /api/v1/admin/system-settings/notifications/telegram/webhook
   ```
   - نیاز به دسترسی `system_settings` یا `superadmin` دارد

3. **از طریق اسکریپت:**
   ```bash
   cd /var/www/ark/hesabixAPI
   python scripts/check_telegram_webhook.py
   ```

#### بررسی وضعیت Webhook

برای بررسی وضعیت webhook از Telegram API:

```bash
curl "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getWebhookInfo"
```

پاسخ باید شامل:
- `url`: آدرس webhook ثبت شده
- `pending_update_count`: تعداد پیام‌های در انتظار
- `last_error_date` و `last_error_message`: در صورت وجود خطا

### 2. مشکل در حالت Proxy

اگر از Telegram Proxy استفاده می‌کنید:

1. **بررسی تنظیمات Proxy:**
   - "فعال‌سازی Telegram Proxy" را فعال کنید
   - "آدرس پایه پروکسی" را تنظیم کنید (مثلاً: `https://proxy.example.com`)
   - "کلید دسترسی پروکسی" را تنظیم کنید

2. **بررسی فایل config.php در Proxy:**
   - فایل `telegram_proxy/config.php` را بررسی کنید
   - مطمئن شوید که `internal_webhook_url` تنظیم شده است:
     ```php
     'internal_webhook_url' => 'https://hsxn.hesabix.ir/api/v1/integrations/telegram/webhook/{WEBHOOK_SECRET}'
     ```
   - `{WEBHOOK_SECRET}` را با رمز webhook واقعی جایگزین کنید

3. **بررسی لاگ‌های Proxy:**
   - لاگ‌های proxy را بررسی کنید تا ببینید آیا درخواست‌ها به درستی forward می‌شوند

### 3. مشکل در اتصال کاربران

اگر کاربران نمی‌توانند به ربات متصل شوند:

1. **بررسی لینک اتصال:**
   - از داخل برنامه، لینک اتصال را ایجاد کنید
   - لینک باید به این صورت باشد: `https://t.me/{BOT_USERNAME}?start={TOKEN}`
   - مطمئن شوید که نام کاربری ربات درست است

2. **بررسی منقضی شدن لینک:**
   - لینک‌های اتصال 10 دقیقه اعتبار دارند
   - اگر لینک منقضی شده، لینک جدید ایجاد کنید

3. **بررسی لاگ‌های Webhook:**
   - لاگ‌های سرور را بررسی کنید تا ببینید آیا درخواست‌های `/start` دریافت می‌شوند
   - بررسی کنید که `telegram_webhook_secret` در URL درست است

### 4. بررسی لاگ‌ها

برای بررسی لاگ‌های مربوط به تلگرام:

```bash
# لاگ‌های API
tail -f /var/log/hesabix/api.log | grep -i telegram

# لاگ‌های Proxy (اگر از proxy استفاده می‌کنید)
tail -f /var/log/telegram_proxy.log
```

### 5. تست دستی Webhook

برای تست دستی webhook:

```bash
# تست با curl
curl -X POST "https://hsxn.hesabix.ir/api/v1/integrations/telegram/webhook/{WEBHOOK_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{
    "update_id": 123456789,
    "message": {
      "message_id": 1,
      "from": {"id": 123456789, "is_bot": false, "first_name": "Test"},
      "chat": {"id": 123456789, "type": "private"},
      "date": 1234567890,
      "text": "/start test_token"
    }
  }'
```

### 6. مشکلات رایج دیگر

#### خطای "Forbidden" در Webhook
- بررسی کنید که `telegram_webhook_secret` در URL با مقدار تنظیم شده در دیتابیس مطابقت دارد
- اگر `telegram_secret_header` تنظیم شده، بررسی کنید که header `X-Telegram-Bot-Api-Secret-Token` ارسال می‌شود

#### خطای "Bot token is invalid"
- توکن ربات را دوباره از BotFather دریافت کنید
- مطمئن شوید که توکن به درستی در دیتابیس ذخیره شده است

#### Webhook ثبت می‌شود اما پیام‌ها دریافت نمی‌شوند
- بررسی کنید که سرور شما از اینترنت قابل دسترسی است
- بررسی کنید که فایروال یا nginx به درستی تنظیم شده است
- بررسی کنید که SSL certificate معتبر است (Telegram فقط HTTPS را می‌پذیرد)

### 7. چک‌لیست نهایی

قبل از گزارش مشکل، این موارد را بررسی کنید:

- [ ] توکن ربات تنظیم شده است
- [ ] رمز webhook تنظیم شده است
- [ ] نام کاربری ربات تنظیم شده است
- [ ] Webhook ثبت شده است (از طریق پنل یا API)
- [ ] URL webhook صحیح است و از اینترنت قابل دسترسی است
- [ ] SSL certificate معتبر است
- [ ] اگر از proxy استفاده می‌کنید، تنظیمات proxy درست است
- [ ] لاگ‌ها را بررسی کرده‌اید

### 8. دریافت کمک

اگر مشکل حل نشد:

1. لاگ‌های کامل را جمع‌آوری کنید
2. خروجی `check_telegram_webhook.py` را ذخیره کنید
3. پاسخ `getWebhookInfo` را ذخیره کنید
4. این اطلاعات را به تیم پشتیبانی ارسال کنید

