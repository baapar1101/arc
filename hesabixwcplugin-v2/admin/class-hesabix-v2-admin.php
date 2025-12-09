<?php
/**
 * The admin-specific functionality of the plugin.
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin
 */

class Hesabix_V2_Admin
{
	/**
	 * The ID of this plugin.
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      string    $plugin_name
	 */
	private $plugin_name;

	/**
	 * The version of this plugin.
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      string    $version
	 */
	private $version;

	/**
	 * Initialize the class and set its properties.
	 *
	 * @since    2.0.0
	 * @param    string    $plugin_name
	 * @param    string    $version
	 */
	public function __construct($plugin_name, $version)
	{
		$this->plugin_name = $plugin_name;
		$this->version = $version;
	}

	/**
	 * Register the stylesheets for the admin area.
	 *
	 * @since    2.0.0
	 */
	public function enqueue_styles()
	{
		if (isset($_GET['page']) && strpos($_GET['page'], 'hesabix-v2') !== false) {
			wp_enqueue_style(
				$this->plugin_name,
				HESABIX_V2_PLUGIN_URL . 'assets/css/hesabix-v2-admin.css',
				array(),
				$this->version,
				'all'
			);
		}
	}

	/**
	 * Register the JavaScript for the admin area.
	 *
	 * @since    2.0.0
	 */
	public function enqueue_scripts()
	{
		if (isset($_GET['page']) && strpos($_GET['page'], 'hesabix-v2') !== false) {
			wp_enqueue_script(
				$this->plugin_name,
				HESABIX_V2_PLUGIN_URL . 'assets/js/hesabix-v2-admin.js',
				array('jquery'),
				$this->version,
				false
			);

			wp_localize_script(
				$this->plugin_name,
				'hesabix_v2_ajax',
				array(
					'ajax_url' => admin_url('admin-ajax.php'),
					'nonce' => wp_create_nonce('hesabix_v2_nonce'),
					'strings' => array(
						'confirm_sync' => __('آیا مطمئن هستید؟', 'hesabix-v2'),
						'syncing' => __('در حال همگام‌سازی...', 'hesabix-v2'),
						'success' => __('با موفقیت انجام شد', 'hesabix-v2'),
						'error' => __('خطا رخ داد', 'hesabix-v2'),
					),
				)
			);
		}
	}

	/**
	 * Add admin menu
	 *
	 * @since    2.0.0
	 */
	public function add_admin_menu()
	{
		add_menu_page(
			__('حسابیکس V2', 'hesabix-v2'),
			__('حسابیکس V2', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2',
			array($this, 'display_dashboard'),
			'dashicons-businessman',
			56
		);

		add_submenu_page(
			'hesabix-v2',
			__('داشبورد', 'hesabix-v2'),
			__('داشبورد', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2',
			array($this, 'display_dashboard')
		);

		add_submenu_page(
			'hesabix-v2',
			__('تنظیمات', 'hesabix-v2'),
			__('تنظیمات', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2-settings',
			array($this, 'display_settings')
		);

		add_submenu_page(
			'hesabix-v2',
			__('همگام‌سازی', 'hesabix-v2'),
			__('همگام‌سازی', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2-sync',
			array($this, 'display_sync')
		);

		add_submenu_page(
			'hesabix-v2',
			__('لاگ‌ها', 'hesabix-v2'),
			__('لاگ‌ها', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2-logs',
			array($this, 'display_logs')
		);

		// Hide setup wizard from menu
		add_submenu_page(
			null,
			__('راه‌اندازی', 'hesabix-v2'),
			__('راه‌اندازی', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2-setup',
			array($this, 'display_setup_wizard')
		);

		// Migration tool (hidden if old version not installed)
		if (is_plugin_active('hesabixwcplugin/hesabix.php')) {
			add_submenu_page(
				'hesabix-v2',
				__('مایگریشن', 'hesabix-v2'),
				__('مایگریشن', 'hesabix-v2'),
				'manage_woocommerce',
				'hesabix-v2-migration',
				array($this, 'display_migration')
			);
		}
	}

	/**
	 * Display dashboard page
	 *
	 * @since    2.0.0
	 */
	public function display_dashboard()
	{
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-dashboard.php';
	}

	/**
	 * Display settings page
	 *
	 * @since    2.0.0
	 */
	public function display_settings()
	{
		if (isset($_POST['hesabix_v2_save_settings'])) {
			check_admin_referer('hesabix_v2_settings');
			$this->save_settings();
		}

		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-settings.php';
	}

	/**
	 * Display sync page
	 *
	 * @since    2.0.0
	 */
	public function display_sync()
	{
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-sync.php';
	}

	/**
	 * Display logs page
	 *
	 * @since    2.0.0
	 */
	public function display_logs()
	{
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-logs.php';
	}

	/**
	 * Display setup wizard
	 *
	 * @since    2.0.0
	 */
	public function display_setup_wizard()
	{
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-setup-wizard.php';
	}

	/**
	 * Display migration tool
	 *
	 * @since    2.0.0
	 */
	public function display_migration()
	{
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-migration.php';
	}

	/**
	 * Save settings
	 *
	 * @since    2.0.0
	 */
	private function save_settings()
	{
		// Sync settings
		$sync_settings = array(
			'auto_sync_products' => isset($_POST['auto_sync_products']),
			'auto_sync_customers' => isset($_POST['auto_sync_customers']),
			'auto_sync_orders' => isset($_POST['auto_sync_orders']),
			'sync_on_product_update' => isset($_POST['sync_on_product_update']),
			'sync_on_order_create' => isset($_POST['sync_on_order_create']),
			'sync_product_price' => isset($_POST['sync_product_price']),
			'sync_product_stock' => isset($_POST['sync_product_stock']),
			'create_customer_on_order' => isset($_POST['create_customer_on_order']),
		);

		update_option('hesabix_v2_sync_settings', $sync_settings);
		update_option('hesabix_v2_debug_mode', isset($_POST['debug_mode']));
		update_option('hesabix_v2_add_checkout_fields', isset($_POST['add_checkout_fields']));

		add_settings_error(
			'hesabix_v2_messages',
			'hesabix_v2_message',
			__('تنظیمات ذخیره شد', 'hesabix-v2'),
			'updated'
		);
	}

	// ==================== WooCommerce Hooks ====================

	/**
	 * On product create
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 */
	public function on_product_create($product_id)
	{
		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		
		if (isset($sync_settings['auto_sync_products']) && $sync_settings['auto_sync_products']) {
			$sync_service = new Hesabix_V2_Sync_Service();
			$sync_service->sync_product($product_id);
		}
	}

	/**
	 * On product update
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 */
	public function on_product_update($product_id)
	{
		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		
		if (isset($sync_settings['sync_on_product_update']) && $sync_settings['sync_on_product_update']) {
			$sync_service = new Hesabix_V2_Sync_Service();
			$sync_service->sync_product($product_id);
		}
	}

	/**
	 * On product delete
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 */
	public function on_product_delete($product_id)
	{
		// Only if it's a product
		if (get_post_type($product_id) !== 'product') {
			return;
		}

		$db = new Hesabix_V2_DB_Service();
		$db->delete_mapping('product', $product_id);
	}

	/**
	 * On order create
	 *
	 * @since    2.0.0
	 * @param    int         $order_id
	 * @param    WC_Order    $order
	 */
	public function on_order_create($order_id, $order)
	{
		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		
		if (isset($sync_settings['sync_on_order_create']) && $sync_settings['sync_on_order_create']) {
			$sync_service = new Hesabix_V2_Sync_Service();
			$sync_service->sync_order($order_id);
		}
	}

	/**
	 * On order status change
	 *
	 * @since    2.0.0
	 * @param    int         $order_id
	 * @param    string      $old_status
	 * @param    string      $new_status
	 * @param    WC_Order    $order
	 */
	public function on_order_status_change($order_id, $old_status, $new_status, $order)
	{
		// Sync order when status changes to processing or completed
		if (in_array($new_status, array('processing', 'completed'))) {
			$sync_service = new Hesabix_V2_Sync_Service();
			$sync_service->sync_order($order_id);
		}
	}

	/**
	 * On customer register
	 *
	 * @since    2.0.0
	 * @param    int    $customer_id
	 */
	public function on_customer_register($customer_id)
	{
		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		
		if (isset($sync_settings['auto_sync_customers']) && $sync_settings['auto_sync_customers']) {
			$sync_service = new Hesabix_V2_Sync_Service();
			$sync_service->sync_customer($customer_id);
		}
	}

	/**
	 * On customer update
	 *
	 * @since    2.0.0
	 * @param    int    $customer_id
	 */
	public function on_customer_update($customer_id)
	{
		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		
		if (isset($sync_settings['auto_sync_customers']) && $sync_settings['auto_sync_customers']) {
			$sync_service = new Hesabix_V2_Sync_Service();
			$sync_service->sync_customer($customer_id);
		}
	}

	/**
	 * Add custom checkout fields
	 *
	 * @since    2.0.0
	 * @param    array    $fields
	 * @return   array
	 */
	public function add_checkout_fields($fields)
	{
		$fields['billing']['billing_hesabix_v2_national_id'] = array(
			'label' => __('کد ملی', 'hesabix-v2'),
			'required' => false,
			'class' => array('form-row-wide'),
			'clear' => true,
			'priority' => 120,
		);

		$fields['billing']['billing_hesabix_v2_economic_code'] = array(
			'label' => __('کد اقتصادی', 'hesabix-v2'),
			'required' => false,
			'class' => array('form-row-wide'),
			'clear' => true,
			'priority' => 121,
		);

		return $fields;
	}

	/**
	 * Save custom checkout fields
	 *
	 * @since    2.0.0
	 * @param    int    $order_id
	 */
	public function save_checkout_fields($order_id)
	{
		if (isset($_POST['billing_hesabix_v2_national_id'])) {
			update_post_meta($order_id, '_billing_hesabix_v2_national_id', sanitize_text_field($_POST['billing_hesabix_v2_national_id']));
		}

		if (isset($_POST['billing_hesabix_v2_economic_code'])) {
			update_post_meta($order_id, '_billing_hesabix_v2_economic_code', sanitize_text_field($_POST['billing_hesabix_v2_economic_code']));
		}
	}

	// ==================== AJAX Handlers ====================

	/**
	 * AJAX: Test connection
	 *
	 * @since    2.0.0
	 */
	public function ajax_test_connection()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$api = new Hesabix_V2_Api();
		$result = $api->test_connection();

		wp_send_json($result);
	}

	/**
	 * AJAX: Sync single product
	 *
	 * @since    2.0.0
	 */
	public function ajax_sync_product()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$product_id = intval($_POST['product_id']);
		$variation_id = isset($_POST['variation_id']) ? intval($_POST['variation_id']) : null;

		$sync_service = new Hesabix_V2_Sync_Service();
		$result = $sync_service->sync_product($product_id, $variation_id);

		wp_send_json($result);
	}

	/**
	 * AJAX: Sync all products
	 *
	 * @since    2.0.0
	 */
	public function ajax_sync_products()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$product_ids = Hesabix_V2_Product_Service::get_all_products();
		
		$sync_service = new Hesabix_V2_Sync_Service();
		$result = $sync_service->bulk_sync_products($product_ids);

		wp_send_json($result);
	}

	/**
	 * AJAX: Sync all customers
	 *
	 * @since    2.0.0
	 */
	public function ajax_sync_customers()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$customer_ids = Hesabix_V2_Customer_Service::get_all_customers();
		
		$sync_service = new Hesabix_V2_Sync_Service();
		$result = $sync_service->bulk_sync_customers($customer_ids);

		wp_send_json($result);
	}
}

