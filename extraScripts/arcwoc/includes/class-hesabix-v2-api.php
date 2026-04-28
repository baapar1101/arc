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
		if (strpos($endpoint, '/business/') !== false || strpos($endpoint, '/businesses/') !== false) {
			if ($this->business_id) {
				$headers['X-Business-ID'] = $this->business_id;
			}
			if ($this->fiscal_year_id) {
				$headers['X-Fiscal-Year-ID'] = $this->fiscal_year_id;
			}
		}

		$args = array(
			'method' => $method,
			'headers' => $headers,
			'timeout' => $timeout,
			'body' => $data ? wp_json_encode($data) : null,
		);

		// Log request in debug mode (برای خطایابی بهتر)
		if (get_option('hesabix_v2_debug_mode')) {
			Hesabix_V2_Log_Service::debug('API Request', array(
				'method' => $method,
				'url' => $url,
				'endpoint' => $endpoint,
				'data' => $data,
			));
		}

		$start_time = microtime(true);
		$response = wp_remote_request($url, $args);
		$execution_time = microtime(true) - $start_time;

		if (is_wp_error($response)) {
			$error_message = $response->get_error_message();
			
			Hesabix_V2_Log_Service::error('API Request Error', array(
				'endpoint' => $endpoint,
				'error' => $error_message,
				'execution_time' => $execution_time,
			));

			return array(
				'success' => false,
				'message' => $error_message,
				'error_code' => 'REQUEST_FAILED',
			);
		}

		$status_code = wp_remote_retrieve_response_code($response);
		$body = wp_remote_retrieve_body($response);
		$result = json_decode($body, true);

		// Log response in debug mode (پاسخ سرور برای بررسی و خطایابی)
		if (get_option('hesabix_v2_debug_mode')) {
			Hesabix_V2_Log_Service::debug('API Response', array(
				'method' => $method,
				'endpoint' => $endpoint,
				'status_code' => $status_code,
				'response' => $result,
				'raw_body' => $body,
				'execution_time' => $execution_time,
			));
		}

		// Handle non-JSON responses
		if (json_last_error() !== JSON_ERROR_NONE) {
			Hesabix_V2_Log_Service::error('Invalid JSON Response', array(
				'endpoint' => $endpoint,
				'status_code' => $status_code,
				'raw_body' => $body,
				'json_error' => json_last_error_msg(),
			));

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
			return array(
				'success' => true,
				'message' => __('اتصال با موفقیت برقرار شد', 'hesabix-v2'),
				'user' => $result['data'] ?? null,
			);
		}

		return array(
			'success' => false,
			'message' => $result['message'] ?? __('خطا در برقراری ارتباط', 'hesabix-v2'),
		);
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
	 * Search persons
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
			"/persons/businesses/{$this->business_id}/persons/search",
			$query
		);
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
}

