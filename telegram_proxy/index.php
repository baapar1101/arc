<?php
declare(strict_types=1);

/**
 * پروکسی سبک PHP برای عبور درخواست‌های تلگرام.
 *
 * نحوه استفاده:
 *   - فایل config.php را مطابق نمونه پر کنید.
 *   - این فایل را روی هاست PHP خود (با mod_php یا FPM) قرار دهید.
 *   - درخواست‌ها:
 *       POST /telegram/send   → بدنه JSON شامل { "method": "sendMessage", "payload": {...} }
 *       POST /telegram/webhook → همان payload دریافتی از تلگرام را ارسال کنید.
 *   - هدر X-Proxy-Key در صورت تنظیم، برای احراز استفاده می‌شود.
 */

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/logger.php';

// مقداردهی اولیه لاگر
TelegramProxyLogger::init();

header('Content-Type: application/json; charset=utf-8');

// بررسی health endpoint
$healthPath = parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH);
if ($_SERVER['REQUEST_METHOD'] === 'GET' && ($healthPath === '/health' || strpos($healthPath, '/health') !== false)) {
	echo json_encode(['ok' => true]);
	return;
}

if (!defined('TG_PROXY_CONFIG')) {
	http_response_code(500);
	echo json_encode(['ok' => false, 'error' => 'CONFIG_NOT_DEFINED']);
	return;
}

$config = TG_PROXY_CONFIG;
$botToken = $config['telegram_bot_token'] ?? null;
$telegramBase = rtrim($config['telegram_api_base'] ?? 'https://api.telegram.org', '/');
$internalWebhook = $config['internal_webhook_url'] ?? null;
$proxyKey = $config['proxy_api_key'] ?? null;

// لاگ تنظیمات (بدون نمایش کامل مقادیر حساس)
TelegramProxyLogger::info("Proxy configuration loaded", [
	'has_bot_token' => !empty($botToken),
	'bot_token_preview' => $botToken ? substr($botToken, 0, 15) . '...' : null,
	'telegram_api_base' => $telegramBase,
	'has_internal_webhook' => !empty($internalWebhook),
	'internal_webhook_url' => $internalWebhook, // نمایش کامل URL برای بررسی صحت
	'has_proxy_key' => !empty($proxyKey),
	'proxy_key_preview' => $proxyKey ? substr($proxyKey, 0, 10) . '...' : null,
]);

// بررسی تنظیمات ضروری
if (!$botToken) {
	TelegramProxyLogger::error("Bot token not configured", [
		'config_keys' => array_keys($config),
		'bot_token_exists' => isset($config['telegram_bot_token']),
	]);
	http_response_code(500);
	echo json_encode(['ok' => false, 'error' => 'BOT_TOKEN_NOT_SET']);
	return;
}

// بررسی internal_webhook_url
if (!$internalWebhook) {
	TelegramProxyLogger::warning("Internal webhook URL not configured", [
		'config_keys' => array_keys($config),
		'internal_webhook_exists' => isset($config['internal_webhook_url']),
	]);
} else {
	// بررسی فرمت internal_webhook_url
	$webhookParts = parse_url($internalWebhook);
	$webhookSecret = basename($webhookParts['path'] ?? '');
	
	TelegramProxyLogger::info("Internal webhook URL analysis", [
		'internal_webhook_url' => $internalWebhook,
		'parsed_host' => $webhookParts['host'] ?? null,
		'parsed_path' => $webhookParts['path'] ?? null,
		'extracted_secret' => $webhookSecret,
		'secret_length' => strlen($webhookSecret),
		'secret_contains_colon' => strpos($webhookSecret, ':') !== false,
		'is_valid_format' => preg_match('/^\/api\/v1\/integrations\/telegram\/webhook\/[^\/]+$/', $webhookParts['path'] ?? ''),
	]);
	
	// هشدار اگر secret شامل کاراکترهای مشکوک باشد
	if (strpos($webhookSecret, ':') !== false) {
		TelegramProxyLogger::error("⚠️ WARNING: Internal webhook URL contains colon (:) - might be using bot token instead of webhook secret!", [
			'internal_webhook_url' => $internalWebhook,
			'extracted_secret_preview' => substr($webhookSecret, 0, 20) . '...',
			'issue' => 'URL probably contains bot token instead of telegram_webhook_secret',
			'expected_format' => 'https://domain.com/api/v1/integrations/telegram/webhook/{WEBHOOK_SECRET}',
			'current_secret' => $webhookSecret,
		]);
	}
}

function requireAuth(?string $expectedKey): bool {
	if (!$expectedKey) {
		return true;
	}
	$headerKey = $_SERVER['HTTP_X_PROXY_KEY'] ?? null;
	if ($headerKey !== $expectedKey) {
		http_response_code(401);
		echo json_encode(['ok' => false, 'error' => 'INVALID_PROXY_KEY']);
		return false;
	}
	return true;
}

function readJsonBody(): array {
	$raw = file_get_contents('php://input') ?: '';
	$data = json_decode($raw, true);
	return is_array($data) ? $data : [];
}

function callTelegramApi(string $url, array $payload): array {
	$startTime = microtime(true);
	
	TelegramProxyLogger::debug("Calling Telegram API", [
		'url' => $url,
		'method' => parse_url($url, PHP_URL_PATH) ?: 'unknown',
		'payload_size' => strlen(json_encode($payload, JSON_UNESCAPED_UNICODE))
	]);
	
	$ch = curl_init($url);
	curl_setopt($ch, CURLOPT_POST, true);
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
	curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload, JSON_UNESCAPED_UNICODE));
	curl_setopt($ch, CURLOPT_TIMEOUT, 15);
	curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
	curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
	curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
	
	$response = curl_exec($ch);
	$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
	$curlError = curl_error($ch);
	$curlErrno = curl_errno($ch);
	$duration = round((microtime(true) - $startTime) * 1000, 2);
	
	if ($response === false) {
		curl_close($ch);
		
		$errorMsg = $curlError ?: 'Unknown error';
		TelegramProxyLogger::error("Failed to call Telegram API", [
			'url' => $url,
			'error' => $errorMsg,
			'curl_errno' => $curlErrno,
			'http_code' => $httpCode ?: 0,
			'duration_ms' => $duration
		]);
		
		return ['ok' => false, 'error' => $errorMsg, 'status' => $httpCode ?: 500];
	}
	
	curl_close($ch);
	
	$json = json_decode($response, true);
	if (!is_array($json)) {
		TelegramProxyLogger::error("Invalid JSON response from Telegram API", [
			'url' => $url,
			'http_code' => $httpCode,
			'response_preview' => substr($response, 0, 500),
			'response_length' => strlen($response),
			'duration_ms' => $duration
		]);
		
		return ['ok' => false, 'error' => 'INVALID_RESPONSE', 'raw_response' => substr($response, 0, 200), 'status' => $httpCode ?: 500];
	}
	
	$json['status'] = $httpCode ?: 200;
	
	// لاگ پاسخ (خصوصاً برای setWebhook)
	if (isset($json['ok'])) {
		if (!$json['ok']) {
			// استخراج اطلاعات خطا
			$errorCode = $json['error_code'] ?? null;
			$description = $json['description'] ?? null;
			$parameters = $json['parameters'] ?? null;
			
			TelegramProxyLogger::error("Telegram API returned error", [
				'url' => $url,
				'http_code' => $httpCode,
				'error_code' => $errorCode,
				'description' => $description,
				'parameters' => $parameters,
				'duration_ms' => $duration,
				'full_response' => $json
			]);
		} else {
			TelegramProxyLogger::info("Telegram API call successful", [
				'url' => $url,
				'http_code' => $httpCode,
				'description' => $json['description'] ?? null,
				'result' => $json['result'] ?? null,
				'duration_ms' => $duration
			]);
		}
	}
	
	return $json;
}

function forwardWebhook(string $url, string $body, ?string $proxyKey): array {
	$startTime = microtime(true);
	
	// تحلیل URL مقصد
	$urlParts = parse_url($url);
	$targetSecret = basename($urlParts['path'] ?? '');
	
	// تحلیل headers
	$secretTokenHeader = $_SERVER['HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN'] ?? null;
	
	TelegramProxyLogger::info("Starting webhook forward - DETAILED INFO", [
		'target_url' => $url,
		'target_host' => $urlParts['host'] ?? null,
		'target_path' => $urlParts['path'] ?? null,
		'target_secret' => $targetSecret,
		'target_secret_length' => strlen($targetSecret),
		'body_size' => strlen($body),
		'headers_to_send' => [
			'content_type' => 'application/json',
			'x_telegram_proxy' => 'true',
			'has_secret_token_header' => !empty($secretTokenHeader),
			'secret_token_header_preview' => $secretTokenHeader ? substr($secretTokenHeader, 0, 10) . '...' : null,
			'has_proxy_key' => !empty($proxyKey),
			'proxy_key_preview' => $proxyKey ? substr($proxyKey, 0, 10) . '...' : null,
		],
	]);
	
	$ch = curl_init($url);
	curl_setopt($ch, CURLOPT_POST, true);
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_TIMEOUT, 30); // افزایش timeout
	curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10); // timeout برای اتصال
	curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
	curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
	
	$headers = ['Content-Type: application/json', 'X-Telegram-Proxy: true'];
	
	// Forward header X-Telegram-Bot-Api-Secret-Token از تلگرام به سرور اصلی
	if ($secretTokenHeader) {
		$headers[] = 'X-Telegram-Bot-Api-Secret-Token: ' . $secretTokenHeader;
		TelegramProxyLogger::debug("Forwarding secret token header", [
			'has_token' => true,
			'token_preview' => substr($secretTokenHeader, 0, 10) . '...',
			'token_length' => strlen($secretTokenHeader),
		]);
	} else {
		TelegramProxyLogger::debug("No secret token header to forward", [
			'telegram_headers' => array_filter($_SERVER, function($key) {
				return strpos($key, 'HTTP_X_TELEGRAM') === 0;
			}, ARRAY_FILTER_USE_KEY),
		]);
	}
	
	if ($proxyKey) {
		$headers[] = 'X-Proxy-Key: ' . $proxyKey;
	}
	
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
	
	$response = curl_exec($ch);
	$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
	$curlError = curl_error($ch);
	$curlErrno = curl_errno($ch);
	$duration = round((microtime(true) - $startTime) * 1000, 2);
	curl_close($ch);
	
	if ($response === false) {
		// خطاهای رایج curl
		$errorMsg = $curlError ?: 'Unknown error';
		if ($curlErrno == CURLE_COULDNT_CONNECT) {
			$errorMsg = 'Could not connect to server. Check firewall and network settings.';
		} elseif ($curlErrno == CURLE_OPERATION_TIMEOUTED) {
			$errorMsg = 'Connection timeout. Server may be slow or unreachable.';
		} elseif ($curlErrno == CURLE_SSL_CONNECT_ERROR) {
			$errorMsg = 'SSL connection error. Check certificate.';
		}
		
		TelegramProxyLogger::error("❌ Failed to forward webhook - DETAILED ERROR", [
			'target_url' => $url,
			'target_host' => $urlParts['host'] ?? null,
			'target_secret' => $targetSecret,
			'error' => $errorMsg,
			'curl_errno' => $curlErrno,
			'curl_error_code' => $curlErrno,
			'body_length' => strlen($body),
			'duration_ms' => $duration,
			'headers_sent' => $headers,
			'possible_causes' => [
				'firewall_blocking' => $curlErrno == CURLE_COULDNT_CONNECT,
				'server_unreachable' => $curlErrno == CURLE_COULDNT_CONNECT,
				'timeout' => $curlErrno == CURLE_OPERATION_TIMEOUTED,
				'ssl_issue' => $curlErrno == CURLE_SSL_CONNECT_ERROR,
			],
			'solution' => $curlErrno == CURLE_COULDNT_CONNECT ? 'Whitelist proxy IP in main server firewall' : 'Check server connectivity and SSL certificate',
		]);
		
		return ['ok' => false, 'error' => $errorMsg, 'curl_errno' => $curlErrno, 'status' => 500];
	}
	
	// تحلیل پاسخ
	$responseData = json_decode($response, true);
	$isJson = json_last_error() === JSON_ERROR_NONE;
	
	TelegramProxyLogger::info("Webhook forward completed", [
		'target_url' => $url,
		'target_secret' => $targetSecret,
		'http_code' => $httpCode,
		'response_length' => strlen($response),
		'is_json' => $isJson,
		'response_preview' => substr($response, 0, 200),
		'duration_ms' => $duration,
		'status_meaning' => $httpCode == 200 ? 'Success' : ($httpCode == 403 ? 'Forbidden (check secret)' : ($httpCode == 404 ? 'Not Found' : 'Error')),
	]);
	
	// بررسی خطای 403
	if ($httpCode == 403) {
		TelegramProxyLogger::error("❌ Webhook forward returned 403 Forbidden - DETAILED ANALYSIS", [
			'target_url' => $url,
			'target_secret_used' => $targetSecret,
			'target_secret_length' => strlen($targetSecret),
			'target_secret_preview' => substr($targetSecret, 0, 30),
			'secret_token_header_sent' => !empty($secretTokenHeader),
			'secret_token_header_preview' => $secretTokenHeader ? substr($secretTokenHeader, 0, 10) . '...' : null,
			'response_body' => $response,
			'possible_causes' => [
				'wrong_webhook_secret' => 'The webhook secret in URL does not match telegram_webhook_secret in database',
				'missing_secret_header' => 'telegram_secret_header is set but header was not forwarded correctly',
				'wrong_secret_header' => 'telegram_secret_header does not match what was sent in header',
			],
			'✅ CHECK' => [
				'1' => 'Verify telegram_webhook_secret in database matches the secret in URL',
				'2' => 'Verify telegram_secret_header is set correctly (if used)',
				'3' => 'Check if secret token header is being forwarded correctly',
			],
		]);
	}
	
	// حتی اگر HTTP code خطا باشد، اگر response دریافت شده باشد، forward موفق بوده
	return ['ok' => true, 'status' => $httpCode ?: 200, 'response' => $response];
}

// دریافت مسیر درخواست - پشتیبانی از subdirectory
$requestUri = $_SERVER['REQUEST_URI'] ?? '';
$scriptName = $_SERVER['SCRIPT_NAME'] ?? '';

// اگر در subdirectory هستیم، مسیر را normalize کنیم
$path = parse_url($requestUri, PHP_URL_PATH);
// حذف subdirectory از مسیر اگر وجود دارد
if ($scriptName && strpos($scriptName, '/') !== false) {
	$scriptDir = dirname($scriptName);
	if ($scriptDir !== '.' && $scriptDir !== '/' && strpos($path, $scriptDir) === 0) {
		$path = substr($path, strlen($scriptDir));
	}
}
// اطمینان از شروع با /
if ($path === '' || $path[0] !== '/') {
	$path = '/' . $path;
}

// برای تست و دیباگ (اختیاری - می‌توانید حذف کنید)
if (isset($_GET['debug'])) {
	echo json_encode([
		'ok' => true,
		'debug' => [
			'request_uri' => $requestUri,
			'script_name' => $scriptName,
			'path' => $path,
			'method' => $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN',
		]
	]);
	return;
}

// Endpoint برای چک کردن وضعیت webhook (GET request)
if ($path === '/telegram/webhook/status' && $_SERVER['REQUEST_METHOD'] === 'GET') {
	// احراز هویت اختیاری برای این endpoint
	if ($proxyKey && !requireAuth($proxyKey)) {
		return;
	}
	
	$url = sprintf('%s/bot%s/getWebhookInfo', $telegramBase, $botToken);
	$result = callTelegramApi($url, []);
	
	http_response_code($result['status'] ?? 200);
	echo json_encode($result);
	return;
}

if ($path === '/telegram/send' && $_SERVER['REQUEST_METHOD'] === 'POST') {
	if (!requireAuth($proxyKey)) {
		return;
	}
	
	$body = readJsonBody();
	$method = $body['method'] ?? 'sendMessage';
	$payload = $body['payload'] ?? [];
	
	TelegramProxyLogger::info("Proxy request received", [
		'method' => $method,
		'payload_keys' => is_array($payload) ? array_keys($payload) : []
	]);
	
	// برای setWebhook، باید مطمئن شویم که URL صحیح است
	if ($method === 'setWebhook' && isset($payload['url'])) {
		$webhookUrl = $payload['url'];
		$secretToken = $payload['secret_token'] ?? null;
		
		// لاگ مقدار secret_token (بدون نمایش کامل برای امنیت)
		$secretTokenPreview = $secretToken ? substr($secretToken, 0, 10) . '...' : null;
		$secretTokenFull = $secretToken; // برای تحلیل
		$secretTokenChars = $secretToken ? str_split($secretToken) : [];
		$hasInvalidChars = false;
		$invalidChars = [];
		$charAnalysis = [];
		
		if ($secretToken) {
			// بررسی کاراکترهای غیرمجاز در secret_token
			// Telegram فقط کاراکترهای alphanumeric و dash, underscore, dot, tilde را می‌پذیرد
			foreach ($secretTokenChars as $index => $char) {
				$isValid = preg_match('/^[a-zA-Z0-9\-_\.~]$/', $char);
				if (!$isValid) {
					$hasInvalidChars = true;
					if (!in_array($char, $invalidChars)) {
						$invalidChars[] = $char;
					}
				}
				// آنالیز کاراکترها (فقط 10 کاراکتر اول)
				if ($index < 10) {
					$charAnalysis[] = [
						'pos' => $index,
						'char' => $char === ' ' ? '[SPACE]' : ($char === "\n" ? '[NEWLINE]' : $char),
						'is_valid' => $isValid,
						'char_code' => ord($char),
					];
				}
			}
		}
		
		// تحلیل دقیق secret_token
		$secretAnalysis = [
			'length' => strlen($secretToken ?? ''),
			'contains_colon' => strpos($secretToken ?? '', ':') !== false,
			'contains_slash' => strpos($secretToken ?? '', '/') !== false,
			'contains_space' => strpos($secretToken ?? '', ' ') !== false,
			'starts_with_bot_id' => preg_match('/^\d{10}:/', $secretToken ?? ''),
			'is_bot_token_format' => preg_match('/^\d{10}:[A-Za-z0-9_-]+$/', $secretToken ?? ''),
			'first_20_chars' => substr($secretToken ?? '', 0, 20),
		];
		
		TelegramProxyLogger::info("Processing setWebhook request - DETAILED ANALYSIS", [
			'webhook_url' => $webhookUrl,
			'drop_pending_updates' => $payload['drop_pending_updates'] ?? false,
			'has_secret_token' => isset($payload['secret_token']),
			'secret_token_info' => [
				'length' => $secretToken ? strlen($secretToken) : 0,
				'preview_first_10' => $secretTokenPreview,
				'preview_last_10' => $secretToken ? '...' . substr($secretToken, -10) : null,
				'full_preview' => $secretToken ? substr($secretToken, 0, 50) . (strlen($secretToken) > 50 ? '...' : '') : null,
			],
			'secret_token_analysis' => $secretAnalysis,
			'char_analysis_first_10' => $charAnalysis,
			'validation' => [
				'has_invalid_chars' => $hasInvalidChars,
				'invalid_chars' => $invalidChars,
				'invalid_char_count' => count($invalidChars),
			],
			'⚠️ WARNING' => $secretAnalysis['contains_colon'] ? 'Secret token contains colon (:) - might be bot token instead of webhook secret!' : null,
			'⚠️ ISSUE' => $secretAnalysis['is_bot_token_format'] ? 'Secret token looks like bot token format (BOT_ID:TOKEN) - this is WRONG!' : null,
		]);
		
		// بررسی اینکه URL با HTTPS شروع می‌شود
		if (!preg_match('/^https:\/\//i', $webhookUrl)) {
			TelegramProxyLogger::error("setWebhook URL validation failed", [
				'webhook_url' => $webhookUrl,
				'reason' => 'URL must use HTTPS'
			]);
			http_response_code(400);
			echo json_encode(['ok' => false, 'error' => 'Webhook URL must use HTTPS']);
			return;
		}
		
		// بررسی secret_token: باید فقط شامل کاراکترهای مجاز باشد
		if ($secretToken !== null && $hasInvalidChars) {
			TelegramProxyLogger::error("❌ setWebhook secret_token validation FAILED - DETAILED ERROR", [
				'secret_token_preview' => $secretTokenPreview,
				'secret_token_length' => strlen($secretToken),
				'secret_token_full_preview' => substr($secretToken, 0, 100),
				'invalid_chars' => $invalidChars,
				'invalid_char_count' => count($invalidChars),
				'char_positions' => $charAnalysis,
				'analysis' => $secretAnalysis,
				'reason' => 'Secret token contains unallowed characters. Only alphanumeric, dash (-), underscore (_), dot (.), and tilde (~) are allowed.',
				'❌ PROBLEM' => $secretAnalysis['contains_colon'] ? 'Secret token contains colon (:) - this is probably a BOT TOKEN, not a webhook secret!' : 'Secret token contains invalid characters',
				'✅ SOLUTION' => 'Go to admin panel > Notifications Settings > Set telegram_webhook_secret to a valid value (without : or other special chars)',
				'example_valid_secret' => 'my-webhook-secret-123',
			]);
			http_response_code(400);
			echo json_encode([
				'ok' => false, 
				'error' => 'Bad Request: secret token contains unallowed characters',
				'description' => 'Secret token contains unallowed characters. Only alphanumeric, dash (-), underscore (_), dot (.), and tilde (~) are allowed.',
				'invalid_chars' => array_values($invalidChars),
				'secret_token_preview' => $secretTokenPreview,
				'issue' => $secretAnalysis['contains_colon'] ? 'Secret token appears to be a bot token (contains colon). Use telegram_webhook_secret instead.' : null,
			]);
			return;
		}
		
		// بررسی طول: Telegram محدودیتی برای طول ندارد اما باید معقول باشد
		if ($secretToken && strlen($secretToken) > 256) {
			TelegramProxyLogger::error("setWebhook secret_token validation failed", [
				'secret_token_length' => strlen($secretToken),
				'reason' => 'Secret token is too long (max 256 characters)'
			]);
			http_response_code(400);
			echo json_encode(['ok' => false, 'error' => 'Secret token is too long']);
			return;
		}
	}
	
	$url = sprintf('%s/bot%s/%s', $telegramBase, $botToken, $method);
	
	TelegramProxyLogger::info("Calling Telegram API", [
		'method' => $method,
		'telegram_url' => $url,
		'payload_size' => strlen(json_encode($payload))
	]);
	
	$result = callTelegramApi($url, $payload);
	
	TelegramProxyLogger::info("Telegram API response received", [
		'method' => $method,
		'ok' => $result['ok'] ?? false,
		'status_code' => $result['status'] ?? null,
		'error' => $result['error'] ?? null,
		'description' => $result['description'] ?? null
	]);
	
	// اگر خطا داریم، اطلاعات بیشتر برگردان
	if (!$result['ok'] && isset($result['error'])) {
		$result['error_detail'] = $result['error'];
		
		TelegramProxyLogger::error("Telegram API call failed", [
			'method' => $method,
			'error' => $result['error'],
			'status_code' => $result['status'] ?? null,
			'raw_response' => isset($result['raw_response']) ? substr($result['raw_response'], 0, 500) : null
		]);
	}
	
	http_response_code($result['status'] ?? 200);
	echo json_encode($result);
	return;
}

// مسیر webhook - باید بدون نیاز به authentication کار کند (تلگرام مستقیماً به این مسیر درخواست می‌دهد)
if ($path === '/telegram/webhook' && $_SERVER['REQUEST_METHOD'] === 'POST') {
	// این endpoint توسط تلگرام برای تست webhook و ارسال پیام‌ها استفاده می‌شود
	// تلگرام secret header را خودکار ارسال می‌کند (اگر تنظیم شده باشد)
	
	// لاگ جزئیات درخواست
	$requestHeaders = [];
	foreach ($_SERVER as $key => $value) {
		if (strpos($key, 'HTTP_') === 0 || in_array($key, ['REQUEST_METHOD', 'REQUEST_URI', 'SERVER_NAME'])) {
			$requestHeaders[$key] = $value;
		}
	}
	
	TelegramProxyLogger::info("Webhook endpoint called", [
		'path' => $path,
		'method' => $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN',
		'remote_addr' => $_SERVER['REMOTE_ADDR'] ?? null,
		'has_internal_webhook' => !empty($internalWebhook),
		'internal_webhook_url' => $internalWebhook,
	]);
	
	if (!$internalWebhook) {
		TelegramProxyLogger::error("❌ Internal webhook URL not configured - DETAILED ERROR", [
			'config_loaded' => defined('TG_PROXY_CONFIG'),
			'config_keys' => defined('TG_PROXY_CONFIG') ? array_keys($config) : [],
			'internal_webhook_in_config' => isset($config['internal_webhook_url']),
			'internal_webhook_value' => $config['internal_webhook_url'] ?? null,
			'problem' => 'internal_webhook_url is not set in config.php',
			'solution' => 'Set internal_webhook_url in config.php to: https://hsxn.hesabix.ir/api/v1/integrations/telegram/webhook/{WEBHOOK_SECRET}',
		]);
		http_response_code(500);
		echo json_encode(['ok' => false, 'error' => 'INTERNAL_WEBHOOK_NOT_SET']);
		return;
	}
	
	// تحلیل internal_webhook_url
	$webhookParts = parse_url($internalWebhook);
	$webhookSecret = basename($webhookParts['path'] ?? '');
	$secretTokenHeader = $_SERVER['HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN'] ?? null;
	
	TelegramProxyLogger::info("Webhook forwarding details", [
		'internal_webhook_url' => $internalWebhook,
		'parsed_url' => [
			'scheme' => $webhookParts['scheme'] ?? null,
			'host' => $webhookParts['host'] ?? null,
			'path' => $webhookParts['path'] ?? null,
			'extracted_secret' => $webhookSecret,
			'secret_length' => strlen($webhookSecret),
		],
		'telegram_headers' => [
			'has_secret_token_header' => !empty($secretTokenHeader),
			'secret_token_header_preview' => $secretTokenHeader ? substr($secretTokenHeader, 0, 10) . '...' : null,
			'x_telegram_proxy' => isset($_SERVER['HTTP_X_TELEGRAM_PROXY']),
		],
		'proxy_config' => [
			'has_proxy_key' => !empty($proxyKey),
			'will_forward_proxy_key' => !empty($proxyKey) && isset($_SERVER['HTTP_X_TELEGRAM_PROXY']),
		],
	]);
	
	$rawBody = file_get_contents('php://input') ?: '';
	
	// اگر body خالی است (مثلاً برای تست webhook)، پاسخ موفق برگردان
	if (empty($rawBody)) {
		TelegramProxyLogger::info("Webhook test request received (empty body)", [
			'internal_webhook_url' => $internalWebhook,
			'will_forward' => false,
		]);
		http_response_code(200);
		echo json_encode(['ok' => true]);
		return;
	}
	
	// لاگ درخواست webhook
	$bodyData = json_decode($rawBody, true);
	$updateId = $bodyData['update_id'] ?? null;
	$messageText = $bodyData['message']['text'] ?? null;
	
	TelegramProxyLogger::info("Webhook request received - DETAILED", [
		'update_id' => $updateId,
		'message_text' => $messageText ? substr($messageText, 0, 50) : null,
		'body_size' => strlen($rawBody),
		'message_type' => isset($bodyData['message']) ? 'message' : (isset($bodyData['callback_query']) ? 'callback_query' : 'unknown'),
		'internal_webhook_url' => $internalWebhook,
		'extracted_webhook_secret' => $webhookSecret,
	]);
	
	// بررسی اینکه آیا این درخواست از تلگرام است یا از پروکسی داخلی
	// اگر header X-Telegram-Proxy وجود دارد، از proxyKey استفاده می‌کنیم
	$isFromProxy = isset($_SERVER['HTTP_X_TELEGRAM_PROXY']);
	$forwardKey = ($isFromProxy && $proxyKey) ? $proxyKey : null;
	
	TelegramProxyLogger::info("Forwarding webhook to internal server", [
		'target_url' => $internalWebhook,
		'target_secret' => $webhookSecret,
		'has_forward_key' => !empty($forwardKey),
		'will_forward_telegram_secret_header' => !empty($secretTokenHeader),
		'body_size' => strlen($rawBody),
	]);
	
	// Forward webhook به سرور اصلی
	$result = forwardWebhook($internalWebhook, $rawBody, $forwardKey);
	
	// برای تلگرام، همیشه باید پاسخ موفق برگردانیم (حتی اگر forward ناموفق باشد)
	// چون تلگرام اگر پاسخ ناموفق بگیرد، webhook را reject می‌کند
	http_response_code(200);
	
	if ($result['ok']) {
		// Forward موفق بود
		TelegramProxyLogger::info("Webhook forwarded successfully", [
			'update_id' => $updateId,
			'status_code' => $result['status'] ?? 200
		]);
		echo json_encode(['ok' => true]);
	} else {
		// Forward ناموفق بود، اما برای تلگرام پاسخ موفق می‌دهیم
		TelegramProxyLogger::error("Webhook forward failed", [
			'update_id' => $updateId,
			'error' => $result['error'] ?? 'Unknown error',
			'target_url' => $internalWebhook
		]);
		echo json_encode(['ok' => true]);
	}
	return;
}

http_response_code(404);
echo json_encode([
	'ok' => false,
	'error' => 'NOT_FOUND',
	'path' => $path,
	'method' => $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN',
]);

