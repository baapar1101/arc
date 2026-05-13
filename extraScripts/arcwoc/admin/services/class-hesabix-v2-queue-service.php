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

	/** پیش‌فرض تعداد آیتم در هر اجرای کرون؛ مقدار واقعی از تنظیمات همگام‌سازی خوانده می‌شود. */
	const DEFAULT_ITEMS_PER_RUN = 15;

	/**
	 * حداکثر تعداد کارهای صف که در هر فراخوانی process_due پردازش می‌شود (۱ تا ۵۰۰).
	 *
	 * @since 3.3.6
	 * @return int
	 */
	public static function get_batch_size()
	{
		$sync = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		$n = isset($sync['queue_items_per_cron_run']) ? (int) $sync['queue_items_per_cron_run'] : self::DEFAULT_ITEMS_PER_RUN;

		return (int) apply_filters('hesabix_v2_queue_batch_size', max(1, min(500, $n)));
	}

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

		if (defined('DOING_CRON') && DOING_CRON) {
			if (function_exists('wp_raise_memory_limit')) {
				wp_raise_memory_limit('admin');
			}
			@set_time_limit(0);
		}

		$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync(new Hesabix_V2_Api(), null);
		if (!$gate['ok']) {
			return;
		}

		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_queue';
		$limit = self::get_batch_size();

		$rows = $wpdb->get_results(
			$wpdb->prepare(
				"SELECT * FROM {$table} WHERE status = %s ORDER BY priority DESC, id ASC LIMIT %d",
				'pending',
				$limit
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
						if (class_exists('Hesabix_V2_Order_Sync_Meta') && Hesabix_V2_Order_Sync_Meta::is_pause_auto_sync((int) $row['entity_id'])) {
							$res = array(
								'success' => true,
								'message' => __('رد شده — همگام‌سازی خودکار برای این سفارش متوقف است.', 'hesabix-v2'),
								'skipped_pause' => true,
							);
						} else {
							$res = $sync->sync_order((int) $row['entity_id']);
						}
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

	/**
	 * حذف کارهای در انتظار/در حال پردازش صف برای یک سفارش (مثلاً پس از لغو ارسال).
	 *
	 * @param int $order_id
	 * @return int تعداد ردیف‌های حذف‌شده
	 */
	public static function cancel_pending_for_order($order_id)
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_queue';
		$order_id = (int) $order_id;
		if ($order_id < 1) {
			return 0;
		}

		return (int) $wpdb->query(
			$wpdb->prepare(
				"DELETE FROM {$table} WHERE entity_type = %s AND entity_id = %d AND status IN ('pending','processing')",
				'order',
				$order_id
			)
		);
	}
}
