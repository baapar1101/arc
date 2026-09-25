<?php
/**
 * REST API برای دریافت رویدادهای نصب/به‌روزرسانی.
 *
 * @package Hesabix_Install_Stats
 */

defined( 'ABSPATH' ) || exit;

/**
 * REST routes.
 */
final class HIS_REST {

	const NS = 'hesabix-stats/v1';

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
	 * ثبت مسیرها.
	 */
	public function register() {
		register_rest_route(
			self::NS,
			'/event',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( $this, 'handle_event' ),
				'permission_callback' => '__return_true',
			)
		);

		register_rest_route(
			self::NS,
			'/health',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( $this, 'handle_health' ),
				'permission_callback' => '__return_true',
			)
		);
	}

	/**
	 * سلامت ساده برای تست endpoint.
	 *
	 * @return WP_REST_Response
	 */
	public function handle_health() {
		return new WP_REST_Response(
			array(
				'ok'      => true,
				'service' => 'hesabix-install-stats',
				'version' => HIS_VERSION,
			),
			200
		);
	}

	/**
	 * دریافت رویداد.
	 *
	 * @param WP_REST_Request $request درخواست.
	 * @return WP_REST_Response|WP_Error
	 */
	public function handle_event( WP_REST_Request $request ) {
		$rl = $this->rate_limit( 'event', 30, 60 );
		if ( is_wp_error( $rl ) ) {
			return $rl;
		}

		$token_ok = $this->verify_ingest_token( $request );
		if ( is_wp_error( $token_ok ) ) {
			return $token_ok;
		}

		$raw = $request->get_json_params();
		if ( ! is_array( $raw ) || ! $raw ) {
			// fallback form-encoded
			$raw = $request->get_body_params();
		}
		if ( ! is_array( $raw ) || ! $raw ) {
			return new WP_Error(
				'his_empty_body',
				__( 'بدنهٔ JSON خالی یا نامعتبر است.', 'hesabix-install-stats' ),
				array( 'status' => 400 )
			);
		}

		// محدودیت اندازهٔ تقریبی.
		$body = $request->get_body();
		if ( is_string( $body ) && strlen( $body ) > 32768 ) {
			return new WP_Error(
				'his_body_too_large',
				__( 'بدنهٔ درخواست بیش از حد بزرگ است.', 'hesabix-install-stats' ),
				array( 'status' => 413 )
			);
		}

		$normalized = HIS_Storage::normalize_payload( $raw );
		if ( is_wp_error( $normalized ) ) {
			return $normalized;
		}

		$remote_ip = $this->client_ip();
		$result    = HIS_Storage::ingest( $normalized, $remote_ip );
		if ( is_wp_error( $result ) ) {
			return $result;
		}

		return new WP_REST_Response( $result, $result['is_new'] ? 201 : 200 );
	}

	/**
	 * بررسی توکن ingest.
	 *
	 * @param WP_REST_Request $request درخواست.
	 * @return true|WP_Error
	 */
	private function verify_ingest_token( WP_REST_Request $request ) {
		$expected = (string) get_option( 'his_ingest_token', HIS_DEFAULT_INGEST_TOKEN );
		if ( $expected === '' ) {
			// خالی = پذیرش بدون توکن (فقط برای محیط توسعه؛ در production مقدار بگذارید).
			return true;
		}

		$got = $request->get_header( 'x-hesabix-stats-token' );
		if ( ! is_string( $got ) || $got === '' ) {
			$got = $request->get_param( 'token' );
		}
		$got = is_string( $got ) ? trim( $got ) : '';

		if ( $got === '' || ! hash_equals( $expected, $got ) ) {
			return new WP_Error(
				'his_forbidden',
				__( 'توکن ingest نامعتبر است.', 'hesabix-install-stats' ),
				array( 'status' => 403 )
			);
		}
		return true;
	}

	/**
	 * محدودیت نرخ بر اساس IP.
	 *
	 * @param string $bucket سطل.
	 * @param int    $max حداکثر.
	 * @param int    $window_seconds پنجره.
	 * @return true|WP_Error
	 */
	private function rate_limit( $bucket, $max, $window_seconds ) {
		$ip             = $this->client_ip();
		$window_seconds = max( 1, (int) $window_seconds );
		$slot           = (int) floor( time() / $window_seconds );
		$key            = 'his_rl_' . $bucket . '_' . md5( $ip . '|' . (string) $slot );
		$n              = (int) get_transient( $key );
		if ( $n >= $max ) {
			return new WP_Error(
				'his_rate_limit',
				__( 'تعداد درخواست بیش از حد؛ کمی بعد دوباره تلاش کنید.', 'hesabix-install-stats' ),
				array( 'status' => 429 )
			);
		}
		set_transient( $key, $n + 1, $window_seconds + 5 );
		return true;
	}

	/**
	 * IP کلاینت با درنظر گرفتن پروکسی قابل اعتماد وردپرس.
	 *
	 * @return string
	 */
	private function client_ip() {
		if ( ! empty( $_SERVER['HTTP_X_FORWARDED_FOR'] ) ) {
			$parts = explode( ',', (string) wp_unslash( $_SERVER['HTTP_X_FORWARDED_FOR'] ) );
			$first = trim( $parts[0] );
			if ( filter_var( $first, FILTER_VALIDATE_IP ) ) {
				return $first;
			}
		}
		if ( ! empty( $_SERVER['REMOTE_ADDR'] ) ) {
			$ip = sanitize_text_field( wp_unslash( (string) $_SERVER['REMOTE_ADDR'] ) );
			if ( filter_var( $ip, FILTER_VALIDATE_IP ) ) {
				return $ip;
			}
		}
		return '0.0.0.0';
	}
}
