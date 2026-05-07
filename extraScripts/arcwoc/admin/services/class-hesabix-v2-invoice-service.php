<?php
/**
 * Invoice Service
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Invoice_Service
{
	/**
	 * Get all WooCommerce orders
	 *
	 * @since    2.0.0
	 * @param    array    $args
	 * @return   array
	 */
	public static function get_all_orders($args = array())
	{
		$default_args = array(
			'limit' => -1,
			'return' => 'ids',
		);

		$args = array_merge($default_args, $args);
		
		return wc_get_orders($args);
	}

	/**
	 * Get sync status for order
	 *
	 * @since    2.0.0
	 * @param    int    $order_id
	 * @return   array|null
	 */
	public static function get_sync_status($order_id)
	{
		$db = new Hesabix_V2_DB_Service();
		return $db->get_mapping('order', $order_id);
	}

	/**
	 * Get orders by status
	 *
	 * @since    2.0.0
	 * @param    string|array    $status
	 * @return   array
	 */
	public static function get_orders_by_status($status)
	{
		return wc_get_orders(array(
			'status' => $status,
			'limit' => -1,
			'return' => 'ids',
		));
	}

	/**
	 * حذف فاکتور حسابیکس، نگاشت، صف، و فلگ توقف خودکار؛ یادداشت روی سفارش.
	 *
	 * @param int $order_id
	 * @return array{success:bool,message:string,already_gone?:bool}
	 */
	public static function unsync_order_from_hesabix($order_id)
	{
		$order_id = (int) $order_id;
		$order = wc_get_order($order_id);
		if (!$order) {
			return array(
				'success' => false,
				'message' => __('سفارش یافت نشد.', 'hesabix-v2'),
			);
		}

		$db = new Hesabix_V2_DB_Service();
		$map = $db->get_mapping('order', $order_id);
		Hesabix_V2_Queue_Service::cancel_pending_for_order($order_id);

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

		$invoice_id = (int) $map['hesabix_id'];
		$api = new Hesabix_V2_Api();
		$res = $api->delete_invoice($invoice_id);

		if (empty($res['success'])) {
			$msg = isset($res['message']) ? (string) $res['message'] : __('حذف فاکتور در حسابیکس ناموفق بود.', 'hesabix-v2');
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
				/* translators: %d: Hesabix invoice id */
				__('ارسال به حسابیکس لغو شد؛ فاکتور %d حذف شد.', 'hesabix-v2'),
				$invoice_id
			)
		);

		Hesabix_V2_Log_Service::info('Order unsynced from Hesabix (invoice deleted)', array(
			'entity_type' => 'order',
			'entity_id' => $order_id,
			'hesabix_invoice_id' => $invoice_id,
		));

		return array(
			'success' => true,
			'message' => __('فاکتور در حسابیکس حذف و ارتباط در افزونه پاک شد.', 'hesabix-v2'),
		);
	}
}

