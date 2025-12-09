<?php
/**
 * Data Mapper Class - Convert WooCommerce data to Hesabix V2 API format
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

class Hesabix_V2_Mapper
{
	/**
	 * Convert WooCommerce product to Hesabix API format
	 *
	 * @since    2.0.0
	 * @param    WC_Product    $product
	 * @param    int           $wc_id
	 * @return   array
	 */
	public static function wc_product_to_api($product, $wc_id)
	{
		$name_fa = Hesabix_V2_Validation::sanitize_product_name($product->get_title());
		
		// Get category
		$category_id = null;
		$categories = $product->get_category_ids();
		if (!empty($categories)) {
			$category_id = self::get_or_create_category_mapping($categories[0]);
		}

		// Get price
		$sell_price = 0;
		if ($product->get_regular_price()) {
			$sell_price = Hesabix_V2_Validation::sanitize_price($product->get_regular_price());
		} elseif ($product->get_price()) {
			$sell_price = Hesabix_V2_Validation::sanitize_price($product->get_price());
		}

		return array(
			'name_fa' => $name_fa,
			'name_en' => null,
			'product_type' => 'simple',
			'unit' => 'عدد',
			'sell_price' => $sell_price,
			'buy_price' => null,
			'barcode' => Hesabix_V2_Validation::sanitize_barcode($product->get_sku()),
			'category_id' => $category_id,
			'is_service' => $product->is_virtual(),
			'track_inventory' => $product->managing_stock(),
			'description' => $product->get_description() ? mb_substr($product->get_description(), 0, 500) : null,
			'custom_fields' => array(
				'woocommerce_id' => $wc_id,
				'variation_id' => null,
				'source' => 'woocommerce_plugin_v2',
				'plugin_version' => HESABIX_V2_VERSION,
			),
		);
	}

	/**
	 * Convert WooCommerce product variation to Hesabix API format
	 *
	 * @since    2.0.0
	 * @param    WC_Product              $parent_product
	 * @param    WC_Product_Variation    $variation
	 * @param    int                     $parent_id
	 * @return   array
	 */
	public static function wc_variation_to_api($parent_product, $variation, $parent_id)
	{
		$variation_id = $variation->get_id();
		$parent_name = $parent_product->get_title();
		$variation_name = $variation->get_attribute_summary();

		// Build full name
		$full_name = $parent_name;
		if (!empty($variation_name)) {
			$full_name .= ' - ' . $variation_name;
		}
		$full_name = Hesabix_V2_Validation::sanitize_product_name($full_name);

		// Get category from parent
		$category_id = null;
		$categories = $parent_product->get_category_ids();
		if (!empty($categories)) {
			$category_id = self::get_or_create_category_mapping($categories[0]);
		}

		// Get price
		$sell_price = 0;
		if ($variation->get_regular_price()) {
			$sell_price = Hesabix_V2_Validation::sanitize_price($variation->get_regular_price());
		} elseif ($variation->get_price()) {
			$sell_price = Hesabix_V2_Validation::sanitize_price($variation->get_price());
		}

		return array(
			'name_fa' => $full_name,
			'name_en' => null,
			'product_type' => 'simple',
			'unit' => 'عدد',
			'sell_price' => $sell_price,
			'buy_price' => null,
			'barcode' => Hesabix_V2_Validation::sanitize_barcode($variation->get_sku()),
			'category_id' => $category_id,
			'is_service' => $variation->is_virtual(),
			'track_inventory' => $variation->managing_stock(),
			'custom_fields' => array(
				'woocommerce_id' => $parent_id,
				'variation_id' => $variation_id,
				'source' => 'woocommerce_plugin_v2',
				'plugin_version' => HESABIX_V2_VERSION,
			),
		);
	}

	/**
	 * Convert WooCommerce customer to Hesabix API format
	 *
	 * @since    2.0.0
	 * @param    WC_Customer    $customer
	 * @param    WC_Order       $order     Optional order for additional data
	 * @return   array
	 */
	public static function wc_customer_to_api($customer, $order = null)
	{
		$first_name = $customer->get_first_name();
		$last_name = $customer->get_last_name();

		// Fallback to billing data
		if (empty($first_name) && empty($last_name) && $order) {
			$first_name = $order->get_billing_first_name();
			$last_name = $order->get_billing_last_name();
		}

		// Default names if still empty
		if (empty($first_name) && empty($last_name)) {
			$first_name = 'مشتری';
			$last_name = 'گرامی';
		}

		$data = array(
			'alias_name' => trim($first_name . ' ' . $last_name),
			'first_name' => $first_name ?: 'مشتری',
			'last_name' => $last_name ?: 'گرامی',
			'person_type' => 'customer',
			'mobile_number' => Hesabix_V2_Validation::sanitize_mobile($customer->get_billing_phone()),
			'email' => Hesabix_V2_Validation::sanitize_email($customer->get_email()),
			'custom_fields' => array(
				'woocommerce_id' => $customer->get_id(),
				'source' => 'woocommerce_plugin_v2',
			),
		);

		// Add address data from order if available
		if ($order) {
			$address = $order->get_billing_address_1();
			if ($order->get_billing_address_2()) {
				$address .= ' - ' . $order->get_billing_address_2();
			}

			$data['address'] = Hesabix_V2_Validation::sanitize_address($address);
			$data['city'] = $order->get_billing_city();
			$data['postal_code'] = Hesabix_V2_Validation::sanitize_postal_code($order->get_billing_postcode());

			// Custom checkout fields
			$national_id = $order->get_meta('_billing_hesabix_v2_national_id');
			if ($national_id) {
				$data['national_id'] = Hesabix_V2_Validation::sanitize_national_id($national_id);
			}

			$economic_code = $order->get_meta('_billing_hesabix_v2_economic_code');
			if ($economic_code) {
				$data['economic_code'] = $economic_code;
			}
		}

		// Remove null values
		return array_filter($data, function($value) {
			return $value !== null && $value !== '';
		});
	}

	/**
	 * Convert guest customer from order to Hesabix API format
	 *
	 * @since    2.0.0
	 * @param    WC_Order    $order
	 * @return   array
	 */
	public static function wc_guest_to_api($order)
	{
		$first_name = $order->get_billing_first_name();
		$last_name = $order->get_billing_last_name();

		if (empty($first_name) && empty($last_name)) {
			$first_name = 'مهمان';
			$last_name = 'گرامی';
		}

		$address = $order->get_billing_address_1();
		if ($order->get_billing_address_2()) {
			$address .= ' - ' . $order->get_billing_address_2();
		}

		$data = array(
			'alias_name' => trim($first_name . ' ' . $last_name),
			'first_name' => $first_name ?: 'مهمان',
			'last_name' => $last_name ?: 'گرامی',
			'person_type' => 'customer',
			'mobile_number' => Hesabix_V2_Validation::sanitize_mobile($order->get_billing_phone()),
			'email' => Hesabix_V2_Validation::sanitize_email($order->get_billing_email()),
			'address' => Hesabix_V2_Validation::sanitize_address($address),
			'city' => $order->get_billing_city(),
			'postal_code' => Hesabix_V2_Validation::sanitize_postal_code($order->get_billing_postcode()),
			'custom_fields' => array(
				'woocommerce_id' => 0,
				'guest_order_id' => $order->get_id(),
				'source' => 'woocommerce_plugin_v2',
			),
		);

		// Custom checkout fields
		$national_id = $order->get_meta('_billing_hesabix_v2_national_id');
		if ($national_id) {
			$data['national_id'] = Hesabix_V2_Validation::sanitize_national_id($national_id);
		}

		$economic_code = $order->get_meta('_billing_hesabix_v2_economic_code');
		if ($economic_code) {
			$data['economic_code'] = $economic_code;
		}

		// Remove null values
		return array_filter($data, function($value) {
			return $value !== null && $value !== '';
		});
	}

	/**
	 * Convert WooCommerce order to Hesabix invoice format
	 *
	 * @since    2.0.0
	 * @param    WC_Order    $order
	 * @param    int         $person_id
	 * @return   array
	 */
	public static function wc_order_to_invoice($order, $person_id)
	{
		$lines = array();
		$db_service = new Hesabix_V2_DB_Service();

		// Add order items
		foreach ($order->get_items() as $item) {
			$product = $item->get_product();
			if (!$product) {
				continue;
			}

			$variation_id = $item->get_variation_id();
			$product_id = $variation_id ?: $item->get_product_id();

			// Get Hesabix product ID from mapping
			$hesabix_product_id = $db_service->get_hesabix_id(
				'product',
				$product_id,
				$variation_id ? $item->get_product_id() : null
			);

			// If product not synced, try to sync it now
			if (!$hesabix_product_id) {
				$sync_service = new Hesabix_V2_Sync_Service();
				$sync_result = $sync_service->sync_product($product_id, $variation_id);
				if ($sync_result['success']) {
					$hesabix_product_id = $sync_result['hesabix_id'];
				} else {
					// Skip this item if sync failed
					Hesabix_V2_Log_Service::warning('Product not synced, skipping from invoice', array(
						'wc_product_id' => $product_id,
						'order_id' => $order->get_id(),
					));
					continue;
				}
			}

			$quantity = $item->get_quantity();
			$total = $item->get_total();
			$unit_price = $quantity > 0 ? $total / $quantity : 0;

			$lines[] = array(
				'product_id' => $hesabix_product_id,
				'quantity' => $quantity,
				'unit_price' => Hesabix_V2_Validation::sanitize_price($unit_price),
				'discount' => 0,
				'tax' => Hesabix_V2_Validation::sanitize_price($item->get_total_tax()),
			);
		}

		// Add shipping as a line item if exists
		if ($order->get_shipping_total() > 0) {
			$shipping_product_id = self::get_or_create_shipping_product();
			if ($shipping_product_id) {
				$lines[] = array(
					'product_id' => $shipping_product_id,
					'quantity' => 1,
					'unit_price' => Hesabix_V2_Validation::sanitize_price($order->get_shipping_total()),
					'discount' => 0,
					'tax' => Hesabix_V2_Validation::sanitize_price($order->get_shipping_tax()),
				);
			}
		}

		return array(
			'document_type' => 'sales_invoice',
			'document_date' => $order->get_date_created()->format('Y-m-d'),
			'person_id' => $person_id,
			'lines' => $lines,
			'notes' => sprintf(__('سفارش شماره %s از ووکامرس', 'hesabix-v2'), $order->get_order_number()),
			'custom_fields' => array(
				'woocommerce_order_id' => $order->get_id(),
				'order_number' => $order->get_order_number(),
				'order_status' => $order->get_status(),
				'source' => 'woocommerce_plugin_v2',
			),
		);
	}

	/**
	 * Get or create category mapping
	 *
	 * @since    2.0.0
	 * @param    int    $wc_category_id
	 * @return   int|null
	 */
	private static function get_or_create_category_mapping($wc_category_id)
	{
		$db_service = new Hesabix_V2_DB_Service();
		
		// Check if category already mapped
		$hesabix_id = $db_service->get_hesabix_id('category', $wc_category_id);
		if ($hesabix_id) {
			return $hesabix_id;
		}

		// Get WooCommerce category
		$term = get_term($wc_category_id, 'product_cat');
		if (!$term || is_wp_error($term)) {
			return null;
		}

		// Create category in Hesabix
		$api = new Hesabix_V2_Api();
		$result = $api->create_category(array(
			'name_fa' => $term->name,
			'parent_id' => null, // TODO: Handle parent categories
		));

		if (isset($result['success']) && $result['success']) {
			$hesabix_category_id = $result['data']['id'];
			
			// Save mapping
			$db_service->save_mapping(
				'category',
				$wc_category_id,
				null,
				$hesabix_category_id
			);

			return $hesabix_category_id;
		}

		return null;
	}

	/**
	 * Get or create shipping product in Hesabix
	 *
	 * @since    2.0.0
	 * @return   int|null
	 */
	private static function get_or_create_shipping_product()
	{
		$shipping_product_id = get_option('hesabix_v2_shipping_product_id');
		
		if ($shipping_product_id) {
			return $shipping_product_id;
		}

		// Create shipping product
		$api = new Hesabix_V2_Api();
		$result = $api->create_product(array(
			'name_fa' => 'هزینه حمل و نقل',
			'product_type' => 'simple',
			'unit' => 'عدد',
			'is_service' => true,
			'track_inventory' => false,
			'custom_fields' => array(
				'type' => 'shipping',
				'source' => 'woocommerce_plugin_v2',
			),
		));

		if (isset($result['success']) && $result['success']) {
			$shipping_product_id = $result['data']['id'];
			update_option('hesabix_v2_shipping_product_id', $shipping_product_id);
			return $shipping_product_id;
		}

		return null;
	}
}

