<?php
/**
 * Fired when the plugin is uninstalled.
 *
 * @link       https://hesabix.ir
 * @since      2.0.0
 * @package    Hesabix_V2
 */

// If uninstall not called from WordPress, then exit.
if (!defined('WP_UNINSTALL_PLUGIN')) {
	exit;
}

// Only delete data if user confirms
$delete_data = get_option('hesabix_v2_delete_data_on_uninstall', false);

if ($delete_data) {
	global $wpdb;

	// Delete tables
	$wpdb->query("DROP TABLE IF EXISTS {$wpdb->prefix}hesabix_v2");
	$wpdb->query("DROP TABLE IF EXISTS {$wpdb->prefix}hesabix_v2_sync_log");
	$wpdb->query("DROP TABLE IF EXISTS {$wpdb->prefix}hesabix_v2_queue");

	// Delete options
	$wpdb->query("DELETE FROM {$wpdb->options} WHERE option_name LIKE 'hesabix_v2_%'");

	// Delete transients
	$wpdb->query("DELETE FROM {$wpdb->options} WHERE option_name LIKE '_transient_hesabix_v2_%'");
	$wpdb->query("DELETE FROM {$wpdb->options} WHERE option_name LIKE '_transient_timeout_hesabix_v2_%'");

	// Delete log files
	$upload_dir = wp_upload_dir();
	$log_dir = $upload_dir['basedir'] . '/hesabix-v2-logs';
	
	if (file_exists($log_dir)) {
		$files = glob($log_dir . '/*');
		foreach ($files as $file) {
			if (is_file($file)) {
				@unlink($file);
			}
		}
		@rmdir($log_dir);
	}

	// Clear scheduled crons
	wp_clear_scheduled_hook('hesabix_v2_process_queue');
	wp_clear_scheduled_hook('hesabix_v2_clean_old_logs');
}

