<?php
/**
 * تست مقایسه normalize - بدون نیاز به کتابخانه کامل
 */

// کپی Normalizer از کتابخانه PHP
class Normalizer
{
    public static function normalizeArray(array $data): string
    {
        $flattened = self::flattenArray($data);
        ksort($flattened);
        return self::arrayToValueString($flattened);
    }

    private static function flattenArray(array $array): array
    {
        $result = [];

        foreach ($array as $key => $value) {
            if (is_array($value)) {
                $flattened = self::flattenArray($value);

                $flattened = array_combine(
                    array_map(
                        fn ($nestedKey) => "$key.$nestedKey",
                        array_keys($flattened)
                    ),
                    array_values($flattened)
                );

                $result = array_merge($result, $flattened);
            } else {
                $result[$key] = $value;
            }
        }

        return $result;
    }

    private static function arrayToValueString(array $data): string
    {
        $textValues = [];

        foreach ($data as $value) {
            if (is_bool($value)) {
                $textValue = $value ? 'true' : 'false';
            } elseif ($value === '' || $value === null) {
                $textValue = '#';
            } else {
                $textValue = str_replace('#', '##', (string)$value);
            }

            $textValues[] = $textValue;
        }

        return implode('#', $textValues);
    }
}

echo "=" . str_repeat("=", 79) . "\n";
echo "مقایسه Normalize - Python vs PHP\n";
echo "=" . str_repeat("=", 79) . "\n\n";

// داده‌های از لاگ Python
$pythonNormalizedString = "eyJhbGciOiJIUzUxMiJ9.eyJqdGkiOiJBM09HTTUiLCJ0b2tlbklkIjoiZWQxMDBkNDgtZTc1ZS00MzA4LWFjN2UtOGFlNjRiN2YyNDhmIiwiY3JlYXRlRGF0ZSI6MTc2Njk3MTQ4MjY3MCwiY2xpZW50VHlwZSI6Ik1FTU9SWSIsInRheHBheWVySWQiOiIzMzIwMDU1MjY3Iiwic3ViIjoiQTNPR001IiwiZXhwIjoxNzY2OTg1ODgyLCJpc3MiOiJUQVggT3JnYW5pemF0aW9uIn0.-5zBUpxXsTGL091B7Q_L_deDQNmIaKJ8en3BR8AC-wU-oz2bPyECUcXSzjeLU1b3NYQ1Lldxq9STm5RW92XRnQ#w05xM2G0O/wN5qUL/oHLSsG4u7AUqJWy9WOpcXaN/d+WRzeiEW/jvHcLbgf1jkHR1sJLtO5Bg0SwWNmHfqO9ZAvtVrXashhmnFhpNT074w3CE2ybDIFoyHu4FTTIYl0A1wdNNl9CaMoY6zBBTQHDMnHhhF7GQStCbRzc+d+NX+vEqobmtIa8yiPgQKxrAGdUuuZD2+LWpY0QFGowDucRKPWccnCsXajFMkzzFq936d2hCZx7pcSj4FtnSY/ct9IgQ71ICdLZItnMkXT0gOeetl0b22CtMpH7ZFofwaX/iAGIa6yScKo4/QGzfYmc75Fumz6Q3EP0fGR7cP6Q8Tu0DkC5n+j8PBQt9lOwcr/jSN15R2+ea28aQ0zvfE317JzWkOno6VTarFZIme4C+5h1hBmnazh3hWOcshI/cACjH2smOaWRx60TQjtZf/0SNo2xD1JMAgSVgcTEM0Zdlw98zfMTKI1PkV4L7Q==#Q3DzJZ57Yvgpx5K32kXPEYbbBqWovLd3NZmQiyDj2PGeLdG9AV16XqbReoYPqXqVGsz/GVusWFBDfvVzaetWNcYILKxl4V+/BM7kzS7QEbiufsBC5OQ54qEVO2QRPSNWlEYzbE9J8o8n0ORScDujl2mL94ONSaKQ3/IXW76OMzlwC3XOSGTGdjKrlupBTT3HX8Pc6QDJ70Yew5SiisWix0ujUpC50+24CpTcQelO3OvCuJsdJjYocHEsTaFK6pIT1gzl+jXYGhV2KuePqZtHrFbPguj0MikPs53ueyURtrsuhxXBXjtv4zuE9sH7hiK6alUsAO2Lu3jWtvfTChNIwA==#6a2bcd88-a871-4245-a393-2843eafe6e02#A3OGM5#637aa1a3433d40462d2b8c7408aef9e5#INVOICE_V01#false#xWLuHdQ3HP2ZCODH8J70XkqEw4I5/TtaKlRkvDRDl0TX9D5LtFyEML1pNFM1Bv5TUkT7lcvBnZpFdxCckmdflW3UYX1Sg9yhtgWxG5sQga1xUbyo34HAjkIuD7DPkrJqCb2cStldIekpMc+/aj1Rbg6fQrU6gX2F5N2Jg0Kf+RAZmCDj8MJ1SCmQJZk0OwyhNfuAqL0zs+sxkgRTIkvQBDZT9LGYiEOqRLFn4VmRx3ntNMsYlf75Cw2Ae5cv6wYgwuRWGeGR1yKMFJH3UTY6dcYYCgBR2ASLfBv7YE6FjW5RXbt2J3SRgY1r9pLbdKX6hWFG3B3aM27ObtD67xJiJIJDvHuKS5eTcu5Di6aLYYM1RJshMzAbKQCEaeXZcX1X3ODul9PLKtzb11pKRdYjmsTEvjPJj+059y6Lm+m/o3cC8o9vNPgZxFcPtrMLZqaWss8//Mq/U1UiI9Df7Xneeuysa/71QJ7wUcDr/cVqDOGyPyLoEV31Kpq3JluHwLK7hwZdXjJUpGGYdfhBleP9QEocO2HBNAzvkna3Q/vairhqxeAU1EbwUgPoo517ups5U9e5uvzq4ni4m7fiGvK5xCIhF9Tsg1zCkVZHesXX3GS+kjKH3Tz4cSMwIKC9BCkW8BWNOSRcuRRhsSokrsbc7Ng5Wnk8/98RT0QJ/NgHbcE=#374ddc3c-42bf-40ca-a6bb-29abe9df2655#25ac701c-2582-4829-a3c2-fa5df9351759#1766977051716";

// ساختار داده از لاگ Python
$packetData = [
    "uid" => "374ddc3c-42bf-40ca-a6bb-29abe9df2655",
    "packetType" => "INVOICE_V01",
    "retry" => false,
    "data" => "w05xM2G0O/wN5qUL/oHLSsG4u7AUqJWy9WOpcXaN/d+WRzeiEW/jvHcLbgf1jkHR1sJLtO5Bg0SwWNmHfqO9ZAvtVrXashhmnFhpNT074w3CE2ybDIFoyHu4FTTIYl0A1wdNNl9CaMoY6zBBTQHDMnHhhF7GQStCbRzc+d+NX+vEqobmtIa8yiPgQKxrAGdUuuZD2+LWpY0QFGowDucRKPWccnCsXajFMkzzFq936d2hCZx7pcSj4FtnSY/ct9IgQ71ICdLZItnMkXT0gOeetl0b22CtMpH7ZFofwaX/iAGIa6yScKo4/QGzfYmc75Fumz6Q3EP0fGR7cP6Q8Tu0DkC5n+j8PBQt9lOwcr/jSN15R2+ea28aQ0zvfE317JzWkOno6VTarFZIme4C+5h1hBmnazh3hWOcshI/cACjH2smOaWRx60TQjtZf/0SNo2xD1JMAgSVgcTEM0Zdlw98zfMTKI1PkV4L7Q==",
    "encryptionKeyId" => "6a2bcd88-a871-4245-a393-2843eafe6e02",
    "symmetricKey" => "xWLuHdQ3HP2ZCODH8J70XkqEw4I5/TtaKlRkvDRDl0TX9D5LtFyEML1pNFM1Bv5TUkT7lcvBnZpFdxCckmdflW3UYX1Sg9yhtgWxG5sQga1xUbyo34HAjkIuD7DPkrJqCb2cStldIekpMc+/aj1Rbg6fQrU6gX2F5N2Jg0Kf+RAZmCDj8MJ1SCmQJZk0OwyhNfuAqL0zs+sxkgRTIkvQBDZT9LGYiEOqRLFn4VmRx3ntNMsYlf75Cw2Ae5cv6wYgwuRWGeGR1yKMFJH3UTY6dcYYCgBR2ASLfBv7YE6FjW5RXbt2J3SRgY1r9pLbdKX6hWFG3B3aM27ObtD67xJiJIJDvHuKS5eTcu5Di6aLYYM1RJshMzAbKQCEaeXZcX1X3ODul9PLKtzb11pKRdYjmsTEvjPJj+059y6Lm+m/o3cC8o9vNPgZxFcPtrMLZqaWss8//Mq/U1UiI9Df7Xneeuysa/71QJ7wUcDr/cVqDOGyPyLoEV31Kpq3JluHwLK7hwZdXjJUpGGYdfhBleP9QEocO2HBNAzvkna3Q/vairhqxeAU1EbwUgPoo517ups5U9e5uvzq4ni4m7fiGvK5xCIhF9Tsg1zCkVZHesXX3GS+kjKH3Tz4cSMwIKC9BCkW8BWNOSRcuRRhsSokrsbc7Ng5Wnk8/98RT0QJ/NgHbcE=",
    "iv" => "637aa1a3433d40462d2b8c7408aef9e5",
    "fiscalId" => "A3OGM5",
    "dataSignature" => "Q3DzJZ57Yvgpx5K32kXPEYbbBqWovLd3NZmQiyDj2PGeLdG9AV16XqbReoYPqXqVGsz/GVusWFBDfvVzaetWNcYILKxl4V+/BM7kzS7QEbiufsBC5OQ54qEVO2QRPSNWlEYzbE9J8o8n0ORScDujl2mL94ONSaKQ3/IXW76OMzlwC3XOSGTGdjKrlupBTT3HX8Pc6QDJ70Yew5SiisWix0ujUpC50+24CpTcQelO3OvCuJsdJjYocHEsTaFK6pIT1gzl+jXYGhV2KuePqZtHrFbPguj0MikPs53ueyURtrsuhxXBXjtv4zuE9sH7hiK6alUsAO2Lu3jWtvfTChNIwA=="
];

$headers = [
    "timestamp" => "1766977051716",
    "requestTraceId" => "25ac701c-2582-4829-a3c2-fa5df9351759",
    "Authorization" => "eyJhbGciOiJIUzUxMiJ9.eyJqdGkiOiJBM09HTTUiLCJ0b2tlbklkIjoiZWQxMDBkNDgtZTc1ZS00MzA4LWFjN2UtOGFlNjRiN2YyNDhmIiwiY3JlYXRlRGF0ZSI6MTc2Njk3MTQ4MjY3MCwiY2xpZW50VHlwZSI6Ik1FTU9SWSIsInRheHBheWVySWQiOiIzMzIwMDU1MjY3Iiwic3ViIjoiQTNPR001IiwiZXhwIjoxNzY2OTg1ODgyLCJpc3MiOiJUQVggT3JnYW5pemF0aW9uIn0.-5zBUpxXsTGL091B7Q_L_deDQNmIaKJ8en3BR8AC-wU-oz2bPyECUcXSzjeLU1b3NYQ1Lldxq9STm5RW92XRnQ"
];

// ساختار normalize مطابق PHP (array_merge(['packets' => [...]], $cloneHeader))
$dataForNormalize = array_merge(
    ['packets' => [$packetData]],
    $headers
);

// حذف "Bearer " از Authorization (مطابق Python)
if (isset($dataForNormalize['Authorization'])) {
    $dataForNormalize['Authorization'] = str_replace('Bearer ', '', $dataForNormalize['Authorization']);
}

echo "Python Normalized String length: " . strlen($pythonNormalizedString) . "\n";
echo "Python Normalized String (first 100 chars): " . substr($pythonNormalizedString, 0, 100) . "...\n\n";

// تست normalize در PHP
$phpNormalized = Normalizer::normalizeArray($dataForNormalize);
echo "PHP Normalized String length: " . strlen($phpNormalized) . "\n";
echo "PHP Normalized String (first 100 chars): " . substr($phpNormalized, 0, 100) . "...\n\n";

// مقایسه
echo "=" . str_repeat("=", 79) . "\n";
if ($phpNormalized === $pythonNormalizedString) {
    echo "✓ Normalized strings یکسان هستند!\n";
} else {
    echo "✗ Normalized strings متفاوت هستند!\n\n";
    echo "تفاوت در طول: " . (strlen($phpNormalized) !== strlen($pythonNormalizedString) ? "بله (" . strlen($phpNormalized) . " vs " . strlen($pythonNormalizedString) . ")" : "خیر") . "\n";
    
    if (strlen($phpNormalized) === strlen($pythonNormalizedString)) {
        for ($i = 0; $i < min(strlen($phpNormalized), strlen($pythonNormalizedString)); $i++) {
            if ($phpNormalized[$i] !== $pythonNormalizedString[$i]) {
                echo "\nاولین تفاوت در موقعیت: $i\n";
                echo "PHP (20 chars around): " . substr($phpNormalized, max(0, $i - 20), 40) . "\n";
                echo "Python (20 chars around): " . substr($pythonNormalizedString, max(0, $i - 20), 40) . "\n";
                break;
            }
        }
    } else {
        echo "\nمقایسه بخش‌های اول:\n";
        echo "PHP (first 500): " . substr($phpNormalized, 0, 500) . "\n\n";
        echo "Python (first 500): " . substr($pythonNormalizedString, 0, 500) . "\n";
    }
}

echo "=" . str_repeat("=", 79) . "\n";

