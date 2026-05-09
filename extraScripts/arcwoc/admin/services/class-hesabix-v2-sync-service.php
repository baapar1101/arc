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

		$o['wc_product_parents_per_ajax'] = max(5, min(500, absint($o['wc_product_parents_per_ajax'])));
		$o['wc_categories_per_ajax'] = max(10, min(300, absint($o['wc_categories_per_ajax'])));
		$o['wc_customers_per_ajax'] = max(5, min(500, absint($o['wc_customers_per_ajax'])));

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
			$sync_settings = get_option('hesabix_v2_sync_settings', array());
			if (empty($sync_settings['sync_product_price'])) {
				unset($product_data['base_sales_price']);
			}
			if (empty($sync_settings['sync_product_stock'])) {
				$product_data['track_inventory'] = false;
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
			$order->add_order_note(
				sprintf(__('همگام‌سازی حسابیکس متوقف شد (ارز): %s', 'hesabix-v2'), $gate['message'])
			);

			return array(
				'success' => false,
				'message' => $gate['message'],
				'currency_blocked' => true,
			);
		}

		$wc_payload_for_log = null;
		$api_last_result = null;

		try {

			// Get or create customer (با توجه به تنظیم create_customer_on_order)
			$sync_settings = get_option('hesabix_v2_sync_settings', array());
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
			$invoice_data = apply_filters(
				'hesabix_v2_invoice_data',
				Hesabix_V2_Mapper::wc_order_to_invoice($order, $person_id, $gate['factor'], $gate['currency_id']),
				$order
			);

			$wc_payload_for_log = $invoice_data;

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
			Hesabix_V2_Log_Service::error('Order sync failed', $elog);

			// Add error note to order (order may not be set if exception was early)
			$order_for_note = isset($order) ? $order : wc_get_order($order_id);
			if ($order_for_note) {
				$order_for_note->add_order_note(
					sprintf(__('خطا در ایجاد فاکتور حسابیکس: %s', 'hesabix-v2'), $e->getMessage())
				);
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
	 * Bulk sync products (محصولات ساده مستقیم؛ محصولات متغیر به‌صورت واریانت‌ها همگام می‌شوند)
	 *
	 * @since    2.0.0
	 * @param    array    $product_ids
	 * @return   array
	 */
	public function bulk_sync_products($product_ids)
	{
		$results = array(
			'success' => 0,
			'failed' => 0,
			'total' => 0,
			'errors' => array(),
		);

		foreach ($product_ids as $product_id) {
			$product = wc_get_product($product_id);
			if (!$product) {
				$results['failed']++;
				$results['total']++;
				$results['errors'][] = array(
					'product_id' => $product_id,
					'message' => __('محصول یافت نشد', 'hesabix-v2'),
				);
				continue;
			}

			if ($product->is_type('variable')) {
				$variation_ids = $product->get_children();
				if (empty($variation_ids)) {
					$results['failed']++;
					$results['total']++;
					$results['errors'][] = array(
						'product_id' => $product_id,
						'message' => __('محصول متغیر بدون واریانت', 'hesabix-v2'),
					);
					continue;
				}
				foreach ($variation_ids as $variation_id) {
					$results['total']++;
					$result = $this->sync_product($product_id, $variation_id);
					if ($result['success']) {
						$results['success']++;
					} else {
						$results['failed']++;
						$results['errors'][] = array(
							'product_id' => $product_id,
							'variation_id' => $variation_id,
							'message' => $result['message'],
						);
					}
				}
			} else {
				$results['total']++;
				$result = $this->sync_product($product_id);
				if ($result['success']) {
					$results['success']++;
				} else {
					$results['failed']++;
					$results['errors'][] = array(
						'product_id' => $product_id,
						'message' => $result['message'],
					);
				}
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
		);

		foreach ($customer_ids as $customer_id) {
			$result = $this->sync_customer($customer_id);

			if ($result['success']) {
				$results['success']++;
			} else {
				$results['failed']++;
				$results['errors'][] = array(
					'customer_id' => $customer_id,
					'message' => $result['message'],
				);
			}
		}

		return $results;
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

