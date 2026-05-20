<?php
/**
 * صفحهٔ عمومی کاتالوگ با URL اختصاصی (شبیه تجربهٔ ترب).
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * Rewrite و قالب صفحهٔ کاتالوگ.
 */
final class Shabake_Tamin_Public_Catalog {

	const QUERY_VAR = 'st_public_catalog';

	/**
	 * @var self|null
	 */
	private static $instance = null;

	/**
	 * @return self
	 */
	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	/**
	 * هنگام فعال‌سازی افزونه — بازنویسی قوانین permalink.
	 */
	public static function activate_flush() {
		self::register_rewrite_rules();
		flush_rewrite_rules( false );
	}

	/**
	 * ثبت rewrite (بدون flush؛ برای init).
	 */
	public static function register_rewrite_rules() {
		if ( ! (int) get_option( 'st_public_catalog_enabled', 0 ) ) {
			return;
		}
		$slug = self::get_slug();
		if ( '' === $slug ) {
			return;
		}
		add_rewrite_rule( '^' . preg_quote( $slug, '/' ) . '/?$', 'index.php?' . self::QUERY_VAR . '=1', 'top' );
	}

	/**
	 * اسلاگ از تنظیمات (sanitize).
	 *
	 * @return string
	 */
	public static function get_slug() {
		$s = (string) get_option( 'st_public_catalog_slug', 'tamin' );
		$s = sanitize_title( $s );
		return '' === $s ? 'tamin' : $s;
	}

	/**
	 * آیا درخواست فعلی صفحهٔ کاتالوگ عمومی است؟
	 */
	public static function is_request(): bool {
		return '1' === (string) get_query_var( self::QUERY_VAR );
	}

	/**
	 * پیکربندی پیش‌فرض کاتالوگ برای صفحهٔ عمومی.
	 *
	 * @return array<string, mixed>
	 */
	public static function default_page_config() {
		return array(
			'pageLayout'            => true,
			'columns'               => 5,
			'take'                  => 24,
			'search'                => true,
			'locationFilters'       => true,
			'provinceSuggestions'   => true,
			'showProductDetails'    => true,
			'businessId'            => null,
			'categoryId'            => null,
			'province'              => null,
			'city'                  => null,
		);
	}

	private function __construct() {
		add_action( 'init', array( __CLASS__, 'register_rewrite_rules' ), 20 );
		add_filter( 'query_vars', array( $this, 'filter_query_vars' ) );
		add_action( 'wp_enqueue_scripts', array( $this, 'enqueue_public_assets' ), 12 );
		add_filter( 'template_include', array( $this, 'template_include' ) );
		add_filter( 'body_class', array( $this, 'body_class' ) );
		add_action( 'update_option_st_public_catalog_slug', array( __CLASS__, 'on_slug_changed' ), 10, 2 );
		add_action( 'update_option_st_public_catalog_enabled', array( __CLASS__, 'on_enabled_changed' ), 10, 2 );
	}

	/**
	 * @param array<int, string> $vars متغیرهای query.
	 * @return array<int, string>
	 */
	public function filter_query_vars( $vars ) {
		$vars[] = self::QUERY_VAR;
		return $vars;
	}

	/**
	 * بارگذاری CSS/JS قبل از رندر قالب (چون رندر در بدنه است).
	 */
	public function enqueue_public_assets() {
		if ( ! self::is_request() ) {
			return;
		}
		Shabake_Tamin_Frontend::enqueue_assets_once();
		Shabake_Tamin_Frontend::enqueue_page_layout_styles();
	}

	/**
	 * @param string $template مسیر قالب تم.
	 * @return string
	 */
	public function template_include( $template ) {
		if ( ! self::is_request() ) {
			return $template;
		}
		$file = Shabake_Tamin_Templates::locate( 'catalog-public-page.php' );
		return is_readable( $file ) ? $file : $template;
	}

	/**
	 * @param array<int, string> $classes کلاس‌های body.
	 * @return array<int, string>
	 */
	public function body_class( $classes ) {
		if ( self::is_request() ) {
			$classes[] = 'st-public-catalog-body';
		}
		return $classes;
	}

	/**
	 * @param mixed $old مقدار قبلی.
	 */
	public static function on_slug_changed( $old, $value ) {
		unset( $old, $value );
		self::register_rewrite_rules();
		flush_rewrite_rules( false );
	}

	/**
	 * @param mixed $old مقدار قبلی.
	 */
	public static function on_enabled_changed( $old, $value ) {
		unset( $old, $value );
		self::register_rewrite_rules();
		flush_rewrite_rules( false );
	}
}
