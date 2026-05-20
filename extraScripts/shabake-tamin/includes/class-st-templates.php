<?php
/**
 * یافتن قالب PHP قابل override از تم فرزند/والد.
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * لودر قالب.
 */
final class Shabake_Tamin_Templates {

	/**
	 * مسیر فایل قالب (تم shabake-tamin/ یا پیش‌فرض افزونه).
	 *
	 * @param string $relative نام فایل نسبی داخل templates/ (مثلاً catalog-wrapper.php).
	 * @return string
	 */
	public static function locate( $relative ) {
		$relative = ltrim( (string) $relative, '/' );
		$child    = get_stylesheet_directory() . '/shabake-tamin/' . $relative;
		if ( is_readable( $child ) ) {
			return apply_filters( 'shabake_tamin_locate_template', $child, $relative );
		}
		$parent = get_template_directory() . '/shabake-tamin/' . $relative;
		if ( is_readable( $parent ) ) {
			return apply_filters( 'shabake_tamin_locate_template', $parent, $relative );
		}
		$default = ST_PLUGIN_DIR . 'templates/' . $relative;
		return apply_filters( 'shabake_tamin_locate_template', $default, $relative );
	}

	/**
	 * include با آرگومان‌های قابل استفاده در قالب.
	 *
	 * @param string               $relative نام فایل.
	 * @param array<string, mixed> $args     متغیرها برای extract.
	 */
	public static function load( $relative, array $args = array() ) {
		$file = self::locate( $relative );
		if ( ! is_readable( $file ) ) {
			return;
		}
		// phpcs:ignore WordPress.PHP.DontExtract.extract_extract
		extract( $args, EXTR_SKIP );
		include $file;
	}
}
