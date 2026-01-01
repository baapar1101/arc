<?php
/**
 * اسکریپت مقایسه خروجی Python با PHP SDK
 * داده‌ها از لاگ Python استخراج شده‌اند
 */

require __DIR__ . '/tmp/moadian/vendor/autoload.php';

use SnappMarketPro\Moadian\Services\Normalizer;
use SnappMarketPro\Moadian\Services\SignatureService;
use SnappMarketPro\Moadian\Services\EncryptionService;
use phpseclib3\Crypt\RSA;

echo "=" . str_repeat("=", 79) . "\n";
echo "مقایسه خروجی Python با PHP SDK\n";
echo "=" . str_repeat("=", 79) . "\n\n";

// داده‌های از لاگ Python
$pythonAesHex = "70e6a15350fd97b67b83fae4fea6e067a8fbcc289517997b2566496269b4b610";
$pythonIvHex = "637aa1a3433d40462d2b8c7408aef9e5";
$pythonEncryptedAesKey = "xWLuHdQ3HP2ZCODH8J70XkqEw4I5/TtaKlRkvDRDl0TX9D5LtFyEML1pNFM1Bv5TUkT7lcvBnZpFdxCckmdflW3UYX1Sg9yhtgWxG5sQga1xUbyo34HAjkIuD7DPkrJqCb2cStldIekpMc+/aj1Rbg6fQrU6gX2F5N2Jg0Kf+RAZmCDj8MJ1SCmQJZk0OwyhNfuAqL0zs+sxkgRTIkvQBDZT9LGYiEOqRLFn4VmRx3ntNMsYlf75Cw2Ae5cv6wYgwuRWGeGR1yKMFJH3UTY6dcYYCgBR2ASLfBv7YE6FjW5RXbt2J3SRgY1r9pLbdKX6hWFG3B3aM27ObtD67xJiJIJDvHuKS5eTcu5Di6aLYYM1RJshMzAbKQCEaeXZcX1X3ODul9PLKtzb11pKRdYjmsTEvjPJj+059y6Lm+m/o3cC8o9vNPgZxFcPtrMLZqaWss8//Mq/U1UiI9Df7Xneeuysa/71QJ7wUcDr/cVqDOGyPyLoEV31Kpq3JluHwLK7hwZdXjJUpGGYdfhBleP9QEocO2HBNAzvkna3Q/vairhqxeAU1EbwUgPoo517ups5U9e5uvzq4ni4m7fiGvK5xCIhF9Tsg1zCkVZHesXX3GS+kjKH3Tz4cSMwIKC9BCkW8BWNOSRcuRRhsSokrsbc7Ng5Wnk8/98RT0QJ/NgHbcE=";
$pythonNormalizedString = "eyJhbGciOiJIUzUxMiJ9.eyJqdGkiOiJBM09HTTUiLCJ0b2tlbklkIjoiZWQxMDBkNDgtZTc1ZS00MzA4LWFjN2UtOGFlNjRiN2YyNDhmIiwiY3JlYXRlRGF0ZSI6MTc2Njk3MTQ4MjY3MCwiY2xpZW50VHlwZSI6Ik1FTU9SWSIsInRheHBheWVySWQiOiIzMzIwMDU1MjY3Iiwic3ViIjoiQTNPR001IiwiZXhwIjoxNzY2OTg1ODgyLCJpc3MiOiJUQVggT3JnYW5pemF0aW9uIn0.-5zBUpxXsTGL091B7Q_L_deDQNmIaKJ8en3BR8AC-wU-oz2bPyECUcXSzjeLU1b3NYQ1Lldxq9STm5RW92XRnQ#w05xM2G0O/wN5qUL/oHLSsG4u7AUqJWy9WOpcXaN/d+WRzeiEW/jvHcLbgf1jkHR1sJLtO5Bg0SwWNmHfqO9ZAvtVrXashhmnFhpNT074w3CE2ybDIFoyHu4FTTIYl0A1wdNNl9CaMoY6zBBTQHDMnHhhF7GQStCbRzc+d+NX+vEqobmtIa8yiPgQKxrAGdUuuZD2+LWpY0QFGowDucRKPWccnCsXajFMkzzFq936d2hCZx7pcSj4FtnSY/ct9IgQ71ICdLZItnMkXT0gOeetl0b22CtMpH7ZFofwaX/iAGIa6yScKo4/QGzfYmc75Fumz6Q3EP0fGR7cP6Q8Tu0DkC5n+j8PBQt9lOwcr/jSN15R2+ea28aQ0zvfE317JzWkOno6VTarFZIme4C+5h1hBmnazh3hWOcshI/cACjH2smOaWRx60TQjtZf/0SNo2xD1JMAgSVgcTEM0Zdlw98zfMTKI1PkV4L7Q==#Q3DzJZ57Yvgpx5K32kXPEYbbBqWovLd3NZmQiyDj2PGeLdG9AV16XqbReoYPqXqVGsz/GVusWFBDfvVzaetWNcYILKxl4V+/BM7kzS7QEbiufsBC5OQ54qEVO2QRPSNWlEYzbE9J8o8n0ORScDujl2mL94ONSaKQ3/IXW76OMzlwC3XOSGTGdjKrlupBTT3HX8Pc6QDJ70Yew5SiisWix0ujUpC50+24CpTcQelO3OvCuJsdJjYocHEsTaFK6pIT1gzl+jXYGhV2KuePqZtHrFbPguj0MikPs53ueyURtrsuhxXBXjtv4zuE9sH7hiK6alUsAO2Lu3jWtvfTChNIwA==#6a2bcd88-a871-4245-a393-2843eafe6e02#A3OGM5#637aa1a3433d40462d2b8c7408aef9e5#INVOICE_V01#false#xWLuHdQ3HP2ZCODH8J70XkqEw4I5/TtaKlRkvDRDl0TX9D5LtFyEML1pNFM1Bv5TUkT7lcvBnZpFdxCckmdflW3UYX1Sg9yhtgWxG5sQga1xUbyo34HAjkIuD7DPkrJqCb2cStldIekpMc+/aj1Rbg6fQrU6gX2F5N2Jg0Kf+RAZmCDj8MJ1SCmQJZk0OwyhNfuAqL0zs+sxkgRTIkvQBDZT9LGYiEOqRLFn4VmRx3ntNMsYlf75Cw2Ae5cv6wYgwuRWGeGR1yKMFJH3UTY6dcYYCgBR2ASLfBv7YE6FjW5RXbt2J3SRgY1r9pLbdKX6hWFG3B3aM27ObtD67xJiJIJDvHuKS5eTcu5Di6aLYYM1RJshMzAbKQCEaeXZcX1X3ODul9PLKtzb11pKRdYjmsTEvjPJj+059y6Lm+m/o3cC8o9vNPgZxFcPtrMLZqaWss8//Mq/U1UiI9Df7Xneeuysa/71QJ7wUcDr/cVqDOGyPyLoEV31Kpq3JluHwLK7hwZdXjJUpGGYdfhBleP9QEocO2HBNAzvkna3Q/vairhqxeAU1EbwUgPoo517ups5U9e5uvzq4ni4m7fiGvK5xCIhF9Tsg1zCkVZHesXX3GS+kjKH3Tz4cSMwIKC9BCkW8BWNOSRcuRRhsSokrsbc7Ng5Wnk8/98RT0QJ/NgHbcE=#374ddc3c-42bf-40ca-a6bb-29abe9df2655#25ac701c-2582-4829-a3c2-fa5df9351759#1766977051716";
$pythonSignature = "hgYX3ErM6AHgZBP+EzuN50SwI+LWfM3/64JYx0xn+OtJ0c3V3MlaiwvBjtV2RplYsBKjZD1DGMOzwSogYPv+MFU1x0UKjhSUcST/OuxWpqaEJBsCWx8XM9ydv0WZL726l0IWMpfN3X0Mur+vZI+4t/1mNIc8/l5BRUQniL97LecI/R0N0ew5wxxiXC7Rtfu3jDs1TdMYU/xNlCsdRVLGgDT99lhVNIDYuWGlWxks/djxMEbJPJC+YMYIb5MA3KIFpQxapawCOjNfistIfdNBbqiecK9jWCM27GAr+wUa/tDIQyrJHDjPrNS5qibDZPhOBj+KRTk11lnB6Oi8bveAXg==";

// کلید عمومی سازمان (از لاگ - باید کامل باشد)
$serverPublicKey = "MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxdzREOEfk3vBQogDPGTMqdDQ7t0oDhuKMZkA+Wm1lhzjjhAGfSUOuDvOKRoUEQwP8oUcXRmYzcvCUgcfoRT5iz7HbovqH+bIeJwT4rmLmFcbfPke+E3DLUxOtIZifEXrKXWgSVPkRnhMgym6UiAtnzwA1rmK...";

echo "1. تست encryptAesKey:\n";
echo "   Python AES Hex: " . $pythonAesHex . "\n";
echo "   Python AES Hex length: " . strlen($pythonAesHex) . "\n";
echo "   Python Encrypted AES Key: " . substr($pythonEncryptedAesKey, 0, 100) . "...\n\n";

// تست encryptAesKey در PHP
// توجه: برای تست کامل نیاز به کلید عمومی کامل داریم
// اما می‌توانیم بررسی کنیم که آیا hex string به درستی پردازش می‌شود
echo "   در PHP، encryptAesKey(\$aesHex) فراخوانی می‌شود که \$aesHex یک hex string است.\n";
echo "   phpseclib RSA::encrypt(\$aesHex) hex string را به binary تبدیل می‌کند.\n\n";

// تست normalize
echo "2. تست Normalize:\n";
echo "   Python Normalized String length: " . strlen($pythonNormalizedString) . "\n";
echo "   Python Normalized String (first 200 chars): " . substr($pythonNormalizedString, 0, 200) . "...\n\n";

// ساختار داده برای normalize (از لاگ)
// باید packet و headers را بازسازی کنیم
$packetData = [
    "uid" => "374ddc3c-42bf-40ca-a6bb-29abe9df2655",
    "packetType" => "INVOICE_V01",
    "retry" => false,
    "data" => "w05xM2G0O/wN5qUL/oHLSsG4u7AUqJWy9WOpcXaN/d+WRzeiEW/jvHcLbgf1jkHR1sJLtO5Bg0SwWNmHfqO9ZAvtVrXashhmnFhpNT074w3CE2ybDIFoyHu4FTTIYl0A1wdNNl9CaMoY6zBBTQHDMnHhhF7GQStCbRzc+d+NX+vEqobmtIa8yiPgQKxrAGdUuuZD2+LWpY0QFGowDucRKPWccnCsXajFMkzzFq936d2hCZx7pcSj4FtnSY/ct9IgQ71ICdLZItnMkXT0gOeetl0b22CtMpH7ZFofwaX/iAGIa6yScKo4/QGzfYmc75Fumz6Q3EP0fGR7cP6Q8Tu0DkC5n+j8PBQt9lOwcr/jSN15R2+ea28aQ0zvfE317JzWkOno6VTarFZIme4C+5h1hBmnazh3hWOcshI/cACjH2smOaWRx60TQjtZf/0SNo2xD1JMAgSVgcTEM0Zdlw98zfMTKI1PkV4L7Q==",
    "encryptionKeyId" => "6a2bcd88-a871-4245-a393-2843eafe6e02",
    "symmetricKey" => $pythonEncryptedAesKey,
    "iv" => $pythonIvHex,
    "fiscalId" => "A3OGM5",
    "dataSignature" => "Q3DzJZ57Yvgpx5K32kXPEYbbBqWovLd3NZmQiyDj2PGeLdG9AV16XqbReoYPqXqVGsz/GVusWFBDfvVzaetWNcYILKxl4V+/BM7kzS7QEbiufsBC5OQ54qEVO2QRPSNWlEYzbE9J8o8n0ORScDujl2mL94ONSaKQ3/IXW76OMzlwC3XOSGTGdjKrlupBTT3HX8Pc6QDJ70Yew5SiisWix0ujUpC50+24CpTcQelO3OvCuJsdJjYocHEsTaFK6pIT1gzl+jXYGhV2KuePqZtHrFbPguj0MikPs53ueyURtrsuhxXBXjtv4zuE9sH7hiK6alUsAO2Lu3jWtvfTChNIwA=="
];

$headers = [
    "timestamp" => "1766977051716",
    "requestTraceId" => "25ac701c-2582-4829-a3c2-fa5df9351759",
    "Authorization" => "eyJhbGciOiJIUzUxMiJ9.eyJqdGkiOiJBM09HTTUiLCJ0b2tlbklkIjoiZWQxMDBkNDgtZTc1ZS00MzA4LWFjN2UtOGFlNjRiN2YyNDhmIiwiY3JlYXRlRGF0ZSI6MTc2Njk3MTQ4MjY3MCwiY2xpZW50VHlwZSI6Ik1FTU9SWSIsInRheHBheWVySWQiOiIzMzIwMDU1MjY3Iiwic3ViIjoiQTNPR001IiwiZXhwIjoxNzY2OTg1ODgyLCJpc3MiOiJUQVggT3JnYW5pemF0aW9uIn0.-5zBUpxXsTGL091B7Q_L_deDQNmIaKJ8en3BR8AC-wU-oz2bPyECUcXSzjeLU1b3NYQ1Lldxq9STm5RW92XRnQ"
];

// ساختار normalize مطابق PHP
$dataForNormalize = array_merge(
    ['packets' => [$packetData]],
    $headers
);

// حذف "Bearer " از Authorization
if (isset($dataForNormalize['Authorization'])) {
    $dataForNormalize['Authorization'] = str_replace('Bearer ', '', $dataForNormalize['Authorization']);
}

echo "   ساختار داده برای normalize:\n";
echo "   - Packets count: " . count($dataForNormalize['packets']) . "\n";
echo "   - Headers: " . implode(', ', array_keys(array_diff_key($dataForNormalize, ['packets' => null]))) . "\n\n";

// تست normalize
$phpNormalized = Normalizer::normalizeArray($dataForNormalize);
echo "   PHP Normalized String length: " . strlen($phpNormalized) . "\n";
echo "   PHP Normalized String (first 200 chars): " . substr($phpNormalized, 0, 200) . "...\n\n";

// مقایسه
echo "   مقایسه:\n";
if ($phpNormalized === $pythonNormalizedString) {
    echo "   ✓ Normalized strings یکسان هستند!\n\n";
} else {
    echo "   ✗ Normalized strings متفاوت هستند!\n";
    echo "   تفاوت در کاراکتر: " . (strlen($phpNormalized) !== strlen($pythonNormalizedString) ? "طول متفاوت" : "محتوا متفاوت") . "\n";
    if (strlen($phpNormalized) === strlen($pythonNormalizedString)) {
        for ($i = 0; $i < min(strlen($phpNormalized), strlen($pythonNormalizedString)); $i++) {
            if ($phpNormalized[$i] !== $pythonNormalizedString[$i]) {
                echo "   اولین تفاوت در موقعیت: $i\n";
                echo "   PHP: " . substr($phpNormalized, max(0, $i - 20), 40) . "\n";
                echo "   Python: " . substr($pythonNormalizedString, max(0, $i - 20), 40) . "\n";
                break;
            }
        }
    }
    echo "\n";
}

// نمایش flattened برای دیباگ
echo "3. Flattened structure (PHP):\n";
function flattenArray($array, $prefix = "", &$result = []) {
    foreach ($array as $key => $value) {
        $newKey = $prefix ? "$prefix.$key" : $key;
        if (is_array($value)) {
            flattenArray($value, $newKey, $result);
        } else {
            $result[$newKey] = $value;
        }
    }
    return $result;
}

$flattened = flattenArray($dataForNormalize);
ksort($flattened);
foreach ($flattened as $key => $value) {
    $displayValue = is_string($value) && strlen($value) > 50 ? substr($value, 0, 50) . "..." : $value;
    echo "   $key: $displayValue\n";
}
echo "\n";

echo "=" . str_repeat("=", 79) . "\n";
echo "نتیجه: اگر normalized strings یکسان باشند، مشکل در signature یا encryption است.\n";
echo "اگر متفاوت باشند، مشکل در normalize کردن داده‌ها است.\n";
echo "=" . str_repeat("=", 79) . "\n";





