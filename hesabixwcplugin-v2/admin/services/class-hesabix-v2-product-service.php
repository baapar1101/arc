<?php
/**
 * Product Service
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Product_Service
{
	/**
	 * Get all WooCommerce products
	 *
	 * @since    2.0.0
	 * @param    array    $args
	 * @return   array
	 */
	public static function get_all_products($args = array())
	{
		$default_args = array(
			'status' => 'publish',
			'limit' => -1,
			'return' => 'ids',
		);

		$args = array_merge($default_args, $args);
		
		return wc_get_products($args);
	}

	/**
	 * Get product variations
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 * @return   array
	 */
	public static function get_variations($product_id)
	{
		$product = wc_get_product($product_id);

		if (!$product || !$product->is_type('variable')) {
			return array();
		}

		return $product->get_children();
	}

	/**
	 * Get sync status for product
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 * @param    int    $variation_id
	 * @return   array|null
	 */
	public static function get_sync_status($product_id, $variation_id = null)
	{
		$db = new Hesabix_V2_DB_Service();
		$wc_id = $variation_id ?: $product_id;
		$wc_parent_id = $variation_id ? $product_id : null;

		return $db->get_mapping('product', $wc_id, $wc_parent_id);
	}
}

