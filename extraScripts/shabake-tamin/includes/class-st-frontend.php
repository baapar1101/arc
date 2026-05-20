<?php
/**
 * بارگذاری استایل و اسکریپت (فقط همراه شورت‌کد یا فیلتر).
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * فرانت‌اند.
 */
final class Shabake_Tamin_Frontend {

	/**
	 * @var self|null
	 */
	private static $instance = null;

	/**
	 * @var bool
	 */
	private static $assets_enqueued = false;

	/**
	 * @var bool
	 */
	private static $page_layout_styles_enqueued = false;

	/**
	 * @return self
	 */
	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	private function __construct() {
		add_action( 'wp_enqueue_scripts', array( $this, 'register_assets' ), 5 );
	}

	/**
	 * ثبت handleها (بدون enqueue اجباری).
	 */
	public function register_assets() {
		wp_register_style(
			'shabake-tamin-catalog',
			ST_PLUGIN_URL . 'assets/css/catalog-default.css',
			array(),
			ST_VERSION
		);
		wp_register_script(
			'shabake-tamin-catalog',
			ST_PLUGIN_URL . 'assets/js/catalog.js',
			array(),
			ST_VERSION,
			true
		);
		wp_register_style(
			'shabake-tamin-catalog-page',
			ST_PLUGIN_URL . 'assets/css/catalog-page.css',
			array( 'shabake-tamin-catalog' ),
			ST_VERSION
		);
	}

	/**
	 * enqueue یک‌بار برای کل صفحه.
	 */
	public static function enqueue_assets_once() {
		if ( self::$assets_enqueued ) {
			return;
		}
		self::$assets_enqueued = true;

		wp_enqueue_style( 'shabake-tamin-catalog' );
		wp_enqueue_script( 'shabake-tamin-catalog' );

		$base = Shabake_Tamin_Hesabix_API::base_url();

		wp_localize_script(
			'shabake-tamin-catalog',
			'shabakeTamin',
			array(
				'restBase'      => esc_url_raw( rest_url( Shabake_Tamin_REST::NS . '/' ) ),
				'apiPublicBase' => $base,
				'configured'    => Shabake_Tamin_Hesabix_API::is_configured(),
				'i18n'          => array(
					'loadMore'       => __( 'بارگذاری بیشتر', 'shabake-tamin' ),
					'search'         => __( 'جستجو در کاتالوگ…', 'shabake-tamin' ),
					'contact'        => __( 'تماس با تأمین‌کننده', 'shabake-tamin' ),
					'name'           => __( 'نام شما', 'shabake-tamin' ),
					'contactField'   => __( 'تلفن یا ایمیل', 'shabake-tamin' ),
					'message'        => __( 'متن پیام', 'shabake-tamin' ),
					'captcha'        => __( 'کد امنیتی', 'shabake-tamin' ),
					'refreshCaptcha' => __( 'تصویر جدید', 'shabake-tamin' ),
					'send'           => __( 'ارسال', 'shabake-tamin' ),
					'close'          => __( 'بستن', 'shabake-tamin' ),
					'sentOk'         => __( 'پیام با موفقیت ثبت شد.', 'shabake-tamin' ),
					'errorGeneric'   => __( 'خطا در ارتباط با سرور.', 'shabake-tamin' ),
					'notConfigured'  => __( 'آدرس API در تنظیمات وردپرس ثبت نشده است.', 'shabake-tamin' ),
					'priceNA'        => __( 'تماس بگیرید', 'shabake-tamin' ),
					'loading'        => __( 'در حال بارگذاری…', 'shabake-tamin' ),
					'emptyResults'   => __( 'کالایی با این شرایط یافت نشد.', 'shabake-tamin' ),
					'details'        => __( 'جزئیات', 'shabake-tamin' ),
					'detailLoadError' => __( 'بارگذاری جزئیات کالا ناموفق بود.', 'shabake-tamin' ),
					'descriptionLabel' => __( 'توضیحات', 'shabake-tamin' ),
					'supplierLabel'  => __( 'تأمین‌کننده', 'shabake-tamin' ),
					'unitLabel'      => __( 'واحد', 'shabake-tamin' ),
					'updatedLabel'   => __( 'به‌روزرسانی', 'shabake-tamin' ),
					'phoneLabel'     => __( 'تلفن', 'shabake-tamin' ),
					'mobileLabel'    => __( 'موبایل', 'shabake-tamin' ),
					'resultCountTemplate' => __( '{shown} کالا از {total} نتیجه', 'shabake-tamin' ),
				),
			)
		);
	}

	/**
	 * استایل چیدمان تمام‌صفحه / صفحهٔ عمومی (یک‌بار).
	 */
	public static function enqueue_page_layout_styles() {
		if ( self::$page_layout_styles_enqueued ) {
			return;
		}
		self::$page_layout_styles_enqueued = true;
		wp_enqueue_style( 'shabake-tamin-catalog-page' );
	}
}
