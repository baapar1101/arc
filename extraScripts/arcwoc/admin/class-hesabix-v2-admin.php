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
	 * AJAX فقط برای کاربرانی که WooCommerce را مدیریت می‌کنند.
	 *
	 * @return void
	 */
	private function ajax_require_manage_wc()
	{
		if (!current_user_can('manage_woocommerce')) {
			wp_send_json(
				array(
					'success' => false,
					'message' => __('شما اجازهٔ انجام این عمل را ندارید.', 'hesabix-v2'),
				)
			);
		}
	}

	/**
	 * هشدار هم‌خوان نبودن ارز ووکامرس با ارز فاکتور حسابیکس (کل ادمین، برای مدیر فروشگاه).
	 *
	 * @return void
	 */
	public function maybe_admin_notice_currency_mismatch()
	{
		if (!is_admin() || !current_user_can('manage_woocommerce')) {
			return;
		}
		if (!class_exists('WooCommerce')) {
			return;
		}
		if (!get_option('hesabix_v2_enabled') || !get_option('hesabix_v2_api_key')) {
			return;
		}

		$ev = Hesabix_V2_Currency_Service::evaluate_currency_sync(new Hesabix_V2_Api(), null);
		if (!empty($ev['ok'])) {
			return;
		}

		echo '<div class="notice notice-error"><p>' . esc_html($ev['message']) . '</p></div>';
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
	 * @param string $hook_suffix Current admin page hook.
	 */
	public function enqueue_scripts($hook_suffix = '')
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
					'bulk_sync' => Hesabix_V2_Sync_Service::get_bulk_sync_options(),
					'strings' => array(
						'confirm_sync' => __('آیا مطمئن هستید؟', 'hesabix-v2'),
						'syncing' => __('در حال همگام‌سازی...', 'hesabix-v2'),
						'success' => __('با موفقیت انجام شد', 'hesabix-v2'),
						'error' => __('خطا رخ داد', 'hesabix-v2'),
						'testing_connection' => __('در حال بررسی اتصال...', 'hesabix-v2'),
						'loading_connection_detail' => __('در حال دریافت جزئیات کسب‌وکار...', 'hesabix-v2'),
						'connection_detail_failed' => __('جزئیات کسب‌وکار دریافت نشد.', 'hesabix-v2'),
						'warn_change_business_title' => __('هشدار', 'hesabix-v2'),
						/* translators: line breaks optional; modal body */
						'warn_change_business_body' => __(
							'برای اتصال کسب‌وکار دیگری به افزونه، ابتدا افزونه را حذف و مجدد نصب کنید تا ارتباطات کسب‌وکار قبلی پاک شود.',
							'hesabix-v2'
						),
						'warn_change_business_ok' => __('متوجه شدم؛ ادامه', 'hesabix-v2'),
						'warn_change_business_cancel' => __('انصراف', 'hesabix-v2'),
						'lbl_linked_business' => __('کسب‌وکار متصل', 'hesabix-v2'),
						'lbl_business_id' => __('شناسه کسب‌وکار', 'hesabix-v2'),
						'lbl_owner' => __('مالک در حسابیکس', 'hesabix-v2'),
						'lbl_your_role' => __('نقش شما', 'hesabix-v2'),
						'lbl_owner_suffix' => __('مالک', 'hesabix-v2'),
						'lbl_field' => __('زمینه فعالیت', 'hesabix-v2'),
						'lbl_type' => __('نوع شخصیت', 'hesabix-v2'),
						'lbl_fiscal_current' => __('سال مالی جاری حسابیکس', 'hesabix-v2'),
						'lbl_fiscal_dates' => __('بازه', 'hesabix-v2'),
						'lbl_api_key_owner' => __('صاحب کلید API در حسابیکس', 'hesabix-v2'),
					),
				)
			);

			if (isset($_GET['page']) && sanitize_text_field(wp_unslash((string) $_GET['page'])) === 'hesabix-v2-orders') {
				wp_enqueue_script(
					'hesabix-v2-orders',
					HESABIX_V2_PLUGIN_URL . 'assets/js/hesabix-v2-orders.js',
					array('jquery'),
					$this->version,
					true
				);
				$bulk_o = Hesabix_V2_Sync_Service::get_bulk_sync_options();
				$o_chunk = isset($bulk_o['wc_orders_ajax_batch']) ? (int) $bulk_o['wc_orders_ajax_batch'] : 40;
				wp_localize_script(
					'hesabix-v2-orders',
					'hesabix_v2_orders',
					array(
						'ajax_url' => admin_url('admin-ajax.php'),
						'nonce' => wp_create_nonce('hesabix_v2_nonce'),
						'chunk_size' => max(5, min(Hesabix_V2_Sync_Service::BULK_WC_CHUNK_MAX_ITEMS, $o_chunk)),
						'strings' => array(
							'genericError' => __('عملیات ناموفق بود.', 'hesabix-v2'),
							'requestFailed' => __('خطا در ارتباط با سرور.', 'hesabix-v2'),
							'confirmSync' => __('ارسال یا به‌روزرسانی این سفارش در حسابیکس انجام شود؟', 'hesabix-v2'),
							'confirmUnsync' => __('فاکتور این سفارش در حسابیکس حذف و پیوند افزونه پاک شود؟ این کار برگشت‌پذیر نیست.', 'hesabix-v2'),
							'confirmBulkSync' => __('برای همهٔ سفارش‌های انتخاب‌شده ارسال یا به‌روزرسانی انجام شود؟', 'hesabix-v2'),
							'confirmBulkUnsync' => __('برای همهٔ موارد انتخاب‌شده لغو ارسال (حذف فاکتور) انجام شود؟', 'hesabix-v2'),
							'confirmPause' => __('همگام‌سازی خودکار این سفارش متوقف شود؟ (فاکتورهای دستی در حسابیکس با به‌روزرسانی خودکار بازنویسی نمی‌شوند.)', 'hesabix-v2'),
							'confirmResume' => __('همگام‌سازی خودکار دوباره فعال شود؟ در رویدادهای بعدی، محتوای ووکامرس ممکن است فاکتور حسابیکس را به‌روز کند.', 'hesabix-v2'),
						),
					)
				);
			}

			if (isset($_GET['page']) && sanitize_text_field(wp_unslash((string) $_GET['page'])) === 'hesabix-v2-customers') {
				wp_enqueue_script(
					'hesabix-v2-customers',
					HESABIX_V2_PLUGIN_URL . 'assets/js/hesabix-v2-customers.js',
					array('jquery'),
					$this->version,
					true
				);
				$bco = Hesabix_V2_Sync_Service::get_bulk_sync_options();
				$c_chunk = isset($bco['wc_customers_per_ajax']) ? (int) $bco['wc_customers_per_ajax'] : 45;

				wp_localize_script(
					'hesabix-v2-customers',
					'hesabix_v2_customers',
					array(
						'ajax_url' => admin_url('admin-ajax.php'),
						'nonce' => wp_create_nonce('hesabix_v2_nonce'),
						'chunk_size' => max(5, min(Hesabix_V2_Sync_Service::BULK_WC_CHUNK_MAX_ITEMS, $c_chunk)),
						'strings' => array(
							'genericError' => __('عملیات ناموفق بود.', 'hesabix-v2'),
							'requestFailed' => __('خطا در ارتباط با سرور.', 'hesabix-v2'),
							'confirmSync' => __('این مشتری با حسابیکس همگام شود؟ در صورت وجود نگاشت، اطلاعات به‌روز می‌شود.', 'hesabix-v2'),
							'confirmBulkSync' => __('برای تمام مشتریان انتخاب‌شده همگام‌سازی با حسابیکس انجام شود؟', 'hesabix-v2'),
						),
					)
				);
			}

			if (isset($_GET['page']) && sanitize_text_field(wp_unslash((string) $_GET['page'])) === 'hesabix-v2-products') {
				wp_enqueue_script(
					'hesabix-v2-products',
					HESABIX_V2_PLUGIN_URL . 'assets/js/hesabix-v2-products.js',
					array('jquery'),
					$this->version,
					true
				);
				$bcp = Hesabix_V2_Sync_Service::get_bulk_sync_options();
				$p_chunk = isset($bcp['wc_product_parents_per_ajax']) ? (int) $bcp['wc_product_parents_per_ajax'] : 35;

				wp_localize_script(
					'hesabix-v2-products',
					'hesabix_v2_products',
					array(
						'ajax_url' => admin_url('admin-ajax.php'),
						'nonce' => wp_create_nonce('hesabix_v2_nonce'),
						'chunk_size' => max(5, min(Hesabix_V2_Sync_Service::BULK_WC_CHUNK_MAX_ITEMS, $p_chunk)),
						'strings' => array(
							'genericError' => __('عملیات ناموفق بود.', 'hesabix-v2'),
							'requestFailed' => __('خطا در ارتباط با سرور.', 'hesabix-v2'),
							'confirmSync' => __('این محصول (و در صورت متغیر بودن، واریانت‌ها) با حسابیکس همگام شود؟', 'hesabix-v2'),
							'confirmBulkSync' => __('برای تمام محصولات انتخاب‌شده همگام‌سازی با حسابیکس انجام شود؟', 'hesabix-v2'),
						),
					)
				);
			}

			$on_settings_page = ($hook_suffix === 'hesabix-v2_page_hesabix-v2-settings')
				|| (isset($_GET['page']) && sanitize_text_field(wp_unslash((string) $_GET['page'])) === 'hesabix-v2-settings');

			if ($on_settings_page) {
				wp_enqueue_script(
					'hesabix-v2-admin-update',
					HESABIX_V2_PLUGIN_URL . 'assets/js/hesabix-v2-admin-update.js',
					array('jquery'),
					$this->version,
					true
				);
				wp_localize_script(
					'hesabix-v2-admin-update',
					'HESABIX_V2_UPD',
					array(
						'ajaxUrl' => admin_url('admin-ajax.php'),
						'nonce' => wp_create_nonce(HESABIX_V2_UPDATE_NONCE_ACTION),
						'actions' => array(
							'check' => HESABIX_V2_UPDATE_AJAX_CHECK,
							'install' => HESABIX_V2_UPDATE_AJAX_INSTALL,
						),
						'strings' => array(
							'checking' => __('در حال بررسی با سرور…', 'hesabix-v2'),
							'installing' => __('در حال دریافت و نصب به‌روزرسانی، لطفاً صبر کنید…', 'hesabix-v2'),
							'reloadHint' => __('به‌روزرسانی انجام شد؛ صفحه در حال تازه‌سازی است.', 'hesabix-v2'),
							'genericError' => __('درخواست ناموفق بود.', 'hesabix-v2'),
							'remoteShort' => __('نامشخص', 'hesabix-v2'),
							'sourceLabelOff' => __('تنظیم نشده', 'hesabix-v2'),
							'sourceRawZip' => __('فایل خام hesabix-v2.php + بستهٔ zip', 'hesabix-v2'),
							'sourceManifest' => __('مانیفست JSON', 'hesabix-v2'),
							'sourceMixed' => __('ترکیبی', 'hesabix-v2'),
							'sourceDisabledSummary' => __('منبع به‌روزرسانی تنظیم نشده؛ ثابت‌ها را در wp-config یا فایل اصلی افزونه بررسی کنید.', 'hesabix-v2'),
							'summaryNoRemote' => __('به منبع وصل نشد یا نسخه‌ای خوانده نشد؛ «بررسی مجدد» را بزنید.', 'hesabix-v2'),
							'summaryUpdateReady' => __('نسخهٔ جدیدتری موجود است؛ می‌توانید همین‌جا از بستهٔ zip نصب کنید.', 'hesabix-v2'),
							'summaryUpToDate' => __('نسخهٔ نصب‌شده با منبع هم‌خوان است (یا نسخهٔ محلی جدیدتر است).', 'hesabix-v2'),
							'blockedEnv' => __('نسخهٔ جدید روی مخزن است؛ ولی وردپرس یا PHP الزامات را نمی‌گذرد.', 'hesabix-v2'),
							'requirementsUnknown' => __('نامشخص', 'hesabix-v2'),
							'requirementsFmt' => __('وردپرس ≥ {{w}}؛ PHP ≥ {{p}}', 'hesabix-v2'),
						),
					)
				);

				wp_enqueue_script(
					'hesabix-v2-opening-inventory',
					HESABIX_V2_PLUGIN_URL . 'assets/js/hesabix-v2-opening-inventory.js',
					array('jquery'),
					$this->version,
					true
				);
				wp_localize_script(
					'hesabix-v2-opening-inventory',
					'hesabix_v2_ob_inv',
					array_merge(
						array(
							'ajax_url' => admin_url('admin-ajax.php'),
							'nonce' => wp_create_nonce('hesabix_v2_nonce'),
							'completed' => (bool) get_option('hesabix_v2_opening_inventory_completed'),
						),
						$this->get_opening_inventory_script_payload()
					)
				);
			}
		}
	}

	/**
	 * Add admin menu
	 *
	 * @since    2.0.0
	 */
	public function add_admin_menu()
	{
		if (!function_exists('is_plugin_active')) {
			require_once ABSPATH . 'wp-admin/includes/plugin.php';
		}

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

		add_submenu_page(
			'hesabix-v2',
			__('سفارش‌ها و حسابیکس', 'hesabix-v2'),
			__('سفارش‌ها و حسابیکس', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2-orders',
			array($this, 'display_orders')
		);

		add_submenu_page(
			'hesabix-v2',
			__('مشتریان و حسابیکس', 'hesabix-v2'),
			__('مشتریان', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2-customers',
			array($this, 'display_customers')
		);

		add_submenu_page(
			'hesabix-v2',
			__('محصولات و حسابیکس', 'hesabix-v2'),
			__('محصولات', 'hesabix-v2'),
			'manage_woocommerce',
			'hesabix-v2-products',
			array($this, 'display_products')
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
		if (isset($_POST['hesabix_v2_save_bulk_sync'])) {
			if (!check_admin_referer('hesabix_v2_bulk_sync_save')) {
				wp_die(esc_html__('خطای امنیتی.', 'hesabix-v2'));
			}
			$this->save_bulk_sync_settings();
			wp_safe_redirect(add_query_arg('hesabix_bulk_saved', '1', admin_url('admin.php?page=hesabix-v2-sync')));
			exit;
		}

		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-sync.php';
	}

	/**
	 * ذخیره اندازهٔ دسته برای همگام‌سازی/واردات سنگین.
	 *
	 * @since 2.0.7
	 */
	private function save_bulk_sync_settings()
	{
		if (!current_user_can('manage_woocommerce')) {
			wp_die(esc_html__('فقط کاربر با مجوز مدیریت ووکامرس.', 'hesabix-v2'));
		}

		$d = Hesabix_V2_Sync_Service::get_bulk_sync_defaults();
		$opt = array(
			'wc_product_parents_per_ajax' => isset($_POST['wc_product_parents_per_ajax'])
				? absint(wp_unslash($_POST['wc_product_parents_per_ajax']))
				: $d['wc_product_parents_per_ajax'],
			'wc_categories_per_ajax' => isset($_POST['wc_categories_per_ajax'])
				? absint(wp_unslash($_POST['wc_categories_per_ajax']))
				: $d['wc_categories_per_ajax'],
			'wc_customers_per_ajax' => isset($_POST['wc_customers_per_ajax'])
				? absint(wp_unslash($_POST['wc_customers_per_ajax']))
				: $d['wc_customers_per_ajax'],
			'wc_orders_ajax_batch' => isset($_POST['wc_orders_ajax_batch'])
				? absint(wp_unslash($_POST['wc_orders_ajax_batch']))
				: ($d['wc_orders_ajax_batch'] ?? 40),
			'api_bulk_persons_per_request' => isset($_POST['api_bulk_persons_per_request'])
				? absint(wp_unslash($_POST['api_bulk_persons_per_request']))
				: ($d['api_bulk_persons_per_request'] ?? 35),
			'api_bulk_invoices_per_request' => isset($_POST['api_bulk_invoices_per_request'])
				? absint(wp_unslash($_POST['api_bulk_invoices_per_request']))
				: ($d['api_bulk_invoices_per_request'] ?? 8),
			'api_bulk_products_per_request' => isset($_POST['api_bulk_products_per_request'])
				? absint(wp_unslash($_POST['api_bulk_products_per_request']))
				: ($d['api_bulk_products_per_request'] ?? 20),
			'hesabix_person_take' => isset($_POST['hesabix_person_take'])
				? absint(wp_unslash($_POST['hesabix_person_take']))
				: $d['hesabix_person_take'],
			'hesabix_import_pages_per_ajax' => isset($_POST['hesabix_import_pages_per_ajax'])
				? absint(wp_unslash($_POST['hesabix_import_pages_per_ajax']))
				: $d['hesabix_import_pages_per_ajax'],
			'errors_preview_cap' => isset($_POST['errors_preview_cap'])
				? absint(wp_unslash($_POST['errors_preview_cap']))
				: $d['errors_preview_cap'],
		);

		update_option('hesabix_v2_bulk_sync', $opt);
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
	 * فهرست سفارش‌ها، وضعیت حسابیکس، ارسال/لغو دستی
	 *
	 * @return void
	 */
	public function display_orders()
	{
		if (!current_user_can('manage_woocommerce')) {
			wp_die(esc_html__('شما اجازهٔ دسترسی ندارید.', 'hesabix-v2'));
		}

		require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/class-hesabix-v2-orders-list-table.php';
		$list_table = new Hesabix_V2_Orders_List_Table();
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-orders.php';
	}

	/**
	 * فهرست مشتریان و همگام‌سازی شخص با حسابیکس.
	 *
	 * @since      3.3.5
	 * @return void
	 */
	public function display_customers()
	{
		if (!current_user_can('manage_woocommerce')) {
			wp_die(esc_html__('شما اجازهٔ دسترسی ندارید.', 'hesabix-v2'));
		}

		require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/class-hesabix-v2-customers-list-table.php';
		$list_table = new Hesabix_V2_Customers_List_Table();
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-customers.php';
	}

	/**
	 * فهرست محصولات والد و همگام‌سازی کالا با حسابیکس.
	 *
	 * @return void
	 */
	public function display_products()
	{
		if (!current_user_can('manage_woocommerce')) {
			wp_die(esc_html__('شما اجازهٔ دسترسی ندارید.', 'hesabix-v2'));
		}

		require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/class-hesabix-v2-products-list-table.php';
		$list_table = new Hesabix_V2_Products_List_Table();
		require_once HESABIX_V2_PLUGIN_DIR . 'admin/partials/hesabix-v2-products.php';
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
	 * کمبوی چندگانهٔ برچسب اضافی: آرایه → رشتهٔ ویرگول‌دار (هم‌خوان با parse_extra_tag_ids).
	 *
	 * @return string
	 */
	private static function sanitize_invoice_extra_tag_ids_from_post()
	{
		$raw = isset($_POST['invoice_extra_tag_ids'])
			? wp_unslash($_POST['invoice_extra_tag_ids'])
			: '';
		if (is_string($raw)) {
			$raw = $raw !== '' ? array($raw) : array();
		}
		if (!is_array($raw)) {
			$raw = array();
		}
		$ids = array();
		foreach ($raw as $part) {
			$id = absint($part);
			if ($id > 0) {
				$ids[] = $id;
			}
		}
		$ids = array_values(array_unique($ids));

		return implode(',', $ids);
	}

	/**
	 * Save settings
	 *
	 * @since    2.0.0
	 */
	private function save_settings()
	{
		// Sync settings (قالب واحد با Hesabix_V2_Invoice_Helper::normalize_sync_settings)
		$prev_sync = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
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

		$invoice_tab_in_post = isset($_POST['hesabix_v2_invoice_tab_fields']);
		$finalize_proforma_on_paid = !empty($prev_sync['finalize_proforma_on_paid']);
		$finalize_proforma_order_statuses = isset($prev_sync['finalize_proforma_order_statuses']) && is_array($prev_sync['finalize_proforma_order_statuses'])
			? $prev_sync['finalize_proforma_order_statuses']
			: array('processing', 'completed');
		if ($invoice_tab_in_post) {
			$finalize_proforma_on_paid = isset($_POST['finalize_proforma_on_paid']);
			$finalize_proforma_order_statuses = array();
			if (isset($_POST['finalize_proforma_order_statuses']) && is_array($_POST['finalize_proforma_order_statuses'])) {
				foreach ($_POST['finalize_proforma_order_statuses'] as $st) {
					$st = sanitize_text_field(wp_unslash($st));
					if ($st !== '' && isset($status_choices[$st])) {
						$finalize_proforma_order_statuses[] = $st;
					}
				}
			}
		}

		$sync_settings = array(
			'auto_sync_products' => isset($_POST['auto_sync_products']),
			'auto_sync_customers' => isset($_POST['auto_sync_customers']),
			'auto_sync_orders' => isset($_POST['auto_sync_orders']),
			'sync_on_product_update' => isset($_POST['sync_on_product_update']),
			'sync_product_categories' => isset($_POST['sync_product_categories']),
			'sync_category_link_by_name_in_hesabix' => isset($_POST['sync_category_link_by_name_in_hesabix']),
			'sync_product_price' => isset($_POST['sync_product_price']),
			'sync_product_stock' => isset($_POST['sync_product_stock']),
			'track_inventory_policy' => isset($_POST['track_inventory_policy'])
				? sanitize_key(wp_unslash($_POST['track_inventory_policy']))
				: 'wc',
			'create_customer_on_order' => isset($_POST['create_customer_on_order']),
			'sync_order_on_checkout' => isset($_POST['sync_order_on_checkout']),
			'sync_order_on_payment_complete' => isset($_POST['sync_order_on_payment_complete']),
			'sync_order_on_statuses' => $sync_order_on_statuses,
			'invoice_is_proforma' => isset($_POST['invoice_doc_mode']) && sanitize_text_field(wp_unslash($_POST['invoice_doc_mode'])) === 'proforma',
			'finalize_proforma_on_paid' => $finalize_proforma_on_paid,
			'finalize_proforma_order_statuses' => $finalize_proforma_order_statuses,
			'invoice_tag_website_enabled' => isset($_POST['invoice_tag_website_enabled']),
			'invoice_tag_website_name' => isset($_POST['invoice_tag_website_name'])
				? sanitize_text_field(wp_unslash($_POST['invoice_tag_website_name']))
				: 'فروش سایت',
			'invoice_extra_tag_ids' => self::sanitize_invoice_extra_tag_ids_from_post(),
			'shipping_line_mode' => isset($_POST['shipping_line_mode'])
				? sanitize_key(wp_unslash($_POST['shipping_line_mode']))
				: 'service',
			'shipping_adjustment_account_id' => isset($_POST['shipping_adjustment_account_id'])
				? absint(wp_unslash($_POST['shipping_adjustment_account_id']))
				: 0,
			'order_fiscal_year_date_policy' => isset($_POST['order_fiscal_year_date_policy'])
				? sanitize_key(wp_unslash($_POST['order_fiscal_year_date_policy']))
				: 'keep',
			'queue_items_per_cron_run' => isset($_POST['queue_items_per_cron_run'])
				? max(1, min(500, absint(wp_unslash($_POST['queue_items_per_cron_run']))))
				: 15,
		);

		$fiscal_policy_allowed = array('keep', 'clamp', 'skip');
		if (!in_array($sync_settings['order_fiscal_year_date_policy'], $fiscal_policy_allowed, true)) {
			$sync_settings['order_fiscal_year_date_policy'] = 'keep';
		}

		$policy_allowed = array('wc', 'physical_always', 'always_on', 'always_off');
		if (!isset($sync_settings['track_inventory_policy']) || !in_array($sync_settings['track_inventory_policy'], $policy_allowed, true)) {
			$sync_settings['track_inventory_policy'] = 'wc';
		}
		if (!in_array($sync_settings['shipping_line_mode'], array('service', 'account_adjustment'), true)) {
			$sync_settings['shipping_line_mode'] = 'service';
		}

		update_option('hesabix_v2_sync_settings', $sync_settings);
		if (class_exists('Hesabix_V2_Order_Fiscal_Service')) {
			Hesabix_V2_Order_Fiscal_Service::invalidate_bounds_cache();
		}
		update_option('hesabix_v2_debug_mode', isset($_POST['debug_mode']));
		update_option('hesabix_v2_add_checkout_fields', isset($_POST['add_checkout_fields']));

		$ob_cost = isset($_POST['ob_inv_cost_basis']) ? sanitize_key(wp_unslash($_POST['ob_inv_cost_basis'])) : 'regular';
		if (!in_array($ob_cost, array('regular', 'sale', 'zero'), true)) {
			$ob_cost = 'regular';
		}
		$ob_inv_prefs = array(
			'include_tax' => isset($_POST['ob_inv_include_tax']),
			'cost_basis' => $ob_cost,
			'auto_balance_to_equity' => isset($_POST['ob_inv_auto_balance']),
			'do_post' => isset($_POST['ob_inv_do_post']),
			'batch_size' => isset($_POST['ob_inv_batch_size']) ? max(3, min(40, absint(wp_unslash($_POST['ob_inv_batch_size'])))) : 12,
			'inventory_account_id' => isset($_POST['ob_inv_inventory_account_id']) ? absint(wp_unslash($_POST['ob_inv_inventory_account_id'])) : 0,
			'equity_account_id' => isset($_POST['ob_inv_equity_account_id']) ? absint(wp_unslash($_POST['ob_inv_equity_account_id'])) : 0,
			'warehouse_override' => isset($_POST['ob_inv_warehouse_override']) ? absint(wp_unslash($_POST['ob_inv_warehouse_override'])) : 0,
		);
		update_option('hesabix_v2_opening_inventory_prefs', $ob_inv_prefs);

		// API base URL - allow configuring server address
		if (isset($_POST['api_base_url'])) {
			$url = esc_url_raw(trim(wp_unslash($_POST['api_base_url'])));
			if (!empty($url)) {
				$url = rtrim($url, '/');
				update_option('hesabix_v2_api_base_url', $url);
				Hesabix_V2_Currency_Service::invalidate_list_cache();
			}
		}

		if (isset($_POST['hesabix_v2_currency_id'])) {
			$raw = sanitize_text_field(wp_unslash($_POST['hesabix_v2_currency_id']));
			if ($raw === '' || $raw === '0') {
				update_option('hesabix_v2_currency_id', 0);
			} else {
				update_option('hesabix_v2_currency_id', absint($raw));
			}
			Hesabix_V2_Currency_Service::invalidate_list_cache();
		}
		if (isset($_POST['hesabix_v2_default_warehouse_id'])) {
			$v = sanitize_text_field(wp_unslash($_POST['hesabix_v2_default_warehouse_id']));
			update_option('hesabix_v2_default_warehouse_id', $v === '' ? '' : absint($v));
		}

		$scope = isset($_POST['stock_pull_warehouse_scope'])
			? sanitize_key(wp_unslash($_POST['stock_pull_warehouse_scope']))
			: 'default';
		if (!in_array($scope, array('default', 'selected', 'all'), true)) {
			$scope = 'default';
		}
		$sp_wh_ids = array();
		if (!empty($_POST['stock_pull_warehouse_ids']) && is_array($_POST['stock_pull_warehouse_ids'])) {
			foreach ($_POST['stock_pull_warehouse_ids'] as $wid_raw) {
				$wid = absint(wp_unslash($wid_raw));
				if ($wid > 0) {
					$sp_wh_ids[] = $wid;
				}
			}
		}
		$sp_wh_ids = array_values(array_unique($sp_wh_ids));
		$cron_min = isset($_POST['stock_pull_cron_minutes'])
			? absint(wp_unslash($_POST['stock_pull_cron_minutes']))
			: 15;
		$cron_min = max(5, min(180, $cron_min));

		update_option(
			'hesabix_v2_stock_pull',
			array(
				'enabled' => isset($_POST['stock_pull_enabled']),
				'warehouse_scope' => $scope,
				'warehouse_ids' => $sp_wh_ids,
				'cron_minutes' => $cron_min,
				'force_manage_stock' => isset($_POST['stock_pull_force_manage_stock']),
				'disable_wc_stock_reduction' => isset($_POST['stock_pull_disable_wc_reduce']),
			)
		);
		Hesabix_V2_Stock_Pull_Service::reschedule_cron();

		$inv_resolution = isset($_POST['invoice_wh_resolution'])
			? sanitize_key(wp_unslash($_POST['invoice_wh_resolution']))
			: 'default';
		if (!in_array($inv_resolution, array('default', 'rules'), true)) {
			$inv_resolution = 'default';
		}
		$inv_types = isset($_POST['inv_wh_r_type']) && is_array($_POST['inv_wh_r_type'])
			? wp_unslash($_POST['inv_wh_r_type'])
			: array();
		$inv_keys = isset($_POST['inv_wh_r_key']) && is_array($_POST['inv_wh_r_key'])
			? wp_unslash($_POST['inv_wh_r_key'])
			: array();
		$inv_wids = isset($_POST['inv_wh_r_wid']) && is_array($_POST['inv_wh_r_wid'])
			? wp_unslash($_POST['inv_wh_r_wid'])
			: array();
		$inv_rule_count = max(count($inv_types), count($inv_keys), count($inv_wids));
		$inv_rule_count = min(40, $inv_rule_count);
		$inv_rules = array();
		for ($ri = 0; $ri < $inv_rule_count; $ri++) {
			$t = isset($inv_types[ $ri ]) ? sanitize_key((string) $inv_types[ $ri ]) : '';
			if ($t !== 'shipping_method' && $t !== 'shipping_zone') {
				continue;
			}
			$k = isset($inv_keys[ $ri ]) ? trim((string) $inv_keys[ $ri ]) : '';
			$w = isset($inv_wids[ $ri ]) ? absint($inv_wids[ $ri ]) : 0;
			if ($k === '' || $w < 1) {
				continue;
			}
			if ($t === 'shipping_zone') {
				$k = (string) absint($k);
			}
			$inv_rules[] = array(
				'type' => $t,
				'key' => $k,
				'warehouse_id' => $w,
			);
		}
		update_option(
			Hesabix_V2_Invoice_Warehouse_Service::OPTION_KEY,
			array(
				'resolution' => $inv_resolution,
				'rules' => $inv_rules,
			)
		);
		if (isset($_POST['hesabix_v2_default_bank_id'])) {
			update_option('hesabix_v2_default_bank_id', sanitize_text_field(wp_unslash($_POST['hesabix_v2_default_bank_id'])));
		}
		if (isset($_POST['hesabix_v2_invoice_payment_destination'])) {
			$pd = sanitize_text_field(wp_unslash($_POST['hesabix_v2_invoice_payment_destination']));
			update_option('hesabix_v2_invoice_payment_destination', $pd === 'cash_register' ? 'cash_register' : 'bank');
		}
		if (isset($_POST['hesabix_v2_default_cash_register_id'])) {
			$v = sanitize_text_field(wp_unslash($_POST['hesabix_v2_default_cash_register_id']));
			update_option('hesabix_v2_default_cash_register_id', $v === '' ? '' : absint($v));
		}

		update_option(Hesabix_V2_Bridge_Rest::OPT_ENABLED, isset($_POST['hesabix_v2_bridge_enabled']));

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
	 * رد کردن همگام‌سازی خودکار برای این سفارش (فلگ توقف توسط کاربر).
	 *
	 * @param int $order_id
	 * @return bool اگر true باشد نباید sync_order از هوک‌های خودکار صدا زده شود.
	 */
	private function should_skip_auto_order_sync($order_id)
	{
		$order_id = (int) $order_id;
		if ($order_id < 1) {
			return false;
		}
		if (!class_exists('Hesabix_V2_Order_Sync_Meta')) {
			return false;
		}
		if (!Hesabix_V2_Order_Sync_Meta::is_pause_auto_sync($order_id)) {
			return false;
		}

		Hesabix_V2_Log_Service::info(
			'Order auto sync skipped (pause_auto_sync meta)',
			array(
				'entity_type' => 'order',
				'entity_id' => $order_id,
			)
		);
		return true;
	}

	/**
	 * همگام‌سازی سفارش در پس‌زمینه (صف Cron) تا درخواست ادمین/چک‌اوت به‌خاطر کندی API حسابیکس 504 ندهد.
	 *
	 * @param int $order_id
	 * @return void
	 */
	private function defer_auto_order_sync_to_queue($order_id)
	{
		$order_id = (int) $order_id;
		if ($order_id < 1) {
			return;
		}

		Hesabix_V2_Queue_Service::enqueue('order', $order_id, 'sync_order');

		// بدون spawn_cron: آن درخواست loopback اغلب همان بدنهٔ ذخیرهٔ سفارش را منتظر یا PHP-FPM را اشغال می‌کند.
		$scheduled = false;
		if (function_exists('as_enqueue_async_action')) {
			$id = as_enqueue_async_action('hesabix_v2_async_process_queue', array(), 'hesabix-v2-queue', true);
			$scheduled = is_int($id) && $id > 0;
		}

		if (!$scheduled && !get_transient('hesabix_v2_queue_wp_cron_sched')) {
			set_transient('hesabix_v2_queue_wp_cron_sched', '1', 90);
			wp_schedule_single_event(time() + 2, 'hesabix_v2_process_queue');
		}
	}

	/**
	 * فقط کاربران با نقش customer (مشتری فروشگاه) همگام شوند، نه هر کاربر وردپرس.
	 *
	 * @param int $user_id
	 * @return bool
	 */
	private function should_sync_wp_user_as_customer($user_id)
	{
		if ($user_id < 1) {
			return false;
		}
		$user = get_userdata($user_id);
		if (!$user || empty($user->roles)) {
			return false;
		}

		return in_array('customer', (array) $user->roles, true);
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
		if ($this->should_skip_auto_order_sync($order_id)) {
			return;
		}
		$this->defer_auto_order_sync_to_queue($order_id);
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
		$sync_on_payment = !empty($sync['sync_order_on_payment_complete']);
		$proforma_promote = !empty($sync['invoice_is_proforma']) && !empty($sync['finalize_proforma_on_paid']);
		if (!$sync_on_payment && !$proforma_promote) {
			return;
		}
		if ($this->should_skip_auto_order_sync($order_id)) {
			return;
		}
		$this->defer_auto_order_sync_to_queue($order_id);
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
		$new_slug = Hesabix_V2_Invoice_Helper::normalize_order_status_slug($new_status);
		$promote_statuses = isset($sync['finalize_proforma_order_statuses']) && is_array($sync['finalize_proforma_order_statuses'])
			? $sync['finalize_proforma_order_statuses']
			: array();
		$proforma_promote = false;
		if (!empty($sync['invoice_is_proforma']) && $new_slug !== '') {
			foreach ($promote_statuses as $ps) {
				if ($new_slug === Hesabix_V2_Invoice_Helper::normalize_order_status_slug($ps)) {
					$proforma_promote = true;
					break;
				}
			}
		}
		$in_sync_list = !empty($allowed) && in_array($new_status, $allowed, true);
		if (!$in_sync_list && !$proforma_promote) {
			return;
		}
		if ($this->should_skip_auto_order_sync($order_id)) {
			return;
		}
		$this->defer_auto_order_sync_to_queue($order_id);
	}

	/**
	 * متاباکس سفارش: توقف همگام خودکار + لینک به فهرست
	 *
	 * @return void
	 */
	public function add_order_hesabix_meta_box()
	{
		$screens = array('shop_order');
		if (function_exists('wc_get_page_screen_id')) {
			$screens[] = wc_get_page_screen_id('shop-order');
		}
		foreach (array_unique($screens) as $screen) {
			if (!$screen) {
				continue;
			}
			add_meta_box(
				'hesabix_v2_order_sync_panel',
				__('حسابیکس — همگام‌سازی', 'hesabix-v2'),
				array($this, 'render_order_hesabix_meta_box'),
				$screen,
				'side',
				'default'
			);
		}
	}

	/**
	 * @param WP_Post|WC_Order $post_or_order_object
	 * @return void
	 */
	public function render_order_hesabix_meta_box($post_or_order_object)
	{
		if (!current_user_can('manage_woocommerce')) {
			return;
		}

		$order = ($post_or_order_object instanceof WP_Post)
			? wc_get_order($post_or_order_object->ID)
			: $post_or_order_object;
		if (!$order instanceof WC_Order) {
			return;
		}

		$oid = (int) $order->get_id();
		wp_nonce_field('hesabix_v2_order_panel', 'hesabix_v2_order_panel_nonce');
		$paused = Hesabix_V2_Order_Sync_Meta::is_pause_auto_sync($oid);
		$row = Hesabix_V2_Invoice_Service::get_sync_status($oid);
		$hx_status = __('ارسال نشده', 'hesabix-v2');
		if ($row && !empty($row['hesabix_id'])) {
			$st = isset($row['sync_status']) ? (string) $row['sync_status'] : 'synced';
			if ($st === 'error') {
				$hx_status = __('خطا', 'hesabix-v2');
			} elseif ($st === 'pending') {
				$hx_status = __('در انتظار', 'hesabix-v2');
			} else {
				$hx_status = sprintf(
					/* translators: %d: Hesabix invoice id */
					__('ارسال شده (فاکتور %d)', 'hesabix-v2'),
					(int) $row['hesabix_id']
				);
			}
		}

		echo '<p><strong>' . esc_html__('وضعیت حسابیکس:', 'hesabix-v2') . '</strong> ' . esc_html($hx_status) . '</p>';
		echo '<p class="description">' . esc_html__(
			'اگر فاکتور را در حسابیکس دستی ویرایش کرده‌اید، با فعال کردن گزینهٔ زیر از بازنویسی خودکار توسط ووکامرس جلوگیری کنید.',
			'hesabix-v2'
		) . '</p>';
		echo '<p><label><input type="checkbox" name="hesabix_v2_pause_auto_sync" value="1" ' . checked($paused, true, false) . ' /> ';
		echo esc_html__('توقف همگام‌سازی خودکار برای این سفارش', 'hesabix-v2');
		echo '</label></p>';
		printf(
			'<p><a href="%s">%s</a></p>',
			esc_url(admin_url('admin.php?page=hesabix-v2-orders')),
			esc_html__('فهرست سفارش‌ها و عملیات دسته‌ای…', 'hesabix-v2')
		);
	}

	/**
	 * @param int|mixed        $order_id
	 * @param WC_Order|null    $order
	 * @return void
	 */
	public function save_order_hesabix_meta_box($order_id, $order = null)
	{
		if (!isset($_POST['hesabix_v2_order_panel_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['hesabix_v2_order_panel_nonce'])), 'hesabix_v2_order_panel')) {
			return;
		}
		if (!current_user_can('manage_woocommerce')) {
			return;
		}

		if ($order instanceof WC_Order) {
			$oid = (int) $order->get_id();
		} else {
			$oid = (int) $order_id;
		}
		if ($oid < 1) {
			return;
		}

		$pause = !empty($_POST['hesabix_v2_pause_auto_sync']);
		Hesabix_V2_Order_Sync_Meta::set_pause_auto_sync($oid, $pause);
	}

	/**
	 * AJAX: ارسال/به‌روزرسانی دستهٔ کوچک سفارش‌ها در حسابیکس
	 *
	 * @return void
	 */
	public function ajax_orders_sync_batch()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json_error(array('message' => __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2')));
		}

		$raw = isset($_POST['order_ids']) ? wp_unslash($_POST['order_ids']) : array();
		if (!is_array($raw)) {
			$raw = array();
		}

		$bulk_opts = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$o_max = isset($bulk_opts['wc_orders_ajax_batch']) ? (int) $bulk_opts['wc_orders_ajax_batch'] : 40;
		$o_max = max(5, min(Hesabix_V2_Sync_Service::BULK_WC_CHUNK_MAX_ITEMS, $o_max));

		$ids = array_slice(array_filter(array_map('absint', $raw)), 0, $o_max);
		if (empty($ids)) {
			wp_send_json_error(array('message' => __('سفارشی انتخاب نشده است.', 'hesabix-v2')));
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$bulk = $sync_service->bulk_sync_orders($ids);

		$results = array();
		foreach ($ids as $oid) {
			if (isset($bulk['per_order'][ $oid ])) {
				$po = $bulk['per_order'][ $oid ];
				$paused = !empty($po['skipped_pause']);
				$results[] = array(
					'order_id' => (int) $oid,
					'success' => $paused ? true : (!empty($po['success'])),
					'skipped_pause' => $paused,
					'message' => isset($po['message']) ? (string) $po['message'] : '',
				);

				continue;
			}

			$results[] = array(
				'order_id' => (int) $oid,
				'success' => false,
				/* translators: %d: WooCommerce order id */
				'message' => sprintf(__('خلاصهٔ نتیجه برای سفارش %d موجود نبود.', 'hesabix-v2'), (int) $oid),
			);
		}

		wp_send_json_success(
			array(
				'results' => $results,
				'summary' => array(
					'success' => isset($bulk['success']) ? (int) $bulk['success'] : 0,
					'failed' => isset($bulk['failed']) ? (int) $bulk['failed'] : 0,
				),
			)
		);
	}

	/**
	 * AJAX: همگام‌سازی دستهٔ مشتریان (bulk API حسابیکس).
	 *
	 * @since      3.3.5
	 * @return void
	 */
	public function ajax_customers_sync_batch()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json_error(array('message' => __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2')));
		}

		$raw = isset($_POST['customer_ids']) ? wp_unslash($_POST['customer_ids']) : array();
		if (!is_array($raw)) {
			$raw = array();
		}
		$c_opts = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$c_max = isset($c_opts['wc_customers_per_ajax']) ? (int) $c_opts['wc_customers_per_ajax'] : 45;
		$c_max = max(5, min(500, $c_max));

		$ids = array_slice(array_filter(array_map('absint', $raw)), 0, $c_max);
		if (empty($ids)) {
			wp_send_json_error(array('message' => __('مشتری انتخاب نشده است.', 'hesabix-v2')));
		}

		$eligible = array();
		$precheck = array();
		foreach ($ids as $uid) {
			if (! Hesabix_V2_Customer_Service::user_has_customer_list_role((int) $uid)) {
				$precheck[] = array(
					'customer_id' => (int) $uid,
					'success' => false,
					/* translators: %d: user ID */
					'message' => sprintf(__('شناسه %d جزو نقش‌های مجاز مشتری نیست؛ رد شد.', 'hesabix-v2'), (int) $uid),
				);

				continue;
			}

			$eligible[] = (int) $uid;
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$r = empty($eligible) ? array(
			'success' => 0,
			'failed' => count($precheck),
			'per_customer' => array(),
		) : $sync_service->bulk_sync_customers($eligible);

		$results = $precheck;
		foreach ($eligible as $cid) {
			$slot = isset($r['per_customer'][ $cid ]) ? $r['per_customer'][ $cid ] : array(
				'success' => false,
				/* translators: %d customer id */
				'message' => sprintf(__('نتیجه‌ای برای مشتری %d برنگشت.', 'hesabix-v2'), (int) $cid),
			);
			$results[] = array(
				'customer_id' => (int) $cid,
				'success' => !empty($slot['success']),
				'message' => isset($slot['message']) ? (string) $slot['message'] : '',
			);
		}

		wp_send_json_success(array('results' => $results));
	}

	/**
	 * AJAX: همگام‌سازی دستهٔ محصولات والد با API bulk حسابیکس.
	 *
	 * @return void
	 */
	public function ajax_products_sync_batch()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json_error(array('message' => __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2')));
		}

		$raw = isset($_POST['product_ids']) ? wp_unslash($_POST['product_ids']) : array();
		if (!is_array($raw)) {
			$raw = array();
		}

		$b_opts = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$p_max = isset($b_opts['wc_product_parents_per_ajax']) ? (int) $b_opts['wc_product_parents_per_ajax'] : 35;
		$p_max = max(5, min(Hesabix_V2_Sync_Service::BULK_WC_CHUNK_MAX_ITEMS, $p_max));

		$ids = array_slice(array_filter(array_map('absint', $raw)), 0, $p_max);
		if (empty($ids)) {
			wp_send_json_error(array('message' => __('محصولی انتخاب نشده است.', 'hesabix-v2')));
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$bulk = $sync_service->bulk_sync_products($ids);

		$failed_messages = array();
		if (!empty($bulk['errors']) && is_array($bulk['errors'])) {
			foreach ($bulk['errors'] as $err) {
				if (!is_array($err)) {
					continue;
				}
				$pid = isset($err['product_id']) ? (int) $err['product_id'] : 0;
				if ($pid < 1) {
					continue;
				}
				$msg = isset($err['message']) ? trim((string) $err['message']) : '';
				if (!isset($failed_messages[ $pid ])) {
					$failed_messages[ $pid ] = array();
				}
				$failed_messages[ $pid ][] = $msg !== '' ? $msg : __('ناموفق', 'hesabix-v2');
			}
		}

		$results = array();
		foreach ($ids as $pid) {
			$pid = (int) $pid;
			if (isset($failed_messages[ $pid ]) && $failed_messages[ $pid ] !== array()) {
				$results[] = array(
					'product_id' => $pid,
					'success' => false,
					'message' => implode(' ', array_unique($failed_messages[ $pid ])),
				);
			} else {
				$results[] = array(
					'product_id' => $pid,
					'success' => true,
					'message' => '',
				);
			}
		}

		wp_send_json_success(array('results' => $results));
	}

	/**
	 * AJAX: لغو ارسال (حذف فاکتور) برای چند سفارش
	 *
	 * @return void
	 */
	public function ajax_orders_unsync_batch()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json_error(array('message' => __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2')));
		}

		$raw = isset($_POST['order_ids']) ? wp_unslash($_POST['order_ids']) : array();
		if (!is_array($raw)) {
			$raw = array();
		}
		$ids = array_slice(array_filter(array_map('absint', $raw)), 0, 8);
		if (empty($ids)) {
			wp_send_json_error(array('message' => __('سفارشی انتخاب نشده است.', 'hesabix-v2')));
		}

		$results = array();
		foreach ($ids as $oid) {
			$r = Hesabix_V2_Invoice_Service::unsync_order_from_hesabix($oid);
			$results[] = array(
				'order_id' => $oid,
				'success' => !empty($r['success']),
				'message' => isset($r['message']) ? (string) $r['message'] : '',
			);
		}

		wp_send_json_success(array('results' => $results));
	}

	/**
	 * AJAX: تنظیم توقف همگام‌سازی خودکار
	 *
	 * @return void
	 */
	public function ajax_orders_set_pause()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		$order_id = isset($_POST['order_id']) ? absint($_POST['order_id']) : 0;
		$pause = !empty($_POST['pause']);
		if ($order_id < 1) {
			wp_send_json_error(array('message' => __('سفارش نامعتبر است.', 'hesabix-v2')));
		}
		if (!current_user_can('manage_woocommerce')) {
			wp_send_json_error(array('message' => __('مجوز کافی نیست.', 'hesabix-v2')));
		}

		Hesabix_V2_Order_Sync_Meta::set_pause_auto_sync($order_id, $pause);
		wp_send_json_success(array('pause' => $pause));
	}

	/**
	 * AJAX: فهرست حساب‌ها برای تراز افتتاحیه
	 *
	 * @return void
	 */
	public function ajax_opening_inventory_accounts()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();
		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json_error(array('message' => __('افزونه غیرفعال است.', 'hesabix-v2')));
		}

		$api = new Hesabix_V2_Api();
		Hesabix_V2_Opening_Inventory_Service::sync_and_get_stored_fiscal_year_id($api);

		$res = $api->get_accounts_flat();
		$items = array();
		$data = Hesabix_V2_Opening_Inventory_Service::get_api_data_array($res);
		$ids_with_children = array();
		if (is_array($data) && isset($data['items']) && is_array($data['items'])) {
			foreach ($data['items'] as $row) {
				if (!is_array($row)) {
					continue;
				}
				$pp = isset($row['parent_id']) ? (int) $row['parent_id'] : 0;
				if ($pp > 0) {
					$ids_with_children[ $pp ] = true;
				}
			}
			foreach ($data['items'] as $row) {
				if (!is_array($row) || empty($row['id'])) {
					continue;
				}
				$id = (int) $row['id'];
				if (!empty($ids_with_children[ $id ])) {
					continue;
				}
				$code = isset($row['code']) ? (string) $row['code'] : '';
				$name = isset($row['name']) ? (string) $row['name'] : '';
				$acc_type = isset($row['account_type']) ? (string) $row['account_type'] : '';
				$items[] = array(
					'id' => $id,
					'code' => $code,
					'name' => $name,
					'account_type' => $acc_type,
					'label' => trim($code . ' — ' . $name),
				);
			}
		}

		Hesabix_V2_Opening_Inventory_Service::invalidate_connection_prereq_ui_cache();
		$ui_snap = Hesabix_V2_Opening_Inventory_Service::get_connection_prereq_for_ui();

		wp_send_json_success(
			array(
				'accounts' => $items,
				'prereq' => $ui_snap['prereq'],
				'checklist' => $ui_snap['checklist'],
				'message' => empty($items) ? __('حسابی برنگشت؛ دسترسی chart_of_accounts.view و اتصال را بررسی کنید.', 'hesabix-v2') : '',
			)
		);
	}

	/**
	 * AJAX: پیش‌نمایش اقلام و تخمین دسته‌ها (بدون ایجاد نشست).
	 *
	 * @return void
	 */
	public function ajax_opening_inventory_preview()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();
		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json_error(array('message' => __('افزونه غیرفعال است.', 'hesabix-v2')));
		}

		$cost = isset($_POST['cost_basis']) ? sanitize_key(wp_unslash($_POST['cost_basis'])) : 'regular';
		if (!in_array($cost, array('regular', 'sale', 'zero'), true)) {
			$cost = 'regular';
		}

		$post_like = array(
			'include_tax' => !empty($_POST['include_tax']),
			'cost_basis' => $cost,
			'batch_size' => isset($_POST['batch_size']) ? absint(wp_unslash($_POST['batch_size'])) : 12,
			'warehouse_id' => isset($_POST['warehouse_id']) ? absint(wp_unslash($_POST['warehouse_id'])) : 0,
		);

		$res = Hesabix_V2_Opening_Inventory_Service::build_preview_payload($post_like);
		if (empty($res['success'])) {
			wp_send_json_error(array('message' => $res['message'] ?? __('پیش‌نمایش ناموفق', 'hesabix-v2')));
		}

		unset($res['success']);
		wp_send_json_success($res);
	}

	/**
	 * AJAX: درخواست توقف پردازش دسته‌ای پس از اتمام دستهٔ جاری.
	 *
	 * @return void
	 */
	public function ajax_opening_inventory_cancel()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();
		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json_error(array('message' => __('افزونه غیرفعال است.', 'hesabix-v2')));
		}
		$job_id = isset($_POST['job_id']) ? sanitize_key(wp_unslash((string) $_POST['job_id'])) : '';
		$res = Hesabix_V2_Opening_Inventory_Service::mark_job_cancel_requested($job_id, get_current_user_id());
		if (empty($res['success'])) {
			wp_send_json_error(array('message' => $res['message'] ?? __('درخواست توقف ناموفق', 'hesabix-v2')));
		}
		unset($res['success']);
		wp_send_json_success($res);
	}

	/**
	 * @return void
	 */
	public function ajax_opening_inventory_prepare()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();
		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json_error(array('message' => __('افزونه غیرفعال است.', 'hesabix-v2')));
		}

		$cost = isset($_POST['cost_basis']) ? sanitize_key(wp_unslash($_POST['cost_basis'])) : 'regular';
		if (!in_array($cost, array('regular', 'sale', 'zero'), true)) {
			$cost = 'regular';
		}

		$options = array(
			'include_tax' => !empty($_POST['include_tax']),
			'cost_basis' => $cost,
			'auto_balance_to_equity' => !empty($_POST['auto_balance_to_equity']),
			'do_post' => !empty($_POST['do_post']),
			'inventory_account_id' => isset($_POST['inventory_account_id']) ? absint(wp_unslash($_POST['inventory_account_id'])) : 0,
			'equity_account_id' => isset($_POST['equity_account_id']) ? absint(wp_unslash($_POST['equity_account_id'])) : 0,
			'batch_size' => isset($_POST['batch_size']) ? absint(wp_unslash($_POST['batch_size'])) : 12,
			'warehouse_id' => isset($_POST['warehouse_id']) ? absint(wp_unslash($_POST['warehouse_id'])) : 0,
		);

		$res = Hesabix_V2_Opening_Inventory_Service::job_prepare(get_current_user_id(), $options);
		if (empty($res['success'])) {
			wp_send_json_error(array('message' => $res['message'] ?? __('آماده‌سازی ناموفق', 'hesabix-v2')));
		}

		unset($res['success']);
		wp_send_json_success($res);
	}

	/**
	 * @return void
	 */
	public function ajax_opening_inventory_batch()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();
		$job_id = isset($_POST['job_id']) ? sanitize_key(wp_unslash((string) $_POST['job_id'])) : '';
		$res = Hesabix_V2_Opening_Inventory_Service::job_run_batch($job_id, get_current_user_id());
		if (empty($res['success'])) {
			wp_send_json_error($res);
		}
		wp_send_json_success($res);
	}

	/**
	 * @return void
	 */
	public function ajax_opening_inventory_finalize()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();
		$job_id = isset($_POST['job_id']) ? sanitize_key(wp_unslash((string) $_POST['job_id'])) : '';
		$res = Hesabix_V2_Opening_Inventory_Service::job_finalize($job_id, get_current_user_id());
		if (empty($res['success'])) {
			wp_send_json_error($res);
		}
		wp_send_json_success($res);
	}

	/**
	 * AJAX: لیست برچسب‌های فاکتور از حسابیکس (برای مرجع در تنظیمات)
	 */
	public function ajax_get_invoice_tags()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

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
		if (!$this->should_sync_wp_user_as_customer((int) $customer_id)) {
			return;
		}

		$sync_settings = get_option('hesabix_v2_sync_settings', array());
		
		if (isset($sync_settings['auto_sync_customers']) && $sync_settings['auto_sync_customers']) {
			$sync_service = new Hesabix_V2_Sync_Service();
			$sync_service->sync_customer($customer_id);
		}
	}

	/**
	 * بعد از به‌روزرسانی مشتری ووکامرس یا پروفایل وردپرس (همگام با حسابیکس در صورت فعال بودن تنظیمات).
	 *
	 * هوک‌ها: {@see profile_update}، {@see woocommerce_update_customer} (آدرس/جزئیات از حساب کاربری من).
	 *
	 * @since    2.0.0
	 * @param    int    $customer_id شناسهٔ کاربر = همان customer id در ووکامرس
	 */
	public function on_customer_update($customer_id)
	{
		if (!$this->should_sync_wp_user_as_customer((int) $customer_id)) {
			return;
		}

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
		$this->ajax_require_manage_wc();

		$api = new Hesabix_V2_Api();
		$result = $api->test_connection();
		if (!empty($result['success'])) {
			$result = $this->sanitize_connection_ajax_payload($result);
		}

		wp_send_json($result);
	}

	/**
	 * جزئیات اتصال و کسب‌وکار برای فرم تنظیمات (بدون فشار روی متن «تست»).
	 *
	 * @since 2.0.6
	 */
	public function ajax_connection_summary()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_api_key')) {
			wp_send_json(array(
				'success' => false,
				'message' => __('کلید API تنظیم نشده است.', 'hesabix-v2'),
			));
		}

		$api = new Hesabix_V2_Api();
		$result = $api->test_connection();
		if (!empty($result['success'])) {
			$result = $this->sanitize_connection_ajax_payload($result);
		}

		wp_send_json($result);
	}

	/**
	 * فیلدهای امن برای JSON مدیریت وردپرس.
	 *
	 * @param array $result Payload خروجی test_connection قبل از پاک‌سازی.
	 * @return array
	 */
	private function sanitize_connection_ajax_payload(array $result)
	{
		if (isset($result['user']) && is_array($result['user'])) {
			$user = array();
			foreach (array('id', 'email', 'mobile', 'first_name', 'last_name') as $k) {
				if (!empty($result['user'][ $k ])) {
					$user[ $k ] = $result['user'][ $k ];
				}
			}
			$result['user'] = count($user) ? $user : null;
		}

		if (isset($result['connection']) && is_array($result['connection'])) {
			$conn = $result['connection'];
			if (!empty($conn['business']) && is_array($conn['business'])) {
				$row = array();
				foreach (array(
					'id',
					'name',
					'name_fa',
					'title',
					'business_type',
					'business_field',
					'owner_id',
					'is_owner',
					'role',
				) as $bk) {
					if (isset($conn['business'][ $bk ])) {
						$row[ $bk ] = $conn['business'][ $bk ];
					}
				}
				if (empty($row['name']) && !empty($row['name_fa'])) {
					$row['name'] = $row['name_fa'];
				} elseif (empty($row['name']) && !empty($row['title'])) {
					$row['name'] = $row['title'];
				}
				if (empty($row['name']) && !empty($row['id'])) {
					$row['name'] = sprintf(__('کسب‌وکار #%d', 'hesabix-v2'), (int) $row['id']);
				}
				$conn['business'] = !empty($row['id']) ? $row : null;
			}
			if (!empty($conn['fiscal_year']) && is_array($conn['fiscal_year'])) {
				$f = array();
				foreach (array('id', 'title', 'start_date', 'end_date', 'is_current', 'is_last') as $fk) {
					if (isset($conn['fiscal_year'][ $fk ])) {
						$f[ $fk ] = $conn['fiscal_year'][ $fk ];
					}
				}
				$conn['fiscal_year'] = $f ?: null;
				if (!empty($f['id'])) {
					$this->persist_fiscal_year_option_from_hesabix((int) $f['id']);
				}
			}
			$result['connection'] = $conn;
		}

		return $result;
	}

	/**
	 * ذخیرهٔ شناسهٔ سال مالی جاری برای هدرهای API و عملیات تراز افتتاحیه.
	 *
	 * @param int $fiscal_year_id
	 * @return void
	 */
	private function persist_fiscal_year_option_from_hesabix($fiscal_year_id)
	{
		$fiscal_year_id = (int) $fiscal_year_id;
		if ($fiscal_year_id < 1) {
			return;
		}
		update_option('hesabix_v2_fiscal_year_id', $fiscal_year_id);
		if (class_exists('Hesabix_V2_Opening_Inventory_Service', false)) {
			Hesabix_V2_Opening_Inventory_Service::invalidate_connection_prereq_ui_cache();
		}
		if (class_exists('Hesabix_V2_Order_Fiscal_Service', false)) {
			Hesabix_V2_Order_Fiscal_Service::invalidate_bounds_cache();
		}
	}

	/**
	 * دادهٔ اسکریپت تب موجودی افتتاحیه (پیش‌نیاز، چک‌لیست، رشته‌ها).
	 *
	 * @return array<string,mixed>
	 */
	private function get_opening_inventory_script_payload()
	{
		$ui = Hesabix_V2_Opening_Inventory_Service::get_connection_prereq_for_ui();
		return array(
			'post_confirm_phrase' => Hesabix_V2_Opening_Inventory_Service::post_confirm_phrase(),
			'prereq' => $ui['prereq'],
			'checklist' => $ui['checklist'],
			'pending_job' => Hesabix_V2_Opening_Inventory_Service::get_pending_job_summary_for_user(get_current_user_id()),
			'strings' => array(
				'loadAccounts' => __('در حال بارگذاری حساب‌ها…', 'hesabix-v2'),
				'accountsError' => __('خطا در دریافت حساب‌ها از حسابیکس.', 'hesabix-v2'),
				'confirmTitle' => __('تأیید قبل از ثبت موجودی افتتاحیه', 'hesabix-v2'),
				'confirmIntro' => __('پس از اتمام موفق، این بخش دیگر در دسترس نخواهد بود. موارد زیر را بررسی کنید:', 'hesabix-v2'),
				'running' => __('در حال پردازش دسته‌ها…', 'hesabix-v2'),
				'finalizing' => __('در حال نهایی‌سازی…', 'hesabix-v2'),
				'needInventoryAccount' => __('حساب موجودی (کالا) را انتخاب کنید.', 'hesabix-v2'),
				'needEquity' => __('حساب حقوق صاحبان سهام را انتخاب کنید.', 'hesabix-v2'),
				'needWarehouse' => __('انبار پیش‌فرض در تب فاکتور یا شناسه انبار در همین صفحه لازم است.', 'hesabix-v2'),
				'needFiscalYear' => __('سال مالی جاری در حسابیکس برای این کسب‌وکار در دسترس نیست. تب اتصال را باز کنید یا «بارگذاری حساب‌ها از حسابیکس» را بزنید؛ در صورت نیاز مجوز سال مالی را به کلید API بدهید.', 'hesabix-v2'),
				'needCurrency' => __('ارز فاکتور/سند را در تب فاکتور تنظیم کنید.', 'hesabix-v2'),
				'genericFail' => __('عملیات ناموفق بود.', 'hesabix-v2'),
				'requestFail' => __('خطا در ارتباط با سرور.', 'hesabix-v2'),
				'taxYes' => __('بله — مالیات بر ارزش افزوده در بهای واحد لحاظ شود', 'hesabix-v2'),
				'taxNo' => __('خیر — بهای واحد بدون مالیات (خالص)', 'hesabix-v2'),
				'postYes' => __('بله، سند تراز افتتاحیه در حسابیکس نهایی شود', 'hesabix-v2'),
				'postNo' => __('خیر، فقط ذخیره شود (نهایی‌سازی بعداً در حسابیکس)', 'hesabix-v2'),
				'autoBalYes' => __('بله، اختلاف تراز به حساب حقوق صاحبان سهام بسته شود', 'hesabix-v2'),
				'autoBalNo' => __('خیر، بستن خودکار غیرفعال', 'hesabix-v2'),
				'done' => __('انجام شد.', 'hesabix-v2'),
				'resumedHint' => __('ادامهٔ نشست', 'hesabix-v2'),
				'previewLoading' => __('در حال محاسبهٔ پیش‌نمایش…', 'hesabix-v2'),
				'previewTitle' => __('پیش‌نمایش اقلام', 'hesabix-v2'),
				'previewTotal' => __('تعداد اقلام قابل ثبت', 'hesabix-v2'),
				'previewBatches' => __('تخمین تعداد دسته با اندازهٔ فعلی', 'hesabix-v2'),
				'previewPostedWarn' => __('تراز افتتاحیهٔ این سال در حسابیکس قبلاً نهایی شده؛ ویرایش ممکن نیست.', 'hesabix-v2'),
				'previewColProduct' => __('کالا', 'hesabix-v2'),
				'previewColQty' => __('موجودی', 'hesabix-v2'),
				'previewColCost' => __('بهای واحد', 'hesabix-v2'),
				'previewColKind' => __('نوع', 'hesabix-v2'),
				'copyLog' => __('کپی لاگ', 'hesabix-v2'),
				'copyLogDone' => __('متن لاگ در حافظه کپی شد.', 'hesabix-v2'),
				'copyLogEmpty' => __('لاگی برای کپی وجود ندارد.', 'hesabix-v2'),
				'confirmPostDanger' => __('گزینهٔ «نهایی‌سازی سند» فعال است؛ سند تراز افتتاحیه در حسابیکس قفل می‌شود. برای ادامه، عبارت زیر را دقیقاً در پنجرهٔ بعدی وارد کنید:', 'hesabix-v2'),
				'confirmPostMismatch' => __('عبارت واردشده با مورد نیاز یکسان نیست؛ اجرا لغو شد.', 'hesabix-v2'),
				'chkEnabled' => __('افزونهٔ حسابیکس فعال است', 'hesabix-v2'),
				'chkApiKey' => __('کلید API ذخیره شده است', 'hesabix-v2'),
				'chkBusiness' => __('کسب‌وکار متصل است', 'hesabix-v2'),
				'chkFiscalYear' => __('سال مالی جاری برای افزونه در دسترس است', 'hesabix-v2'),
				'chkWarehouse' => __('انبار: پیش‌فرض تب فاکتور یا شناسهٔ انبار در همین فرم', 'hesabix-v2'),
				'chkCurrency' => __('ارز سند (از تب فاکتور / حسابیکس) قابل تشخیص است', 'hesabix-v2'),
				'pendingBatch' => __('نشست نیمه‌تمام: %1$d از %2$d قلم پردازش شده؛ با «شروع ثبت…» ادامه دهید.', 'hesabix-v2'),
				'pendingFinalize' => __('نشست نیمه‌تمام: دسته‌ها ذخیره شده‌اند؛ فقط نهایی‌سازی مانده. با «شروع ثبت…» ادامه دهید.', 'hesabix-v2'),
				'cancelRun' => __('توقف امن پس از دستهٔ جاری', 'hesabix-v2'),
				'cancelRunHint' => __('پردازش بعد از اتمام دستهٔ در حال اجرا قطع می‌شود؛ نشست ذخیره می‌ماند.', 'hesabix-v2'),
				'cancelRequestSent' => __('درخواست توقف ثبت شد؛ تا پایان دستهٔ جاری صبر کنید.', 'hesabix-v2'),
				'cancelRunFail' => __('ثبت درخواست توقف ناموفق بود.', 'hesabix-v2'),
				'stoppedBetweenBatches' => __('پردازش متوقف شد؛ بعداً با «شروع ثبت» می‌توانید ادامه دهید.', 'hesabix-v2'),
			),
		);
	}

	/**
	 * AJAX: Sync single product
	 *
	 * @since    2.0.0
	 */
	public function ajax_sync_product()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

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
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json(array(
				'success' => false,
				'message' => __('ابتدا اتصال را از تنظیمات یا ویزارد کامل کنید.', 'hesabix-v2'),
			));
		}

		$o = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$offset = isset($_POST['offset']) ? absint($_POST['offset']) : 0;
		$batch = isset($_POST['batch_size']) ? absint($_POST['batch_size']) : 0;
		if ($batch < 5 || $batch > 500) {
			$batch = (int) $o['wc_product_parents_per_ajax'];
		}

		$published_total = Hesabix_V2_Product_Service::count_published_parent_products();
		$id_slice = Hesabix_V2_Product_Service::get_published_parent_product_ids_slice($batch, $offset);

		if (empty($id_slice)) {
			wp_send_json(
				array(
					'success' => true,
					'done' => true,
					'next_offset' => $offset,
					'estimated_catalog_total_parents' => $published_total,
					'processed_parent_posts_in_chunk' => 0,
					'chunk_results' => array(
						'success' => 0,
						'failed' => 0,
						'total' => 0,
						'errors_preview' => array(),
						'errors_total' => 0,
					),
					'message' => __('موردی در این بازه یافت نشد؛ به نظر می‌رسد همگام‌سازی به پایان رسیده است.', 'hesabix-v2'),
				)
			);
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$r = $sync_service->bulk_sync_products($id_slice);
		$all_err = isset($r['errors']) && is_array($r['errors']) ? $r['errors'] : array();
		$cap = (int) $o['errors_preview_cap'];
		$next_off = $offset + count($id_slice);

		wp_send_json(
			array(
				'success' => true,
				'done' => ($next_off >= $published_total),
				'next_offset' => $next_off,
				'estimated_catalog_total_parents' => $published_total,
				'processed_parent_posts_in_chunk' => count($id_slice),
				'chunk_results' => array(
					'success' => (int) $r['success'],
					'failed' => (int) $r['failed'],
					'total' => (int) $r['total'],
					'errors_preview' => array_slice($all_err, 0, $cap),
					'errors_total' => count($all_err),
				),
				'message' => sprintf(
					/* translators: %d: number of parent product posts in chunk */
					__('مرحله انجام شد (%d محصول والد در این دسته پردازش شد).', 'hesabix-v2'),
					count($id_slice)
				),
			)
		);
	}

	/**
	 * AJAX: همگام‌سازی دسته‌های product_cat ووکامرس (شامل خالی)، مرحله‌ای.
	 *
	 * @since 2.0.8
	 */
	public function ajax_sync_wc_categories()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json(array(
				'success' => false,
				'message' => __('ابتدا اتصال را از تنظیمات یا ویزارد کامل کنید.', 'hesabix-v2'),
			));
		}

		$o = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$offset = isset($_POST['offset']) ? absint($_POST['offset']) : 0;
		$batch = isset($_POST['batch_size']) ? absint($_POST['batch_size']) : 0;
		if ($batch < 10 || $batch > 300) {
			$batch = (int) $o['wc_categories_per_ajax'];
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$r = $sync_service->bulk_sync_wc_categories_chunk($offset, $batch);

		if (empty($r['success'])) {
			wp_send_json($r);
		}

		$all_err = isset($r['chunk_results']['errors_preview']) && is_array($r['chunk_results']['errors_preview'])
			? $r['chunk_results']['errors_preview']
			: array();
		$cap = (int) $o['errors_preview_cap'];

		wp_send_json(array(
			'success' => true,
			'done' => !empty($r['done']),
			'next_offset' => isset($r['next_offset']) ? (int) $r['next_offset'] : $offset,
			'estimated_catalog_total_wc_categories' => isset($r['estimated_catalog_total_wc_categories'])
				? (int) $r['estimated_catalog_total_wc_categories']
				: 0,
			'processed_wc_categories_in_chunk' => isset($r['processed_wc_categories_in_chunk'])
				? (int) $r['processed_wc_categories_in_chunk']
				: 0,
			'chunk_results' => array(
				'success' => isset($r['chunk_results']['success']) ? (int) $r['chunk_results']['success'] : 0,
				'failed' => isset($r['chunk_results']['failed']) ? (int) $r['chunk_results']['failed'] : 0,
				'total' => isset($r['chunk_results']['total']) ? (int) $r['chunk_results']['total'] : 0,
				'errors_preview' => array_slice($all_err, 0, $cap),
				'errors_total' => isset($r['chunk_results']['errors_total'])
					? (int) $r['chunk_results']['errors_total']
					: count($all_err),
			),
			'message' => isset($r['message']) ? (string) $r['message'] : '',
		));
	}

	/**
	 * AJAX: همگام‌سازی مشتریان (وکامرس → حسابیکس)، دسته‌ای با offset.
	 *
	 * @since 2.0.0
	 */
	public function ajax_sync_customers()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json(array(
				'success' => false,
				'message' => __('ابتدا اتصال را از تنظیمات یا ویزارد کامل کنید.', 'hesabix-v2'),
			));
		}

		$o = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$offset = isset($_POST['offset']) ? absint($_POST['offset']) : 0;
		$batch = isset($_POST['batch_size']) ? absint($_POST['batch_size']) : 0;
		if ($batch < 5 || $batch > 500) {
			$batch = (int) $o['wc_customers_per_ajax'];
		}

		$customers_total = Hesabix_V2_Customer_Service::count_sync_customers();
		$id_slice = Hesabix_V2_Customer_Service::get_sync_customer_ids_slice($batch, $offset);

		if (empty($id_slice)) {
			wp_send_json(
				array(
					'success' => true,
					'done' => true,
					'next_offset' => $offset,
					'estimated_catalog_total_customers' => $customers_total,
					'processed_in_chunk' => 0,
					'chunk_results' => array(
						'success' => 0,
						'failed' => 0,
						'total' => 0,
						'errors_preview' => array(),
						'errors_total' => 0,
					),
					'message' => __('موردی در این بازه یافت نشد؛ به نظر می‌رسد همگام‌سازی به پایان رسیده است.', 'hesabix-v2'),
				)
			);
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$r = $sync_service->bulk_sync_customers($id_slice);
		$all_err = isset($r['errors']) && is_array($r['errors']) ? $r['errors'] : array();
		$cap = (int) $o['errors_preview_cap'];
		$next_off = $offset + count($id_slice);

		wp_send_json(
			array(
				'success' => true,
				'done' => ($next_off >= $customers_total),
				'next_offset' => $next_off,
				'estimated_catalog_total_customers' => $customers_total,
				'processed_in_chunk' => count($id_slice),
				'chunk_results' => array(
					'success' => (int) $r['success'],
					'failed' => (int) $r['failed'],
					'total' => (int) $r['total'],
					'errors_preview' => array_slice($all_err, 0, $cap),
					'errors_total' => count($all_err),
				),
				'message' => sprintf(
					/* translators: %d: customer user rows in chunk */
					__('مرحله انجام شد (%d مشتری در این دسته پردازش شد).', 'hesabix-v2'),
					count($id_slice)
				),
			)
		);
	}

	/**
	 * AJAX: واردات اشخاص (مشتری‌سان) از حسابیکس به ووکامرس (مرحله‌ای با skip).
	 *
	 * @since 2.0.1
	 */
	public function ajax_import_customers_from_hesabix()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json(array(
				'success' => false,
				'message' => __('ابتدا اتصال را از تنظیمات یا ویزارد کامل کنید.', 'hesabix-v2'),
			));
		}

		$create_missing = !empty($_POST['create_missing']);
		$o = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$skip = isset($_POST['skip']) ? absint($_POST['skip']) : 0;
		$take = (int) apply_filters(
			'hesabix_v2_import_customers_page_size',
			$o['hesabix_person_take']
		);
		$take = max(10, min(200, absint($take)));
		$pages = (int) $o['hesabix_import_pages_per_ajax'];

		$sync_service = new Hesabix_V2_Sync_Service();
		$res = $sync_service->import_customers_from_hesabix_chunk($skip, $create_missing, $take, $pages);

		wp_send_json($res);
	}

	/**
	 * AJAX: بارگذاری لیست انبارها و حساب‌های بانکی برای کمبوباکس تنظیمات فاکتور
	 *
	 * @since    2.0.0
	 */
	public function ajax_get_warehouses_and_banks()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

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

		$cash_registers = array();
		$cash_res = $api->get_cash_registers();
		if (!empty($cash_res['success']) && !empty($cash_res['data'])) {
			$items = isset($cash_res['data']['items']) ? $cash_res['data']['items'] : (is_array($cash_res['data']) ? $cash_res['data'] : array());
			foreach ($items as $row) {
				$id = isset($row['id']) ? $row['id'] : null;
				$name = isset($row['name']) ? $row['name'] : (isset($row['title']) ? $row['title'] : (isset($row['code']) ? $row['code'] : (string) $id));
				$code = isset($row['code']) ? $row['code'] : '';
				if ($id !== null) {
					$cash_registers[] = array('id' => (string) $id, 'name' => $name, 'code' => $code);
				}
			}
		}

		$currencies = array();
		$cur_res = $api->get_business_currencies();
		$cur_rows = Hesabix_V2_Currency_Service::normalize_rows_from_api_response($cur_res);
		foreach ($cur_rows as $row) {
			$currencies[] = array(
				'id' => (int) $row['id'],
				'code' => isset($row['code']) ? (string) $row['code'] : '',
				'title' => $row['title'] !== '' ? (string) $row['title'] : (string) $row['name'],
				'is_default' => !empty($row['is_default']),
			);
		}

		wp_send_json(array(
			'success' => true,
			'warehouses' => $warehouses,
			'banks' => $banks,
			'cash_registers' => $cash_registers,
			'currencies' => $currencies,
		));
	}

	/**
	 * AJAX: کشش موجودی حسابیکس → ووکامرس (هم‌اکنون)
	 *
	 * @since 3.3.2
	 */
	public function ajax_pull_stock_now()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!get_option('hesabix_v2_enabled')) {
			wp_send_json(array(
				'success' => false,
				'message' => __('ابتدا اتصال به حسابیکس را تکمیل کنید.', 'hesabix-v2'),
			));
		}

		$result = Hesabix_V2_Stock_Pull_Service::execute_pull(array('source' => 'ajax'));

		wp_send_json($result);
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
		$this->ajax_require_manage_wc();

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
		$this->ajax_require_manage_wc();

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
	 * AJAX: Setup wizard - save API key, business and complete
	 * سال مالی جاری از API خوانده و در option ذخیره می‌شود (برای هدر API و تراز افتتاحیه).
	 *
	 * @since    2.0.0
	 */
	public function ajax_setup_complete()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

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
		$api = new Hesabix_V2_Api();
		Hesabix_V2_Opening_Inventory_Service::sync_and_get_stored_fiscal_year_id($api);
		if (class_exists('Hesabix_V2_Order_Fiscal_Service')) {
			Hesabix_V2_Order_Fiscal_Service::invalidate_bounds_cache();
		}
		update_option('hesabix_v2_enabled', true);
		update_option('hesabix_v2_setup_completed', true);
		delete_transient('hesabix_v2_show_setup_wizard');
		Hesabix_V2_Currency_Service::invalidate_list_cache();

		wp_send_json(array('success' => true, 'message' => __('راه‌اندازی با موفقیت انجام شد.', 'hesabix-v2')));
	}

	/**
	 * AJAX: تولید توکن پل REST (نمایش یک‌باره در مرورگر).
	 *
	 * @return void
	 */
	public function ajax_bridge_generate_token()
	{
		check_ajax_referer('hesabix_v2_nonce', 'nonce');
		$this->ajax_require_manage_wc();

		if (!class_exists('Hesabix_V2_Bridge_Rest')) {
			wp_send_json(array('success' => false, 'message' => __('کلاس پل REST بارگذاری نشده است.', 'hesabix-v2')));
		}

		$plain = wp_generate_password(48, false, false);
		Hesabix_V2_Bridge_Rest::save_token_hash($plain);

		wp_send_json_success(
			array(
				'token'   => $plain,
				'message' => __(
					'توکن جدید ایجاد شد. آن را در حسابیکس ذخیره کنید؛ پس از بستن صفحه دیگر نمایش داده نمی‌شود.',
					'hesabix-v2'
				),
			)
		);
	}
}

