<?php
/**
 * اسکریپت تست PHP برای مقایسه با نسخه Python
 * این اسکریپت همان داده‌ها را با PHP SDK پردازش می‌کند
 */

require __DIR__ . '/tmp/moadian/vendor/autoload.php';

use SnappMarketPro\Moadian\Services\Normalizer;
use SnappMarketPro\Moadian\Services\SignatureService;
use SnappMarketPro\Moadian\Services\EncryptionService;
use phpseclib3\Crypt\RSA;

// داده تست (باید از لاگ Python کپی شود)
$testData = [
    "packets" => [
        [
            "uid" => "test-uid-123",
            "packetType" => "INVOICE_V01",
            "data" => "encrypted-data",
            "symmetricKey" => "enc-key",
            "iv" => "hex-iv-string",
            "fiscalId" => "A1B2C3",
            "dataSignature" => "sig"
        ]
    ],
    "timestamp" => "1234567890",
    "requestTraceId" => "abc123"
];

echo "=" . str_repeat("=", 79) . "\n";
echo "PHP SDK Test - Normalize Comparison\n";
echo "=" . str_repeat("=", 79) . "\n";
echo "Input data:\n";
echo json_encode($testData, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n\n";

// تست normalize
$normalized = Normalizer::normalizeArray($testData);
echo "Normalized string: " . $normalized . "\n";
echo "Normalized length: " . strlen($normalized) . "\n\n";

// نمایش flattened (برای دیباگ)
function printFlattened($array, $prefix = "") {
    foreach ($array as $key => $value) {
        $fullKey = $prefix ? "$prefix.$key" : $key;
        if (is_array($value)) {
            printFlattened($value, $fullKey);
        } else {
            echo "  $fullKey: $value\n";
        }
    }
}

echo "Flattened structure:\n";
// شبیه‌سازی flatten برای نمایش
$flattened = [];
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

$flattened = flattenArray($testData);
ksort($flattened);
foreach ($flattened as $key => $value) {
    echo "  $key: $value\n";
}
echo "\n";

// تست encryptAesKey
echo "Testing encryptAesKey:\n";
$testAesHex = bin2hex(random_bytes(32));
echo "AES Hex (64 chars): " . $testAesHex . "\n";
echo "AES Hex length: " . strlen($testAesHex) . "\n";

// برای تست، نیاز به کلید عمومی داریم
// این فقط برای نمایش است
echo "\nNote: To test encryption, you need the actual tax organization public key.\n";
echo "Copy the AES hex and IV hex from Python logs and compare with PHP.\n";





