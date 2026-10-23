<?php
/**
 * سیستم لاگ برای پروکسی تلگرام
 */

class TelegramProxyLogger {
	private static $logDir = __DIR__ . '/logs';
	private static $logFile = null;
	// کنترل فعال/غیرفعال بودن لاگ و سطح لاگ
	private static $enabled = true;
	private static $level = 'DEBUG';
	private static $levels = [
		'ERROR' => 1,
		'WARNING' => 2,
		'INFO' => 3,
		'DEBUG' => 4,
	];
	
	/**
	 * مقداردهی اولیه لاگر
	 */
	public static function init() {
		// خواندن تنظیمات از config (در صورت وجود)
		if (defined('TG_PROXY_CONFIG') && is_array(TG_PROXY_CONFIG)) {
			$cfg = TG_PROXY_CONFIG;
			if (array_key_exists('enable_logging', $cfg)) {
				self::$enabled = (bool)$cfg['enable_logging'];
			}
			if (!empty($cfg['log_level']) && is_string($cfg['log_level'])) {
				$lvl = strtoupper($cfg['log_level']);
				if (isset(self::$levels[$lvl])) {
					self::$level = $lvl;
				}
			}
		}
		// بازنویسی توسط متغیرهای محیطی در صورت نیاز
		$envEnable = getenv('TG_PROXY_ENABLE_LOGGING');
		if ($envEnable !== false) {
			$val = strtolower(trim($envEnable));
			self::$enabled = !in_array($val, ['0', 'false', 'no', 'off', '']);
		}
		$envLevel = getenv('TG_PROXY_LOG_LEVEL');
		if ($envLevel !== false) {
			$lvl = strtoupper(trim($envLevel));
			if (isset(self::$levels[$lvl])) {
				self::$level = $lvl;
			}
		}

		// اگر لاگ غیرفعال شده است، نیازی به ایجاد دایرکتوری یا فایل نیست
		if (!self::$enabled) {
			return;
		}

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
		// اگر لاگ غیرفعال باشد، از نوشتن جلوگیری کن
		if (!self::$enabled) {
			return;
		}

		$level = strtoupper($level);
		$currentRank = self::$levels[$level] ?? 4;
		$configRank = self::$levels[self::$level] ?? 4;
		// اگر سطح پیام کمتر از سطح پیکربندی باشد، آن را رد کن
		if ($currentRank > $configRank) {
			return;
		}

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

