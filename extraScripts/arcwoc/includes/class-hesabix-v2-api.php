<?php
/**
 * API Client for Hesabix V2
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

class Hesabix_V2_Api
{
	/**
	 * API base URL
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      string    $base_url
	 */
	private $base_url;

	/**
	 * API Key
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      string    $api_key
	 */
	private $api_key;

	/**
	 * Business ID
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      int    $business_id
	 */
	private $business_id;

	/**
	 * Fiscal Year ID
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      int    $fiscal_year_id
	 */
	private $fiscal_year_id;

	/**
	 * Initialize the class
	 *
	 * @since    2.0.0
	 */
	public function __construct()
	{
		$this->base_url = get_option('hesabix_v2_api_base_url', HESABIX_V2_API_BASE_URL);
		$this->api_key = get_option('hesabix_v2_api_key');
		$this->business_id = get_option('hesabix_v2_business_id');
		$this->fiscal_year_id = get_option('hesabix_v2_fiscal_year_id');
	}

	/**
	 * Make API request
	 *
	 * @since    2.0.0
	 * @param    string    $method      HTTP method
	 * @param    string    $endpoint    API endpoint
	 * @param    array     $data        Request data
	 * @param    int       $timeout     Request timeout
	 * @return   array                  Response array
	 */
	private function request($method, $endpoint, $data = null, $timeout = 30)
	{
		$url = $this->base_url . $endpoint;

		$headers = array(
			'Content-Type' => 'application/json',
			'Accept' => 'application/json',
		);

		// Add authorization header if API key is set (ApiKey ak_live_... or ak_test_...)
		if ($this->api_key) {
			$headers['Authorization'] = 'ApiKey ' . $this->api_key;
		}

		// Add business and fiscal year headers for business endpoints
		if (strpos($endpoint, '/business/') !== false || strpos($endpoint, '/businesses/') !== false || strpos($endpoint, '/accounts/') !== false) {
			if ($this->business_id) {
				$headers['X-Business-ID'] = $this->business_id;
			}
			if ($this->fiscal_year_id) {
				$headers['X-Fiscal-Year-ID'] = $this->fiscal_year_id;
			}
		}

		$audit_headers = Hesabix_V2_Log_Service::sanitize_log_recursive($headers);

		$args = array(
			'method' => $method,
			'headers' => $headers,
			'timeout' => $timeout,
			'body' => $data ? wp_json_encode($data) : null,
		);

		if (get_option('hesabix_v2_debug_mode')) {
			Hesabix_V2_Log_Service::debug(
				__('درخواست ووکامرس → حسابیکس', 'hesabix-v2'),
				array(
					'entity_type' => 'hesabix_api',
					'request' => array(
						'direction' => 'woocommerce_to_hesabix',
						'method' => $method,
						'url' => $url,
						'endpoint' => $endpoint,
						'headers' => $audit_headers,
						'json_body' => $data,
						'timeout' => $timeout,
					),
				)
			);
		}

		$start_time = microtime(true);
		$response = wp_remote_request($url, $args);
		$execution_time = microtime(true) - $start_time;

		if (is_wp_error($response)) {
			$error_message = $response->get_error_message();

			Hesabix_V2_Log_Service::error(
				'API Request Error',
				array(
					'entity_type' => 'hesabix_api',
					'error' => $error_message,
					'execution_time' => $execution_time,
					'request' => array(
						'direction' => 'woocommerce_to_hesabix',
						'method' => $method,
						'url' => $url,
						'endpoint' => $endpoint,
						'headers' => $audit_headers,
						'json_body' => $data,
						'timeout' => $timeout,
					),
					'response' => array(
						'direction' => 'hesabix_to_woocommerce',
						'type' => 'transport_error',
						'transport_error' => $error_message,
					),
				)
			);

			return array(
				'success' => false,
				'message' => $error_message,
				'error_code' => 'REQUEST_FAILED',
			);
		}

		$status_code = wp_remote_retrieve_response_code($response);
		$body = wp_remote_retrieve_body($response);
		$result = json_decode($body, true);

		if (get_option('hesabix_v2_debug_mode')) {
			$raw_preview = (string) $body;
			if (strlen($raw_preview) > 8192) {
				$raw_preview = substr($raw_preview, 0, 8192) . "\n…[truncated in log]";
			}
			Hesabix_V2_Log_Service::debug(
				__('پاسخ حسابیکس ← ووکامرس', 'hesabix-v2'),
				array(
					'entity_type' => 'hesabix_api',
					'execution_time' => $execution_time,
					'request' => array(
						'_summary' => sprintf('%s %s', $method, $url),
						'direction_reference' => 'woocommerce_to_hesabix',
					),
					'response' => array(
						'direction' => 'hesabix_to_woocommerce',
						'method' => $method,
						'url' => $url,
						'endpoint' => $endpoint,
						'status_code' => $status_code,
						'decoded' => $result,
						'raw_body_preview' => $raw_preview,
					),
				)
			);
		}

		if (json_last_error() !== JSON_ERROR_NONE) {
			$raw_preview = (string) $body;
			if (strlen($raw_preview) > 8192) {
				$raw_preview = substr($raw_preview, 0, 8192) . "\n…[truncated]";
			}
			Hesabix_V2_Log_Service::error(
				'Invalid JSON Response',
				array(
					'entity_type' => 'hesabix_api',
					'error' => json_last_error_msg(),
					'request' => array(
						'direction' => 'woocommerce_to_hesabix',
						'method' => $method,
						'url' => $url,
						'endpoint' => $endpoint,
						'headers' => $audit_headers,
						'json_body' => $data,
						'timeout' => $timeout,
					),
					'response' => array(
						'direction' => 'hesabix_to_woocommerce',
						'type' => 'invalid_json',
						'status_code' => $status_code,
						'raw_body_preview' => $raw_preview,
						'json_error' => json_last_error_msg(),
					),
					'execution_time' => $execution_time,
				)
			);

			return array(
				'success' => false,
				'message' => 'Invalid response from server',
				'error_code' => 'INVALID_RESPONSE',
			);
		}

		// برای پاسخ‌های خطا، یک پیام قابل‌نمایش بساز (API ممکن است message، error یا errors برگرداند)
		if (is_array($result) && ($status_code >= 400 || (isset($result['success']) && $result['success'] === false))) {
			$result['success'] = false;
			if (empty($result['message'])) {
				$result['message'] = self::extract_error_message($result, $status_code, $body);
			}
		}

		// Add execution time to result
		if (is_array($result)) {
			$result['_execution_time'] = $execution_time;
		}

		return $result;
	}

	/**
	 * استخراج پیام خطا از پاسخ API (پشتیبانی از message، error، errors، detail)
	 *
	 * @param    array    $result
	 * @param    int      $status_code
	 * @param    string   $raw_body     پاسخ خام برای نمایش در صورت نبود پیام
	 * @return   string
	 */
	public static function extract_error_message($result, $status_code = 0, $raw_body = '')
	{
		if (!is_array($result)) {
			return __('پاسخ نامعتبر از سرور', 'hesabix-v2') . ($raw_body ? ' ' . mb_substr($raw_body, 0, 300) : '');
		}
		// ساختار خطای حسابیکس: { "success": false, "error": { "code": "...", "message": "...", "details": [...] } }
		if (!empty($result['error']) && is_array($result['error'])) {
			$err = $result['error'];
			$msg = isset($err['message']) && is_string($err['message']) ? $err['message'] : '';
			if (!empty($err['details']) && is_array($err['details'])) {
				$parts = array();
				foreach ($err['details'] as $d) {
					if (isset($d['loc'], $d['msg'])) {
						$parts[] = implode('.', (array) $d['loc']) . ': ' . $d['msg'];
					}
				}
				if (!empty($parts)) {
					$msg .= ($msg ? ' — ' : '') . implode('; ', $parts);
				}
			}
			if ($msg !== '') {
				return $msg;
			}
		}
		if (!empty($result['message']) && is_string($result['message'])) {
			return $result['message'];
		}
		if (!empty($result['error']) && is_string($result['error'])) {
			return $result['error'];
		}
		if (!empty($result['detail']) && is_string($result['detail'])) {
			return $result['detail'];
		}
		if (!empty($result['errors'])) {
			if (is_string($result['errors'])) {
				return $result['errors'];
			}
			if (is_array($result['errors'])) {
				$parts = array();
				foreach ($result['errors'] as $key => $val) {
					if (is_array($val)) {
						$parts[] = $key . ': ' . implode(', ', $val);
					} else {
						$parts[] = $key . ': ' . $val;
					}
				}
				return implode('; ', $parts);
			}
		}
		// کلیدهای متداول دیگر
		if (!empty($result['title']) && is_string($result['title'])) {
			return $result['title'];
		}
		if (!empty($result['msg']) && is_string($result['msg'])) {
			return $result['msg'];
		}
		if ($status_code === 401) {
			return __('احراز هویت ناموفق. کلید API یا دسترسی کسب‌وکار را بررسی کنید.', 'hesabix-v2');
		}
		if ($status_code === 403) {
			return __('دسترسی غیرمجاز به این منبع.', 'hesabix-v2');
		}
		if ($status_code === 404) {
			return __('منبع یافت نشد.', 'hesabix-v2');
		}
		if ($status_code >= 400) {
			$msg = sprintf(__('خطای سرور (کد %d)', 'hesabix-v2'), $status_code);
			if ($raw_body !== '') {
				$snippet = is_string($raw_body) ? mb_substr($raw_body, 0, 350) : wp_json_encode($result);
				$msg .= ' — پاسخ: ' . $snippet;
			}
			return $msg;
		}
		return __('خطا در همگام‌سازی', 'hesabix-v2');
	}

	// ==================== Authentication ====================

	/**
	 * Login and get session token
	 *
	 * @since    2.0.0
	 * @param    string    $email
	 * @param    string    $password
	 * @return   array
	 */
	public function login($email, $password)
	{
		return $this->request('POST', '/auth/login', array(
			'email' => $email,
			'password' => $password,
		));
	}

	/**
	 * Get current user info
	 *
	 * @since    2.0.0
	 * @return   array
	 */
	public function get_me()
	{
		return $this->request('GET', '/auth/me');
	}

	/**
	 * Create personal API key
	 *
	 * @since    2.0.0
	 * @param    string    $session_token
	 * @param    array     $data
	 * @return   array
	 */
	public function create_api_key($session_token, $data)
	{
		// Temporarily use session token
		$old_key = $this->api_key;
		$this->api_key = $session_token;

		$result = $this->request('POST', '/auth/api-keys', $data);

		$this->api_key = $old_key;
		return $result;
	}

	/**
	 * Test API connection
	 *
	 * @since    2.0.0
	 * @return   array
	 */
	public function test_connection()
	{
		$result = $this->get_me();

		if (isset($result['success']) && $result['success']) {
			$user_data = $result['data'] ?? null;
			return array_merge(
				array(
					'success' => true,
					'message' => __('اتصال با موفقیت برقرار شد', 'hesabix-v2'),
					'user' => $user_data,
				),
				$this->build_connection_snapshot_payload(is_array($user_data) ? $user_data : array())
			);
		}

		return array(
			'success' => false,
			'message' => $result['message'] ?? __('خطا در برقراری ارتباط', 'hesabix-v2'),
		);
	}

	/**
	 * پس از احراز هویت موفق: کسب‌وکار انتخاب‌شده و سال جاری حسابیکس برای نمایش در پنل.
	 *
	 * @since 2.0.6
	 * @param array $api_user بدنهٔ استاندارد کاربر حسابیکس (همان خروجی /auth/me).
	 * @return array{connection: array<string,mixed>}
	 */
	private function build_connection_snapshot_payload(array $api_user)
	{
		$connection = array(
			'stored_business_id' => (int) $this->business_id,
			'business' => null,
			'business_note' => null,
			'fiscal_year' => null,
			'fiscal_year_note' => null,
		);

		$business_id = (int) $this->business_id;
		if (!$business_id) {
			return array('connection' => $connection);
		}

		$list_res = $this->request('POST', '/businesses/list?take=500&skip=0&sort_by=name&sort_desc=false', null);
		$items = self::normalize_businesses_list_items(is_array($list_res) ? $list_res : array());
		$business_row = null;
		foreach ($items as $row) {
			if (!is_array($row)) {
				continue;
			}
			$rid = (int) ($row['id'] ?? $row['business_id'] ?? 0);
			if ($rid === $business_id) {
				$business_row = $row;
				break;
			}
		}

		if ($business_row) {
			$connection['business'] = $business_row;
		} else {
			if (isset($list_res['success']) && $list_res['success'] === false) {
				$connection['business_note'] = isset($list_res['message'])
					? (string) $list_res['message']
					: __('دریافت فهرست کسب‌وکارها ناموفق بود.', 'hesabix-v2');
			} else {
				$connection['business_note'] = sprintf(
					__('کسب‌وکار #%d در فهرست کسب‌وکارهای این کلید API دیده نشد.', 'hesabix-v2'),
					$business_id
				);
			}
		}

		$fy_res = $this->get_current_fiscal_year($business_id);
		if (isset($fy_res['success']) && $fy_res['success']) {
			$fy_payload = isset($fy_res['data']) && is_array($fy_res['data']) ? $fy_res['data'] : null;
			if ($fy_payload !== null && $fy_payload !== array()) {
				$connection['fiscal_year'] = $fy_payload;
			} elseif (($fy_payload === null || $fy_payload === array()) && isset($fy_res['message']) && stripos((string) $fy_res['message'], 'NO_CURRENT') !== false) {
				$connection['fiscal_year_note'] = __('برای این کسب‌وکار سال مالی جاری در حسابیکس تنظیم نشده است.', 'hesabix-v2');
			}
		} else {
			$connection['fiscal_year_note'] = isset($fy_res['message']) && $fy_res['message'] !== ''
				? self::sanitize_connection_note_message((string) $fy_res['message'])
				: __('بدون حق مشاهدهٔ سال مالی کسب‌وکار در حسابیکس؛ در صورت نیاز مجوز مشاهدهٔ سال مالی را به کلید برسانید.', 'hesabix-v2');
		}

		$connection['owner_display'] = $this->infer_owner_display($business_row, $api_user);

		return array('connection' => $connection);
	}

	/**
	 * پارس آرایه items از پاسخ POST /businesses/list
	 *
	 * @param array $api_result Raw API response body.
	 * @return array<int, array<string,mixed>>
	 */
	private static function normalize_businesses_list_items(array $api_result)
	{
		$data = $api_result['data'] ?? $api_result;
		$list = is_array($data) ? ($data['items'] ?? $data['list'] ?? $data['data'] ?? array()) : array();
		if (is_array($data) && $list === array() && isset($data[0]) && is_array($data[0])) {
			$list = $data;
		}
		return is_array($list) ? $list : array();
	}

	/**
	 * یادداشت خطای کوتاه برای نمایش در پنل (بدون جزییات داخلی API).
	 */
	private static function sanitize_connection_note_message($msg)
	{
		$m = wp_strip_all_tags($msg);
		if (strlen($m) > 220) {
			$m = trim(mb_substr($m, 0, 217)) . '…';
		}
		return $m;
	}

	private function infer_owner_display($business_row, array $api_user)
	{
		if (!is_array($business_row)) {
			return null;
		}
		$owner_id = isset($business_row['owner_id']) ? (int) $business_row['owner_id'] : 0;
		if (!$owner_id) {
			return null;
		}
		$user_id = isset($api_user['id']) ? (int) $api_user['id'] : 0;
		if ($user_id && $owner_id === $user_id) {
			$name = '';
			foreach (array('first_name', 'last_name') as $k) {
				if (!empty($api_user[ $k ]) && is_string($api_user[ $k ])) {
					$name .= trim($api_user[ $k ]) . ' ';
				}
			}
			$name = trim($name);
			if ($name === '') {
				if (!empty($api_user['email']) && is_string($api_user['email'])) {
					$name = $api_user['email'];
				} elseif (!empty($api_user['mobile']) && is_string($api_user['mobile'])) {
					$name = $api_user['mobile'];
				}
			}
			if ($name !== '') {
				return sprintf(__('شما (%s)', 'hesabix-v2'), $name);
			}
			return sprintf(__('شما — شناسه کاربر: %d', 'hesabix-v2'), $user_id);
		}
		return sprintf(__('شناسه کاربر مالک در حسابیکس: %d', 'hesabix-v2'), $owner_id);
	}

	/**
	 * سال مالی جاری کسب‌وکار ( نیاز به مجوز fiscal_years.view در حسابیکس ).
	 *
	 * @since 2.0.6
	 * @param int $business_id
	 * @return array
	 */
	public function get_current_fiscal_year($business_id)
	{
		$business_id = (int) $business_id;
		if (!$business_id) {
			return array(
				'success' => false,
				'message' => __('شناسه کسب‌وکار نامعتبر است.', 'hesabix-v2'),
			);
		}

		return $this->request('GET', '/business/' . $business_id . '/fiscal-years/current');
	}

	// ==================== Businesses ====================

	/**
	 * Get list of businesses
	 *
	 * @since    2.0.0
	 * @param    string    $session_token
	 * @return   array
	 */
	public function get_businesses($session_token = null)
	{
		if ($session_token) {
			$old_key = $this->api_key;
			$this->api_key = $session_token;
		}

		// POST with query params (مطابق API رسمی: take, skip, sort_by, sort_desc)
		$result = $this->request('POST', '/businesses/list?take=100&skip=0&sort_by=created_at&sort_desc=true', null);

		if ($session_token) {
			$this->api_key = $old_key;
		}

		return $result;
	}

	/**
	 * Get fiscal years for a business
	 *
	 * @since    2.0.0
	 * @param    int       $business_id
	 * @param    string    $session_token   Optional token for setup wizard
	 * @return   array
	 */
	public function get_fiscal_years($business_id, $session_token = null)
	{
		if ($session_token) {
			$old_key = $this->api_key;
			$this->api_key = $session_token;
		}

		$result = $this->request('GET', "/business/{$business_id}/fiscal-years");

		if ($session_token) {
			$this->api_key = $old_key;
		}

		return $result;
	}

	// ==================== Products ====================

	/**
	 * Create product
	 *
	 * @since    2.0.0
	 * @param    array    $data
	 * @return   array
	 */
	public function create_product($data)
	{
		return $this->request(
			'POST',
			'/products/business/' . $this->business_id,
			$data
		);
	}

	/**
	 * Update product
	 *
	 * @since    2.0.0
	 * @param    int      $product_id
	 * @param    array    $data
	 * @return   array
	 */
	public function update_product($product_id, $data)
	{
		return $this->request(
			'PUT',
			"/products/business/{$this->business_id}/{$product_id}",
			$data
		);
	}

	/**
	 * Get product by ID
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 * @return   array
	 */
	public function get_product($product_id)
	{
		return $this->request(
			'GET',
			"/products/business/{$this->business_id}/{$product_id}"
		);
	}

	/**
	 * Search products
	 *
	 * @since    2.0.0
	 * @param    array    $query
	 * @return   array
	 */
	public function search_products($query = array())
	{
		$default_query = array(
			'take' => 50,
			'skip' => 0,
		);

		$query = array_merge($default_query, $query);

		return $this->request(
			'POST',
			"/products/business/{$this->business_id}/search",
			$query
		);
	}

	/**
	 * گزارش موجودی انبار (نیاز به دسترسی reports.view در حسابیکس).
	 * POST /products/businesses/{business_id}/reports/inventory-stock
	 *
	 * @since    3.3.2
	 * @param    array $body پارامترها: product_ids، warehouse_ids، track_inventory، include_zero، skip، take، …
	 * @param    int   $timeout
	 * @return   array
	 */
	public function inventory_stock_report($body = array(), $timeout = 60)
	{
		return $this->request(
			'POST',
			'/products/businesses/' . (int) $this->business_id . '/reports/inventory-stock',
			$body,
			(int) max(25, min(180, $timeout))
		);
	}

	/**
	 * Delete product
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 * @return   array
	 */
	public function delete_product($product_id)
	{
		return $this->request(
			'DELETE',
			"/products/business/{$this->business_id}/{$product_id}"
		);
	}

	// ==================== Persons (Customers) ====================

	/**
	 * Create person
	 *
	 * @since    2.0.0
	 * @param    array    $data
	 * @return   array
	 */
	public function create_person($data)
	{
		return $this->request(
			'POST',
			"/persons/businesses/{$this->business_id}/persons/create",
			$data
		);
	}

	/**
	 * Update person
	 *
	 * @since    2.0.0
	 * @param    int      $person_id
	 * @param    array    $data
	 * @return   array
	 */
	public function update_person($person_id, $data)
	{
		return $this->request(
			'PUT',
			"/persons/persons/{$person_id}",
			$data
		);
	}

	/**
	 * Get person by ID
	 *
	 * @since    2.0.0
	 * @param    int    $person_id
	 * @return   array
	 */
	public function get_person($person_id)
	{
		return $this->request(
			'GET',
			"/persons/persons/{$person_id}"
		);
	}

	/**
	 * لیست و جستجوی اشخاص کسب‌وکار (بدنه همان QueryInfo سرور: take، skip، search، …).
	 *
	 * مسیر رسمی API: POST /persons/businesses/{business_id}/persons — نه .../persons/search.
	 *
	 * @since    2.0.0
	 * @param    array    $query
	 * @return   array
	 */
	public function search_persons($query = array())
	{
		$default_query = array(
			'take' => 50,
			'skip' => 0,
		);

		$query = array_merge($default_query, $query);

		return $this->request(
			'POST',
			"/persons/businesses/{$this->business_id}/persons",
			$query
		);
	}

	/**
	 * جستجوی شخص با تطبیق دقیق ایمیل یا موبایل (برای جلوگیری از تکرار مهمان).
	 *
	 * @param string $email
	 * @param string $mobile
	 * @return int|null
	 */
	public function find_person_id_by_contact($email, $mobile)
	{
		$email = mb_strtolower(trim((string) $email));
		$mobile = trim((string) $mobile);

		if ($email !== '') {
			$res = $this->search_persons(
				array(
					'take' => 15,
					'skip' => 0,
					'search' => $email,
					'search_fields' => array('email'),
				)
			);
			$pid = self::pick_person_id_exact_match($res, 'email', $email);
			if ($pid) {
				return $pid;
			}
		}

		if ($mobile !== '') {
			$res = $this->search_persons(
				array(
					'take' => 15,
					'skip' => 0,
					'search' => $mobile,
					'search_fields' => array('mobile'),
				)
			);
			$pid = self::pick_person_id_exact_match($res, 'mobile', $mobile);
			if ($pid) {
				return $pid;
			}
		}

		return null;
	}

	/**
	 * @param array $api_result
	 * @param string $field email|mobile
	 * @param string $needle_normalized
	 * @return int|null
	 */
	private static function pick_person_id_exact_match($api_result, $field, $needle_normalized)
	{
		if (empty($api_result['success']) || empty($api_result['data']['items']) || !is_array($api_result['data']['items'])) {
			return null;
		}

		foreach ($api_result['data']['items'] as $item) {
			if (!isset($item['id'])) {
				continue;
			}
			if (!isset($item[$field])) {
				continue;
			}
			$val = mb_strtolower(trim((string) $item[$field]));
			if ($val !== '' && $val === $needle_normalized) {
				return (int) $item['id'];
			}
		}

		return null;
	}

	/**
	 * Delete person
	 *
	 * @since    2.0.0
	 * @param    int    $person_id
	 * @return   array
	 */
	public function delete_person($person_id)
	{
		return $this->request(
			'DELETE',
			"/persons/persons/{$person_id}"
		);
	}

	// ==================== Invoices ====================

	/**
	 * لیست برچسب‌های فاکتور کسب‌وکار
	 *
	 * @param    bool    $include_inactive
	 * @return   array
	 */
	public function list_invoice_tags($include_inactive = false)
	{
		$q = $include_inactive ? 'true' : 'false';
		return $this->request(
			'GET',
			"/invoices/business/{$this->business_id}/tags?include_inactive={$q}"
		);
	}

	/**
	 * ایجاد برچسب فاکتور
	 *
	 * @param    string      $name
	 * @param    string|null $color
	 * @return   array
	 */
	public function create_invoice_tag($name, $color = null)
	{
		$body = array('name' => $name);
		if ($color !== null && $color !== '') {
			$body['color'] = $color;
		}
		return $this->request(
			'POST',
			"/invoices/business/{$this->business_id}/tags",
			$body
		);
	}

	/**
	 * Create invoice
	 *
	 * @since    2.0.0
	 * @param    array    $data
	 * @return   array
	 */
	public function create_invoice($data)
	{
		return $this->request(
			'POST',
			"/invoices/business/{$this->business_id}",
			$data
		);
	}

	/**
	 * Update invoice
	 *
	 * @since    2.0.0
	 * @param    int      $invoice_id
	 * @param    array    $data
	 * @return   array
	 */
	public function update_invoice($invoice_id, $data)
	{
		return $this->request(
			'PUT',
			"/invoices/business/{$this->business_id}/{$invoice_id}",
			$data
		);
	}

	/**
	 * Get invoice by ID
	 *
	 * @since    2.0.0
	 * @param    int    $invoice_id
	 * @return   array
	 */
	public function get_invoice($invoice_id)
	{
		return $this->request(
			'GET',
			"/invoices/business/{$this->business_id}/{$invoice_id}"
		);
	}

	/**
	 * Search invoices
	 *
	 * @since    2.0.0
	 * @param    array    $query
	 * @return   array
	 */
	public function search_invoices($query = array())
	{
		$default_query = array(
			'take' => 50,
			'skip' => 0,
		);

		$query = array_merge($default_query, $query);

		return $this->request(
			'POST',
			"/invoices/business/{$this->business_id}/search",
			$query
		);
	}

	/**
	 * Delete invoice
	 *
	 * @since    2.0.0
	 * @param    int    $invoice_id
	 * @return   array
	 */
	public function delete_invoice($invoice_id)
	{
		return $this->request(
			'DELETE',
			"/invoices/business/{$this->business_id}/{$invoice_id}"
		);
	}

	// ==================== Categories ====================

	/**
	 * Get categories
	 *
	 * @since    2.0.0
	 * @return   array
	 */
	public function get_categories()
	{
		return $this->request(
			'POST',
			"/categories/business/{$this->business_id}/list",
			array('take' => 1000, 'skip' => 0)
		);
	}

	/**
	 * درخت دسته‌های کسب‌وکار (برای تطبیق نام و والد).
	 *
	 * @since 2.0.8
	 * @param array<string,mixed> $body
	 * @return array
	 */
	public function get_categories_tree($body = null)
	{
		if (!is_array($body)) {
			$body = new \stdClass();
		}
		return $this->request(
			'POST',
			"/categories/business/{$this->business_id}/tree",
			$body
		);
	}

	/**
	 * Create category
	 *
	 * @since    2.0.0
	 * @param    array    $data
	 * @return   array
	 */
	public function create_category($data)
	{
		return $this->request(
			'POST',
			"/categories/business/{$this->business_id}",
			$data
		);
	}

	/**
	 * به‌روزرسانی دسته (برچسب و سایر فیلدهای اختیاری)
	 *
	 * @since 2.0.8
	 * @param array<string,mixed> $data category_id، label، ...
	 * @return array
	 */
	public function update_category($data)
	{
		return $this->request(
			'POST',
			"/categories/business/{$this->business_id}/update",
			$data
		);
	}

	/**
	 * جابه‌جایی دسته در درخت (مثلاً ریشه با new_parent_id برابر null)
	 *
	 * @since 2.0.8
	 * @param array<string,mixed> $data category_id، new_parent_id
	 * @return array
	 */
	public function move_category($data)
	{
		return $this->request(
			'POST',
			"/categories/business/{$this->business_id}/move",
			$data
		);
	}

	// ==================== Warehouses & Bank Accounts (برای انتخاب در تنظیمات فاکتور) ====================

	/**
	 * لیست انبارهای کسب‌وکار
	 * GET /warehouses/business/{business_id}
	 *
	 * @since    2.0.0
	 * @return   array
	 */
	public function get_warehouses()
	{
		return $this->request(
			'GET',
			"/warehouses/business/{$this->business_id}"
		);
	}

	/**
	 * لیست حساب‌های بانکی کسب‌وکار
	 * POST /bank-accounts/businesses/{business_id}/bank-accounts با body QueryInfo
	 *
	 * @since    2.0.0
	 * @return   array
	 */
	public function get_bank_accounts()
	{
		return $this->request(
			'POST',
			"/bank-accounts/businesses/{$this->business_id}/bank-accounts",
			array('take' => 500, 'skip' => 0)
		);
	}

	/**
	 * لیست صندوق‌های کسب‌وکار
	 * POST /cash-registers/businesses/{business_id}/cash-registers (بدنه QueryInfo)
	 *
	 * @since    2.0.0
	 * @return   array
	 */
	public function get_cash_registers()
	{
		return $this->request(
			'POST',
			"/cash-registers/businesses/{$this->business_id}/cash-registers",
			array('take' => 500, 'skip' => 0)
		);
	}

	/**
	 * ارزهای فعال کسب‌وکار + پیش‌فرض (بدون تکرار).
	 * GET /currencies/business/{business_id}
	 *
	 * @since 2.0.1
	 * @return array
	 */
	public function get_business_currencies()
	{
		if (!$this->business_id) {
			return array(
				'success' => false,
				'message' => __('شناسه کسب‌وکار تنظیم نشده است.', 'hesabix-v2'),
			);
		}

		return $this->request(
			'GET',
			"/currencies/business/" . (int) $this->business_id
		);
	}

	// ==================== Opening balance ====================

	/**
	 * تراز افتتاحیه سال مالی
	 *
	 * @param int|null $fiscal_year_id
	 * @return array
	 */
	public function get_opening_balance($fiscal_year_id = null)
	{
		$bid = (int) $this->business_id;
		if (!$bid) {
			return array(
				'success' => false,
				'message' => __('شناسه کسب‌وکار تنظیم نشده است.', 'hesabix-v2'),
			);
		}
		$q = '';
		if ($fiscal_year_id !== null && (int) $fiscal_year_id > 0) {
			$q = '?fiscal_year_id=' . (int) $fiscal_year_id;
		}
		return $this->request(
			'GET',
			"/businesses/{$bid}/opening-balance{$q}",
			null,
			45
		);
	}

	/**
	 * ذخیره / به‌روزرسانی تراز افتتاحیه
	 *
	 * @param array $body
	 * @return array
	 */
	public function upsert_opening_balance($body)
	{
		$bid = (int) $this->business_id;
		if (!$bid) {
			return array(
				'success' => false,
				'message' => __('شناسه کسب‌وکار تنظیم نشده است.', 'hesabix-v2'),
			);
		}
		return $this->request(
			'PUT',
			"/businesses/{$bid}/opening-balance",
			$body,
			120
		);
	}

	/**
	 * نهایی‌سازی تراز افتتاحیه
	 *
	 * @param int|null $fiscal_year_id
	 * @return array
	 */
	public function post_opening_balance($fiscal_year_id = null)
	{
		$bid = (int) $this->business_id;
		if (!$bid) {
			return array(
				'success' => false,
				'message' => __('شناسه کسب‌وکار تنظیم نشده است.', 'hesabix-v2'),
			);
		}
		$q = '';
		if ($fiscal_year_id !== null && (int) $fiscal_year_id > 0) {
			$q = '?fiscal_year_id=' . (int) $fiscal_year_id;
		}
		return $this->request(
			'POST',
			"/businesses/{$bid}/opening-balance/post{$q}",
			null,
			60
		);
	}

	/**
	 * لیست تخت حساب‌ها (کد + نام)
	 *
	 * @return array
	 */
	public function get_accounts_flat()
	{
		$bid = (int) $this->business_id;
		if (!$bid) {
			return array(
				'success' => false,
				'message' => __('شناسه کسب‌وکار تنظیم نشده است.', 'hesabix-v2'),
			);
		}
		return $this->request(
			'GET',
			'/accounts/business/' . $bid,
			null,
			60
		);
	}
}
