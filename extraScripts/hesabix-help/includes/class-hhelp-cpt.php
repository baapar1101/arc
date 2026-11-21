<?php
/**
 * Custom post type registration.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hhelp_CPT
 */
class Hhelp_CPT {

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
		add_action( 'init', array( __CLASS__, 'register' ) );
		add_action( 'init', array( $this, 'register_search_rewrite' ), 20 );
		add_filter( 'query_vars', array( $this, 'query_vars' ) );
		add_action( 'pre_get_posts', array( $this, 'archive_query' ) );
		add_action( 'parse_query', array( $this, 'parse_search_query' ) );
	}

	/**
	 * Register CPT.
	 */
	public static function register() {
		$labels = array(
			'name'               => __( 'راهنمای حسابیکس', 'hesabix-help' ),
			'singular_name'      => __( 'مطلب راهنما', 'hesabix-help' ),
			'add_new'            => __( 'افزودن', 'hesabix-help' ),
			'add_new_item'       => __( 'افزودن مطلب راهنما', 'hesabix-help' ),
			'edit_item'          => __( 'ویرایش مطلب راهنما', 'hesabix-help' ),
			'new_item'           => __( 'مطلب جدید', 'hesabix-help' ),
			'view_item'          => __( 'مشاهده', 'hesabix-help' ),
			'search_items'       => __( 'جستجو در راهنما', 'hesabix-help' ),
			'not_found'          => __( 'مطلبی یافت نشد', 'hesabix-help' ),
			'not_found_in_trash' => __( 'در زباله‌دان چیزی نیست', 'hesabix-help' ),
			'parent_item_colon'  => __( 'والد:', 'hesabix-help' ),
			'menu_name'          => __( 'راهنمای جامع', 'hesabix-help' ),
			'all_items'          => __( 'همه مطالب', 'hesabix-help' ),
		);

		register_post_type(
			HHELP_CPT,
			array(
				'labels'              => $labels,
				'public'              => true,
				'publicly_queryable'  => true,
				'show_ui'             => true,
				'show_in_menu'        => true,
				'show_in_rest'        => true,
				'rest_base'           => 'help',
				'rest_controller_class' => 'WP_REST_Posts_Controller',
				'menu_icon'           => 'dashicons-welcome-learn-more',
				'menu_position'       => 22,
				'hierarchical'        => true,
				'has_archive'         => 'help',
				'rewrite'             => array(
					'slug'       => 'help',
					'with_front' => false,
					'pages'      => true,
				),
				'supports'            => array( 'title', 'editor', 'excerpt', 'thumbnail', 'page-attributes', 'revisions', 'custom-fields' ),
				'capability_type'     => 'page',
				'map_meta_cap'        => true,
				'exclude_from_search' => false,
			)
		);
	}

	/**
	 * Search rewrite under /help/search/.
	 */
	public function register_search_rewrite() {
		add_rewrite_rule( '^help/search/?$', 'index.php?hhelp_search=1', 'top' );
	}

	/**
	 * @param array<int, string> $vars Query vars.
	 * @return array<int, string>
	 */
	public function query_vars( $vars ) {
		$vars[] = 'hhelp_search';
		return $vars;
	}

	/**
	 * Hub archive: only top-level sections.
	 *
	 * @param WP_Query $query Query.
	 */
	public function archive_query( $query ) {
		if ( ! $query->is_main_query() ) {
			return;
		}
		if ( is_admin() ) {
			if ( $query->get( 'post_type' ) === HHELP_CPT && '' === $query->get( 'orderby' ) ) {
				$query->set( 'orderby', hhelp_query_order() );
			}
			return;
		}
		if ( $query->is_post_type_archive( HHELP_CPT ) ) {
			$query->set( 'post_parent', 0 );
			$query->set( 'orderby', hhelp_query_order() );
			$query->set( 'posts_per_page', 50 );
		}
	}

	/**
	 * Keep /help/search/ from falling through as blog home.
	 *
	 * @param WP_Query $query Query.
	 */
	public function parse_search_query( $query ) {
		if ( is_admin() || ! $query->is_main_query() ) {
			return;
		}
		if ( ! $query->get( 'hhelp_search' ) ) {
			return;
		}
		$query->is_home    = false;
		$query->is_search  = false;
		$query->is_archive = false;
		$query->is_404     = false;
		$query->set( 'post_type', HHELP_CPT );
		$query->set( 'posts_per_page', 1 );
	}
}
