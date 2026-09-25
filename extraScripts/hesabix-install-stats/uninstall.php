<?php
/**
 * پاک‌سازی هنگام حذف افزونه.
 *
 * @package Hesabix_Install_Stats
 */

defined( 'WP_UNINSTALL_PLUGIN' ) || exit;

global $wpdb;

delete_option( 'his_ingest_token' );
delete_option( 'his_retention_days' );
delete_option( 'his_db_version' );

$instances = $wpdb->prefix . 'hesabix_install_instances';
$events    = $wpdb->prefix . 'hesabix_install_events';

// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
$wpdb->query( "DROP TABLE IF EXISTS {$events}" );
// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
$wpdb->query( "DROP TABLE IF EXISTS {$instances}" );
