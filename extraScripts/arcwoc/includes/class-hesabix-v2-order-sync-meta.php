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
	 * اثر انگشت همگام‌سازی «دریافت همراه فاکتور» برای پرهیز از حذف/ایجاد مکرر سند در API با هر بار به‌روزرسانی.
	 *
	 * @var string
	 */
	const META_RP_SYNC_FP = '_hesabix_v2_invoice_rp_sync_fp';

	/**
	 * متا برای شناسهٔ نظر واحد «وضعیت همگام‌سازی حسابیکس»: ارز، سال مالی، خطای فاکتور؛ با هر رویداد همان نظر به‌روز می‌شود.
	 */
	const META_ORDER_SYSTEM_NOTE = '_hesabix_v2_order_system_note_id';

	/** @var string نسخهٔ قدیمی متای خطای فاکتور؛ فقط خوانده می‌شود و هنگام ثبت نظر جدید حذف می‌گردد */
	const LEGACY_META_INVOICE_SYNC_ERROR_NOTE = '_hesabix_v2_invoice_sync_error_note_id';

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

		// هوک woocommerce_update_order در حین ذخیرهٔ اصلی سفارش: save() تمام شیء خطر حلقه با افزونه‌هایی
		// (مثلاً Yoast کش نقشه سایت بعد از پاک‌کردن کش پست هنگام همگام‌سازی CPT/HPOS) دارد؛ فقط متادیتا را بنویسیم.
		if (doing_action('woocommerce_update_order')) {
			$order->save_meta_data();

			return true;
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

		$order = wc_get_order((int) $order_id);
		if ($order) {
			self::clear_rp_sync_fp($order);
			self::remove_order_system_note($order);
		}
	}

	/**
	 * اثر انگشت پارامترهایی که رفتار ثبت دریافت ووکامرس را تعیین می‌کنند (بدون هَش کردن کل خطوط فاکتور).
	 *
	 * @param WC_Order $order
	 * @param int      $hesabix_invoice_id
	 * @param array    $invoice_data خروجی mapper بعد از فیلتر hesabix_v2_invoice_data
	 * @return string sha256 hex
	 */
	public static function compute_invoice_rp_sync_fingerprint($order, $hesabix_invoice_id, array $invoice_data)
	{
		$hid = absint((string) $hesabix_invoice_id);
		$ei = isset($invoice_data['extra_info']) && is_array($invoice_data['extra_info']) ? $invoice_data['extra_info'] : array();
		$totals = isset($ei['totals']) && is_array($ei['totals']) ? $ei['totals'] : array();
		$net = isset($totals['net']) ? (int) $totals['net'] : 0;
		$currency_id = isset($invoice_data['currency_id']) ? (int) $invoice_data['currency_id'] : 0;
		$is_pf = !empty($invoice_data['is_proforma']);

		$dest = get_option('hesabix_v2_invoice_payment_destination', 'bank');
		$dest = ($dest === 'cash_register') ? 'cash_register' : 'bank';
		$account_ref = '';
		if ($dest === 'cash_register') {
			$account_ref = (string) absint((string) get_option('hesabix_v2_default_cash_register_id', ''));
		} else {
			$account_ref = trim((string) get_option('hesabix_v2_default_bank_id', ''));
		}

		$parts = array(
			'v1',
			(string) $hid,
			(string) $net,
			(string) $currency_id,
			$is_pf ? '1' : '0',
			$dest,
			$account_ref,
			is_object($order) && method_exists($order, 'is_paid') && $order->is_paid() ? '1' : '0',
		);

		return hash('sha256', implode('|', $parts));
	}

	/**
	 * قبل از ایجاد/به‌روزرسانی فاکتور: اگر قبلاً با همین اثر انگشت دریافت ثبت شده، کلید payments حذف می‌شود تا
	 * API دیگر اسناد پیوندخوردهٔ قبلی را حذف/جدید نکند (اسناد دستی که در لیست پیوند فاکتور نیستند دست‌نخورده می‌مانند).
	 *
	 * @param WC_Order   $order
	 * @param int|null   $hesabix_invoice_id برای ایجاد فاکتور تازه null یا ۰
	 * @param array      $invoice_data
	 * @return array{had_positive_rp:bool,omitted_payments:bool}
	 */
	public static function maybe_omit_repeat_invoice_payments($order, $hesabix_invoice_id, array &$invoice_data)
	{
		$had_positive_rp = false;
		if (isset($invoice_data['payments']) && is_array($invoice_data['payments'])) {
			foreach ($invoice_data['payments'] as $p) {
				if (!is_array($p)) {
					continue;
				}
				if ((float) ($p['amount'] ?? 0) > 0) {
					$had_positive_rp = true;
					break;
				}
			}
		}

		$omitted = false;
		$hid = absint((string) ($hesabix_invoice_id ?? 0));
		if ($hid > 0 && $had_positive_rp && is_object($order) && ($order instanceof WC_Order)) {
			$fp = self::compute_invoice_rp_sync_fingerprint($order, $hid, $invoice_data);
			$stored = (string) $order->get_meta(self::META_RP_SYNC_FP, true);
			if ($stored !== '' && hash_equals($stored, $fp)) {
				unset($invoice_data['payments']);
				$omitted = true;
			}
		}

		return array(
			'had_positive_rp' => $had_positive_rp,
			'omitted_payments' => $omitted,
		);
	}

	/**
	 * پس از پاسخ موفق API فاکتور.
	 *
	 * @param WC_Order $order
	 * @param array    $rp_gate خروجی {@see maybe_omit_repeat_invoice_payments}
	 * @param array    $invoice_data همان آرایهٔ نهایی ارسالی (بعد از حذف اختیاری payments)
	 * @param int      $hesabix_invoice_id
	 */
	public static function persist_rp_sync_state_after_invoice_success($order, array $rp_gate, array $invoice_data, $hesabix_invoice_id)
	{
		if (!is_object($order) || !($order instanceof WC_Order)) {
			return;
		}

		if (!empty($rp_gate['omitted_payments'])) {
			return;
		}

		if (empty($rp_gate['had_positive_rp'])) {
			self::clear_rp_sync_fp($order);

			return;
		}

		$hid = absint((string) $hesabix_invoice_id);
		if ($hid < 1) {
			return;
		}

		self::set_rp_sync_fp($order, self::compute_invoice_rp_sync_fingerprint($order, $hid, $invoice_data));
	}

	/**
	 * @param WC_Order $order
	 * @param string   $fp sha256 hex
	 */
	public static function set_rp_sync_fp($order, $fp)
	{
		if (!is_object($order) || !($order instanceof WC_Order)) {
			return;
		}

		$fp = is_string($fp) ? trim($fp) : '';
		if ($fp === '') {
			self::clear_rp_sync_fp($order);

			return;
		}

		$order->update_meta_data(self::META_RP_SYNC_FP, $fp);
		self::persist_order_meta_simple($order);
	}

	/**
	 * @param WC_Order $order
	 */
	public static function clear_rp_sync_fp($order)
	{
		if (!is_object($order) || !($order instanceof WC_Order)) {
			return;
		}

		$order->delete_meta_data(self::META_RP_SYNC_FP);
		self::persist_order_meta_simple($order);
	}

	/**
	 * ذخیرهٔ متای سفارش بدون risk در هوک woocommerce_update_order.
	 *
	 * @param WC_Order $order
	 */
	private static function persist_order_meta_simple($order)
	{
		if (doing_action('woocommerce_update_order')) {
			$order->save_meta_data();

			return;
		}

		$order->save();
	}

	/**
	 * @param WC_Order $order
	 * @return int
	 */
	private static function get_stored_system_note_id($order)
	{
		$nid = absint((string) $order->get_meta(self::META_ORDER_SYSTEM_NOTE, true));
		if ($nid > 0) {
			return $nid;
		}

		return absint((string) $order->get_meta(self::LEGACY_META_INVOICE_SYNC_ERROR_NOTE, true));
	}

	/**
	 * @param WC_Order $order
	 * @return void
	 */
	private static function persist_order_meta_after_note_change($order)
	{
		if (doing_action('woocommerce_update_order')) {
			$order->save_meta_data();
		} else {
			$order->save();
		}
	}

	/**
	 * یک یادداشت واحد از طرف افزونه: متن کامل قبلاً ترجمه/قالب شده باشد؛ در صورت وجود نظر قبلی متن آن به‌روز می‌شود.
	 *
	 * @param WC_Order $order
	 * @param string   $content متن یادداشت کامل برای نمایش در سفارش
	 */
	public static function set_or_update_order_system_note($order, $content)
	{
		if (!is_object($order) || !($order instanceof WC_Order)) {
			return;
		}

		$content = wp_strip_all_tags((string) $content);
		if (mb_strlen($content) > 2500) {
			$content = mb_substr($content, 0, 2497) . '…';
		}

		$note_id = self::get_stored_system_note_id($order);
		if ($note_id > 0) {
			$c = get_comment($note_id);
			if (
				is_object($c)
				&& (int) $c->comment_post_ID === (int) $order->get_id()
				&& (($c->comment_type ?? '') === 'order_note' || ($c->comment_type ?? '') === '')
			) {
				wp_update_comment(
					array(
						'comment_ID' => $note_id,
						'comment_content' => $content,
						'comment_date' => current_time('mysql'),
						'comment_date_gmt' => current_time('mysql', 1),
					)
				);

				if ($order->meta_exists(self::LEGACY_META_INVOICE_SYNC_ERROR_NOTE)) {
					$order->delete_meta_data(self::LEGACY_META_INVOICE_SYNC_ERROR_NOTE);
					self::persist_order_meta_after_note_change($order);
				}

				return;
			}
		}

		$new_id = (int) $order->add_order_note($content, false);
		if ($new_id > 0) {
			$order->update_meta_data(self::META_ORDER_SYSTEM_NOTE, (string) $new_id);
			$order->delete_meta_data(self::LEGACY_META_INVOICE_SYNC_ERROR_NOTE);
			self::persist_order_meta_after_note_change($order);
		}
	}

	/**
	 * پیام خطای ایجاد/به‌روزرسانی فاکتور؛ همان یادداشت تجمیعی سفارش را به‌روز می‌کند.
	 *
	 * @param WC_Order $order
	 * @param string   $exception_message پیام خام استثناء (بدون پیشوند افزونه)
	 */
	public static function set_or_update_invoice_sync_error_note($order, $exception_message)
	{
		$body = sanitize_text_field(wp_strip_all_tags((string) $exception_message));
		if (mb_strlen($body) > 2000) {
			$body = mb_substr($body, 0, 1997) . '…';
		}

		$content = sprintf(
			__('خطا در ایجاد فاکتور حسابیکس: %s', 'hesabix-v2'),
			$body
		);

		self::set_or_update_order_system_note($order, $content);
	}

	/**
	 * پس از موفقیت همگام‌سازی فاکتور یا لغو ارسال: حذف یادداشت تجمیعی و متای آن.
	 *
	 * @param WC_Order $order
	 */
	public static function remove_order_system_note($order)
	{
		if (!is_object($order) || !($order instanceof WC_Order)) {
			return;
		}

		$note_id = self::get_stored_system_note_id($order);
		if ($note_id > 0) {
			$c = get_comment($note_id);
			if (is_object($c) && (int) $c->comment_post_ID === (int) $order->get_id()) {
				wp_delete_comment($note_id, true);
			}
		}

		$order->delete_meta_data(self::META_ORDER_SYSTEM_NOTE);
		$order->delete_meta_data(self::LEGACY_META_INVOICE_SYNC_ERROR_NOTE);

		self::persist_order_meta_after_note_change($order);
	}

	/**
	 * @param WC_Order $order
	 * @deprecated سازگاری عقب‌رو؛ از {@see remove_order_system_note} استفاده کنید.
	 */
	public static function remove_invoice_sync_error_note($order)
	{
		self::remove_order_system_note($order);
	}
}
