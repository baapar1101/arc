<?php
/**
 * ذخیرهٔ لاگ دیباگ ویجیت (بدون افشای توکن کامل) و اکشن Ajax.
 *
 * @package HesabixChat
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hesabix_Chat_Debug
 */
final class Hesabix_Chat_Debug {

	const LOG_OPTION = 'hesabix_chat_widget_debug_log';

	const MAX_ENTRIES = 400;

	const NONCE_ACTION = 'hesabix_chat_widget_debug_v1';

	public static function init() {
		add_action( 'wp_ajax_nopriv_hesabix_chat_debug_push', array( __CLASS__, 'ajax_push' ) );
		add_action( 'wp_ajax_hesabix_chat_debug_push', array( __CLASS__, 'ajax_push' ) );
		add_action( 'wp_ajax_hesabix_chat_debug_clear', array( __CLASS__, 'ajax_clear' ) );
	}

	/**
	 * @return bool
	 */
	public static function is_logging_enabled() {
		$o = Hesabix_Chat_Admin::get_options();
		return ! empty( $o['widget_debug_logging'] );
	}

	/**
	 * @return array<int, array<string, mixed>>
	 */
	public static function get_entries() {
		$raw = get_option( self::LOG_OPTION, array() );
		if ( ! is_array( $raw ) ) {
			return array();
		}
		$items = isset( $raw['items'] ) && is_array( $raw['items'] ) ? $raw['items'] : array();
		return array_values( $items );
	}

	public static function clear_log() {
		delete_option( self::LOG_OPTION );
	}

	/**
	 * @param array<int, array<string, mixed>> $batch .
	 */
	public static function append_batch( array $batch ) {
		if ( $batch === array() ) {
			return;
		}
		$now = time();
		$raw = get_option( self::LOG_OPTION, array() );
		if ( ! is_array( $raw ) ) {
			$raw = array();
		}
		$items = isset( $raw['items'] ) && is_array( $raw['items'] ) ? $raw['items'] : array();
		foreach ( $batch as $row ) {
			if ( ! is_array( $row ) ) {
				continue;
			}
			$topic = isset( $row['topic'] ) ? sanitize_text_field( (string) $row['topic'] ) : '';
			if ( $topic === '' || ( function_exists( 'mb_strlen' ) ? mb_strlen( $topic ) > 80 : strlen( $topic ) > 80 ) ) {
				$topic = 'event';
			}
			$payload = isset( $row['payload'] ) ? $row['payload'] : null;
			if ( null !== $payload && ! is_scalar( $payload ) ) {
				$enc = wp_json_encode( $payload );
				if ( false !== $enc && function_exists( 'mb_strlen' ) ? mb_strlen( $enc ) : strlen( $enc ) > 12000 ) {
					$enc = function_exists( 'mb_substr' ) ? mb_substr( $enc, 0, 12000 ) . '…' : substr( $enc, 0, 12000 ) . '…';
				}
				if ( false !== $enc ) {
					$payload = $enc;
				} else {
					$payload = '[non-json]';
				}
			} elseif ( is_string( $payload ) ) {
				if ( function_exists( 'mb_strlen' ) ? mb_strlen( $payload ) : strlen( $payload ) > 4000 ) {
					$payload = function_exists( 'mb_substr' )
						? mb_substr( $payload, 0, 4000 ) . '…'
						: substr( $payload, 0, 4000 ) . '…';
				}
			}
			$items[] = array(
				'server_ts' => $now,
				'client_ts' => isset( $row['client_ts'] ) ? (int) $row['client_ts'] : 0,
				'topic'     => $topic,
				'referer'   => isset( $row['referer'] ) ? esc_url_raw( (string) $row['referer'] ) : '',
				'payload'   => $payload,
			);
		}
		while ( count( $items ) > self::MAX_ENTRIES ) {
			array_shift( $items );
		}
		update_option(
			self::LOG_OPTION,
			array(
				'items'      => array_values( $items ),
				'updated_at' => $now,
			),
			false
		);
	}

	public static function ajax_push() {
		if ( ! self::is_logging_enabled() ) {
			wp_send_json_error( array( 'message' => 'disabled' ), 403 );
		}
		$nonce = isset( $_POST['nonce'] ) ? sanitize_text_field( wp_unslash( $_POST['nonce'] ) ) : '';
		if ( ! wp_verify_nonce( $nonce, self::NONCE_ACTION ) ) {
			wp_send_json_error( array( 'message' => 'nonce' ), 403 );
		}

		$ip = isset( $_SERVER['REMOTE_ADDR'] ) ? (string) $_SERVER['REMOTE_ADDR'] : '';
		$key = 'hesabix_dbg_' . md5( $ip . '|' . wp_salt() );
		$n   = (int) get_transient( $key );
		if ( $n > 200 ) {
			wp_send_json_error( array( 'message' => 'rate' ), 429 );
		}
		set_transient( $key, $n + 1, HOUR_IN_SECONDS );

		$raw = isset( $_POST['batch'] ) ? wp_unslash( $_POST['batch'] ) : '';
		if ( ! is_string( $raw ) || $raw === '' ) {
			wp_send_json_error( array( 'message' => 'empty' ), 400 );
		}
		$parsed = json_decode( $raw, true );
		if ( ! is_array( $parsed ) ) {
			wp_send_json_error( array( 'message' => 'json' ), 400 );
		}
		if ( isset( $parsed['referer'] ) ) {
			$parsed['referer'] = esc_url_raw( (string) $parsed['referer'] );
		}

		if ( isset( $parsed['items'] ) && is_array( $parsed['items'] ) ) {
			$take = array_slice( $parsed['items'], -40 );
			$prep = array();
			foreach ( $take as $it ) {
				if ( ! is_array( $it ) ) {
					continue;
				}
				$prep[] = array(
					'topic'     => isset( $it['topic'] ) ? (string) $it['topic'] : '',
					'client_ts' => isset( $it['client_ts'] ) ? (int) $it['client_ts'] : 0,
					'payload'   => isset( $it['payload'] ) ? $it['payload'] : null,
					'referer'   => isset( $parsed['referer'] ) ? (string) $parsed['referer'] : '',
				);
			}
			self::append_batch( $prep );
		}
		wp_send_json_success( array( 'ok' => true ) );
	}

	public static function ajax_clear() {
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_send_json_error( array( 'message' => 'cap' ), 403 );
		}
		check_ajax_referer( 'hesabix_chat_debug_admin', 'nonce' );
		self::clear_log();
		wp_send_json_success( array( 'ok' => true ) );
	}
}
