<?php
/**
 * کنترل کاهش موجودی ووکامرس هنگام ثبت سفارش (در حالت مرجع‌بودن حسابیکس برای موجودی).
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Order_Stock_Control
{
	/**
	 * پس از بارگذاری WooCommerce.
	 */
	public static function boot()
	{
		if (!function_exists('WC') || !get_option('hesabix_v2_enabled')) {
			return;
		}

		$opts = Hesabix_V2_Stock_Pull_Service::get_options();
		if (empty($opts['disable_wc_stock_reduction'])) {
			return;
		}

		add_filter('woocommerce_can_reduce_order_stock', array(__CLASS__, 'filter_can_reduce_order_stock'), 20, 2);
	}

	/**
	 * @param bool|mixed    $maybe_allowed پیش‌فرض true در ووکامرس جدید
	 * @param WC_Order|null $order
	 * @return bool
	 */
	public static function filter_can_reduce_order_stock($maybe_allowed = true, $order = null)
	{
		list($allowed, $ord) = self::unpack_reduce_filter_args(func_get_args());

		if (!apply_filters('hesabix_v2_disable_wc_stock_reduction_active', Hesabix_V2_Stock_Pull_Service::get_options()['disable_wc_stock_reduction'] ?? false)) {
			return $allowed;
		}

		if ($ord instanceof WC_Order && apply_filters('hesabix_v2_force_allow_wc_reduce_stock', false, $ord)) {
			return $allowed;
		}

		return false;
	}

	/**
	 * امضاهای رایج: (bool, WC_Order) یا (WC_Order,) در سبک‌های قدیمی‌تر.
	 *
	 * @param array<int, mixed> $args
	 * @return array{0:bool, 1:?WC_Order}
	 */
	private static function unpack_reduce_filter_args(array $args)
	{
		$allowed = true;
		$order = null;

		if (isset($args[1]) && $args[1] instanceof WC_Order) {
			$order = $args[1];
			$allowed = isset($args[0]) ? (bool) $args[0] : true;
		} elseif (isset($args[0])) {
			if ($args[0] instanceof WC_Order) {
				$order = $args[0];
				$allowed = true;
			} elseif (is_bool($args[0])) {
				$allowed = $args[0];
			}
		}

		return array($allowed, $order instanceof WC_Order ? $order : null);
	}
}
