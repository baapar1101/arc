<?php
/**
 * درخواست سمت سرور به API حسابیکس (بدون CORS برای مرورگر).
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * کلاینت HTTP ساده.
 */
final class Shabake_Tamin_Hesabix_API {

	/**
	 * آدرس پایهٔ API از تنظیمات (بدون اسلش انتهایی).
	 *
	 * @return string
	 */
	public static function base_url() {
		$url = (string) get_option( 'st_api_base_url', '' );
		$url = esc_url_raw( $url );
		return rtrim( $url, '/' );
	}

	/**
	 * آیا پایهٔ API تنظیم شده است؟
	 *
	 * @return bool
	 */
	public static function is_configured() {
		return '' !== self::base_url();
	}

	/**
	 * GET JSON از Hesabix.
	 *
	 * @param string $path   مسیر نسبی بعد از پایه (مثلاً /api/v1/public/catalog/products).
	 * @param array  $query  آرایهٔ query string.
	 * @return array{ ok: bool, code: int, body: string|array|null, error?: string }
	 */
	public static function get_json( $path, array $query = array() ) {
		if ( ! self::is_configured() ) {
			return array(
				'ok'    => false,
				'code'  => 503,
				'body'  => null,
				'error' => 'not_configured',
			);
		}

		$path = '/' . ltrim( (string) $path, '/' );
		$url  = self::base_url() . $path;
		if ( ! empty( $query ) ) {
			$url = add_query_arg( $query, $url );
		}

		$response = wp_remote_get(
			$url,
			array(
				'timeout' => 20,
				'headers' => array(
					'Accept' => 'application/json',
				),
			)
		);

		if ( is_wp_error( $response ) ) {
			return array(
				'ok'    => false,
				'code'  => 502,
				'body'  => null,
				'error' => $response->get_error_message(),
			);
		}

		$code = (int) wp_remote_retrieve_response_code( $response );
		$raw  = wp_remote_retrieve_body( $response );
		$data = json_decode( $raw, true );

		return array(
			'ok'   => $code >= 200 && $code < 300,
			'code' => $code,
			'body' => is_array( $data ) ? $data : $raw,
		);
	}

	/**
	 * POST JSON به Hesabix.
	 *
	 * @param string               $path مسیر نسبی.
	 * @param array<string, mixed> $body بدنهٔ JSON.
	 * @return array{ ok: bool, code: int, body: string|array|null, error?: string }
	 */
	public static function post_json( $path, array $body ) {
		if ( ! self::is_configured() ) {
			return array(
				'ok'    => false,
				'code'  => 503,
				'body'  => null,
				'error' => 'not_configured',
			);
		}

		$path = '/' . ltrim( (string) $path, '/' );
		$url  = self::base_url() . $path;

		$response = wp_remote_post(
			$url,
			array(
				'timeout' => 25,
				'headers' => array(
					'Accept'       => 'application/json',
					'Content-Type' => 'application/json',
				),
				'body'    => wp_json_encode( $body ),
			)
		);

		if ( is_wp_error( $response ) ) {
			return array(
				'ok'    => false,
				'code'  => 502,
				'body'  => null,
				'error' => $response->get_error_message(),
			);
		}

		$code = (int) wp_remote_retrieve_response_code( $response );
		$raw  = wp_remote_retrieve_body( $response );
		$data = json_decode( $raw, true );

		return array(
			'ok'   => $code >= 200 && $code < 300,
			'code' => $code,
			'body' => is_array( $data ) ? $data : $raw,
		);
	}
}
