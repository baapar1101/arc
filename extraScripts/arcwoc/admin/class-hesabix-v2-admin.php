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
			$fonts_url = HESABIX_V2_PLUGIN_URL . 'assets/fonts/';
			?>
			<style>
				@font-face {
					font-family: 'IRANYekanWeb';
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebThin.eot');
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebThin.eot?#iefix') format('embedded-opentype'),
						url('<?php echo esc_url($fonts_url); ?>woff2/IRANYekanWebThin.woff2') format('woff2'),
						url('<?php echo esc_url($fonts_url); ?>woff/IRANYekanWebThin.woff') format('woff'),
						url('<?php echo esc_url($fonts_url); ?>ttf/IRANYekanWebThin.ttf') format('truetype'),
						url('<?php echo esc_url($fonts_url); ?>svg/iranyekanwebthin.svg#IRANYekanWebThin') format('svg');
					font-weight: 100;
					font-style: normal;
					font-display: swap;
				}
				@font-face {
					font-family: 'IRANYekanWeb';
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebLight.eot');
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebLight.eot?#iefix') format('embedded-opentype'),
						url('<?php echo esc_url($fonts_url); ?>woff2/IRANYekanWebLight.woff2') format('woff2'),
						url('<?php echo esc_url($fonts_url); ?>woff/IRANYekanWebLight.woff') format('woff'),
						url('<?php echo esc_url($fonts_url); ?>ttf/IRANYekanWebLight.ttf') format('truetype'),
						url('<?php echo esc_url($fonts_url); ?>svg/iranyekanweblight.svg#IRANYekanWebLight') format('svg');
					font-weight: 300;
					font-style: normal;
					font-display: swap;
				}
				@font-face {
					font-family: 'IRANYekanWeb';
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebRegular.eot');
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebRegular.eot?#iefix') format('embedded-opentype'),
						url('<?php echo esc_url($fonts_url); ?>woff2/IRANYekanWebRegular.woff2') format('woff2'),
						url('<?php echo esc_url($fonts_url); ?>woff/IRANYekanWebRegular.woff') format('woff'),
						url('<?php echo esc_url($fonts_url); ?>ttf/IRANYekanWebRegular.ttf') format('truetype'),
						url('<?php echo esc_url($fonts_url); ?>svg/IRANYekanWebRegular.svg#IRANYekanWebRegular') format('svg');
					font-weight: 400;
					font-style: normal;
					font-display: swap;
				}
				@font-face {
					font-family: 'IRANYekanWeb';
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebMedium.eot');
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebMedium.eot?#iefix') format('embedded-opentype'),
						url('<?php echo esc_url($fonts_url); ?>woff2/IRANYekanWebMedium.woff2') format('woff2'),
						url('<?php echo esc_url($fonts_url); ?>woff/IRANYekanWebMedium.woff') format('woff'),
						url('<?php echo esc_url($fonts_url); ?>ttf/IRANYekanWebMedium.ttf') format('truetype'),
						url('<?php echo esc_url($fonts_url); ?>svg/iranyekanwebmedium.svg#IRANYekanWebMedium') format('svg');
					font-weight: 500;
					font-style: normal;
					font-display: swap;
				}
				@font-face {
					font-family: 'IRANYekanWeb';
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebBold.eot');
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebBold.eot?#iefix') format('embedded-opentype'),
						url('<?php echo esc_url($fonts_url); ?>woff2/IRANYekanWebBold.woff2') format('woff2'),
						url('<?php echo esc_url($fonts_url); ?>woff/IRANYekanWebBold.woff') format('woff'),
						url('<?php echo esc_url($fonts_url); ?>ttf/IRANYekanWebBold.ttf') format('truetype'),
						url('<?php echo esc_url($fonts_url); ?>svg/iranyekanwebbold.svg#IRANYekanWebBold') format('svg');
					font-weight: 700;
					font-style: normal;
					font-display: swap;
				}
				@font-face {
					font-family: 'IRANYekanWeb';
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebExtraBold.eot');
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebExtraBold.eot?#iefix') format('embedded-opentype'),
						url('<?php echo esc_url($fonts_url); ?>woff2/IRANYekanWebExtraBold.woff2') format('woff2'),
						url('<?php echo esc_url($fonts_url); ?>woff/IRANYekanWebExtraBold.woff') format('woff'),
						url('<?php echo esc_url($fonts_url); ?>ttf/IRANYekanWebExtraBold.ttf') format('truetype'),
						url('<?php echo esc_url($fonts_url); ?>svg/iranyekanwebextrabold.svg#IRANYekanWebExtraBold') format('svg');
					font-weight: 800;
					font-style: normal;
					font-display: swap;
				}
				@font-face {
					font-family: 'IRANYekanWeb';
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebBlack.eot');
					src: url('<?php echo esc_url($fonts_url); ?>eot/IRANYekanWebBlack.eot?#iefix') format('embedded-opentype'),
						url('<?php echo esc_url($fonts_url); ?>woff2/IRANYekanWebBlack.woff2') format('woff2'),
						url('<?php echo esc_url($fonts_url); ?>woff/IRANYekanWebBlack.woff') format('woff'),
						url('<?php echo esc_url($fonts_url); ?>ttf/IRANYekanWebBlack.ttf') format('truetype'),
						url('<?php echo esc_url($fonts_url); ?>svg/iranyekanwebblack.svg#IRANYekanWebBlack') format('svg');
					font-weight: 900;
					font-style: normal;
					font-display: swap;
				}
			</style>
			<?php
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
			HESABIX_V2_PLUGIN_URL . 'assets/img/menu-icon.png',
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
		if (isset($_POST['hesabix_v2_clear_logs']) && check_admin_referer('hesabix_v2_clear_logs')) {
			Hesabix_V2_Log_Service::clear_all_logs();
			wp_safe_redirect(add_query_arg(array('page' => 'hesabix-v2-logs', 'logs_cleared' => '1'), admin_url('admin.php')));
			exit;
		}
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
		// Sync settings (قالب واحد با Hesabix_V2_Invoice_Helper::normalize_sync_settings)
		$status_choices = Hesabix_V2_Invoice_Helper::get_wc_order_status_choices();
		$sync_order_on_statuses = array();
		if (isset($_POST['sync_order_on_statuses']) && is_array($_POST['sync_order_on_statuses'])) {
			foreach ($_POST['sync_order_on_statuses'] as $st) {
				$st = sanitize_text_field(wp_unslash($st));
				if ($st !== '' && isset($status_choices[$st])) {
					$sync_order_on_statuses[] = $st;
				}
			}
		}

		$sync_settings = array(
			'auto_sync_products' => isset($_POST['auto_sync_products']),
			'auto_sync_customers' => isset($_POST['auto_sync_customers']),
			'auto_sync_orders' => isset($_POST['auto_sync_orders']),
			'sync_on_product_update' => isset($_POST['sync_on_product_update']),
			'sync_product_price' => isset($_POST['sync_product_price']),
			'sync_product_stock' => isset($_POST['sync_product_stock']),
			'create_customer_on_order' => isset($_POST['create_customer_on_order']),
			'sync_order_on_checkout' => isset($_POST['sync_order_on_checkout']),
			'sync_order_on_payment_complete' => isset($_POST['sync_order_on_payment_complete']),
			'sync_order_on_statuses' => $sync_order_on_statuses,
			'invoice_is_proforma' => isset($_POST['invoice_doc_mode']) && sanitize_text_field(wp_unslash($_POST['invoice_doc_mode'])) === 'proforma',
			'invoice_tag_website_enabled' => isset($_POST['invoice_tag_website_enabled']),
			'invoice_tag_website_name' => isset($_POST['invoice_tag_website_name'])
				? sanitize_text_field(wp_unslash($_POST['invoice_tag_website_name']))
				: 'فروش سایت',
			'invoice_extra_tag_ids' => isset($_POST['invoice_extra_tag_ids'])
				? sanitize_text_field(wp_unslash($_POST['invoice_extra_tag_ids']))
				: '',
		);

		update_option('hesabix_v2_sync_settings', $sync_settings);
		update_option('hesabix_v2_debug_mode', isset($_POST['debug_mode']));
		update_option('hesabix_v2_add_checkout_fields', isset($_POST['add_checkout_fields']));

		// API base URL - allow configuring server address
		if (isset($_POST['api_base_url'])) {
			$url = esc_url_raw(trim(wp_unslash($_POST['api_base_url'])));
			if (!empty($url)) {
				$url = rtrim($url, '/');
				update_option('hesabix_v2_api_base_url', $url);
			}
		}

		if (isset($_POST['hesabix_v2_currency_id'])) {
			$v = absint($_POST['hesabix_v2_currency_id']);
			if ($v >= 1) {
				update_option('hesabix_v2_currency_id', $v);
			}
		}
		if (isset($_POST['hesabix_v2_default_warehouse_id'])) {
			$v = sanitize_text_field(wp_unslash($_POST['hesabix_v2_default_warehouse_id']));
			update_option('hesabix_v2_default_warehouse_id', $v === '' ? '' : absint($v));
		}
		if (isset($_POST['hesabix_v2_default_bank_id'])) {
			update_option('hesabix_v2_default_bank_id', sanitize_text_field(wp_unslash($_POST['hesabix_v2_default_bank_id'])));
		}

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
	 * آیا همگام‌سازی خودکار سفارش فعال است؟
	 *
	 * @return bool
	 */
	private function is_auto_sync_orders_enabled()
	{
		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		return !empty($sync_settings['auto_sync_orders']);
	}

	/**
	 * بعد از تکمیل چک‌اوت — در صورت فعال بودن در تنظیمات
	 *
	 * @param int         $order_id
	 * @param array|null  $posted_data
	 * @param WC_Order|null $order
	 */
	public function maybe_sync_order_on_checkout($order_id, $posted_data = null, $order = null)
	{
		if (!$this->is_auto_sync_orders_enabled()) {
			return;
		}
		$sync = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		if (empty($sync['sync_order_on_checkout'])) {
			return;
		}
		$sync_service = new Hesabix_V2_Sync_Service();
		$sync_service->sync_order($order_id);
	}

	/**
	 * پس از پرداخت کامل سفارش (woocommerce_payment_complete)
	 *
	 * @param int $order_id
	 */
	public function maybe_sync_order_on_payment_complete($order_id)
	{
		if (!$this->is_auto_sync_orders_enabled()) {
			return;
		}
		$sync = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		if (empty($sync['sync_order_on_payment_complete'])) {
			return;
		}
		$sync_service = new Hesabix_V2_Sync_Service();
		$sync_service->sync_order($order_id);
	}

	/**
	 * تغییر وضعیت سفارش — در صورت انتخاب در تنظیمات
	 *
	 * @param int       $order_id
	 * @param string    $old_status
	 * @param string    $new_status
	 * @param WC_Order  $order
	 */
	public function maybe_sync_order_on_status_change($order_id, $old_status, $new_status, $order)
	{
		if (!$this->is_auto_sync_orders_enabled()) {
			return;
		}
		$sync = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		$allowed = isset($sync['sync_order_on_statuses']) && is_array($sync['sync_order_on_statuses'])
			? $sync['sync_order_on_statuses']
			: array();
		if (empty($allowed) || !in_array($new_status, $allowed, true)) {
			return;
		}
		$sync_service = new Hesabix_V2_Sync_Service();
		$sync_service->sync_order($order_id);
	}

	/**
	 * AJAX: لیست برچسب‌های فاکتور از حسابیکس (برای مرجع در تنظیمات)
	 */
	public function ajax_get_invoice_tags()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$api = new Hesabix_V2_Api();
		$res = $api->list_invoice_tags(false);
		$items = array();
		if (!empty($res['success']) && isset($res['data']['items']) && is_array($res['data']['items'])) {
			foreach ($res['data']['items'] as $row) {
				if (isset($row['id'], $row['name'])) {
					$items[] = array(
						'id' => (int) $row['id'],
						'name' => (string) $row['name'],
					);
				}
			}
		}

		wp_send_json(array(
			'success' => !empty($res['success']),
			'message' => isset($res['message']) ? $res['message'] : '',
			'tags' => $items,
		));
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
	 * Compatible with WooCommerce HPOS (Custom Order Tables).
	 *
	 * @since    2.0.0
	 * @param    int    $order_id
	 */
	public function save_checkout_fields($order_id)
	{
		$order = wc_get_order($order_id);
		if (!$order) {
			return;
		}

		if (isset($_POST['billing_hesabix_v2_national_id'])) {
			$order->update_meta_data('_billing_hesabix_v2_national_id', sanitize_text_field(wp_unslash($_POST['billing_hesabix_v2_national_id'])));
		}

		if (isset($_POST['billing_hesabix_v2_economic_code'])) {
			$order->update_meta_data('_billing_hesabix_v2_economic_code', sanitize_text_field(wp_unslash($_POST['billing_hesabix_v2_economic_code'])));
		}

		$order->save();
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

	/**
	 * AJAX: بارگذاری لیست انبارها و حساب‌های بانکی برای کمبوباکس تنظیمات فاکتور
	 *
	 * @since    2.0.0
	 */
	public function ajax_get_warehouses_and_banks()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$api = new Hesabix_V2_Api();
		$warehouses = array();
		$banks = array();

		$wh_res = $api->get_warehouses();
		if (!empty($wh_res['success']) && !empty($wh_res['data'])) {
			$items = isset($wh_res['data']['items']) ? $wh_res['data']['items'] : (is_array($wh_res['data']) ? $wh_res['data'] : array());
			foreach ($items as $row) {
				$id = isset($row['id']) ? $row['id'] : (isset($row['warehouse_id']) ? $row['warehouse_id'] : null);
				$name = isset($row['name']) ? $row['name'] : (isset($row['title']) ? $row['title'] : (isset($row['code']) ? $row['code'] : (string) $id));
				$code = isset($row['code']) ? $row['code'] : '';
				if ($id !== null) {
					$warehouses[] = array('id' => (int) $id, 'name' => $name, 'code' => $code);
				}
			}
		}

		$bank_res = $api->get_bank_accounts();
		if (!empty($bank_res['success']) && !empty($bank_res['data'])) {
			$items = isset($bank_res['data']['items']) ? $bank_res['data']['items'] : (is_array($bank_res['data']) ? $bank_res['data'] : array());
			foreach ($items as $row) {
				$id = isset($row['id']) ? $row['id'] : (isset($row['bank_account_id']) ? $row['bank_account_id'] : null);
				$name = isset($row['name']) ? $row['name'] : (isset($row['account_name']) ? $row['account_name'] : (isset($row['code']) ? $row['code'] : (string) $id));
				$code = isset($row['code']) ? $row['code'] : (isset($row['account_number']) ? $row['account_number'] : '');
				if ($id !== null) {
					$banks[] = array('id' => (string) $id, 'name' => $name, 'code' => $code);
				}
			}
		}

		wp_send_json(array(
			'success' => true,
			'warehouses' => $warehouses,
			'banks' => $banks,
		));
	}

	// ==================== Setup Wizard AJAX ====================

	/**
	 * AJAX: Setup wizard - verify API key (Authorization: Bearer sk_...)
	 *
	 * @since    2.0.0
	 */
	public function ajax_setup_verify_api_key()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$api_key = isset($_POST['api_key']) ? sanitize_text_field(wp_unslash($_POST['api_key'])) : '';
		if (empty($api_key)) {
			wp_send_json(array('success' => false, 'message' => __('کلید API را وارد کنید.', 'hesabix-v2')));
		}

		// Update API base URL if provided
		if (!empty($_POST['api_base_url'])) {
			$url = esc_url_raw(trim(wp_unslash($_POST['api_base_url'])));
			if (!empty($url)) {
				update_option('hesabix_v2_api_base_url', rtrim($url, '/'));
			}
		}

		// Temporarily set API key and verify via GET /auth/me (Authorization: Bearer sk_...)
		update_option('hesabix_v2_api_key', $api_key);
		$api = new Hesabix_V2_Api();
		$result = $api->get_me();

		if (isset($result['success']) && $result['success']) {
			// Remove key - will be saved again in ajax_setup_complete
			delete_option('hesabix_v2_api_key');
			wp_send_json(array('success' => true));
		}

		// Remove invalid key
		delete_option('hesabix_v2_api_key');

		$message = $result['message'] ?? '';
		if (empty($message) && !empty($result['errors'])) {
			$err = is_array($result['errors']) ? reset($result['errors']) : $result['errors'];
			$message = is_string($err) ? $err : __('کلید API نامعتبر است.', 'hesabix-v2');
		}
		if (empty($message)) {
			$message = __('کلید API نامعتبر است یا منقضی شده. لطفاً از پنل حسابیکس کلید جدید دریافت کنید.', 'hesabix-v2');
		}

		wp_send_json(array('success' => false, 'message' => $message));
	}

	/**
	 * AJAX: Setup wizard - get businesses list
	 *
	 * @since    2.0.0
	 */
	public function ajax_setup_businesses()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$api_key = isset($_POST['api_key']) ? sanitize_text_field(wp_unslash($_POST['api_key'])) : '';
		if (empty($api_key)) {
			wp_send_json(array('success' => false, 'message' => __('کلید API را وارد کنید.', 'hesabix-v2')));
		}

		$api = new Hesabix_V2_Api();
		$result = $api->get_businesses($api_key);

		if (isset($result['success']) && $result['success']) {
			$data = $result['data'] ?? $result;
			// پاسخ: data.items (لیست کسب‌وکارها) - data ممکن است items, pagination, query_info داشته باشد
			$list = $data['items'] ?? $data['list'] ?? $data['data'] ?? array();
			if (is_array($data) && empty($list) && isset($data[0])) {
				$list = $data;
			}
			if (!is_array($list)) {
				$list = array();
			}
			wp_send_json(array('success' => true, 'businesses' => $list));
		}

		$message = $result['message'] ?? __('بارگذاری کسب‌وکارها ناموفق بود.', 'hesabix-v2');
		wp_send_json(array('success' => false, 'message' => $message));
	}

	/**
	 * AJAX: Setup wizard - get fiscal years for a business
	 *
	 * @since    2.0.0
	 */
	public function ajax_setup_fiscal_years()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$api_key = isset($_POST['api_key']) ? sanitize_text_field(wp_unslash($_POST['api_key'])) : '';
		$business_id = isset($_POST['business_id']) ? absint($_POST['business_id']) : 0;
		if (empty($api_key)) {
			wp_send_json(array('success' => false, 'message' => __('کلید API را وارد کنید.', 'hesabix-v2')));
		}
		if (!$business_id) {
			wp_send_json(array('success' => false, 'message' => __('کسب‌وکار انتخاب نشده.', 'hesabix-v2')));
		}

		$api = new Hesabix_V2_Api();
		$result = $api->get_fiscal_years($business_id, $api_key);

		if (isset($result['success']) && $result['success']) {
			$data = $result['data'] ?? $result;
			$list = is_array($data) ? $data : ($data['items'] ?? $data['list'] ?? $data['data'] ?? array());
			if (!is_array($list)) {
				$list = array();
			}

			wp_send_json(array('success' => true, 'fiscal_years' => $list));
		}

		$message = $result['message'] ?? __('بارگذاری سال‌های مالی ناموفق بود.', 'hesabix-v2');
		wp_send_json(array('success' => false, 'message' => $message));
	}

	/**
	 * AJAX: Setup wizard - save API key, business and complete
	 * سال مالی ارسال نمی‌شود - حسابیکس به‌صورت خودکار اسناد را به سال مالی جاری ارجاع می‌دهد.
	 *
	 * @since    2.0.0
	 */
	public function ajax_setup_complete()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');

		$api_key = isset($_POST['api_key']) ? sanitize_text_field(wp_unslash($_POST['api_key'])) : '';
		$business_id = isset($_POST['business_id']) ? absint($_POST['business_id']) : 0;

		if (empty($api_key)) {
			wp_send_json(array('success' => false, 'message' => __('کلید API را وارد کنید.', 'hesabix-v2')));
		}
		if (!$business_id) {
			wp_send_json(array('success' => false, 'message' => __('کسب‌وکار را انتخاب کنید.', 'hesabix-v2')));
		}

		update_option('hesabix_v2_api_key', $api_key);
		update_option('hesabix_v2_business_id', $business_id);
		update_option('hesabix_v2_fiscal_year_id', 0);
		update_option('hesabix_v2_enabled', true);
		update_option('hesabix_v2_setup_completed', true);
		delete_transient('hesabix_v2_show_setup_wizard');

		wp_send_json(array('success' => true, 'message' => __('راه‌اندازی با موفقیت انجام شد.', 'hesabix-v2')));
	}
}

