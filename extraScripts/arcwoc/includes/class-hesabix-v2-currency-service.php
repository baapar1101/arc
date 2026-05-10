<?php
/**
 * ارز فاکتور، فهرست ارزهای کسب‌وکار، تطبیق با ووکامرس، تبدیل تومان→ریال.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Currency_Service
{
	/**
	 * کش لیست ارزهای کسب‌وکار (ثانیه).
	 */
	const LIST_CACHE_TTL = 300;

	/**
	 * کلید ترنزینت لیست ارز بر اساس شناسهٔ کسب‌وکار.
	 *
	 * @return string
	 */
	private static function list_transient_key()
	{
		return 'hesabix_v2_bc_' . (int) get_option('hesabix_v2_business_id');
	}

	/**
	 * پاک کردن کش لیست ارزها (پس از ذخیرهٔ تنظیمات یا تغییر اتصال).
	 *
	 * @return void
	 */
	public static function invalidate_list_cache()
	{
		delete_transient(self::list_transient_key());
	}

	/**
	 * استخراج ردیف‌های ارز از پاسخ API.
	 *
	 * @param array $res
	 * @return array<int, array{id:int,code:string,title:string,name:string,is_default:bool}>
	 */
	public static function normalize_rows_from_api_response($res)
	{
		if (!is_array($res) || empty($res['success'])) {
			return array();
		}

		$data = isset($res['data']) ? $res['data'] : null;
		$items = array();
		if (is_array($data)) {
			if (isset($data['items']) && is_array($data['items'])) {
				$items = $data['items'];
			} else {
				$keys = array_keys($data);
				$numeric_keys = true;
				foreach ($keys as $i => $k) {
					if ((string) $k !== (string) $i) {
						$numeric_keys = false;
						break;
					}
				}
				if ($numeric_keys && !empty($keys)) {
					$items = $data;
				}
			}
		}

		$out = array();
		foreach ($items as $row) {
			if (!is_array($row) || empty($row['id'])) {
				continue;
			}
			$code = isset($row['code']) ? strtoupper(trim((string) $row['code'])) : '';
			$out[] = array(
				'id' => (int) $row['id'],
				'code' => $code,
				'title' => isset($row['title']) ? (string) $row['title'] : '',
				'name' => isset($row['name']) ? (string) $row['name'] : '',
				'is_default' => !empty($row['is_default']),
			);
		}

		return $out;
	}

	/**
	 * دریافت لیست ارزهای کسب‌وکار (با کش).
	 *
	 * @param Hesabix_V2_Api|null $api
	 * @return array<int, array{id:int,code:string,title:string,name:string,is_default:bool}>
	 */
	public static function get_business_currency_rows(Hesabix_V2_Api $api = null)
	{
		$key = self::list_transient_key();
		$cached = get_transient($key);
		if ($cached !== false && is_array($cached)) {
			return $cached;
		}

		$api = $api ?: new Hesabix_V2_Api();
		$res = $api->get_business_currencies();
		$rows = self::normalize_rows_from_api_response($res);
		if (!empty($rows)) {
			set_transient($key, $rows, self::LIST_CACHE_TTL);
		}

		return $rows;
	}

	/**
	 * ارز انتخاب‌شده در تنظیمات افزونه یا پیش‌فرض کسب‌وکار.
	 *
	 * @param Hesabix_V2_Api|null $api
	 * @return array{id:int,code:string,title:string,name:string,is_default:bool}|null
	 */
	public static function resolve_invoice_currency_row(Hesabix_V2_Api $api = null)
	{
		$rows = self::get_business_currency_rows($api);
		if (empty($rows)) {
			return null;
		}

		$opt = (int) get_option('hesabix_v2_currency_id', 0);
		if ($opt > 0) {
			foreach ($rows as $r) {
				if ((int) $r['id'] === $opt) {
					return $r;
				}
			}

			return null;
		}

		foreach ($rows as $r) {
			if (!empty($r['is_default'])) {
				return $r;
			}
		}

		return $rows[0];
	}

	/**
	 * شناسهٔ ارز برای فاکتور.
	 *
	 * @param Hesabix_V2_Api|null $api
	 * @return int
	 */
	public static function resolve_invoice_currency_id(Hesabix_V2_Api $api = null)
	{
		$row = self::resolve_invoice_currency_row($api);
		if ($row) {
			return (int) $row['id'];
		}

		$fallback = (int) get_option('hesabix_v2_currency_id', 0);

		return $fallback > 0 ? $fallback : 1;
	}

	/**
	 * کد ارز فروشگاه ووکامرس.
	 *
	 * @param string|null $override از سفارش یا همگام‌سازی.
	 * @return string
	 */
	public static function get_wc_currency_code($override = null)
	{
		if ($override !== null && $override !== '') {
			return strtoupper(trim((string) $override));
		}

		if (function_exists('get_woocommerce_currency')) {
			return strtoupper(trim((string) get_woocommerce_currency()));
		}

		return '';
	}

	/**
	 * آیا کد ارز ووکامرس به‌منزلهٔ تومان در نظر گرفته شود (IRT، TMN، …).
	 *
	 * @param string $code
	 * @return bool
	 */
	public static function wc_code_is_toman($code)
	{
		$c = strtoupper(trim((string) $code));
		$tomans = apply_filters('hesabix_v2_wc_toman_currency_codes', array('IRT', 'TMN'));

		return in_array($c, array_map('strtoupper', (array) $tomans), true);
	}

	/**
	 * ارزیابی هم‌خوانی ارز ووکامرس با ارز فاکتور حسابیکس و ضریب تبدیل مبلغ.
	 *
	 * @param Hesabix_V2_Api|null $api
	 * @param string|null         $wc_currency_override
	 * @return array{ok:bool,factor:float,currency_id:int,message:string,currency_blocked?:bool}
	 */
	public static function evaluate_currency_sync(Hesabix_V2_Api $api = null, $wc_currency_override = null)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return array(
				'ok' => false,
				'factor' => 1.0,
				'currency_id' => 0,
				'message' => __('همگام‌سازی حسابیکس غیرفعال است.', 'hesabix-v2'),
				'currency_blocked' => true,
			);
		}

		$wc = self::get_wc_currency_code($wc_currency_override);
		if ($wc === '') {
			return array(
				'ok' => false,
				'factor' => 1.0,
				'currency_id' => 0,
				'message' => __('ارز فروشگاه ووکامرس مشخص نیست؛ ابتدا واحد پول فروشگاه را تنظیم کنید.', 'hesabix-v2'),
				'currency_blocked' => true,
			);
		}

		$api = $api ?: new Hesabix_V2_Api();
		$row = self::resolve_invoice_currency_row($api);
		if (!$row) {
			return array(
				'ok' => false,
				'factor' => 1.0,
				'currency_id' => 0,
				'message' => __(
					'لیست ارزهای کسب‌وکار از حسابیکس دریافت نشد یا ارز انتخاب‌شده در افزونه دیگر برای این کسب‌وکار فعال نیست. تنظیمات «ارز فاکتور» را بررسی کنید.',
					'hesabix-v2'
				),
				'currency_blocked' => true,
			);
		}

		$hx_code = isset($row['code']) ? strtoupper(trim((string) $row['code'])) : '';

		if ($wc === $hx_code) {
			return array(
				'ok' => true,
				'factor' => 1.0,
				'currency_id' => (int) $row['id'],
				'message' => '',
			);
		}

		if (self::wc_code_is_toman($wc) && $hx_code === 'IRR') {
			return array(
				'ok' => true,
				'factor' => 10.0,
				'currency_id' => (int) $row['id'],
				'message' => '',
			);
		}

		$label = $row['title'] !== '' ? $row['title'] : ($row['name'] !== '' ? $row['name'] : $hx_code);

		return array(
			'ok' => false,
			'factor' => 1.0,
			'currency_id' => (int) $row['id'],
			'message' => sprintf(
				/* translators: 1: WooCommerce currency code, 2: Hesabix currency code */
				__(
					'ارز فروشگاه ووکامرس (%1$s) با ارز فاکتور انتخاب‌شده در حسابیکس (%2$s — %3$s) هم‌خوان نیست. تا یکسان کردن ارزها یا استفاده از «تومان» در ووکامرس و «ریال (IRR)» در حسابیکس، همگام‌سازی متوقف می‌ماند.',
					'hesabix-v2'
				),
				$wc,
				$hx_code,
				$label
			),
			'currency_blocked' => true,
		);
	}
}
