<?php
/**
 * بلوک گوتنبرگ «کاتالوگ شبکه تأمین».
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * ثبت بلوک و اسکریپت ادیتور (وابسته به هستهٔ وردپرس، نه CDN).
 */
final class Shabake_Tamin_Block {

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
		add_action( 'init', array( $this, 'register' ) );
	}

	/**
	 * ثبت بلوک و اسکریپت ادیتور.
	 */
	public function register() {
		wp_register_script(
			'shabake-tamin-block-editor',
			ST_PLUGIN_URL . 'assets/js/block-editor.js',
			array(
				'wp-blocks',
				'wp-element',
				'wp-block-editor',
				'wp-components',
				'wp-i18n',
			),
			ST_VERSION,
			true
		);

		if ( function_exists( 'wp_set_script_translations' ) ) {
			wp_set_script_translations( 'shabake-tamin-block-editor', 'shabake-tamin', ST_PLUGIN_DIR . 'languages' );
		}

		register_block_type(
			'shabake-tamin/catalog',
			array(
				'title'           => __( 'کاتالوگ شبکه تأمین', 'shabake-tamin' ),
				'description'     => __(
					'لیست کالاهای عمومی Hesabix؛ با خالی گذاشتن کسب‌وکار، همهٔ تأمین‌کنندگان (مطابق API) قابل نمایش است.',
					'shabake-tamin'
				),
				'category'        => 'widgets',
				'icon'            => 'store',
				'keywords'        => array( __( 'hesabix', 'shabake-tamin' ), __( 'کاتالوگ', 'shabake-tamin' ) ),
				'editor_script'   => 'shabake-tamin-block-editor',
				'render_callback' => array( $this, 'render_block' ),
				'attributes'      => array(
					'businessId' => array(
						'type'    => 'string',
						'default' => '',
					),
					'categoryId' => array(
						'type'    => 'integer',
						'default' => 0,
					),
					'province'   => array(
						'type'    => 'string',
						'default' => '',
					),
					'city'       => array(
						'type'    => 'string',
						'default' => '',
					),
					'columns'    => array(
						'type'    => 'integer',
						'default' => 4,
					),
					'search'     => array(
						'type'    => 'boolean',
						'default' => true,
					),
					'take'             => array(
						'type'    => 'integer',
						'default' => 20,
					),
					'locationFilters' => array(
						'type'    => 'boolean',
						'default' => false,
					),
					'provinceSuggestions' => array(
						'type'    => 'boolean',
						'default' => true,
					),
					'showProductDetails' => array(
						'type'    => 'boolean',
						'default' => true,
					),
				),
			)
		);
	}

	/**
	 * رندر سمت سرور بلوک.
	 *
	 * @param array<string, mixed> $attributes صفت‌های بلوک.
	 * @return string
	 */
	public function render_block( $attributes ) {
		$atts = is_array( $attributes ) ? $attributes : array();

		$bid_attr = isset( $atts['businessId'] ) ? trim( (string) $atts['businessId'] ) : '';
		if ( '' === $bid_attr ) {
			$business_id = Shabake_Tamin_Catalog::resolve_business_id( '' );
		} else {
			$id          = absint( $bid_attr );
			$business_id = $id > 0 ? $id : null;
		}

		$config = array(
			'businessId'            => $business_id,
			'categoryId'            => isset( $atts['categoryId'] ) ? (int) $atts['categoryId'] : 0,
			'province'              => isset( $atts['province'] ) ? (string) $atts['province'] : '',
			'city'                  => isset( $atts['city'] ) ? (string) $atts['city'] : '',
			'columns'               => isset( $atts['columns'] ) ? (int) $atts['columns'] : 4,
			'search'                => array_key_exists( 'search', $atts ) ? (bool) $atts['search'] : true,
			'take'                  => isset( $atts['take'] ) ? (int) $atts['take'] : 20,
			'locationFilters'       => array_key_exists( 'locationFilters', $atts ) ? (bool) $atts['locationFilters'] : false,
			'provinceSuggestions'   => array_key_exists( 'provinceSuggestions', $atts ) ? (bool) $atts['provinceSuggestions'] : true,
			'showProductDetails'    => array_key_exists( 'showProductDetails', $atts ) ? (bool) $atts['showProductDetails'] : true,
		);

		return Shabake_Tamin_Catalog::render_html( $config, 'block', $atts );
	}
}
