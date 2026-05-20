<?php
/**
 * شورت‌کد [shabake_tamin].
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * شورت‌کد.
 */
final class Shabake_Tamin_Shortcode {

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

	private function __construct() {
		add_shortcode( 'shabake_tamin', array( $this, 'render' ) );
	}

	/**
	 * رندر شورت‌کد.
	 *
	 * @param array<string, string> $atts صفت‌ها.
	 * @return string
	 */
	public function render( $atts ) {
		$atts = shortcode_atts(
			array(
				'business_id'       => '',
				'category_id'       => '',
				'province'          => '',
				'city'                => '',
				'location_filters'    => '0',
				'province_suggest'    => '1',
				'show_details'        => '1',
				'columns'             => '4',
				'search'              => '1',
				'take'                => '20',
			),
			$atts,
			'shabake_tamin'
		);

		$bid_raw = trim( (string) $atts['business_id'] );
		if ( '' === $bid_raw ) {
			$business_id = Shabake_Tamin_Catalog::resolve_business_id( '' );
		} else {
			$id          = absint( $bid_raw );
			$business_id = $id > 0 ? $id : null;
		}

		$cid_raw = trim( (string) $atts['category_id'] );
		$category_id = '' === $cid_raw ? null : absint( $cid_raw );
		if ( $category_id <= 0 ) {
			$category_id = null;
		}

		$config = array(
			'businessId'            => $business_id,
			'categoryId'            => $category_id,
			'province'              => (string) $atts['province'],
			'city'                  => (string) $atts['city'],
			'locationFilters'       => in_array( (string) $atts['location_filters'], array( '1', 'true', 'yes' ), true ),
			'provinceSuggestions'   => ! in_array( (string) $atts['province_suggest'], array( '0', 'false', 'no' ), true ),
			'showProductDetails'    => ! in_array( (string) $atts['show_details'], array( '0', 'false', 'no' ), true ),
			'columns'               => (int) $atts['columns'],
			'search'                => in_array( (string) $atts['search'], array( '1', 'true', 'yes' ), true ),
			'take'                  => (int) $atts['take'],
		);

		$config = apply_filters( 'shabake_tamin_shortcode_config', $config, $atts );

		return Shabake_Tamin_Catalog::render_html( $config, 'shortcode', $atts );
	}
}
