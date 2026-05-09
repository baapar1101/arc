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
		if (!array_key_exists('invoice_tag_website_enabled', $sync)) {
			$sync['invoice_tag_website_enabled'] = true;
		}
		if (!isset($sync['invoice_tag_website_name']) || $sync['invoice_tag_website_name'] === '') {
			$sync['invoice_tag_website_name'] = 'فروش سایت';
		}
		if (!isset($sync['invoice_extra_tag_ids'])) {
			$sync['invoice_extra_tag_ids'] = '';
		}
		if (!array_key_exists('sync_category_link_by_name_in_hesabix', $sync)) {
			$sync['sync_category_link_by_name_in_hesabix'] = false;
		}

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
}
