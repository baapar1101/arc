<?php
/**
 * Fired during plugin deactivation
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

class Hesabix_V2_Deactivator
{
	/**
	 * Deactivate the plugin
	 *
	 * @since    2.0.0
	 */
	public static function deactivate()
	{
		// Clear scheduled cron jobs
		$timestamp = wp_next_scheduled('hesabix_v2_process_queue');
		if ($timestamp) {
			wp_unschedule_event($timestamp, 'hesabix_v2_process_queue');
		}

		$timestamp = wp_next_scheduled('hesabix_v2_clean_old_logs');
		if ($timestamp) {
			wp_unschedule_event($timestamp, 'hesabix_v2_clean_old_logs');
		}

		// Note: We don't delete data on deactivation
		// Data will only be deleted if user chooses to uninstall
		
		// Flush rewrite rules
		flush_rewrite_rules();
	}
}

