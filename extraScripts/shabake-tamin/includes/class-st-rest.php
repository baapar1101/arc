<?php
/**
 * REST وردپرس — پراکسی امن به API عمومی Hesabix.
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * ثبت مسیرهای REST.
 */
final class Shabake_Tamin_REST {

	const NS = 'shabake-tamin/v1';

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
		add_action( 'rest_api_init', array( $this, 'register' ) );
	}

	/**
	 * محدودیت سادهٔ نرخ بر اساس IP (برای کاهش سوءاستفاده از پراکسی).
	 *
	 * @param string $bucket نام سطل.
	 * @param int    $max    حداکثر در پنجره.
	 * @param int    $window_seconds طول پنجره.
	 * @return true|WP_Error
	 */
	private function rate_limit( $bucket, $max, $window_seconds ) {
		$ip = isset( $_SERVER['REMOTE_ADDR'] ) ? sanitize_text_field( wp_unslash( (string) $_SERVER['REMOTE_ADDR'] ) ) : 'unknown';
		$window_seconds = max( 1, (int) $window_seconds );
		$slot           = (int) floor( time() / $window_seconds );
		$key            = 'st_rl_' . $bucket . '_' . md5( $ip . '|' . (string) $slot );
		$n              = (int) get_transient( $key );
		if ( $n >= $max ) {
			return new WP_Error(
				'st_rate_limit',
				__( 'تعداد درخواست بیش از حد؛ کمی بعد دوباره تلاش کنید.', 'shabake-tamin' ),
				array( 'status' => 429 )
			);
		}
		set_transient( $key, $n + 1, $window_seconds + 5 );
		return true;
	}

	/**
	 * ثبت routeها.
	 */
	public function register() {
		register_rest_route(
			self::NS,
			'/catalog',
			array(
				'methods'             => \WP_REST_Server::READABLE,
				'callback'            => array( $this, 'handle_catalog' ),
				'permission_callback' => '__return_true',
				'args'                => array(
					'search'      => array(
						'type'              => 'string',
						'sanitize_callback' => function ( $v ) {
							return mb_substr( sanitize_text_field( (string) $v ), 0, 500 );
						},
					),
					'business_id' => array( 'type' => 'integer' ),
					'category_id' => array( 'type' => 'integer' ),
					'province'    => array(
						'type'              => 'string',
						'sanitize_callback' => function ( $v ) {
							return mb_substr( sanitize_text_field( (string) $v ), 0, 100 );
						},
					),
					'city'        => array(
						'type'              => 'string',
						'sanitize_callback' => function ( $v ) {
							return mb_substr( sanitize_text_field( (string) $v ), 0, 100 );
						},
					),
					'skip'        => array(
						'type'    => 'integer',
						'default' => 0,
					),
					'take'        => array(
						'type'    => 'integer',
						'default' => 20,
					),
				),
			)
		);

		register_rest_route(
			self::NS,
			'/product/(?P<uuid>[0-9a-fA-F-]{10,40})',
			array(
				'methods'             => \WP_REST_Server::READABLE,
				'callback'            => array( $this, 'handle_product' ),
				'permission_callback' => '__return_true',
			)
		);

		register_rest_route(
			self::NS,
			'/captcha',
			array(
				'methods'             => \WP_REST_Server::CREATABLE,
				'callback'            => array( $this, 'handle_captcha' ),
				'permission_callback' => '__return_true',
			)
		);

		register_rest_route(
			self::NS,
			'/contact',
			array(
				'methods'             => \WP_REST_Server::CREATABLE,
				'callback'            => array( $this, 'handle_contact' ),
				'permission_callback' => '__return_true',
				'args'                => array(),
			)
		);
	}

	/**
	 * لیست کاتالوگ.
	 *
	 * @param \WP_REST_Request $req درخواست.
	 * @return \WP_REST_Response|\WP_Error
	 */
	public function handle_catalog( \WP_REST_Request $req ) {
		$rl = $this->rate_limit( 'catalog', 90, 60 );
		if ( is_wp_error( $rl ) ) {
			return $rl;
		}

		$skip = max( 0, min( 500000, (int) $req->get_param( 'skip' ) ) );
		$take = max( 1, min( 100, (int) $req->get_param( 'take' ) ) );

		$query = array(
			'skip' => $skip,
			'take' => $take,
		);
		$search = $req->get_param( 'search' );
		if ( is_string( $search ) && '' !== trim( $search ) ) {
			$query['search'] = trim( $search );
		}
		$bid = $req->get_param( 'business_id' );
		if ( null !== $bid && '' !== $bid ) {
			$query['business_id'] = absint( $bid );
		}
		$cid = $req->get_param( 'category_id' );
		if ( null !== $cid && '' !== $cid ) {
			$query['category_id'] = absint( $cid );
		}
		$prov = $req->get_param( 'province' );
		if ( is_string( $prov ) && '' !== trim( $prov ) ) {
			$query['province'] = trim( $prov );
		}
		$city = $req->get_param( 'city' );
		if ( is_string( $city ) && '' !== trim( $city ) ) {
			$query['city'] = trim( $city );
		}

		ksort( $query );
		$cache_key = 'cat_' . wp_json_encode( $query );
		$cached    = Shabake_Tamin_Cache::get( $cache_key );
		if ( null !== $cached ) {
			return new \WP_REST_Response( $cached, 200 );
		}

		$res = Shabake_Tamin_Hesabix_API::get_json( '/api/v1/public/catalog/products', $query );
		$out = $this->normalize_proxy_response( $res );
		if ( $out['ok'] && isset( $out['data'] ) ) {
			Shabake_Tamin_Cache::set( $cache_key, $out );
		}
		return new \WP_REST_Response( $out, $out['http'] );
	}

	/**
	 * جزئیات یک کالا.
	 *
	 * @param \WP_REST_Request $req درخواست.
	 * @return \WP_REST_Response|\WP_Error
	 */
	public function handle_product( \WP_REST_Request $req ) {
		$rl = $this->rate_limit( 'product', 120, 60 );
		if ( is_wp_error( $rl ) ) {
			return $rl;
		}

		$uuid = strtolower( (string) $req->get_param( 'uuid' ) );
		if ( ! preg_match( '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $uuid ) ) {
			return new \WP_Error( 'st_bad_uuid', __( 'شناسهٔ کالا نامعتبر است.', 'shabake-tamin' ), array( 'status' => 422 ) );
		}

		$cache_key = 'prd_' . $uuid;
		$cached    = Shabake_Tamin_Cache::get( $cache_key );
		if ( null !== $cached ) {
			return new \WP_REST_Response( $cached, 200 );
		}

		$path = '/api/v1/public/catalog/products/' . rawurlencode( $uuid );
		$res  = Shabake_Tamin_Hesabix_API::get_json( $path, array() );
		$out  = $this->normalize_proxy_response( $res );
		if ( $out['ok'] && isset( $out['data'] ) ) {
			Shabake_Tamin_Cache::set( $cache_key, $out );
		}
		return new \WP_REST_Response( $out, $out['http'] );
	}

	/**
	 * تولید کپچا (پراکسی POST).
	 *
	 * @return \WP_REST_Response|\WP_Error
	 */
	public function handle_captcha() {
		$rl = $this->rate_limit( 'captcha', 30, 60 );
		if ( is_wp_error( $rl ) ) {
			return $rl;
		}

		if ( ! Shabake_Tamin_Hesabix_API::is_configured() ) {
			return new WP_Error( 'st_not_configured', __( 'API تنظیم نشده است.', 'shabake-tamin' ), array( 'status' => 503 ) );
		}

		$url      = Shabake_Tamin_Hesabix_API::base_url() . '/api/v1/auth/captcha';
		$response = wp_remote_post(
			$url,
			array(
				'timeout' => 20,
				'headers' => array(
					'Accept'       => 'application/json',
					'Content-Type' => 'application/json',
				),
				'body'    => '{}',
			)
		);

		if ( is_wp_error( $response ) ) {
			return new WP_REST_Response(
				array(
					'ok'     => false,
					'http'   => 502,
					'error'  => $response->get_error_message(),
					'remote' => null,
				),
				502
			);
		}

		$code = (int) wp_remote_retrieve_response_code( $response );
		$raw  = wp_remote_retrieve_body( $response );
		$data = json_decode( $raw, true );

		if ( is_array( $data ) && ! empty( $data['success'] ) && isset( $data['data'] ) && is_array( $data['data'] ) ) {
			return new WP_REST_Response(
				array(
					'ok'     => true,
					'http'   => $code,
					'data'   => $data['data'],
					'remote' => $data,
				),
				$code
			);
		}

		return new WP_REST_Response(
			array(
				'ok'     => $code >= 200 && $code < 300,
				'http'   => $code,
				'remote' => is_array( $data ) ? $data : $raw,
			),
			$code
		);
	}

	/**
	 * ارسال پیام تماس.
	 *
	 * @param \WP_REST_Request $req درخواست.
	 * @return \WP_REST_Response|\WP_Error
	 */
	public function handle_contact( \WP_REST_Request $req ) {
		$rl = $this->rate_limit( 'contact', 15, 3600 );
		if ( is_wp_error( $rl ) ) {
			return $rl;
		}

		$body = $req->get_json_params();
		if ( ! is_array( $body ) ) {
			$body = array();
		}

		$payload = array(
			'business_id'            => isset( $body['business_id'] ) ? absint( $body['business_id'] ) : 0,
			'product_catalog_uuid'   => isset( $body['product_catalog_uuid'] ) ? sanitize_text_field( (string) $body['product_catalog_uuid'] ) : null,
			'sender_name'            => isset( $body['sender_name'] ) ? mb_substr( sanitize_text_field( (string) $body['sender_name'] ), 0, 200 ) : '',
			'sender_contact'         => isset( $body['sender_contact'] ) ? mb_substr( sanitize_text_field( (string) $body['sender_contact'] ), 0, 200 ) : '',
			'message'                => isset( $body['message'] ) ? mb_substr( sanitize_textarea_field( (string) $body['message'] ), 0, 2000 ) : '',
			'captcha_id'             => isset( $body['captcha_id'] ) ? sanitize_text_field( (string) $body['captcha_id'] ) : '',
			'captcha_code'           => isset( $body['captcha_code'] ) ? sanitize_text_field( (string) $body['captcha_code'] ) : '',
		);

		if ( $payload['business_id'] <= 0 ) {
			return new \WP_Error( 'st_bad_body', __( 'شناسهٔ کسب‌وکار الزامی است.', 'shabake-tamin' ), array( 'status' => 400 ) );
		}
		if ( '' === $payload['sender_name'] || '' === $payload['sender_contact'] || '' === $payload['message'] ) {
			return new \WP_Error( 'st_bad_body', __( 'فیلدهای نام، راه تماس و متن پیام الزامی‌اند.', 'shabake-tamin' ), array( 'status' => 400 ) );
		}
		if ( strlen( $payload['captcha_id'] ) < 8 || strlen( $payload['captcha_code'] ) < 3 ) {
			return new \WP_Error( 'st_bad_body', __( 'کپچا ناقص است.', 'shabake-tamin' ), array( 'status' => 400 ) );
		}

		$pu = $payload['product_catalog_uuid'];
		if ( null === $pu || '' === $pu ) {
			unset( $payload['product_catalog_uuid'] );
		} elseif ( ! preg_match( '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $pu ) ) {
			return new \WP_Error( 'st_bad_uuid', __( 'شناسهٔ کالا نامعتبر است.', 'shabake-tamin' ), array( 'status' => 422 ) );
		}

		$res = Shabake_Tamin_Hesabix_API::post_json( '/api/v1/public/catalog/contact-messages', $payload );
		$out = $this->normalize_proxy_response( $res );
		return new \WP_REST_Response( $out, $out['http'] );
	}

	/**
	 * یکدست‌سازی پاسخ برای فرانت (همیشه JSON قابل parse در لایهٔ remote).
	 *
	 * @param array<string, mixed> $res خروجی get_json/post_json.
	 * @return array{ ok: bool, http: int, data?: mixed, remote?: mixed, error?: string }
	 */
	private function normalize_proxy_response( array $res ) {
		$code = isset( $res['code'] ) ? (int) $res['code'] : 500;
		$body = $res['body'] ?? null;

		if ( ! empty( $res['error'] ) && 'not_configured' === $res['error'] ) {
			return array(
				'ok'    => false,
				'http'  => 503,
				'error' => 'not_configured',
			);
		}

		if ( ! $res['ok'] && ! is_array( $body ) ) {
			return array(
				'ok'    => false,
				'http'  => $code >= 400 ? $code : 502,
				'error' => isset( $res['error'] ) ? (string) $res['error'] : 'upstream',
				'remote' => $body,
			);
		}

		if ( is_array( $body ) && isset( $body['success'] ) && $body['success'] && array_key_exists( 'data', $body ) ) {
			return array(
				'ok'     => true,
				'http'   => $code,
				'data'   => $body['data'],
				'remote' => $body,
			);
		}

		return array(
			'ok'     => $res['ok'],
			'http'   => $code,
			'remote' => $body,
		);
	}
}
