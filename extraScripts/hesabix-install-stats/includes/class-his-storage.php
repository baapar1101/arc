<?php
/**
 * لایهٔ ذخیره و upsert نمونه‌ها/رویدادها.
 *
 * @package Hesabix_Install_Stats
 */

defined( 'ABSPATH' ) || exit;

/**
 * Storage helpers.
 */
final class HIS_Storage {

	/**
	 * @return string
	 */
	public static function instances_table() {
		global $wpdb;
		return $wpdb->prefix . 'hesabix_install_instances';
	}

	/**
	 * @return string
	 */
	public static function events_table() {
		global $wpdb;
		return $wpdb->prefix . 'hesabix_install_events';
	}

	/**
	 * رویدادهای مجاز.
	 *
	 * @return string[]
	 */
	public static function allowed_events() {
		return array( 'install', 'update', 'heartbeat' );
	}

	/**
	 * آیا UUID معتبر است (نسخهٔ سادهٔ RFC).
	 *
	 * @param string $id شناسه.
	 * @return bool
	 */
	public static function is_valid_install_id( $id ) {
		return (bool) preg_match(
			'/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i',
			(string) $id
		);
	}

	/**
	 * نرمال‌سازی دامنه (بدون scheme/path).
	 *
	 * @param string $domain دامنه.
	 * @return string
	 */
	public static function sanitize_domain( $domain ) {
		$domain = strtolower( trim( (string) $domain ) );
		$domain = preg_replace( '#^https?://#', '', $domain );
		$domain = preg_replace( '#/.*$#', '', $domain );
		$domain = preg_replace( '/:\d+$/', '', $domain );
		$domain = sanitize_text_field( $domain );
		if ( $domain === '' || strlen( $domain ) > 253 ) {
			return '';
		}
		if ( ! preg_match( '/^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$/i', $domain ) ) {
			return '';
		}
		return $domain;
	}

	/**
	 * نرمال‌سازی payload ورودی REST به آرایهٔ امن.
	 *
	 * @param array $raw دادهٔ خام.
	 * @return array|\WP_Error
	 */
	public static function normalize_payload( array $raw ) {
		$install_id = isset( $raw['install_id'] ) ? strtolower( trim( (string) $raw['install_id'] ) ) : '';
		if ( ! self::is_valid_install_id( $install_id ) ) {
			return new WP_Error( 'his_bad_install_id', __( 'install_id نامعتبر است.', 'hesabix-install-stats' ), array( 'status' => 400 ) );
		}

		$event = isset( $raw['event'] ) ? strtolower( trim( (string) $raw['event'] ) ) : '';
		if ( ! in_array( $event, self::allowed_events(), true ) ) {
			return new WP_Error( 'his_bad_event', __( 'event نامعتبر است.', 'hesabix-install-stats' ), array( 'status' => 400 ) );
		}

		$api_domain = self::sanitize_domain( isset( $raw['api_domain'] ) ? $raw['api_domain'] : '' );
		$ui_domain  = self::sanitize_domain( isset( $raw['ui_domain'] ) ? $raw['ui_domain'] : '' );
		if ( $api_domain === '' && $ui_domain === '' ) {
			return new WP_Error( 'his_bad_domain', __( 'حداقل یکی از api_domain یا ui_domain لازم است.', 'hesabix-install-stats' ), array( 'status' => 400 ) );
		}

		$bool = static function ( $v ) {
			if ( is_bool( $v ) ) {
				return $v ? 1 : 0;
			}
			$s = strtolower( trim( (string) $v ) );
			return in_array( $s, array( '1', 'true', 'yes', 'y', 'on' ), true ) ? 1 : 0;
		};

		$uint = static function ( $v, $max = 1000000 ) {
			$n = (int) $v;
			if ( $n < 0 ) {
				$n = 0;
			}
			if ( $n > $max ) {
				$n = $max;
			}
			return $n;
		};

		$str = static function ( $v, $max = 255 ) {
			$s = sanitize_text_field( (string) $v );
			if ( function_exists( 'mb_substr' ) ) {
				return mb_substr( $s, 0, $max );
			}
			return substr( $s, 0, $max );
		};

		$reported_ip = '';
		if ( ! empty( $raw['reported_ip'] ) ) {
			$candidate = trim( (string) $raw['reported_ip'] );
			if ( filter_var( $candidate, FILTER_VALIDATE_IP ) ) {
				$reported_ip = $candidate;
			}
		}

		$schema_version = isset( $raw['schema_version'] ) ? $uint( $raw['schema_version'], 100 ) : 1;

		$meta = array(
			'schema_version' => $schema_version,
			'script'         => $str( isset( $raw['script'] ) ? $raw['script'] : '', 64 ),
			'hostname'       => $str( isset( $raw['hostname'] ) ? $raw['hostname'] : '', 128 ),
		);
		if ( ! empty( $raw['extra'] ) && is_array( $raw['extra'] ) ) {
			// فقط کلیدهای کوتاه و مقادیر اسکالر برای جلوگیری از abuse.
			$extra = array();
			$count = 0;
			foreach ( $raw['extra'] as $k => $v ) {
				if ( $count >= 20 ) {
					break;
				}
				if ( ! is_string( $k ) || ! is_scalar( $v ) ) {
					continue;
				}
				$key = sanitize_key( $k );
				if ( $key === '' || strlen( $key ) > 40 ) {
					continue;
				}
				$extra[ $key ] = $str( $v, 200 );
				++$count;
			}
			if ( $extra ) {
				$meta['extra'] = $extra;
			}
		}

		return array(
			'install_id'       => $install_id,
			'event'            => $event,
			'api_domain'       => $api_domain,
			'ui_domain'        => $ui_domain,
			'reported_ip'      => $reported_ip,
			'ram_mb'           => $uint( isset( $raw['ram_mb'] ) ? $raw['ram_mb'] : 0, 2000000 ),
			'cpu_cores'        => $uint( isset( $raw['cpu_cores'] ) ? $raw['cpu_cores'] : 0, 1024 ),
			'disk_free_gb'     => $uint( isset( $raw['disk_free_gb'] ) ? $raw['disk_free_gb'] : 0, 1000000 ),
			'arch'             => $str( isset( $raw['arch'] ) ? $raw['arch'] : '', 32 ),
			'os_id'            => $str( isset( $raw['os_id'] ) ? $raw['os_id'] : '', 64 ),
			'os_version'       => $str( isset( $raw['os_version'] ) ? $raw['os_version'] : '', 128 ),
			'branch'           => $str( isset( $raw['branch'] ) ? $raw['branch'] : '', 128 ),
			'git_commit'       => $str( isset( $raw['git_commit'] ) ? $raw['git_commit'] : '', 64 ),
			'app_version'      => $str( isset( $raw['app_version'] ) ? $raw['app_version'] : '', 64 ),
			'uvicorn_workers'  => $uint( isset( $raw['uvicorn_workers'] ) ? $raw['uvicorn_workers'] : 0, 10000 ),
			'ssl_api'          => $bool( isset( $raw['ssl_api'] ) ? $raw['ssl_api'] : 0 ),
			'ssl_ui'           => $bool( isset( $raw['ssl_ui'] ) ? $raw['ssl_ui'] : 0 ),
			'install_pgadmin'  => $bool( isset( $raw['install_pgadmin'] ) ? $raw['install_pgadmin'] : 0 ),
			'install_voice'    => $bool( isset( $raw['install_voice'] ) ? $raw['install_voice'] : 0 ),
			'pip_mirror'       => $str( isset( $raw['pip_mirror'] ) ? $raw['pip_mirror'] : '', 64 ),
			'flutter_mirror'   => $str( isset( $raw['flutter_mirror'] ) ? $raw['flutter_mirror'] : '', 64 ),
			'meta'             => $meta,
		);
	}

	/**
	 * ثبت رویداد و به‌روزرسانی نمونه.
	 *
	 * @param array  $data دادهٔ نرمال‌شده.
	 * @param string $remote_ip IP درخواست‌کننده.
	 * @return array|\WP_Error
	 */
	public static function ingest( array $data, $remote_ip ) {
		global $wpdb;

		$now        = current_time( 'mysql', true );
		$remote_ip  = sanitize_text_field( (string) $remote_ip );
		$meta_json  = wp_json_encode( $data['meta'] );
		$table_i    = self::instances_table();
		$table_e    = self::events_table();

		$existing = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT id, event_count FROM {$table_i} WHERE install_id = %s LIMIT 1",
				$data['install_id']
			),
			ARRAY_A
		);

		$common = array(
			'api_domain'      => $data['api_domain'],
			'ui_domain'       => $data['ui_domain'],
			'remote_ip'       => $remote_ip,
			'reported_ip'     => $data['reported_ip'],
			'ram_mb'          => $data['ram_mb'],
			'cpu_cores'       => $data['cpu_cores'],
			'disk_free_gb'    => $data['disk_free_gb'],
			'arch'            => $data['arch'],
			'os_id'           => $data['os_id'],
			'os_version'      => $data['os_version'],
			'branch'          => $data['branch'],
			'git_commit'      => $data['git_commit'],
			'app_version'     => $data['app_version'],
			'uvicorn_workers' => $data['uvicorn_workers'],
			'ssl_api'         => $data['ssl_api'],
			'ssl_ui'          => $data['ssl_ui'],
			'install_pgadmin' => $data['install_pgadmin'],
			'install_voice'   => $data['install_voice'],
			'pip_mirror'      => $data['pip_mirror'],
			'flutter_mirror'  => $data['flutter_mirror'],
			'last_seen'       => $now,
			'last_event'      => $data['event'],
			'meta_json'       => $meta_json,
		);

		$common_formats = array(
			'%s', '%s', '%s', '%s',
			'%d', '%d', '%d', '%s', '%s', '%s',
			'%s', '%s', '%s', '%d',
			'%d', '%d', '%d', '%d',
			'%s', '%s',
			'%s', '%s', '%s',
		);

		if ( $existing ) {
			$common['event_count'] = (int) $existing['event_count'] + 1;
			$common_formats[]      = '%d';
			$updated               = $wpdb->update(
				$table_i,
				$common,
				array( 'id' => (int) $existing['id'] ),
				$common_formats,
				array( '%d' )
			);
			if ( false === $updated ) {
				return new WP_Error( 'his_db_update', __( 'خطا در به‌روزرسانی نمونه.', 'hesabix-install-stats' ), array( 'status' => 500 ) );
			}
			$is_new = false;
		} else {
			$insert_row = array_merge(
				array( 'install_id' => $data['install_id'] ),
				$common,
				array(
					'first_seen'  => $now,
					'event_count' => 1,
				)
			);
			$inserted = $wpdb->insert(
				$table_i,
				$insert_row,
				array_merge( array( '%s' ), $common_formats, array( '%s', '%d' ) )
			);
			if ( false === $inserted ) {
				return new WP_Error( 'his_db_insert', __( 'خطا در ثبت نمونه.', 'hesabix-install-stats' ), array( 'status' => 500 ) );
			}
			$is_new = true;
		}

		$payload_for_log = $data;
		unset( $payload_for_log['meta'] );
		$payload_for_log['meta'] = $data['meta'];

		$ev = $wpdb->insert(
			$table_e,
			array(
				'install_id'   => $data['install_id'],
				'event'        => $data['event'],
				'remote_ip'    => $remote_ip,
				'payload_json' => wp_json_encode( $payload_for_log ),
				'created_at'   => $now,
			),
			array( '%s', '%s', '%s', '%s', '%s' )
		);
		if ( false === $ev ) {
			return new WP_Error( 'his_db_event', __( 'خطا در ثبت رویداد.', 'hesabix-install-stats' ), array( 'status' => 500 ) );
		}

		self::maybe_prune_old_events();

		return array(
			'ok'         => true,
			'install_id' => $data['install_id'],
			'is_new'     => $is_new,
			'event'      => $data['event'],
		);
	}

	/**
	 * حذف رویدادهای قدیمی‌تر از retention (نمونه‌ها نگه داشته می‌شوند).
	 */
	public static function maybe_prune_old_events() {
		// حدوداً هر ۱۰۰ ingest یک‌بار.
		if ( wp_rand( 1, 100 ) !== 1 ) {
			return;
		}
		$days = (int) get_option( 'his_retention_days', 730 );
		if ( $days < 30 ) {
			$days = 30;
		}
		global $wpdb;
		$table = self::events_table();
		$wpdb->query(
			$wpdb->prepare(
				"DELETE FROM {$table} WHERE created_at < (UTC_TIMESTAMP() - INTERVAL %d DAY)",
				$days
			)
		);
	}

	/**
	 * یک نمونه بر اساس install_id.
	 *
	 * @param string $install_id شناسه.
	 * @return array|null
	 */
	public static function get_instance( $install_id ) {
		global $wpdb;
		$table = self::instances_table();
		$row   = $wpdb->get_row(
			$wpdb->prepare( "SELECT * FROM {$table} WHERE install_id = %s LIMIT 1", $install_id ),
			ARRAY_A
		);
		return $row ? $row : null;
	}

	/**
	 * رویدادهای یک نمونه.
	 *
	 * @param string $install_id شناسه.
	 * @param int    $limit حد.
	 * @return array
	 */
	public static function get_instance_events( $install_id, $limit = 50 ) {
		global $wpdb;
		$table = self::events_table();
		$limit = max( 1, min( 200, (int) $limit ) );
		return $wpdb->get_results(
			$wpdb->prepare(
				"SELECT * FROM {$table} WHERE install_id = %s ORDER BY created_at DESC LIMIT %d",
				$install_id,
				$limit
			),
			ARRAY_A
		);
	}
}
