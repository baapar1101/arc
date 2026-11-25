<?php
/**
 * برگشت از فروش حسابیکس برای لغو، بازپرداخت، حذف دائمی و لغو ارسال.
 *
 * فروش قطعی (invoice_sales) نگه داشته می‌شود. زباله‌دان رویداد مالی نیست.
 *
 * @since      4.12.6
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Sales_Return_Service
{
	const ENTITY_TYPE = 'order_return';

	const REASON_CANCEL = 'cancel';
	const REASON_REFUND = 'refund';
	const REASON_DELETE = 'delete';
	const REASON_UNSYNC = 'unsync';
	const REASON_REFUNDED_STATUS = 'refunded_status';

	/**
	 * آیا برای این سفارش حداقل یک فاکتور برگشت از فروش ثبت شده است؟
	 *
	 * @param int $order_id
	 * @return bool
	 */
	public static function order_has_returns($order_id)
	{
		$db = new Hesabix_V2_DB_Service();
		$rows = $db->get_order_return_mappings((int) $order_id);

		return !empty($rows);
	}

	/**
	 * @return string
	 */
	public static function sale_sync_blocked_message()
	{
		return __('این سفارش برگشت از فروش دارد؛ فاکتور فروش قطعی در حسابیکس به‌روز نمی‌شود. برای فروش جدید یک سفارش تازه در ووکامرس ثبت کنید.', 'hesabix-v2');
	}

	/**
	 * لغو ارسال از فهرست سفارش‌ها: پیش‌فاکتور حذف می‌شود؛ فروش قطعی با برگشت از فروش خنثی می‌گردد.
	 *
	 * @param int $order_id
	 * @return array{success:bool,message:string,already_gone?:bool,proforma_deleted?:bool,return_invoice_id?:int}
	 */
	public static function unsync($order_id)
	{
		$order_id = (int) $order_id;
		$order = wc_get_order($order_id);
		if (!$order instanceof WC_Order) {
			return array(
				'success' => false,
				'message' => __('سفارش یافت نشد.', 'hesabix-v2'),
			);
		}

		Hesabix_V2_Queue_Service::cancel_pending_for_order($order_id);

		$db = new Hesabix_V2_DB_Service();
		$map = $db->get_mapping('order', $order_id);
		if (!$map || empty($map['hesabix_id'])) {
			if (class_exists('Hesabix_V2_Order_Sync_Meta')) {
				Hesabix_V2_Order_Sync_Meta::clear_on_unsync($order_id);
			}
			$db->delete_mapping('order', $order_id);

			return array(
				'success' => true,
				'message' => __('سفارشی در حسابیکس برای این سفارش ثبت نشده بود.', 'hesabix-v2'),
				'already_gone' => true,
			);
		}

		return self::process_remaining($order_id, self::REASON_UNSYNC);
	}

	/**
	 * صف کردن برگشت مانده (لغو / حذف / وضعیت refunded بدون شیء بازپرداخت).
	 *
	 * @param int    $order_id
	 * @param string $reason
	 * @return bool
	 */
	public static function enqueue_remaining($order_id, $reason)
	{
		$order_id = (int) $order_id;
		if ($order_id < 1) {
			return false;
		}

		self::prepare_order_for_reverse($order_id);

		$inserted = Hesabix_V2_Queue_Service::enqueue(
			self::ENTITY_TYPE,
			$order_id,
			'sales_return',
			array(
				'reason' => (string) $reason,
			),
			Hesabix_V2_Queue_Service::PRIORITY_ORDER
		);

		Hesabix_V2_Queue_Service::spawn_processor();

		return $inserted;
	}

	/**
	 * صف کردن برگشت متناظر با یک بازپرداخت ووکامرس.
	 *
	 * @param int $order_id
	 * @param int $refund_id
	 * @return bool
	 */
	public static function enqueue_refund($order_id, $refund_id)
	{
		$order_id = (int) $order_id;
		$refund_id = (int) $refund_id;
		if ($order_id < 1 || $refund_id < 1) {
			return false;
		}

		self::prepare_order_for_reverse($order_id);

		$inserted = Hesabix_V2_Queue_Service::enqueue(
			self::ENTITY_TYPE,
			$refund_id,
			'sales_return',
			array(
				'reason' => self::REASON_REFUND,
				'order_id' => $order_id,
				'refund_id' => $refund_id,
			),
			Hesabix_V2_Queue_Service::PRIORITY_ORDER
		);

		Hesabix_V2_Queue_Service::spawn_processor();

		return $inserted;
	}

	/**
	 * پردازش آیتم صف order_return.
	 *
	 * @param int   $entity_id
	 * @param array $payload
	 * @return array{success:bool,message:string}
	 */
	public static function process_queue_item($entity_id, array $payload)
	{
		$reason = isset($payload['reason']) ? (string) $payload['reason'] : '';
		$refund_id = isset($payload['refund_id']) ? (int) $payload['refund_id'] : 0;
		$order_id = isset($payload['order_id']) ? (int) $payload['order_id'] : 0;

		if ($reason === self::REASON_REFUND || $refund_id > 0) {
			if ($refund_id < 1) {
				$refund_id = (int) $entity_id;
			}
			if ($order_id < 1) {
				$refund = wc_get_order($refund_id);
				if ($refund instanceof WC_Order_Refund) {
					$order_id = (int) $refund->get_parent_id();
				}
			}

			return self::process_refund($order_id, $refund_id);
		}

		if ($order_id < 1) {
			$order_id = (int) $entity_id;
		}

		if ($reason === '') {
			$reason = self::REASON_CANCEL;
		}

		return self::process_remaining($order_id, $reason);
	}

	/**
	 * برگشت ماندهٔ فروش (پس از کسر برگشت‌های قبلی و بازپرداخت‌های هنوز نگاشت‌نشده).
	 *
	 * @param int    $order_id
	 * @param string $reason
	 * @return array{success:bool,message:string,already_gone?:bool,proforma_deleted?:bool,return_invoice_id?:int,skipped?:bool}
	 */
	public static function process_remaining($order_id, $reason)
	{
		$order_id = (int) $order_id;
		$reason = (string) $reason;
		if ($reason === '') {
			$reason = self::REASON_CANCEL;
		}

		return self::with_order_lock(
			$order_id,
			function () use ($order_id, $reason) {
				return self::create_return_invoice(
					$order_id,
					$reason,
					0,
					null
				);
			}
		);
	}

	/**
	 * برگشت متناظر با یک WC_Order_Refund.
	 *
	 * @param int $order_id
	 * @param int $refund_id
	 * @return array{success:bool,message:string,return_invoice_id?:int,skipped?:bool}
	 */
	public static function process_refund($order_id, $refund_id)
	{
		$order_id = (int) $order_id;
		$refund_id = (int) $refund_id;
		if ($refund_id < 1) {
			return array(
				'success' => false,
				'message' => __('شناسهٔ بازپرداخت نامعتبر است.', 'hesabix-v2'),
			);
		}

		if ($order_id < 1) {
			$refund = wc_get_order($refund_id);
			if ($refund instanceof WC_Order_Refund) {
				$order_id = (int) $refund->get_parent_id();
			}
		}

		return self::with_order_lock(
			$order_id,
			function () use ($order_id, $refund_id) {
				return self::create_return_invoice(
					$order_id,
					self::REASON_REFUND,
					$refund_id,
					null
				);
			}
		);
	}

	/**
	 * قبل از برگشت: صف به‌روزرسانی فاکتور فروش لغو شود و همگام خودکار متوقف گردد.
	 *
	 * @param int $order_id
	 * @return void
	 */
	public static function prepare_order_for_reverse($order_id)
	{
		$order_id = (int) $order_id;
		if ($order_id < 1) {
			return;
		}

		Hesabix_V2_Queue_Service::cancel_pending_for_order($order_id);
		if (class_exists('Hesabix_V2_Order_Sync_Meta')) {
			Hesabix_V2_Order_Sync_Meta::set_pause_auto_sync($order_id, true);
		}
	}

	/**
	 * @param int      $order_id
	 * @param callable $fn
	 * @return array
	 */
	private static function with_order_lock($order_id, $fn)
	{
		$order_id = (int) $order_id;
		if ($order_id < 1) {
			return array(
				'success' => false,
				'message' => __('شناسهٔ سفارش نامعتبر است.', 'hesabix-v2'),
			);
		}

		$lock_key = 'hesabix_v2_sr_lock_' . $order_id;
		if (get_transient($lock_key)) {
			return array(
				'success' => false,
				'message' => __('برگشت از فروش همین سفارش در حال انجام است؛ کمی بعد دوباره تلاش می‌شود.', 'hesabix-v2'),
				'busy' => true,
			);
		}

		set_transient($lock_key, '1', 180);
		try {
			return $fn();
		} finally {
			delete_transient($lock_key);
		}
	}

	/**
	 * @param int             $order_id
	 * @param string          $reason
	 * @param int             $refund_id
	 * @param WC_Order|null   $order_override
	 * @return array
	 */
	private static function create_return_invoice($order_id, $reason, $refund_id, $order_override)
	{
		$order_id = (int) $order_id;
		$refund_id = (int) $refund_id;
		$reason = (string) $reason;

		$order = $order_override instanceof WC_Order ? $order_override : wc_get_order($order_id);
		if (!$order instanceof WC_Order) {
			return array(
				'success' => false,
				'message' => __('سفارش یافت نشد.', 'hesabix-v2'),
			);
		}

		if ($order instanceof WC_Order_Refund) {
			return array(
				'success' => false,
				'message' => __('این رکورد یک بازپرداخت است نه سفارش فروش.', 'hesabix-v2'),
			);
		}

		if ($reason === self::REASON_DELETE) {
			Hesabix_V2_Queue_Service::cancel_pending_returns_for_order($order_id);
		}

		$db = new Hesabix_V2_DB_Service();
		$sale_map = $db->get_mapping('order', $order_id);
		if (!$sale_map || empty($sale_map['hesabix_id'])) {
			return array(
				'success' => true,
				'skipped' => true,
				'already_gone' => true,
				'message' => __('فاکتور فروشی در حسابیکس برای این سفارش نیست؛ برگشت لازم نشد.', 'hesabix-v2'),
			);
		}

		$source_id = (int) $sale_map['hesabix_id'];

		if ($refund_id > 0) {
			$existing = $db->get_mapping(self::ENTITY_TYPE, $refund_id, $order_id);
			if ($existing && !empty($existing['hesabix_id'])) {
				return array(
					'success' => true,
					'skipped' => true,
					'return_invoice_id' => (int) $existing['hesabix_id'],
					'message' => sprintf(
						/* translators: %d: Hesabix sales-return invoice id */
						__('برگشت از فروش این بازپرداخت قبلاً ثبت شده است (فاکتور %d).', 'hesabix-v2'),
						(int) $existing['hesabix_id']
					),
				);
			}
		} elseif ($reason !== self::REASON_REFUND) {
			$existing_full = $db->get_mapping(self::ENTITY_TYPE, $order_id, null);
			if ($existing_full && !empty($existing_full['hesabix_id'])) {
				$full_meta = self::decode_meta($existing_full);
				$remaining_probe = self::compute_remaining_plan($order, $db, $reason, 0);
				$probe_empty = empty($remaining_probe['lines']) && empty($remaining_probe['adjustments']['shipping']);
				if ($probe_empty || empty($full_meta['lines'])) {
					return array(
						'success' => true,
						'skipped' => true,
						'return_invoice_id' => (int) $existing_full['hesabix_id'],
						'message' => sprintf(
							/* translators: %d: Hesabix sales-return invoice id */
							__('برگشت از فروش این سفارش قبلاً ثبت شده است (فاکتور %d).', 'hesabix-v2'),
							(int) $existing_full['hesabix_id']
						),
					);
				}
			}
		}

		$api = new Hesabix_V2_Api();
		$got = $api->get_invoice($source_id);
		$invoice = self::unwrap_invoice($got);
		if (!$invoice) {
			$status = isset($got['status_code']) ? (int) $got['status_code'] : 0;
			$msg = isset($got['message']) ? (string) $got['message'] : '';
			if ($status === 404 || self::looks_like_not_found($msg)) {
				$db->delete_mapping('order', $order_id);
				if (class_exists('Hesabix_V2_Order_Sync_Meta')) {
					Hesabix_V2_Order_Sync_Meta::clear_on_unsync($order_id);
				}

				return array(
					'success' => true,
					'already_gone' => true,
					'message' => __('فاکتور فروش در حسابیکس پیدا نشد؛ پیوند افزونه پاک شد.', 'hesabix-v2'),
				);
			}

			return array(
				'success' => false,
				'message' => $msg !== '' ? $msg : __('دریافت فاکتور فروش از حسابیکس ناموفق بود.', 'hesabix-v2'),
			);
		}

		if (self::invoice_is_proforma($invoice)) {
			return self::delete_proforma_sale($order, $db, $api, $source_id);
		}

		self::prepare_order_for_reverse($order_id);

		if ($refund_id < 1 && $reason !== self::REASON_REFUND && $reason !== self::REASON_DELETE) {
			foreach ($order->get_refunds() as $prior_refund) {
				if (!$prior_refund instanceof WC_Order_Refund) {
					continue;
				}
				$prior_id = (int) $prior_refund->get_id();
				if ($prior_id < 1) {
					continue;
				}
				$already = $db->get_mapping(self::ENTITY_TYPE, $prior_id, $order_id);
				if ($already && !empty($already['hesabix_id'])) {
					continue;
				}
				$prior_res = self::create_return_invoice($order_id, self::REASON_REFUND, $prior_id, $order);
				if (empty($prior_res['success'])) {
					return $prior_res;
				}
			}
		}

		$plan = self::compute_remaining_plan($order, $db, $reason, $refund_id);
		if (empty($plan['lines']) && empty($plan['adjustments']['shipping'])) {
			$empty_msg = ($reason === self::REASON_UNSYNC)
				? __('مانده‌ای برای برگشت از فروش نماند؛ فاکتور فروش قطعی در حسابیکس نگه داشته شد و همگام خودکار متوقف است.', 'hesabix-v2')
				: __('مانده‌ای برای برگشت از فروش نماند.', 'hesabix-v2');

			return array(
				'success' => true,
				'skipped' => true,
				'message' => $empty_msg,
			);
		}

		$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($api, $order->get_currency());
		if (empty($gate['ok'])) {
			$gmsg = isset($gate['message']) ? (string) $gate['message'] : __('همگام‌سازی به‌دلیل ارز متوقف شد.', 'hesabix-v2');

			return array(
				'success' => false,
				'message' => $gmsg,
			);
		}

		$person_id = self::resolve_person_id($order, $db, $invoice);
		if ($person_id < 1) {
			return array(
				'success' => false,
				'message' => __('مشتری فاکتور فروش در حسابیکس پیدا نشد؛ برگشت از فروش ثبت نشد.', 'hesabix-v2'),
			);
		}

		$payload = apply_filters(
			'hesabix_v2_invoice_data',
			Hesabix_V2_Mapper::wc_order_to_invoice(
				$order,
				$person_id,
				isset($gate['factor']) ? (float) $gate['factor'] : 1.0,
				isset($gate['currency_id']) ? (int) $gate['currency_id'] : null,
				array(
					'document_date' => current_time('Y-m-d'),
				)
			),
			$order
		);

		if (!is_array($payload)) {
			return array(
				'success' => false,
				'message' => __('ساخت دادهٔ فاکتور برگشت ناموفق بود.', 'hesabix-v2'),
			);
		}

		$payload = self::transform_sale_payload_to_return(
			$payload,
			$source_id,
			$order,
			$reason,
			$refund_id,
			$plan
		);
		$pay_saved = 0.0;
		if (!empty($payload['payments']) && is_array($payload['payments'])) {
			foreach ($payload['payments'] as $prow) {
				if (is_array($prow) && isset($prow['amount'])) {
					$pay_saved += abs((float) $prow['amount']);
				}
			}
		}

		if (empty($payload['lines']) && empty($payload['extra_info']['invoice_adjustments'])) {
			if (!empty($plan['lines'])) {
				Hesabix_V2_Log_Service::warning(
					'Sales return plan had lines but payload lines were empty after transform',
					array(
						'entity_type' => self::ENTITY_TYPE,
						'entity_id' => $order_id,
						'reason' => $reason,
						'plan_keys' => array_keys($plan['lines']),
					)
				);
			}

			return array(
				'success' => true,
				'skipped' => true,
				'message' => __('پس از تبدیل، خطی برای برگشت از فروش نماند.', 'hesabix-v2'),
			);
		}

		$created = $api->create_invoice($payload);
		$new_id = Hesabix_V2_Api::extract_id($created);
		if ($new_id < 1) {
			$err = isset($created['message']) ? (string) $created['message'] : __('ثبت برگشت از فروش در حسابیکس ناموفق بود.', 'hesabix-v2');
			Hesabix_V2_Log_Service::error(
				'Sales return invoice create failed',
				array(
					'entity_type' => self::ENTITY_TYPE,
					'entity_id' => $refund_id > 0 ? $refund_id : $order_id,
					'wc_order_id' => $order_id,
					'wc_refund_id' => $refund_id,
					'reason' => $reason,
					'source_invoice_id' => $source_id,
					'error' => $err,
				)
			);

			return array(
				'success' => false,
				'message' => $err,
			);
		}

		$meta = array(
			'reason' => $reason,
			'refund_id' => $refund_id,
			'source_invoice_id' => $source_id,
			'payment_amount' => $pay_saved,
			'lines' => isset($plan['line_meta']) && is_array($plan['line_meta']) ? $plan['line_meta'] : array(),
		);

		$map_wc_id = $refund_id > 0 ? $refund_id : $order_id;
		$map_parent = $refund_id > 0 ? $order_id : null;
		$db->save_mapping(
			self::ENTITY_TYPE,
			$map_wc_id,
			$map_parent,
			$new_id,
			'invoice_sales_return',
			$meta
		);

		self::prepare_order_for_reverse($order_id);

		$note = sprintf(
			/* translators: 1: return invoice id, 2: original sales invoice id, 3: reason label */
			__('برگشت از فروش در حسابیکس ثبت شد (فاکتور %1$d برای فروش %2$d — %3$s). فاکتور فروش قطعی حذف نشد.', 'hesabix-v2'),
			$new_id,
			$source_id,
			self::reason_label($reason)
		);
		$order->add_order_note($note);

		Hesabix_V2_Log_Service::info(
			'Sales return invoice created',
			array(
				'entity_type' => self::ENTITY_TYPE,
				'entity_id' => $map_wc_id,
				'wc_order_id' => $order_id,
				'wc_refund_id' => $refund_id,
				'reason' => $reason,
				'source_invoice_id' => $source_id,
				'hesabix_id' => $new_id,
			)
		);

		if (class_exists('Hesabix_V2_Invoice_Profit_Service')) {
			Hesabix_V2_Invoice_Profit_Service::maybe_refresh_after_sync($order_id, $source_id, $api);
		}

		return array(
			'success' => true,
			'return_invoice_id' => $new_id,
			'message' => $note,
		);
	}

	/**
	 * @param WC_Order            $order
	 * @param Hesabix_V2_DB_Service $db
	 * @param Hesabix_V2_Api      $api
	 * @param int                 $source_id
	 * @return array
	 */
	private static function delete_proforma_sale($order, $db, $api, $source_id)
	{
		$order_id = (int) $order->get_id();
		Hesabix_V2_Queue_Service::cancel_pending_for_order($order_id);

		$res = $api->delete_invoice((int) $source_id);
		if (empty($res['success'])) {
			$msg = isset($res['message']) ? (string) $res['message'] : __('حذف پیش‌فاکتور در حسابیکس ناموفق بود.', 'hesabix-v2');

			return array(
				'success' => false,
				'message' => $msg,
			);
		}

		$db->delete_mapping('order', $order_id);
		if (class_exists('Hesabix_V2_Order_Sync_Meta')) {
			Hesabix_V2_Order_Sync_Meta::clear_on_unsync($order_id);
		}

		$order->add_order_note(
			sprintf(
				/* translators: %d: Hesabix proforma invoice id */
				__('پیش‌فاکتور حسابیکس %d حذف شد (هنوز قطعی نشده بود).', 'hesabix-v2'),
				(int) $source_id
			)
		);

		Hesabix_V2_Log_Service::info(
			'Proforma invoice deleted on unsync/reverse',
			array(
				'entity_type' => 'order',
				'entity_id' => $order_id,
				'hesabix_invoice_id' => (int) $source_id,
			)
		);

		return array(
			'success' => true,
			'proforma_deleted' => true,
			'message' => __('پیش‌فاکتور در حسابیکس حذف و ارتباط در افزونه پاک شد.', 'hesabix-v2'),
		);
	}

	/**
	 * @param WC_Order              $order
	 * @param Hesabix_V2_DB_Service $db
	 * @param string                $reason
	 * @param int                   $refund_id
	 * @return array{lines:array,adjustments:array,payment_amount:float,line_meta:array,include_shipping:bool,include_fees:bool,factor:float}
	 */
	private static function compute_remaining_plan($order, $db, $reason, $refund_id)
	{
		$consumed = self::consumed_qty_map($order, $db, $reason, $refund_id);
		$original_lines = self::original_line_qty_map($order);
		$want = array();
		$factor = 1.0;
		$include_shipping = true;
		$include_fees = true;

		if ($refund_id > 0) {
			$refund = wc_get_order($refund_id);
			if (!$refund instanceof WC_Order_Refund) {
				return array(
					'lines' => array(),
					'adjustments' => array(),
					'payment_amount' => 0.0,
					'line_meta' => array(),
					'include_shipping' => false,
					'include_fees' => false,
					'factor' => 0.0,
				);
			}

			$want = self::refund_qty_want_map($refund);
			$refund_abs = abs((float) $refund->get_total());
			$has_items = !empty($want);

			if (!$has_items) {
				$remaining_net = self::remaining_net_amount($order, $consumed, $original_lines);
				if ($remaining_net <= 0.05) {
					$include_shipping = false;
					$include_fees = false;
					$want = array();
				} elseif ($refund_abs + 0.05 >= $remaining_net) {
					$want = self::remaining_qty_map($original_lines, $consumed);
				} else {
					$factor = $remaining_net > 0 ? ($refund_abs / $remaining_net) : 0.0;
					Hesabix_V2_Log_Service::warning(
						'Amount-only WooCommerce refund scaled into sales-return quantities',
						array(
							'entity_type' => self::ENTITY_TYPE,
							'entity_id' => $refund_id,
							'wc_order_id' => (int) $order->get_id(),
							'refund_amount' => $refund_abs,
							'remaining_net' => $remaining_net,
							'factor' => $factor,
						)
					);
					$want = self::scale_qty_map(self::remaining_qty_map($original_lines, $consumed), $factor);
				}
			}

			$include_shipping = self::refund_includes_shipping($refund, $want, $has_items);
			$include_fees = self::refund_includes_fees($refund, $want, $has_items);
		} else {
			$want = self::remaining_qty_map($original_lines, $consumed);
			$include_shipping = empty($consumed['kind:shipping']) || (float) $consumed['kind:shipping'] < 1;
			$include_fees = true;
		}

		$lines = array();
		$line_meta = array();
		foreach ($original_lines as $key => $row) {
			$orig_qty = (float) $row['qty'];
			$used = isset($consumed[ $key ]) ? (float) $consumed[ $key ] : 0.0;
			$left = max(0.0, $orig_qty - $used);
			if ($left <= 0.00001) {
				continue;
			}

			$take = $left;
			if ($refund_id > 0) {
				if (isset($want[ $key ])) {
					$take = min($left, (float) $want[ $key ]);
				} elseif ($factor < 1.0 - 0.00001 && $factor > 0) {
					$take = min($left, $left * $factor);
				} elseif (!empty($want) && $factor >= 1.0 - 0.00001) {
					if (!isset($want[ $key ])) {
						continue;
					}
					$take = min($left, (float) $want[ $key ]);
				}
			}

			if ($take <= 0.00001) {
				continue;
			}

			$kind = isset($row['kind']) ? (string) $row['kind'] : 'product';
			if ($kind === 'shipping' && !$include_shipping) {
				continue;
			}
			if ($kind === 'fee' && !$include_fees) {
				continue;
			}

			$lines[ $key ] = $take;
			$line_meta[] = array(
				'key' => $key,
				'quantity' => $take,
				'kind' => $kind,
			);
		}

		$adj_shipping = ($include_shipping && (empty($consumed['adj:shipping']) || (float) $consumed['adj:shipping'] < 1));
		if ($refund_id > 0 && !$include_shipping) {
			$adj_shipping = false;
		}

		$payment_amount = 0.0;
		if ($refund_id > 0) {
			$refund_obj = wc_get_order($refund_id);
			if ($refund_obj instanceof WC_Order_Refund) {
				$payment_amount = abs((float) $refund_obj->get_total());
			}
		}

		return array(
			'lines' => $lines,
			'adjustments' => array(
				'shipping' => $adj_shipping,
			),
			'payment_amount' => $payment_amount,
			'line_meta' => $line_meta,
			'include_shipping' => $include_shipping,
			'include_fees' => $include_fees,
			'factor' => $factor,
		);
	}

	/**
	 * @param array    $payload
	 * @param int      $source_id
	 * @param WC_Order $order
	 * @param string   $reason
	 * @param int      $refund_id
	 * @param array    $plan
	 * @return array
	 */
	private static function transform_sale_payload_to_return(array $payload, $source_id, $order, $reason, $refund_id, array $plan)
	{
		$payload['invoice_type'] = 'invoice_sales_return';
		$payload['is_proforma'] = false;
		$payload['document_date'] = current_time('Y-m-d');

		if (!isset($payload['extra_info']) || !is_array($payload['extra_info'])) {
			$payload['extra_info'] = array();
		}

		$payload['extra_info']['returned_from_invoice_id'] = (int) $source_id;
		$payload['extra_info']['source_invoice_id'] = (int) $source_id;
		$payload['extra_info']['copy_from_invoice_id'] = (int) $source_id;
		$payload['extra_info']['post_inventory'] = true;
		$payload['extra_info']['source'] = 'woocommerce';
		$payload['extra_info']['wc_order_id'] = (int) $order->get_id();
		$payload['extra_info']['wc_return_reason'] = (string) $reason;
		if ($refund_id > 0) {
			$payload['extra_info']['wc_refund_id'] = (int) $refund_id;
		}

		$qty_plan = isset($plan['lines']) && is_array($plan['lines']) ? $plan['lines'] : array();
		$new_lines = array();
		if (isset($payload['lines']) && is_array($payload['lines'])) {
			foreach ($payload['lines'] as $line) {
				if (!is_array($line)) {
					continue;
				}
				$key = self::line_key($line);
				if (!isset($qty_plan[ $key ])) {
					continue;
				}
				$take = (float) $qty_plan[ $key ];
				$scaled = self::scale_line_to_qty($line, $take);
				if (!$scaled) {
					continue;
				}
				$scaled = self::flip_line_movement_in($scaled);
				$new_lines[] = $scaled;
			}
		}
		$payload['lines'] = $new_lines;

		$keep_ship_adj = !empty($plan['adjustments']['shipping']);
		if (isset($payload['extra_info']['invoice_adjustments']) && is_array($payload['extra_info']['invoice_adjustments'])) {
			$flipped = array();
			foreach ($payload['extra_info']['invoice_adjustments'] as $adj) {
				if (!is_array($adj)) {
					continue;
				}
				$src = isset($adj['source']) ? (string) $adj['source'] : '';
				if ($src === 'woocommerce_shipping' && !$keep_ship_adj) {
					continue;
				}
				if ($src === 'woocommerce_fee' && empty($plan['include_fees'])) {
					continue;
				}
				if ($src === 'woocommerce_shipping' || $src === 'woocommerce_fee') {
					$kind = isset($adj['kind']) ? (string) $adj['kind'] : 'addition';
					$adj['kind'] = ($kind === 'subtraction') ? 'addition' : 'subtraction';
				}
				$flipped[] = $adj;
			}
			if (!empty($flipped)) {
				$payload['extra_info']['invoice_adjustments'] = $flipped;
			} else {
				unset($payload['extra_info']['invoice_adjustments']);
			}
		}

		self::recompute_header_totals($payload);

		$paid_left = self::remaining_paid_amount($order, (int) $order->get_id());
		$return_net = 0.0;
		if (isset($payload['extra_info']['totals']['net'])) {
			$return_net = abs((float) $payload['extra_info']['totals']['net']);
		}
		$pay = 0.0;
		if ($refund_id > 0 && isset($plan['payment_amount'])) {
			$pay = abs((float) $plan['payment_amount']);
		} else {
			$pay = $return_net;
		}
		if ($paid_left <= 0.05) {
			$pay = 0.0;
		} else {
			$pay = min($pay, $paid_left, $return_net > 0 ? $return_net : $pay);
		}

		$payload['payments'] = self::build_return_payments($order, $pay, $reason, $refund_id);

		return $payload;
	}

	/**
	 * @param array $line
	 * @param float $take
	 * @return array|null
	 */
	private static function scale_line_to_qty(array $line, $take)
	{
		$orig_qty = isset($line['quantity']) ? (float) $line['quantity'] : 0.0;
		if ($orig_qty <= 0.00001 || $take <= 0.00001) {
			return null;
		}
		$ratio = $take / $orig_qty;
		if ($ratio <= 0) {
			return null;
		}
		if (abs($ratio - 1.0) < 0.0000001) {
			$line['quantity'] = $orig_qty;
			return $line;
		}

		$line['quantity'] = $take;
		if (isset($line['extra_info']) && is_array($line['extra_info'])) {
			$ei = $line['extra_info'];
			foreach (array('tax_amount', 'line_discount', 'line_total', 'discount_value') as $k) {
				if (isset($ei[ $k ]) && is_numeric($ei[ $k ])) {
					$ei[ $k ] = Hesabix_V2_Validation::sanitize_price((float) $ei[ $k ] * $ratio);
				}
			}
			$line['extra_info'] = $ei;
		}

		if (isset($line['allocations']) && is_array($line['allocations'])) {
			foreach ($line['allocations'] as $i => $alloc) {
				if (!is_array($alloc)) {
					continue;
				}
				$aq = isset($alloc['quantity']) ? (float) $alloc['quantity'] : $orig_qty;
				$line['allocations'][ $i ]['quantity'] = $aq * $ratio;
			}
			if (isset($line['extra_info']) && is_array($line['extra_info'])) {
				$line['extra_info']['allocations'] = $line['allocations'];
			}
		}

		return $line;
	}

	/**
	 * @param array $line
	 * @return array
	 */
	private static function flip_line_movement_in(array $line)
	{
		if (!isset($line['extra_info']) || !is_array($line['extra_info'])) {
			$line['extra_info'] = array();
		}
		$line['extra_info']['movement'] = 'in';

		return $line;
	}

	/**
	 * @param array $payload
	 * @return void
	 */
	private static function recompute_header_totals(array &$payload)
	{
		$gross = 0.0;
		$tax = 0.0;
		$net = 0.0;
		$lines = isset($payload['lines']) && is_array($payload['lines']) ? $payload['lines'] : array();
		foreach ($lines as $line) {
			if (!is_array($line)) {
				continue;
			}
			$ei = isset($line['extra_info']) && is_array($line['extra_info']) ? $line['extra_info'] : array();
			$qty = isset($line['quantity']) ? (float) $line['quantity'] : 0.0;
			$up = isset($ei['unit_price']) ? (float) $ei['unit_price'] : 0.0;
			$disc = isset($ei['line_discount']) ? (float) $ei['line_discount'] : 0.0;
			$ltax = isset($ei['tax_amount']) ? (float) $ei['tax_amount'] : 0.0;
			$lt = isset($ei['line_total']) ? (float) $ei['line_total'] : (($up * $qty) - $disc + $ltax);
			$gross += ($up * $qty) - $disc;
			$tax += $ltax;
			$net += $lt;
		}

		$adj_net = 0.0;
		$adj_tax = 0.0;
		$adjs = array();
		if (isset($payload['extra_info']['invoice_adjustments']) && is_array($payload['extra_info']['invoice_adjustments'])) {
			$adjs = $payload['extra_info']['invoice_adjustments'];
		}
		foreach ($adjs as $adj) {
			if (!is_array($adj)) {
				continue;
			}
			$amount = isset($adj['amount']) ? (float) $adj['amount'] : 0.0;
			$rate = isset($adj['tax_rate']) ? (float) $adj['tax_rate'] : 0.0;
			$sign = (isset($adj['kind']) && $adj['kind'] === 'subtraction') ? -1.0 : 1.0;
			$adj_net += $sign * $amount;
			$adj_tax += $sign * ($amount * $rate / 100.0);
		}

		$net += $adj_net + $adj_tax;
		if ($net < 0) {
			$net = 0.0;
		}

		$payload['extra_info']['totals'] = array(
			'gross' => (int) round($gross, 0),
			'discount' => 0,
			'tax' => (int) round($tax, 0),
			'net' => (int) round($net, 0),
			'adjustments_net' => (int) round($adj_net, 0),
			'adjustments_tax' => (int) round($adj_tax, 0),
		);
	}

	/**
	 * @param WC_Order $order
	 * @param float    $amount
	 * @param string   $reason
	 * @param int      $refund_id
	 * @return array
	 */
	private static function build_return_payments($order, $amount, $reason, $refund_id)
	{
		$amount = (int) round(abs((float) $amount), 0);
		if ($amount <= 0) {
			return array();
		}

		$desc = sprintf(
			/* translators: %s: WooCommerce order number */
			__('برگشت پرداخت سفارش #%s', 'hesabix-v2'),
			$order->get_order_number()
		);
		if ($refund_id > 0) {
			$desc = sprintf(
				/* translators: 1: order number, 2: refund id */
				__('بازپرداخت سفارش #%1$s (بازپرداخت %2$d)', 'hesabix-v2'),
				$order->get_order_number(),
				$refund_id
			);
		}

		$transaction_date = current_time('Y-m-d\TH:i:s.v');
		$destination = get_option('hesabix_v2_invoice_payment_destination', 'bank');
		if ($destination !== 'cash_register') {
			$destination = 'bank';
		}

		$payments = array();
		if ($destination === 'cash_register') {
			$cash_id = get_option('hesabix_v2_default_cash_register_id', '');
			if ($cash_id !== '' && $cash_id !== null && (int) $cash_id > 0) {
				$payments[] = array(
					'type' => 'cash_register',
					'transaction_type' => 'cash_register',
					'cash_register_id' => (string) (int) $cash_id,
					'amount' => $amount,
					'transaction_date' => $transaction_date,
					'description' => $desc,
				);
			} else {
				Hesabix_V2_Log_Service::warning(
					'Sales return: cash_register selected but none configured; payment omitted.',
					array('order_id' => (int) $order->get_id())
				);
			}
		} else {
			$bank_id = get_option('hesabix_v2_default_bank_id', '');
			if ($bank_id !== '' && $bank_id !== null) {
				$payments[] = array(
					'type' => 'bank',
					'transaction_type' => 'bank',
					'bank_id' => (string) $bank_id,
					'amount' => $amount,
					'transaction_date' => $transaction_date,
					'description' => $desc,
				);
			} else {
				Hesabix_V2_Log_Service::warning(
					'Sales return: bank selected but none configured; payment omitted.',
					array('order_id' => (int) $order->get_id())
				);
			}
		}

		return $payments;
	}

	/**
	 * @param WC_Order $order
	 * @param int      $order_id
	 * @return float
	 */
	private static function remaining_paid_amount($order, $order_id)
	{
		$had_payment = $order->is_paid()
			|| (bool) $order->get_date_paid()
			|| (float) $order->get_total_refunded() > 0;
		if (!$had_payment) {
			return 0.0;
		}

		$original = (float) $order->get_total() + (float) $order->get_total_refunded();
		if ($original <= 0) {
			return 0.0;
		}

		$db = new Hesabix_V2_DB_Service();
		$used = 0.0;
		foreach ($db->get_order_return_mappings((int) $order_id) as $row) {
			$meta = self::decode_meta($row);
			if (isset($meta['payment_amount'])) {
				$used += abs((float) $meta['payment_amount']);
			}
		}

		return max(0.0, $original - $used);
	}

	/**
	 * @param WC_Order              $order
	 * @param Hesabix_V2_DB_Service $db
	 * @param string                $reason
	 * @param int                   $refund_id
	 * @return array<string,float>
	 */
	private static function consumed_qty_map($order, $db, $reason, $refund_id)
	{
		$map = array();
		$order_id = (int) $order->get_id();
		foreach ($db->get_order_return_mappings($order_id) as $row) {
			$meta = self::decode_meta($row);
			$lines = isset($meta['lines']) && is_array($meta['lines']) ? $meta['lines'] : array();
			foreach ($lines as $ln) {
				if (!is_array($ln) || empty($ln['key'])) {
					continue;
				}
				$k = (string) $ln['key'];
				$q = isset($ln['quantity']) ? (float) $ln['quantity'] : 0.0;
				if (!isset($map[ $k ])) {
					$map[ $k ] = 0.0;
				}
				$map[ $k ] += $q;
			}
			if (!empty($meta['reason']) && empty($lines)) {
				continue;
			}
		}

		return $map;
	}

	/**
	 * @param WC_Order $order
	 * @return array<string,array{qty:float,kind:string}>
	 */
	private static function original_line_qty_map($order)
	{
		$map = array();
		foreach ($order->get_items() as $item) {
			$key = 'item:' . (int) $item->get_id();
			$map[ $key ] = array(
				'qty' => (float) $item->get_quantity(),
				'kind' => 'product',
			);
			$pid = (int) $item->get_product_id();
			$vid = (int) $item->get_variation_id();
			$fallback = 'product:' . $pid . ':' . $vid;
			if (!isset($map[ $fallback ])) {
				$map[ $fallback ] = array(
					'qty' => 0.0,
					'kind' => 'product',
				);
			}
			$map[ $fallback ]['qty'] += (float) $item->get_quantity();
		}

		if ((float) $order->get_shipping_total() > 0) {
			$map['kind:shipping'] = array(
				'qty' => 1.0,
				'kind' => 'shipping',
			);
		}

		foreach ($order->get_items('fee') as $fee_item) {
			$label = method_exists($fee_item, 'get_name') ? (string) $fee_item->get_name() : '';
			$key = 'fee:' . md5($label);
			$map[ $key ] = array(
				'qty' => 1.0,
				'kind' => 'fee',
			);
		}

		return $map;
	}

	/**
	 * @param WC_Order_Refund $refund
	 * @return array<string,float>
	 */
	private static function refund_qty_want_map($refund)
	{
		$want = array();
		$parent = null;
		$parent_id = method_exists($refund, 'get_parent_id') ? (int) $refund->get_parent_id() : 0;
		if ($parent_id > 0) {
			$parent = wc_get_order($parent_id);
		}

		foreach ($refund->get_items() as $item) {
			$qty = abs((float) $item->get_quantity());
			if ($qty <= 0) {
				continue;
			}
			$orig_id = 0;
			if (method_exists($item, 'get_meta')) {
				$orig_id = absint($item->get_meta('_refunded_item_id'));
			}
			if ($orig_id < 1 && $parent instanceof WC_Order) {
				$pid = method_exists($item, 'get_product_id') ? (int) $item->get_product_id() : 0;
				$vid = method_exists($item, 'get_variation_id') ? (int) $item->get_variation_id() : 0;
				foreach ($parent->get_items() as $orig_item) {
					if ((int) $orig_item->get_product_id() === $pid && (int) $orig_item->get_variation_id() === $vid) {
						$orig_id = (int) $orig_item->get_id();
						break;
					}
				}
			}
			if ($orig_id > 0) {
				$key = 'item:' . $orig_id;
				if (!isset($want[ $key ])) {
					$want[ $key ] = 0.0;
				}
				$want[ $key ] += $qty;
			}
		}

		if (abs((float) $refund->get_shipping_total()) > 0.00001 || !empty($refund->get_items('shipping'))) {
			$want['kind:shipping'] = 1.0;
		}

		foreach ($refund->get_items('fee') as $fee_item) {
			$label = method_exists($fee_item, 'get_name') ? (string) $fee_item->get_name() : '';
			$want[ 'fee:' . md5($label) ] = 1.0;
		}

		return $want;
	}

	/**
	 * @param WC_Order_Refund $refund
	 * @param array           $want
	 * @param bool            $has_items
	 * @return bool
	 */
	private static function refund_includes_shipping($refund, array $want, $has_items)
	{
		if (abs((float) $refund->get_shipping_total()) > 0.00001) {
			return true;
		}
		$ships = $refund->get_items('shipping');
		if (!empty($ships)) {
			return true;
		}
		if (!$has_items && abs((float) $refund->get_total()) > 0) {
			return true;
		}

		return false;
	}

	/**
	 * @param WC_Order_Refund $refund
	 * @param array           $want
	 * @param bool            $has_items
	 * @return bool
	 */
	private static function refund_includes_fees($refund, array $want, $has_items)
	{
		$fees = $refund->get_items('fee');
		if (!empty($fees)) {
			return true;
		}
		if (!$has_items && abs((float) $refund->get_total()) > 0) {
			return true;
		}

		return false;
	}

	/**
	 * @param array<string,array{qty:float,kind:string}> $original
	 * @param array<string,float>                         $consumed
	 * @return array<string,float>
	 */
	private static function remaining_qty_map(array $original, array $consumed)
	{
		$out = array();
		foreach ($original as $key => $row) {
			$left = (float) $row['qty'] - (isset($consumed[ $key ]) ? (float) $consumed[ $key ] : 0.0);
			if ($left > 0.00001) {
				$out[ $key ] = $left;
			}
		}

		return $out;
	}

	/**
	 * @param array<string,float> $map
	 * @param float               $factor
	 * @return array<string,float>
	 */
	private static function scale_qty_map(array $map, $factor)
	{
		$factor = (float) $factor;
		$out = array();
		foreach ($map as $k => $q) {
			$v = (float) $q * $factor;
			if ($v > 0.00001) {
				$out[ $k ] = $v;
			}
		}

		return $out;
	}

	/**
	 * @param WC_Order            $order
	 * @param array<string,float> $consumed
	 * @param array               $original_lines
	 * @return float
	 */
	private static function remaining_net_amount($order, array $consumed, array $original_lines)
	{
		$total = (float) $order->get_total() + (float) $order->get_total_refunded();
		$used_ratio = 0.0;
		$orig_sum = 0.0;
		$used_sum = 0.0;
		foreach ($original_lines as $key => $row) {
			if (($row['kind'] ?? '') !== 'product') {
				continue;
			}
			$orig_sum += (float) $row['qty'];
			$used_sum += isset($consumed[ $key ]) && strpos($key, 'item:') === 0 ? (float) $consumed[ $key ] : 0.0;
		}
		if ($orig_sum > 0) {
			$used_ratio = min(1.0, $used_sum / $orig_sum);
		}

		return max(0.0, $total * (1.0 - $used_ratio));
	}

	/**
	 * @param array $line
	 * @return string
	 */
	private static function line_key(array $line)
	{
		$ei = isset($line['extra_info']) && is_array($line['extra_info']) ? $line['extra_info'] : array();
		$kind = isset($ei['wc_line_kind']) ? (string) $ei['wc_line_kind'] : 'product';
		if ($kind === 'shipping') {
			return 'kind:shipping';
		}
		if ($kind === 'fee') {
			$label = isset($ei['wc_fee_label']) ? (string) $ei['wc_fee_label'] : '';
			return 'fee:' . md5($label);
		}
		$item_id = isset($ei['wc_item_id']) ? (int) $ei['wc_item_id'] : 0;
		if ($item_id > 0) {
			return 'item:' . $item_id;
		}
		$wpid = isset($ei['wc_product_id']) ? (int) $ei['wc_product_id'] : 0;
		$wvid = isset($ei['wc_variation_id']) ? (int) $ei['wc_variation_id'] : 0;
		if ($wpid > 0) {
			return 'product:' . $wpid . ':' . $wvid;
		}
		$pid = isset($line['product_id']) ? (int) $line['product_id'] : 0;
		$vid = 0;
		if (!empty($line['allocations'][0]['variant_id'])) {
			$vid = (int) $line['allocations'][0]['variant_id'];
		}

		return 'product:' . $pid . ':' . $vid;
	}

	/**
	 * @param WC_Order              $order
	 * @param Hesabix_V2_DB_Service $db
	 * @param array                 $invoice
	 * @return int
	 */
	private static function resolve_person_id($order, $db, array $invoice)
	{
		$extra = array();
		if (isset($invoice['extra_info']) && is_array($invoice['extra_info'])) {
			$extra = $invoice['extra_info'];
		}
		if (!empty($extra['person_id'])) {
			return (int) $extra['person_id'];
		}

		$customer_id = (int) $order->get_customer_id();
		if ($customer_id > 0) {
			$pid = $db->get_hesabix_id('customer', $customer_id);
			if ($pid) {
				return (int) $pid;
			}
		}

		$guest = $db->get_hesabix_id('customer', (int) $order->get_id(), (int) $order->get_id());
		if ($guest) {
			return (int) $guest;
		}

		$guest2 = $db->get_mapping('customer', (int) $order->get_id(), null);

		return $guest2 && !empty($guest2['hesabix_id']) ? (int) $guest2['hesabix_id'] : 0;
	}

	/**
	 * @param array $res
	 * @return array|null
	 */
	private static function unwrap_invoice($res)
	{
		if (!is_array($res) || empty($res['success'])) {
			return null;
		}
		$data = isset($res['data']) && is_array($res['data']) ? $res['data'] : array();
		if (isset($data['item']) && is_array($data['item'])) {
			return $data['item'];
		}
		if (isset($data['id']) || isset($data['invoice_type']) || isset($data['document_type'])) {
			return $data;
		}

		return !empty($data) ? $data : null;
	}

	/**
	 * @param array $invoice
	 * @return bool
	 */
	private static function invoice_is_proforma(array $invoice)
	{
		if (!empty($invoice['is_proforma'])) {
			return true;
		}
		if (isset($invoice['extra_info']) && is_array($invoice['extra_info']) && !empty($invoice['extra_info']['is_proforma'])) {
			return true;
		}

		return false;
	}

	/**
	 * @param string $msg
	 * @return bool
	 */
	private static function looks_like_not_found($msg)
	{
		$msg = mb_strtolower((string) $msg);
		if ($msg === '') {
			return false;
		}

		return (strpos($msg, 'not found') !== false)
			|| (strpos($msg, '404') !== false)
			|| (strpos($msg, 'پیدا نشد') !== false)
			|| (strpos($msg, 'یافت نشد') !== false);
	}

	/**
	 * @param array $row
	 * @return array
	 */
	private static function decode_meta(array $row)
	{
		if (empty($row['meta_data'])) {
			return array();
		}
		if (is_array($row['meta_data'])) {
			return $row['meta_data'];
		}
		$decoded = json_decode((string) $row['meta_data'], true);

		return is_array($decoded) ? $decoded : array();
	}

	/**
	 * @param string $reason
	 * @return string
	 */
	private static function reason_label($reason)
	{
		switch ((string) $reason) {
			case self::REASON_REFUND:
				return __('بازپرداخت ووکامرس', 'hesabix-v2');
			case self::REASON_DELETE:
				return __('حذف دائمی سفارش', 'hesabix-v2');
			case self::REASON_UNSYNC:
				return __('لغو ارسال', 'hesabix-v2');
			case self::REASON_REFUNDED_STATUS:
				return __('وضعیت بازپرداخت‌شده', 'hesabix-v2');
			case self::REASON_CANCEL:
			default:
				return __('لغو سفارش', 'hesabix-v2');
		}
	}
}
