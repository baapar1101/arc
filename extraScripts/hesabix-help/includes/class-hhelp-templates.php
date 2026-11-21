<?php
/**
 * Template loading.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hhelp_Templates
 */
class Hhelp_Templates {

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
	 * Constructor.
	 */
	private function __construct() {
		add_filter( 'template_include', array( $this, 'template_include' ), 99 );
		add_filter( 'body_class', array( $this, 'body_class' ) );
	}

	/**
	 * @param string $template Template path.
	 * @return string
	 */
	public function template_include( $template ) {
		if ( get_query_var( 'hhelp_search' ) ) {
			return self::locate( 'help-search.php' );
		}
		if ( is_post_type_archive( HHELP_CPT ) ) {
			return self::locate( 'help-hub.php' );
		}
		if ( is_singular( HHELP_CPT ) ) {
			return self::locate( 'help-single.php' );
		}
		return $template;
	}

	/**
	 * Locate theme override or plugin template.
	 *
	 * @param string $file File name.
	 * @return string
	 */
	public static function locate( $file ) {
		$theme = locate_template( array( 'help/' . $file ) );
		if ( $theme ) {
			return $theme;
		}
		$path = HHELP_PATH . 'templates/' . $file;
		return is_readable( $path ) ? $path : $path;
	}

	/**
	 * Include a partial.
	 *
	 * @param string               $name Partial name without .php.
	 * @param array<string, mixed> $vars Variables.
	 */
	public static function partial( $name, $vars = array() ) {
		$path = locate_template( array( 'help/partials/' . $name . '.php' ) );
		if ( ! $path ) {
			$path = HHELP_PATH . 'templates/partials/' . $name . '.php';
		}
		if ( ! is_readable( $path ) ) {
			return;
		}
		// phpcs:ignore WordPress.PHP.DontExtract.extract_extract
		extract( $vars, EXTR_SKIP );
		include $path;
	}

	/**
	 * @param array<int, string> $classes Classes.
	 * @return array<int, string>
	 */
	public function body_class( $classes ) {
		if ( hhelp_is_help() ) {
			$classes[] = 'hx-help-page';
		}
		return $classes;
	}
}
