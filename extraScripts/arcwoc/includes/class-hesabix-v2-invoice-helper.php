<?php
/**
 * Invoice options & tag resolution for WooCommerce → Hesabix sync.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Invoice_Helper
{
	/**
	 * Merge legacy keys and defaults into sync settings.
	 *
	 * @param array $sync Raw option value.
	 * @return array
	 */
	public static function normalize_sync_settings($sync)
	{
		if (!is_array($sync)) {
			$sync = array();
		}

		if (!array_key_exists('sync_order_on_checkout', $sync)) {
			$sync['sync_order_on_checkout'] = true;
		}
		if (!array_key_exists('sync_order_on_payment_complete', $sync)) {
			$sync['sync_order_on_payment_complete'] = false;
		}
		if (!isset($sync['sync_order_on_statuses']) || !is_array($sync['sync_order_on_statuses'])) {
			$sync['sync_order_on_statuses'] = array('processing', 'completed');
		}
		if (!array_key_exists('invoice_is_proforma', $sync)) {
			$sync['invoice_is_proforma'] = false;
		}
		if (!array_key_exists('finalize_proforma_on_paid', $sync)) {
			$sync['finalize_proforma_on_paid'] = true;
		}
		if (!isset($sync['finalize_proforma_order_statuses']) || !is_array($sync['finalize_proforma_order_statuses'])) {
			$sync['finalize_proforma_order_statuses'] = array('processing', 'completed');
		}
		$sync['finalize_proforma_on_paid'] = (bool) $sync['finalize_proforma_on_paid'];
		$fp_st = array();
		foreach ($sync['finalize_proforma_order_statuses'] as $st) {
			if (!is_string($st) && !is_numeric($st)) {
				continue;
			}
			$s = sanitize_key(str_replace('wc-', '', (string) $st));
			if ($s !== '') {
				$fp_st[] = $s;
			}
		}
		$sync['finalize_proforma_order_statuses'] = array_values(array_unique($fp_st));
		if (!array_key_exists('invoice_tag_website_enabled', $sync)) {
			$sync['invoice_tag_website_enabled'] = true;
		}
		if (!isset($sync['invoice_tag_website_name']) || $sync['invoice_tag_website_name'] === '') {
			$sync['invoice_tag_website_name'] = 'فروش سایت';
		}
		if (!isset($sync['invoice_extra_tag_ids'])) {
			$sync['invoice_extra_tag_ids'] = '';
		}
		if (!isset($sync['shipping_line_mode']) || !is_string($sync['shipping_line_mode'])) {
			$sync['shipping_line_mode'] = 'service';
		} else {
			$sync['shipping_line_mode'] = sanitize_key($sync['shipping_line_mode']);
		}
		if (!in_array($sync['shipping_line_mode'], array('service', 'account_adjustment'), true)) {
			$sync['shipping_line_mode'] = 'service';
		}
		$sync['shipping_adjustment_account_id'] = isset($sync['shipping_adjustment_account_id'])
			? absint($sync['shipping_adjustment_account_id'])
			: 0;
		if (!array_key_exists('sync_category_link_by_name_in_hesabix', $sync)) {
			$sync['sync_category_link_by_name_in_hesabix'] = false;
		}
		if (!isset($sync['track_inventory_policy']) || !is_string($sync['track_inventory_policy'])) {
			$sync['track_inventory_policy'] = 'wc';
		} else {
			$sync['track_inventory_policy'] = sanitize_key($sync['track_inventory_policy']);
		}
		$allowed_policies = array('wc', 'physical_always', 'always_on', 'always_off');
		if (!in_array($sync['track_inventory_policy'], $allowed_policies, true)) {
			$sync['track_inventory_policy'] = 'wc';
		}

		if (!isset($sync['order_fiscal_year_date_policy']) || !is_string($sync['order_fiscal_year_date_policy'])) {
			$sync['order_fiscal_year_date_policy'] = 'keep';
		} else {
			$sync['order_fiscal_year_date_policy'] = sanitize_key($sync['order_fiscal_year_date_policy']);
		}
		$allowed_fiscal = array('keep', 'clamp', 'skip');
		if (!in_array($sync['order_fiscal_year_date_policy'], $allowed_fiscal, true)) {
			$sync['order_fiscal_year_date_policy'] = 'keep';
		}

		if (!array_key_exists('queue_items_per_cron_run', $sync)) {
			$sync['queue_items_per_cron_run'] = 15;
		}
		$sync['queue_items_per_cron_run'] = max(1, min(500, absint($sync['queue_items_per_cron_run'])));

		return $sync;
	}

	/**
	 * Parse extra tag IDs from comma-separated setting.
	 *
	 * @param string $raw
	 * @return int[]
	 */
	public static function parse_extra_tag_ids($raw)
	{
		$out = array();
		if (!is_string($raw) || $raw === '') {
			return $out;
		}
		foreach (explode(',', $raw) as $p) {
			$p = trim($p);
			if ($p !== '' && ctype_digit($p)) {
				$out[] = (int) $p;
			}
		}
		return $out;
	}

	/**
	 * Resolve Hesabix document tag IDs for invoice payload (website tag + manual IDs).
	 *
	 * @return int[]
	 */
	public static function resolve_invoice_tag_ids()
	{
		$sync = self::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		$ids = self::parse_extra_tag_ids(isset($sync['invoice_extra_tag_ids']) ? $sync['invoice_extra_tag_ids'] : '');

		if (!empty($sync['invoice_tag_website_enabled'])) {
			$name = isset($sync['invoice_tag_website_name']) ? trim((string) $sync['invoice_tag_website_name']) : '';
			if ($name !== '') {
				$tid = self::ensure_invoice_tag_id_by_name($name);
				if ($tid) {
					$ids[] = $tid;
				}
			}
		}

		$ids = array_values(array_unique(array_filter(array_map('intval', $ids))));
		return $ids;
	}

	/**
	 * Find tag by exact name or create it via API.
	 *
	 * @param string $name
	 * @return int|null
	 */
	public static function ensure_invoice_tag_id_by_name($name)
	{
		$name = trim((string) $name);
		if ($name === '') {
			return null;
		}

		$cache_key = 'hesabix_v2_itag_' . md5($name);
		$cached = get_transient($cache_key);
		if ($cached !== false && $cached !== '') {
			return (int) $cached;
		}

		$api = new Hesabix_V2_Api();
		$list = $api->list_invoice_tags(false);
		if (!empty($list['success']) && isset($list['data']['items']) && is_array($list['data']['items'])) {
			foreach ($list['data']['items'] as $it) {
				if (!isset($it['name'])) {
					continue;
				}
				if (trim((string) $it['name']) === $name && isset($it['id'])) {
					$id = (int) $it['id'];
					if ($id > 0) {
						set_transient($cache_key, $id, 12 * HOUR_IN_SECONDS);
						return $id;
					}
				}
			}
		}

		$create = $api->create_invoice_tag($name, null);
		if (!empty($create['success']) && isset($create['data']['item']['id'])) {
			$id = (int) $create['data']['item']['id'];
			if ($id > 0) {
				set_transient($cache_key, $id, 12 * HOUR_IN_SECONDS);
				return $id;
			}
		}

		return null;
	}

	/**
	 * Registered WooCommerce order statuses (slug => label).
	 *
	 * @return array<string,string>
	 */
	public static function get_wc_order_status_choices()
	{
		if (!function_exists('wc_get_order_statuses')) {
			return array();
		}
		$statuses = wc_get_order_statuses();
		$out = array();
		foreach ($statuses as $key => $label) {
			$slug = str_replace('wc-', '', (string) $key);
			$out[$slug] = $label;
		}
		return $out;
	}

	/**
	 * نرمال‌سازی اسلاگ وضعیت سفارش ووکامرس (بدون پیشوند wc-).
	 *
	 * @param string $status
	 * @return string
	 */
	public static function normalize_order_status_slug($status)
	{
		$s = is_string($status) ? strtolower(trim(str_replace('wc-', '', $status))) : '';
		if ($s === '') {
			return '';
		}
		return sanitize_key($s);
	}

	/**
	 * آیا با توجه به وضعیت/پرداخت سفارش، فاکتور ارسالی به حسابیکس باید قطعی باشد؟
	 * وقتی invoice_is_proforma خاموش است، همیشه true (یعنی همیشه قطعی).
	 *
	 * @param WC_Order $order
	 * @param array|null $sync نتیجه normalize_sync_settings یا null برای خواندن از option.
	 * @return bool
	 */
	public static function order_invoice_should_be_final($order, $sync = null)
	{
		if (!is_object($order) || !($order instanceof WC_Order)) {
			return true;
		}
		if ($sync === null) {
			$sync = self::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		} else {
			$sync = self::normalize_sync_settings($sync);
		}
		if (empty($sync['invoice_is_proforma'])) {
			return true;
		}
		if (!empty($sync['finalize_proforma_on_paid']) && $order->is_paid()) {
			return true;
		}
		$cur = self::normalize_order_status_slug($order->get_status());
		foreach ($sync['finalize_proforma_order_statuses'] as $allowed) {
			if ($cur !== '' && $cur === self::normalize_order_status_slug($allowed)) {
				return true;
			}
		}
		return false;
	}
}
