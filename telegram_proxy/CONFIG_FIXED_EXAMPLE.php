<?php
declare(strict_types=1);

/**
 * مثال فایل config.php صحیح
 *
 * ⚠️ مهم: این یک فایل نمونه است. فایل واقعی config.php را با مقادیر صحیح پر کنید.
 * هرگز توکن واقعی، کلید پروکسی، یا webhook secret را در این فایل یا گیت قرار ندهید.
 */

const TG_PROXY_CONFIG = [
	// توکن ربات تلگرام (از @BotFather) — فقط در config.php واقعی
	'telegram_bot_token' => 'REPLACE_WITH_BOT_TOKEN',

	'telegram_api_base' => 'https://api.telegram.org',

	// کلید مستقل با آنتروپی بالا (هرگز از bot token مشتق نشود)
	'proxy_api_key' => 'REPLACE_WITH_INDEPENDENT_PROXY_API_KEY',

	'proxy_base_url' => 'https://eucdn.hesabix.ir',

	// باید از telegram_webhook_secret استفاده کند، نه bot token
	'internal_webhook_url' => 'https://hsxn.hesabix.ir/api/v1/integrations/telegram/webhook/REPLACE_WITH_WEBHOOK_SECRET',

	'enable_logging' => true,
	'log_level' => 'INFO',
];

/**
 * تفاوت بین telegram_webhook_secret و telegram_bot_token:
 *
 * telegram_bot_token:
 * - توکن ربات تلگرام
 * - فرمت: {BOT_ID}:{TOKEN}
 *
 * telegram_webhook_secret:
 * - یک secret مستقل برای مسیر webhook
 * - نباید شامل کاراکترهای خاص مثل /, \, :, *, ?, ", <, >, | باشد
 * - فقط: حروف، اعداد، dash (-), underscore (_), dot (.), tilde (~)
 * - هرگز از بخشی از bot token ساخته نشود
 */
