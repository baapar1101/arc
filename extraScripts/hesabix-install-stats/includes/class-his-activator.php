<?php
/**
 * فعال‌سازی افزونه و ساخت جداول.
 *
 * @package Hesabix_Install_Stats
 */

defined( 'ABSPATH' ) || exit;

/**
 * Activator.
 */
final class HIS_Activator {

	/**
	 * ساخت/به‌روزرسانی جداول و گزینه‌های پیش‌فرض.
	 */
	public static function activate() {
		self::create_tables();
		if ( get_option( 'his_ingest_token', null ) === null ) {
			add_option( 'his_ingest_token', HIS_DEFAULT_INGEST_TOKEN, '', false );
		}
		if ( get_option( 'his_retention_days', null ) === null ) {
			add_option( 'his_retention_days', 730, '', false );
		}
		update_option( 'his_db_version', HIS_DB_VERSION, false );
	}

	/**
	 * dbDelta برای instances و events.
	 */
	public static function create_tables() {
		global $wpdb;

		require_once ABSPATH . 'wp-admin/includes/upgrade.php';

		$charset = $wpdb->get_charset_collate();
		$instances = HIS_Storage::instances_table();
		$events    = HIS_Storage::events_table();

		$sql_instances = "CREATE TABLE {$instances} (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			install_id char(36) NOT NULL,
			api_domain varchar(255) NOT NULL DEFAULT '',
			ui_domain varchar(255) NOT NULL DEFAULT '',
			remote_ip varchar(45) NOT NULL DEFAULT '',
			reported_ip varchar(45) NOT NULL DEFAULT '',
			ram_mb int(11) unsigned NOT NULL DEFAULT 0,
			cpu_cores int(11) unsigned NOT NULL DEFAULT 0,
			disk_free_gb int(11) unsigned NOT NULL DEFAULT 0,
			arch varchar(32) NOT NULL DEFAULT '',
			os_id varchar(64) NOT NULL DEFAULT '',
			os_version varchar(128) NOT NULL DEFAULT '',
			branch varchar(128) NOT NULL DEFAULT '',
			git_commit varchar(64) NOT NULL DEFAULT '',
			app_version varchar(64) NOT NULL DEFAULT '',
			uvicorn_workers int(11) unsigned NOT NULL DEFAULT 0,
			ssl_api tinyint(1) NOT NULL DEFAULT 0,
			ssl_ui tinyint(1) NOT NULL DEFAULT 0,
			install_pgadmin tinyint(1) NOT NULL DEFAULT 0,
			install_voice tinyint(1) NOT NULL DEFAULT 0,
			pip_mirror varchar(64) NOT NULL DEFAULT '',
			flutter_mirror varchar(64) NOT NULL DEFAULT '',
			first_seen datetime NOT NULL,
			last_seen datetime NOT NULL,
			last_event varchar(32) NOT NULL DEFAULT '',
			event_count int(11) unsigned NOT NULL DEFAULT 0,
			meta_json longtext NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY install_id (install_id),
			KEY last_seen (last_seen),
			KEY api_domain (api_domain(191)),
			KEY os_id (os_id),
			KEY branch (branch),
			KEY last_event (last_event)
		) {$charset};";

		$sql_events = "CREATE TABLE {$events} (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			install_id char(36) NOT NULL,
			event varchar(32) NOT NULL DEFAULT '',
			remote_ip varchar(45) NOT NULL DEFAULT '',
			payload_json longtext NULL,
			created_at datetime NOT NULL,
			PRIMARY KEY  (id),
			KEY install_id (install_id),
			KEY event_created (event, created_at),
			KEY created_at (created_at)
		) {$charset};";

		dbDelta( $sql_instances );
		dbDelta( $sql_events );
	}
}
