<?php
/**
 * بارگذاری و اتصال اجزای افزونه.
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

require_once ST_PLUGIN_DIR . 'includes/class-st-cache.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-hesabix-api.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-templates.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-rest.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-catalog.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-admin.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-frontend.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-shortcode.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-block.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-widget.php';
require_once ST_PLUGIN_DIR . 'includes/class-st-public-catalog.php';

/**
 * کلاس اصلی لودر.
 */
final class Shabake_Tamin_Loader {

	/**
	 * نمونهٔ یکتا.
	 *
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
		add_action( 'plugins_loaded', array( $this, 'load_textdomain' ), 5 );
		Shabake_Tamin_Admin::instance();
		Shabake_Tamin_REST::instance();
		Shabake_Tamin_Frontend::instance();
		Shabake_Tamin_Shortcode::instance();
		Shabake_Tamin_Block::instance();
		Shabake_Tamin_Widget_Controller::instance();
		Shabake_Tamin_Public_Catalog::instance();
	}

	/**
	 * بارگذاری ترجمه‌ها.
	 */
	public function load_textdomain() {
		load_plugin_textdomain(
			'shabake-tamin',
			false,
			dirname( plugin_basename( ST_PLUGIN_FILE ) ) . '/languages'
		);
	}
}
