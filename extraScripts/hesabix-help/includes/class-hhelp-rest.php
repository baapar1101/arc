<?php
/**
 * REST API support: registered meta + Application Passwords helpers.
 *
 * Path A — standard WP REST (`/wp/v2/help`) for external AI agents.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hhelp_REST
 */
class Hhelp_REST {

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
		add_action( 'init', array( $this, 'register_meta' ), 25 );
		add_filter( 'wp_is_application_passwords_available', array( $this, 'ensure_app_passwords' ) );
		add_filter( 'rest_prepare_' . HHELP_CPT, array( $this, 'prepare_response' ), 10, 3 );
		add_filter( 'rest_' . HHELP_CPT . '_collection_params', array( $this, 'collection_params' ) );
		add_filter( 'rest_' . HHELP_CPT . '_query', array( $this, 'rest_query' ), 10, 2 );
	}

	/**
	 * If site URL is HTTPS, keep Application Passwords available
	 * (CLI / mis-detected SSL behind reverse proxy).
	 *
	 * @param bool $available Available.
	 * @return bool
	 */
	public function ensure_app_passwords( $available ) {
		if ( $available ) {
			return true;
		}
		$home = home_url( '/' );
		if ( is_string( $home ) && 0 === stripos( $home, 'https://' ) ) {
			return true;
		}
		return $available;
	}

	/**
	 * Whether current user may edit help meta via REST.
	 *
	 * @return bool
	 */
	public static function can_edit_meta() {
		return current_user_can( 'edit_pages' );
	}

	/**
	 * Register all help meta for REST read/write under `meta`.
	 */
	public function register_meta() {
		$auth = array( __CLASS__, 'can_edit_meta' );

		register_post_meta(
			HHELP_CPT,
			'_hhelp_access',
			array(
				'type'              => 'string',
				'description'       => 'Access level: free | members | paid',
				'single'            => true,
				'default'           => 'free',
				'show_in_rest'      => array(
					'schema' => array(
						'type' => 'string',
						'enum' => array( 'free', 'members', 'paid' ),
					),
				),
				'auth_callback'     => $auth,
				'sanitize_callback' => array( $this, 'sanitize_access' ),
			)
		);

		register_post_meta(
			HHELP_CPT,
			'_hhelp_product_id',
			array(
				'type'              => 'integer',
				'description'       => 'Linked WooCommerce product ID for paid lessons',
				'single'            => true,
				'default'           => 0,
				'show_in_rest'      => true,
				'auth_callback'     => $auth,
				'sanitize_callback' => 'absint',
			)
		);

		register_post_meta(
			HHELP_CPT,
			'_hhelp_icon',
			array(
				'type'              => 'string',
				'description'       => 'Section icon slug (start, invoice, inventory, …)',
				'single'            => true,
				'default'           => '',
				'show_in_rest'      => true,
				'auth_callback'     => $auth,
				'sanitize_callback' => 'sanitize_key',
			)
		);

		register_post_meta(
			HHELP_CPT,
			'_hhelp_featured',
			array(
				'type'              => 'boolean',
				'description'       => 'Show in hub featured paths',
				'single'            => true,
				'default'           => false,
				'show_in_rest'      => true,
				'auth_callback'     => $auth,
				'sanitize_callback' => array( $this, 'sanitize_bool' ),
			)
		);

		register_post_meta(
			HHELP_CPT,
			'_hhelp_video_type',
			array(
				'type'              => 'string',
				'description'       => 'Video provider: none | aparat | youtube | embed',
				'single'            => true,
				'default'           => 'none',
				'show_in_rest'      => array(
					'schema' => array(
						'type' => 'string',
						'enum' => array( 'none', 'aparat', 'youtube', 'embed' ),
					),
				),
				'auth_callback'     => $auth,
				'sanitize_callback' => array( $this, 'sanitize_video_type' ),
			)
		);

		register_post_meta(
			HHELP_CPT,
			'_hhelp_video_id',
			array(
				'type'              => 'string',
				'description'       => 'Video ID or embed URL',
				'single'            => true,
				'default'           => '',
				'show_in_rest'      => true,
				'auth_callback'     => $auth,
				'sanitize_callback' => 'sanitize_text_field',
			)
		);

		register_post_meta(
			HHELP_CPT,
			'_hhelp_video_duration',
			array(
				'type'              => 'string',
				'description'       => 'Human-readable duration (e.g. 4:20)',
				'single'            => true,
				'default'           => '',
				'show_in_rest'      => true,
				'auth_callback'     => $auth,
				'sanitize_callback' => 'sanitize_text_field',
			)
		);
	}

	/**
	 * @param mixed $value Value.
	 * @return string
	 */
	public function sanitize_access( $value ) {
		$value = sanitize_key( (string) $value );
		return in_array( $value, array( 'free', 'members', 'paid' ), true ) ? $value : 'free';
	}

	/**
	 * @param mixed $value Value.
	 * @return string
	 */
	public function sanitize_video_type( $value ) {
		$value = sanitize_key( (string) $value );
		return in_array( $value, array( 'none', 'aparat', 'youtube', 'embed' ), true ) ? $value : 'none';
	}

	/**
	 * @param mixed $value Value.
	 * @return bool
	 */
	public function sanitize_bool( $value ) {
		return (bool) $value;
	}

	/**
	 * Default REST list order is syllabus (menu_order), not date.
	 *
	 * @param array<string, mixed> $params Params.
	 * @return array<string, mixed>
	 */
	public function collection_params( $params ) {
		if ( isset( $params['orderby'] ) ) {
			$params['orderby']['default'] = 'menu_order';
			$params['orderby']['enum'][]  = 'menu_order';
			$params['orderby']['enum']    = array_values( array_unique( $params['orderby']['enum'] ) );
		}
		if ( isset( $params['order'] ) ) {
			$params['order']['default'] = 'asc';
		}
		return $params;
	}

	/**
	 * @param array<string, mixed> $args    WP_Query args.
	 * @param WP_REST_Request      $request Request.
	 * @return array<string, mixed>
	 */
	public function rest_query( $args, $request ) {
		unset( $request );
		if ( empty( $args['orderby'] ) || 'date' === $args['orderby'] ) {
			$args['orderby'] = hhelp_query_order();
		}
		return $args;
	}

	/**
	 * Add convenience fields for AI clients (public keys mirroring meta).
	 *
	 * @param WP_REST_Response $response Response.
	 * @param WP_Post          $post     Post.
	 * @param WP_REST_Request  $request  Request.
	 * @return WP_REST_Response
	 */
	public function prepare_response( $response, $post, $request ) {
		$data = $response->get_data();
		if ( ! is_array( $data ) ) {
			return $response;
		}

		$meta = isset( $data['meta'] ) && is_array( $data['meta'] ) ? $data['meta'] : array();

		// Friendly aliases (same values as underscore meta keys).
		$data['hhelp'] = array(
			'access'         => isset( $meta['_hhelp_access'] ) ? $meta['_hhelp_access'] : hhelp_get_access( $post->ID ),
			'product_id'     => isset( $meta['_hhelp_product_id'] ) ? (int) $meta['_hhelp_product_id'] : (int) get_post_meta( $post->ID, '_hhelp_product_id', true ),
			'icon'           => isset( $meta['_hhelp_icon'] ) ? (string) $meta['_hhelp_icon'] : (string) get_post_meta( $post->ID, '_hhelp_icon', true ),
			'featured'       => isset( $meta['_hhelp_featured'] ) ? (bool) $meta['_hhelp_featured'] : (bool) get_post_meta( $post->ID, '_hhelp_featured', true ),
			'video_type'     => isset( $meta['_hhelp_video_type'] ) ? (string) $meta['_hhelp_video_type'] : (string) get_post_meta( $post->ID, '_hhelp_video_type', true ),
			'video_id'       => isset( $meta['_hhelp_video_id'] ) ? (string) $meta['_hhelp_video_id'] : (string) get_post_meta( $post->ID, '_hhelp_video_id', true ),
			'video_duration' => isset( $meta['_hhelp_video_duration'] ) ? (string) $meta['_hhelp_video_duration'] : (string) get_post_meta( $post->ID, '_hhelp_video_duration', true ),
			'url'            => get_permalink( $post ),
		);

		$response->set_data( $data );
		return $response;
	}
}
