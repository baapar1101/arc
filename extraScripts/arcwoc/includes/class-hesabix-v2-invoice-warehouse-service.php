<?php
/**
 * تعیین انبار خط فاکتور حسابیکس از روی سفارش ووکامرس (روش حمل، سپس منطقه ارسال، سپس پیش‌فرض).
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Invoice_Warehouse_Service
{
	const OPTION_KEY = 'hesabix_v2_invoice_warehouse_rules';

	/**
	 * @return array{resolution:string, rules:array<int, array{type:string,key:string,warehouse_id:int}>}
	 */
	public static function get_config()
	{
		$raw = get_option(self::OPTION_KEY, array());
		if (!is_array($raw)) {
			$raw = array();
		}
		$resolution = isset($raw['resolution']) ? sanitize_key((string) $raw['resolution']) : 'default';
		if (!in_array($resolution, array('default', 'rules'), true)) {
			$resolution = 'default';
		}

		$rules = isset($raw['rules']) && is_array($raw['rules']) ? $raw['rules'] : array();
		$clean = array();
		foreach ($rules as $row) {
			if (!is_array($row)) {
				continue;
			}
			$type = isset($row['type']) ? sanitize_key((string) $row['type']) : '';
			if ($type !== 'shipping_method' && $type !== 'shipping_zone') {
				continue;
			}
			$key = isset($row['key']) ? trim(wp_unslash((string) $row['key'])) : '';
			if ($key === '') {
				continue;
			}
			$wid = isset($row['warehouse_id']) ? absint($row['warehouse_id']) : 0;
			if ($wid < 1) {
				continue;
			}

			if ($type === 'shipping_zone') {
				$key = (string) (int) $key;
			} else {
				$key = self::normalize_shipping_method_key($key);
			}

			$clean[] = array(
				'type' => $type,
				'key' => $key,
				'warehouse_id' => $wid,
			);
		}

		return array(
			'resolution' => $resolution,
			'rules' => $clean,
		);
	}

	/**
	 * مانند flat_rate:12 (حروف کوچک روی شناسه روش برای سازگاری).
	 *
	 * @param string $key
	 * @return string
	 */
	public static function normalize_shipping_method_key($key)
	{
		$key = trim(wp_unslash((string) $key));
		if ($key === '') {
			return '';
		}
		$p = strpos($key, ':');
		if ($p === false) {
			return strtolower($key);
		}
		$mid = strtolower(trim(substr($key, 0, $p)));
		$inst = preg_replace('/[^0-9]/', '', substr($key, $p + 1));

		return $mid . ':' . $inst;
	}

	/**
	 * شناسه انبار حسابیکس برای تمام خطوط یک فاکتور فروش.
	 *
	 * @param WC_Order $order
	 * @return int|null بدون تنظیم پیش‌فرض معتبر = null تا خط بدون warehouse_id بمانَد
	 */
	public static function resolve_warehouse_id_for_order($order)
	{
		$fallback = self::fallback_default_warehouse_id();
		$resolved = ($fallback > 0) ? $fallback : null;
		/** @var WC_Order|null $wc_order */
		$wc_order = (is_object($order) && $order instanceof WC_Order) ? $order : null;

		if (!$wc_order) {
			return apply_filters('hesabix_v2_resolved_invoice_warehouse_id', $resolved, null);
		}

		$config = self::get_config();
		if ($config['resolution'] !== 'rules' || empty($config['rules'])) {
			return apply_filters('hesabix_v2_resolved_invoice_warehouse_id', $resolved, $wc_order);
		}

		$method_keys = self::shipping_method_keys_from_order($wc_order);
		$zone_id = self::matching_shipping_zone_id($wc_order);

		foreach ($config['rules'] as $rule) {
			if ($rule['type'] === 'shipping_method' && self::matches_shipping_rule($rule['key'], $method_keys)) {
				$resolved = (int) $rule['warehouse_id'];
				return apply_filters('hesabix_v2_resolved_invoice_warehouse_id', $resolved, $wc_order);
			}
			if ($rule['type'] === 'shipping_zone' && $zone_id !== null && $rule['key'] === (string) (int) $zone_id) {
				$resolved = (int) $rule['warehouse_id'];
				return apply_filters('hesabix_v2_resolved_invoice_warehouse_id', $resolved, $wc_order);
			}
		}

		$resolved = ($fallback > 0) ? $fallback : null;

		return apply_filters('hesabix_v2_resolved_invoice_warehouse_id', $resolved, $wc_order);
	}

	/**
	 * @return array<int, string>
	 */
	private static function shipping_method_keys_from_order($order)
	{
		$keys = array();
		foreach ($order->get_items('shipping') as $ship_item) {
			if (!$ship_item instanceof WC_Order_Item_Shipping) {
				continue;
			}
			$mid = sanitize_title((string) $ship_item->get_method_id());
			$iid = (string) preg_replace('/[^0-9]/', '', (string) $ship_item->get_instance_id());
			if ($mid === '') {
				continue;
			}
			$keys[] = $mid . ':' . $iid;
		}

		return array_unique($keys);
	}

	/**
	 * @param array<int, string> $method_keys
	 */
	private static function matches_shipping_rule($rule_key, array $method_keys)
	{
		$needle = self::normalize_shipping_method_key($rule_key);
		if ($needle === '') {
			return false;
		}

		foreach ($method_keys as $hay) {
			if ($needle === self::normalize_shipping_method_key($hay)) {
				return true;
			}
			if ($needle === $hay) {
				return true;
			}
		}

		return false;
	}

	/**
	 * @param WC_Order $order
	 * @return int|null
	 */
	private static function matching_shipping_zone_id($order)
	{
		if (!class_exists('WC_Shipping_Zones')) {
			return null;
		}

		$c = function ($s) {
			return (string) wc_strtoupper(trim((string) $s));
		};

		$country = $c($order->get_shipping_country());
		if ($country === '') {
			$country = $c($order->get_billing_country());
		}
		$state = (string) $order->get_shipping_state();
		if ($state === '') {
			$state = (string) $order->get_billing_state();
		}
		$postcode = (string) $order->get_shipping_postcode();
		if ($postcode === '') {
			$postcode = (string) $order->get_billing_postcode();
		}
		$city = (string) $order->get_shipping_city();
		if ($city === '') {
			$city = (string) $order->get_billing_city();
		}

		$package = array(
			'contents' => array(),
			'contents_cost' => 0,
			'applied_coupons' => array(),
			'user' => array('ID' => (int) $order->get_user_id()),
			'destination' => array(
				'country' => $country,
				'state' => $state,
				'postcode' => $postcode,
				'city' => $city,
				'address' => (string) $order->get_shipping_address_1(),
				'address_2' => (string) $order->get_shipping_address_2(),
			),
		);

		$package = apply_filters('hesabix_v2_invoice_warehouse_zone_package', $package, $order);

		try {
			$zone_obj = WC_Shipping_Zones::get_zone_matching_package($package);
		} catch (Exception $e) {
			return null;
		}

		if (!$zone_obj) {
			return null;
		}

		return (int) $zone_obj->get_id();
	}

	/**
	 * @return int
	 */
	private static function fallback_default_warehouse_id()
	{
		$w = get_option('hesabix_v2_default_warehouse_id', '');

		return ($w !== '' && $w !== null) ? absint($w) : 0;
	}
}
