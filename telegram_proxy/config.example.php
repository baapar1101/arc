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
	'internal_webhook_url' => 'https://your-api.example.com/api/v1/integrations/telegram/webhook/YOUR_SECRET',
];

