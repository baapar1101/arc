<?php
/**
 * سیاست یکپارچهٔ موجودی: منبع حقیقت، قفل‌ها و گزینه‌های همگام‌سازی عددی.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Inventory_Policy
{
	const OPTION_KEY = 'hesabix_v2_inventory_policy';

	const SOURCE_HESABIX = 'hesabix';
	const SOURCE_WOOCOMMERCE = 'woocommerce';
	const SOURCE_MANUAL = 'manual';

	/**
	 * @return array<string, mixed>
	 */
	public static function defaults()
	{
		return array(
			'source_of_truth' => self::SOURCE_HESABIX,
			'push_wc_qty_to_hesabix' => false,
			'accept_remote_stock_push' => true,
			'conflict_sample_limit' => 25,
		);
	}

	/**
	 * @return array<string, mixed>
	 */
	public static function get_options()
	{
		$raw = get_option(self::OPTION_KEY, array());
		if (!is_array($raw)) {
			$raw = array();
		}
		$o = wp_parse_args($raw, self::defaults());

		$src = isset($o['source_of_truth']) ? sanitize_key((string) $o['source_of_truth']) : self::SOURCE_HESABIX;
		if (!in_array($src, array(self::SOURCE_HESABIX, self::SOURCE_WOOCOMMERCE, self::SOURCE_MANUAL), true)) {
			$src = self::SOURCE_HESABIX;
		}
		$o['source_of_truth'] = $src;
		$o['push_wc_qty_to_hesabix'] = !empty($o['push_wc_qty_to_hesabix']);
		$o['accept_remote_stock_push'] = !isset($o['accept_remote_stock_push']) || !empty($o['accept_remote_stock_push']);
		$o['conflict_sample_limit'] = max(5, min(100, absint($o['conflict_sample_limit'])));

		return $o;
	}

	/**
	 * @param array<string, mixed> $incoming
	 * @return array<string, mixed>
	 */
	public static function sanitize_and_save(array $incoming)
	{
		$cur = self::get_options();
		$src = isset($incoming['source_of_truth']) ? sanitize_key((string) $incoming['source_of_truth']) : $cur['source_of_truth'];
		if (!in_array($src, array(self::SOURCE_HESABIX, self::SOURCE_WOOCOMMERCE, self::SOURCE_MANUAL), true)) {
			$src = self::SOURCE_HESABIX;
		}

		$out = array(
			'source_of_truth' => $src,
			'push_wc_qty_to_hesabix' => !empty($incoming['push_wc_qty_to_hesabix']),
			'accept_remote_stock_push' => !empty($incoming['accept_remote_stock_push']),
			'conflict_sample_limit' => isset($incoming['conflict_sample_limit'])
				? max(5, min(100, absint($incoming['conflict_sample_limit'])))
				: (int) $cur['conflict_sample_limit'],
		);

		update_option(self::OPTION_KEY, $out);
		return $out;
	}

	/**
	 * آیا باید عدد موجودی ووکامرس را به حسابیکس (حواله تعدیل) بفرستیم؟
	 *
	 * @return bool
	 */
	public static function should_push_wc_qty_to_hesabix()
	{
		$o = self::get_options();
		if ($o['source_of_truth'] !== self::SOURCE_WOOCOMMERCE) {
			return false;
		}
		if (empty($o['push_wc_qty_to_hesabix'])) {
			return false;
		}
		// پس از موجودی افتتاحیه، منبع حقیقت نباید ووکامرس بماند مگر صریحاً انتخاب شده باشد.
		return true;
	}

	/**
	 * آیا کشش/پوش از حسابیکس به ووکامرس مجاز است؟
	 *
	 * @return bool
	 */
	public static function should_apply_hesabix_qty_to_wc()
	{
		$o = self::get_options();
		return $o['source_of_truth'] === self::SOURCE_HESABIX;
	}

	/**
	 * آیا فراخوان از راه دور (پل حسابیکس) برای کشش موجودی پذیرفته می‌شود؟
	 *
	 * @return bool
	 */
	public static function accept_remote_stock_push()
	{
		$o = self::get_options();
		if ($o['source_of_truth'] !== self::SOURCE_HESABIX) {
			return false;
		}
		return !empty($o['accept_remote_stock_push']);
	}

	/**
	 * آیا موجودی افتتاحیه تکمیل شده و ممکن است با پوش عددی از WC تداخل داشته باشد؟
	 *
	 * @return bool
	 */
	public static function opening_inventory_completed()
	{
		return (bool) get_option('hesabix_v2_opening_inventory_completed');
	}

	/**
	 * خلاصه وضعیت برای UI / پل.
	 *
	 * @return array<string, mixed>
	 */
	public static function status_summary()
	{
		$o = self::get_options();
		$pull = Hesabix_V2_Stock_Pull_Service::get_options();
		$last = get_option('hesabix_v2_stock_pull_last', array());
		if (!is_array($last)) {
			$last = array();
		}

		$warnings = array();
		if ($o['source_of_truth'] === self::SOURCE_HESABIX && empty($pull['enabled'])) {
			$warnings[] = 'stock_pull_cron_disabled';
		}
		if ($o['source_of_truth'] === self::SOURCE_HESABIX && empty($pull['disable_wc_stock_reduction'])) {
			$warnings[] = 'wc_stock_reduction_still_active';
		}
		if ($o['source_of_truth'] === self::SOURCE_WOOCOMMERCE && self::opening_inventory_completed() && !empty($o['push_wc_qty_to_hesabix'])) {
			$warnings[] = 'opening_inventory_done_with_wc_push';
		}
		if ($o['source_of_truth'] === self::SOURCE_WOOCOMMERCE && !empty($pull['enabled'])) {
			$warnings[] = 'pull_enabled_while_wc_is_source';
		}
		if ($o['source_of_truth'] === self::SOURCE_MANUAL) {
			$warnings[] = 'manual_mode_no_auto_qty';
		}

		return array(
			'source_of_truth' => $o['source_of_truth'],
			'push_wc_qty_to_hesabix' => self::should_push_wc_qty_to_hesabix(),
			'push_wc_qty_requested' => !empty($o['push_wc_qty_to_hesabix']),
			'accept_remote_stock_push' => self::accept_remote_stock_push(),
			'apply_hesabix_qty_to_wc' => self::should_apply_hesabix_qty_to_wc(),
			'opening_inventory_completed' => self::opening_inventory_completed(),
			'stock_pull' => $pull,
			'last_stock_pull' => $last,
			'warnings' => $warnings,
			'recommended' => self::recommended_checklist($o, $pull),
		);
	}

	/**
	 * @param array<string, mixed> $o
	 * @param array<string, mixed> $pull
	 * @return array<string, bool>
	 */
	private static function recommended_checklist(array $o, array $pull)
	{
		if ($o['source_of_truth'] === self::SOURCE_HESABIX) {
			return array(
				'enable_stock_pull_cron' => !empty($pull['enabled']),
				'disable_wc_stock_reduction' => !empty($pull['disable_wc_stock_reduction']),
				'default_warehouse_set' => absint(get_option('hesabix_v2_default_warehouse_id', 0)) > 0,
				'accept_remote_push' => !empty($o['accept_remote_stock_push']),
			);
		}
		if ($o['source_of_truth'] === self::SOURCE_WOOCOMMERCE) {
			return array(
				'enable_wc_qty_push' => !empty($o['push_wc_qty_to_hesabix']),
				'disable_stock_pull_cron' => empty($pull['enabled']),
				'default_warehouse_set' => absint(get_option('hesabix_v2_default_warehouse_id', 0)) > 0,
			);
		}
		return array(
			'use_opening_inventory_once' => self::opening_inventory_completed(),
			'default_warehouse_set' => absint(get_option('hesabix_v2_default_warehouse_id', 0)) > 0,
		);
	}
}
