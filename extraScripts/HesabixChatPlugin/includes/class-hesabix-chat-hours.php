<?php
/**
 * ساعت کاری، تعطیلات و پیام خارج از حضور ویجیت.
 *
 * @package HesabixChat
 */

defined( 'ABSPATH' ) || exit;

/**
 * Hesabix_Chat_Business_Hours
 */
final class Hesabix_Chat_Business_Hours {

	const AJAX_ACTION = 'hesabix_chat_hours_status';

	const NONCE_ACTION = 'hesabix_chat_hours_v1';

	public static function init() {
		add_action( 'wp_ajax_' . self::AJAX_ACTION, array( __CLASS__, 'ajax_status' ) );
		add_action( 'wp_ajax_nopriv_' . self::AJAX_ACTION, array( __CLASS__, 'ajax_status' ) );
	}

	public static function ajax_status() {
		check_ajax_referer( self::NONCE_ACTION, 'nonce' );
		$r = self::evaluate_for_public();
		$r = apply_filters( 'hesabix_chat_hours_ajax_response', $r, Hesabix_Chat_Admin::get_options() );
		if ( ! is_array( $r ) || ! isset( $r['outside_hours'], $r['message'] ) ) {
			wp_send_json_error( array( 'message' => 'invalid' ), 500 );
		}
		wp_send_json_success(
			array(
				'outside_hours' => (bool) $r['outside_hours'],
				'message'       => (string) $r['message'],
			)
		);
	}

	/**
	 * @param array<string, mixed>|null $o در صورت null از get_options می‌آید.
	 * @return array{outside_hours: bool, message: string}
	 */
	public static function evaluate_for_public( $o = null ) {
		if ( null === $o ) {
			$o = Hesabix_Chat_Admin::get_options();
		}
		$o = apply_filters( 'hesabix_chat_business_hours_options', $o );
		if ( empty( $o['business_hours_enabled'] ) ) {
			return array(
				'outside_hours' => false,
				'message'       => '',
			);
		}
		$today = self::now_in_tz( $o );

		return self::evaluate_at( $o, $today );
	}

	/**
	 * برای اسنپ‌شات localize (اولین بارگذاری صفحه).
	 *
	 * @param array<string, mixed>|null $o .
	 * @return array{outside: bool, message: string, raw: array{outside_hours: bool, message: string}}
	 */
	public static function localize_snapshot( $o = null ): array {
		if ( null === $o ) {
			$o = Hesabix_Chat_Admin::get_options();
		}
		$r = self::evaluate_for_public( $o );

		return array(
			'outside' => ! empty( $r['outside_hours'] ),
			'message' => ! empty( $r['outside_hours'] ) ? Hesabix_Chat_Admin::business_hours_visitor_message_line( $o ) : '',
			'raw'     => $r,
		);
	}

	/**
	 * @param array<string, mixed> $o .
	 * @param \DateTimeImmutable   $instant .
	 * @return array{outside_hours: bool, message: string}
	 */
	private static function evaluate_at( array $o, DateTimeImmutable $instant ) {
		$sched    = Hesabix_Chat_Admin::normalize_business_hours_schedule( isset( $o['business_hours_schedule'] ) ? $o['business_hours_schedule'] : null );
		$holidays = isset( $o['business_hours_holidays'] ) && is_array( $o['business_hours_holidays'] ) ? $o['business_hours_holidays'] : array();

		$ymd = $instant->format( 'Y-m-d' );

		foreach ( $holidays as $h ) {
			if ( ! is_string( $h ) || $h === '' ) {
				continue;
			}
			if ( $ymd === $h ) {
				return array(
					'outside_hours' => true,
					'message'       => Hesabix_Chat_Admin::business_hours_visitor_message_line( $o ),
				);
			}
		}

		$dow = (int) $instant->format( 'w' );
		if ( $dow < 0 || $dow > 6 ) {
			$dow = 0;
		}
		$row = isset( $sched[ $dow ] ) && is_array( $sched[ $dow ] ) ? $sched[ $dow ] : array();

		if ( ! empty( $row['closed'] ) ) {
			return array(
				'outside_hours' => true,
				'message'       => Hesabix_Chat_Admin::business_hours_visitor_message_line( $o ),
			);
		}

		$open  = Hesabix_Chat_Admin::sanitize_time_hm( isset( $row['open'] ) ? (string) $row['open'] : '' );
		$close = Hesabix_Chat_Admin::sanitize_time_hm( isset( $row['close'] ) ? (string) $row['close'] : '' );

		$o_min = Hesabix_Chat_Admin::minutes_from_hm( $open );
		$c_min = Hesabix_Chat_Admin::minutes_from_hm( $close );
		if ( null === $o_min || null === $c_min || $o_min === $c_min ) {
			return array(
				'outside_hours' => true,
				'message'       => Hesabix_Chat_Admin::business_hours_visitor_message_line( $o ),
			);
		}

		if ( $c_min <= $o_min ) {
			// شیفت شب پشتیبانی نمی‌شود؛ خارج از وقت تلقی شود تا ناخوشیگیری نشود.
			return array(
				'outside_hours' => true,
				'message'       => Hesabix_Chat_Admin::business_hours_visitor_message_line( $o ),
			);
		}

		$h    = (int) $instant->format( 'G' );
		$i    = (int) $instant->format( 'i' );
		$nowm = $h * 60 + $i;
		if ( $nowm >= $o_min && $nowm < $c_min ) {
			return array(
				'outside_hours' => false,
				'message'       => '',
			);
		}

		return array(
			'outside_hours' => true,
			'message'       => Hesabix_Chat_Admin::business_hours_visitor_message_line( $o ),
		);
	}

	/**
	 * زمان کنونی در منطقهٔ انتخاب‌شده برای ساعت کاری.
	 *
	 * @param array<string, mixed> $o .
	 */
	private static function now_in_tz( array $o ): DateTimeImmutable {
		$tz = self::timezone_for_hours( $o );
		try {
			return new DateTimeImmutable( 'now', $tz );
		} catch ( Exception $e ) {
			return new DateTimeImmutable( 'now', wp_timezone() );
		}
	}

	/**
	 * @param array<string, mixed> $o .
	 */
	private static function timezone_for_hours( array $o ): DateTimeZone {
		$mode = isset( $o['business_hours_tz_mode'] ) ? (string) $o['business_hours_tz_mode'] : 'wp';
		if ( 'custom' === $mode ) {
			$id = isset( $o['business_hours_timezone'] ) ? sanitize_text_field( (string) $o['business_hours_timezone'] ) : '';
			if ( '' !== $id ) {
				try {
					return new DateTimeZone( $id );
				} catch ( Exception $e ) {
					return wp_timezone();
				}
			}
		}

		return wp_timezone();
	}
}
