<?php
/**
 * بازهٔ سال مالی جاری حسابیکس و اعمال سیاست تاریخ روی همگام‌سازی سفارش.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Order_Fiscal_Service
{
	/**
	 * مدت نگهداری کش بازهٔ سال مالی (ثانیه).
	 */
	const CACHE_TTL = 3600;

	/**
	 * حذف کش بازهٔ سال مالی برای کسب‌وکار ذخیره‌شده.
	 *
	 * @return void
	 */
	public static function invalidate_bounds_cache()
	{
		$bid = (int) get_option('hesabix_v2_business_id');
		if ($bid > 0) {
			delete_transient('hesabix_v2_fy_bounds_' . $bid);
		}
	}

	/**
	 * دریافت تاریخ شروع/پایان سال مالی جاری (با کش).
	 *
	 * @param Hesabix_V2_Api $api
	 * @return array{ok:bool,start:?string,end:?string,message:string}
	 */
	public static function get_current_fiscal_year_bounds(Hesabix_V2_Api $api)
	{
		$bid = (int) get_option('hesabix_v2_business_id');
		if ($bid <= 0) {
			return array(
				'ok' => false,
				'start' => null,
				'end' => null,
				'message' => __('کسب‌وکار در تنظیمات افزونه مشخص نیست.', 'hesabix-v2'),
			);
		}

		$key = 'hesabix_v2_fy_bounds_' . $bid;
		$cached = get_transient($key);
		if (is_array($cached) && !empty($cached['start']) && is_string($cached['start'])) {
			$end = isset($cached['end']) && is_string($cached['end']) && $cached['end'] !== ''
				? $cached['end']
				: null;
			return array(
				'ok' => true,
				'start' => $cached['start'],
				'end' => $end,
				'message' => '',
			);
		}

		$res = $api->get_current_fiscal_year($bid);
		$data = (is_array($res) && !empty($res['success']) && isset($res['data']) && is_array($res['data']))
			? $res['data']
			: null;

		if ($data === null || $data === array()) {
			$msg = isset($res['message']) ? (string) $res['message'] : __('دریافت سال مالی جاری ناموفق بود.', 'hesabix-v2');
			return array(
				'ok' => false,
				'start' => null,
				'end' => null,
				'message' => $msg,
			);
		}

		$start = self::normalize_api_date($data['start_date'] ?? null);
		$end = self::normalize_api_date($data['end_date'] ?? null);
		if ($start === null) {
			return array(
				'ok' => false,
				'start' => null,
				'end' => null,
				'message' => __('تاریخ شروع سال مالی در پاسخ حسابیکس نیست.', 'hesabix-v2'),
			);
		}

		$payload = array('start' => $start);
		if ($end !== null) {
			$payload['end'] = $end;
		}
		set_transient($key, $payload, self::CACHE_TTL);

		return array(
			'ok' => true,
			'start' => $start,
			'end' => $end,
			'message' => '',
		);
	}

	/**
	 * @param mixed $val
	 * @return string|null Y-m-d
	 */
	private static function normalize_api_date($val)
	{
		if ($val === null || $val === '') {
			return null;
		}
		if (is_string($val)) {
			$val = trim($val);
			if (strlen($val) >= 10) {
				return substr($val, 0, 10);
			}
		}
		return null;
	}

	/**
	 * تاریخ ایجاد سفارش به‌صورت Y-m-d (زمان محلی ووکامرس).
	 *
	 * @param WC_Order $order
	 * @return string
	 */
	public static function order_created_ymd($order)
	{
		if (!$order || !is_a($order, 'WC_Order')) {
			return current_time('Y-m-d');
		}
		$d = $order->get_date_created();
		return $d ? $d->date('Y-m-d') : current_time('Y-m-d');
	}

	/**
	 * اعمال سیاست تاریخ نسبت به سال مالی قبل از ساخت بدنهٔ فاکتور.
	 *
	 * @param WC_Order       $order
	 * @param string         $policy keep|clamp|skip
	 * @param Hesabix_V2_Api $api
	 * @return array{
	 *   skip:bool,
	 *   skip_message?:string,
	 *   document_date:?string,
	 *   payment_date_ymd:?string,
	 *   note:string,
	 *   fallback?:bool
	 * }
	 */
	public static function resolve_for_sync($order, $policy, Hesabix_V2_Api $api)
	{
		$policy = sanitize_key((string) $policy);
		if ($policy === '' || $policy === 'keep') {
			return array(
				'skip' => false,
				'document_date' => null,
				'payment_date_ymd' => null,
				'note' => '',
			);
		}

		$bounds = self::get_current_fiscal_year_bounds($api);
		if (!$bounds['ok']) {
			Hesabix_V2_Log_Service::warning(
				'Order fiscal policy: year bounds unavailable; using WooCommerce dates',
				array(
					'entity_type' => 'order',
					'entity_id' => $order->get_id(),
					'policy' => $policy,
					'detail' => $bounds['message'],
				)
			);
			return array(
				'skip' => false,
				'document_date' => null,
				'payment_date_ymd' => null,
				'note' => '',
				'fallback' => true,
			);
		}

		$start = $bounds['start'];
		$end = $bounds['end'];
		if ($end === null || $end === '') {
			$end = '9999-12-31';
		}
		if (strcmp($start, $end) > 0) {
			Hesabix_V2_Log_Service::warning(
				'Order fiscal policy: invalid fiscal range (start after end)',
				array(
					'entity_type' => 'order',
					'entity_id' => $order->get_id(),
					'start' => $start,
					'end' => $end,
				)
			);
			return array(
				'skip' => false,
				'document_date' => null,
				'payment_date_ymd' => null,
				'note' => '',
				'fallback' => true,
			);
		}

		$created = self::order_created_ymd($order);
		$cmp_s = strcmp($created, $start);
		$cmp_e = strcmp($created, $end);
		$inside = ($cmp_s >= 0 && $cmp_e <= 0);

		if ($policy === 'skip') {
			if ($inside) {
				return array(
					'skip' => false,
					'document_date' => null,
					'payment_date_ymd' => null,
					'note' => '',
				);
			}
			$end_label = ($bounds['end'] !== null && $bounds['end'] !== '') ? $bounds['end'] : __('بدون تاریخ پایان', 'hesabix-v2');
			return array(
				'skip' => true,
				'skip_message' => sprintf(
					/* translators: 1: order date Y-m-d, 2: fiscal start, 3: fiscal end or em dash */
					__('تاریخ سفارش (%1$s) خارج از سال مالی جاری (%2$s تا %3$s) است؛ طبق تنظیمات همگام‌سازی انجام نشد.', 'hesabix-v2'),
					$created,
					$start,
					$end_label
				),
			);
		}

		if ($policy === 'clamp') {
			if ($inside) {
				return array(
					'skip' => false,
					'document_date' => null,
					'payment_date_ymd' => null,
					'note' => '',
				);
			}
			$doc = $created;
			$adjusted = false;
			if ($cmp_s < 0) {
				$doc = $start;
				$adjusted = true;
			} elseif ($cmp_e > 0) {
				$doc = $end;
				$adjusted = true;
			}
			$pay_ymd = null;
			if ($adjusted && $order->is_paid()) {
				$pay_ymd = $doc;
			}
			$note = '';
			if ($adjusted) {
				$note = sprintf(
					/* translators: 1: original order date, 2: document date sent to Hesabix */
					__('تاریخ فاکتور حسابیکس از %1$s به %2$s (مطابق بازهٔ سال مالی جاری) اصلاح شد.', 'hesabix-v2'),
					$created,
					$doc
				);
			}
			return array(
				'skip' => false,
				'document_date' => $adjusted ? $doc : null,
				'payment_date_ymd' => $pay_ymd,
				'note' => $note,
			);
		}

		return array(
			'skip' => false,
			'document_date' => null,
			'payment_date_ymd' => null,
			'note' => '',
		);
	}
}
