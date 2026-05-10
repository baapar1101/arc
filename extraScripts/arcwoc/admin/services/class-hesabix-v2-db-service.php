<?php
/**
 * Database Service - Handle mappings between WooCommerce and Hesabix
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_DB_Service
{
	/**
	 * Table name
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      string    $table
	 */
	private $table;

	/**
	 * Business ID
	 *
	 * @since    2.0.0
	 * @access   private
	 * @var      int    $business_id
	 */
	private $business_id;

	/**
	 * Initialize the class
	 *
	 * @since    2.0.0
	 */
	public function __construct()
	{
		global $wpdb;
		$this->table = $wpdb->prefix . 'hesabix_v2';
		$this->business_id = get_option('hesabix_v2_business_id');
	}

	/**
	 * Save mapping
	 *
	 * @since    2.0.0
	 * @param    string    $entity_type      product, customer, order, variation, category
	 * @param    int       $wc_id            WooCommerce ID
	 * @param    int       $wc_parent_id     Parent ID for variations
	 * @param    int       $hesabix_id       Hesabix ID
	 * @param    string    $hesabix_type     Type in Hesabix
	 * @param    array     $meta_data        Additional metadata
	 * @return   int|false                   Inserted ID or false on failure
	 */
	public function save_mapping($entity_type, $wc_id, $wc_parent_id, $hesabix_id, $hesabix_type = null, $meta_data = array())
	{
		global $wpdb;

		$data = array(
			'entity_type' => $entity_type,
			'wc_id' => $wc_id,
			'wc_parent_id' => $wc_parent_id,
			'hesabix_id' => $hesabix_id,
			'hesabix_type' => $hesabix_type,
			'business_id' => $this->business_id,
			'sync_status' => 'synced',
			'last_sync_at' => current_time('mysql'),
			'meta_data' => !empty($meta_data) ? wp_json_encode($meta_data) : null,
		);

		// Check if mapping already exists
		$existing = $this->get_mapping($entity_type, $wc_id, $wc_parent_id);

		if ($existing) {
			// Update existing mapping
			$wpdb->update(
				$this->table,
				$data,
				array('id' => $existing['id']),
				array('%s', '%d', '%d', '%d', '%s', '%d', '%s', '%s', '%s'),
				array('%d')
			);
			return $existing['id'];
		} else {
			// Insert new mapping
			$wpdb->insert(
				$this->table,
				$data,
				array('%s', '%d', '%d', '%d', '%s', '%d', '%s', '%s', '%s')
			);
			return $wpdb->insert_id;
		}
	}

	/**
	 * Get mapping
	 *
	 * @since    2.0.0
	 * @param    string    $entity_type
	 * @param    int       $wc_id
	 * @param    int       $wc_parent_id
	 * @return   array|null
	 */
	public function get_mapping($entity_type, $wc_id, $wc_parent_id = null)
	{
		global $wpdb;

		$where = $wpdb->prepare(
			"entity_type = %s AND wc_id = %d AND business_id = %d",
			$entity_type,
			$wc_id,
			$this->business_id
		);

		if ($wc_parent_id !== null) {
			$where .= $wpdb->prepare(" AND wc_parent_id = %d", $wc_parent_id);
		} else {
			$where .= " AND wc_parent_id IS NULL";
		}

		$query = "SELECT * FROM {$this->table} WHERE $where LIMIT 1";
		$result = $wpdb->get_row($query, ARRAY_A);

		return $result;
	}

	/**
	 * Get Hesabix ID from WooCommerce ID
	 *
	 * @since    2.0.0
	 * @param    string    $entity_type
	 * @param    int       $wc_id
	 * @param    int       $wc_parent_id
	 * @return   int|null
	 */
	public function get_hesabix_id($entity_type, $wc_id, $wc_parent_id = null)
	{
		$mapping = $this->get_mapping($entity_type, $wc_id, $wc_parent_id);
		return $mapping ? $mapping['hesabix_id'] : null;
	}

	/**
	 * Get WooCommerce ID from Hesabix ID
	 *
	 * @since    2.0.0
	 * @param    string    $entity_type
	 * @param    int       $hesabix_id
	 * @return   array|null    Array with wc_id and wc_parent_id
	 */
	public function get_wc_id($entity_type, $hesabix_id)
	{
		global $wpdb;

		$query = $wpdb->prepare(
			"SELECT wc_id, wc_parent_id FROM {$this->table} 
			WHERE entity_type = %s AND hesabix_id = %d AND business_id = %d 
			LIMIT 1",
			$entity_type,
			$hesabix_id,
			$this->business_id
		);

		$result = $wpdb->get_row($query, ARRAY_A);
		return $result;
	}

	/**
	 * Delete mapping
	 *
	 * @since    2.0.0
	 * @param    string    $entity_type
	 * @param    int       $wc_id
	 * @param    int       $wc_parent_id
	 * @return   bool
	 */
	public function delete_mapping($entity_type, $wc_id, $wc_parent_id = null)
	{
		global $wpdb;

		$where = array(
			'entity_type' => $entity_type,
			'wc_id' => $wc_id,
			'business_id' => $this->business_id,
		);

		if ($wc_parent_id !== null) {
			$where['wc_parent_id'] = $wc_parent_id;
		}

		return $wpdb->delete($this->table, $where);
	}

	/**
	 * Update sync status
	 *
	 * @since    2.0.0
	 * @param    string    $entity_type
	 * @param    int       $wc_id
	 * @param    int       $wc_parent_id
	 * @param    string    $status          synced, pending, error
	 * @param    string    $error_message
	 * @return   bool
	 */
	public function update_sync_status($entity_type, $wc_id, $wc_parent_id, $status, $error_message = null)
	{
		global $wpdb;

		$data = array(
			'sync_status' => $status,
			'last_sync_at' => current_time('mysql'),
		);

		if ($error_message) {
			$data['error_message'] = $error_message;
			$data['retry_count'] = $wpdb->get_var($wpdb->prepare(
				"SELECT retry_count FROM {$this->table} 
				WHERE entity_type = %s AND wc_id = %d AND business_id = %d",
				$entity_type,
				$wc_id,
				$this->business_id
			)) + 1;
		} else {
			$data['error_message'] = null;
			$data['retry_count'] = 0;
		}

		$where = array(
			'entity_type' => $entity_type,
			'wc_id' => $wc_id,
			'business_id' => $this->business_id,
		);

		if ($wc_parent_id !== null) {
			$where['wc_parent_id'] = $wc_parent_id;
		}

		return $wpdb->update($this->table, $data, $where);
	}

	/**
	 * Get sync statistics
	 *
	 * @since    2.0.0
	 * @return   array
	 */
	public function get_sync_stats()
	{
		global $wpdb;

		$stats = array();

		// Total mappings by type
		$query = "SELECT entity_type, COUNT(*) as count 
				  FROM {$this->table} 
				  WHERE business_id = %d 
				  GROUP BY entity_type";
		
		$results = $wpdb->get_results($wpdb->prepare($query, $this->business_id), ARRAY_A);
		
		foreach ($results as $row) {
			$stats[$row['entity_type']] = array(
				'total' => $row['count'],
			);
		}

		// Count by status
		$query = "SELECT entity_type, sync_status, COUNT(*) as count 
				  FROM {$this->table} 
				  WHERE business_id = %d 
				  GROUP BY entity_type, sync_status";
		
		$results = $wpdb->get_results($wpdb->prepare($query, $this->business_id), ARRAY_A);
		
		foreach ($results as $row) {
			if (!isset($stats[$row['entity_type']])) {
				$stats[$row['entity_type']] = array('total' => 0);
			}
			$stats[$row['entity_type']][$row['sync_status']] = $row['count'];
		}

		return $stats;
	}

	/**
	 * Get pending sync items
	 *
	 * @since    2.0.0
	 * @param    string    $entity_type
	 * @param    int       $limit
	 * @return   array
	 */
	public function get_pending_items($entity_type = null, $limit = 50)
	{
		global $wpdb;

		$where = $wpdb->prepare("sync_status = 'pending' AND business_id = %d", $this->business_id);
		
		if ($entity_type) {
			$where .= $wpdb->prepare(" AND entity_type = %s", $entity_type);
		}

		$query = "SELECT * FROM {$this->table} 
				  WHERE $where 
				  ORDER BY created_at ASC 
				  LIMIT %d";

		return $wpdb->get_results($wpdb->prepare($query, $limit), ARRAY_A);
	}

	/**
	 * Get error items
	 *
	 * @since    2.0.0
	 * @param    string    $entity_type
	 * @param    int       $limit
	 * @return   array
	 */
	public function get_error_items($entity_type = null, $limit = 50)
	{
		global $wpdb;

		$where = $wpdb->prepare("sync_status = 'error' AND business_id = %d", $this->business_id);
		
		if ($entity_type) {
			$where .= $wpdb->prepare(" AND entity_type = %s", $entity_type);
		}

		$query = "SELECT * FROM {$this->table} 
				  WHERE $where 
				  ORDER BY updated_at DESC 
				  LIMIT %d";

		return $wpdb->get_results($wpdb->prepare($query, $limit), ARRAY_A);
	}

	/**
	 * همهٔ نگاشت‌های محصول (ساده و واریانت) برای کسب‌وکار جاری.
	 *
	 * @since 3.3.2
	 * @return array<int, array<string, mixed>>
	 */
	public function get_all_product_mappings()
	{
		global $wpdb;

		$query = $wpdb->prepare(
			"SELECT wc_id, wc_parent_id, hesabix_id FROM {$this->table}
			WHERE entity_type = %s AND business_id = %d",
			'product',
			$this->business_id
		);

		$rows = $wpdb->get_results($query, ARRAY_A);

		return is_array($rows) ? $rows : array();
	}
}

