<?php
/**
 * کوئری‌های آماری برای داشبورد و خروجی.
 *
 * @package Hesabix_Install_Stats
 */

defined( 'ABSPATH' ) || exit;

/**
 * Reports.
 */
final class HIS_Reports {

	/**
	 * خلاصهٔ داشبورد.
	 *
	 * @return array
	 */
	public static function dashboard_summary() {
		global $wpdb;
		$t = HIS_Storage::instances_table();
		$e = HIS_Storage::events_table();

		$total = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t}" );

		$active_7  = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t} WHERE last_seen >= (UTC_TIMESTAMP() - INTERVAL 7 DAY)" );
		$active_30 = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t} WHERE last_seen >= (UTC_TIMESTAMP() - INTERVAL 30 DAY)" );
		$silent_90 = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t} WHERE last_seen < (UTC_TIMESTAMP() - INTERVAL 90 DAY)" );

		$installs_today = (int) $wpdb->get_var(
			"SELECT COUNT(*) FROM {$e} WHERE event = 'install' AND created_at >= UTC_DATE()"
		);
		$installs_7 = (int) $wpdb->get_var(
			"SELECT COUNT(*) FROM {$e} WHERE event = 'install' AND created_at >= (UTC_TIMESTAMP() - INTERVAL 7 DAY)"
		);
		$installs_30 = (int) $wpdb->get_var(
			"SELECT COUNT(*) FROM {$e} WHERE event = 'install' AND created_at >= (UTC_TIMESTAMP() - INTERVAL 30 DAY)"
		);
		$updates_30 = (int) $wpdb->get_var(
			"SELECT COUNT(*) FROM {$e} WHERE event = 'update' AND created_at >= (UTC_TIMESTAMP() - INTERVAL 30 DAY)"
		);

		$ssl_api = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t} WHERE ssl_api = 1" );
		$ssl_ui  = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t} WHERE ssl_ui = 1" );
		$voice   = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t} WHERE install_voice = 1" );
		$pgadmin = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t} WHERE install_pgadmin = 1" );

		$avg_ram = (float) $wpdb->get_var( "SELECT AVG(ram_mb) FROM {$t} WHERE ram_mb > 0" );
		$avg_cpu = (float) $wpdb->get_var( "SELECT AVG(cpu_cores) FROM {$t} WHERE cpu_cores > 0" );

		return array(
			'total_instances'   => $total,
			'active_7d'         => $active_7,
			'active_30d'        => $active_30,
			'silent_90d'        => $silent_90,
			'installs_today'    => $installs_today,
			'installs_7d'       => $installs_7,
			'installs_30d'      => $installs_30,
			'updates_30d'       => $updates_30,
			'ssl_api_count'     => $ssl_api,
			'ssl_ui_count'      => $ssl_ui,
			'voice_count'       => $voice,
			'pgadmin_count'     => $pgadmin,
			'avg_ram_mb'        => round( $avg_ram, 1 ),
			'avg_cpu_cores'     => round( $avg_cpu, 2 ),
		);
	}

	/**
	 * روند رویدادها به‌ازای روز.
	 *
	 * @param int    $days تعداد روز.
	 * @param string $event فیلتر رویداد (خالی = همه).
	 * @return array
	 */
	public static function events_by_day( $days = 30, $event = '' ) {
		global $wpdb;
		$e    = HIS_Storage::events_table();
		$days = max( 1, min( 366, (int) $days ) );

		if ( $event !== '' && in_array( $event, HIS_Storage::allowed_events(), true ) ) {
			$sql = $wpdb->prepare(
				"SELECT DATE(created_at) AS d, COUNT(*) AS c
				 FROM {$e}
				 WHERE event = %s AND created_at >= (UTC_TIMESTAMP() - INTERVAL %d DAY)
				 GROUP BY DATE(created_at)
				 ORDER BY d ASC",
				$event,
				$days
			);
		} else {
			$sql = $wpdb->prepare(
				"SELECT DATE(created_at) AS d, COUNT(*) AS c
				 FROM {$e}
				 WHERE created_at >= (UTC_TIMESTAMP() - INTERVAL %d DAY)
				 GROUP BY DATE(created_at)
				 ORDER BY d ASC",
				$days
			);
		}

		$rows = $wpdb->get_results( $sql, ARRAY_A );
		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * توزیع یک ستون گسسته.
	 *
	 * @param string $column نام ستون امن.
	 * @param int    $limit حد.
	 * @return array
	 */
	public static function distribution( $column, $limit = 20 ) {
		$allowed = array(
			'os_id',
			'os_version',
			'arch',
			'branch',
			'app_version',
			'pip_mirror',
			'flutter_mirror',
			'last_event',
		);
		if ( ! in_array( $column, $allowed, true ) ) {
			return array();
		}
		global $wpdb;
		$t     = HIS_Storage::instances_table();
		$limit = max( 1, min( 100, (int) $limit ) );
		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- column whitelist بالا.
		$sql = $wpdb->prepare(
			"SELECT {$column} AS label, COUNT(*) AS c
			 FROM {$t}
			 GROUP BY {$column}
			 ORDER BY c DESC
			 LIMIT %d",
			$limit
		);
		$rows = $wpdb->get_results( $sql, ARRAY_A );
		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * سطل‌بندی RAM.
	 *
	 * @return array
	 */
	public static function ram_buckets() {
		global $wpdb;
		$t = HIS_Storage::instances_table();
		$sql = "SELECT
			SUM(CASE WHEN ram_mb > 0 AND ram_mb < 4096 THEN 1 ELSE 0 END) AS b_lt4,
			SUM(CASE WHEN ram_mb >= 4096 AND ram_mb < 8192 THEN 1 ELSE 0 END) AS b_4_8,
			SUM(CASE WHEN ram_mb >= 8192 AND ram_mb < 16384 THEN 1 ELSE 0 END) AS b_8_16,
			SUM(CASE WHEN ram_mb >= 16384 AND ram_mb < 32768 THEN 1 ELSE 0 END) AS b_16_32,
			SUM(CASE WHEN ram_mb >= 32768 THEN 1 ELSE 0 END) AS b_ge32,
			SUM(CASE WHEN ram_mb = 0 THEN 1 ELSE 0 END) AS b_unknown
			FROM {$t}";
		$row = $wpdb->get_row( $sql, ARRAY_A );
		if ( ! $row ) {
			return array();
		}
		return array(
			array( 'label' => '< 4 GB', 'c' => (int) $row['b_lt4'] ),
			array( 'label' => '4–8 GB', 'c' => (int) $row['b_4_8'] ),
			array( 'label' => '8–16 GB', 'c' => (int) $row['b_8_16'] ),
			array( 'label' => '16–32 GB', 'c' => (int) $row['b_16_32'] ),
			array( 'label' => '≥ 32 GB', 'c' => (int) $row['b_ge32'] ),
			array( 'label' => 'نامشخص', 'c' => (int) $row['b_unknown'] ),
		);
	}

	/**
	 * سطل‌بندی CPU.
	 *
	 * @return array
	 */
	public static function cpu_buckets() {
		global $wpdb;
		$t = HIS_Storage::instances_table();
		$sql = "SELECT
			SUM(CASE WHEN cpu_cores = 1 THEN 1 ELSE 0 END) AS c1,
			SUM(CASE WHEN cpu_cores = 2 THEN 1 ELSE 0 END) AS c2,
			SUM(CASE WHEN cpu_cores BETWEEN 3 AND 4 THEN 1 ELSE 0 END) AS c3_4,
			SUM(CASE WHEN cpu_cores BETWEEN 5 AND 8 THEN 1 ELSE 0 END) AS c5_8,
			SUM(CASE WHEN cpu_cores > 8 THEN 1 ELSE 0 END) AS c_gt8,
			SUM(CASE WHEN cpu_cores = 0 THEN 1 ELSE 0 END) AS c_unknown
			FROM {$t}";
		$row = $wpdb->get_row( $sql, ARRAY_A );
		if ( ! $row ) {
			return array();
		}
		return array(
			array( 'label' => '1', 'c' => (int) $row['c1'] ),
			array( 'label' => '2', 'c' => (int) $row['c2'] ),
			array( 'label' => '3–4', 'c' => (int) $row['c3_4'] ),
			array( 'label' => '5–8', 'c' => (int) $row['c5_8'] ),
			array( 'label' => '> 8', 'c' => (int) $row['c_gt8'] ),
			array( 'label' => 'نامشخص', 'c' => (int) $row['c_unknown'] ),
		);
	}

	/**
	 * لیست نمونه‌ها با فیلتر.
	 *
	 * @param array $args آرگومان‌ها.
	 * @return array{items: array, total: int}
	 */
	public static function list_instances( array $args ) {
		global $wpdb;
		$t = HIS_Storage::instances_table();

		$page     = max( 1, (int) ( $args['page'] ?? 1 ) );
		$per_page = max( 1, min( 100, (int) ( $args['per_page'] ?? 20 ) ) );
		$offset   = ( $page - 1 ) * $per_page;
		$search   = isset( $args['s'] ) ? trim( (string) $args['s'] ) : '';
		$active   = isset( $args['active'] ) ? (string) $args['active'] : '';

		$where  = array( '1=1' );
		$params = array();

		if ( $search !== '' ) {
			$like     = '%' . $wpdb->esc_like( $search ) . '%';
			$where[]  = '(install_id LIKE %s OR api_domain LIKE %s OR ui_domain LIKE %s OR remote_ip LIKE %s OR os_id LIKE %s OR branch LIKE %s)';
			$params[] = $like;
			$params[] = $like;
			$params[] = $like;
			$params[] = $like;
			$params[] = $like;
			$params[] = $like;
		}

		if ( $active === '7' ) {
			$where[] = 'last_seen >= (UTC_TIMESTAMP() - INTERVAL 7 DAY)';
		} elseif ( $active === '30' ) {
			$where[] = 'last_seen >= (UTC_TIMESTAMP() - INTERVAL 30 DAY)';
		} elseif ( $active === 'silent90' ) {
			$where[] = 'last_seen < (UTC_TIMESTAMP() - INTERVAL 90 DAY)';
		}

		$where_sql = implode( ' AND ', $where );

		if ( $params ) {
			$count_sql = "SELECT COUNT(*) FROM {$t} WHERE {$where_sql}";
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			$total = (int) $wpdb->get_var( $wpdb->prepare( $count_sql, ...$params ) );
			$list_sql = "SELECT * FROM {$t} WHERE {$where_sql} ORDER BY last_seen DESC LIMIT %d OFFSET %d";
			$all_args = array_merge( $params, array( $per_page, $offset ) );
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			$query = $wpdb->prepare( $list_sql, ...$all_args );
		} else {
			$total = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$t} WHERE {$where_sql}" );
			$query = $wpdb->prepare(
				"SELECT * FROM {$t} WHERE {$where_sql} ORDER BY last_seen DESC LIMIT %d OFFSET %d",
				$per_page,
				$offset
			);
		}

		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$items = $wpdb->get_results( $query, ARRAY_A );
		return array(
			'items' => is_array( $items ) ? $items : array(),
			'total' => $total,
		);
	}

	/**
	 * داده‌های CSV همهٔ نمونه‌ها.
	 *
	 * @return array
	 */
	public static function export_instances_rows() {
		global $wpdb;
		$t = HIS_Storage::instances_table();
		$rows = $wpdb->get_results( "SELECT * FROM {$t} ORDER BY last_seen DESC", ARRAY_A );
		return is_array( $rows ) ? $rows : array();
	}

	/**
	 * لیست دامنه‌ها (API و UI) برای پنل ادمین.
	 *
	 * هر ردیف یک دامنه است؛ اگر API و UI یکسان باشند دو نقش جدا یا یک ردیف با نقش both.
	 *
	 * @param array $args آرگومان‌ها: page, per_page, s, role (api|ui|), active (7|30|silent90|).
	 * @return array{items: array, total: int, unique_domains: int, api_count: int, ui_count: int}
	 */
	public static function list_domains( array $args ) {
		global $wpdb;
		$t = HIS_Storage::instances_table();

		$page     = max( 1, (int) ( $args['page'] ?? 1 ) );
		$per_page = max( 1, min( 200, (int) ( $args['per_page'] ?? 50 ) ) );
		$search   = isset( $args['s'] ) ? trim( (string) $args['s'] ) : '';
		$role     = isset( $args['role'] ) ? (string) $args['role'] : '';
		$active   = isset( $args['active'] ) ? (string) $args['active'] : '';

		$where  = array( '1=1' );
		$params = array();

		if ( $search !== '' ) {
			$like     = '%' . $wpdb->esc_like( $search ) . '%';
			$where[]  = '(api_domain LIKE %s OR ui_domain LIKE %s OR remote_ip LIKE %s OR reported_ip LIKE %s OR install_id LIKE %s)';
			$params[] = $like;
			$params[] = $like;
			$params[] = $like;
			$params[] = $like;
			$params[] = $like;
		}

		if ( $active === '7' ) {
			$where[] = 'last_seen >= (UTC_TIMESTAMP() - INTERVAL 7 DAY)';
		} elseif ( $active === '30' ) {
			$where[] = 'last_seen >= (UTC_TIMESTAMP() - INTERVAL 30 DAY)';
		} elseif ( $active === 'silent90' ) {
			$where[] = 'last_seen < (UTC_TIMESTAMP() - INTERVAL 90 DAY)';
		}

		$where_sql = implode( ' AND ', $where );

		if ( $params ) {
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			$rows = $wpdb->get_results( $wpdb->prepare( "SELECT * FROM {$t} WHERE {$where_sql} ORDER BY last_seen DESC", ...$params ), ARRAY_A );
		} else {
			$rows = $wpdb->get_results( "SELECT * FROM {$t} WHERE {$where_sql} ORDER BY last_seen DESC", ARRAY_A );
		}
		if ( ! is_array( $rows ) ) {
			$rows = array();
		}

		$flat = array();
		$unique_set = array();
		$api_count  = 0;
		$ui_count   = 0;

		foreach ( $rows as $row ) {
			$api = trim( (string) ( $row['api_domain'] ?? '' ) );
			$ui  = trim( (string) ( $row['ui_domain'] ?? '' ) );

			if ( $api !== '' ) {
				++$api_count;
				$unique_set[ strtolower( $api ) ] = true;
				$flat[] = array(
					'domain'      => $api,
					'role'        => 'api',
					'ssl'         => (int) ( $row['ssl_api'] ?? 0 ),
					'install_id'  => $row['install_id'],
					'pair_domain' => $ui,
					'remote_ip'   => $row['remote_ip'],
					'reported_ip' => $row['reported_ip'],
					'last_seen'   => $row['last_seen'],
					'first_seen'  => $row['first_seen'],
					'last_event'  => $row['last_event'],
					'os_id'       => $row['os_id'],
					'branch'      => $row['branch'],
				);
			}
			if ( $ui !== '' ) {
				++$ui_count;
				$unique_set[ strtolower( $ui ) ] = true;
				$flat[] = array(
					'domain'      => $ui,
					'role'        => 'ui',
					'ssl'         => (int) ( $row['ssl_ui'] ?? 0 ),
					'install_id'  => $row['install_id'],
					'pair_domain' => $api,
					'remote_ip'   => $row['remote_ip'],
					'reported_ip' => $row['reported_ip'],
					'last_seen'   => $row['last_seen'],
					'first_seen'  => $row['first_seen'],
					'last_event'  => $row['last_event'],
					'os_id'       => $row['os_id'],
					'branch'      => $row['branch'],
				);
			}
		}

		if ( $role === 'api' || $role === 'ui' ) {
			$flat = array_values(
				array_filter(
					$flat,
					static function ( $item ) use ( $role ) {
						return $item['role'] === $role;
					}
				)
			);
		}

		$total  = count( $flat );
		$offset = ( $page - 1 ) * $per_page;
		$items  = array_slice( $flat, $offset, $per_page );

		return array(
			'items'          => $items,
			'total'          => $total,
			'unique_domains' => count( $unique_set ),
			'api_count'      => $api_count,
			'ui_count'       => $ui_count,
		);
	}

	/**
	 * خروجی CSV دامنه‌ها.
	 *
	 * @return array
	 */
	public static function export_domains_rows() {
		$result = self::list_domains(
			array(
				'page'     => 1,
				'per_page' => 100000,
			)
		);
		return $result['items'];
	}
}
