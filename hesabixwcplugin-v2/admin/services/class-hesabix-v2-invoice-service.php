<?php
/**
 * Invoice Service
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Invoice_Service
{
	/**
	 * Get all WooCommerce orders
	 *
	 * @since    2.0.0
	 * @param    array    $args
	 * @return   array
	 */
	public static function get_all_orders($args = array())
	{
		$default_args = array(
			'limit' => -1,
			'return' => 'ids',
		);

		$args = array_merge($default_args, $args);
		
		return wc_get_orders($args);
	}

	/**
	 * Get sync status for order
	 *
	 * @since    2.0.0
	 * @param    int    $order_id
	 * @return   array|null
	 */
	public static function get_sync_status($order_id)
	{
		$db = new Hesabix_V2_DB_Service();
		return $db->get_mapping('order', $order_id);
	}

	/**
	 * Get orders by status
	 *
	 * @since    2.0.0
	 * @param    string|array    $status
	 * @return   array
	 */
	public static function get_orders_by_status($status)
	{
		return wc_get_orders(array(
			'status' => $status,
			'limit' => -1,
			'return' => 'ids',
		));
	}
}

