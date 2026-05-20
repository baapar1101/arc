<?php
/**
 * کش Transient برای پاسخ‌های پراکسی.
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * کش ساده با کلید و TTL از تنظیمات.
 */
final class Shabake_Tamin_Cache {

	/**
	 * پیشوند کلید transient.
	 */
	const PREFIX = 'st_px_';

	/**
	 * TTL پیش‌فرض (ثانیه).
	 */
	const DEFAULT_TTL = 45;

	/**
	 * مقدار TTL فعلی از تنظیمات.
	 *
	 * @return int
	 */
	public static function ttl() {
		$ttl = (int) get_option( 'st_cache_ttl', self::DEFAULT_TTL );
		if ( $ttl < 0 ) {
			$ttl = 0;
		}
		if ( $ttl > 3600 ) {
			$ttl = 3600;
		}
		return $ttl;
	}

	/**
	 * خواندن از کش.
	 *
	 * @param string $key کلید منطقی (بدون پیشوند).
	 * @return mixed|null
	 */
	public static function get( $key ) {
		$ttl = self::ttl();
		if ( 0 === $ttl ) {
			return null;
		}
		$full = self::PREFIX . md5( (string) $key );
		$data = get_transient( $full );
		return false === $data ? null : $data;
	}

	/**
	 * نوشتن در کش.
	 *
	 * @param string $key  کلید منطقی.
	 * @param mixed  $data دادهٔ قابل serialize.
	 */
	public static function set( $key, $data ) {
		$ttl = self::ttl();
		if ( 0 === $ttl ) {
			return;
		}
		$full = self::PREFIX . md5( (string) $key );
		set_transient( $full, $data, $ttl );
	}
}
