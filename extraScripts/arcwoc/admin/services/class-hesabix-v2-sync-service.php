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
	public function sync_product($product_id, $variation_id = null)
	{
		$start_time = microtime(true);

		try {
			// Get product
			if ($variation_id) {
				$product = wc_get_product($variation_id);
				$parent_product = wc_get_product($product_id);
				
				if (!$product || !$parent_product) {
					throw new Exception(__('محصول یافت نشد', 'hesabix-v2'));
				}

				$product_data = Hesabix_V2_Mapper::wc_variation_to_api($parent_product, $product, $product_id);
				$wc_id = $variation_id;
				$wc_parent_id = $product_id;
			} else {
				$product = wc_get_product($product_id);
				
				if (!$product) {
					throw new Exception(__('محصول یافت نشد', 'hesabix-v2'));
				}

				$product_data = Hesabix_V2_Mapper::wc_product_to_api($product, $product_id);
				$wc_id = $product_id;
				$wc_parent_id = null;
			}

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
				$result = $this->api->update_product($existing_mapping['hesabix_id'], $product_data);
			} else {
				// Create new product
				$result = $this->api->create_product($product_data);
			}

			if (isset($result['success']) && $result['success']) {
				$hesabix_id = $result['data']['id'];

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
				throw new Exception($result['message'] ?? __('خطا در همگام‌سازی', 'hesabix-v2'));
			}

		} catch (Exception $e) {
			$execution_time = microtime(true) - $start_time;

			Hesabix_V2_Log_Service::error('Product sync failed', array(
				'entity_type' => 'product',
				'entity_id' => $product_id,
				'error' => $e->getMessage(),
				'execution_time' => $execution_time,
			));

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

		try {
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

			// Check if already synced
			$existing_mapping = $this->db->get_mapping('customer', $customer_id);
			$result = null;

			if ($existing_mapping) {
				$result = $this->api->update_person($existing_mapping['hesabix_id'], $customer_data);
				// اگر شخص در حسابیکس حذف شده یا وجود ندارد، mapping را پاک کرده و دوباره ایجاد کن
				$msg = isset($result['message']) ? (string) $result['message'] : '';
				$is_not_found = $msg !== ''
					&& (stripos($msg, 'not found') !== false
						|| stripos($msg, 'Entity not found') !== false
						|| stripos($msg, 'یافت نشد') !== false);
				if (isset($result['success']) && !$result['success'] && $is_not_found) {
					$this->db->delete_mapping('customer', $customer_id);
					$result = $this->api->create_person($customer_data);
				}
			} else {
				$result = $this->api->create_person($customer_data);
			}

			if (isset($result['success']) && $result['success']) {
				$hesabix_id = self::api_result_entity_id($result);
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
				throw new Exception($result['message'] ?? __('خطا در همگام‌سازی', 'hesabix-v2'));
			}

		} catch (Exception $e) {
			$execution_time = microtime(true) - $start_time;

			Hesabix_V2_Log_Service::error('Customer sync failed', array(
				'entity_type' => 'customer',
				'entity_id' => $customer_id,
				'error' => $e->getMessage(),
				'execution_time' => $execution_time,
			));

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

		try {
			$order = wc_get_order($order_id);

			if (!$order) {
				throw new Exception(__('سفارش یافت نشد', 'hesabix-v2'));
			}

			$guest_data = apply_filters('hesabix_v2_guest_customer_data', Hesabix_V2_Mapper::wc_guest_to_api($order), $order);
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

			$result = $this->api->create_person($guest_data);

			if (isset($result['success']) && $result['success']) {
				$hesabix_id = self::api_result_entity_id($result);
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

			throw new Exception($result['message'] ?? __('خطا در ایجاد مشتری', 'hesabix-v2'));

		} catch (Exception $e) {
			$execution_time = microtime(true) - $start_time;

			Hesabix_V2_Log_Service::error('Guest customer creation failed', array(
				'entity_type' => 'customer',
				'order_id' => $order_id,
				'error' => $e->getMessage(),
				'execution_time' => $execution_time,
			));

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

		try {
			$order = wc_get_order($order_id);

			if (!$order) {
				throw new Exception(__('سفارش یافت نشد', 'hesabix-v2'));
			}

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
						throw new Exception(__('خطا در همگام‌سازی مشتری', 'hesabix-v2'));
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
					throw new Exception(__('خطا در ایجاد مشتری مهمان', 'hesabix-v2'));
				}
			}

			// Prepare invoice data
			$invoice_data = apply_filters(
				'hesabix_v2_invoice_data',
				Hesabix_V2_Mapper::wc_order_to_invoice($order, $person_id),
				$order
			);

			// Check if already synced
			$existing_mapping = $this->db->get_mapping('order', $order_id);
			$is_new_invoice = !$existing_mapping;

			if ($existing_mapping) {
				// Update existing invoice
				$result = $this->api->update_invoice($existing_mapping['hesabix_id'], $invoice_data);
			} else {
				// Create new invoice
				$result = $this->api->create_invoice($invoice_data);
			}

			if (isset($result['success']) && $result['success']) {
				$hesabix_id = $result['data']['id'];

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
				throw new Exception($result['message'] ?? __('خطا در همگام‌سازی', 'hesabix-v2'));
			}

		} catch (Exception $e) {
			$execution_time = microtime(true) - $start_time;

			Hesabix_V2_Log_Service::error('Order sync failed', array(
				'entity_type' => 'order',
				'entity_id' => $order_id,
				'error' => $e->getMessage(),
				'execution_time' => $execution_time,
			));

			// Add error note to order (order may not be set if exception was early)
			$order_for_note = isset($order) ? $order : wc_get_order($order_id);
			if ($order_for_note) {
				$order_for_note->add_order_note(
					sprintf(__('خطا در ایجاد فاکتور حسابیکس: %s', 'hesabix-v2'), $e->getMessage())
				);
			}

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
	 * واردات اشخاص از حسابیکس به مشتریان ووکامرس (صفحهٔ همگام‌سازی در ادمین افزونه).
	 *
	 * @param bool $create_missing اگر کاربری با ایمیل موجود نبود، مشتری ووکامرس ایجاد شود.
	 * @return array
	 */
	public function import_customers_from_hesabix($create_missing = false)
	{
		$take = (int) apply_filters('hesabix_v2_import_customers_page_size', 100);
		if ($take < 10) {
			$take = 10;
		}
		if ($take > 200) {
			$take = 200;
		}

		$max_skip = (int) apply_filters('hesabix_v2_import_customers_max_skip', 10000);
		$skip = 0;

		$stats = array(
			'matched_updated' => 0,
			'created' => 0,
			'skipped' => 0,
			'failed' => 0,
			'total_processed' => 0,
		);

		while ($skip < $max_skip) {
			$res = $this->api->search_persons(
				array(
					'take' => $take,
					'skip' => $skip,
					'sort_by' => 'id',
					'sort_desc' => false,
				)
			);

			if (empty($res['success'])) {
				return array(
					'success' => false,
					'message' => isset($res['message']) ? $res['message'] : __('خطا در دریافت لیست اشخاص', 'hesabix-v2'),
					'stats' => $stats,
				);
			}

			$items = isset($res['data']['items']) && is_array($res['data']['items']) ? $res['data']['items'] : array();
			if (empty($items)) {
				break;
			}

			foreach ($items as $row) {
				$stats['total_processed']++;
				$r = $this->import_single_person_row($row, (bool) $create_missing);
				if (isset($stats[ $r['status'] ])) {
					$stats[ $r['status'] ]++;
				}
			}

			$skip += count($items);
			if (count($items) < $take) {
				break;
			}
		}

		return array(
			'success' => true,
			'message' => __('واردات به پایان رسید.', 'hesabix-v2'),
			'stats' => $stats,
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

