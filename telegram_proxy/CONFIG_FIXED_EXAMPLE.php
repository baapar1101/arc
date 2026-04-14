<?php
declare(strict_types=1);

/**
 * مثال فایل config.php صحیح
 * 
 * ⚠️ مهم: این یک فایل نمونه است. فایل واقعی config.php را با مقادیر صحیح پر کنید.
 */

const TG_PROXY_CONFIG = [
	// ✅ توکن ربات تلگرام (از @BotFather دریافت شده)
	'telegram_bot_token' => '8493247922:AAE1PF_1fc5VTCvtxVyNXxi69ULlxVahDw8',
	
	// ✅ آدرس API تلگرام (معمولاً تغییر نمی‌کند)
	'telegram_api_base' => 'https://api.telegram.org',
	
	// ✅ کلید API پروکسی (یک مقدار دلخواه برای امنیت)
	// می‌تواند هر مقدار دلخواه باشد، اما بهتر است یک مقدار امن و منحصر به فرد باشد
	'proxy_api_key' => 'my-secure-proxy-key-2024',
	
	// ✅ آدرس domain پروکسی (اختیاری - برای تست)
	'proxy_base_url' => 'https://eucdn.hesabix.ir',
	
	// ⚠️ مهم: این باید از telegram_webhook_secret استفاده کند، نه bot token!
	// برای پیدا کردن telegram_webhook_secret:
	// 1. به پنل مدیریت بروید
	// 2. به بخش تنظیمات نوتیفیکیشن‌ها بروید
	// 3. مقدار telegram_webhook_secret را پیدا کنید
	// 4. آن را در اینجا قرار دهید
	'internal_webhook_url' => 'https://hsxn.hesabix.ir/api/v1/integrations/telegram/webhook/YOUR_WEBHOOK_SECRET_HERE',

		// کنترل‌های لاگینگ (اختیاری):
		// enable_logging: اگر false باشد، هیچ لاگی نوشته نمی‌شود
		// log_level: یکی از 'ERROR'|'WARNING'|'INFO'|'DEBUG'
		'enable_logging'      => true,
		'log_level'           => 'INFO',

/**
 * تفاوت بین telegram_webhook_secret و telegram_bot_token:
 * 
 * telegram_bot_token:
 * - توکن ربات تلگرام
 * - فرمت: {BOT_ID}:{TOKEN}
 * - مثال: 849324cx7922:AAE1PF_1fc5VTCxvtxVcyNXxi69ULlxVahDw8
 * 
 * telegram_webhook_secret:
 * - یک secret برای webhook endpoint
 * - می‌تواند هر مقدار دلخواه باشد
 * - نباید شامل کاراکترهای خاص مثل /, \, :, *, ?, ", <, >, | باشد
 * - فقط باید شامل: حروف، اعداد، dash (-), underscore (_), dot (.), tilde (~)
 * - مثال: my-webhook-secret-123
 */

