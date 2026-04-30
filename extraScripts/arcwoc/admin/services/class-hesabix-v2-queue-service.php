<?php
/**
 * پردازشگر صف همگام‌سازی (جدول wp_hesabix_v2_queue).
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Queue_Service
{
	const MAX_ATTEMPTS = 5;

	const BATCH_SIZE = 15;

	/**
	 * Cron: پردازش آیتم‌های در انتظار صف.
	 *
	 * @return void
	 */
	public static function process_due()
	{
		if (!get_option('hesabix_v2_enabled')) {
			return;
		}

		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_queue';

		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT * FROM {$table} WHERE status = %s ORDER BY priority DESC, id ASC LIMIT %d",
				'pending',
				self::BATCH_SIZE
			),
			ARRAY_A
		);

		if (empty($rows)) {
			return;
		}

		$sync = new Hesabix_V2_Sync_Service();

		foreach ($rows as $row) {
			$id = (int) $row['id'];
			$wpdb->update(
				$table,
				array(
					'status' => 'processing',
					'updated_at' => current_time('mysql'),
				),
				array('id' => $id),
				array('%s', '%s'),
				array('%d')
			);

			$payload = array();
			if (!empty($row['payload'])) {
				$decoded = json_decode($row['payload'], true);
				if (is_array($decoded)) {
					$payload = $decoded;
				}
			}

			$res = null;
			$ok = false;

			try {
				switch ($row['entity_type']) {
					case 'product':
						if (!empty($payload['parent_id'])) {
							$res = $sync->sync_product((int) $payload['parent_id'], (int) $row['entity_id']);
						} else {
							$res = $sync->sync_product((int) $row['entity_id']);
						}
						break;
					case 'customer':
						$res = $sync->sync_customer((int) $row['entity_id']);
						break;
					case 'order':
						$res = $sync->sync_order((int) $row['entity_id']);
						break;
					default:
						$res = array(
							'success' => false,
							'message' => __('نوع موجودیت صف نامعتبر است.', 'hesabix-v2'),
						);
				}

				$ok = is_array($res) && !empty($res['success']);
			} catch (Exception $e) {
				$res = array(
					'success' => false,
					'message' => $e->getMessage(),
				);
			}

			$msg = is_array($res) && isset($res['message'])
				? mb_substr((string) $res['message'], 0, 500)
				: '';

			if ($ok) {
				$wpdb->update(
					$table,
					array(
						'status' => 'completed',
						'error_message' => null,
						'updated_at' => current_time('mysql'),
					),
					array('id' => $id),
					array('%s', '%s', '%s'),
					array('%d')
				);
			} else {
				$attempts = (int) $row['attempts'] + 1;
				$status = $attempts >= self::MAX_ATTEMPTS ? 'failed' : 'pending';
				$wpdb->update(
					$table,
					array(
						'status' => $status,
						'attempts' => $attempts,
						'error_message' => $msg !== '' ? $msg : __('همگام‌سازی ناموفق', 'hesabix-v2'),
						'updated_at' => current_time('mysql'),
					),
					array('id' => $id),
					array('%s', '%d', '%s', '%s'),
					array('%d')
				);
			}
		}
	}

	/**
	 * افزودن به صف در صورت نبود ردیف pending تکراری.
	 *
	 * @param string   $entity_type product|customer|order
	 * @param int      $entity_id
	 * @param string   $action
	 * @param array|null $payload
	 * @param int      $priority
	 * @return bool درج شد یا نه
	 */
	public static function enqueue($entity_type, $entity_id, $action, $payload = null, $priority = 5)
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_queue';

		$entity_id = (int) $entity_id;
		if ($entity_id < 1 || $entity_type === '') {
			return false;
		}

		$exists = $wpdb->get_var(
			$wpdb->prepare(
				"SELECT id FROM {$table} WHERE entity_type = %s AND entity_id = %d AND action = %s AND status = %s LIMIT 1",
				$entity_type,
				$entity_id,
				$action,
				'pending'
			)
		);

		if ($exists) {
			return false;
		}

		$data = array(
			'entity_type' => $entity_type,
			'entity_id' => $entity_id,
			'action' => $action,
			'priority' => (int) $priority,
			'status' => 'pending',
			'attempts' => 0,
		);
		$formats = array('%s', '%d', '%s', '%d', '%s', '%d');

		if ($payload !== null && array() !== $payload) {
			$data['payload'] = wp_json_encode($payload);
			$formats[] = '%s';
		}

		$wpdb->insert($table, $data, $formats);

		return (bool) $wpdb->insert_id;
	}
}
