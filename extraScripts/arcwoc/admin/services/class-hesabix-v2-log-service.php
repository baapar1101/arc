<?php
/**
 * Logging Service
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Log_Service
{
	/**
	 * Log directory
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      string    $log_dir
	 */
	private static $log_dir;

	/**
	 * Initialize log directory
	 *
	 * @since    2.0.0
	 */
	private static function init()
	{
		if (!self::$log_dir) {
			$upload_dir = wp_upload_dir();
			self::$log_dir = $upload_dir['basedir'] . '/hesabix-v2-logs';

			if (!file_exists(self::$log_dir)) {
				wp_mkdir_p(self::$log_dir);
				file_put_contents(self::$log_dir . '/.htaccess', 'Deny from all');
			}
		}
	}

	/**
	 * Write log to file and database
	 *
	 * @since    2.0.0
	 * @param    string    $level       Log level (info, warning, error, debug)
	 * @param    string    $message     Log message
	 * @param    array     $context     Additional context
	 */
	private static function write($level, $message, $context = array())
	{
		// Initialize
		self::init();

		// Don't log debug messages unless debug mode is on
		if ($level === 'debug' && !get_option('hesabix_v2_debug_mode')) {
			return;
		}

		// Prepare log entry
		$timestamp = current_time('Y-m-d H:i:s');
		$log_entry = sprintf(
			"[%s] [%s] %s\n",
			$timestamp,
			strtoupper($level),
			$message
		);

		if (!empty($context)) {
			$log_entry .= "Context: " . wp_json_encode($context, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . "\n";
		}

		$log_entry .= str_repeat('-', 80) . "\n";

		// Write to file
		$log_file = self::$log_dir . '/' . date('Y-m-d') . '.log';
		file_put_contents($log_file, $log_entry, FILE_APPEND);

		// Also log to database for easier querying
		if ($level !== 'debug') {
			global $wpdb;
			$table = $wpdb->prefix . 'hesabix_v2_sync_log';

			$wpdb->insert(
				$table,
				array(
					'entity_type' => $context['entity_type'] ?? 'system',
					'entity_id' => $context['entity_id'] ?? 0,
					'action' => $level,
					'status' => $level === 'error' ? 'error' : 'success',
					'error_message' => $level === 'error' ? $message : null,
					'request_data' => isset($context['request']) ? wp_json_encode($context['request']) : null,
					'response_data' => isset($context['response']) ? wp_json_encode($context['response']) : null,
					'created_at' => current_time('mysql'),
				),
				array('%s', '%d', '%s', '%s', '%s', '%s', '%s', '%s')
			);
		}
	}

	/**
	 * Log info message
	 *
	 * @since    2.0.0
	 * @param    string    $message
	 * @param    array     $context
	 */
	public static function info($message, $context = array())
	{
		self::write('info', $message, $context);
	}

	/**
	 * Log warning message
	 *
	 * @since    2.0.0
	 * @param    string    $message
	 * @param    array     $context
	 */
	public static function warning($message, $context = array())
	{
		self::write('warning', $message, $context);
	}

	/**
	 * Log error message
	 *
	 * @since    2.0.0
	 * @param    string    $message
	 * @param    array     $context
	 */
	public static function error($message, $context = array())
	{
		self::write('error', $message, $context);
	}

	/**
	 * Log debug message
	 *
	 * @since    2.0.0
	 * @param    string    $message
	 * @param    array     $context
	 */
	public static function debug($message, $context = array())
	{
		self::write('debug', $message, $context);
	}

	/**
	 * Get recent logs from database
	 *
	 * @since    2.0.0
	 * @param    int       $limit
	 * @param    string    $level
	 * @return   array
	 */
	public static function get_recent_logs($limit = 100, $level = null)
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_sync_log';

		$where = '';
		if ($level) {
			$where = $wpdb->prepare(' WHERE action = %s', $level);
		}

		$query = "SELECT * FROM $table $where ORDER BY created_at DESC LIMIT %d";
		$results = $wpdb->get_results($wpdb->prepare($query, $limit), ARRAY_A);

		return $results;
	}

	/**
	 * پاک کردن تمام لاگ‌ها (جدول دیتابیس + فایل‌های .log)
	 *
	 * @since    2.0.0
	 */
	public static function clear_all_logs()
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_sync_log';
		$wpdb->query("TRUNCATE TABLE $table");

		self::init();
		$files = glob(self::$log_dir . '/*.log');
		foreach ($files as $file) {
			if (is_file($file)) {
				@unlink($file);
			}
		}
	}

	/**
	 * Clean old logs
	 *
	 * @since    2.0.0
	 * @param    int    $days    Days to keep
	 */
	public static function clean_old_logs($days = 30)
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_sync_log';

		$date = date('Y-m-d H:i:s', strtotime("-{$days} days"));
		$wpdb->query($wpdb->prepare("DELETE FROM $table WHERE created_at < %s", $date));

		// Also clean old log files
		self::init();
		$files = glob(self::$log_dir . '/*.log');
		foreach ($files as $file) {
			if (filemtime($file) < strtotime("-{$days} days")) {
				@unlink($file);
			}
		}
	}

	/**
	 * Cron: پاکسازی لاگ‌های قدیمی (فیلتر روزها: hesabix_v2_log_retention_days، حداقل ۷).
	 *
	 * @return void
	 */
	public static function cron_clean_old_logs()
	{
		$days = (int) apply_filters('hesabix_v2_log_retention_days', 30);
		if ($days < 7) {
			$days = 7;
		}
		self::clean_old_logs($days);
	}

	/**
	 * Get log file path for download
	 *
	 * @since    2.0.0
	 * @param    string    $date    Date in Y-m-d format
	 * @return   string|false
	 */
	public static function get_log_file($date = null)
	{
		self::init();
		
		if (!$date) {
			$date = date('Y-m-d');
		}

		$file = self::$log_dir . '/' . $date . '.log';
		
		if (file_exists($file)) {
			return $file;
		}

		return false;
	}
}

