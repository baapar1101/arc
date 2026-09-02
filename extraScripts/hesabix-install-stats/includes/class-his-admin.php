<?php
/**
 * پنل ادمین: داشبورد، نمونه‌ها، تنظیمات، خروجی CSV.
 *
 * @package Hesabix_Install_Stats
 */

defined( 'ABSPATH' ) || exit;

/**
 * Admin UI.
 */
final class HIS_Admin {

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
		add_action( 'admin_menu', array( $this, 'register_menu' ) );
		add_action( 'admin_init', array( $this, 'handle_actions' ) );
		add_action( 'admin_enqueue_scripts', array( $this, 'enqueue' ) );
	}

	/**
	 * منو.
	 */
	public function register_menu() {
		add_menu_page(
			__( 'آمار نصب Hesabix', 'hesabix-install-stats' ),
			__( 'آمار نصب', 'hesabix-install-stats' ),
			'manage_options',
			'hesabix-install-stats',
			array( $this, 'render_dashboard' ),
			'dashicons-chart-area',
			58
		);

		add_submenu_page(
			'hesabix-install-stats',
			__( 'داشبورد', 'hesabix-install-stats' ),
			__( 'داشبورد', 'hesabix-install-stats' ),
			'manage_options',
			'hesabix-install-stats',
			array( $this, 'render_dashboard' )
		);

		add_submenu_page(
			'hesabix-install-stats',
			__( 'نمونه‌ها', 'hesabix-install-stats' ),
			__( 'نمونه‌ها', 'hesabix-install-stats' ),
			'manage_options',
			'hesabix-install-stats-instances',
			array( $this, 'render_instances' )
		);

		add_submenu_page(
			'hesabix-install-stats',
			__( 'دامنه‌ها', 'hesabix-install-stats' ),
			__( 'دامنه‌ها', 'hesabix-install-stats' ),
			'manage_options',
			'hesabix-install-stats-domains',
			array( $this, 'render_domains' )
		);

		add_submenu_page(
			'hesabix-install-stats',
			__( 'تنظیمات', 'hesabix-install-stats' ),
			__( 'تنظیمات', 'hesabix-install-stats' ),
			'manage_options',
			'hesabix-install-stats-settings',
			array( $this, 'render_settings' )
		);
	}

	/**
	 * استایل ادمین.
	 *
	 * @param string $hook صفحه.
	 */
	public function enqueue( $hook ) {
		if ( strpos( (string) $hook, 'hesabix-install-stats' ) === false ) {
			return;
		}
		wp_enqueue_style(
			'his-admin',
			HIS_PLUGIN_URL . 'admin/css/admin.css',
			array(),
			HIS_VERSION
		);
	}

	/**
	 * اکشن‌های POST/GET (ذخیره تنظیمات، CSV).
	 */
	public function handle_actions() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}

		if ( isset( $_GET['his_export'] ) && $_GET['his_export'] === 'csv' ) {
			check_admin_referer( 'his_export_csv' );
			$this->export_csv();
			exit;
		}

		if ( isset( $_GET['his_export'] ) && $_GET['his_export'] === 'domains_csv' ) {
			check_admin_referer( 'his_export_domains_csv' );
			$this->export_domains_csv();
			exit;
		}

		if ( isset( $_POST['his_save_settings'] ) ) {
			check_admin_referer( 'his_save_settings' );
			$token = isset( $_POST['his_ingest_token'] ) ? sanitize_text_field( wp_unslash( (string) $_POST['his_ingest_token'] ) ) : '';
			$days  = isset( $_POST['his_retention_days'] ) ? (int) $_POST['his_retention_days'] : 730;
			if ( $days < 30 ) {
				$days = 30;
			}
			if ( $days > 3650 ) {
				$days = 3650;
			}
			update_option( 'his_ingest_token', $token, false );
			update_option( 'his_retention_days', $days, false );
			wp_safe_redirect(
				add_query_arg(
					array(
						'page'    => 'hesabix-install-stats-settings',
						'updated' => '1',
					),
					admin_url( 'admin.php' )
				)
			);
			exit;
		}
	}

	/**
	 * خروجی CSV.
	 */
	private function export_csv() {
		$rows = HIS_Reports::export_instances_rows();
		nocache_headers();
		header( 'Content-Type: text/csv; charset=utf-8' );
		header( 'Content-Disposition: attachment; filename=hesabix-install-instances-' . gmdate( 'Ymd-His' ) . '.csv' );

		$out = fopen( 'php://output', 'w' );
		if ( false === $out ) {
			return;
		}
		// BOM for Excel.
		fwrite( $out, "\xEF\xBB\xBF" );

		$headers = array(
			'install_id', 'api_domain', 'ui_domain', 'remote_ip', 'reported_ip',
			'ram_mb', 'cpu_cores', 'disk_free_gb', 'arch', 'os_id', 'os_version',
			'branch', 'git_commit', 'app_version', 'uvicorn_workers',
			'ssl_api', 'ssl_ui', 'install_pgadmin', 'install_voice',
			'pip_mirror', 'flutter_mirror', 'first_seen', 'last_seen', 'last_event', 'event_count',
		);
		fputcsv( $out, $headers );
		foreach ( $rows as $row ) {
			$line = array();
			foreach ( $headers as $h ) {
				$line[] = isset( $row[ $h ] ) ? $row[ $h ] : '';
			}
			fputcsv( $out, $line );
		}
		fclose( $out );
	}

	/**
	 * خروجی CSV دامنه‌ها.
	 */
	private function export_domains_csv() {
		$rows = HIS_Reports::export_domains_rows();
		nocache_headers();
		header( 'Content-Type: text/csv; charset=utf-8' );
		header( 'Content-Disposition: attachment; filename=hesabix-install-domains-' . gmdate( 'Ymd-His' ) . '.csv' );

		$out = fopen( 'php://output', 'w' );
		if ( false === $out ) {
			return;
		}
		fwrite( $out, "\xEF\xBB\xBF" );

		$headers = array(
			'domain', 'role', 'ssl', 'pair_domain', 'remote_ip', 'reported_ip',
			'install_id', 'first_seen', 'last_seen', 'last_event', 'os_id', 'branch',
		);
		fputcsv( $out, $headers );
		foreach ( $rows as $row ) {
			$line = array();
			foreach ( $headers as $h ) {
				$line[] = isset( $row[ $h ] ) ? $row[ $h ] : '';
			}
			fputcsv( $out, $line );
		}
		fclose( $out );
	}

	/**
	 * داشبورد.
	 */
	public function render_dashboard() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		$summary      = HIS_Reports::dashboard_summary();
		$by_day       = HIS_Reports::events_by_day( 30 );
		$installs_day = HIS_Reports::events_by_day( 30, 'install' );
		$os           = HIS_Reports::distribution( 'os_id' );
		$branch       = HIS_Reports::distribution( 'branch' );
		$pip          = HIS_Reports::distribution( 'pip_mirror' );
		$flutter      = HIS_Reports::distribution( 'flutter_mirror' );
		$arch         = HIS_Reports::distribution( 'arch' );
		$ram          = HIS_Reports::ram_buckets();
		$cpu          = HIS_Reports::cpu_buckets();
		$app_ver      = HIS_Reports::distribution( 'app_version' );

		include HIS_PLUGIN_DIR . 'admin/views/dashboard.php';
	}

	/**
	 * لیست / جزئیات نمونه‌ها.
	 */
	public function render_instances() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}

		$install_id = isset( $_GET['install_id'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['install_id'] ) ) : '';
		if ( $install_id !== '' && HIS_Storage::is_valid_install_id( $install_id ) ) {
			$instance = HIS_Storage::get_instance( $install_id );
			$events   = HIS_Storage::get_instance_events( $install_id, 100 );
			include HIS_PLUGIN_DIR . 'admin/views/instance-detail.php';
			return;
		}

		$page   = isset( $_GET['paged'] ) ? max( 1, (int) $_GET['paged'] ) : 1;
		$search = isset( $_GET['s'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['s'] ) ) : '';
		$active = isset( $_GET['active'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['active'] ) ) : '';
		$result = HIS_Reports::list_instances(
			array(
				'page'     => $page,
				'per_page' => 25,
				's'        => $search,
				'active'   => $active,
			)
		);
		include HIS_PLUGIN_DIR . 'admin/views/instances.php';
	}

	/**
	 * لیست دامنه‌ها.
	 */
	public function render_domains() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}

		$page   = isset( $_GET['paged'] ) ? max( 1, (int) $_GET['paged'] ) : 1;
		$search = isset( $_GET['s'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['s'] ) ) : '';
		$role   = isset( $_GET['role'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['role'] ) ) : '';
		$active = isset( $_GET['active'] ) ? sanitize_text_field( wp_unslash( (string) $_GET['active'] ) ) : '';

		if ( ! in_array( $role, array( '', 'api', 'ui' ), true ) ) {
			$role = '';
		}

		$result = HIS_Reports::list_domains(
			array(
				'page'     => $page,
				'per_page' => 50,
				's'        => $search,
				'role'     => $role,
				'active'   => $active,
			)
		);
		include HIS_PLUGIN_DIR . 'admin/views/domains.php';
	}

	/**
	 * تنظیمات.
	 */
	public function render_settings() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		$token = (string) get_option( 'his_ingest_token', HIS_DEFAULT_INGEST_TOKEN );
		$days  = (int) get_option( 'his_retention_days', 730 );
		$endpoint = esc_url_raw( rest_url( HIS_REST::NS . '/event' ) );
		include HIS_PLUGIN_DIR . 'admin/views/settings.php';
	}

	/**
	 * نوار نسبی ساده برای جداول توزیع.
	 *
	 * @param int $value مقدار.
	 * @param int $max حداکثر.
	 * @return string
	 */
	public static function bar_html( $value, $max ) {
		$value = (int) $value;
		$max   = max( 1, (int) $max );
		$pct   = min( 100, round( ( $value / $max ) * 100 ) );
		return '<span class="his-bar"><span class="his-bar__fill" style="width:' . esc_attr( (string) $pct ) . '%"></span></span>';
	}
}
