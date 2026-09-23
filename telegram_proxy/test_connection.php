<?php
declare(strict_types=1);
http_response_code(403);
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
echo json_encode(['ok' => false, 'error' => 'DISABLED']);
