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

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'GET' && $_SERVER['REQUEST_URI'] === '/health') {
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

if (!$botToken) {
	http_response_code(500);
	echo json_encode(['ok' => false, 'error' => 'BOT_TOKEN_NOT_SET']);
	return;
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
	$ch = curl_init($url);
	curl_setopt($ch, CURLOPT_POST, true);
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
	curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
	curl_setopt($ch, CURLOPT_TIMEOUT, 15);
	$response = curl_exec($ch);
	$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
	if ($response === false) {
		$error = curl_error($ch);
		curl_close($ch);
		return ['ok' => false, 'error' => $error, 'status' => $httpCode ?: 500];
	}
	curl_close($ch);
	$json = json_decode($response, true);
	if (!is_array($json)) {
		return ['ok' => false, 'error' => 'INVALID_RESPONSE', 'status' => $httpCode ?: 500];
	}
	$json['status'] = $httpCode ?: 200;
	return $json;
}

function forwardWebhook(string $url, string $body, ?string $proxyKey): array {
	$ch = curl_init($url);
	curl_setopt($ch, CURLOPT_POST, true);
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	$headers = ['Content-Type: application/json', 'X-Telegram-Proxy: true'];
	if ($proxyKey) {
		$headers[] = 'X-Proxy-Key: ' . $proxyKey;
	}
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
	curl_setopt($ch, CURLOPT_TIMEOUT, 15);
	$response = curl_exec($ch);
	$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
	if ($response === false) {
		$error = curl_error($ch);
		curl_close($ch);
		return ['ok' => false, 'error' => $error, 'status' => $httpCode ?: 500];
	}
	curl_close($ch);
	return ['ok' => true, 'status' => $httpCode ?: 200];
}

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

if ($path === '/telegram/send' && $_SERVER['REQUEST_METHOD'] === 'POST') {
	if (!requireAuth($proxyKey)) {
		return;
	}
	$body = readJsonBody();
	$method = $body['method'] ?? 'sendMessage';
	$payload = $body['payload'] ?? [];
	$url = sprintf('%s/bot%s/%s', $telegramBase, $botToken, $method);
	$result = callTelegramApi($url, $payload);
	http_response_code($result['status'] ?? 200);
	echo json_encode($result);
	return;
}

if ($path === '/telegram/webhook' && $_SERVER['REQUEST_METHOD'] === 'POST') {
	if (!requireAuth($proxyKey)) {
		return;
	}
	if (!$internalWebhook) {
		http_response_code(500);
		echo json_encode(['ok' => false, 'error' => 'INTERNAL_WEBHOOK_NOT_SET']);
		return;
	}
	$rawBody = file_get_contents('php://input') ?: '';
	$result = forwardWebhook($internalWebhook, $rawBody, $proxyKey);
	http_response_code($result['status'] ?? 200);
	echo json_encode($result);
	return;
}

http_response_code(404);
echo json_encode(['ok' => false, 'error' => 'NOT_FOUND']);

