<?php
/**
 * Plugin Name: Hesabix Help
 * Description: راهنمای جامع و آموزش حسابیکس — درخت دسته‌بندی، رایگان/عضویت/پولی، ویدئو، و یکپارچگی ووکامرس.
 * Version: 1.2.0
 * Author: Hesabix
 * Text Domain: hesabix-help
 * Requires at least: 6.0
 * Requires PHP: 8.0
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

define( 'HHELP_VERSION', '1.2.0' );
define( 'HHELP_FILE', __FILE__ );
define( 'HHELP_PATH', plugin_dir_path( __FILE__ ) );
define( 'HHELP_URL', plugin_dir_url( __FILE__ ) );
define( 'HHELP_CPT', 'hx_help' );

require_once HHELP_PATH . 'includes/class-hhelp-cpt.php';
require_once HHELP_PATH . 'includes/class-hhelp-meta.php';
require_once HHELP_PATH . 'includes/class-hhelp-rest.php';
require_once HHELP_PATH . 'includes/class-hhelp-tree.php';
require_once HHELP_PATH . 'includes/class-hhelp-access.php';
require_once HHELP_PATH . 'includes/class-hhelp-toc.php';
require_once HHELP_PATH . 'includes/class-hhelp-templates.php';
require_once HHELP_PATH . 'includes/class-hhelp-assets.php';
require_once HHELP_PATH . 'includes/class-hhelp-woocommerce.php';
require_once HHELP_PATH . 'includes/class-hhelp-admin.php';
require_once HHELP_PATH . 'includes/class-hhelp-seed.php';
require_once HHELP_PATH . 'includes/class-hhelp-seo.php';

/**
 * Bootstrap.
 */
function hhelp_init() {
	Hhelp_CPT::instance();
	Hhelp_Meta::instance();
	Hhelp_REST::instance();
	Hhelp_Templates::instance();
	Hhelp_Assets::instance();
	Hhelp_Admin::instance();
	Hhelp_SEO::instance();
	if ( class_exists( 'WooCommerce' ) ) {
		Hhelp_WooCommerce::instance();
	}
}
add_action( 'plugins_loaded', 'hhelp_init' );

/**
 * Flush rewrites after version bump.
 */
function hhelp_maybe_flush_rewrites() {
	$installed = get_option( 'hhelp_version', '' );
	if ( HHELP_VERSION === $installed ) {
		return;
	}
	flush_rewrite_rules( false );
	update_option( 'hhelp_version', HHELP_VERSION, false );
}
add_action( 'init', 'hhelp_maybe_flush_rewrites', 99 );

/**
 * Activation.
 */
function hhelp_activate() {
	Hhelp_CPT::register();
	flush_rewrite_rules( false );
	update_option( 'hhelp_version', HHELP_VERSION, false );
	if ( ! get_option( 'hhelp_seeded' ) ) {
		Hhelp_Seed::run();
		update_option( 'hhelp_seeded', 1, false );
	}
}
register_activation_hook( __FILE__, 'hhelp_activate' );

/**
 * Deactivation.
 */
function hhelp_deactivate() {
	flush_rewrite_rules();
}
register_deactivation_hook( __FILE__, 'hhelp_deactivate' );

/**
 * Hub URL.
 *
 * @return string
 */
function hhelp_hub_url() {
	return get_post_type_archive_link( HHELP_CPT ) ?: home_url( '/help/' );
}

/**
 * Search URL.
 *
 * @param string $query Search query.
 * @return string
 */
function hhelp_search_url( $query = '' ) {
	$url = home_url( '/help/search/' );
	if ( '' !== trim( (string) $query ) ) {
		$url = add_query_arg( 'q', $query, $url );
	}
	return $url;
}

/**
 * Lesson/section permalink helper.
 *
 * @param int|WP_Post $post Post.
 * @return string
 */
function hhelp_url( $post ) {
	$link = get_permalink( $post );
	return $link ? $link : hhelp_hub_url();
}

/**
 * Whether current request is help area.
 *
 * @return bool
 */
function hhelp_is_help() {
	if ( is_post_type_archive( HHELP_CPT ) || is_singular( HHELP_CPT ) ) {
		return true;
	}
	return (bool) get_query_var( 'hhelp_search', false );
}

/**
 * Access level for a post.
 *
 * @param int $post_id Post ID.
 * @return string free|members|paid
 */
function hhelp_get_access( $post_id ) {
	$level = get_post_meta( (int) $post_id, '_hhelp_access', true );
	$level = is_string( $level ) ? $level : 'free';
	return in_array( $level, array( 'free', 'members', 'paid' ), true ) ? $level : 'free';
}

/**
 * Can current user view full content?
 *
 * @param int $post_id Post ID.
 * @return bool
 */
function hhelp_user_can_view( $post_id ) {
	return Hhelp_Access::can_view( (int) $post_id );
}

/**
 * Label for access badge.
 *
 * @param string $level Access level.
 * @return string
 */
function hhelp_access_label( $level ) {
	switch ( $level ) {
		case 'members':
			return __( 'ویژه اعضا', 'hesabix-help' );
		case 'paid':
			return __( 'پولی', 'hesabix-help' );
		default:
			return __( 'رایگان', 'hesabix-help' );
	}
}

/**
 * Curriculum sort for help queries: menu_order, then ID.
 *
 * @return array<string, string>
 */
function hhelp_query_order() {
	return array(
		'menu_order' => 'ASC',
		'ID'         => 'ASC',
	);
}

/**
 * Convert a number to Persian digits for syllabus numbering.
 *
 * @param int $n Number.
 * @return string
 */
function hhelp_fa_num( $n ) {
	return strtr(
		(string) (int) $n,
		array(
			'0' => '۰',
			'1' => '۱',
			'2' => '۲',
			'3' => '۳',
			'4' => '۴',
			'5' => '۵',
			'6' => '۶',
			'7' => '۷',
			'8' => '۸',
			'9' => '۹',
		)
	);
}
