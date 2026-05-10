<?php
/**
 * Fired during plugin activation
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

class Hesabix_V2_Activator
{
	/**
	 * Activate the plugin
	 *
	 * @since    2.0.0
	 */
	public static function activate()
	{
		global $wpdb;
		$charset_collate = $wpdb->get_charset_collate();

		// Create main mapping table
		$table_name = $wpdb->prefix . 'hesabix_v2';
		$sql = "CREATE TABLE IF NOT EXISTS $table_name (
			id bigint(20) NOT NULL AUTO_INCREMENT,
			entity_type varchar(50) NOT NULL COMMENT 'product, customer, order, variation',
			wc_id bigint(20) NOT NULL COMMENT 'ID in WooCommerce',
			wc_parent_id bigint(20) DEFAULT NULL COMMENT 'Parent ID for variations',
			hesabix_id bigint(20) NOT NULL COMMENT 'ID in Hesabix',
			hesabix_type varchar(50) DEFAULT NULL COMMENT 'Type in Hesabix',
			business_id int(11) NOT NULL COMMENT 'Business ID',
			sync_status varchar(20) DEFAULT 'synced' COMMENT 'synced, pending, error',
			last_sync_at datetime DEFAULT NULL COMMENT 'Last sync timestamp',
			error_message text DEFAULT NULL COMMENT 'Error message if sync failed',
			retry_count int(11) DEFAULT 0 COMMENT 'Number of retry attempts',
			created_at datetime DEFAULT CURRENT_TIMESTAMP,
			updated_at datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			meta_data longtext DEFAULT NULL COMMENT 'Additional JSON data',
			PRIMARY KEY (id),
			UNIQUE KEY unique_mapping (entity_type, wc_id, wc_parent_id, business_id),
			KEY idx_hesabix (hesabix_id, business_id),
			KEY idx_entity (entity_type, wc_id),
			KEY idx_sync_status (sync_status),
			KEY idx_business (business_id)
		) $charset_collate;";

		// Create sync log table
		$log_table = $wpdb->prefix . 'hesabix_v2_sync_log';
		$sql_log = "CREATE TABLE IF NOT EXISTS $log_table (
			id bigint(20) NOT NULL AUTO_INCREMENT,
			entity_type varchar(50) NOT NULL,
			entity_id bigint(20) NOT NULL,
			action varchar(50) NOT NULL COMMENT 'create, update, delete',
			status varchar(20) NOT NULL COMMENT 'success, error',
			request_data longtext DEFAULT NULL COMMENT 'Request payload JSON',
			response_data longtext DEFAULT NULL COMMENT 'Response JSON',
			error_message text DEFAULT NULL,
			execution_time float DEFAULT NULL COMMENT 'Execution time in seconds',
			created_at datetime DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			KEY idx_entity (entity_type, entity_id),
			KEY idx_created (created_at),
			KEY idx_status (status)
		) $charset_collate;";

		// Create queue table for background sync
		$queue_table = $wpdb->prefix . 'hesabix_v2_queue';
		$sql_queue = "CREATE TABLE IF NOT EXISTS $queue_table (
			id bigint(20) NOT NULL AUTO_INCREMENT,
			entity_type varchar(50) NOT NULL,
			entity_id bigint(20) NOT NULL,
			action varchar(50) NOT NULL,
			priority int(11) DEFAULT 5 COMMENT '1-10, higher is more important',
			payload longtext DEFAULT NULL COMMENT 'Data to sync',
			status varchar(20) DEFAULT 'pending' COMMENT 'pending, processing, completed, failed',
			attempts int(11) DEFAULT 0,
			error_message text DEFAULT NULL,
			created_at datetime DEFAULT CURRENT_TIMESTAMP,
			updated_at datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			KEY idx_status (status),
			KEY idx_priority (priority),
			KEY idx_entity (entity_type, entity_id)
		) $charset_collate;";

		require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
		dbDelta($sql);
		dbDelta($sql_log);
		dbDelta($sql_queue);

		// Save database version
		update_option('hesabix_v2_db_version', '2.0.0');

		// Set default options
		if (!get_option('hesabix_v2_api_base_url')) {
			update_option('hesabix_v2_api_base_url', HESABIX_V2_API_BASE_URL);
		}

		add_option('hesabix_v2_invoice_payment_destination', 'bank');
		add_option('hesabix_v2_default_cash_register_id', '');

		if (!get_option('hesabix_v2_enabled')) {
			update_option('hesabix_v2_enabled', false);
		}

		if (!get_option('hesabix_v2_debug_mode')) {
			update_option('hesabix_v2_debug_mode', false);
		}

		add_option('hesabix_v2_opening_inventory_completed', false);
		add_option('hesabix_v2_opening_inventory_prefs', array());

		add_option(
			'hesabix_v2_stock_pull',
			array(
				'enabled' => false,
				'warehouse_scope' => 'default',
				'warehouse_ids' => array(),
				'cron_minutes' => 15,
				'force_manage_stock' => true,
				'disable_wc_stock_reduction' => false,
			)
		);

		add_option(
			'hesabix_v2_invoice_warehouse_rules',
			array(
				'resolution' => 'default',
				'rules' => array(),
			)
		);

		// Default sync settings
		$default_sync_settings = array(
			'auto_sync_products' => true,
			'auto_sync_customers' => true,
			'auto_sync_orders' => true,
			'sync_on_product_update' => true,
			'sync_product_price' => true,
			'sync_product_stock' => true,
			'track_inventory_policy' => 'wc',
			'sync_product_categories' => true,
			'sync_category_link_by_name_in_hesabix' => false,
			'create_customer_on_order' => true,
			'sync_order_on_checkout' => true,
			'sync_order_on_payment_complete' => false,
			'sync_order_on_statuses' => array('processing', 'completed'),
			'invoice_is_proforma' => false,
			'invoice_tag_website_enabled' => true,
			'invoice_tag_website_name' => 'فروش سایت',
			'invoice_extra_tag_ids' => '',
			'order_fiscal_year_date_policy' => 'keep',
		);

		if (!get_option('hesabix_v2_sync_settings')) {
			update_option('hesabix_v2_sync_settings', $default_sync_settings);
		} else {
			$existing = get_option('hesabix_v2_sync_settings', array());
			if (is_array($existing)) {
				$merged = array_merge($default_sync_settings, $existing);
				update_option('hesabix_v2_sync_settings', $merged);
			}
		}

		// Show setup wizard on first activation
		if (!get_option('hesabix_v2_setup_completed')) {
			set_transient('hesabix_v2_show_setup_wizard', true, 60 * 60); // 1 hour
		}

		// Create log directory
		$upload_dir = wp_upload_dir();
		$log_dir = $upload_dir['basedir'] . '/hesabix-v2-logs';
		if (!file_exists($log_dir)) {
			wp_mkdir_p($log_dir);
			// Add .htaccess to protect logs
			file_put_contents($log_dir . '/.htaccess', 'Deny from all');
		}

		// Schedule cron jobs
		if (!wp_next_scheduled('hesabix_v2_process_queue')) {
			wp_schedule_event(time(), 'every_5_minutes', 'hesabix_v2_process_queue');
		}

		if (!wp_next_scheduled('hesabix_v2_clean_old_logs')) {
			wp_schedule_event(time(), 'daily', 'hesabix_v2_clean_old_logs');
		}

		// Flush rewrite rules
		flush_rewrite_rules();
	}

	/**
	 * Create custom cron schedule
	 *
	 * @since    2.0.0
	 */
	public static function add_cron_schedules($schedules)
	{
		$schedules['every_5_minutes'] = array(
			'interval' => 300,
			'display'  => __('هر 5 دقیقه', 'hesabix-v2')
		);
		
		return $schedules;
	}
}

// Add custom cron schedule
add_filter('cron_schedules', array('Hesabix_V2_Activator', 'add_cron_schedules'));

