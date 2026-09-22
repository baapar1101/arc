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

// Only delete data if user confirms (تنظیمات → سایر)
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

	// Sync meta (سفارش/محصول) — نه فیلدهای billing مشتری
	$meta_keys = array(
		'_hesabix_v2_pause_auto_sync',
		'_hesabix_v2_invoice_rp_sync_fp',
		'_hesabix_v2_order_system_note_id',
		'_hesabix_v2_invoice_sync_error_note_id',
		'_hesabix_v2_last_pushed_stock_qty',
		'_hesabix_v2_invoice_profit',
		'_hesabix_v2_invoice_profit_percent',
		'_hesabix_v2_invoice_gross_profit',
		'_hesabix_v2_invoice_net_profit',
		'_hesabix_v2_invoice_profit_at',
		'_hesabix_v2_invoice_profit_invoice_id',
		'_hesabix_v2_invoice_total_cost',
		'_hesabix_v2_invoice_total_sales',
		'_hesabix_v2_invoice_profit_currency',
		'_hesabix_v2_invoice_profit_currency_title',
	);
	$placeholders = implode(',', array_fill(0, count($meta_keys), '%s'));
	// phpcs:ignore WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare
	$wpdb->query($wpdb->prepare("DELETE FROM {$wpdb->postmeta} WHERE meta_key IN ($placeholders)", ...$meta_keys));
	$orders_meta = $wpdb->prefix . 'wc_orders_meta';
	// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
	if ($wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s', $orders_meta)) === $orders_meta) {
		// phpcs:ignore WordPress.DB.PreparedSQLPlaceholders.UnfinishedPrepare
		$wpdb->query($wpdb->prepare("DELETE FROM {$orders_meta} WHERE meta_key IN ($placeholders)", ...$meta_keys));
	}

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
	wp_clear_scheduled_hook('hesabix_v2_pull_stock_cron');
}

