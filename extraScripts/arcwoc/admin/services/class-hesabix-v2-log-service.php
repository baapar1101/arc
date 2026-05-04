<?php
/**
 * Logging Service
 *
 * با دیباگ روشن: فایل + دیتابیس برای همه سطوح (شامل جزئیات تبادل API).
 * با دیباگ خاموش: فقط خطاها در فایل و جدول لاگ.
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Log_Service
{
	/** @var string */
	private static $log_dir;

	/** @var int حداکثر طول متن برای ذخیره پس از json_encode (~۵۱۲KiB پیش‌فرض) */
	const MAX_JSON_CHARS = 524288;

	/**
	 * تشخیص حالت لاگ پیش‌پیکربندی‌شده افزونه
	 *
	 * @return bool
	 */
	private static function is_debug_mode_on()
	{
		return (bool) get_option('hesabix_v2_debug_mode');
	}

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
	 * حذف / جایگزینی فیلدهای حساس در آبجکت آرایه‌ای پیش از لاگ.
	 *
	 * @param mixed $data
	 * @return mixed
	 */
	public static function sanitize_log_recursive($data)
	{
		if (is_array($data)) {
			$out = array();
			foreach ($data as $k => $v) {
				$lk = is_string($k) ? strtolower($k) : '';
				if (in_array($lk, array('password', 'passwd', 'api_key', 'apikey', 'secret', 'token', 'refresh_token', 'credit_card'), true)) {
					$out[$k] = '[redacted]';
					continue;
				}
				if ($lk === 'authorization' && is_string($v)) {
					$out[$k] = preg_match('#^apitoken\s|^apikey\s#i', $v)
						? preg_replace('#^(\S+)\s+\S(.*)$#', '$1 ********', $v, 1)
						: '[redacted]';
					continue;
				}
				if (is_array($v)) {
					$out[$k] = self::sanitize_log_recursive($v);
				} elseif (is_object($v)) {
					$out[$k] = self::sanitize_log_recursive((array) $v);
				} else {
					$out[$k] = $v;
				}
			}
			return $out;
		}

		return $data;
	}

	/**
	 * ساده‌سازی فیلدهای حساس (برای هر دو فایل و DB)
	 *
	 * @param mixed $payload
	 * @return mixed
	 */
	public static function prepare_payload_for_storage($payload)
	{
		return self::sanitize_log_recursive($payload);
	}

	/**
	 * json برای ستون با محدود طول و UTF-8
	 *
	 * @param mixed $payload
	 * @return string|null
	 */
	private static function json_column($payload)
	{
		if (null === $payload) {
			return null;
		}
		$prepared = self::sanitize_log_recursive($payload);
		$max = (int) apply_filters('hesabix_v2_log_payload_max_json_chars', self::MAX_JSON_CHARS);
		if ($max < 4096) {
			$max = 4096;
		}
		$json = wp_json_encode($prepared, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
		if ($json !== false && strlen($json) > $max) {
			return substr($json, 0, $max) . "\n…[truncated]";
		}

		return is_string($json) ? $json : wp_json_encode(array('_encode_error' => true), JSON_UNESCAPED_UNICODE);
	}

	/**
	 * پیام آمادهٔ فایل (با trim طول تقریبی)
	 *
	 * @param mixed $payload
	 * @return string
	 */
	private static function json_for_file_preview($payload)
	{
		$prepared = self::sanitize_log_recursive($payload);
		$json = wp_json_encode($prepared, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_INVALID_UTF8_SUBSTITUTE);
		if ($json === false) {
			return '';
		}
		$max = (int) apply_filters('hesabix_v2_log_file_preview_max_chars', self::MAX_JSON_CHARS);
		if ($max < 8192) {
			$max = 8192;
		}
		if (strlen($json) > $max) {
			return substr($json, 0, $max) . "\n…[truncated]";
		}
		return $json;
	}

	/**
	 * نگاشت context به ستون‌های request_data / response_data
	 *
	 * @param string               $level
	 * @param array<string,mixed>  $context
	 * @return array{request:?string,response:?string}
	 */
	private static function derive_request_response_columns($level, $context)
	{
		$req_col = isset($context['request']) ? self::json_column($context['request']) : null;
		$res_col = isset($context['response']) ? self::json_column($context['response']) : null;

		if ($level === 'error' && !$req_col && !$res_col) {
			$extra = array();
			foreach ($context as $k => $v) {
				if (!in_array($k, array('entity_type', 'entity_id', 'execution_time'), true)) {
					$extra[$k] = $v;
				}
			}
			if (!empty($extra)) {
				$res_col = self::json_column($extra);
			}
		} elseif ($level === 'error' && !$res_col && !empty($context['error'])) {
			$res_col = self::json_column(array('error_detail' => $context['error']));
		}

		return array(
			'request' => $req_col,
			'response' => $res_col,
		);
	}

	/**
	 * متن قابل‌نمایش ستون پیام برای خطا
	 *
	 * @param string               $title
	 * @param array<string,mixed>  $context
	 */
	private static function format_error_detail_line($title, $context)
	{
		$detail = '';
		if (!empty($context['error']) && is_string($context['error'])) {
			$detail = trim($context['error']);
		}
		if ($detail === '') {
			return wp_strip_all_tags((string) $title);
		}

		return wp_strip_all_tags(trim($title . ' — ' . $detail));
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
		self::init();
		$debug_on = self::is_debug_mode_on();

		if ($level === 'debug' && !$debug_on) {
			return;
		}

		$file_write = ($level === 'error') || $debug_on;
		if ($file_write) {
			$timestamp = current_time('Y-m-d H:i:s');
			$log_entry = sprintf(
				"[%s] [%s] %s\n",
				$timestamp,
				strtoupper($level),
				$message
			);

			if (!empty($context)) {
				$log_entry .= "Context:\n" . self::json_for_file_preview($context) . "\n";
			}

			$log_entry .= str_repeat('-', 80) . "\n";
			file_put_contents(self::$log_dir . '/' . date('Y-m-d') . '.log', $log_entry, FILE_APPEND);
		}

		$db_insert = ($level === 'error') || $debug_on;
		if (!$db_insert) {
			return;
		}

		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_sync_log';

		$cols = self::derive_request_response_columns($level, $context);

		if ($level === 'error') {
			$status_val = 'error';
		} elseif ($level === 'warning') {
			$status_val = 'warning';
		} elseif ($level === 'debug') {
			$status_val = 'debug';
		} else {
			$status_val = 'success';
		}

		$row = array(
			'entity_type' => isset($context['entity_type']) ? (string) $context['entity_type'] : 'system',
			'entity_id' => isset($context['entity_id']) ? (int) $context['entity_id'] : 0,
			'action' => $level === 'debug' ? 'debug' : $level,
			'status' => $status_val,
			'request_data' => $cols['request'],
			'response_data' => $cols['response'],
			'error_message' => ('error' === $level ? self::format_error_detail_line($message, $context) : null),
			'created_at' => current_time('mysql'),
		);

		$formats_map = array(
			'entity_type' => '%s',
			'entity_id' => '%d',
			'action' => '%s',
			'status' => '%s',
			'request_data' => '%s',
			'response_data' => '%s',
			'error_message' => '%s',
			'created_at' => '%s',
		);

		if (isset($context['execution_time'])) {
			$row['execution_time'] = (float) $context['execution_time'];
			$formats_map['execution_time'] = '%f';
		}

		$wpdb->insert($table, $row, $formats_map);
	}

	/**
	 * @param string               $message
	 * @param array<string,mixed>  $context
	 */
	public static function info($message, $context = array())
	{
		self::write('info', $message, $context);
	}

	/**
	 * @param string               $message
	 * @param array<string,mixed>  $context
	 */
	public static function warning($message, $context = array())
	{
		self::write('warning', $message, $context);
	}

	/**
	 * @param string               $message
	 * @param array<string,mixed>  $context
	 */
	public static function error($message, $context = array())
	{
		self::write('error', $message, $context);
	}

	/**
	 * @param string               $message
	 * @param array<string,mixed>  $context
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
	 * @param    string    $level  action ستون؛ برای فیلتر مثلاً error یا debug
	 * @return   array<int,array<string,mixed>>
	 */
	public static function get_recent_logs($limit = 100, $level = null)
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_sync_log';

		if ($level) {
			$query = $wpdb->prepare(
				"SELECT * FROM $table WHERE action = %s ORDER BY created_at DESC LIMIT %d",
				$level,
				(int) $limit
			);
			return $wpdb->get_results($query, ARRAY_A) ?: array();
		}

		return $wpdb->get_results($wpdb->prepare("SELECT * FROM $table ORDER BY created_at DESC LIMIT %d", (int) $limit), ARRAY_A) ?: array();
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
	 * @param    int    $days    Days to keep
	 */
	public static function clean_old_logs($days = 30)
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_sync_log';

		$date = date('Y-m-d H:i:s', strtotime('-' . absint($days) . ' days'));
		$wpdb->query($wpdb->prepare("DELETE FROM $table WHERE created_at < %s", $date));

		self::init();
		$files = glob(self::$log_dir . '/*.log');
		foreach ($files as $file) {
			if (is_file($file) && filemtime($file) < strtotime('-' . absint($days) . ' days')) {
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
	 * @param    string|null    $date    Date in Y-m-d format
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
