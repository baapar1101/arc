<?php
/**
 * اسکریپت تست برای تنظیم Webhook
 * این فایل webhook را به صورت مستقیم تنظیم می‌کند
 */

header('Content-Type: text/html; charset=utf-8');

require_once __DIR__ . '/config.php';

if (!defined('TG_PROXY_CONFIG')) {
    die('❌ فایل config.php پیدا نشد یا تنظیمات درست نیست!');
}

$config = TG_PROXY_CONFIG;
$botToken = $config['telegram_bot_token'] ?? null;
$proxyApiKey = $config['proxy_api_key'] ?? null;
$baseUrl = 'https://eucdn.hesabix.ir';
$webhookUrl = $baseUrl . '/telegram/webhook';

if (!$botToken) {
    die('❌ Bot Token تنظیم نشده است!');
}

?>
<!DOCTYPE html>
<html dir="rtl" lang="fa">
<head>
    <meta charset="UTF-8">
    <title>تنظیم Webhook تلگرام</title>
    <style>
        body { font-family: Tahoma, Arial; padding: 20px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
        .success { background: #d4edda; padding: 15px; border-radius: 4px; border-left: 4px solid #28a745; margin: 10px 0; }
        .error { background: #f8d7da; padding: 15px; border-radius: 4px; border-left: 4px solid #dc3545; margin: 10px 0; }
        .info { background: #d1ecf1; padding: 15px; border-radius: 4px; border-left: 4px solid #0c5460; margin: 10px 0; }
        pre { background: #f4f4f4; padding: 10px; border-radius: 4px; overflow-x: auto; }
        button { background: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        button:hover { background: #0056b3; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 تنظیم Webhook تلگرام</h1>
        
        <?php
        // اگر دکمه زده شده باشد
        if (isset($_POST['set_webhook'])) {
            echo '<div class="info">';
            echo '<h2>در حال تنظیم Webhook...</h2>';
            echo '<p>Webhook URL: <code>' . htmlspecialchars($webhookUrl) . '</code></p>';
            echo '</div>';
            
            // تنظیم webhook از طریق پروکسی
            $proxyUrl = $baseUrl . '/telegram/send';
            $payload = [
                'method' => 'setWebhook',
                'payload' => [
                    'url' => $webhookUrl,
                    'drop_pending_updates' => true  // پاک کردن پیام‌های قدیمی
                ]
            ];
            
            $ch = curl_init($proxyUrl);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                'Content-Type: application/json',
                'X-Proxy-Key: ' . ($proxyApiKey ?? '')
            ]);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
            curl_setopt($ch, CURLOPT_TIMEOUT, 15);
            
            $response = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $curlError = curl_error($ch);
            curl_close($ch);
            
            if ($response) {
                $result = json_decode($response, true);
                
                if ($result && isset($result['ok']) && $result['ok']) {
                    echo '<div class="success">';
                    echo '<h2>✅ Webhook با موفقیت تنظیم شد!</h2>';
                    echo '<pre>' . htmlspecialchars(json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)) . '</pre>';
                    echo '</div>';
                    
                    // چک کردن وضعیت
                    echo '<div class="info">';
                    echo '<h3>بررسی وضعیت Webhook...</h3>';
                    
                    $statusUrl = $baseUrl . '/telegram/webhook/status';
                    $statusCh = curl_init($statusUrl);
                    curl_setopt($statusCh, CURLOPT_RETURNTRANSFER, true);
                    curl_setopt($statusCh, CURLOPT_TIMEOUT, 10);
                    
                    $statusResponse = curl_exec($statusCh);
                    curl_close($statusCh);
                    
                    if ($statusResponse) {
                        $statusData = json_decode($statusResponse, true);
                        if ($statusData && isset($statusData['ok']) && $statusData['ok']) {
                            $webhookInfo = $statusData['result'] ?? [];
                            echo '<pre>' . htmlspecialchars(json_encode($webhookInfo, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)) . '</pre>';
                            
                            if (!empty($webhookInfo['url'])) {
                                echo '<p>✅ Webhook URL: <code>' . htmlspecialchars($webhookInfo['url']) . '</code></p>';
                            }
                        }
                    }
                    echo '</div>';
                } else {
                    echo '<div class="error">';
                    echo '<h2>❌ تنظیم Webhook ناموفق بود!</h2>';
                    echo '<pre>' . htmlspecialchars(json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)) . '</pre>';
                    if ($curlError) {
                        echo '<p>خطای curl: ' . htmlspecialchars($curlError) . '</p>';
                    }
                    echo '</div>';
                }
            } else {
                echo '<div class="error">';
                echo '<h2>❌ خطا در ارتباط با پروکسی!</h2>';
                if ($curlError) {
                    echo '<p>خطا: ' . htmlspecialchars($curlError) . '</p>';
                }
                echo '</div>';
            }
            
            echo '<hr>';
        }
        
        // نمایش وضعیت فعلی
        echo '<div class="info">';
        echo '<h2>وضعیت فعلی Webhook</h2>';
        
        $statusUrl = $baseUrl . '/telegram/webhook/status';
        $statusCh = curl_init($statusUrl);
        curl_setopt($statusCh, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($statusCh, CURLOPT_TIMEOUT, 10);
        
        $statusResponse = curl_exec($statusCh);
        curl_close($statusCh);
        
        if ($statusResponse) {
            $statusData = json_decode($statusResponse, true);
            if ($statusData && isset($statusData['ok']) && $statusData['ok']) {
                $webhookInfo = $statusData['result'] ?? [];
                $currentUrl = $webhookInfo['url'] ?? '';
                
                if (empty($currentUrl)) {
                    echo '<p>❌ <strong>Webhook تنظیم نشده است</strong></p>';
                } else {
                    echo '<p>✅ Webhook URL: <code>' . htmlspecialchars($currentUrl) . '</code></p>';
                    
                    if ($currentUrl !== $webhookUrl) {
                        echo '<p>⚠️ <strong>توجه:</strong> Webhook به آدرس دیگری تنظیم شده!</p>';
                        echo '<p>Expected: <code>' . htmlspecialchars($webhookUrl) . '</code></p>';
                        echo '<p>Current: <code>' . htmlspecialchars($currentUrl) . '</code></p>';
                    }
                }
                
                if (isset($webhookInfo['pending_update_count'])) {
                    echo '<p>Pending Updates: ' . htmlspecialchars($webhookInfo['pending_update_count']) . '</p>';
                }
                
                if (isset($webhookInfo['last_error_message'])) {
                    echo '<p>⚠️ Last Error: ' . htmlspecialchars($webhookInfo['last_error_message']) . '</p>';
                }
                
                echo '<pre>' . htmlspecialchars(json_encode($webhookInfo, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)) . '</pre>';
            }
        }
        echo '</div>';
        ?>
        
        <form method="POST">
            <h2>تنظیم Webhook جدید</h2>
            <p>با کلیک روی دکمه زیر، webhook تنظیم می‌شود:</p>
            <p><strong>URL:</strong> <code><?php echo htmlspecialchars($webhookUrl); ?></code></p>
            <button type="submit" name="set_webhook">تنظیم Webhook</button>
        </form>
        
        <div class="info" style="margin-top: 20px;">
            <h3>📝 نکات:</h3>
            <ul>
                <li>این صفحه webhook را مستقیماً تنظیم می‌کند</li>
                <li>پیام‌های قدیمی (pending updates) پاک می‌شوند</li>
                <li>بعد از تنظیم، می‌توانید وضعیت را بررسی کنید</li>
                <li>اگر مشکل داشتید، لاگ‌های خطا را بررسی کنید</li>
            </ul>
        </div>
    </div>
</body>
</html>

