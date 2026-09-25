<?php
/**
 * قطع اتصال امن از حسابیکس و پاکسازی لینک‌ها / شناسه‌های وابسته به کسب‌وکار.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Connection_Service
{
	/**
	 * متاهای سفارش/پست که باید هنگام قطع اتصال پاک شوند (نه فیلدهای checkout مشتری).
	 *
	 * @return string[]
	 */
	public static function sync_meta_keys_to_clear()
	{
		$keys = array(
			'_hesabix_v2_pause_auto_sync',
			'_hesabix_v2_invoice_rp_sync_fp',
			'_hesabix_v2_order_system_note_id',
			'_hesabix_v2_invoice_sync_error_note_id',
			'_hesabix_v2_last_pushed_stock_qty',
		);

		if (class_exists('Hesabix_V2_Invoice_Profit_Service', false)) {
			$keys = array_merge(
				$keys,
				array(
					Hesabix_V2_Invoice_Profit_Service::META_PROFIT,
					Hesabix_V2_Invoice_Profit_Service::META_PROFIT_PERCENT,
					Hesabix_V2_Invoice_Profit_Service::META_GROSS,
					Hesabix_V2_Invoice_Profit_Service::META_NET,
					Hesabix_V2_Invoice_Profit_Service::META_AT,
					Hesabix_V2_Invoice_Profit_Service::META_INVOICE_ID,
					Hesabix_V2_Invoice_Profit_Service::META_TOTAL_COST,
					Hesabix_V2_Invoice_Profit_Service::META_TOTAL_SALES,
					Hesabix_V2_Invoice_Profit_Service::META_CURRENCY_CODE,
					Hesabix_V2_Invoice_Profit_Service::META_CURRENCY_TITLE,
				)
			);
		}

		if (class_exists('Hesabix_V2_Stock_Push_Service', false)) {
			$keys[] = Hesabix_V2_Stock_Push_Service::META_LAST_PUSHED_QTY;
		}

		return array_values(array_unique($keys));
	}

	/**
	 * آیا اتصال فعالی (کلید یا شناسه کسب‌وکار) ذخیره شده است؟
	 *
	 * @return bool
	 */
	public static function is_connected()
	{
		$key = (string) get_option('hesabix_v2_api_key', '');
		$bid = (int) get_option('hesabix_v2_business_id', 0);
		return ($key !== '' || $bid > 0);
	}

	/**
	 * قطع اتصال کامل.
	 *
	 * @param array $args {
	 *     @type bool $clear_remote_bridge پاک کردن URL/توکن پل در کسب‌وکار قبلی حسابیکس (بهترین تلاش)
	 *     @type bool $show_setup_wizard   نمایش مجدد ویزارد
	 *     @type bool $truncate_logs       خالی کردن جدول/فایل لاگ همگام‌سازی
	 *     @type bool $clear_order_meta    پاک کردن متای همگام‌سازی سفارش/محصول
	 * }
	 * @return array{success:bool,message:string,details:array}
	 */
	public static function disconnect(array $args = array())
	{
		$args = wp_parse_args(
			$args,
			array(
				'clear_remote_bridge' => true,
				'show_setup_wizard'   => true,
				'truncate_logs'       => true,
				'clear_order_meta'    => true,
			)
		);

		$details = array(
			'previous_business_id'   => (int) get_option('hesabix_v2_business_id', 0),
			'remote_bridge_cleared'  => false,
			'remote_bridge_error'    => '',
			'mappings_truncated'     => false,
			'queue_truncated'        => false,
			'meta_rows_deleted'      => 0,
			'crons_cleared'          => false,
		);

		$old_bid = $details['previous_business_id'];
		$had_key = (string) get_option('hesabix_v2_api_key', '') !== '';

		if (!empty($args['clear_remote_bridge']) && $old_bid > 0 && $had_key) {
			$api = new Hesabix_V2_Api();
			$remote = $api->clear_woocommerce_bridge_settings($old_bid);
			if (!empty($remote['success'])) {
				$details['remote_bridge_cleared'] = true;
			} else {
				$details['remote_bridge_error'] = isset($remote['message'])
					? (string) $remote['message']
					: __('پاکسازی تنظیمات پل در حسابیکس ناموفق بود.', 'hesabix-v2');
			}
		}

		self::clear_cron_hooks();
		$details['crons_cleared'] = true;

		$details['queue_truncated'] = self::truncate_queue_table();
		$details['mappings_truncated'] = self::truncate_mappings_table();

		if (!empty($args['truncate_logs']) && class_exists('Hesabix_V2_Log_Service', false)) {
			Hesabix_V2_Log_Service::clear_all_logs();
			$details['logs_truncated'] = true;
		}

		if (!empty($args['clear_order_meta'])) {
			$details['meta_rows_deleted'] = self::clear_sync_post_meta();
		}

		self::clear_connection_options();
		self::scrub_business_scoped_preferences();
		self::clear_bridge_local();
		self::clear_plugin_transients();

		// افزونه هنوز فعال است؛ فقط cronهای پایه را برگردان (کشش موجودی خاموش می‌ماند).
		self::reschedule_core_crons();

		if (class_exists('Hesabix_V2_Currency_Service', false)) {
			Hesabix_V2_Currency_Service::invalidate_list_cache();
		}
		if (class_exists('Hesabix_V2_Order_Fiscal_Service', false)) {
			Hesabix_V2_Order_Fiscal_Service::invalidate_bounds_cache();
		}

		update_option('hesabix_v2_enabled', false);
		update_option('hesabix_v2_setup_completed', false);

		if (!empty($args['show_setup_wizard'])) {
			set_transient('hesabix_v2_show_setup_wizard', true, HOUR_IN_SECONDS);
		} else {
			delete_transient('hesabix_v2_show_setup_wizard');
		}

		if (class_exists('Hesabix_V2_Log_Service', false)) {
			Hesabix_V2_Log_Service::info(
				__('قطع اتصال از حسابیکس انجام شد.', 'hesabix-v2'),
				array(
					'entity_type' => 'connection',
					'details'     => $details,
				)
			);
		}

		$message = __('اتصال قطع شد و لینک‌های کسب‌وکار قبلی پاک شدند.', 'hesabix-v2');
		if ($details['remote_bridge_error'] !== '') {
			$message .= ' ' . sprintf(
				/* translators: %s: remote API error */
				__('پاکسازی پل در حسابیکس: %s (در صورت نیاز در پنل حسابیکس تنظیمات ووکامرس کسب‌وکار قبلی را خالی کنید.)', 'hesabix-v2'),
				$details['remote_bridge_error']
			);
		}

		return array(
			'success' => true,
			'message' => $message,
			'details' => $details,
		);
	}

	/**
	 * قبل از ذخیرهٔ اتصال جدید: اگر قبلاً متصل بود، قطع اتصال امن.
	 *
	 * @param int $new_business_id
	 * @return array|null نتیجه disconnect یا null اگر نیازی نبود
	 */
	public static function disconnect_before_new_connection($new_business_id = 0)
	{
		if (!self::is_connected() && !self::has_mapping_or_queue_rows()) {
			return null;
		}

		$old_bid = (int) get_option('hesabix_v2_business_id', 0);
		$new_bid = (int) $new_business_id;

		return self::disconnect(
			array(
				'clear_remote_bridge' => ($old_bid > 0 && ($new_bid < 1 || $new_bid !== $old_bid)),
				'show_setup_wizard'   => false,
				'truncate_logs'       => true,
				'clear_order_meta'    => true,
			)
		);
	}

	/**
	 * @return bool
	 */
	public static function has_mapping_or_queue_rows()
	{
		global $wpdb;
		$map = $wpdb->prefix . 'hesabix_v2';
		$queue = $wpdb->prefix . 'hesabix_v2_queue';
		$map_n = (int) $wpdb->get_var("SELECT COUNT(1) FROM {$map}"); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$queue_n = (int) $wpdb->get_var("SELECT COUNT(1) FROM {$queue}"); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		return ($map_n > 0 || $queue_n > 0);
	}

	/**
	 * @return void
	 */
	private static function clear_cron_hooks()
	{
		wp_clear_scheduled_hook('hesabix_v2_process_queue');
		wp_clear_scheduled_hook('hesabix_v2_clean_old_logs');
		wp_clear_scheduled_hook('hesabix_v2_pull_stock_cron');
	}

	/**
	 * @return void
	 */
	private static function reschedule_core_crons()
	{
		if (!wp_next_scheduled('hesabix_v2_process_queue')) {
			wp_schedule_event(time(), 'every_5_minutes', 'hesabix_v2_process_queue');
		}
		if (!wp_next_scheduled('hesabix_v2_clean_old_logs')) {
			wp_schedule_event(time(), 'daily', 'hesabix_v2_clean_old_logs');
		}
	}

	/**
	 * @return bool
	 */
	private static function truncate_mappings_table()
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2';
		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		return false !== $wpdb->query("TRUNCATE TABLE {$table}");
	}

	/**
	 * @return bool
	 */
	private static function truncate_queue_table()
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_queue';
		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		return false !== $wpdb->query("TRUNCATE TABLE {$table}");
	}

	/**
	 * پاک کردن متاهای همگام‌سازی از postmeta و در صورت HPOS از wc_orders_meta.
	 *
	 * @return int تعداد تقریبی ردیف‌های حذف‌شده
	 */
	private static function clear_sync_post_meta()
	{
		global $wpdb;
		$keys = self::sync_meta_keys_to_clear();
		if (empty($keys)) {
			return 0;
		}

		$deleted = 0;
		$placeholders = implode(',', array_fill(0, count($keys), '%s'));

		// phpcs:ignore WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare
		$sql = $wpdb->prepare(
			"DELETE FROM {$wpdb->postmeta} WHERE meta_key IN ($placeholders)",
			...$keys
		);
		if ($sql) {
			$r = $wpdb->query($sql);
			if (is_numeric($r)) {
				$deleted += (int) $r;
			}
		}

		$orders_meta = $wpdb->prefix . 'wc_orders_meta';
		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$table_exists = $wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s', $orders_meta));
		if ($table_exists === $orders_meta) {
			// phpcs:ignore WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare
			$sql2 = $wpdb->prepare(
				"DELETE FROM {$orders_meta} WHERE meta_key IN ($placeholders)",
				...$keys
			);
			if ($sql2) {
				$r2 = $wpdb->query($sql2);
				if (is_numeric($r2)) {
					$deleted += (int) $r2;
				}
			}
		}

		return $deleted;
	}

	/**
	 * گزینه‌های هویت اتصال.
	 *
	 * @return void
	 */
	private static function clear_connection_options()
	{
		$delete = array(
			'hesabix_v2_api_key',
			'hesabix_v2_business_id',
			'hesabix_v2_fiscal_year_id',
			'hesabix_v2_default_warehouse_id',
			'hesabix_v2_default_bank_id',
			'hesabix_v2_default_cash_register_id',
			'hesabix_v2_currency_id',
			'hesabix_v2_shipping_product_id',
			'hesabix_v2_fee_product_id',
			'hesabix_v2_orphan_parent_products',
			'hesabix_v2_stock_pull_last',
			'hesabix_v2_marketplace_woo_status',
		);

		foreach ($delete as $opt) {
			delete_option($opt);
		}

		update_option('hesabix_v2_opening_inventory_completed', false);
	}

	/**
	 * پاک کردن شناسه‌های وابسته به کسب‌وکار داخل تنظیمات نگهداشت‌شونده.
	 *
	 * @return void
	 */
	private static function scrub_business_scoped_preferences()
	{
		$sync = get_option('hesabix_v2_sync_settings', array());
		if (is_array($sync)) {
			$sync['invoice_extra_tag_ids'] = '';
			$sync['shipping_adjustment_account_id'] = 0;
			$sync['fee_adjustment_account_id'] = 0;
			$sync['fee_deduction_account_id'] = 0;
			update_option('hesabix_v2_sync_settings', $sync);
		}

		$stock_pull = get_option('hesabix_v2_stock_pull', array());
		if (!is_array($stock_pull)) {
			$stock_pull = array();
		}
		$stock_pull['enabled'] = false;
		$stock_pull['warehouse_ids'] = array();
		$stock_pull['warehouse_scope'] = isset($stock_pull['warehouse_scope']) ? $stock_pull['warehouse_scope'] : 'default';
		update_option('hesabix_v2_stock_pull', $stock_pull);

		$ob = get_option('hesabix_v2_opening_inventory_prefs', array());
		if (!is_array($ob)) {
			$ob = array();
		}
		$ob['inventory_account_id'] = 0;
		$ob['equity_account_id'] = 0;
		$ob['warehouse_override'] = 0;
		update_option('hesabix_v2_opening_inventory_prefs', $ob);

		$inv_key = class_exists('Hesabix_V2_Invoice_Warehouse_Service', false)
			? Hesabix_V2_Invoice_Warehouse_Service::OPTION_KEY
			: 'hesabix_v2_invoice_warehouse_rules';
		update_option(
			$inv_key,
			array(
				'resolution' => 'default',
				'rules'      => array(),
			)
		);
	}

	/**
	 * @return void
	 */
	private static function clear_bridge_local()
	{
		if (class_exists('Hesabix_V2_Bridge_Rest', false)) {
			Hesabix_V2_Bridge_Rest::clear_token();
			update_option(Hesabix_V2_Bridge_Rest::OPT_ENABLED, false);
		} else {
			delete_option('hesabix_v2_bridge_token_hash');
			update_option('hesabix_v2_bridge_enabled', false);
		}
	}

	/**
	 * پاک کردن transientهای عملیاتی افزونه (به‌جز کش به‌روزرسانی مخزن).
	 *
	 * @return void
	 */
	private static function clear_plugin_transients()
	{
		global $wpdb;

		$keep_like = array(
			'_transient_hesabix_v2_remote_version',
			'_transient_timeout_hesabix_v2_remote_version',
			'_transient_hesabix_v2_upd_',
			'_transient_timeout_hesabix_v2_upd_',
		);

		// phpcs:ignore WordPress.DB.DirectDatabaseQuery.DirectQuery, WordPress.DB.DirectDatabaseQuery.NoCaching
		$rows = $wpdb->get_col(
			"SELECT option_name FROM {$wpdb->options}
			WHERE option_name LIKE '_transient_hesabix_v2_%'
			   OR option_name LIKE '_transient_timeout_hesabix_v2_%'"
		);

		if (!is_array($rows)) {
			return;
		}

		foreach ($rows as $name) {
			$name = (string) $name;
			$skip = false;
			foreach ($keep_like as $prefix) {
				if (strpos($name, $prefix) === 0) {
					$skip = true;
					break;
				}
			}
			if ($skip) {
				continue;
			}
			if (strpos($name, '_transient_timeout_') === 0) {
				$key = substr($name, strlen('_transient_timeout_'));
				delete_transient($key);
			} elseif (strpos($name, '_transient_') === 0) {
				$key = substr($name, strlen('_transient_'));
				delete_transient($key);
			}
		}

	}
}
