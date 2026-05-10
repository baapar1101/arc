<?php
/**
 * Sync Service - Main synchronization logic
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Sync_Service
{
	/**
	 * API instance
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      Hesabix_V2_Api    $api
	 */
	private $api;

	/**
	 * DB Service instance
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      Hesabix_V2_DB_Service    $db
	 */
	private $db;

	/**
	 * پیش از فراخوانی API؛ انبار خطوط حل نشده باشد تا زمان اصلاح تنظیمات نباید دوباره به صف رود.
	 */
	const ERR_INVOICE_WAREHOUSE_PREFLIGHT = 94001;

	/**
	 * سقف اندازهٔ دسته AJAX ووکامرس در فرم همگام‌سازی دسته‌ای — با اندپوینت‌های bulk حسابیکس هم‌سو است.
	 *
	 * @since 3.5.0
	 */
	public const BULK_WC_CHUNK_MAX_ITEMS = 1000;

	/**
	 * حداکثر آیتم در هر بدنهٔ bulk API حسابیکس (اشخاص / فاکتور / کالا).
	 *
	 * @since 3.5.0
	 */
	public const BULK_API_ITEMS_MAX_PERSON = 1000;

	/** @since 3.5.0 */
	public const BULK_API_ITEMS_MAX_INVOICE = 1000;

	/** @since 3.5.0 */
	public const BULK_API_ITEMS_MAX_PRODUCT = 1000;

	/**
	 * پیش‌فرض‌های اندازهٔ دسته برای عملیات سنگین همگام‌سازی و واردات (کاهش تایم‌اوت AJAX).
	 *
	 * @since 2.0.7
	 * @return array<string, int>
	 */
	public static function get_bulk_sync_defaults()
	{
		return array(
			'wc_product_parents_per_ajax' => 35,
			'wc_categories_per_ajax' => 60,
			'wc_customers_per_ajax' => 45,
			'wc_orders_ajax_batch' => 40,
			'api_bulk_persons_per_request' => 35,
			'api_bulk_invoices_per_request' => 8,
			'api_bulk_products_per_request' => 20,
			'hesabix_person_take' => 80,
			'hesabix_import_pages_per_ajax' => 3,
			'errors_preview_cap' => 60,
		);
	}

	/**
	 * تنظیمات ذخیره‌شدهٔ همگام‌سازی دسته‌ای با محدودسازی امن.
	 *
	 * @since 2.0.7
	 * @return array<string, int>
	 */
	public static function get_bulk_sync_options()
	{
		$d = self::get_bulk_sync_defaults();
		$raw = get_option('hesabix_v2_bulk_sync', array());
		if (!is_array($raw)) {
			$raw = array();
		}
		$o = wp_parse_args($raw, $d);

		$o['wc_product_parents_per_ajax'] = max(5, min(self::BULK_WC_CHUNK_MAX_ITEMS, absint($o['wc_product_parents_per_ajax'])));
		$o['wc_categories_per_ajax'] = max(10, min(self::BULK_WC_CHUNK_MAX_ITEMS, absint($o['wc_categories_per_ajax'])));
		$o['wc_customers_per_ajax'] = max(5, min(self::BULK_WC_CHUNK_MAX_ITEMS, absint($o['wc_customers_per_ajax'])));

		$o['wc_orders_ajax_batch'] = max(5, min(self::BULK_WC_CHUNK_MAX_ITEMS, absint($o['wc_orders_ajax_batch'] ?? 40)));

		$o['api_bulk_persons_per_request'] = max(5, min(self::BULK_API_ITEMS_MAX_PERSON, absint($o['api_bulk_persons_per_request'] ?? 35)));
		$o['api_bulk_invoices_per_request'] = max(1, min(self::BULK_API_ITEMS_MAX_INVOICE, absint($o['api_bulk_invoices_per_request'] ?? 8)));
		$o['api_bulk_products_per_request'] = max(3, min(self::BULK_API_ITEMS_MAX_PRODUCT, absint($o['api_bulk_products_per_request'] ?? 20)));

		$o['hesabix_person_take'] = max(10, min(200, absint($o['hesabix_person_take'])));

		$o['hesabix_import_pages_per_ajax'] = max(1, min(50, absint($o['hesabix_import_pages_per_ajax'])));

		$o['errors_preview_cap'] = max(10, min(300, absint($o['errors_preview_cap'])));

		/**
		 * فیلتر نهایی گزینه‌های همگام‌سازی دسته‌ای.
		 *
		 * @param array<string,int> $o
		 */
		return apply_filters('hesabix_v2_bulk_sync_options', $o);
	}

	/**
	 * Initialize the class
	 *
	 * @since    2.0.0
	 */
	public function __construct()
	{
		$this->api = new Hesabix_V2_Api();
		$this->db = new Hesabix_V2_DB_Service();
	}

	/**
	 * Sync product to Hesabix
	 *
	 * @since    2.0.0
	 * @param    int       $product_id
	 * @param    int       $variation_id
	 * @return   array
	 */
	public function sync_product($product_id, $variation_id = null, $wc_currency_override = null)
	{
		$start_time = microtime(true);
		$wc_payload_for_log = null;
		$api_last_result = null;

		try {
			$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($this->api, $wc_currency_override);
			if (!$gate['ok']) {
				Hesabix_V2_Log_Service::warning('Product sync blocked — currency mismatch', array(
					'entity_type' => 'product',
					'entity_id' => $variation_id ? (int) $variation_id : (int) $product_id,
					'message' => $gate['message'],
				));

				return array(
					'success' => false,
					'message' => $gate['message'],
					'currency_blocked' => true,
				);
			}

			// Get product
			if ($variation_id) {
				$product = wc_get_product($variation_id);
				$parent_product = wc_get_product($product_id);
				
				if (!$product || !$parent_product) {
					throw new Exception(__('محصول یافت نشد', 'hesabix-v2'));
				}

				$product_data = Hesabix_V2_Mapper::wc_variation_to_api($parent_product, $product, $product_id, $gate['factor']);
				$wc_id = $variation_id;
				$wc_parent_id = $product_id;
			} else {
				$product = wc_get_product($product_id);
				
				if (!$product) {
					throw new Exception(__('محصول یافت نشد', 'hesabix-v2'));
				}

				$product_data = Hesabix_V2_Mapper::wc_product_to_api($product, $product_id, $gate['factor']);
				$wc_id = $product_id;
				$wc_parent_id = null;
			}

			$wc_payload_for_log = $product_data;

			// اعمال تنظیمات همگام‌سازی قیمت و موجودی (API حسابیکس: base_sales_price، track_inventory)
			$sync_settings = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
			if (empty($sync_settings['sync_product_price'])) {
				unset($product_data['base_sales_price']);
			}
			if (empty($sync_settings['sync_product_stock'])) {
				$product_data['track_inventory'] = false;
			} else {
				$policy = isset($sync_settings['track_inventory_policy']) ? (string) $sync_settings['track_inventory_policy'] : 'wc';
				$product_data['track_inventory'] = Hesabix_V2_Mapper::resolve_track_inventory_by_policy($product, $policy);
			}

			// Check if already synced
			$existing_mapping = $this->db->get_mapping('product', $wc_id, $wc_parent_id);

			if ($existing_mapping) {
				// Update existing product
				$api_last_result = $this->api->update_product($existing_mapping['hesabix_id'], $product_data);
			} else {
				// Create new product
				$api_last_result = $this->api->create_product($product_data);
			}

			if (isset($api_last_result['success']) && $api_last_result['success']) {
				$hesabix_id = $api_last_result['data']['id'];

				// Save mapping
				$this->db->save_mapping(
					'product',
					$wc_id,
					$wc_parent_id,
					$hesabix_id,
					'product',
					array('synced_at' => current_time('mysql'))
				);

				$execution_time = microtime(true) - $start_time;

				Hesabix_V2_Log_Service::info('Product synced successfully', array(
					'entity_type' => 'product',
					'entity_id' => $wc_id,
					'hesabix_id' => $hesabix_id,
					'execution_time' => $execution_time,
				));

				return array(
					'success' => true,
					'hesabix_id' => $hesabix_id,
					'message' => __('محصول با موفقیت همگام‌سازی شد', 'hesabix-v2'),
				);
			} else {
				throw new Exception($api_last_result['message'] ?? __('خطا در همگام‌سازی', 'hesabix-v2'));
			}

		} catch (Exception $e) {
			$execution_time = microtime(true) - $start_time;

			$elog = array(
				'entity_type' => 'product',
				'entity_id' => $variation_id ? (int) $variation_id : (int) $product_id,
				'error' => $e->getMessage(),
				'execution_time' => $execution_time,
			);
			if ($wc_payload_for_log !== null) {
				$elog['request'] = array(
					'direction' => 'woocommerce_payload',
					'entity' => 'product',
					'json_body' => $wc_payload_for_log,
				);
			}
			if (is_array($api_last_result)) {
				$elog['response'] = array(
					'direction' => 'hesabix_api',
					'decoded' => $api_last_result,
				);
			}
			Hesabix_V2_Log_Service::error('Product sync failed', $elog);

			$msg = $e->getMessage();
			if (strpos($msg, __('محصول یافت نشد', 'hesabix-v2')) === false) {
				$qid = $variation_id ? (int) $variation_id : (int) $product_id;
				$qpayload = $variation_id ? array('parent_id' => (int) $product_id) : null;
				Hesabix_V2_Queue_Service::enqueue('product', $qid, 'sync_product', $qpayload);
			}

			return array(
				'success' => false,
				'message' => $e->getMessage(),
			);
		}
	}

	/**
	 * Sync customer to Hesabix
	 *
	 * @since    2.0.0
	 * @param    int       $customer_id
	 * @param    int       $order_id      Optional order for additional data
	 * @return   array
	 */
	public function sync_customer($customer_id, $order_id = null)
	{
		$start_time = microtime(true);
		$wc_payload_for_log = null;
		$api_last_result = null;

		try {
			$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($this->api, null);
			if (!$gate['ok']) {
				Hesabix_V2_Log_Service::warning('Customer sync blocked — currency mismatch', array(
					'entity_type' => 'customer',
					'entity_id' => $customer_id,
					'message' => $gate['message'],
				));

				return array(
					'success' => false,
					'message' => $gate['message'],
					'currency_blocked' => true,
				);
			}

			$customer = new WC_Customer($customer_id);
			$order = $order_id ? wc_get_order($order_id) : null;

			if (!$customer->get_id()) {
				throw new Exception(__('مشتری یافت نشد', 'hesabix-v2'));
			}

			$customer_data = apply_filters(
				'hesabix_v2_customer_data',
				Hesabix_V2_Mapper::wc_customer_to_api($customer, $order),
				$customer,
				$order
			);

			$wc_payload_for_log = $customer_data;

			// Check if already synced
			$existing_mapping = $this->db->get_mapping('customer', $customer_id);

			if ($existing_mapping) {
				$api_last_result = $this->api->update_person($existing_mapping['hesabix_id'], $customer_data);
				// اگر شخص در حسابیکس حذف شده یا وجود ندارد، mapping را پاک کرده و دوباره ایجاد کن
				$msg = isset($api_last_result['message']) ? (string) $api_last_result['message'] : '';
				$is_not_found = $msg !== ''
					&& (stripos($msg, 'not found') !== false
						|| stripos($msg, 'Entity not found') !== false
						|| stripos($msg, 'یافت نشد') !== false);
				if (isset($api_last_result['success']) && !$api_last_result['success'] && $is_not_found) {
					$this->db->delete_mapping('customer', $customer_id);
					$api_last_result = $this->api->create_person($customer_data);
				}
			} else {
				$api_last_result = $this->api->create_person($customer_data);
			}

			if (isset($api_last_result['success']) && $api_last_result['success']) {
				$hesabix_id = self::api_result_entity_id($api_last_result);
				if ($hesabix_id < 1) {
					throw new Exception(__('شناسه شخص در پاسخ API یافت نشد', 'hesabix-v2'));
				}

				// Save mapping
				$this->db->save_mapping(
					'customer',
					$customer_id,
					null,
					$hesabix_id,
					'person'
				);

				$execution_time = microtime(true) - $start_time;

				Hesabix_V2_Log_Service::info('Customer synced successfully', array(
					'entity_type' => 'customer',
					'entity_id' => $customer_id,
					'hesabix_id' => $hesabix_id,
					'execution_time' => $execution_time,
				));

				return array(
					'success' => true,
					'hesabix_id' => $hesabix_id,
					'message' => __('مشتری با موفقیت همگام‌سازی شد', 'hesabix-v2'),
				);
			} else {
				throw new Exception($api_last_result['message'] ?? __('خطا در همگام‌سازی', 'hesabix-v2'));
			}

		} catch (Exception $e) {
			$execution_time = microtime(true) - $start_time;

			$elog = array(
				'entity_type' => 'customer',
				'entity_id' => $customer_id,
				'error' => $e->getMessage(),
				'execution_time' => $execution_time,
			);
			if ($wc_payload_for_log !== null) {
				$elog['request'] = array(
					'direction' => 'woocommerce_payload',
					'entity' => 'customer',
					'json_body' => $wc_payload_for_log,
				);
			}
			if (is_array($api_last_result)) {
				$elog['response'] = array(
					'direction' => 'hesabix_api',
					'decoded' => $api_last_result,
				);
			}
			Hesabix_V2_Log_Service::error('Customer sync failed', $elog);

			if ($customer_id > 0 && strpos($e->getMessage(), __('مشتری یافت نشد', 'hesabix-v2')) === false) {
				Hesabix_V2_Queue_Service::enqueue('customer', $customer_id, 'sync_customer');
			}

			return array(
				'success' => false,
				'message' => $e->getMessage(),
			);
		}
	}

	/**
	 * Sync guest customer from order
	 *
	 * @since    2.0.0
	 * @param    int    $order_id
	 * @return   array
	 */
	public function sync_guest_customer($order_id)
	{
		$start_time = microtime(true);
		$wc_payload_for_log = null;
		$api_last_result = null;

		try {
			$order = wc_get_order($order_id);

			if (!$order) {
				throw new Exception(__('سفارش یافت نشد', 'hesabix-v2'));
			}

			$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($this->api, $order->get_currency());
			if (!$gate['ok']) {
				Hesabix_V2_Log_Service::warning('Guest customer sync blocked — currency mismatch', array(
					'order_id' => $order_id,
					'message' => $gate['message'],
				));

				return array(
					'success' => false,
					'message' => $gate['message'],
					'currency_blocked' => true,
				);
			}

			$guest_data = apply_filters('hesabix_v2_guest_customer_data', Hesabix_V2_Mapper::wc_guest_to_api($order), $order);
			$wc_payload_for_log = $guest_data;
			$cache_key = self::guest_contact_transient_key($order);
			$cached_id = get_transient($cache_key);
			if ($cached_id !== false && $cached_id !== '') {
				$hid = (int) $cached_id;
				if ($hid > 0) {
					return array(
						'success' => true,
						'hesabix_id' => $hid,
						'message' => __('مشتری مهمان (از کش)', 'hesabix-v2'),
					);
				}
			}

			$email_raw = isset($guest_data['email']) ? (string) $guest_data['email'] : '';
			$mobile_raw = isset($guest_data['mobile']) ? (string) $guest_data['mobile'] : '';
			$email_cmp = mb_strtolower(trim($email_raw));
			$existing_pid = $this->api->find_person_id_by_contact($email_cmp, $mobile_raw);
			if ($existing_pid) {
				set_transient($cache_key, $existing_pid, 90 * DAY_IN_SECONDS);
				return array(
					'success' => true,
					'hesabix_id' => $existing_pid,
					'message' => __('مشتری مهمان (موجود در حسابیکس)', 'hesabix-v2'),
				);
			}

			$api_last_result = $this->api->create_person($guest_data);

			if (isset($api_last_result['success']) && $api_last_result['success']) {
				$hesabix_id = self::api_result_entity_id($api_last_result);
				if ($hesabix_id < 1) {
					throw new Exception(__('شناسه شخص در پاسخ API یافت نشد', 'hesabix-v2'));
				}

				set_transient($cache_key, $hesabix_id, 90 * DAY_IN_SECONDS);

				$execution_time = microtime(true) - $start_time;

				Hesabix_V2_Log_Service::info('Guest customer created', array(
					'entity_type' => 'customer',
					'entity_id' => 0,
					'order_id' => $order_id,
					'hesabix_id' => $hesabix_id,
					'execution_time' => $execution_time,
				));

				return array(
					'success' => true,
					'hesabix_id' => $hesabix_id,
					'message' => __('مشتری مهمان ایجاد شد', 'hesabix-v2'),
				);
			}

			throw new Exception($api_last_result['message'] ?? __('خطا در ایجاد مشتری', 'hesabix-v2'));

		} catch (Exception $e) {
			$execution_time = microtime(true) - $start_time;

			$elog = array(
				'entity_type' => 'customer',
				'entity_id' => 0,
				'order_id' => $order_id,
				'error' => $e->getMessage(),
				'execution_time' => $execution_time,
			);
			if ($wc_payload_for_log !== null) {
				$elog['request'] = array(
					'direction' => 'woocommerce_payload',
					'entity' => 'guest_customer',
					'order_id' => $order_id,
					'json_body' => $wc_payload_for_log,
				);
			}
			if (is_array($api_last_result)) {
				$elog['response'] = array(
					'direction' => 'hesabix_api',
					'decoded' => $api_last_result,
				);
			}
			Hesabix_V2_Log_Service::error('Guest customer creation failed', $elog);

			if ($order_id > 0 && strpos($e->getMessage(), __('سفارش یافت نشد', 'hesabix-v2')) === false) {
				Hesabix_V2_Queue_Service::enqueue('order', $order_id, 'sync_order');
			}

			return array(
				'success' => false,
				'message' => $e->getMessage(),
			);
		}
	}

	/**
	 * کلید کش ترنزینت برای اشخاص مهمان با همان ایمیل/موبایل.
	 *
	 * @param WC_Order $order
	 * @return string
	 */
	private static function guest_contact_transient_key($order)
	{
		$email = mb_strtolower(trim((string) $order->get_billing_email()));
		$mobile = Hesabix_V2_Validation::sanitize_mobile($order->get_billing_phone());
		if ($email !== '') {
			return 'hesabix_v2_gc_' . md5('e:' . $email);
		}
		if ($mobile !== '') {
			return 'hesabix_v2_gc_' . md5('m:' . $mobile);
		}

		return 'hesabix_v2_gc_' . md5('o:' . $order->get_id());
	}

	/**
	 * بدون تماس شبکهٔ تکی: آمادهٔ payload فاکتور برای bulk-upsert.
	 *
	 * @since 3.4.0
	 * @param int $order_id
	 * @return array{success?:bool,message?:string,order_id?:int,order?:WC_Order,person_id?:mixed,invoice_data?:array,is_new_invoice?:bool,hesabix_invoice_id?:int|null,fiscal_note?:string}
	 */
	private function prepare_order_bulk_invoice_without_api($order_id)
	{
		$order = wc_get_order($order_id);
		if (!$order) {
			return array(
				'success' => false,
				'message' => __('سفارش یافت نشد', 'hesabix-v2'),
			);
		}

		$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($this->api, $order->get_currency());
		if (!$gate['ok']) {
			return array(
				'success' => false,
				'message' => $gate['message'],
			);
		}

		$sync_settings = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		if (class_exists('Hesabix_V2_Order_Fiscal_Service')) {
			$fy_policy = isset($sync_settings['order_fiscal_year_date_policy'])
				? (string) $sync_settings['order_fiscal_year_date_policy']
				: 'keep';
			$fiscal = Hesabix_V2_Order_Fiscal_Service::resolve_for_sync($order, $fy_policy, $this->api);
			if (!empty($fiscal['skip'])) {
				$skip_msg = isset($fiscal['skip_message'])
					? (string) $fiscal['skip_message']
					: __('همگام‌سازی به‌دلیل سال مالی انجام نشد.', 'hesabix-v2');

				return array(
					'success' => false,
					'message' => $skip_msg,
				);
			}
		} else {
			$fiscal = array(
				'document_date' => null,
				'payment_date_ymd' => null,
				'note' => '',
			);
		}

		try {
			$create_customer_on_order = !empty($sync_settings['create_customer_on_order']);
			$customer_id = $order->get_customer_id();
			$person_id = null;

			if ($customer_id) {
				$person_id = $this->db->get_hesabix_id('customer', $customer_id);

				if (!$person_id) {
					if (!$create_customer_on_order) {
						throw new Exception(__('مشتری در حسابیکس وجود ندارد. گزینه «ایجاد مشتری از سفارش» را در تنظیمات فعال کنید.', 'hesabix-v2'));
					}
					$customer_result = $this->sync_customer($customer_id, $order_id);
					if ($customer_result['success']) {
						$person_id = $customer_result['hesabix_id'];
					} else {
						$msg = isset($customer_result['message']) ? (string) $customer_result['message'] : __('خطا در همگام‌سازی مشتری', 'hesabix-v2');
						throw new Exception($msg);
					}
				}
			} else {
				if (!$create_customer_on_order) {
					throw new Exception(__('برای ثبت سفارش مهمان، گزینه «ایجاد مشتری از سفارش» را در تنظیمات فعال کنید.', 'hesabix-v2'));
				}
				$guest_result = $this->sync_guest_customer($order_id);
				if ($guest_result['success']) {
					$person_id = $guest_result['hesabix_id'];
				} else {
					$msg = isset($guest_result['message']) ? (string) $guest_result['message'] : __('خطا در ایجاد مشتری مهمان', 'hesabix-v2');
					throw new Exception($msg);
				}
			}

			$fiscal_dates = array();
			if (!empty($fiscal['document_date'])) {
				$fiscal_dates['document_date'] = $fiscal['document_date'];
			}
			if (!empty($fiscal['payment_date_ymd'])) {
				$fiscal_dates['payment_date_ymd'] = $fiscal['payment_date_ymd'];
			}

			$invoice_data = apply_filters(
				'hesabix_v2_invoice_data',
				Hesabix_V2_Mapper::wc_order_to_invoice(
					$order,
					$person_id,
					$gate['factor'],
					$gate['currency_id'],
					$fiscal_dates ? $fiscal_dates : null
				),
				$order
			);

			self::assert_invoice_lines_have_warehouse_when_required($order, $invoice_data);

			$existing_mapping = $this->db->get_mapping('order', $order_id);
			$hid = null;
			if ($existing_mapping && !empty($existing_mapping['hesabix_id'])) {
				$hid = absint($existing_mapping['hesabix_id']);
			}

			return array(
				'success' => true,
				'order_id' => (int) $order_id,
				'order' => $order,
				'person_id' => $person_id,
				'invoice_data' => $invoice_data,
				'is_new_invoice' => !$existing_mapping,
				'hesabix_invoice_id' => $hid && $hid > 0 ? $hid : null,
				'fiscal_note' => isset($fiscal['note']) ? (string) $fiscal['note'] : '',
			);
		} catch (Exception $e) {
			return array(
				'success' => false,
				'message' => $e->getMessage(),
			);
		}
	}

	/**
	 * همگام‌سازی چند سفارش با چند فاکتور در یک یا چند تماس bulk به API.
	 *
	 * @since 3.4.0
	 * @param array<int> $order_ids
	 * @return array{success:int,failed:int,total:int,errors:array,per_order:array<int,array>}
	 */
	public function bulk_sync_orders(array $order_ids)
	{
		$res = array(
			'success' => 0,
			'failed' => 0,
			'total' => count($order_ids),
			'errors' => array(),
			'per_order' => array(),
		);

		$order_ids = array_values(array_unique(array_filter(array_map('absint', (array) $order_ids))));
		if (empty($order_ids)) {
			return $res;
		}

		$o = self::get_bulk_sync_options();
		$cap = isset($o['api_bulk_invoices_per_request'])
			? (int) $o['api_bulk_invoices_per_request']
			: 8;
		$cap = max(1, min(self::BULK_API_ITEMS_MAX_INVOICE, $cap));

		$queued = array();
		foreach ($order_ids as $oid) {
			$p = $this->prepare_order_bulk_invoice_without_api((int) $oid);
			if (empty($p['success'])) {
				$res['failed']++;
				$res['errors'][] = array(
					'order_id' => (int) $oid,
					'message' => isset($p['message']) ? (string) $p['message'] : '',
				);
				$res['per_order'][ (int) $oid ] = array(
					'success' => false,
					'message' => isset($p['message']) ? (string) $p['message'] : '',
				);

				continue;
			}

			if (class_exists('Hesabix_V2_Order_Sync_Meta') && Hesabix_V2_Order_Sync_Meta::is_pause_auto_sync((int) $oid)) {
				$res['per_order'][ (int) $oid ] = array(
					'success' => false,
					'skipped_pause' => true,
					'message' => __('رد شده — همگام‌سازی خودکار برای این سفارش متوقف است.', 'hesabix-v2'),
				);
				continue;
			}

			$queued[] = $p;
		}

		foreach (array_chunk($queued, $cap) as $chunk) {
			$items = array();
			$cref_to_oid = array();
			$cref_meta = array();

			foreach ($chunk as $prep) {
				$cref = 'wc_order:' . (int) $prep['order_id'];
				$items[] = array(
					'client_ref' => $cref,
					'invoice_id' => (!empty($prep['hesabix_invoice_id']) && absint($prep['hesabix_invoice_id']) > 0)
					? absint($prep['hesabix_invoice_id'])
					: null,
					'payload' => $prep['invoice_data'],
				);
				$cref_to_oid[ $cref ] = (int) $prep['order_id'];
				$cref_meta[ $cref ] = array(
					'is_new_invoice' => !empty($prep['is_new_invoice']),
					'fiscal_note' => isset($prep['fiscal_note']) ? (string) $prep['fiscal_note'] : '',
				);
			}

			if (empty($items)) {
				continue;
			}

			$t_inv = (int) max(120, min(900, ($cap * 5)));

			$api_out = $this->api->bulk_upsert_invoices(array('items' => $items), $t_inv);

			if (empty($api_out['success'])) {
				$fatal = isset($api_out['message']) ? (string) $api_out['message'] : __('خطای bulk فاکتور در API حسابیکس', 'hesabix-v2');
				foreach ($cref_to_oid as $oid_chunk) {
					$res['failed']++;
					$res['errors'][] = array('order_id' => (int) $oid_chunk, 'message' => $fatal);
					$res['per_order'][ (int) $oid_chunk ] = array(
						'success' => false,
						'message' => $fatal,
					);

					$o_fail = wc_get_order((int) $oid_chunk);
					if ($o_fail && class_exists('Hesabix_V2_Order_Sync_Meta')) {
						Hesabix_V2_Order_Sync_Meta::set_or_update_invoice_sync_error_note($o_fail, $fatal);
					}
				}
				continue;
			}

			$bundle = isset($api_out['data']) && is_array($api_out['data']) ? $api_out['data'] : array();
			$list = isset($bundle['results']) && is_array($bundle['results']) ? $bundle['results'] : array();

			foreach ($list as $row) {
				$cref = isset($row['client_ref']) ? (string) $row['client_ref'] : '';
				$oid = isset($cref_to_oid[ $cref ]) ? $cref_to_oid[ $cref ] : 0;
				if ($oid < 1 && preg_match('/^wc_order:(\d+)$/', $cref, $mx)) {
					$oid = absint($mx[1]);
				}
				$st = isset($row['status']) ? (string) $row['status'] : '';
				if (($st === 'created' || $st === 'updated') && !empty($row['invoice_id'])) {
					$hid = absint($row['invoice_id']);
					$oobj = wc_get_order($oid);
					if ($oobj && $hid > 0) {
						$this->db->save_mapping('order', $oid, null, $hid, 'invoice');
						if (class_exists('Hesabix_V2_Order_Sync_Meta')) {
							Hesabix_V2_Order_Sync_Meta::remove_order_system_note($oobj);
						}

						$meta_note = isset($cref_meta[ $cref ]) ? $cref_meta[ $cref ] : array();
						if (!empty($meta_note['is_new_invoice'])) {
							$oobj->add_order_note(
								sprintf(__('فاکتور در حسابیکس ایجاد شد. شناسه: %d', 'hesabix-v2'), $hid)
							);
						}
						if (!empty($meta_note['fiscal_note'])) {
							$oobj->add_order_note((string) $meta_note['fiscal_note']);
						}

						$res['success']++;
						$res['per_order'][ $oid ] = array(
							'success' => true,
							'message' => __('سفارش با موفقیت همگام‌سازی شد', 'hesabix-v2'),
							'hesabix_id' => $hid,
						);
					}
				} else {
					$msg = isset($row['message']) ? (string) $row['message'] : __('ناموفق', 'hesabix-v2');
					if ($oid > 0) {
						$res['failed']++;
						$res['errors'][] = array(
							'order_id' => $oid,
							'message' => $msg,
						);
						$res['per_order'][ $oid ] = array(
							'success' => false,
							'message' => $msg,
						);
						$o_fail = wc_get_order($oid);
						if ($o_fail && class_exists('Hesabix_V2_Order_Sync_Meta')) {
							Hesabix_V2_Order_Sync_Meta::set_or_update_invoice_sync_error_note($o_fail, $msg);
						}
					}
				}
			}
		}

		return $res;
	}

	/**
	 * Sync order (create invoice) to Hesabix
	 *
	 * @since    2.0.0
	 * @param    int    $order_id
	 * @return   array
	 */
	public function sync_order($order_id)
	{
		$start_time = microtime(true);

		$order = wc_get_order($order_id);
		if (!$order) {
			return array(
				'success' => false,
				'message' => __('سفارش یافت نشد', 'hesabix-v2'),
			);
		}

		$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($this->api, $order->get_currency());
		if (!$gate['ok']) {
			Hesabix_V2_Log_Service::error(
				'Order sync blocked — currency mismatch',
				array(
					'entity_type' => 'order',
					'entity_id' => $order_id,
					'error' => $gate['message'],
					'request' => array(
						'direction' => 'woocommerce_order',
						'order_id' => $order_id,
						'currency' => $order->get_currency(),
					),
					'response' => array(
						'direction' => 'policy',
						'detail' => $gate,
					),
				)
			);
			if (class_exists('Hesabix_V2_Order_Sync_Meta')) {
				Hesabix_V2_Order_Sync_Meta::set_or_update_order_system_note(
					$order,
					sprintf(__('همگام‌سازی حسابیکس متوقف شد (ارز): %s', 'hesabix-v2'), $gate['message'])
				);
			}

			return array(
				'success' => false,
				'message' => $gate['message'],
				'currency_blocked' => true,
			);
		}

		$sync_settings = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		if (class_exists('Hesabix_V2_Order_Fiscal_Service')) {
			$fy_policy = isset($sync_settings['order_fiscal_year_date_policy'])
				? (string) $sync_settings['order_fiscal_year_date_policy']
				: 'keep';
			$fiscal = Hesabix_V2_Order_Fiscal_Service::resolve_for_sync($order, $fy_policy, $this->api);
			if (!empty($fiscal['skip'])) {
				$skip_msg = isset($fiscal['skip_message'])
					? (string) $fiscal['skip_message']
					: __('همگام‌سازی به‌دلیل سال مالی انجام نشد.', 'hesabix-v2');
				Hesabix_V2_Log_Service::info(
					'Order sync skipped — outside current fiscal year (plugin setting)',
					array(
						'entity_type' => 'order',
						'entity_id' => $order_id,
						'detail' => $skip_msg,
					)
				);
				if (class_exists('Hesabix_V2_Order_Sync_Meta')) {
					Hesabix_V2_Order_Sync_Meta::set_or_update_order_system_note($order, $skip_msg);
				}

				return array(
					'success' => false,
					'message' => $skip_msg,
					'fiscal_year_skipped' => true,
				);
			}
		} else {
			$fiscal = array(
				'document_date' => null,
				'payment_date_ymd' => null,
				'note' => '',
			);
		}

		$wc_payload_for_log = null;
		$api_last_result = null;

		try {

			// Get or create customer (با توجه به تنظیم create_customer_on_order)
			$create_customer_on_order = !empty($sync_settings['create_customer_on_order']);
			$customer_id = $order->get_customer_id();
			$person_id = null;

			if ($customer_id) {
				// Registered customer
				$person_id = $this->db->get_hesabix_id('customer', $customer_id);

				if (!$person_id) {
					if (!$create_customer_on_order) {
						throw new Exception(__('مشتری در حسابیکس وجود ندارد. گزینه «ایجاد مشتری از سفارش» را در تنظیمات فعال کنید.', 'hesabix-v2'));
					}
					// Sync customer first
					$customer_result = $this->sync_customer($customer_id, $order_id);
					if ($customer_result['success']) {
						$person_id = $customer_result['hesabix_id'];
					} else {
						$msg = isset($customer_result['message']) ? (string) $customer_result['message'] : __('خطا در همگام‌سازی مشتری', 'hesabix-v2');
						throw new Exception($msg);
					}
				}
			} else {
				// Guest customer
				if (!$create_customer_on_order) {
					throw new Exception(__('برای ثبت سفارش مهمان، گزینه «ایجاد مشتری از سفارش» را در تنظیمات فعال کنید.', 'hesabix-v2'));
				}
				$guest_result = $this->sync_guest_customer($order_id);
				if ($guest_result['success']) {
					$person_id = $guest_result['hesabix_id'];
				} else {
					$msg = isset($guest_result['message']) ? (string) $guest_result['message'] : __('خطا در ایجاد مشتری مهمان', 'hesabix-v2');
					throw new Exception($msg);
				}
			}

			// Prepare invoice data
			$fiscal_dates = array();
			if (!empty($fiscal['document_date'])) {
				$fiscal_dates['document_date'] = $fiscal['document_date'];
			}
			if (!empty($fiscal['payment_date_ymd'])) {
				$fiscal_dates['payment_date_ymd'] = $fiscal['payment_date_ymd'];
			}

			$invoice_data = apply_filters(
				'hesabix_v2_invoice_data',
				Hesabix_V2_Mapper::wc_order_to_invoice(
					$order,
					$person_id,
					$gate['factor'],
					$gate['currency_id'],
					$fiscal_dates ? $fiscal_dates : null
				),
				$order
			);

			$wc_payload_for_log = $invoice_data;

			self::assert_invoice_lines_have_warehouse_when_required($order, $invoice_data);

			// Check if already synced
			$existing_mapping = $this->db->get_mapping('order', $order_id);
			$is_new_invoice = !$existing_mapping;

			if ($existing_mapping) {
				// Update existing invoice
				$api_last_result = $this->api->update_invoice($existing_mapping['hesabix_id'], $invoice_data);
			} else {
				// Create new invoice
				$api_last_result = $this->api->create_invoice($invoice_data);
			}

			if (isset($api_last_result['success']) && $api_last_result['success']) {
				$hesabix_id = $api_last_result['data']['id'];

				if (class_exists('Hesabix_V2_Order_Sync_Meta')) {
					Hesabix_V2_Order_Sync_Meta::remove_order_system_note($order);
				}

				// Save mapping
				$this->db->save_mapping(
					'order',
					$order_id,
					null,
					$hesabix_id,
					'invoice'
				);

				$execution_time = microtime(true) - $start_time;

				Hesabix_V2_Log_Service::info('Order synced successfully', array(
					'entity_type' => 'order',
					'entity_id' => $order_id,
					'hesabix_id' => $hesabix_id,
					'person_id' => $person_id,
					'execution_time' => $execution_time,
				));

				if ($is_new_invoice) {
					$order->add_order_note(
						sprintf(__('فاکتور در حسابیکس ایجاد شد. شناسه: %d', 'hesabix-v2'), $hesabix_id)
					);
				}
				if (!empty($fiscal['note'])) {
					$order->add_order_note((string) $fiscal['note']);
				}

				return array(
					'success' => true,
					'hesabix_id' => $hesabix_id,
					'message' => __('سفارش با موفقیت همگام‌سازی شد', 'hesabix-v2'),
				);
			} else {
				throw new Exception($api_last_result['message'] ?? __('خطا در همگام‌سازی', 'hesabix-v2'));
			}

		} catch (Exception $e) {
			$execution_time = microtime(true) - $start_time;

			$elog = array(
				'entity_type' => 'order',
				'entity_id' => $order_id,
				'error' => $e->getMessage(),
				'execution_time' => $execution_time,
			);
			if ($wc_payload_for_log !== null) {
				$elog['request'] = array(
					'direction' => 'woocommerce_payload',
					'entity' => 'order_invoice',
					'wc_order_number' => $order->get_order_number(),
					'json_body' => $wc_payload_for_log,
				);
			}
			if (is_array($api_last_result)) {
				$elog['response'] = array(
					'direction' => 'hesabix_api',
					'decoded' => $api_last_result,
				);
			}
			if ((int) $e->getCode() !== self::ERR_INVOICE_WAREHOUSE_PREFLIGHT) {
				$hint_msg = (string) $e->getMessage();
				if (
					stripos($hint_msg, 'warehouse') !== false
					|| preg_match('/انبار/u', $hint_msg) === 1
				) {
					$elog['resolution_hint_fa'] = __(
						'این پاسخ از API معمولاً یعنی حسابیکس برای خط انبارداری به warehouse_id نیاز داشته اما مقدار را نپذیرفته است. در تنظیمات افزونه، تب فاکتور، «انبار پیش‌فرض» و «انبار در خطوط فاکتور فروش» را بررسی کنید و payload ارسالی (json_body) را در همین رکورد لاگ ببینید.',
						'hesabix-v2'
					);
				}
				Hesabix_V2_Log_Service::error('Order sync failed', $elog);
			}

			$order_for_note = isset($order) ? $order : wc_get_order($order_id);
			if ($order_for_note && class_exists('Hesabix_V2_Order_Sync_Meta')) {
				Hesabix_V2_Order_Sync_Meta::set_or_update_invoice_sync_error_note($order_for_note, $e->getMessage());
			}

			$should_queue = $order_id > 0 && strpos($e->getMessage(), __('سفارش یافت نشد', 'hesabix-v2')) === false;
			if ($should_queue && strpos($e->getMessage(), __('هم‌خوان نیست', 'hesabix-v2')) !== false) {
				$should_queue = false;
			}
			if ($should_queue && strpos($e->getMessage(), __('لیست ارزهای کسب‌وکار', 'hesabix-v2')) !== false) {
				$should_queue = false;
			}
			if ($should_queue && strpos($e->getMessage(), __('ارز فروشگاه ووکامرس مشخص نیست', 'hesabix-v2')) !== false) {
				$should_queue = false;
			}
			if ($should_queue && (int) $e->getCode() === self::ERR_INVOICE_WAREHOUSE_PREFLIGHT) {
				$should_queue = false;
			}

			if ($should_queue) {
				Hesabix_V2_Queue_Service::enqueue('order', $order_id, 'sync_order');
			}

			return array(
				'success' => false,
				'message' => $e->getMessage(),
			);
		}
	}

	/**
	 * وقتی post_inventory فعال است، هر خط با movement برابر out باید warehouse_id در extra_info داشته باشد.
	 *
	 * @param WC_Order $order
	 * @param array    $invoice_data
	 * @return void
	 * @throws Exception با کد {@see self::ERR_INVOICE_WAREHOUSE_PREFLIGHT}
	 */
	private static function assert_invoice_lines_have_warehouse_when_required($order, array $invoice_data)
	{
		if (!is_object($order) || !($order instanceof WC_Order)) {
			return;
		}

		$extra = isset($invoice_data['extra_info']) && is_array($invoice_data['extra_info']) ? $invoice_data['extra_info'] : array();
		if (empty($extra['post_inventory'])) {
			return;
		}

		$lines = isset($invoice_data['lines']) && is_array($invoice_data['lines']) ? $invoice_data['lines'] : array();
		$missing = array();

		foreach ($lines as $i => $line) {
			if (!is_array($line)) {
				continue;
			}
			$ei = isset($line['extra_info']) && is_array($line['extra_info']) ? $line['extra_info'] : array();
			if (($ei['movement'] ?? '') !== 'out') {
				continue;
			}
			$wid = isset($ei['warehouse_id']) ? (int) $ei['warehouse_id'] : 0;
			if ($wid < 1) {
				$missing[] = array(
					'line_index' => (int) $i,
					'hesabix_product_id' => isset($line['product_id']) ? (int) $line['product_id'] : 0,
					'description' => isset($line['description']) && is_string($line['description'])
						? mb_substr($line['description'], 0, 200)
						: '',
				);
			}
		}

		if ($missing === array()) {
			return;
		}

		$resolved = Hesabix_V2_Invoice_Warehouse_Service::resolve_warehouse_id_for_order($order);
		$resolved_log = ($resolved !== null && $resolved !== '') ? (int) $resolved : null;
		$cfg = Hesabix_V2_Invoice_Warehouse_Service::get_config();
		$default_opt = get_option('hesabix_v2_default_warehouse_id', '');
		$default_log = ($default_opt !== '' && $default_opt !== null) ? absint($default_opt) : null;

		Hesabix_V2_Log_Service::warning(
			__('فاکتور ارسال نشد — خطوط خروج از انبار بدون شناسهٔ انبار (warehouse_id)', 'hesabix-v2'),
			array(
				'entity_type' => 'order',
				'entity_id' => $order->get_id(),
				'wc_order_number' => $order->get_order_number(),
				'detail_title_fa' => __(
					'حسابیکس برای فاکتورهای با ثبت موجودی، برای هر خط خروج از انبار به warehouse_id نیاز دارد.',
					'hesabix-v2'
				),
				'resolution' => 'invoice_warehouse_preflight',
				'post_inventory' => true,
				'invoice_warehouse_mode' => isset($cfg['resolution']) ? (string) $cfg['resolution'] : '',
				'default_warehouse_id_option' => $default_log,
				'resolved_warehouse_for_order' => $resolved_log,
				'shipping_methods' => self::summarize_order_shipping_method_keys_for_log($order),
				'hint_configure_fa' => __(
					'مسیر پیشنهادی: حسابیکس ووکامرس ← تنظیمات ← تب فاکتور — «انبار پیش‌فرض» را انتخاب کنید، یا در بخش «انبار در خطوط فاکتور فروش» قانون منطبق با روش حمل یا منطقهٔ ارسال همین سفارش تعریف کنید.',
					'hesabix-v2'
				),
				'lines_missing_warehouse_id' => $missing,
				'direction' => 'woocommerce_payload',
				'request_preview' => array(
					'lines_count' => count($lines),
				),
			)
		);

		$msg = __(
			'ثبت موجودی برای فاکتور فعال است اما حسابیکس برای یک یا چند خط خروج از انبار warehouse_id دریافت نکرده است. در تنظیمات افزونه، تب فاکتور، انبار پیش‌فرض یا قوانین انبار را تکمیل کنید.',
			'hesabix-v2'
		);

		throw new Exception($msg, self::ERR_INVOICE_WAREHOUSE_PREFLIGHT);
	}

	/**
	 * خلاصهٔ روش‌های حمل برای توضیح در لاگ.
	 *
	 * @param WC_Order $order
	 * @return array<int, string>
	 */
	private static function summarize_order_shipping_method_keys_for_log($order)
	{
		if (!is_object($order) || !($order instanceof WC_Order)) {
			return array();
		}

		$keys = array();
		foreach ($order->get_items('shipping') as $ship_item) {
			if (!$ship_item instanceof WC_Order_Item_Shipping) {
				continue;
			}
			$mid = sanitize_title((string) $ship_item->get_method_id());
			$iid = preg_replace('/[^0-9]/', '', (string) $ship_item->get_instance_id());
			if ($mid !== '') {
				$keys[] = $mid . ':' . $iid;
			}
		}

		return array_values(array_unique($keys));
	}

	/**
	 * شناسهٔ مرجع یک سطر bulk برای هماهنگ‌کردن پاسخ API با WC (ساده: والد منطقی ۰، موجودیت = شناسهٔ محصول).
	 *
	 * @since 3.4.0
	 * @param int $parent_or_zero برای واریانت شناسهٔ محصول متغیر؛ برای محصول ساده ۰.
	 * @param int $entity_wc_id  همان wc_id ذخیره‌شده در نگاشت (محصول یا واریانت).
	 * @return string
	 */
	private static function product_bulk_client_ref($parent_or_zero, $entity_wc_id)
	{
		return 'wc_pv:' . (int) $parent_or_zero . ':' . (int) $entity_wc_id;
	}

	/**
	 * صف‌بندی همگام تکی مانند خطای سنتی sync_product (بدون تکرار برای «محصول یافت نشد»).
	 *
	 * @since 3.4.0
	 * @param int         $wc_id
	 * @param int|null    $wc_parent_id
	 * @param string      $error_message
	 * @return void
	 */
	private static function enqueue_product_retry_from_bulk_failure($wc_id, $wc_parent_id, $error_message)
	{
		$m = (string) $error_message;
		if (strpos($m, __('محصول یافت نشد', 'hesabix-v2')) !== false) {
			return;
		}

		$qpayload = ((int) $wc_parent_id) > 0
			? array('parent_id' => (int) $wc_parent_id)
			: null;

		Hesabix_V2_Queue_Service::enqueue('product', (int) $wc_id, 'sync_product', $qpayload);
	}

	/**
	 * فقط شناسه‌های محصول والد ووکامرس را به فهرست سطرهای bulk (محصول یا هر واریانت) گسترده می‌کند.
	 *
	 * @since 3.4.0
	 * @param array<int|string> $parent_product_ids
	 * @return array<int, array<string, mixed>>
	 */
	private function expand_parent_product_ids_for_bulk_sync(array $parent_product_ids)
	{
		$list = array();

		foreach (array_unique(array_filter(array_map('absint', (array) $parent_product_ids))) as $product_id) {
			if ($product_id < 1) {
				continue;
			}

			$product = wc_get_product($product_id);
			if (!$product) {
				$list[] = array(
					'kind' => 'missing_parent',
					'product_id' => $product_id,
				);
				continue;
			}

			if ($product->is_type('variable')) {
				$variation_ids = $product->get_children();
				if (empty($variation_ids)) {
					$list[] = array(
						'kind' => 'empty_variable',
						'product_id' => $product_id,
					);
					continue;
				}

				foreach ($variation_ids as $variation_id) {
					$vid = absint($variation_id);
					if ($vid > 0) {
						$list[] = array(
							'kind' => 'row',
							'parent_id' => $product_id,
							'variation_id' => $vid,
						);
					}
				}

				continue;
			}

			$list[] = array(
				'kind' => 'row',
				'parent_id' => $product_id,
				'variation_id' => null,
			);
		}

		return $list;
	}

	/**
	 * ساخت یک آیتم bulk-upsert برای API کالا (بدون تماس شبکه)، با توجه به نگاشت فعلی.
	 *
	 * @since 3.4.0
	 * @param int                       $parent_product_id شناسهٔ محصول والد برای واریانت؛ برای محصول ساده همان wc_id محصول است.
	 * @param int|null                  $variation_id برای محصول ساده null.
	 * @param array<string, mixed>      $gate خروجی {@see Hesabix_V2_Currency_Service::evaluate_currency_sync()} با ok=true
	 * @return array{ok:bool,message?:string,item?:array,wc_id?:int,wc_parent_id:?int}
	 */
	private function collect_product_bulk_item($parent_product_id, $variation_id, array $gate)
	{
		$pid = absint($parent_product_id);

		if ($variation_id !== null && (int) $variation_id !== 0) {
			$vid = absint($variation_id);
			$product = wc_get_product($vid);
			$parent_product = wc_get_product($pid);

			if (!$product || !$parent_product) {
				return array(
					'ok' => false,
					'message' => __('محصول یافت نشد', 'hesabix-v2'),
					'wc_id' => $vid > 0 ? $vid : $pid,
					'wc_parent_id' => $pid,
				);
			}

			$product_data = Hesabix_V2_Mapper::wc_variation_to_api($parent_product, $product, $pid, $gate['factor']);
			$wc_id = $vid;
			$wc_parent_id = $pid;
			$cref_zone = $pid;
		} else {
			$product = wc_get_product($pid);

			if (!$product) {
				return array(
					'ok' => false,
					'message' => __('محصول یافت نشد', 'hesabix-v2'),
					'wc_id' => $pid,
					'wc_parent_id' => null,
				);
			}

			$product_data = Hesabix_V2_Mapper::wc_product_to_api($product, $pid, $gate['factor']);
			$wc_id = $pid;
			$wc_parent_id = null;
			$cref_zone = 0;
		}

		$sync_settings = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		if (empty($sync_settings['sync_product_price'])) {
			unset($product_data['base_sales_price']);
		}

		if (empty($sync_settings['sync_product_stock'])) {
			$product_data['track_inventory'] = false;
		} else {
			$policy = isset($sync_settings['track_inventory_policy']) ? (string) $sync_settings['track_inventory_policy'] : 'wc';
			$product_data['track_inventory'] = Hesabix_V2_Mapper::resolve_track_inventory_by_policy($product, $policy);
		}

		$existing_mapping = $this->db->get_mapping('product', $wc_id, $wc_parent_id);

		$hx_pid = null;
		if (!empty($existing_mapping['hesabix_id'])) {
			$h = absint($existing_mapping['hesabix_id']);
			if ($h > 0) {
				$hx_pid = $h;
			}
		}

		$item = array(
			'client_ref' => self::product_bulk_client_ref($cref_zone, $wc_id),
			'payload' => $product_data,
		);

		if ($hx_pid !== null) {
			$item['product_id'] = $hx_pid;
		}

		return array(
			'ok' => true,
			'item' => $item,
			'wc_id' => $wc_id,
			'wc_parent_id' => $wc_parent_id,
		);
	}

	/**
	 * Bulk sync products via یک یا چند تماس bulk-upsert به API حسابیکس (ساده‌ها و واریانت‌ها).
	 *
	 * @since    2.0.0
	 * @param    array<int|string>    $product_ids شناسهٔ پست‌های والد منتشرشده در ووکامرس
	 * @return   array{success:int,failed:int,total:int,errors:array}
	 */
	public function bulk_sync_products($product_ids)
	{
		$results = array(
			'success' => 0,
			'failed' => 0,
			'total' => 0,
			'errors' => array(),
		);

		$plans = $this->expand_parent_product_ids_for_bulk_sync((array) $product_ids);
		$results['total'] = count($plans);

		if (empty($plans)) {
			return $results;
		}

		$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($this->api, null);

		if (!$gate['ok']) {
			$gmsg = isset($gate['message']) ? (string) $gate['message'] : '';

			foreach ($plans as $pl) {
				if (($pl['kind'] ?? '') === 'missing_parent') {
					$results['failed']++;
					$results['errors'][] = array(
						'product_id' => (int) ($pl['product_id'] ?? 0),
						'message' => __('محصول یافت نشد', 'hesabix-v2'),
					);
					continue;
				}

				if (($pl['kind'] ?? '') === 'empty_variable') {
					$results['failed']++;
					$results['errors'][] = array(
						'product_id' => (int) ($pl['product_id'] ?? 0),
						'message' => __('محصول متغیر بدون واریانت', 'hesabix-v2'),
					);
					continue;
				}

				$parent_id = (int) ($pl['parent_id'] ?? 0);
				$vid = isset($pl['variation_id']) ? (int) $pl['variation_id'] : 0;

				$row_err = array('message' => $gmsg);
				if ($vid > 0) {
					$row_err['product_id'] = $parent_id;
					$row_err['variation_id'] = $vid;
				} else {
					$row_err['product_id'] = $parent_id;
				}

				$results['failed']++;
				$results['errors'][] = $row_err;
			}

			return $results;
		}

		$rows = array();

		foreach ($plans as $pl) {
			if (($pl['kind'] ?? '') === 'missing_parent') {
				$results['failed']++;
				$results['errors'][] = array(
					'product_id' => (int) ($pl['product_id'] ?? 0),
					'message' => __('محصول یافت نشد', 'hesabix-v2'),
				);
				continue;
			}

			if (($pl['kind'] ?? '') === 'empty_variable') {
				$results['failed']++;
				$results['errors'][] = array(
					'product_id' => (int) ($pl['product_id'] ?? 0),
					'message' => __('محصول متغیر بدون واریانت', 'hesabix-v2'),
				);
				continue;
			}

			$rows[] = $pl;
		}

		$o = self::get_bulk_sync_options();
		$cap = isset($o['api_bulk_products_per_request']) ? (int) $o['api_bulk_products_per_request'] : 20;
		$cap = max(3, min(self::BULK_API_ITEMS_MAX_PRODUCT, $cap));

		foreach (array_chunk($rows, $cap) as $chunk_plans) {
			$items = array();
			$cref_meta = array();

			foreach ($chunk_plans as $rp) {
				$variation_id = isset($rp['variation_id']) && (int) $rp['variation_id'] > 0
					? (int) $rp['variation_id']
					: null;

				$collected = $this->collect_product_bulk_item((int) ($rp['parent_id'] ?? 0), $variation_id, $gate);

				if (empty($collected['ok'])) {
					$m = isset($collected['message']) ? (string) $collected['message'] : '';

					$wc_id_fail = isset($collected['wc_id']) ? (int) $collected['wc_id'] : 0;
					$wc_par_fail = isset($collected['wc_parent_id'])
						? $collected['wc_parent_id']
						: null;

					if ($variation_id !== null && $variation_id > 0) {
						$results['errors'][] = array(
							'product_id' => (int) ($rp['parent_id'] ?? 0),
							'variation_id' => $variation_id,
							'message' => $m,
						);
					} else {
						$results['errors'][] = array(
							'product_id' => (int) ($rp['parent_id'] ?? 0),
							'message' => $m,
						);
					}

					$results['failed']++;

					if ($wc_id_fail > 0) {
						self::enqueue_product_retry_from_bulk_failure($wc_id_fail, $wc_par_fail, $m);
					}

					continue;
				}

				$cref = isset($collected['item']['client_ref']) ? (string) $collected['item']['client_ref'] : '';
				if ($cref === '') {
					continue;
				}

				$cref_meta[ $cref ] = array(
					'wc_id' => (int) $collected['wc_id'],
					'wc_parent_id' => isset($collected['wc_parent_id'])
						? $collected['wc_parent_id']
						: null,
				);
				$items[] = $collected['item'];
			}

			if ($items === array()) {
				continue;
			}

			$items = apply_filters('hesabix_v2_bulk_upsert_products_items_before_api', $items, $chunk_plans, $this->api);

			$t_out = max(90, min(900, ($cap * 5)));

			$api_res = $this->api->bulk_upsert_products(
				array(
					'items' => $items,
					'create_if_update_missing' => true,
				),
				$t_out
			);

			if (empty($api_res['success'])) {
				$fatal = isset($api_res['message'])
					? (string) $api_res['message']
					: __('خطای bulk کالا در API حسابیکس', 'hesabix-v2');

				Hesabix_V2_Log_Service::error(
					'Product bulk-sync API chunk failed',
					array(
						'entity_type' => 'product',
						'bulk_products' => true,
						'items_in_chunk' => count($cref_meta),
						'direction' => 'hesabix_api',
						'error' => $fatal,
					)
				);

				foreach ($cref_meta as $meta) {
					$wid = isset($meta['wc_id']) ? (int) $meta['wc_id'] : 0;
					if ($wid < 1) {
						continue;
					}

					$wc_parent_ok = isset($meta['wc_parent_id']) ? $meta['wc_parent_id'] : null;

					if ($wc_parent_ok !== null && (int) $wc_parent_ok > 0) {
						$p = (int) $wc_parent_ok;
						$results['errors'][] = array(
							'product_id' => $p,
							'variation_id' => $wid,
							'message' => $fatal,
						);
					} else {
						$results['errors'][] = array(
							'product_id' => $wid,
							'message' => $fatal,
						);
					}

					$results['failed']++;
					self::enqueue_product_retry_from_bulk_failure($wid, $wc_parent_ok, $fatal);
				}

				continue;
			}

			$data_bundle = isset($api_res['data']) && is_array($api_res['data'])
				? $api_res['data']
				: array();

			$result_rows = isset($data_bundle['results']) && is_array($data_bundle['results'])
				? $data_bundle['results']
				: array();

			foreach ($result_rows as $row) {
				if (!is_array($row)) {
					continue;
				}

				$cref_raw = isset($row['client_ref']) ? trim((string) $row['client_ref']) : '';

				$resolved = null;

				if ($cref_raw !== '' && isset($cref_meta[ $cref_raw ])) {
					$resolved = $cref_meta[ $cref_raw ];
				} elseif ($cref_raw !== '' && preg_match('/^wc_pv:(\d+):(\d+)$/', $cref_raw, $xm)) {
					$p_zone = absint($xm[1]);
					$e_id = absint($xm[2]);
					if ($p_zone === 0) {
						$resolved = array('wc_id' => $e_id, 'wc_parent_id' => null);
					} else {
						$resolved = array('wc_id' => $e_id, 'wc_parent_id' => $p_zone);
					}
				}

				if ($resolved === null || empty($resolved['wc_id'])) {
					continue;
				}

				if ($cref_raw !== '' && isset($cref_meta[ $cref_raw ])) {
					unset($cref_meta[ $cref_raw ]);
				}

				$wid2 = absint($resolved['wc_id']);
				$wp2 = isset($resolved['wc_parent_id']) ? $resolved['wc_parent_id'] : null;

				$status = isset($row['status']) ? (string) $row['status'] : '';

				if (($status === 'created' || $status === 'updated')
					&& !empty($row['product_id'])
					&& absint($row['product_id']) > 0
				) {
					$h_id = absint($row['product_id']);

					$this->db->save_mapping(
						'product',
						$wid2,
						$wp2,
						$h_id,
						'product',
						array('synced_at' => current_time('mysql'))
					);

					$results['success']++;

					Hesabix_V2_Log_Service::info(
						'Product synced successfully (bulk)',
						array(
							'entity_type' => 'product',
							'entity_id' => $wid2,
							'hesabix_id' => $h_id,
						)
					);

					continue;
				}

				$mf = isset($row['message']) ? (string) $row['message'] : __('ناموفق', 'hesabix-v2');

				if ($wp2 !== null && (int) $wp2 > 0) {
					$results['errors'][] = array(
						'product_id' => (int) $wp2,
						'variation_id' => $wid2,
						'message' => $mf,
					);
				} else {
					$results['errors'][] = array(
						'product_id' => $wid2,
						'message' => $mf,
					);
				}

				$results['failed']++;
				self::enqueue_product_retry_from_bulk_failure($wid2, $wp2, $mf);

				Hesabix_V2_Log_Service::error(
					'Product bulk-sync row failed',
					array(
						'entity_type' => 'product',
						'entity_id' => $wid2,
						'error' => $mf,
						'direction' => 'hesabix_api',
						'bulk_products' => true,
					)
				);
			}
		}

		return $results;
	}

	/**
	 * یک مرحلهٔ همگام‌سازی دسته‌های product_cat ووکامرس (شامل دسته‌های بدون محصول).
	 *
	 * @since 2.0.8
	 * @param int $offset
	 * @param int $batch_size
	 * @return array<string,mixed>
	 */
	public function bulk_sync_wc_categories_chunk($offset, $batch_size)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return array(
				'success' => false,
				'message' => __('ابتدا اتصال را از تنظیمات یا ویزارد کامل کنید.', 'hesabix-v2'),
			);
		}

		return Hesabix_V2_Mapper::bulk_sync_wc_product_categories_chunk($offset, $batch_size);
	}

	/**
	 * Bulk sync customers
	 *
	 * @since    2.0.0
	 * @param    array    $customer_ids
	 * @return   array
	 */
	public function bulk_sync_customers($customer_ids)
	{
		$results = array(
			'success' => 0,
			'failed' => 0,
			'total' => count($customer_ids),
			'errors' => array(),
			'per_customer' => array(),
		);

		$ids = array_values(array_unique(array_filter(array_map('absint', (array) $customer_ids))));
		if (empty($ids)) {
			return $results;
		}

		$results['total'] = count($ids);

		foreach ($ids as $cid_init) {
			$results['per_customer'][ (int) $cid_init ] = array(
				'success' => false,
				'message' => '',
			);
		}

		$o = self::get_bulk_sync_options();
		$cap = isset($o['api_bulk_persons_per_request']) ? (int) $o['api_bulk_persons_per_request'] : 35;
		$cap = max(5, min(self::BULK_API_ITEMS_MAX_PERSON, $cap));

		foreach (array_chunk($ids, $cap) as $chunk) {
			$cid_by_ref = array();
			$items = array();

			foreach ($chunk as $customer_id) {
				$item_data = $this->collect_customer_bulk_item((int) $customer_id, null);

				if (empty($item_data['ok'])) {
					$results['failed']++;
					$row_err = array(
						'customer_id' => (int) $customer_id,
						'message' => isset($item_data['message']) ? (string) $item_data['message'] : '',
					);
					$results['errors'][] = $row_err;
					$results['per_customer'][ (int) $customer_id ] = array(
						'success' => false,
						'message' => $row_err['message'],
					);

					continue;
				}

				$cref = isset($item_data['item']['client_ref']) ? (string) $item_data['item']['client_ref'] : '';
				if ($cref !== '') {
					$cid_by_ref[ $cref ] = (int) $customer_id;
				}
				$items[] = $item_data['item'];
			}

			if (empty($items)) {
				continue;
			}

			$items = apply_filters('hesabix_v2_bulk_upsert_persons_items_before_api', $items, $chunk, $this->api);

			$t_per = (int) max(90, min(900, ($cap * 3)));

			$api_res = $this->api->bulk_upsert_persons(
				array(
					'items' => $items,
					'create_if_update_missing' => true,
				),
				$t_per
			);

			if (empty($api_res['success'])) {
				$m = isset($api_res['message']) ? (string) $api_res['message'] : __('خطای bulk شخص در API', 'hesabix-v2');

				foreach ($cid_by_ref as $wc_id_mapped) {
					$wid = absint($wc_id_mapped);

					if (empty($results['per_customer'][ $wid ]) || empty($results['per_customer'][ $wid ]['success'])) {
						$results['failed']++;
						$results['errors'][] = array('customer_id' => $wid, 'message' => $m);
						$results['per_customer'][ $wid ] = array('success' => false, 'message' => $m);
					}
				}
				continue;
			}

			$bundle = isset($api_res['data']) && is_array($api_res['data']) ? $api_res['data'] : array();
			$list = isset($bundle['results']) && is_array($bundle['results']) ? $bundle['results'] : array();

			foreach ($list as $row) {
				$cref3 = isset($row['client_ref']) ? (string) $row['client_ref'] : '';
				if ($cref3 === '' || empty($cid_by_ref[ $cref3 ])) {
					continue;
				}

				$wc_id = (int) $cid_by_ref[ $cref3 ];
				if ($wc_id < 1) {
					continue;
				}

				$status = isset($row['status']) ? (string) $row['status'] : '';

				if ($status === 'created' || $status === 'updated') {
					if (!empty($row['person_id'])) {
						$hid = absint($row['person_id']);
						if ($hid > 0) {
							$this->db->save_mapping('customer', $wc_id, null, $hid, 'person');

							Hesabix_V2_Log_Service::info('Customer synced (bulk)', array(
								'entity_type' => 'customer',
								'entity_id' => $wc_id,
								'hesabix_id' => $hid,
							));

							$results['success']++;
							$results['per_customer'][ $wc_id ] = array(
								'success' => true,
								'message' => __('مشتری با موفقیت همگام‌سازی شد', 'hesabix-v2'),
							);

							continue;
						}
					}
				}

				if (!empty($results['per_customer'][ $wc_id ]['success'])) {
					continue;
				}

				$mf = isset($row['message']) ? (string) $row['message'] : __('ناموفق', 'hesabix-v2');

				$results['failed']++;
				$results['errors'][] = array('customer_id' => $wc_id, 'message' => $mf);
				$results['per_customer'][ $wc_id ] = array(
					'success' => false,
					'message' => $mf,
				);
			}
		}

		return $results;
	}

	/**
	 * ساخت ورودی bulk-upsert برای یک مشتری ووکامرس.
	 *
	 * @param int           $customer_id
	 * @param WC_Order|null $context_order
	 * @return array{ok:bool, message:string, item?:array<string,mixed>}
	 */
	private function collect_customer_bulk_item($customer_id, $context_order = null)
	{
		$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($this->api, null);
		if (!$gate['ok']) {
			Hesabix_V2_Log_Service::warning('Customer bulk blocked — currency mismatch', array(
				'entity_type' => 'customer',
				'entity_id' => $customer_id,
				'message' => $gate['message'],
			));

			return array(
				'ok' => false,
				'message' => $gate['message'],
			);
		}

		$customer = new WC_Customer($customer_id);
		if (!$customer->get_id()) {
			return array(
				'ok' => false,
				'message' => __('مشتری یافت نشد', 'hesabix-v2'),
			);
		}

		$customer_data = apply_filters(
			'hesabix_v2_customer_data',
			Hesabix_V2_Mapper::wc_customer_to_api($customer, $context_order),
			$customer,
			$context_order
		);

		$mapping = $this->db->get_mapping('customer', $customer_id);
		$hid = null;

		if ($mapping && !empty($mapping['hesabix_id'])) {
			$hid = absint($mapping['hesabix_id']);
		}

		return array(
			'ok' => true,
			'message' => '',
			'item' => array(
				'client_ref' => 'wc_customer:' . (int) $customer_id,
				'person_id' => $hid && $hid > 0 ? $hid : null,
				'payload' => $customer_data,
			),
		);
	}

	/**
	 * یک مرحله از واردات اشخاص حسابیکس → ووکامرس (چند صفحهٔ API در هر درخواست AJAX).
	 *
	 * @since 2.0.7
	 * @param int  $skip ابتدای skip برای search_persons در این مرحله.
	 * @param bool $create_missing
	 * @param int  $take اندازهٔ صفحه API.
	 * @param int  $pages_to_process حداکثر تعداد صفحهٔ پشت‌سرهم در همین درخواست.
	 * @return array{success:bool, message?:string, chunk_stats?:array, next_skip?:int, done?:bool, pages_fetched?:int}
	 */
	public function import_customers_from_hesabix_chunk($skip, $create_missing, $take, $pages_to_process)
	{
		$stats = array(
			'matched_updated' => 0,
			'created' => 0,
			'skipped' => 0,
			'failed' => 0,
			'total_processed' => 0,
		);

		$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($this->api, null);
		if (!$gate['ok']) {
			return array(
				'success' => false,
				'message' => $gate['message'],
				'chunk_stats' => $stats,
				'next_skip' => (int) $skip,
				'done' => false,
			);
		}

		$take = max(10, min(200, absint($take)));
		$pages_to_process = max(1, min(50, absint($pages_to_process)));
		$new_skip = max(0, absint($skip));
		$pages_fetched = 0;
		$done = false;

		for ($step = 0; $step < $pages_to_process && ! $done; $step++) {
			$res = $this->api->search_persons(
				array(
					'take' => $take,
					'skip' => $new_skip,
					'sort_by' => 'id',
					'sort_desc' => false,
				)
			);

			if (empty($res['success'])) {
				return array(
					'success' => false,
					'message' => isset($res['message']) ? $res['message'] : __('خطا در دریافت لیست اشخاص', 'hesabix-v2'),
					'chunk_stats' => $stats,
					'next_skip' => $new_skip,
					'done' => false,
					'pages_fetched' => $pages_fetched,
				);
			}

			$items = isset($res['data']['items']) && is_array($res['data']['items']) ? $res['data']['items'] : array();
			$pages_fetched++;

			if (empty($items)) {
				$done = true;
				break;
			}

			foreach ($items as $row) {
				$stats['total_processed']++;
				$r = $this->import_single_person_row($row, (bool) $create_missing);
				if (isset($stats[ $r['status'] ])) {
					$stats[ $r['status'] ]++;
				}
			}

			$new_skip += count($items);
			if (count($items) < $take) {
				$done = true;
			}
		}

		return array(
			'success' => true,
			'message' => __('مرحله واردات انجام شد.', 'hesabix-v2'),
			'chunk_stats' => $stats,
			'next_skip' => $new_skip,
			'done' => $done,
			'pages_fetched' => $pages_fetched,
		);
	}
	/**
	 * @param array $p
	 * @param bool  $create_missing
	 * @return array{status:string}
	 */
	private function import_single_person_row(array $p, $create_missing)
	{
		if (!apply_filters('hesabix_v2_should_import_person_row', true, $p)) {
			return array('status' => 'skipped');
		}

		$hid = isset($p['id']) ? (int) $p['id'] : 0;
		if ($hid < 1) {
			return array('status' => 'skipped');
		}

		if (!self::person_row_is_customer_like($p)) {
			return array('status' => 'skipped');
		}

		$email_val = isset($p['email']) ? Hesabix_V2_Validation::sanitize_email((string) $p['email']) : null;
		if ($email_val && strpos($email_val, 'woocommerce-placeholder') !== false) {
			return array('status' => 'skipped');
		}

		$mobile_val = isset($p['mobile']) ? Hesabix_V2_Validation::sanitize_mobile((string) $p['mobile']) : null;

		if (!$email_val && !$mobile_val) {
			return array('status' => 'skipped');
		}

		$uid = Hesabix_V2_Customer_Service::find_user_id_by_email_or_mobile($email_val, $mobile_val);

		if ($uid > 0) {
			Hesabix_V2_Mapper::apply_hesabix_person_to_wc_customer($uid, $p);
			$this->db->save_mapping('customer', $uid, null, $hid, 'person');
			return array('status' => 'matched_updated');
		}

		if ($create_missing && $email_val && is_email($email_val)) {
			if (email_exists($email_val)) {
				return array('status' => 'skipped');
			}

			$username = self::generate_username_from_email($email_val);
			$password = wp_generate_password(20, true);
			$new_id = wc_create_new_customer($email_val, $username, $password);

			if (is_wp_error($new_id)) {
				Hesabix_V2_Log_Service::warning(
					'Import customer create failed',
					array(
						'entity_type' => 'customer_import',
						'hesabix_id' => $hid,
						'error' => $new_id->get_error_message(),
					)
				);
				return array('status' => 'failed');
			}

			Hesabix_V2_Mapper::apply_hesabix_person_to_wc_customer((int) $new_id, $p);
			$this->db->save_mapping('customer', (int) $new_id, null, $hid, 'person');

			Hesabix_V2_Log_Service::info(
				'Customer imported from Hesabix',
				array(
					'entity_type' => 'customer_import',
					'wc_user_id' => (int) $new_id,
					'hesabix_id' => $hid,
				)
			);

			return array('status' => 'created');
		}

		return array('status' => 'skipped');
	}

	/**
	 * @param array $p
	 * @return bool
	 */
	private static function person_row_is_customer_like(array $p)
	{
		$types = isset($p['person_types']) && is_array($p['person_types']) ? $p['person_types'] : array();
		if (!empty($p['person_type'])) {
			$types[] = $p['person_type'];
		}
		if (empty($types)) {
			return true;
		}

		foreach ($types as $t) {
			$ts = mb_strtolower(trim((string) $t));
			if (
				$ts === 'customer'
				|| $ts === 'buyer'
				|| strpos($ts, 'مشتری') !== false
				|| strpos($ts, 'customer') !== false
			) {
				return true;
			}
		}

		return false;
	}

	/**
	 * @param string $email
	 * @return string
	 */
	private static function generate_username_from_email($email)
	{
		$parts = explode('@', (string) $email, 2);
		$base = sanitize_user($parts[0], true);
		if ($base === '') {
			$base = 'customer';
		}
		$username = $base;
		$n = 1;
		while (username_exists($username)) {
			$username = $base . $n;
			$n++;
		}

		return $username;
	}

	/**
	 * شناسه موجودیت از پاسخ API (data.id یا data.item.id).
	 *
	 * @param array $result
	 * @return int
	 */
	private static function api_result_entity_id(array $result)
	{
		if (!empty($result['data']['id'])) {
			return (int) $result['data']['id'];
		}
		if (!empty($result['data']['item']['id'])) {
			return (int) $result['data']['item']['id'];
		}

		return 0;
	}
}

