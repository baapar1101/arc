<?php
/**
 * Customer Service
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Customer_Service
{
	/**
	 * Get all WooCommerce customers
	 *
	 * @since    2.0.0
	 * @param    array    $args
	 * @return   array
	 */
	public static function get_all_customers($args = array())
	{
		$default_args = array(
			'role' => 'customer',
			'fields' => 'ID',
			'number' => -1,
		);

		$args = array_merge($default_args, $args);
		
		return get_users($args);
	}

	/**
	 * Get sync status for customer
	 *
	 * @since    2.0.0
	 * @param    int    $customer_id
	 * @return   array|null
	 */
	public static function get_sync_status($customer_id)
	{
		$db = new Hesabix_V2_DB_Service();
		return $db->get_mapping('customer', $customer_id);
	}
}

