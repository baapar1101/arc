<?php
/**
 * The core plugin class.
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

class Hesabix_V2
{
	/**
	 * The loader that's responsible for maintaining and registering all hooks.
	 *
	 * @since    2.0.0
	 * @access   protected
	 * @var      Hesabix_V2_Loader    $loader
	 */
	protected $loader;

	/**
	 * The unique identifier of this plugin.
	 *
	 * @since    2.0.0
	 * @access   protected
	 * @var      string    $plugin_name
	 */
	protected $plugin_name;

	/**
	 * The current version of the plugin.
	 *
	 * @since    2.0.0
	 * @access   protected
	 * @var      string    $version
	 */
	protected $version;

	/**
	 * Define the core functionality of the plugin.
	 *
	 * @since    2.0.0
	 */
	public function __construct()
	{
		if (defined('HESABIX_V2_VERSION')) {
			$this->version = HESABIX_V2_VERSION;
		} else {
			$this->version = '2.0.0';
		}
		$this->plugin_name = 'arcwoc';

		$this->load_dependencies();
		$this->set_locale();
		$this->define_admin_hooks();
		$this->define_public_hooks();
	}

	/**
	 * Load the required dependencies for this plugin.
	 *
	 * @since    2.0.0
	 * @access   private
	 */
	private function load_dependencies()
	{
		/**
		 * The class responsible for orchestrating the actions and filters of the core plugin.
		 */
		require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-loader.php';

		/**
		 * The class responsible for defining internationalization functionality.
		 */
		require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-i18n.php';

		/**
		 * The class responsible for API communication.
		 */
		require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-api.php';

		/**
		 * The class responsible for data mapping.
		 */
		require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-mapper.php';

		/**
		 * Invoice / tag helpers for sync.
		 */
		require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-invoice-helper.php';

		/**
		 * The class responsible for validation.
		 */
		require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-validation.php';

		/**
		 * The class responsible for defining all actions in the admin area.
		 */
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/class-hesabix-v2-admin.php';

		/**
		 * Services
		 */
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/services/class-hesabix-v2-log-service.php';
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/services/class-hesabix-v2-db-service.php';
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/services/class-hesabix-v2-product-service.php';
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/services/class-hesabix-v2-customer-service.php';
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/services/class-hesabix-v2-invoice-service.php';
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/services/class-hesabix-v2-sync-service.php';

		$this->loader = new Hesabix_V2_Loader();
	}

	/**
	 * Define the locale for this plugin for internationalization.
	 *
	 * @since    2.0.0
	 * @access   private
	 */
	private function set_locale()
	{
		$plugin_i18n = new Hesabix_V2_i18n();
		$this->loader->add_action('plugins_loaded', $plugin_i18n, 'load_plugin_textdomain');
	}

	/**
	 * Register all of the hooks related to the admin area functionality.
	 *
	 * @since    2.0.0
	 * @access   private
	 */
	private function define_admin_hooks()
	{
		$plugin_admin = new Hesabix_V2_Admin($this->get_plugin_name(), $this->get_version());

		$this->loader->add_action('admin_enqueue_scripts', $plugin_admin, 'enqueue_styles');
		$this->loader->add_action('admin_enqueue_scripts', $plugin_admin, 'enqueue_scripts');
		$this->loader->add_action('admin_menu', $plugin_admin, 'add_admin_menu');
		
		// Check if plugin is configured
		if (get_option('hesabix_v2_enabled')) {
			// Product sync hooks
			$this->loader->add_action('woocommerce_update_product', $plugin_admin, 'on_product_update');
			$this->loader->add_action('woocommerce_new_product', $plugin_admin, 'on_product_create');
			$this->loader->add_action('before_delete_post', $plugin_admin, 'on_product_delete');
			
			// Order → invoice: زمان‌بندی از تنظیمات (چک‌اوت، پرداخت، تغییر وضعیت)
			$this->loader->add_action('woocommerce_checkout_order_processed', $plugin_admin, 'maybe_sync_order_on_checkout', 20, 3);
			$this->loader->add_action('woocommerce_payment_complete', $plugin_admin, 'maybe_sync_order_on_payment_complete', 10, 1);
			$this->loader->add_action('woocommerce_order_status_changed', $plugin_admin, 'maybe_sync_order_on_status_change', 10, 4);
			
			// Customer sync hooks
			$this->loader->add_action('user_register', $plugin_admin, 'on_customer_register');
			$this->loader->add_action('profile_update', $plugin_admin, 'on_customer_update');
		}

		// AJAX actions
		$this->loader->add_action('wp_ajax_hesabix_v2_test_connection', $plugin_admin, 'ajax_test_connection');
		$this->loader->add_action('wp_ajax_hesabix_v2_sync_product', $plugin_admin, 'ajax_sync_product');
		$this->loader->add_action('wp_ajax_hesabix_v2_sync_products', $plugin_admin, 'ajax_sync_products');
		$this->loader->add_action('wp_ajax_hesabix_v2_sync_customers', $plugin_admin, 'ajax_sync_customers');
		$this->loader->add_action('wp_ajax_hesabix_v2_get_warehouses_and_banks', $plugin_admin, 'ajax_get_warehouses_and_banks');
		$this->loader->add_action('wp_ajax_hesabix_v2_get_invoice_tags', $plugin_admin, 'ajax_get_invoice_tags');

		// Setup wizard AJAX
		$this->loader->add_action('wp_ajax_hesabix_v2_setup_verify_api_key', $plugin_admin, 'ajax_setup_verify_api_key');
		$this->loader->add_action('wp_ajax_hesabix_v2_setup_businesses', $plugin_admin, 'ajax_setup_businesses');
		$this->loader->add_action('wp_ajax_hesabix_v2_setup_fiscal_years', $plugin_admin, 'ajax_setup_fiscal_years');
		$this->loader->add_action('wp_ajax_hesabix_v2_setup_complete', $plugin_admin, 'ajax_setup_complete');
	}

	/**
	 * Register all of the hooks related to the public-facing functionality.
	 *
	 * @since    2.0.0
	 * @access   private
	 */
	private function define_public_hooks()
	{
		// Add custom checkout fields if enabled
		if (get_option('hesabix_v2_add_checkout_fields')) {
			$plugin_admin = new Hesabix_V2_Admin($this->get_plugin_name(), $this->get_version());
			$this->loader->add_filter('woocommerce_checkout_fields', $plugin_admin, 'add_checkout_fields');
			$this->loader->add_action('woocommerce_checkout_update_order_meta', $plugin_admin, 'save_checkout_fields');
		}
	}

	/**
	 * Run the loader to execute all of the hooks with WordPress.
	 *
	 * @since    2.0.0
	 */
	public function run()
	{
		$this->loader->run();
	}

	/**
	 * The name of the plugin used to uniquely identify it.
	 *
	 * @since     2.0.0
	 * @return    string
	 */
	public function get_plugin_name()
	{
		return $this->plugin_name;
	}

	/**
	 * Retrieve the version number of the plugin.
	 *
	 * @since     2.0.0
	 * @return    string
	 */
	public function get_version()
	{
		return $this->version;
	}
}

