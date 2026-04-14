<?php
declare(strict_types=1);

/**
 * فایل نمونهٔ تنظیمات پروکسی تلگرام.
 *
 * برای استفاده، این فایل را به نام config.php کپی کنید و مقادیر واقعی را جایگزین نمایید.
 */

const TG_PROXY_CONFIG = [
	'telegram_bot_token'   => '123456789:ABCDEF_your_token',
	'telegram_api_base'    => 'https://api.telegram.org',
	'proxy_api_key'        => 'change-me', // در صورت عدم نیاز، خالی بگذارید.
	'proxy_base_url'       => 'https://your-proxy-domain.com', // آدرس domain پروکسی (اختیاری - برای تست)
	'internal_webhook_url' => 'https://your-api.example.com/api/v1/integrations/telegram/webhook/YOUR_WEBHOOK_SECRET', // ⚠️ باید telegram_webhook_secret باشد (نه bot token!)

	// Logging controls (optional):
	// enable_logging: اگر false باشد، هیچ لاگی نوشته نمی‌شود
	// log_level: سطح لاگ. یکی از 'ERROR', 'WARNING', 'INFO', 'DEBUG'
	'enable_logging'      => true,
	'log_level'           => 'DEBUG',
];

/**
 * نکات مهم:
 * 
 * 1. telegram_bot_token: توکن ربات از @BotFather (فرمت: BOT_ID:TOKEN)
 * 
 * 2. proxy_api_key: یک کلید دلخواه برای امنیت پروکسی (می‌تواند هر مقداری باشد)
 * 
 * 3. internal_webhook_url: 
 *    - باید از telegram_webhook_secret استفاده کند (نه bot token!)
 *    - فرمت: https://YOUR-DOMAIN/api/v1/integrations/telegram/webhook/{WEBHOOK_SECRET}
 *    - {WEBHOOK_SECRET} باید همان مقدار telegram_webhook_secret در تنظیمات سیستم باشد
 *    - برای پیدا کردن telegram_webhook_secret، به پنل مدیریت > تنظیمات نوتیفیکیشن‌ها بروید
 * 
 * مثال:
 * اگر telegram_webhook_secret = "my-webhook-secret-123"
 * پس internal_webhook_url = "https://hsxn.hesabix.ir/api/v1/integrations/telegram/webhook/my-webhook-secret-123"
 */
