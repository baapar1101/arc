<?php
declare(strict_types=1);

/**
 * فایل نمونهٔ تنظیمات پروکسی تلگرام.
 *
 * برای استفاده، این فایل را به نام config.php کپی کنید و مقادیر واقعی را جایگزین نمایید.
 * هرگز توکن/کلید واقعی را در گیت commit نکنید.
 */

const TG_PROXY_CONFIG = [
	'telegram_bot_token'   => 'REPLACE_WITH_BOT_TOKEN',
	'telegram_api_base'    => 'https://api.telegram.org',
	// الزامی: کلید مستقل با آنتروپی بالا. خالی گذاشتن = رد همه درخواست‌ها.
	'proxy_api_key'        => 'REPLACE_WITH_INDEPENDENT_PROXY_API_KEY',
	'proxy_base_url'       => 'https://eucdn.hesabix.ir',
	'internal_webhook_url' => 'https://hsxn.hesabix.ir/api/v1/integrations/telegram/webhook/REPLACE_WITH_WEBHOOK_SECRET',

	'enable_logging'      => true,
	'log_level'           => 'INFO',
];
