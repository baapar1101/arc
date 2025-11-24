<?php
/**
 * اسکریپت تست برای بررسی مشکل Webhook
 * این فایل را در root domain قرار دهید و با مرورگر باز کنید
 */

header('Content-Type: text/html; charset=utf-8');

$baseUrl = 'https://eucdn.hesabix.ir';
$webhookUrl = $baseUrl . '/telegram/webhook';

?>
<!DOCTYPE html>
<html dir="rtl" lang="fa">
<head>
    <meta charset="UTF-8">
    <title>تست Webhook تلگرام</title>
    <style>
        body { font-family: Tahoma, Arial; padding: 20px; background: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
        .test { margin: 20px 0; padding: 15px; border-left: 4px solid #007bff; background: #f8f9fa; }
        .success { border-color: #28a745; background: #d4edda; }
        .error { border-color: #dc3545; background: #f8d7da; }
        .warning { border-color: #ffc107; background: #fff3cd; }
        h1 { color: #333; }
        h2 { color: #666; font-size: 18px; margin-top: 0; }
        pre { background: #f4f4f4; padding: 10px; border-radius: 4px; overflow-x: auto; font-size: 12px; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
        .ip-info { background: #e7f3ff; padding: 10px; border-radius: 4px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧪 تست Webhook تلگرام</h1>
        <p>این صفحه مشکلات احتمالی را بررسی می‌کند.</p>

        <?php
        // اطلاعات سرور و IP
        $serverIP = $_SERVER['SERVER_ADDR'] ?? 'نامشخص';
        $serverName = $_SERVER['SERVER_NAME'] ?? 'نامشخص';
        $remoteIP = $_SERVER['REMOTE_ADDR'] ?? 'نامشخص';
        
        // تست 0: اطلاعات سرور و IP
        echo '<div class="test">';
        echo '<h2>0. اطلاعات سرور و IP</h2>';
        echo '<div class="ip-info">';
        echo '<pre>';
        echo 'Server Name: ' . htmlspecialchars($serverName) . "\n";
        echo 'Server IP (Internal): ' . htmlspecialchars($serverIP) . "\n";
        echo 'Remote IP (Your IP): ' . htmlspecialchars($remoteIP) . "\n";
        
        // دریافت IP عمومی سرور
        $publicIP = null;
        $services = [
            'https://api.ipify.org',
            'https://ifconfig.me/ip',
            'https://icanhazip.com'
        ];
        
        foreach ($services as $service) {
            $ch = curl_init($service);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 3);
            curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 3);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            $ip = trim(curl_exec($ch));
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            
            if ($ip && $httpCode == 200 && filter_var($ip, FILTER_VALIDATE_IP)) {
                $publicIP = $ip;
                break;
            }
        }
        
        if ($publicIP) {
            echo 'Public IP (Proxy Server): ' . htmlspecialchars($publicIP) . "\n";
        } else {
            echo 'Public IP: ❌ نمی‌تواند دریافت شود' . "\n";
        }
        echo '</pre>';
        echo '</div>';
        echo '<p><strong>نکته:</strong> این IP باید در firewall سرور اصلی whitelist شود.</p>';
        echo '</div>';
        
        // تست 1: بررسی وجود config.php
        $internalHost = null;
        $internalIP = null;
        
        echo '<div class="test">';
        echo '<h2>1. بررسی فایل config.php</h2>';
        $configPath = __DIR__ . '/config.php';
        if (file_exists($configPath)) {
            echo '<p class="success">✅ فایل config.php پیدا شد</p>';
            require_once $configPath;
            if (defined('TG_PROXY_CONFIG')) {
                $config = TG_PROXY_CONFIG;
                echo '<p class="success">✅ تنظیمات خوانده شد</p>';
                
                // استخراج IP سرور اصلی از internal_webhook_url
                $internalWebhookUrl = $config['internal_webhook_url'] ?? '';
                $internalHost = parse_url($internalWebhookUrl, PHP_URL_HOST);
                
                if ($internalHost) {
                    // دریافت IP سرور اصلی با DNS lookup
                    $dnsLookup = @gethostbyname($internalHost);
                    if ($dnsLookup && $dnsLookup != $internalHost && filter_var($dnsLookup, FILTER_VALIDATE_IP)) {
                        $internalIP = $dnsLookup;
                    }
                    
                    // همچنین سعی می‌کنیم IP‌های متعدد را دریافت کنیم
                    $allIPs = @gethostbynamel($internalHost);
                    if ($allIPs && is_array($allIPs)) {
                        $internalIP = $allIPs[0];
                    }
                }
                
                echo '<pre>';
                echo 'Bot Token: ' . (isset($config['telegram_bot_token']) && $config['telegram_bot_token'] ? '✅ تنظیم شده' : '❌ تنظیم نشده') . "\n";
                echo 'Internal Webhook URL: ' . (isset($config['internal_webhook_url']) && $config['internal_webhook_url'] ? htmlspecialchars($config['internal_webhook_url']) : '❌ تنظیم نشده') . "\n";
                if ($internalHost) {
                    echo 'Internal Host: ' . htmlspecialchars($internalHost) . "\n";
                    if ($internalIP) {
                        echo 'Internal Host IP: ' . htmlspecialchars($internalIP) . " ✅\n";
                    } else {
                        echo 'Internal Host IP: ❌ نمی‌تواند resolve شود' . "\n";
                    }
                }
                echo 'Proxy API Key: ' . (isset($config['proxy_api_key']) && $config['proxy_api_key'] ? '✅ تنظیم شده' : '⚠️ تنظیم نشده (اختیاری)') . "\n";
                echo '</pre>';
            } else {
                echo '<p class="error">❌ TG_PROXY_CONFIG تعریف نشده</p>';
            }
        } else {
            echo '<p class="error">❌ فایل config.php پیدا نشد!</p>';
            echo '<p>لطفاً از config.example.php یک کپی بسازید و تنظیمات را وارد کنید.</p>';
        }
        echo '</div>';
        
        // تست پینگ به سرور اصلی (اگر config موجود باشد)
        if ($internalHost) {
            echo '<div class="test">';
            echo '<h2>1.5. تست پینگ و اتصال به سرور اصلی</h2>';
            echo '<p><strong>Host:</strong> ' . htmlspecialchars($internalHost) . '</p>';
            if ($internalIP) {
                echo '<p><strong>IP:</strong> ' . htmlspecialchars($internalIP) . '</p>';
            }
            
            $pingSuccess = false;
            $pingTime = null;
            $pingOutputStr = '';
            
            // تست 1: پینگ با exec (اگر مجاز باشد)
            if (function_exists('exec') && !in_array('exec', explode(',', ini_get('disable_functions')))) {
                $pingCommand = 'ping -c 3 -W 2 ' . escapeshellarg($internalHost) . ' 2>&1';
                @exec($pingCommand, $pingOutput, $pingReturn);
                
                if ($pingOutput) {
                    $pingOutputStr = implode("\n", $pingOutput);
                    
                    // استخراج زمان پینگ از خروجی
                    if (preg_match('/time=([0-9.]+)\s*ms/i', $pingOutputStr, $matches)) {
                        $pingTime = $matches[1];
                    }
                    
                    // بررسی نتیجه
                    if ($pingReturn == 0 || strpos($pingOutputStr, '0% packet loss') !== false || strpos($pingOutputStr, 'time=') !== false) {
                        $pingSuccess = true;
                    }
                }
            }
            
            if ($pingSuccess) {
                echo '<p class="success">✅ پینگ موفق</p>';
                if ($pingTime) {
                    echo '<p>زمان پاسخ متوسط: <strong>' . htmlspecialchars($pingTime) . ' ms</strong></p>';
                }
                if ($pingOutputStr) {
                    echo '<pre>' . htmlspecialchars($pingOutputStr) . '</pre>';
                }
            } else {
                echo '<p class="warning">⚠️ پینگ با exec انجام نشد یا ناموفق بود</p>';
                if ($pingOutputStr) {
                    echo '<pre>' . htmlspecialchars($pingOutputStr) . '</pre>';
                }
                
                // تست جایگزین: اتصال TCP به پورت 443
                echo '<p><strong>تست جایگزین: اتصال TCP به پورت 443</strong></p>';
                $startTime = microtime(true);
                $fp = @fsockopen($internalHost, 443, $errno, $errstr, 5);
                $endTime = microtime(true);
                $connectionTime = round(($endTime - $startTime) * 1000, 2);
                
                if ($fp) {
                    echo '<p class="success">✅ اتصال TCP به پورت 443 موفق</p>';
                    echo '<p>زمان اتصال: <strong>' . htmlspecialchars($connectionTime) . ' ms</strong></p>';
                    fclose($fp);
                } else {
                    echo '<p class="error">❌ نمی‌تواند به پورت 443 متصل شود</p>';
                    echo '<p>خطا: ' . htmlspecialchars($errstr) . ' (' . htmlspecialchars($errno) . ')</p>';
                    echo '<p class="error"><strong>⚠️ این مشکل اصلی است! پروکسی نمی‌تواند به سرور اصلی متصل شود.</strong></p>';
                }
            }
            echo '</div>';
        }
        
        // تست 2: بررسی endpoint webhook
        echo '<div class="test">';
        echo '<h2>2. تست دسترسی به Webhook Endpoint</h2>';
        $ch = curl_init($webhookUrl);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(['test' => true]));
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        
        $startTime = microtime(true);
        $response = curl_exec($ch);
        $endTime = microtime(true);
        $responseTime = round(($endTime - $startTime) * 1000, 2);
        
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        $curlErrno = curl_errno($ch);
        curl_close($ch);
        
        echo '<p>زمان پاسخ: <strong>' . htmlspecialchars($responseTime) . ' ms</strong></p>';
        
        if ($httpCode == 200 || $httpCode == 500 || $httpCode == 401 || $httpCode == 403) {
            echo '<p class="success">✅ Endpoint در دسترس است (HTTP ' . $httpCode . ')</p>';
            if ($response) {
                $responseJson = json_decode($response, true);
                if ($responseJson && isset($responseJson['error'])) {
                    if (strpos($responseJson['error'], 'Could not connect') !== false) {
                        echo '<p class="error">❌ خطای اتصال: نمی‌تواند به سرور اصلی متصل شود!</p>';
                    }
                }
                echo '<pre>' . htmlspecialchars($response) . '</pre>';
            }
        } elseif ($httpCode == 404) {
            echo '<p class="error">❌ خطای 404: مسیر پیدا نشد!</p>';
            echo '<p>مشکل: فایل index.php یا .htaccess در مسیر درست نیست.</p>';
        } elseif ($curlErrno == CURLE_COULDNT_CONNECT || strpos($curlError, 'Could not connect') !== false) {
            echo '<p class="error">❌ خطای اتصال: نمی‌تواند به سرور اصلی متصل شود!</p>';
            if ($publicIP) {
                echo '<div class="ip-info">';
                echo '<p><strong>راه حل:</strong></p>';
                echo '<p>IP سرور پروکسی: <code>' . htmlspecialchars($publicIP) . '</code></p>';
                echo '<p>این IP باید در firewall سرور اصلی (<code>' . htmlspecialchars($internalHost ?? 'نامشخص') . '</code>) whitelist شود.</p>';
                echo '</div>';
            }
            echo '<p><strong>راه حل:</strong></p>';
            echo '<ol>';
            echo '<li>IP سرور پروکسی (' . ($publicIP ? htmlspecialchars($publicIP) : 'نامشخص') . ') را در firewall سرور اصلی whitelist کنید</li>';
            echo '<li>محدودیت IP را برای endpoint webhook بردارید</li>';
            echo '<li>بررسی کنید که سرور اصلی در دسترس است</li>';
            echo '<li>فایل FIREWALL_FIX.md را مطالعه کنید</li>';
            echo '</ol>';
            if ($curlError) {
                echo '<p>جزئیات خطا: <code>' . htmlspecialchars($curlError) . '</code></p>';
            }
        } else {
            echo '<p class="warning">⚠️ HTTP ' . $httpCode . '</p>';
            if ($curlError) {
                echo '<p class="error">خطا: ' . htmlspecialchars($curlError) . '</p>';
            }
            if ($response) {
                echo '<pre>' . htmlspecialchars($response) . '</pre>';
            }
        }
        echo '</div>';
        
        // تست 2.5: تست اتصال به سرور اصلی
        if ($internalHost) {
            echo '<div class="test">';
            echo '<h2>2.5. تست اتصال HTTPS به سرور اصلی</h2>';
            echo '<p><strong>Host:</strong> ' . htmlspecialchars($internalHost) . '</p>';
            if ($internalIP) {
                echo '<p><strong>IP:</strong> ' . htmlspecialchars($internalIP) . '</p>';
            }
            
            // تست ساده اتصال
            $testCh = curl_init('https://' . $internalHost);
            curl_setopt($testCh, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($testCh, CURLOPT_TIMEOUT, 10);
            curl_setopt($testCh, CURLOPT_CONNECTTIMEOUT, 10);
            curl_setopt($testCh, CURLOPT_NOBODY, true);
            curl_setopt($testCh, CURLOPT_SSL_VERIFYPEER, true);
            curl_setopt($testCh, CURLOPT_SSL_VERIFYHOST, 2);
            
            $connectStartTime = microtime(true);
            $testResult = curl_exec($testCh);
            $connectEndTime = microtime(true);
            $connectTime = round(($connectEndTime - $connectStartTime) * 1000, 2);
            
            $testHttpCode = curl_getinfo($testCh, CURLINFO_HTTP_CODE);
            $testError = curl_error($testCh);
            $testErrno = curl_errno($testCh);
            curl_close($testCh);
            
            echo '<p>زمان اتصال: <strong>' . htmlspecialchars($connectTime) . ' ms</strong></p>';
            
            if ($testResult !== false || $testHttpCode > 0) {
                echo '<p class="success">✅ سرور اصلی در دسترس است (HTTP ' . $testHttpCode . ')</p>';
            } else {
                echo '<p class="error">❌ نمی‌تواند به سرور اصلی متصل شود</p>';
                if ($publicIP) {
                    echo '<div class="ip-info">';
                    echo '<p><strong>⚠️ مشکل اصلی:</strong> IP پروکسی (' . htmlspecialchars($publicIP) . ') نمی‌تواند به سرور اصلی (' . htmlspecialchars($internalHost) . ') متصل شود.</p>';
                    echo '<p><strong>راه حل:</strong> این IP را در firewall سرور اصلی whitelist کنید.</p>';
                    echo '</div>';
                }
                if ($testError) {
                    echo '<p>خطا: <code>' . htmlspecialchars($testError) . '</code></p>';
                }
                echo '<p>این مشکل معمولاً به دلیل firewall یا محدودیت شبکه است.</p>';
            }
            echo '</div>';
        }

        // تست 3: بررسی SSL
        echo '<div class="test">';
        echo '<h2>3. بررسی گواهینامه SSL</h2>';
        $ch = curl_init($baseUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_NOBODY, true);
        
        $result = curl_exec($ch);
        $sslError = curl_error($ch);
        $sslInfo = curl_getinfo($ch);
        curl_close($ch);
        
        if (!$sslError && isset($sslInfo['ssl_verify_result']) && $sslInfo['ssl_verify_result'] == 0) {
            echo '<p class="success">✅ گواهینامه SSL معتبر است</p>';
        } else {
            echo '<p class="warning">⚠️ مشکل احتمالی در گواهینامه SSL</p>';
            if ($sslError) {
                echo '<p>خطا: ' . htmlspecialchars($sslError) . '</p>';
            }
        }
        echo '</div>';

        // تست 4: بررسی وضعیت Webhook در تلگرام
        if (defined('TG_PROXY_CONFIG')) {
            $config = TG_PROXY_CONFIG;
            $botToken = $config['telegram_bot_token'] ?? null;
            
            if ($botToken) {
                echo '<div class="test">';
                echo '<h2>4. بررسی وضعیت Webhook در تلگرام</h2>';
                
                // چک کردن وضعیت webhook از طریق Telegram API
                $webhookStatusUrl = 'https://api.telegram.org/bot' . $botToken . '/getWebhookInfo';
                $statusCh = curl_init($webhookStatusUrl);
                curl_setopt($statusCh, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($statusCh, CURLOPT_TIMEOUT, 10);
                curl_setopt($statusCh, CURLOPT_SSL_VERIFYPEER, true);
                curl_setopt($statusCh, CURLOPT_SSL_VERIFYHOST, 2);
                
                $statusResponse = curl_exec($statusCh);
                $statusHttpCode = curl_getinfo($statusCh, CURLINFO_HTTP_CODE);
                $statusError = curl_error($statusCh);
                curl_close($statusCh);
                
                if ($statusResponse) {
                    $statusData = json_decode($statusResponse, true);
                    if ($statusData && isset($statusData['ok']) && $statusData['ok']) {
                        $webhookInfo = $statusData['result'] ?? [];
                        $webhookUrl = $webhookInfo['url'] ?? '';
                        $hasCustomCert = $webhookInfo['has_custom_certificate'] ?? false;
                        $pendingUpdates = $webhookInfo['pending_update_count'] ?? 0;
                        $lastErrorDate = $webhookInfo['last_error_date'] ?? null;
                        $lastErrorMessage = $webhookInfo['last_error_message'] ?? null;
                        $maxConnections = $webhookInfo['max_connections'] ?? null;
                        
                        echo '<pre>';
                        echo 'Webhook URL: ' . ($webhookUrl ? htmlspecialchars($webhookUrl) : '❌ تنظیم نشده') . "\n";
                        
                        if ($webhookUrl) {
                            $expectedUrl = $webhookUrl;
                            $actualUrl = $baseUrl . '/telegram/webhook';
                            
                            if ($webhookUrl === $actualUrl || strpos($webhookUrl, '/telegram/webhook') !== false) {
                                echo 'Status: ✅ Webhook تنظیم شده است' . "\n";
                            } else {
                                echo 'Status: ⚠️ Webhook به آدرس دیگری تنظیم شده' . "\n";
                                echo 'Expected: ' . htmlspecialchars($actualUrl) . "\n";
                                echo 'Actual: ' . htmlspecialchars($webhookUrl) . "\n";
                            }
                            
                            echo 'Custom Certificate: ' . ($hasCustomCert ? 'بله' : 'خیر') . "\n";
                            echo 'Pending Updates: ' . htmlspecialchars($pendingUpdates) . "\n";
                            echo 'Max Connections: ' . ($maxConnections ? htmlspecialchars($maxConnections) : 'نامحدود') . "\n";
                            
                            if ($lastErrorDate) {
                                $errorDate = date('Y-m-d H:i:s', $lastErrorDate);
                                echo 'Last Error Date: ' . htmlspecialchars($errorDate) . "\n";
                                if ($lastErrorMessage) {
                                    echo 'Last Error: ' . htmlspecialchars($lastErrorMessage) . "\n";
                                    
                                    // بررسی نوع خطا
                                    if (strpos($lastErrorMessage, '404') !== false || strpos($lastErrorMessage, 'Not Found') !== false) {
                                        echo '<p class="error">⚠️ خطای 404: مسیر webhook پیدا نشده است!</p>';
                                    } elseif (strpos($lastErrorMessage, '400') !== false || strpos($lastErrorMessage, 'Bad Request') !== false) {
                                        echo '<p class="error">⚠️ خطای 400: درخواست نامعتبر است!</p>';
                                    } elseif (strpos($lastErrorMessage, 'Could not connect') !== false) {
                                        echo '<p class="error">⚠️ خطای اتصال: تلگرام نمی‌تواند به سرور متصل شود!</p>';
                                    }
                                }
                            } else {
                                echo 'Last Error: ❌ خطایی گزارش نشده' . "\n";
                            }
                        } else {
                            echo 'Status: ❌ Webhook تنظیم نشده است' . "\n";
                            echo '<p class="warning">لطفاً webhook را از داخل سیستم تنظیم کنید.</p>';
                        }
                        echo '</pre>';
                        
                        // نمایش کامل اطلاعات webhook
                        if (isset($_GET['show_full'])) {
                            echo '<details>';
                            echo '<summary>نمایش اطلاعات کامل (JSON)</summary>';
                            echo '<pre>' . htmlspecialchars(json_encode($statusData, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)) . '</pre>';
                            echo '</details>';
                        } else {
                            echo '<p><a href="?show_full=1">نمایش اطلاعات کامل</a></p>';
                        }
                    } else {
                        echo '<p class="error">❌ نمی‌تواند وضعیت webhook را دریافت کند</p>';
                        if ($statusData && isset($statusData['description'])) {
                            echo '<p>خطا: ' . htmlspecialchars($statusData['description']) . '</p>';
                        }
                        if ($statusError) {
                            echo '<p>خطای curl: ' . htmlspecialchars($statusError) . '</p>';
                        }
                    }
                } else {
                    echo '<p class="error">❌ نمی‌تواند به Telegram API متصل شود</p>';
                    if ($statusError) {
                        echo '<p>خطا: ' . htmlspecialchars($statusError) . '</p>';
                    }
                }
                echo '</div>';
            }
        }
        
        // تست 5: بررسی فایل‌های ضروری
        echo '<div class="test">';
        echo '<h2>5. بررسی فایل‌های ضروری</h2>';
        $files = [
            'index.php' => __DIR__ . '/index.php',
            '.htaccess' => __DIR__ . '/.htaccess',
        ];
        foreach ($files as $name => $path) {
            if (file_exists($path)) {
                echo '<p class="success">✅ ' . htmlspecialchars($name) . ' موجود است</p>';
            } else {
                echo '<p class="error">❌ ' . htmlspecialchars($name) . ' موجود نیست!</p>';
            }
        }
        echo '</div>';

        // خلاصه و راهنمای بعدی
        echo '<div class="test warning">';
        echo '<h2>📝 خلاصه و راهنمای بعدی</h2>';
        
        if ($publicIP && $internalHost) {
            echo '<div class="ip-info">';
            echo '<h3>اطلاعات مهم برای تنظیم Firewall:</h3>';
            echo '<ul>';
            echo '<li><strong>IP سرور پروکسی:</strong> <code>' . htmlspecialchars($publicIP) . '</code></li>';
            echo '<li><strong>سرور اصلی:</strong> <code>' . htmlspecialchars($internalHost) . '</code></li>';
            if ($internalIP) {
                echo '<li><strong>IP سرور اصلی:</strong> <code>' . htmlspecialchars($internalIP) . '</code></li>';
            }
            echo '</ul>';
            echo '<p><strong>⚠️ مهم:</strong> IP پروکسی (' . htmlspecialchars($publicIP) . ') باید در firewall سرور اصلی whitelist شود تا بتواند به webhook endpoint متصل شود.</p>';
            echo '</div>';
        }
        
        echo '<ol>';
        echo '<li>اگر config.php وجود ندارد یا ناقص است، آن را بسازید و تنظیمات را وارد کنید</li>';
        echo '<li>اگر endpoint 404 می‌دهد، فایل‌ها را در root domain قرار دهید و .htaccess را بررسی کنید</li>';
        echo '<li>اگر اتصال به سرور اصلی ناموفق است، IP پروکسی را در firewall whitelist کنید</li>';
        echo '<li>اگر SSL مشکل دارد، با هاستینگ خود تماس بگیرید</li>';
        echo '<li>برای تست webhook، از دستور curl استفاده کنید (در TEST_WEBHOOK.md آمده)</li>';
        echo '</ol>';
        echo '</div>';
        ?>
    </div>
</body>
</html>
