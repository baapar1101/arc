<?php
/**
 * کشش موجودی عددی حسابیکس → ووکامرس (چند انبار، جمع روی انبارهای انتخاب‌شده).
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Stock_Pull_Service
{
	const CRON_HOOK = 'hesabix_v2_pull_stock_cron';

	const LOCK_TRANSIENT = 'hesabix_v2_stock_pull_running';

	const OPTION_KEY = 'hesabix_v2_stock_pull';

	const SCHEDULE_KEY = 'hesabix_v2_pull_stock_ivl';

	/** @var int تعداد کالا در هر درخواست گزارش (محدودیت ~۵۰۰ سطر = کالا×انبار) */
	const PRODUCT_BATCH = 40;

	/**
	 * گزینه‌های ذخیره‌شده با پیش‌فرض امن.
	 *
	 * @return array<string, mixed>
	 */
	public static function get_options()
	{
		$defaults = array(
			'enabled' => false,
			'warehouse_scope' => 'default',
			'warehouse_ids' => array(),
			'cron_minutes' => 15,
			'force_manage_stock' => true,
			// وقتی فعال است، موجودی با سفارش در ووکامرس کم نمی‌شود (مرجع: حسابیکس / کشش موجودی).
			'disable_wc_stock_reduction' => false,
		);

		$raw = get_option(self::OPTION_KEY, array());
		if (!is_array($raw)) {
			$raw = array();
		}

		$o = wp_parse_args($raw, $defaults);

		$o['enabled'] = !empty($o['enabled']);
		$scope = isset($o['warehouse_scope']) ? (string) $o['warehouse_scope'] : 'default';
		if (!in_array($scope, array('default', 'selected', 'all'), true)) {
			$scope = 'default';
		}
		$o['warehouse_scope'] = $scope;

		$ids = isset($o['warehouse_ids']) && is_array($o['warehouse_ids']) ? $o['warehouse_ids'] : array();
		$clean_ids = array();
		foreach ($ids as $wid) {
			$i = absint($wid);
			if ($i > 0) {
				$clean_ids[] = $i;
			}
		}
		$o['warehouse_ids'] = array_values(array_unique($clean_ids));

		$o['cron_minutes'] = max(5, min(180, absint($o['cron_minutes'])));
		$o['force_manage_stock'] = !empty($o['force_manage_stock']);
		$o['disable_wc_stock_reduction'] = !empty($o['disable_wc_stock_reduction']);

		return $o;
	}

	/**
	 * ثبت بازهٔ cron و اکشن زمان‌بندی.
	 */
	public static function register_hooks()
	{
		add_filter('cron_schedules', array(__CLASS__, 'filter_cron_schedules'));
		add_action(self::CRON_HOOK, array(__CLASS__, 'run_scheduled_pull'));
		add_action('init', array(__CLASS__, 'maybe_ensure_cron_scheduled'), 30);
	}

	/**
	 * اگر کشش زمان‌بندی‌شده فعال است ولی رویداد cron حذف شده، دوباره زمان‌بندی کن.
	 */
	public static function maybe_ensure_cron_scheduled()
	{
		if (defined('WP_INSTALLING') && WP_INSTALLING) {
			return;
		}
		if (!get_option('hesabix_v2_enabled')) {
			return;
		}
		$o = self::get_options();
		if (empty($o['enabled'])) {
			return;
		}
		if (wp_next_scheduled(self::CRON_HOOK)) {
			return;
		}
		wp_schedule_event(time() + 120, self::SCHEDULE_KEY, self::CRON_HOOK);
	}

	/**
	 * @param array<string, mixed> $schedules
	 * @return array<string, mixed>
	 */
	public static function filter_cron_schedules($schedules)
	{
		if (!is_array($schedules)) {
			$schedules = array();
		}
		$opts = self::get_options();
		$m = isset($opts['cron_minutes']) ? (int) $opts['cron_minutes'] : 15;

		$schedules[self::SCHEDULE_KEY] = array(
			'interval' => max(300, min(64800, $m * 60)),
			/* translators: %d: interval in minutes */
			'display' => sprintf(__('موجودی حسابیکس → ووک (%d دقیقه)', 'hesabix-v2'), $m),
		);

		return $schedules;
	}

	/**
	 * حذف و در صورت فعال بودن زمان‌بندی مجدد.
	 */
	public static function reschedule_cron()
	{
		wp_clear_scheduled_hook(self::CRON_HOOK);

		if (!get_option('hesabix_v2_enabled')) {
			return;
		}

		$o = self::get_options();
		if (empty($o['enabled'])) {
			return;
		}

		if (!wp_next_scheduled(self::CRON_HOOK)) {
			wp_schedule_event(time() + 90, self::SCHEDULE_KEY, self::CRON_HOOK);
		}
	}

	public static function run_scheduled_pull()
	{
		$res = self::execute_pull(array('source' => 'cron'));

		if (get_option('hesabix_v2_debug_mode')) {
			Hesabix_V2_Log_Service::debug(
				'Scheduled stock pull',
				array(
					'entity_type' => 'stock_pull',
					'request' => array('decoded' => $res),
				)
			);
		}
	}

	/**
	 * اجرای اصلی کشش موجودی.
	 *
	 * @param array{source?:string} $ctx
	 * @return array{success:bool, message:string, updated?:int, skipped?:int, errors?:int, execution_time?:float}
	 */
	public static function execute_pull($ctx = array())
	{
		$start = microtime(true);
		$source = isset($ctx['source']) ? (string) $ctx['source'] : 'manual';

		if (!class_exists('WooCommerce')) {
			return array(
				'success' => false,
				'message' => __('ووکامرس فعال نیست.', 'hesabix-v2'),
				'execution_time' => microtime(true) - $start,
			);
		}

		if (!get_option('hesabix_v2_enabled')) {
			return array(
				'success' => false,
				'message' => __('افزونه حسابیکس فعال نشده است.', 'hesabix-v2'),
				'execution_time' => microtime(true) - $start,
			);
		}

		$opts = self::get_options();
		if (empty($opts['enabled']) && $source !== 'manual') {
			return array(
				'success' => false,
				'message' => __('کشش موجودی غیرفعال است.', 'hesabix-v2'),
				'execution_time' => microtime(true) - $start,
			);
		}

		if (get_transient(self::LOCK_TRANSIENT)) {
			return array(
				'success' => false,
				'message' => __('یک عملیات کشش موجودی در حال اجراست؛ لحظاتی بعد دوباره تلاش کنید.', 'hesabix-v2'),
				'execution_time' => microtime(true) - $start,
			);
		}
		set_transient(self::LOCK_TRANSIENT, 1, 15 * MINUTE_IN_SECONDS);

		try {
			$wh_filter = self::resolve_warehouse_ids_for_api($opts);
			if (is_wp_error($wh_filter)) {
				return array(
					'success' => false,
					'message' => $wh_filter->get_error_message(),
					'execution_time' => microtime(true) - $start,
				);
			}

			$db = new Hesabix_V2_DB_Service();
			$mappings = $db->get_all_product_mappings();
			if (empty($mappings)) {
				return array(
					'success' => true,
					'message' => __('نگاشت محصولی برای به‌روزرسانی موجودی وجود ندارد.', 'hesabix-v2'),
					'updated' => 0,
					'skipped' => 0,
					'errors' => 0,
					'execution_time' => microtime(true) - $start,
				);
			}

			$hesabix_ids = array();
			foreach ($mappings as $row) {
				$hid = isset($row['hesabix_id']) ? (int) $row['hesabix_id'] : 0;
				if ($hid > 0) {
					$hesabix_ids[] = $hid;
				}
			}
			$hesabix_ids = array_values(array_unique($hesabix_ids));

			$api = new Hesabix_V2_Api();
			$totals = self::fetch_quantities_for_product_ids($api, $hesabix_ids, $wh_filter);

			if (is_wp_error($totals)) {
				return array(
					'success' => false,
					'message' => $totals->get_error_message(),
					'execution_time' => microtime(true) - $start,
				);
			}

			$updated = 0;
			$skipped = 0;
			$errors = 0;

			foreach ($mappings as $row) {
				$hid = isset($row['hesabix_id']) ? (int) $row['hesabix_id'] : 0;
				$wc_id = isset($row['wc_id']) ? (int) $row['wc_id'] : 0;
				$wc_parent = isset($row['wc_parent_id']) && $row['wc_parent_id'] !== null && $row['wc_parent_id'] !== ''
					? (int) $row['wc_parent_id']
					: null;

				if ($hid < 1 || $wc_id < 1) {
					$skipped++;
					continue;
				}

				if (!array_key_exists($hid, $totals)) {
					$skipped++;
					continue;
				}

				$qty = (float) $totals[ $hid ];

				$product = wc_get_product($wc_id);
				if (!$product) {
					$skipped++;
					continue;
				}

				if ($product->is_virtual()) {
					$skipped++;
					continue;
				}

				if ($product->is_type('variable')) {
					$skipped++;
					continue;
				}

				if (!apply_filters('hesabix_v2_stock_pull_apply_to_product', true, $product, $row, $qty, $opts)) {
					$skipped++;
					continue;
				}

				try {
					if (!empty($opts['force_manage_stock'])) {
						$product->set_manage_stock(true);
					} elseif (!$product->managing_stock()) {
						$skipped++;
						continue;
					}

					$product->set_stock_quantity($qty);
					$product->save();

					$updated++;
				} catch (Exception $e) {
					$errors++;
					Hesabix_V2_Log_Service::error(
						'Stock pull: failed to update WooCommerce product',
						array(
							'entity_type' => 'stock_pull',
							'entity_id' => $wc_id,
							'hesabix_id' => $hid,
							'error' => $e->getMessage(),
						)
					);
				}
			}

			$elapsed = microtime(true) - $start;

			Hesabix_V2_Log_Service::info(
				'Stock pull from Hesabix completed',
				array(
					'entity_type' => 'stock_pull',
					'source' => $source,
					'updated' => $updated,
					'skipped' => $skipped,
					'errors' => $errors,
					'execution_time' => $elapsed,
					'warehouse_scope' => $opts['warehouse_scope'],
				)
			);

			return array(
				'success' => true,
				/* translators: 1: updated count, 2: skipped, 3: errors */
				'message' => sprintf(
					__('موجودی به‌روز شد: %1$d مورد، رد شد %2$d، خطا %3$d', 'hesabix-v2'),
					$updated,
					$skipped,
					$errors
				),
				'updated' => $updated,
				'skipped' => $skipped,
				'errors' => $errors,
				'execution_time' => $elapsed,
			);
		} finally {
			delete_transient(self::LOCK_TRANSIENT);
		}
	}

	/**
	 * @param array<string, mixed> $opts
	 * @return array<int>|null|null به‌صورت null یعنی حذف فیلتر (همه انبارها)؛ WP_Error در خطا
	 */
	private static function resolve_warehouse_ids_for_api($opts)
	{
		$scope = isset($opts['warehouse_scope']) ? $opts['warehouse_scope'] : 'default';

		if ($scope === 'all') {
			return null;
		}

		if ($scope === 'selected') {
			if (empty($opts['warehouse_ids']) || !is_array($opts['warehouse_ids'])) {
				return new WP_Error(
					'hesabix_stock_wh',
					__('برای حالت «انبارهای انتخابی» حداقل یک انبار را مشخص کنید.', 'hesabix-v2')
				);
			}

			return array_map('intval', $opts['warehouse_ids']);
		}

		$def = get_option('hesabix_v2_default_warehouse_id', '');
		$wid = ($def !== '' && $def !== null) ? absint($def) : 0;
		if ($wid < 1) {
			return new WP_Error(
				'hesabix_stock_wh',
				__('انبار پیش‌فرض در تنظیمات فاکتور مشخص نیست.', 'hesabix-v2')
			);
		}

		return array($wid);
	}

	/**
	 * @param Hesabix_V2_Api        $api
	 * @param array<int>            $hesabix_product_ids
	 * @param array<int>|null       $warehouse_ids null = همه انبارها
	 * @return array<int, float>|WP_Error
	 */
	private static function fetch_quantities_for_product_ids($api, $hesabix_product_ids, $warehouse_ids)
	{
		$totals = array();
		$batches = array_chunk($hesabix_product_ids, self::PRODUCT_BATCH);

		foreach ($batches as $batch) {
			if (empty($batch)) {
				continue;
			}

			$skip = 0;
			$take = 500;
			$guard = 0;

			do {
				$body = array(
					'product_ids' => array_map('intval', $batch),
					'track_inventory' => true,
					'include_zero' => true,
					'skip' => $skip,
					'take' => $take,
				);

				if ($warehouse_ids !== null) {
					$body['warehouse_ids'] = array_map('intval', $warehouse_ids);
				}

				$body = apply_filters('hesabix_v2_inventory_stock_report_body', $body, $batch, $warehouse_ids);

				$res = $api->inventory_stock_report($body, 90);

				if (empty($res['success'])) {
					$msg = isset($res['message']) ? (string) $res['message'] : __('خطا در گزارش موجودی حسابیکس', 'hesabix-v2');
					return new WP_Error('hesabix_stock_api', $msg);
				}

				$data = isset($res['data']) && is_array($res['data']) ? $res['data'] : array();
				$items = isset($data['items']) && is_array($data['items']) ? $data['items'] : array();

				foreach ($items as $it) {
					if (!is_array($it)) {
						continue;
					}
					$pid = isset($it['product_id']) ? (int) $it['product_id'] : 0;
					if ($pid < 1) {
						continue;
					}
					$q = isset($it['quantity']) ? (float) $it['quantity'] : 0.0;
					if (!isset($totals[ $pid ])) {
						$totals[ $pid ] = 0.0;
					}
					$totals[ $pid ] += $q;
				}

				$n = count($items);
				$has_next = false;
				if (!empty($data['pagination']) && is_array($data['pagination'])) {
					$has_next = !empty($data['pagination']['has_next']);
				} else {
					$has_next = ($n >= $take);
				}

				$skip += $take;
				$guard++;
			} while ($has_next && $guard < 80);
		}

		return $totals;
	}
}
