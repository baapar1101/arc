<?php
/**
 * وضعیت استثناء سفارش از همگام‌سازی خودکار با حسابیکس (مثلاً پس از ویرایش دستی فاکتور).
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Order_Sync_Meta
{
	/** @var string meta روی WC_Order — مقدار '1' یعنی توقف همگام‌سازی خودکار */
	const META_PAUSE_AUTO = '_hesabix_v2_pause_auto_sync';

	/**
	 * آیا همگام‌سازی خودکار (هوک‌ها و صف) برای این سفارش رد شود؟
	 *
	 * @param int $order_id
	 * @return bool
	 */
	public static function is_pause_auto_sync($order_id)
	{
		$order_id = (int) $order_id;
		if ($order_id < 1) {
			return false;
		}
		$order = wc_get_order($order_id);
		if (!$order) {
			return false;
		}
		$v = $order->get_meta(self::META_PAUSE_AUTO, true);
		return $v === '1' || $v === 1 || $v === true;
	}

	/**
	 * تنظیم یا حذف فلگ توقف همگام‌سازی خودکار.
	 *
	 * @param int  $order_id
	 * @param bool $pause
	 * @return bool
	 */
	public static function set_pause_auto_sync($order_id, $pause)
	{
		$order_id = (int) $order_id;
		$order = wc_get_order($order_id);
		if (!$order) {
			return false;
		}
		if ($pause) {
			$order->update_meta_data(self::META_PAUSE_AUTO, '1');
		} else {
			$order->delete_meta_data(self::META_PAUSE_AUTO);
		}
		$order->save();
		return true;
	}

	/**
	 * بعد از لغو ارسال (حذف فاکتور) فلگ را پاک کن تا رفتار پیش‌فرض برگردد.
	 *
	 * @param int $order_id
	 * @return void
	 */
	public static function clear_on_unsync($order_id)
	{
		self::set_pause_auto_sync((int) $order_id, false);
	}
}
