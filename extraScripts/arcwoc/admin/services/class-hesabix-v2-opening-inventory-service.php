<?php
/**
 * انتقال موجودی اولیه ووکامرس به تراز افتتاحیه حسابیکس (دسته‌ای + ادغام با سند موجود).
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Opening_Inventory_Service
{
	const TRANSIENT_PREFIX = 'hesabix_v2_obinv_';

	const TRANSIENT_TTL = 86400;

	/**
	 * اشاره‌گر نشست فعال هر کاربر (برای ادامهٔ ایمن پس از خطا / تازه‌سازی صفحه).
	 */
	const PTR_PREFIX = 'hesabix_v2_obinv_ptr_';

	/**
	 * @param int $user_id
	 * @return string
	 */
	private static function user_ptr_key($user_id)
	{
		return self::PTR_PREFIX . (int) $user_id;
	}

	/**
	 * @param mixed $v
	 * @return int|null
	 */
	private static function normalize_equity_id($v)
	{
		$i = (int) $v;
		return $i > 0 ? $i : null;
	}

	/**
	 * هم‌خوانی گزینه‌های اثرگذار بر محاسبه (به‌جز do_post که فقط در نهایی‌سازی است).
	 *
	 * @param array $job_opts
	 * @param array $incoming
	 * @return bool
	 */
	private static function opening_inv_core_options_match(array $job_opts, array $incoming)
	{
		$keys_int = array('inventory_account_id', 'warehouse_id', 'fiscal_year_id', 'currency_id');
		foreach ($keys_int as $k) {
			if ((int) ($job_opts[ $k ] ?? 0) !== (int) ($incoming[ $k ] ?? 0)) {
				return false;
			}
		}
		if (!empty($job_opts['include_tax']) !== !empty($incoming['include_tax'])) {
			return false;
		}
		if (!empty($job_opts['auto_balance_to_equity']) !== !empty($incoming['auto_balance_to_equity'])) {
			return false;
		}
		$jb = isset($job_opts['cost_basis']) ? (string) $job_opts['cost_basis'] : 'regular';
		$ib = isset($incoming['cost_basis']) ? (string) $incoming['cost_basis'] : 'regular';
		if ($jb !== $ib) {
			return false;
		}
		return self::normalize_equity_id($job_opts['equity_account_id'] ?? null) === self::normalize_equity_id($incoming['equity_account_id'] ?? null);
	}

	/**
	 * @param array $api_result
	 * @return array<string,mixed>|null
	 */
	public static function get_api_data_array($api_result)
	{
		if (!is_array($api_result) || empty($api_result['success'])) {
			return null;
		}
		$d = $api_result['data'] ?? null;
		return is_array($d) ? $d : null;
	}

	/**
	 * اقلام قابل‌ثبت: ساده + واریانت‌ها؛ فقط دارای مدیریت موجودی و موجودی > 0.
	 *
	 * @return array<int, array{product_id:int, parent_id:?int, kind:string}>
	 */
	public static function collect_wc_stock_targets()
	{
		if (!function_exists('wc_get_products')) {
			return array();
		}

		$ids = wc_get_products(
			array(
				'status' => 'publish',
				'limit' => -1,
				'return' => 'ids',
			)
		);
		if (!is_array($ids)) {
			return array();
		}

		$out = array();
		foreach ($ids as $pid) {
			$pid = (int) $pid;
			if ($pid < 1) {
				continue;
			}
			$p = wc_get_product($pid);
			if (!$p || $p->is_virtual()) {
				continue;
			}

			if ($p->is_type('variable')) {
				foreach ($p->get_children() as $vid) {
					$vid = (int) $vid;
					if ($vid < 1) {
						continue;
					}
					$v = wc_get_product($vid);
					if (!$v || $v->is_virtual() || !$v->managing_stock()) {
						continue;
					}
					$q = (float) $v->get_stock_quantity();
					if ($q <= 0) {
						continue;
					}
					$out[] = array(
						'product_id' => $vid,
						'parent_id' => $pid,
						'kind' => 'variation',
					);
				}
				continue;
			}

			if ($p->is_type('simple')) {
				if (!$p->managing_stock()) {
					continue;
				}
				$q = (float) $p->get_stock_quantity();
				if ($q <= 0) {
					continue;
				}
				$out[] = array(
					'product_id' => $pid,
					'parent_id' => null,
					'kind' => 'simple',
				);
			}
		}

		return $out;
	}

	/**
	 * بهای واحد برای خط موجودی (بعرض ارز حسابیکس).
	 *
	 * @param WC_Product $product
	 * @param array      $options include_tax, cost_basis: regular|sale|zero
	 * @param Hesabix_V2_Api $api
	 * @return float
	 */
	public static function resolve_unit_cost_for_opening($product, array $options, Hesabix_V2_Api $api)
	{
		$basis = isset($options['cost_basis']) ? (string) $options['cost_basis'] : 'regular';
		if ($basis === 'zero') {
			return 0.0;
		}

		$inc_tax = !empty($options['include_tax']);
		if ($basis === 'sale') {
			$raw = (float) $product->get_price();
		} else {
			$raw = (float) $product->get_regular_price();
			if ($raw <= 0) {
				$raw = (float) $product->get_price();
			}
		}

		$price_for_tax = $raw;
		if (function_exists('wc_get_price_excluding_tax') && function_exists('wc_get_price_including_tax')) {
			if ($inc_tax) {
				$price_for_tax = (float) wc_get_price_including_tax(array('qty' => 1, 'product' => $product));
			} else {
				$price_for_tax = (float) wc_get_price_excluding_tax(array('qty' => 1, 'product' => $product));
			}
		}

		if ($price_for_tax < 0) {
			$price_for_tax = 0.0;
		}

		$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($api, $product->get_currency());
		if (empty($gate['ok'])) {
			return 0.0;
		}
		$f = isset($gate['factor']) ? (float) $gate['factor'] : 1.0;
		if ($f <= 0 || is_nan($f)) {
			$f = 1.0;
		}

		return Hesabix_V2_Validation::sanitize_price($price_for_tax * $f);
	}

	/**
	 * تبدیل پاسخ سند باز شده به account_lines + inventory_lines برای upsert مجدد.
	 *
	 * @param array<string,mixed>|null $doc
	 * @return array{account_lines: array, inventory_lines: array, document_date: ?string, description: ?string}
	 */
	public static function document_to_payload_parts($doc)
	{
		$account_lines = array();
		$inventory_lines = array();
		$document_date = null;
		$description = null;
		$inv_acc = null;

		if (!is_array($doc)) {
			return array(
				'account_lines' => array(),
				'inventory_lines' => array(),
				'document_date' => null,
				'description' => null,
			);
		}

		if (isset($doc['document_date'])) {
			$document_date = is_string($doc['document_date']) ? $doc['document_date'] : null;
		}
		if (isset($doc['description'])) {
			$description = is_string($doc['description']) ? $doc['description'] : null;
		}

		$ei = isset($doc['extra_info']) && is_array($doc['extra_info']) ? $doc['extra_info'] : array();
		if (isset($ei['inventory_account_id'])) {
			$inv_acc = (int) $ei['inventory_account_id'];
		}
		if (isset($doc['inventory_account_id'])) {
			$inv_acc = (int) $doc['inventory_account_id'];
		}

		$lines = isset($doc['lines']) && is_array($doc['lines']) ? $doc['lines'] : array();
		foreach ($lines as $ln) {
			if (!is_array($ln)) {
				continue;
			}
			$pid = isset($ln['product_id']) ? (int) $ln['product_id'] : 0;
			$qty = isset($ln['quantity']) ? (float) $ln['quantity'] : 0.0;
			if ($pid > 0 && $qty > 0) {
				$info = isset($ln['extra_info']) && is_array($ln['extra_info']) ? $ln['extra_info'] : array();
				$info['movement'] = 'in';
				$inventory_lines[] = array(
					'product_id' => $pid,
					'quantity' => $qty,
					'description' => isset($ln['description']) ? $ln['description'] : null,
					'extra_info' => $info,
				);
				continue;
			}

			$d = isset($ln['debit']) ? (float) $ln['debit'] : 0.0;
			$c = isset($ln['credit']) ? (float) $ln['credit'] : 0.0;
			if ($d <= 0 && $c <= 0) {
				continue;
			}

			$desc = isset($ln['description']) ? (string) $ln['description'] : '';
			$aid = isset($ln['account_id']) ? (int) $ln['account_id'] : 0;
			if ($inv_acc && $aid === $inv_acc && $desc === 'موجودی ابتدای دوره') {
				continue;
			}
			if ($desc === 'بستن اختلاف تراز افتتاحیه') {
				continue;
			}

			$account_lines[] = array(
				'account_id' => $ln['account_id'] ?? null,
				'person_id' => $ln['person_id'] ?? null,
				'bank_account_id' => $ln['bank_account_id'] ?? null,
				'cash_register_id' => $ln['cash_register_id'] ?? null,
				'petty_cash_id' => $ln['petty_cash_id'] ?? null,
				'debit' => $d,
				'credit' => $c,
				'description' => $ln['description'] ?? null,
				'extra_info' => $ln['extra_info'] ?? null,
			);
		}

		return array(
			'account_lines' => $account_lines,
			'inventory_lines' => $inventory_lines,
			'document_date' => $document_date,
			'description' => $description,
		);
	}

	/**
	 * ادغام خطوط موجودی بدون تکرار (کالا + انبار).
	 *
	 * @param array $a
	 * @param array $b
	 * @return array
	 */
	public static function merge_inventory_lines($a, $b)
	{
		$map = array();
		foreach (array_merge($a, $b) as $row) {
			if (!is_array($row) || empty($row['product_id'])) {
				continue;
			}
			$info = isset($row['extra_info']) && is_array($row['extra_info']) ? $row['extra_info'] : array();
			$wid = isset($info['warehouse_id']) ? (int) $info['warehouse_id'] : 0;
			$key = (int) $row['product_id'] . ':' . $wid;
			$map[ $key ] = $row;
		}
		return array_values($map);
	}

	/**
	 * ساخت خط موجودی از محصول ووکامرس.
	 *
	 * @param WC_Product $product
	 * @param int        $hesabix_product_id
	 * @param int        $warehouse_id
	 * @param array      $options
	 * @param Hesabix_V2_Api $api
	 * @return array<string,mixed>|null
	 */
	public static function build_inventory_line_from_wc_product($product, $hesabix_product_id, $warehouse_id, array $options, Hesabix_V2_Api $api)
	{
		$hesabix_product_id = (int) $hesabix_product_id;
		$warehouse_id = (int) $warehouse_id;
		if ($hesabix_product_id < 1 || $warehouse_id < 1) {
			return null;
		}

		$qty = (float) $product->get_stock_quantity();
		if ($qty <= 0) {
			return null;
		}

		$unit_cost = self::resolve_unit_cost_for_opening($product, $options, $api);
		$extra = array(
			'warehouse_id' => $warehouse_id,
			'movement' => 'in',
			'cost_price' => $unit_cost,
		);

		return array(
			'product_id' => $hesabix_product_id,
			'quantity' => $qty,
			'description' => sprintf(
				/* translators: %s: product name */
				__('موجودی اولیه ووکامرس — %s', 'hesabix-v2'),
				$product->get_name()
			),
			'extra_info' => $extra,
		);
	}

	/**
	 * آماده‌سازی کار دسته‌ای.
	 *
	 * @param int   $user_id
	 * @param array $options
	 * @return array{success:bool, message?:string, job_id?:string, total?:int}
	 */
	public static function job_prepare($user_id, array $options)
	{
		$user_id = (int) $user_id;
		if ($user_id < 1) {
			return array('success' => false, 'message' => __('کاربر نامعتبر است.', 'hesabix-v2'));
		}

		if (get_option('hesabix_v2_opening_inventory_completed')) {
			return array('success' => false, 'message' => __('این عمل قبلاً با موفقیت انجام شده و دیگر قابل تکرار نیست.', 'hesabix-v2'));
		}

		if (!get_option('hesabix_v2_enabled')) {
			return array('success' => false, 'message' => __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'));
		}

		$api = new Hesabix_V2_Api();
		$fy = (int) get_option('hesabix_v2_fiscal_year_id');
		if ($fy < 1) {
			return array('success' => false, 'message' => __('سال مالی در تنظیمات افزونه مشخص نیست.', 'hesabix-v2'));
		}

		$cur = Hesabix_V2_Currency_Service::resolve_invoice_currency_id($api);
		if ($cur < 1) {
			return array('success' => false, 'message' => __('ارز فاکتور / سند در تنظیمات مشخص نشده است.', 'hesabix-v2'));
		}

		$warehouse_id = isset($options['warehouse_id']) ? (int) $options['warehouse_id'] : 0;
		if ($warehouse_id < 1) {
			$warehouse_id = (int) get_option('hesabix_v2_default_warehouse_id');
		}
		if ($warehouse_id < 1) {
			return array('success' => false, 'message' => __('انبار پیش‌فرض را در تب فاکتور انتخاب کنید.', 'hesabix-v2'));
		}

		$inv_acc = isset($options['inventory_account_id']) ? (int) $options['inventory_account_id'] : 0;
		if ($inv_acc < 1) {
			return array('success' => false, 'message' => __('حساب موجودی (کالا) را انتخاب کنید.', 'hesabix-v2'));
		}

		$auto_eq = !empty($options['auto_balance_to_equity']);
		$eq_acc = isset($options['equity_account_id']) ? (int) $options['equity_account_id'] : 0;
		if ($auto_eq && $eq_acc < 1) {
			return array('success' => false, 'message' => __('برای بستن خودکار تراز، حساب حقوق صاحبان سهام را انتخاب کنید.', 'hesabix-v2'));
		}

		$cost_basis = isset($options['cost_basis']) ? (string) $options['cost_basis'] : 'regular';
		if (!in_array($cost_basis, array('regular', 'sale', 'zero'), true)) {
			$cost_basis = 'regular';
		}
		$incoming_core = array(
			'include_tax' => !empty($options['include_tax']),
			'cost_basis' => $cost_basis,
			'auto_balance_to_equity' => $auto_eq,
			'inventory_account_id' => $inv_acc,
			'equity_account_id' => $eq_acc > 0 ? $eq_acc : null,
			'warehouse_id' => $warehouse_id,
			'fiscal_year_id' => $fy,
			'currency_id' => $cur,
		);

		$ptr_key = self::user_ptr_key($user_id);
		$existing_id = get_transient($ptr_key);
		if (is_string($existing_id) && $existing_id !== '') {
			$existing_job = self::get_job($existing_id, $user_id);
			if (!$existing_job) {
				delete_transient($ptr_key);
			} else {
				$ex_items = isset($existing_job['items']) && is_array($existing_job['items']) ? $existing_job['items'] : array();
				$ex_cursor = (int) ($existing_job['cursor'] ?? 0);
				$job_opts = isset($existing_job['options']) && is_array($existing_job['options']) ? $existing_job['options'] : array();
				if (!self::opening_inv_core_options_match($job_opts, $incoming_core)) {
					return array(
						'success' => false,
						'message' => __('نشست نیمه‌تمام با گزینه‌های فعلی فرم هم‌خوان نیست. همان گزینه‌های اجرای قبلی را برگردانید یا پس از اتمام نشست دوباره تلاش کنید.', 'hesabix-v2'),
					);
				}
				if ($ex_cursor < count($ex_items)) {
					return array(
						'success' => true,
						'job_id' => $existing_id,
						'total' => count($ex_items),
						'resumed' => true,
						'message' => __('ادامهٔ نشست قبلی (همان دسته باقی‌مانده).', 'hesabix-v2'),
					);
				}
				$existing_job['options']['do_post'] = !empty($options['do_post']);
				set_transient(self::TRANSIENT_PREFIX . $existing_id, $existing_job, self::TRANSIENT_TTL);
				return array(
					'success' => true,
					'job_id' => $existing_id,
					'total' => count($ex_items),
					'needs_finalize' => true,
					'message' => __('دسته‌ها قبلاً ذخیره شده‌اند؛ فقط نهایی‌سازی مانده است.', 'hesabix-v2'),
				);
			}
		}

		$ob = self::get_api_data_array($api->get_opening_balance($fy));
		if (is_array($ob)) {
			$ei = isset($ob['extra_info']) && is_array($ob['extra_info']) ? $ob['extra_info'] : array();
			if (!empty($ei['posted'])) {
				return array('success' => false, 'message' => __('تراز افتتاحیه این سال مالی در حسابیکس نهایی شده؛ امکان ویرایش نیست.', 'hesabix-v2'));
			}
		}

		$targets = self::collect_wc_stock_targets();
		if (empty($targets)) {
			return array('success' => false, 'message' => __('هیچ کالای منتشرشده‌ای با موجودی مدیریت‌شده و شمارش > 0 یافت نشد.', 'hesabix-v2'));
		}

		$job_id = wp_generate_password(20, false, false);
		$batch = isset($options['batch_size']) ? max(3, min(40, (int) $options['batch_size'])) : 12;

		$payload = array(
			'user_id' => $user_id,
			'cursor' => 0,
			'batch_size' => $batch,
			'items' => $targets,
			'options' => array(
				'include_tax' => $incoming_core['include_tax'],
				'cost_basis' => $incoming_core['cost_basis'],
				'auto_balance_to_equity' => $incoming_core['auto_balance_to_equity'],
				'inventory_account_id' => $inv_acc,
				'equity_account_id' => $incoming_core['equity_account_id'],
				'warehouse_id' => $warehouse_id,
				'do_post' => !empty($options['do_post']),
				'fiscal_year_id' => $fy,
				'currency_id' => $cur,
			),
			'created_at' => time(),
		);

		set_transient(self::TRANSIENT_PREFIX . $job_id, $payload, self::TRANSIENT_TTL);
		set_transient($ptr_key, $job_id, self::TRANSIENT_TTL);

		return array(
			'success' => true,
			'job_id' => $job_id,
			'total' => count($targets),
			'message' => __('کار آماده شد.', 'hesabix-v2'),
		);
	}

	/**
	 * @param string $job_id
	 * @param int    $user_id
	 * @return array<string,mixed>|null
	 */
	public static function get_job($job_id, $user_id)
	{
		$job_id = sanitize_key((string) $job_id);
		if ($job_id === '') {
			return null;
		}
		$raw = get_transient(self::TRANSIENT_PREFIX . $job_id);
		if (!is_array($raw) || (int) ($raw['user_id'] ?? 0) !== (int) $user_id) {
			return null;
		}
		return $raw;
	}

	/**
	 * @param string $job_id
	 * @return void
	 */
	public static function delete_job($job_id)
	{
		$job_id = sanitize_key((string) $job_id);
		if ($job_id !== '') {
			delete_transient(self::TRANSIENT_PREFIX . $job_id);
		}
	}

	/**
	 * اجرای یک دسته.
	 *
	 * @param string $job_id
	 * @param int    $user_id
	 * @return array{success:bool, message?:string, cursor?:int, total?:int, done?:bool, detail?:array}
	 */
	public static function job_run_batch($job_id, $user_id)
	{
		$job = self::get_job($job_id, $user_id);
		if (!$job) {
			return array('success' => false, 'message' => __('نشست کار نامعتبر یا منقضی است. از نو شروع کنید.', 'hesabix-v2'));
		}

		$sync = new Hesabix_V2_Sync_Service();
		$api = new Hesabix_V2_Api();
		$opts = isset($job['options']) && is_array($job['options']) ? $job['options'] : array();
		$fy = (int) ($opts['fiscal_year_id'] ?? 0);
		$currency_id = (int) ($opts['currency_id'] ?? 0);
		$warehouse_id = (int) ($opts['warehouse_id'] ?? 0);
		$batch_size = (int) ($job['batch_size'] ?? 12);
		$items = isset($job['items']) && is_array($job['items']) ? $job['items'] : array();
		$cursor = (int) ($job['cursor'] ?? 0);
		$total = count($items);

		$slice = array_slice($items, $cursor, $batch_size);
		if (empty($slice)) {
			return array(
				'success' => true,
				'done' => true,
				'cursor' => $cursor,
				'total' => $total,
				'message' => __('همهٔ مراحل پردازش شد.', 'hesabix-v2'),
			);
		}

		$new_lines = array();
		$detail = array();
		$blocking = false;

		foreach ($slice as $row) {
			$wc_pid = (int) $row['product_id'];
			$parent = isset($row['parent_id']) ? (int) $row['parent_id'] : 0;
			$product = wc_get_product($wc_pid);
			if (!$product) {
				$detail[] = array('wc_id' => $wc_pid, 'ok' => false, 'message' => __('محصول حذف شده است.', 'hesabix-v2'));
				continue;
			}

			if ($parent > 0) {
				$res = $sync->sync_product($parent, $wc_pid);
			} else {
				$res = $sync->sync_product($wc_pid);
			}

			if (empty($res['success']) || empty($res['hesabix_id'])) {
				$blocking = true;
				$detail[] = array(
					'wc_id' => $wc_pid,
					'ok' => false,
					'message' => isset($res['message']) ? (string) $res['message'] : __('همگام کالا ناموفق', 'hesabix-v2'),
				);
				continue;
			}

			$line = self::build_inventory_line_from_wc_product(
				$product,
				(int) $res['hesabix_id'],
				$warehouse_id,
				$opts,
				$api
			);
			if (!$line) {
				$detail[] = array('wc_id' => $wc_pid, 'ok' => true, 'message' => __('بدون خط (موجودی صفر)', 'hesabix-v2'));
				continue;
			}
			$new_lines[] = $line;
			$detail[] = array('wc_id' => $wc_pid, 'ok' => true, 'hesabix_product' => (int) $res['hesabix_id']);
		}

		if ($blocking) {
			return array(
				'success' => false,
				'message' => __('در این دسته خطایی رخ داد؛ پس از رفع مشکل دوباره «شروع ثبت موجودی اولیه» را بزنید — همان نشست ادامه پیدا می‌کند.', 'hesabix-v2'),
				'cursor' => $cursor,
				'total' => $total,
				'detail' => $detail,
			);
		}

		if (!empty($new_lines)) {
			$ob_raw = $api->get_opening_balance($fy);
			$doc = self::get_api_data_array($ob_raw);
			$parts = self::document_to_payload_parts($doc);

			$merged_inv = self::merge_inventory_lines($parts['inventory_lines'], $new_lines);

			$doc_date = $parts['document_date'];
			if (!$doc_date) {
				$fy_info = $api->get_current_fiscal_year((int) get_option('hesabix_v2_business_id'));
				$fy_data = self::get_api_data_array($fy_info);
				if (is_array($fy_data) && !empty($fy_data['start_date'])) {
					$doc_date = is_string($fy_data['start_date']) ? $fy_data['start_date'] : null;
				}
				if (!$doc_date) {
					$doc_date = gmdate('Y-m-d');
				}
			}

			$desc = $parts['description'];
			if (!$desc) {
				$desc = __('موجودی اولیه ووکامرس', 'hesabix-v2');
			}

			$body = array(
				'fiscal_year_id' => $fy,
				'document_date' => $doc_date,
				'currency_id' => $currency_id,
				'account_lines' => $parts['account_lines'],
				'inventory_lines' => $merged_inv,
				'inventory_account_id' => (int) $opts['inventory_account_id'],
				'auto_balance_to_equity' => !empty($opts['auto_balance_to_equity']),
				'equity_account_id' => !empty($opts['equity_account_id']) ? (int) $opts['equity_account_id'] : null,
				'description' => $desc,
			);

			$put = $api->upsert_opening_balance($body);
			if (empty($put['success'])) {
				$msg = isset($put['message']) ? (string) $put['message'] : __('ذخیرهٔ تراز افتتاحیه ناموفق بود.', 'hesabix-v2');
				return array(
					'success' => false,
					'message' => $msg,
					'cursor' => $cursor,
					'total' => $total,
					'detail' => $detail,
				);
			}
		}

		$cursor += count($slice);
		$job['cursor'] = $cursor;
		set_transient(self::TRANSIENT_PREFIX . $job_id, $job, self::TRANSIENT_TTL);

		$done = $cursor >= $total;

		return array(
			'success' => true,
			'cursor' => $cursor,
			'total' => $total,
			'done' => $done,
			'detail' => $detail,
			'message' => $done
				? __('پردازش موجودی تمام شد؛ در صورت نیاز نهایی‌سازی را بزنید.', 'hesabix-v2')
				: __('دسته با موفقیت ذخیره شد.', 'hesabix-v2'),
		);
	}

	/**
	 * نهایی‌سازی: در صورت انتخاب post، و علامت‌گذاری یک‌بار مصرف.
	 *
	 * @param string $job_id
	 * @param int    $user_id
	 * @return array{success:bool, message?:string}
	 */
	public static function job_finalize($job_id, $user_id)
	{
		$job = self::get_job($job_id, $user_id);
		if (!$job) {
			return array('success' => false, 'message' => __('نشست کار نامعتبر است.', 'hesabix-v2'));
		}

		$items = isset($job['items']) && is_array($job['items']) ? $job['items'] : array();
		$cursor = (int) ($job['cursor'] ?? 0);
		if ($cursor < count($items)) {
			return array('success' => false, 'message' => __('هنوز مراحل باقی مانده است.', 'hesabix-v2'));
		}

		$opts = isset($job['options']) && is_array($job['options']) ? $job['options'] : array();
		$api = new Hesabix_V2_Api();

		if (!empty($opts['do_post'])) {
			$fy = (int) ($opts['fiscal_year_id'] ?? 0);
			$pr = $api->post_opening_balance($fy);
			if (empty($pr['success'])) {
				$msg = isset($pr['message']) ? (string) $pr['message'] : __('نهایی‌سازی تراز افتتاحیه ناموفق بود.', 'hesabix-v2');
				return array('success' => false, 'message' => $msg);
			}
		}

		update_option('hesabix_v2_opening_inventory_completed', true);
		$ptr_k = self::user_ptr_key((int) ($job['user_id'] ?? 0));
		delete_transient($ptr_k);
		self::delete_job($job_id);

		Hesabix_V2_Log_Service::info('WooCommerce opening inventory pushed to Hesabix opening balance', array(
			'entity_type' => 'opening_balance',
			'posted' => !empty($opts['do_post']),
		));

		return array(
			'success' => true,
			'message' => !empty($opts['do_post'])
				? __('تراز افتتاحیه ذخیره و نهایی شد. این عمل دیگر در دسترس نیست.', 'hesabix-v2')
				: __('تراز افتتاحیه ذخیره شد. این عمل دیگر در دسترس نیست.', 'hesabix-v2'),
		);
	}
}
