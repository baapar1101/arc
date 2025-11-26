<?php
/**
 * اسکریپت تست اتصال از سرور proxy به سرور اصلی
 * این اسکریپت بررسی می‌کند که آیا سرور proxy می‌تواند به سرور اصلی متصل شود یا نه
 */

require_once __DIR__ . '/config.php';

if (!defined('TG_PROXY_CONFIG')) {
    die("❌ Config not loaded\n");
}

$config = TG_PROXY_CONFIG;
$internalWebhook = $config['internal_webhook_url'] ?? null;

if (!$internalWebhook) {
    die("❌ internal_webhook_url not configured\n");
}

echo "=" . str_repeat("=", 60) . "\n";
echo "تست اتصال از Proxy به سرور اصلی\n";
echo "=" . str_repeat("=", 60) . "\n\n";

echo "📋 تنظیمات:\n";
echo "  - Internal Webhook URL: $internalWebhook\n\n";

// تجزیه URL
$urlParts = parse_url($internalWebhook);
$host = $urlParts['host'] ?? null;
$port = $urlParts['port'] ?? 443;
$scheme = $urlParts['scheme'] ?? 'https';

echo "🔍 بررسی DNS...\n";
$ip = gethostbyname($host);
if ($ip === $host) {
    echo "  ❌ DNS resolution failed for: $host\n";
    exit(1);
}
echo "  ✓ DNS resolved: $host -> $ip\n\n";

echo "🔍 بررسی اتصال TCP...\n";
$socket = @fsockopen($host, $port, $errno, $errstr, 5);
if (!$socket) {
    echo "  ❌ Cannot connect to $host:$port\n";
    echo "     Error: $errstr ($errno)\n";
    echo "\n💡 راه‌حل‌های احتمالی:\n";
    echo "   1. بررسی فایروال سرور اصلی - IP سرور proxy را whitelist کنید\n";
    echo "   2. بررسی اینکه پورت $port باز است\n";
    echo "   3. بررسی تنظیمات nginx/apache\n";
    exit(1);
}
fclose($socket);
echo "  ✓ TCP connection successful to $host:$port\n\n";

echo "🔍 تست HTTP/HTTPS...\n";
$ch = curl_init($internalWebhook);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 5);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'X-Telegram-Proxy: true',
]);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(['test' => true]));

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlError = curl_error($ch);
$curlErrno = curl_errno($ch);
$totalTime = curl_getinfo($ch, CURLINFO_TOTAL_TIME);
curl_close($ch);

if ($response === false) {
    echo "  ❌ HTTP request failed\n";
    echo "     Error: $curlError\n";
    echo "     Error Code: $curlErrno\n";
    echo "\n💡 راه‌حل‌های احتمالی:\n";
    
    if ($curlErrno == CURLE_COULDNT_CONNECT) {
        echo "   - فایروال سرور اصلی، IP سرور proxy را block کرده است\n";
        echo "   - IP سرور proxy را در فایروال whitelist کنید\n";
        echo "   - IP سرور proxy: " . ($_SERVER['SERVER_ADDR'] ?? 'unknown') . "\n";
    } elseif ($curlErrno == CURLE_OPERATION_TIMEOUTED) {
        echo "   - Timeout - سرور پاسخ نمی‌دهد\n";
        echo "   - بررسی کنید که سرور در دسترس است\n";
    } elseif ($curlErrno == CURLE_SSL_CONNECT_ERROR) {
        echo "   - مشکل SSL/TLS\n";
        echo "   - بررسی certificate سرور اصلی\n";
    }
    exit(1);
}

echo "  ✓ HTTP request successful\n";
echo "  - HTTP Code: $httpCode\n";
echo "  - Response Time: " . round($totalTime * 1000, 2) . " ms\n";
echo "  - Response Length: " . strlen($response) . " bytes\n";

if ($httpCode == 403) {
    echo "\n⚠️  Warning: Got 403 Forbidden\n";
    echo "   این ممکن است به دلیل:\n";
    echo "   - Secret token در URL اشتباه است\n";
    echo "   - Secret header تنظیم نشده یا اشتباه است\n";
} elseif ($httpCode == 404) {
    echo "\n⚠️  Warning: Got 404 Not Found\n";
    echo "   بررسی کنید که URL webhook صحیح است\n";
} elseif ($httpCode >= 500) {
    echo "\n⚠️  Warning: Got $httpCode Server Error\n";
    echo "   بررسی لاگ‌های سرور اصلی\n";
} else {
    echo "\n✅ اتصال موفق است!\n";
}

echo "\n" . str_repeat("=", 62) . "\n";

