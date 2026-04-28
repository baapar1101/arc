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
			'name' => $name_fa,
			'item_type' => $product->is_virtual() ? 'خدمت' : 'کالا',
			'main_unit' => 'عدد',
			'base_sales_price' => $sell_price,
			'base_purchase_price' => null,
			'barcode' => Hesabix_V2_Validation::sanitize_barcode($product->get_sku()),
			'category_id' => $category_id,
			'track_inventory' => $product->managing_stock(),
			'description' => $product->get_description() ? mb_substr($product->get_description(), 0, 500) : null,
			'is_active' => true,
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
			'name' => $full_name,
			'item_type' => $variation->is_virtual() ? 'خدمت' : 'کالا',
			'main_unit' => 'عدد',
			'base_sales_price' => $sell_price,
			'base_purchase_price' => null,
			'barcode' => Hesabix_V2_Validation::sanitize_barcode($variation->get_sku()),
			'category_id' => $category_id,
			'track_inventory' => $variation->managing_stock(),
			'is_active' => true,
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
		$customer_id = $customer->get_id();
		$first_name = $customer->get_first_name();
		$last_name = $customer->get_last_name();

		// Fallback: از سفارش (اطلاعات صورتحساب)
		if (empty($first_name) && empty($last_name) && $order) {
			$first_name = $order->get_billing_first_name();
			$last_name = $order->get_billing_last_name();
		}

		// Fallback: متای کاربر وردپرس / ووکامرس (بilling یا نام پروفایل)
		if (empty($first_name) && empty($last_name) && $customer_id) {
			$first_name = get_user_meta($customer_id, 'billing_first_name', true)
				?: get_user_meta($customer_id, 'first_name', true);
			$last_name = get_user_meta($customer_id, 'billing_last_name', true)
				?: get_user_meta($customer_id, 'last_name', true);
		}

		// Fallback: نام نمایشی کاربر (مثلاً "علی محمدی")
		if (empty($first_name) && empty($last_name) && $customer_id) {
			$user = get_userdata($customer_id);
			if ($user && !empty($user->display_name)) {
				$parts = preg_split('/\s+/u', trim($user->display_name), 2);
				$first_name = $parts[0] ?? '';
				$last_name = $parts[1] ?? '';
			}
		}

		// فقط در صورت خالی ماندن هر دو: مقدار پیش‌فرض
		if (empty($first_name) && empty($last_name)) {
			$first_name = 'مشتری';
			$last_name = 'گرامی';
		}

		$data = array(
			'alias_name' => trim($first_name . ' ' . $last_name),
			'first_name' => $first_name ?: 'مشتری',
			'last_name' => $last_name ?: 'گرامی',
			'person_type' => 'مشتری',
			'mobile' => Hesabix_V2_Validation::sanitize_mobile($customer->get_billing_phone()),
			'email' => Hesabix_V2_Validation::sanitize_email($customer->get_email()),
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

			$national_id = $order->get_meta('_billing_hesabix_v2_national_id');
			if ($national_id) {
				$data['national_id'] = Hesabix_V2_Validation::sanitize_national_id($national_id);
			}

			$economic_code = $order->get_meta('_billing_hesabix_v2_economic_code');
			if ($economic_code) {
				$data['economic_id'] = $economic_code;
			}
		}

		// اگر هر دو موبایل و ایمیل خالی باشند، API اغلب 422 برمی‌گرداند؛ یک مقدار placeholder بگذار
		if (empty($data['mobile']) && empty($data['email'])) {
			$data['email'] = 'wc-' . $customer->get_id() . '@woocommerce-placeholder.local';
		}
		if (!empty($data['mobile']) && preg_match('/^0+$/', $data['mobile'])) {
			$data['mobile'] = '09100000000';
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

		$mobile = Hesabix_V2_Validation::sanitize_mobile($order->get_billing_phone());
		$email = Hesabix_V2_Validation::sanitize_email($order->get_billing_email());
		if (empty($mobile) && empty($email)) {
			$email = 'guest-' . $order->get_id() . '@woocommerce-placeholder.local';
		}
		if (!empty($mobile) && preg_match('/^0+$/', $mobile)) {
			$mobile = '09100000000';
		}

		$data = array(
			'alias_name' => trim($first_name . ' ' . $last_name),
			'first_name' => $first_name ?: 'مهمان',
			'last_name' => $last_name ?: 'گرامی',
			'person_type' => 'مشتری',
			'mobile' => $mobile,
			'email' => $email,
			'address' => Hesabix_V2_Validation::sanitize_address($address),
			'city' => $order->get_billing_city(),
			'postal_code' => Hesabix_V2_Validation::sanitize_postal_code($order->get_billing_postcode()),
		);

		$national_id = $order->get_meta('_billing_hesabix_v2_national_id');
		if ($national_id) {
			$data['national_id'] = Hesabix_V2_Validation::sanitize_national_id($national_id);
		}

		$economic_code = $order->get_meta('_billing_hesabix_v2_economic_code');
		if ($economic_code) {
			$data['economic_id'] = $economic_code;
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
		$warehouse_id = get_option('hesabix_v2_default_warehouse_id', null);

		// Add order items (فرمت API حسابیکس: lines[].product_id, quantity, extra_info)
		foreach ($order->get_items() as $item) {
			$product = $item->get_product();
			if (!$product) {
				continue;
			}

			$variation_id = $item->get_variation_id();
			$product_id = $variation_id ?: $item->get_product_id();

			$hesabix_product_id = $db_service->get_hesabix_id(
				'product',
				$product_id,
				$variation_id ? $item->get_product_id() : null
			);

			if (!$hesabix_product_id) {
				$sync_service = new Hesabix_V2_Sync_Service();
				$sync_result = $sync_service->sync_product($product_id, $variation_id);
				if ($sync_result['success']) {
					$hesabix_product_id = $sync_result['hesabix_id'];
				} else {
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
			$tax_amount = Hesabix_V2_Validation::sanitize_price($item->get_total_tax());
			$line_total = Hesabix_V2_Validation::sanitize_price($total) + $tax_amount;

			$line_extra = array(
				'unit_price' => Hesabix_V2_Validation::sanitize_price($unit_price),
				'line_discount' => 0,
				'tax_amount' => $tax_amount,
				'line_total' => $line_total,
				'unit' => 'عدد',
				'unit_price_source' => 'base',
				'discount_type' => 'amount',
				'discount_value' => 0,
				'tax_rate' => 0,
				'movement' => 'out',
			);
			if ($warehouse_id !== null && $warehouse_id !== '') {
				$line_extra['warehouse_id'] = (int) $warehouse_id;
			}

			$lines[] = array(
				'product_id' => $hesabix_product_id,
				'quantity' => $quantity,
				'extra_info' => $line_extra,
			);
		}

		// هزینه حمل و نقل
		if ($order->get_shipping_total() > 0) {
			$shipping_product_id = self::get_or_create_shipping_product();
			if ($shipping_product_id) {
				$ship_total = Hesabix_V2_Validation::sanitize_price($order->get_shipping_total());
				$ship_tax = Hesabix_V2_Validation::sanitize_price($order->get_shipping_tax());
				$line_extra = array(
					'unit_price' => $ship_total,
					'line_discount' => 0,
					'tax_amount' => $ship_tax,
					'line_total' => $ship_total + $ship_tax,
					'unit' => 'عدد',
					'unit_price_source' => 'base',
					'discount_type' => 'amount',
					'discount_value' => 0,
					'tax_rate' => 0,
					'movement' => 'out',
				);
				if ($warehouse_id !== null && $warehouse_id !== '') {
					$line_extra['warehouse_id'] = (int) $warehouse_id;
				}
				$lines[] = array(
					'product_id' => $shipping_product_id,
					'quantity' => 1,
					'extra_info' => $line_extra,
				);
			}
		}

		$order_total = (float) $order->get_total();
		$order_tax = (float) $order->get_total_tax();
		$order_discount = (float) $order->get_discount_total();
		$gross = $order_total + $order_discount - $order_tax;

		$sync = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		$is_proforma = !empty($sync['invoice_is_proforma']);

		$payload = array(
			'invoice_type' => 'invoice_sales',
			'document_date' => $order->get_date_created()->format('Y-m-d'),
			'currency_id' => (int) get_option('hesabix_v2_currency_id', 1),
			'is_proforma' => $is_proforma,
			'extra_info' => array(
				'totals' => array(
					'gross' => round($gross, 0),
					'discount' => round($order_discount, 0),
					'tax' => round($order_tax, 0),
					'net' => round($order_total, 0),
				),
				'post_inventory' => true,
				'ignore_credit_check' => false,
				'person_id' => $person_id,
				'source' => 'woocommerce',
				'wc_order_id' => $order->get_id(),
			),
			'lines' => $lines,
		);

		$tag_ids = Hesabix_V2_Invoice_Helper::resolve_invoice_tag_ids();
		if (!empty($tag_ids)) {
			$payload['tag_ids'] = $tag_ids;
		}

		$payments = array();
		if (!$is_proforma && $order->is_paid()) {
			$bank_id = get_option('hesabix_v2_default_bank_id', null);
			$payments[] = array(
				'type' => 'bank',
				'bank_id' => $bank_id ? (string) $bank_id : null,
				'amount' => round($order_total, 0),
				'transaction_date' => $order->get_date_paid() ? $order->get_date_paid()->format('Y-m-d\TH:i:s.v') : current_time('Y-m-d\TH:i:s.v'),
			);
		}
		$payload['payments'] = $payments;

		return $payload;
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

		// تطبیق والد ووکامرس با دستهٔ والد در حسابیکس (در صورت وجود)
		$parent_hesabix_id = null;
		if (!empty($term->parent) && (int) $term->parent > 0) {
			$parent_hesabix_id = self::get_or_create_category_mapping((int) $term->parent);
		}

		// Create category in Hesabix (API از فیلد label برای title_translations استفاده می‌کند)
		$api = new Hesabix_V2_Api();
		$result = $api->create_category(array(
			'label' => $term->name,
			'parent_id' => $parent_hesabix_id,
		));

		if (isset($result['success']) && $result['success']) {
			$item = (isset($result['data']['item']) && is_array($result['data']['item']))
				? $result['data']['item']
				: null;
			$hesabix_category_id = null;
			if ($item && isset($item['id'])) {
				$hesabix_category_id = (int) $item['id'];
			} elseif (isset($result['data']['id'])) {
				$hesabix_category_id = (int) $result['data']['id'];
			}

			if (!$hesabix_category_id) {
				return null;
			}

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

		// Create shipping product (فرمت API حسابیکس: name، item_type، main_unit، base_sales_price)
		$api = new Hesabix_V2_Api();
		$result = $api->create_product(array(
			'name' => 'هزینه حمل و نقل',
			'item_type' => 'خدمت',
			'main_unit' => 'عدد',
			'base_sales_price' => 0,
			'track_inventory' => false,
			'is_active' => true,
		));

		if (isset($result['success']) && $result['success']) {
			$shipping_product_id = $result['data']['id'];
			update_option('hesabix_v2_shipping_product_id', $shipping_product_id);
			return $shipping_product_id;
		}

		return null;
	}
}

