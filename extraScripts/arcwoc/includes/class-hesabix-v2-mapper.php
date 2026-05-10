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
	 * کش مسطح درخت دسته‌های حسابیکس برای تطبیق نام (هر درخواست PHP).
	 *
	 * @var array<int, array{id:int,parent_id:?int,label:string}>|null
	 */
	private static $hx_category_flat_cache = null;

	/**
	 * کش شناسه‌های ترم product_cat مرتب‌شده بر اساس عمق (هر درخواست PHP).
	 *
	 * @var int[]|null
	 */
	private static $wc_product_cat_ids_sorted_cache = null;

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
			$wc_cat = self::pick_wc_product_category_term_id($product);
			if ($wc_cat !== null) {
				$category_id = self::get_or_create_category_mapping($wc_cat);
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
			$wc_cat = self::pick_wc_product_category_term_id($parent_product);
			if ($wc_cat !== null) {
				$category_id = self::get_or_create_category_mapping($wc_cat);
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
	 * مقدار track_inventory حسابیکس بر اساس سیاست انتخابی (وقتی همگام‌سازی موجودی روشن باشد).
	 *
	 * @param WC_Product $product محصول ساده یا واریانت.
	 * @param string     $policy  یکی از: wc، physical_always، always_on، always_off
	 * @return bool
	 */
	public static function resolve_track_inventory_by_policy($product, $policy)
	{
		if (!$product instanceof WC_Product) {
			return false;
		}

		$p = is_string($policy) ? sanitize_key($policy) : 'wc';

		switch ($p) {
			case 'physical_always':
				return !$product->is_virtual();
			case 'always_on':
				return true;
			case 'always_off':
				return false;
			case 'wc':
			default:
				return $product->managing_stock();
		}
	}

	/**
	 * آیا برای موجودی اولیه / نمایش موجودی ووکامرس از این قلم استفاده شود؟
	 *
	 * @param WC_Product $product
	 * @param string     $policy
	 * @return bool
	 */
	public static function wc_product_qualifies_for_opening_stock_qty($product, $policy)
	{
		if (!$product instanceof WC_Product || $product->is_virtual()) {
			return false;
		}

		$p = is_string($policy) ? sanitize_key($policy) : 'wc';

		switch ($p) {
			case 'physical_always':
			case 'always_on':
				return true;
			case 'always_off':
				return $product->managing_stock();
			case 'wc':
			default:
				return $product->managing_stock();
		}
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
	 * @param    array|null  $date_overrides      اختیاری: `document_date` (Y-m-d)، `payment_date_ymd` (Y-m-d برای بخش تاریخ transaction_date پرداخت).
	 * @return   array
	 */
	public static function wc_order_to_invoice($order, $person_id, $amount_factor = 1.0, $invoice_currency_id = null, $date_overrides = null)
	{
		$f = (float) $amount_factor;
		if ($f <= 0 || is_nan($f)) {
			$f = 1.0;
		}

		$date_opts = is_array($date_overrides) ? $date_overrides : array();
		$document_date_override = isset($date_opts['document_date']) && is_string($date_opts['document_date']) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $date_opts['document_date'])
			? $date_opts['document_date']
			: null;
		$payment_date_ymd = isset($date_opts['payment_date_ymd']) && is_string($date_opts['payment_date_ymd']) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $date_opts['payment_date_ymd'])
			? $date_opts['payment_date_ymd']
			: null;

		$lines = array();
		$db_service = new Hesabix_V2_DB_Service();
		$warehouse_id = Hesabix_V2_Invoice_Warehouse_Service::resolve_warehouse_id_for_order($order);

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

			if ($warehouse_id !== null && $warehouse_id !== '') {
				$line_extra['warehouse_id'] = (int) $warehouse_id;
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

		$_created = $order->get_date_created();
		$document_date = $document_date_override !== null
			? $document_date_override
			: ($_created ? $_created->format('Y-m-d') : current_time('Y-m-d'));

		$payload = array(
			'invoice_type' => 'invoice_sales',
			'document_date' => $document_date,
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

		$payload['payments'] = self::build_wc_order_invoice_payments($order, $is_proforma, $f, $payment_date_ymd);

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
	 * @param string|null $payment_date_ymd اگر ست باشد، بخش تاریخ transaction_date هم‌راستا با این مقدار (بخش ساعت از تاریخ پرداخت یا زمان کنونی).
	 * @return array<int, array<string, mixed>>
	 */
	private static function build_wc_order_invoice_payments($order, $is_proforma, $amount_factor = 1.0, $payment_date_ymd = null)
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

		$date_paid = $order->get_date_paid();
		if (is_string($payment_date_ymd) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $payment_date_ymd)) {
			$time_part = $date_paid ? $date_paid->format('H:i:s.v') : current_time('H:i:s.v');
			$transaction_date = $payment_date_ymd . 'T' . $time_part;
		} elseif ($date_paid) {
			$transaction_date = $date_paid->format('Y-m-d\TH:i:s.v');
		} else {
			$transaction_date = current_time('Y-m-d\TH:i:s.v');
		}

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
	 * انتخاب یک ترم product_cat برای همگام با حسابیکس (چند دسته: اصلی SEO یا عمیق‌ترین شاخه).
	 *
	 * @since 2.0.8
	 * @param WC_Product $product
	 * @return int|null term_id
	 */
	private static function pick_wc_product_category_term_id($product)
	{
		$ids = array_values(array_unique(array_filter(array_map('intval', (array) $product->get_category_ids()))));
		if (empty($ids)) {
			return null;
		}

		$picked = apply_filters('hesabix_v2_primary_product_cat_term_id', null, $product, $ids);
		if (is_int($picked) && $picked > 0 && in_array($picked, $ids, true)) {
			return (int) apply_filters('hesabix_v2_picked_product_cat_term_id', $picked, $product, $ids);
		}

		$yoast = (int) get_post_meta($product->get_id(), '_yoast_wpseo_primary_product_cat', true);
		if ($yoast > 0 && in_array($yoast, $ids, true)) {
			return (int) apply_filters('hesabix_v2_picked_product_cat_term_id', $yoast, $product, $ids);
		}

		$rank_math = (int) get_post_meta($product->get_id(), 'rank_math_primary_product_cat', true);
		if ($rank_math < 1) {
			$rank_math = (int) get_post_meta($product->get_id(), '_rank_math_primary_product_cat', true);
		}
		if ($rank_math > 0 && in_array($rank_math, $ids, true)) {
			return (int) apply_filters('hesabix_v2_picked_product_cat_term_id', $rank_math, $product, $ids);
		}

		$best_id = null;
		$best_depth = -1;
		foreach ($ids as $tid) {
			$d = self::wc_product_cat_hierarchy_depth($tid);
			if ($d > $best_depth) {
				$best_depth = $d;
				$best_id = $tid;
			} elseif ($d === $best_depth && $best_id !== null && $tid < $best_id) {
				$best_id = $tid;
			}
		}

		return apply_filters('hesabix_v2_picked_product_cat_term_id', $best_id, $product, $ids);
	}

	/**
	 * عمق سلسلهٔ والدها برای ترم product_cat (خود ترم شمرده می‌شود).
	 *
	 * @since 2.0.8
	 * @param int $term_id
	 * @return int
	 */
	private static function wc_product_cat_hierarchy_depth($term_id)
	{
		$depth = 0;
		$tid = (int) $term_id;
		$guard = 0;
		while ($tid > 0 && $guard++ < 64) {
			$t = get_term($tid, 'product_cat');
			if (!$t || is_wp_error($t)) {
				break;
			}
			$depth++;
			$tid = (int) $t->parent;
		}
		return $depth;
	}

	/**
	 * ذخیرهٔ اسنپ‌شات ووکامرس/حسابیکس برای تشخیص تغییر بعدی نام یا والد.
	 *
	 * @since 2.0.8
	 * @param Hesabix_V2_DB_Service $db
	 * @param int                   $wc_category_id
	 * @param int                   $hesabix_category_id
	 * @param \WP_Term              $term
	 * @param int|null              $hesabix_parent_id
	 * @param array<string,mixed>   $extra_meta
	 * @return void
	 */
	private static function persist_category_sync_snapshot($db, $wc_category_id, $hesabix_category_id, $term, $hesabix_parent_id, $extra_meta = array())
	{
		$meta = array(
			'wc_snapshot_v' => 1,
			'wc_label' => $term->name,
			'wc_parent_term_id' => (int) $term->parent,
			'hesabix_parent_id' => $hesabix_parent_id,
		);
		if (is_array($extra_meta) && !empty($extra_meta)) {
			$meta = array_merge($meta, $extra_meta);
		}
		$db->save_mapping(
			'category',
			$wc_category_id,
			null,
			$hesabix_category_id,
			null,
			$meta
		);
	}

	/**
	 * اگر نام یا والد ترم در ووکامرس عوض شده، دستهٔ متناظر در حسابیکس را به‌روز یا جابه‌جا کن.
	 *
	 * @since 2.0.8
	 * @param int                   $wc_category_id
	 * @param int                   $hesabix_category_id
	 * @param array<string,mixed>   $mapping_row
	 * @return void
	 */
	private static function refresh_mapped_wc_category_if_stale($wc_category_id, $hesabix_category_id, array $mapping_row)
	{
		$term = get_term($wc_category_id, 'product_cat');
		if (!$term || is_wp_error($term)) {
			return;
		}

		$db = new Hesabix_V2_DB_Service();
		$meta = array();
		if (!empty($mapping_row['meta_data'])) {
			$decoded = json_decode((string) $mapping_row['meta_data'], true);
			if (is_array($decoded)) {
				$meta = $decoded;
			}
		}

		$desired_parent_hx = null;
		if (!empty($term->parent) && (int) $term->parent > 0) {
			$desired_parent_hx = self::get_or_create_category_mapping((int) $term->parent);
		}

		if (empty($meta['wc_snapshot_v'])) {
			self::persist_category_sync_snapshot($db, $wc_category_id, $hesabix_category_id, $term, $desired_parent_hx);
			return;
		}

		$old_label = isset($meta['wc_label']) ? (string) $meta['wc_label'] : '';
		$old_wc_parent = array_key_exists('wc_parent_term_id', $meta) ? (int) $meta['wc_parent_term_id'] : null;
		$old_hx_parent = array_key_exists('hesabix_parent_id', $meta) ? $meta['hesabix_parent_id'] : '__unset__';
		if ($old_hx_parent !== null && $old_hx_parent !== '__unset__') {
			$old_hx_parent = (int) $old_hx_parent;
		}

		$label_stale = ($old_label !== (string) $term->name);
		$wc_parent_stale = ($old_wc_parent !== (int) $term->parent);
		$hx_parent_norm = ($old_hx_parent === '__unset__' ? null : $old_hx_parent);
		$parent_stale = $wc_parent_stale || ($hx_parent_norm !== $desired_parent_hx);

		if (!$label_stale && !$parent_stale) {
			return;
		}

		$api = new Hesabix_V2_Api();
		$ok = true;

		if ($parent_stale) {
			$mv = $api->move_category(array(
				'category_id' => $hesabix_category_id,
				'new_parent_id' => $desired_parent_hx,
			));
			if (empty($mv['success'])) {
				$ok = false;
				Hesabix_V2_Log_Service::warning('Hesabix category move failed (WC category sync)', array(
					'wc_category_id' => $wc_category_id,
					'hesabix_category_id' => $hesabix_category_id,
					'new_parent_id' => $desired_parent_hx,
					'response' => $mv,
				));
			}
		}

		if ($ok && $label_stale) {
			$up = $api->update_category(array(
				'category_id' => $hesabix_category_id,
				'label' => $term->name,
			));
			if (empty($up['success'])) {
				$ok = false;
				Hesabix_V2_Log_Service::warning('Hesabix category label update failed (WC category sync)', array(
					'wc_category_id' => $wc_category_id,
					'hesabix_category_id' => $hesabix_category_id,
					'response' => $up,
				));
			}
		}

		if ($ok) {
			self::persist_category_sync_snapshot($db, $wc_category_id, $hesabix_category_id, $term, $desired_parent_hx);
			self::invalidate_hesabix_category_flat_cache();
		}
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

		$mapping_row = $db_service->get_mapping('category', $wc_category_id, null);
		if ($mapping_row && !empty($mapping_row['hesabix_id'])) {
			$hid = (int) $mapping_row['hesabix_id'];
			self::refresh_mapped_wc_category_if_stale((int) $wc_category_id, $hid, $mapping_row);
			return $hid;
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

		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		if (!empty($sync_settings['sync_category_link_by_name_in_hesabix'])) {
			$try_link = apply_filters('hesabix_v2_should_link_category_by_name', true, $term, $parent_hesabix_id);
			if ($try_link) {
				$linked_id = self::find_hesabix_category_id_by_wc_term($term->name, $parent_hesabix_id);
				if ($linked_id) {
					self::persist_category_sync_snapshot(
						$db_service,
						(int) $wc_category_id,
						$linked_id,
						$term,
						$parent_hesabix_id,
						array('linked_existing_by_name' => true)
					);
					return $linked_id;
				}
			}
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

			self::invalidate_hesabix_category_flat_cache();

			self::persist_category_sync_snapshot(
				$db_service,
				(int) $wc_category_id,
				$hesabix_category_id,
				$term,
				$parent_hesabix_id
			);

			return $hesabix_category_id;
		}

		return null;
	}

	/**
	 * یک مرحلهٔ همگام‌سازی همهٔ ترم‌های product_cat (حتی بدون محصول).
	 *
	 * @since 2.0.8
	 * @param int $offset
	 * @param int $batch_size
	 * @return array<string,mixed>
	 */
	public static function bulk_sync_wc_product_categories_chunk($offset, $batch_size)
	{
		$offset = max(0, (int) $offset);
		$batch_size = max(1, min(500, (int) $batch_size));

		$ids = self::get_sorted_wc_product_cat_term_ids();
		$total = count($ids);
		$slice = array_slice($ids, $offset, $batch_size);

		$ok = 0;
		$fail = 0;
		$errors = array();

		foreach ($slice as $tid) {
			$hid = self::get_or_create_category_mapping((int) $tid);
			if ($hid) {
				$ok++;
			} else {
				$fail++;
				if (count($errors) < 40) {
					$errors[] = array(
						'wc_category_id' => (int) $tid,
						'message' => __('ایجاد/تطبیق دسته در حسابیکس ناموفق بود', 'hesabix-v2'),
					);
				}
			}
		}

		$next = $offset + count($slice);

		return array(
			'success' => true,
			'done' => ($next >= $total || empty($slice)),
			'next_offset' => $next,
			'estimated_catalog_total_wc_categories' => $total,
			'processed_wc_categories_in_chunk' => count($slice),
			'chunk_results' => array(
				'success' => $ok,
				'failed' => $fail,
				'total' => count($slice),
				'errors_preview' => $errors,
				'errors_total' => $fail,
			),
			'message' => sprintf(
				/* translators: 1: processed count, 2: total WC categories */
				__('مرحله انجام شد (%1$d از %2$d دسته در این بسته).', 'hesabix-v2'),
				count($slice),
				$total
			),
		);
	}

	/**
	 * @since 2.0.8
	 * @return int[]
	 */
	private static function get_sorted_wc_product_cat_term_ids()
	{
		if (self::$wc_product_cat_ids_sorted_cache !== null) {
			return self::$wc_product_cat_ids_sorted_cache;
		}

		$terms = get_terms(array(
			'taxonomy' => 'product_cat',
			'hide_empty' => false,
			'number' => 0,
			'orderby' => 'term_id',
			'order' => 'ASC',
		));

		if (is_wp_error($terms) || !is_array($terms)) {
			self::$wc_product_cat_ids_sorted_cache = array();
			return self::$wc_product_cat_ids_sorted_cache;
		}

		$ids = array();
		foreach ($terms as $t) {
			if (isset($t->term_id)) {
				$ids[] = (int) $t->term_id;
			}
		}
		$ids = array_values(array_unique(array_filter($ids)));

		usort(
			$ids,
			function ($a, $b) {
				$da = self::wc_product_cat_hierarchy_depth($a);
				$db = self::wc_product_cat_hierarchy_depth($b);
				if ($da !== $db) {
					return $da - $db;
				}
				return $a - $b;
			}
		);

		self::$wc_product_cat_ids_sorted_cache = $ids;
		return self::$wc_product_cat_ids_sorted_cache;
	}

	/**
	 * @since 2.0.8
	 * @return void
	 */
	private static function invalidate_hesabix_category_flat_cache()
	{
		self::$hx_category_flat_cache = null;
	}

	/**
	 * نرمال‌سازی برچسب برای مقایسهٔ تطبیق نام.
	 *
	 * @since 2.0.8
	 * @param string $label
	 * @return string
	 */
	private static function normalize_category_label_for_match($label)
	{
		$s = wp_strip_all_tags((string) $label);
		$s = preg_replace('/\s+/u', ' ', trim($s));
		if (function_exists('mb_strtolower')) {
			return mb_strtolower($s, 'UTF-8');
		}
		return strtolower($s);
	}

	/**
	 * @since 2.0.8
	 * @param int|null $a
	 * @param int|null $b
	 * @return bool
	 */
	private static function hesabix_parent_ids_equal($a, $b)
	{
		$ai = ($a === null || $a === '' || $a === false) ? null : (int) $a;
		$bi = ($b === null || $b === '' || $b === false) ? null : (int) $b;
		return $ai === $bi;
	}

	/**
	 * فهرست مسطح دسته‌های حسابیکس از درخت API.
	 *
	 * @since 2.0.8
	 * @return array<int, array{id:int,parent_id:?int,label:string}>
	 */
	private static function load_hesabix_categories_flat_index()
	{
		if (self::$hx_category_flat_cache !== null) {
			return self::$hx_category_flat_cache;
		}

		$api = new Hesabix_V2_Api();
		$res = $api->get_categories_tree();
		$flat = array();

		if (empty($res['success'])) {
			self::$hx_category_flat_cache = $flat;
			return self::$hx_category_flat_cache;
		}

		$items = array();
		if (isset($res['data']['items']) && is_array($res['data']['items'])) {
			$items = $res['data']['items'];
		}

		$walk = function ($nodes) use (&$walk, &$flat) {
			foreach ((array) $nodes as $n) {
				if (!is_array($n)) {
					continue;
				}
				$pid = null;
				if (array_key_exists('parent_id', $n)) {
					$pv = $n['parent_id'];
					$pid = ($pv === null || $pv === '' || $pv === false) ? null : (int) $pv;
				}
				$flat[] = array(
					'id' => isset($n['id']) ? (int) $n['id'] : 0,
					'parent_id' => $pid,
					'label' => isset($n['label']) ? (string) $n['label'] : '',
				);
				if (!empty($n['children']) && is_array($n['children'])) {
					$walk($n['children']);
				}
			}
		};
		$walk($items);

		self::$hx_category_flat_cache = $flat;
		return self::$hx_category_flat_cache;
	}

	/**
	 * پیدا کردن شناسهٔ دسته در حسابیکس با نام و والد (بدون ساخت رکورد جدید).
	 *
	 * @since 2.0.8
	 * @param string   $wc_term_name
	 * @param int|null $expected_parent_hesabix_id
	 * @return int|null
	 */
	private static function find_hesabix_category_id_by_wc_term($wc_term_name, $expected_parent_hesabix_id)
	{
		$want = self::normalize_category_label_for_match($wc_term_name);
		if ($want === '') {
			return null;
		}

		$rows = self::load_hesabix_categories_flat_index();
		if (empty($rows)) {
			return null;
		}

		$candidates = array();
		foreach ($rows as $row) {
			if (empty($row['id'])) {
				continue;
			}
			if (self::normalize_category_label_for_match($row['label']) !== $want) {
				continue;
			}
			if (!self::hesabix_parent_ids_equal($row['parent_id'], $expected_parent_hesabix_id)) {
				continue;
			}
			$candidates[] = (int) $row['id'];
		}

		if (empty($candidates)) {
			return null;
		}

		sort($candidates, SORT_NUMERIC);
		$chosen = (int) $candidates[0];

		return (int) apply_filters('hesabix_v2_linked_hesabix_category_id', $chosen, $wc_term_name, $expected_parent_hesabix_id, $candidates);
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

