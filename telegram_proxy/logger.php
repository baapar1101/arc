<?php
/**
 * سیستم لاگ برای پروکسی تلگرام
 */

class TelegramProxyLogger {
	private static $logDir = __DIR__ . '/logs';
	private static $logFile = null;
	
	/**
	 * مقداردهی اولیه لاگر
	 */
	public static function init() {
		if (!is_dir(self::$logDir)) {
			@mkdir(self::$logDir, 0755, true);
		}
		
		$date = date('Y-m-d');
		self::$logFile = self::$logDir . '/proxy_' . $date . '.log';
	}
	
	/**
	 * نوشتن لاگ
	 */
	public static function log(string $level, string $message, array $context = []): void {
		if (!self::$logFile) {
			self::init();
		}
		
		$timestamp = date('Y-m-d H:i:s');
		$contextStr = !empty($context) ? ' ' . json_encode($context, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : '';
		$logEntry = "[$timestamp] [$level] $message$contextStr" . PHP_EOL;
		
		@file_put_contents(self::$logFile, $logEntry, FILE_APPEND | LOCK_EX);
		
		// همچنین در stderr هم بنویس (برای docker logs)
		if (defined('STDERR')) {
			@fwrite(STDERR, $logEntry);
		}
	}
	
	/**
	 * لاگ اطلاعات
	 */
	public static function info(string $message, array $context = []): void {
		self::log('INFO', $message, $context);
	}
	
	/**
	 * لاگ خطا
	 */
	public static function error(string $message, array $context = []): void {
		self::log('ERROR', $message, $context);
	}
	
	/**
	 * لاگ هشدار
	 */
	public static function warning(string $message, array $context = []): void {
		self::log('WARNING', $message, $context);
	}
	
	/**
	 * لاگ دیباگ
	 */
	public static function debug(string $message, array $context = []): void {
		self::log('DEBUG', $message, $context);
	}
	
	/**
	 * دریافت آخرین خطاها
	 */
	public static function getRecentErrors(int $lines = 50): array {
		if (!self::$logFile || !file_exists(self::$logFile)) {
			return [];
		}
		
		$content = @file_get_contents(self::$logFile);
		if (!$content) {
			return [];
		}
		
		$allLines = explode(PHP_EOL, $content);
		$errorLines = array_filter($allLines, function($line) {
			return strpos($line, '[ERROR]') !== false || strpos($line, '[WARNING]') !== false;
		});
		
		return array_slice($errorLines, -$lines);
	}
}

