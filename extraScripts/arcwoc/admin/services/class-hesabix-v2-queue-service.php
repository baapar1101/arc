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

	/** اولویت پیش‌فرض محصول/مشتری. */
	const PRIORITY_DEFAULT = 5;

	/** سفارش باید جلوتر از backlog محصول پردازش شود. */
	const PRIORITY_ORDER = 20;

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
				"SELECT * FROM {$table} WHERE status = %s ORDER BY CASE entity_type WHEN 'order' THEN 0 WHEN 'order_return' THEN 0 WHEN 'customer' THEN 1 ELSE 2 END, priority DESC, id ASC LIMIT %d",
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
					case 'order_return':
						$res = Hesabix_V2_Sales_Return_Service::process_queue_item((int) $row['entity_id'], $payload);
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
				$permanent = is_array($res) && !empty($res['non_retryable']);
				if (!$permanent && class_exists('Hesabix_V2_Sync_Service') && Hesabix_V2_Sync_Service::message_is_duplicate_barcode($msg)) {
					$permanent = true;
				}
				$status = ($permanent || $attempts >= self::MAX_ATTEMPTS) ? 'failed' : 'pending';
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
	 * @param string   $entity_type product|customer|order|order_return
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
				"SELECT id FROM {$table} WHERE entity_type = %s AND entity_id = %d AND action = %s AND status IN ('pending','processing') LIMIT 1",
				$entity_type,
				$entity_id,
				$action
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

	/**
	 * حذف کارهای برگشت از فروش در انتظار برای سفارش و بازپرداخت‌هایش (مثلاً هنگام حذف دائمی).
	 *
	 * @param int        $order_id
	 * @param int[]|null $refund_ids
	 * @return int
	 */
	public static function cancel_pending_returns_for_order($order_id, $refund_ids = null)
	{
		global $wpdb;
		$table = $wpdb->prefix . 'hesabix_v2_queue';
		$order_id = (int) $order_id;
		if ($order_id < 1) {
			return 0;
		}

		$deleted = (int) $wpdb->query(
			$wpdb->prepare(
				"DELETE FROM {$table} WHERE entity_type = %s AND entity_id = %d AND status IN ('pending','processing')",
				'order_return',
				$order_id
			)
		);

		if (!is_array($refund_ids)) {
			$refund_ids = array();
			$order = wc_get_order($order_id);
			if ($order instanceof WC_Order && method_exists($order, 'get_refunds')) {
				foreach ($order->get_refunds() as $refund) {
					if ($refund instanceof WC_Order_Refund) {
						$refund_ids[] = (int) $refund->get_id();
					}
				}
			}
		}

		$refund_ids = array_values(array_unique(array_filter(array_map('intval', $refund_ids))));
		foreach ($refund_ids as $rid) {
			if ($rid < 1) {
				continue;
			}
			$deleted += (int) $wpdb->query(
				$wpdb->prepare(
					"DELETE FROM {$table} WHERE entity_type = %s AND entity_id = %d AND status IN ('pending','processing')",
					'order_return',
					$rid
				)
			);
		}

		return $deleted;
	}

	/**
	 * اجرای بعدی صف (Action Scheduler در صورت وجود، وگرنه رویداد تکی WP-Cron).
	 *
	 * @return void
	 */
	public static function spawn_processor()
	{
		$scheduled = false;
		if (function_exists('as_enqueue_async_action')) {
			$id = as_enqueue_async_action('hesabix_v2_async_process_queue', array(), 'hesabix-v2-queue', true);
			$scheduled = is_int($id) && $id > 0;
		}

		if (!$scheduled && !get_transient('hesabix_v2_queue_wp_cron_sched')) {
			set_transient('hesabix_v2_queue_wp_cron_sched', '1', 90);
			wp_schedule_single_event(time() + 2, 'hesabix_v2_process_queue');
		}
	}
}
