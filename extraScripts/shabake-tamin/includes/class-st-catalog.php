<?php
/**
 * خروجی HTML کاتالوگ (شورت‌کد و بلوک).
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * رندر کاتالوگ و حل business_id پیش‌فرض.
 */
final class Shabake_Tamin_Catalog {

	/**
	 * اگر در شورت‌کد/بلوک business_id خالی باشد، از گزینهٔ «شناسهٔ کسب‌وکار پیش‌فرض» استفاده می‌شود؛
	 * اگر آن گزینه هم ۰ باشد، خروجی **null** یعنی بدون فیلتر business در API — یعنی **همهٔ کسب‌وکارهایی که کالای عمومی دارند**.
	 *
	 * @param string $explicit_from_ui مقدار صریح از شورت‌کد یا بلوک (خالی = طبق گزینهٔ پیش‌فرض یا همه).
	 * @return int|null
	 */
	public static function resolve_business_id( $explicit_from_ui ) {
		$s = trim( (string) $explicit_from_ui );
		if ( '' !== $s ) {
			$id = absint( $s );
			return $id > 0 ? $id : null;
		}
		$def = (int) get_option( 'st_default_business_id', 0 );
		return $def > 0 ? $def : null;
	}

	/**
	 * محدود کردن فیلدهای عددی/رشته‌ای قبل از خروجی.
	 *
	 * @param array<string, mixed> $config پیکربندی.
	 * @return array<string, mixed>
	 */
	public static function clamp_config( array $config ) {
		$config['columns'] = max( 2, min( 6, (int) ( $config['columns'] ?? 4 ) ) );
		$config['take']    = max( 1, min( 100, (int) ( $config['take'] ?? 20 ) ) );
		if ( ! array_key_exists( 'search', $config ) ) {
			$config['search'] = true;
		} else {
			$config['search'] = filter_var( $config['search'], FILTER_VALIDATE_BOOLEAN );
		}

		if ( ! array_key_exists( 'locationFilters', $config ) ) {
			$config['locationFilters'] = false;
		} else {
			$config['locationFilters'] = filter_var( $config['locationFilters'], FILTER_VALIDATE_BOOLEAN );
		}

		if ( ! empty( $config['locationFilters'] ) ) {
			if ( ! array_key_exists( 'provinceSuggestions', $config ) ) {
				$config['provinceSuggestions'] = true;
			} else {
				$config['provinceSuggestions'] = filter_var( $config['provinceSuggestions'], FILTER_VALIDATE_BOOLEAN );
			}
		} else {
			$config['provinceSuggestions'] = false;
		}

		if ( ! array_key_exists( 'showProductDetails', $config ) ) {
			$config['showProductDetails'] = true;
		} else {
			$config['showProductDetails'] = filter_var( $config['showProductDetails'], FILTER_VALIDATE_BOOLEAN );
		}

		if ( ! array_key_exists( 'pageLayout', $config ) ) {
			$config['pageLayout'] = false;
		} else {
			$config['pageLayout'] = filter_var( $config['pageLayout'], FILTER_VALIDATE_BOOLEAN );
		}

		$bid = $config['businessId'] ?? null;
		if ( is_string( $bid ) ) {
			$bid = trim( $bid );
			$bid = '' === $bid ? null : absint( $bid );
		}
		if ( is_int( $bid ) && $bid <= 0 ) {
			$bid = null;
		}
		$config['businessId'] = ( null === $bid || false === $bid ) ? null : (int) $bid;

		$cid = isset( $config['categoryId'] ) ? (int) $config['categoryId'] : 0;
		$config['categoryId'] = $cid > 0 ? $cid : null;

		$prov = $config['province'] ?? null;
		$config['province']   = null;
		if ( is_string( $prov ) ) {
			$prov = mb_substr( sanitize_text_field( trim( $prov ) ), 0, 100 );
			if ( '' !== $prov ) {
				$config['province'] = $prov;
			}
		}

		$city = $config['city'] ?? null;
		$config['city'] = null;
		if ( is_string( $city ) ) {
			$city = mb_substr( sanitize_text_field( trim( $city ) ), 0, 100 );
			if ( '' !== $city ) {
				$config['city'] = $city;
			}
		}

		return $config;
	}

	/**
	 * رندر HTML کاتالوگ.
	 *
	 * @param array<string, mixed> $config  پیکربندی (businessId=null یعنی همهٔ کسب‌وکارها وقتی در تنظیمات پیش‌فرض هم نباشد).
	 * @param string                 $context shortcode|block|custom.
	 * @param mixed                  $extra   مثلاً آرایهٔ atts شورت‌کد.
	 * @return string
	 */
	public static function render_html( array $config, $context = 'custom', $extra = null ) {
		$config = self::clamp_config( $config );
		$config = apply_filters( 'shabake_tamin_catalog_config', $config, $context, $extra );

		Shabake_Tamin_Frontend::enqueue_assets_once();
		if ( ! empty( $config['pageLayout'] ) ) {
			Shabake_Tamin_Frontend::enqueue_page_layout_styles();
		}
		ob_start();
		Shabake_Tamin_Templates::load(
			'catalog-wrapper.php',
			array(
				'st_config' => $config,
			)
		);
		return (string) ob_get_clean();
	}
}
