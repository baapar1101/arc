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
	public static function wc_product_to_api($product, $wc_id, $amount_factor = 1.0)
	{
		$name_fa = Hesabix_V2_Validation::sanitize_product_name($product->get_title());

		$f = (float) $amount_factor;
		if ($f <= 0 || is_nan($f)) {
			$f = 1.0;
		}

		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		$cats_on = !isset($sync_settings['sync_product_categories']) || !empty($sync_settings['sync_product_categories']);

		// Get category
		$category_id = null;
		if ($cats_on) {
			$categories = $product->get_category_ids();
			if (!empty($categories)) {
				$category_id = self::get_or_create_category_mapping($categories[0]);
			}
		}

		// Get price
		$sell_price = 0;
		if ($product->get_regular_price()) {
			$sell_price = Hesabix_V2_Validation::sanitize_price((float) $product->get_regular_price() * $f);
		} elseif ($product->get_price()) {
			$sell_price = Hesabix_V2_Validation::sanitize_price((float) $product->get_price() * $f);
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
	public static function wc_variation_to_api($parent_product, $variation, $parent_id, $amount_factor = 1.0)
	{
		$variation_id = $variation->get_id();
		$parent_name = $parent_product->get_title();
		$variation_name = $variation->get_attribute_summary();

		$f = (float) $amount_factor;
		if ($f <= 0 || is_nan($f)) {
			$f = 1.0;
		}

		// Build full name
		$full_name = $parent_name;
		if (!empty($variation_name)) {
			$full_name .= ' - ' . $variation_name;
		}
		$full_name = Hesabix_V2_Validation::sanitize_product_name($full_name);

		// Get category from parent
		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		$cats_on = !isset($sync_settings['sync_product_categories']) || !empty($sync_settings['sync_product_categories']);

		$category_id = null;
		if ($cats_on) {
			$categories = $parent_product->get_category_ids();
			if (!empty($categories)) {
				$category_id = self::get_or_create_category_mapping($categories[0]);
			}
		}

		// Get price
		$sell_price = 0;
		if ($variation->get_regular_price()) {
			$sell_price = Hesabix_V2_Validation::sanitize_price((float) $variation->get_regular_price() * $f);
		} elseif ($variation->get_price()) {
			$sell_price = Hesabix_V2_Validation::sanitize_price((float) $variation->get_price() * $f);
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
		} elseif ($customer_id) {
			self::merge_wc_customer_billing_into_person_payload($customer, $data);
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
	 * پر کردن آدرس و تماس از صورت‌حساب ذخیره‌شده روی WC_Customer وقتی سفارش در دست نیست.
	 *
	 * @param WC_Customer $customer
	 * @param array         $data      ارجاع به آرایهٔ در حال ساخت برای API
	 * @return void
	 */
	private static function merge_wc_customer_billing_into_person_payload($customer, array &$data)
	{
		$uid = (int) $customer->get_id();
		if ($uid < 1) {
			return;
		}

		$line1 = trim((string) $customer->get_billing_address_1());
		$line2 = trim((string) $customer->get_billing_address_2());
		$address = $line1;
		if ($line2 !== '') {
			$address .= ($address !== '' ? ' - ' : '') . $line2;
		}
		if ($address !== '') {
			$san = Hesabix_V2_Validation::sanitize_address($address);
			if ($san) {
				$data['address'] = $san;
			}
		}

		$city = trim((string) $customer->get_billing_city());
		if ($city !== '') {
			$data['city'] = sanitize_text_field($city);
		}

		$postcode_raw = (string) $customer->get_billing_postcode();
		$postcode = Hesabix_V2_Validation::sanitize_postal_code($postcode_raw);
		if (!$postcode && $postcode_raw !== '') {
			$digits = preg_replace('/[^0-9]/', '', $postcode_raw);
			if ($digits !== '') {
				$postcode = substr($digits, 0, 20);
			}
		}
		if ($postcode) {
			$data['postal_code'] = $postcode;
		}

		$state = trim((string) $customer->get_billing_state());
		if ($state !== '') {
			$data['province'] = mb_substr(sanitize_text_field($state), 0, 100);
		}

		$country = trim((string) $customer->get_billing_country());
		if ($country !== '') {
			$data['country'] = mb_substr(sanitize_text_field($country), 0, 100);
		}

		$company = trim((string) $customer->get_billing_company());
		if ($company !== '') {
			$data['company_name'] = mb_substr(sanitize_text_field($company), 0, 255);
		}

		$billing_phone_alt = Hesabix_V2_Validation::sanitize_mobile($customer->get_billing_phone());
		if (empty($data['mobile']) && $billing_phone_alt) {
			$data['mobile'] = $billing_phone_alt;
		}

		$nid = get_user_meta($uid, 'billing_hesabix_v2_national_id', true);
		if (!$nid) {
			$nid = get_user_meta($uid, '_billing_hesabix_v2_national_id', true);
		}
		if ($nid) {
			$san_nid = Hesabix_V2_Validation::sanitize_national_id($nid);
			if ($san_nid) {
				$data['national_id'] = $san_nid;
			}
		}

		$econ = get_user_meta($uid, 'billing_hesabix_v2_economic_code', true);
		if (!$econ) {
			$econ = get_user_meta($uid, '_billing_hesabix_v2_economic_code', true);
		}
		if ($econ) {
			$data['economic_id'] = mb_substr(sanitize_text_field((string) $econ), 0, 50);
		}
	}

	/**
	 * اعمال دادهٔ شخص حسابیکس روی مشتری ووکامرس + متای کاربر.
	 *
	 * @param int   $user_id
	 * @param array $person ردیف شخص از API (مثل items[])
	 * @return void
	 */
	public static function apply_hesabix_person_to_wc_customer($user_id, array $person)
	{
		$user_id = (int) $user_id;
		if ($user_id < 1 || empty($person['id'])) {
			return;
		}

		$wc = new WC_Customer($user_id);

		$fn = isset($person['first_name']) ? trim((string) $person['first_name']) : '';
		$ln = isset($person['last_name']) ? trim((string) $person['last_name']) : '';

		if ($fn === '' && $ln === '' && !empty($person['alias_name'])) {
			$parts = preg_split('/\s+/u', trim((string) $person['alias_name']), 2);
			$fn = $parts[0] ?? '';
			$ln = isset($parts[1]) ? $parts[1] : '';
		}

		if ($fn !== '') {
			$wc->set_first_name(mb_substr($fn, 0, 100));
		}
		if ($ln !== '') {
			$wc->set_last_name(mb_substr($ln, 0, 100));
		}

		if ($fn !== '' || $ln !== '') {
			$wc->set_display_name(trim($fn . ' ' . $ln));
			wp_update_user(
				array(
					'ID' => $user_id,
					'first_name' => $wc->get_first_name(),
					'last_name' => $wc->get_last_name(),
					'display_name' => trim($wc->get_first_name() . ' ' . $wc->get_last_name()),
				)
			);
		}

		if (!empty($person['email'])) {
			$new_email = Hesabix_V2_Validation::sanitize_email((string) $person['email']);
			if ($new_email) {
				$existing = email_exists($new_email);
				if (!$existing || (int) $existing === $user_id) {
					wp_update_user(array(
						'ID' => $user_id,
						'user_email' => $new_email,
					));
					$wc->set_email($new_email);
				}
			}
		}

		if (!empty($person['mobile'])) {
			$m = Hesabix_V2_Validation::sanitize_mobile((string) $person['mobile']);
			if ($m) {
				$wc->set_billing_phone($m);
			}
		} elseif (!empty($person['phone'])) {
			$wc->set_billing_phone(mb_substr(sanitize_text_field((string) $person['phone']), 0, 20));
		}

		if (!empty($person['company_name'])) {
			$wc->set_billing_company(mb_substr(sanitize_text_field((string) $person['company_name']), 0, 200));
		}

		if (!empty($person['address'])) {
			$wc->set_billing_address_1(mb_substr(Hesabix_V2_Validation::sanitize_address((string) $person['address']), 0, 200));
		}

		if (!empty($person['city'])) {
			$wc->set_billing_city(mb_substr(sanitize_text_field((string) $person['city']), 0, 100));
		}

		if (!empty($person['postal_code'])) {
			$pc = Hesabix_V2_Validation::sanitize_postal_code((string) $person['postal_code']);
			if (!$pc) {
				$digits = preg_replace('/[^0-9]/', '', (string) $person['postal_code']);
				$pc = $digits !== '' ? substr($digits, 0, 20) : '';
			}
			if ($pc) {
				$wc->set_billing_postcode($pc);
			}
		}

		if (!empty($person['province'])) {
			$wc->set_billing_state(mb_substr(sanitize_text_field((string) $person['province']), 0, 100));
		}

		if (!empty($person['country'])) {
			$raw = trim((string) $person['country']);
			if (preg_match('/^[A-Za-z]{2}$/', $raw)) {
				$wc->set_billing_country(strtoupper($raw));
			}
		}

		if (!empty($person['national_id'])) {
			$n = Hesabix_V2_Validation::sanitize_national_id((string) $person['national_id']);
			if ($n) {
				update_user_meta($user_id, 'billing_hesabix_v2_national_id', $n);
			}
		}

		if (!empty($person['economic_id'])) {
			update_user_meta($user_id, 'billing_hesabix_v2_economic_code', mb_substr(sanitize_text_field((string) $person['economic_id']), 0, 50));
		}

		$wc->save();
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
	 * @param    float|null  $amount_factor   ضریب مبلغ (مثلاً ۱۰ برای تومان→ریال).
	 * @param    int|null    $invoice_currency_id شناسهٔ ارز در حسابیکس؛ اگر تهی باشد از تنظیمات/پیش‌فرض حل می‌شود.
	 * @return   array
	 */
	public static function wc_order_to_invoice($order, $person_id, $amount_factor = 1.0, $invoice_currency_id = null)
	{
		$f = (float) $amount_factor;
		if ($f <= 0 || is_nan($f)) {
			$f = 1.0;
		}

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
				$sync_result = $sync_service->sync_product($product_id, $variation_id, $order->get_currency());
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
			$total = (float) $item->get_total() * $f;
			$unit_price = $quantity > 0 ? $total / $quantity : 0;
			$tax_amount = Hesabix_V2_Validation::sanitize_price((float) $item->get_total_tax() * $f);
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
				$ship_total = Hesabix_V2_Validation::sanitize_price((float) $order->get_shipping_total() * $f);
				$ship_tax = Hesabix_V2_Validation::sanitize_price((float) $order->get_shipping_tax() * $f);
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

		// کارمزد درگاه، هزینه‌های اضافی و سایر Feeهای ووکامرس
		foreach ($order->get_items('fee') as $fee_item) {
			if (!is_object($fee_item) || !method_exists($fee_item, 'get_total')) {
				continue;
			}
			$fee_total = Hesabix_V2_Validation::sanitize_price((float) $fee_item->get_total() * $f);
			$fee_tax = method_exists($fee_item, 'get_total_tax')
				? Hesabix_V2_Validation::sanitize_price((float) $fee_item->get_total_tax() * $f)
				: 0.0;
			if (abs($fee_total) < 0.00001 && abs($fee_tax) < 0.00001) {
				continue;
			}

			$fee_product_id = self::get_or_create_fee_product();
			if (!$fee_product_id) {
				Hesabix_V2_Log_Service::warning('Fee line skipped — could not resolve fee service product in Hesabix', array(
					'order_id' => $order->get_id(),
					'fee_name' => method_exists($fee_item, 'get_name') ? $fee_item->get_name() : '',
				));
				continue;
			}

			$fee_label = method_exists($fee_item, 'get_name') ? trim((string) $fee_item->get_name()) : '';
			if ($fee_label === '') {
				$fee_label = __('کارمزد / هزینه سفارش', 'hesabix-v2');
			}

			// کارمزد منفی ووکامرس: بدون unit_price منفی؛ با line_discount برای هم‌خوانی بهتر گزارش‌ها
			if ($fee_total < 0) {
				$line_extra = array(
					'unit_price' => 0,
					'line_discount' => Hesabix_V2_Validation::sanitize_price(-(float) $fee_total),
					'tax_amount' => $fee_tax,
					'line_total' => $fee_total + $fee_tax,
					'unit' => 'عدد',
					'unit_price_source' => 'base',
					'discount_type' => 'amount',
					'discount_value' => 0,
					'tax_rate' => 0,
					'movement' => 'out',
					'wc_fee_label' => $fee_label,
					'wc_fee_negative' => true,
				);
			} else {
				$line_extra = array(
					'unit_price' => $fee_total,
					'line_discount' => 0,
					'tax_amount' => $fee_tax,
					'line_total' => $fee_total + $fee_tax,
					'unit' => 'عدد',
					'unit_price_source' => 'base',
					'discount_type' => 'amount',
					'discount_value' => 0,
					'tax_rate' => 0,
					'movement' => 'out',
					'wc_fee_label' => $fee_label,
				);
			}

			$lines[] = array(
				'product_id' => $fee_product_id,
				'quantity' => 1,
				'description' => sanitize_text_field(mb_substr($fee_label, 0, 500)),
				'extra_info' => $line_extra,
			);
		}

		$order_total = (float) $order->get_total() * $f;
		$order_tax = (float) $order->get_total_tax() * $f;
		$order_discount = (float) $order->get_discount_total() * $f;

		$target_net_rounded = (int) round($order_total, 0);
		self::adjust_invoice_lines_rounding_to_order_net($lines, $target_net_rounded, $order->get_id());

		$gross = $order_total + $order_discount - $order_tax;

		// حسابیکس مبلغ قطعی فاکتور را از gross − discount + tax می‌گیرد؛ پرداخت افزونه از round(order_total).
		// گرد کردن جداگانه ممکن است ۱–۲ واحد اختلاف بدهد؛ gross را در حد تحمل اصلاح می‌کنیم.
		$gross_r = (int) round($gross, 0);
		$discount_r = (int) round($order_discount, 0);
		$tax_r = (int) round($order_tax, 0);
		$from_header = $gross_r - $discount_r + $tax_r;
		$hdr_delta = $target_net_rounded - $from_header;
		if ($hdr_delta !== 0) {
			$hdr_tol = (int) apply_filters('hesabix_v2_invoice_header_totals_tolerance', 5);
			if ($hdr_tol < 1) {
				$hdr_tol = 1;
			}
			if (abs($hdr_delta) <= $hdr_tol && ($gross_r + $hdr_delta) >= 0) {
				$gross_r += $hdr_delta;
			} elseif (abs($hdr_delta) <= $hdr_tol && ($gross_r + $hdr_delta) < 0) {
				Hesabix_V2_Log_Service::warning(
					'Invoice header gross adjustment skipped (would become negative).',
					array(
						'order_id' => $order->get_id(),
						'gross_r' => $gross_r,
						'hdr_delta' => $hdr_delta,
					)
				);
			} elseif (abs($hdr_delta) > $hdr_tol) {
				Hesabix_V2_Log_Service::warning(
					'Invoice header totals (gross−discount+tax) vs WooCommerce order total differ beyond tolerance; payment amount may not match AR.',
					array(
						'order_id' => $order->get_id(),
						'gross_rounded' => (int) round($gross, 0),
						'discount_r' => $discount_r,
						'tax_r' => $tax_r,
						'from_header' => $from_header,
						'target_net_rounded' => $target_net_rounded,
						'delta' => $hdr_delta,
						'tolerance' => $hdr_tol,
					)
				);
			}
		}

		$sync = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		$is_proforma = !empty($sync['invoice_is_proforma']);

		$currency_id = $invoice_currency_id !== null
			? (int) $invoice_currency_id
			: Hesabix_V2_Currency_Service::resolve_invoice_currency_id();

		$payload = array(
			'invoice_type' => 'invoice_sales',
			'document_date' => $order->get_date_created()->format('Y-m-d'),
			'currency_id' => $currency_id,
			'is_proforma' => $is_proforma,
			'extra_info' => array(
				'totals' => array(
					'gross' => $gross_r,
					'discount' => $discount_r,
					'tax' => $tax_r,
					'net' => $target_net_rounded,
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

		$payload['payments'] = self::build_wc_order_invoice_payments($order, $is_proforma, $f);

		return $payload;
	}

	/**
	 * اختلاف گرد کردن بین جمع line_total خطوط و مبلغ نهایی سفارش ( IRR / واحدهای صحیح ).
	 *
	 * حداکثر اختلاف قابل قبول با فیلتر `hesabix_v2_invoice_rounding_tolerance` (پیش‌فرض ۲ واحد پول).
	 *
	 * @param array<int, array<string, mixed>> $lines
	 * @param int                               $target_net_rounded round(order_total)
	 * @param int                               $order_id
	 * @return void
	 */
	private static function adjust_invoice_lines_rounding_to_order_net(array &$lines, $target_net_rounded, $order_id)
	{
		if (empty($lines)) {
			return;
		}

		$sum = 0.0;
		foreach ($lines as $ln) {
			$ei = isset($ln['extra_info']) && is_array($ln['extra_info']) ? $ln['extra_info'] : array();
			if (!isset($ei['line_total'])) {
				continue;
			}
			$sum += (float) $ei['line_total'];
		}

		$delta = $target_net_rounded - (int) round($sum, 0);
		if ($delta === 0) {
			return;
		}

		$tolerance = (int) apply_filters('hesabix_v2_invoice_rounding_tolerance', 2);
		if ($tolerance < 1) {
			$tolerance = 1;
		}
		if (abs($delta) > $tolerance) {
			Hesabix_V2_Log_Service::warning(
				'Invoice lines sum vs WooCommerce order total exceeds rounding tolerance; no auto-adjust applied.',
				array(
					'order_id' => $order_id,
					'lines_sum_rounded' => (int) round($sum, 0),
					'target_net_rounded' => $target_net_rounded,
					'delta' => $delta,
					'tolerance' => $tolerance,
				)
			);
			return;
		}

		$fee_pid = (int) get_option('hesabix_v2_fee_product_id', 0);
		$ship_pid = (int) get_option('hesabix_v2_shipping_product_id', 0);

		$idx = null;
		for ($i = count($lines) - 1; $i >= 0; $i--) {
			$pid = isset($lines[ $i ]['product_id']) ? (int) $lines[ $i ]['product_id'] : 0;
			if ($fee_pid > 0 && $pid === $fee_pid) {
				$idx = $i;
				break;
			}
		}
		if ($idx === null) {
			for ($i = count($lines) - 1; $i >= 0; $i--) {
				$pid = isset($lines[ $i ]['product_id']) ? (int) $lines[ $i ]['product_id'] : 0;
				if ($ship_pid > 0 && $pid === $ship_pid) {
					$idx = $i;
					break;
				}
			}
		}
		if ($idx === null) {
			$idx = count($lines) - 1;
		}

		$qty = isset($lines[ $idx ]['quantity']) ? (float) $lines[ $idx ]['quantity'] : 1.0;
		if ($qty <= 0) {
			$qty = 1.0;
		}

		if (!isset($lines[ $idx ]['extra_info']) || !is_array($lines[ $idx ]['extra_info'])) {
			return;
		}

		$ei = &$lines[ $idx ]['extra_info'];
		$ei['line_total'] = (float) $ei['line_total'] + $delta;

		if (!empty($ei['wc_fee_negative'])) {
			$ei['line_discount'] = (float) $ei['line_discount'] - $delta;
		} else {
			$ei['unit_price'] = (float) $ei['unit_price'] + ($delta / $qty);
		}

		$ei['wc_rounding_adjust'] = $delta;

		if (get_option('hesabix_v2_debug_mode')) {
			Hesabix_V2_Log_Service::debug(
				'Invoice lines rounded to match WooCommerce order net.',
				array(
					'order_id' => $order_id,
					'adjusted_line_index' => $idx,
					'delta' => $delta,
				)
			);
		}
	}

	/**
	 * پرداخت‌های همراه فاکتور (سند دریافت در حسابیکس) فقط برای فاکتور قطعی و سفارش پرداخت‌شده.
	 *
	 * @param WC_Order $order
	 * @param bool     $is_proforma
	 * @param float    $amount_factor ضریب مبلغ نهایی سفارش برای پرداخت هم‌تراز با خطوط فاکتور.
	 * @return array<int, array<string, mixed>>
	 */
	private static function build_wc_order_invoice_payments($order, $is_proforma, $amount_factor = 1.0)
	{
		$payments = array();

		if ($is_proforma || !$order->is_paid()) {
			return apply_filters('hesabix_v2_invoice_payments', $payments, $order, $amount_factor);
		}

		$f = (float) $amount_factor;
		if ($f <= 0 || is_nan($f)) {
			$f = 1.0;
		}

		$amount = round((float) $order->get_total() * $f, 0);
		if ($amount <= 0) {
			return apply_filters('hesabix_v2_invoice_payments', $payments, $order, $amount_factor);
		}

		$transaction_date = $order->get_date_paid()
			? $order->get_date_paid()->format('Y-m-d\TH:i:s.v')
			: current_time('Y-m-d\TH:i:s.v');

		$desc = sprintf(
			/* translators: %s: WooCommerce order number */
			__('پرداخت سفارش #%s', 'hesabix-v2'),
			$order->get_order_number()
		);

		$destination = get_option('hesabix_v2_invoice_payment_destination', 'bank');
		if ($destination !== 'cash_register') {
			$destination = 'bank';
		}

		if ($destination === 'cash_register') {
			$cash_id = get_option('hesabix_v2_default_cash_register_id', '');
			if ($cash_id !== '' && $cash_id !== null && (int) $cash_id > 0) {
				$payments[] = array(
					'type' => 'cash_register',
					'transaction_type' => 'cash_register',
					'cash_register_id' => (string) (int) $cash_id,
					'amount' => $amount,
					'transaction_date' => $transaction_date,
					'description' => $desc,
				);
			} else {
				Hesabix_V2_Log_Service::warning(
					'Paid order: cash_register selected for invoice payments but no cash register configured.',
					array('order_id' => $order->get_id())
				);
			}
		} else {
			$bank_id = get_option('hesabix_v2_default_bank_id', '');
			if ($bank_id !== '' && $bank_id !== null) {
				$payments[] = array(
					'type' => 'bank',
					'transaction_type' => 'bank',
					'bank_id' => (string) $bank_id,
					'amount' => $amount,
					'transaction_date' => $transaction_date,
					'description' => $desc,
				);
			} else {
				Hesabix_V2_Log_Service::warning(
					'Paid order: bank selected for invoice payments but no bank account configured.',
					array('order_id' => $order->get_id())
				);
			}
		}

		return apply_filters('hesabix_v2_invoice_payments', $payments, $order, $amount_factor);
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

	/**
	 * کالای خدمتی برای خطوط کارمزد/Fee ووکامرس در فاکتور
	 *
	 * @return int|null
	 */
	private static function get_or_create_fee_product()
	{
		$fee_product_id = get_option('hesabix_v2_fee_product_id');

		if ($fee_product_id) {
			return (int) $fee_product_id;
		}

		$api = new Hesabix_V2_Api();
		$result = $api->create_product(array(
			'name' => 'کارمزد و هزینه سفارش (ووکامرس)',
			'item_type' => 'خدمت',
			'main_unit' => 'عدد',
			'base_sales_price' => 0,
			'track_inventory' => false,
			'is_active' => true,
		));

		if (isset($result['success']) && $result['success']) {
			$fee_product_id = null;
			if (isset($result['data']['item']['id'])) {
				$fee_product_id = (int) $result['data']['item']['id'];
			} elseif (isset($result['data']['id'])) {
				$fee_product_id = (int) $result['data']['id'];
			}
			if ($fee_product_id && $fee_product_id > 0) {
				update_option('hesabix_v2_fee_product_id', $fee_product_id);
				return $fee_product_id;
			}
		}

		return null;
	}
}

