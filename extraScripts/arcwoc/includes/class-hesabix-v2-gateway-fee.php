<?php
/**
 * کارمزد درگاه / Fee ووکامرس: تنظیمات، اضافات/کسورات فاکتور، کارمزد تسویه در سند دریافت.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Gateway_Fee_Service
{
	const FEE_LINE_SERVICE = 'service';
	const FEE_LINE_ACCOUNT_ADDITION = 'account_adjustment';
	const FEE_NEGATIVE_LINE_DISCOUNT = 'line_discount';
	const FEE_NEGATIVE_DEDUCTION = 'deduction_adjustment';

	const SETTLEMENT_OFF = 'off';
	const SETTLEMENT_PERCENT = 'percent';
	const SETTLEMENT_FIXED = 'fixed';
	const SETTLEMENT_RULES = 'rules';
	const SETTLEMENT_ORDER_META = 'order_meta';

	/**
	 * @param array<string,mixed> $sync
	 * @return array<string,mixed>
	 */
	public static function normalize_sync_settings($sync)
	{
		if (!is_array($sync)) {
			$sync = array();
		}

		$mode = isset($sync['fee_line_mode']) ? sanitize_key((string) $sync['fee_line_mode']) : self::FEE_LINE_SERVICE;
		if (!in_array($mode, array(self::FEE_LINE_SERVICE, self::FEE_LINE_ACCOUNT_ADDITION), true)) {
			$mode = self::FEE_LINE_SERVICE;
		}
		$sync['fee_line_mode'] = $mode;

		$neg = isset($sync['fee_negative_mode']) ? sanitize_key((string) $sync['fee_negative_mode']) : self::FEE_NEGATIVE_LINE_DISCOUNT;
		if (!in_array($neg, array(self::FEE_NEGATIVE_LINE_DISCOUNT, self::FEE_NEGATIVE_DEDUCTION), true)) {
			$neg = self::FEE_NEGATIVE_LINE_DISCOUNT;
		}
		$sync['fee_negative_mode'] = $neg;

		$sync['fee_adjustment_account_id'] = isset($sync['fee_adjustment_account_id'])
			? absint($sync['fee_adjustment_account_id'])
			: 0;
		$sync['fee_deduction_account_id'] = isset($sync['fee_deduction_account_id'])
			? absint($sync['fee_deduction_account_id'])
			: 0;

		$sync['fee_exclude_from_profit'] = !empty($sync['fee_exclude_from_profit']);

		$settle = isset($sync['gateway_settlement_mode']) ? sanitize_key((string) $sync['gateway_settlement_mode']) : self::SETTLEMENT_OFF;
		$allowed_settle = array(
			self::SETTLEMENT_OFF,
			self::SETTLEMENT_PERCENT,
			self::SETTLEMENT_FIXED,
			self::SETTLEMENT_RULES,
			self::SETTLEMENT_ORDER_META,
		);
		if (!in_array($settle, $allowed_settle, true)) {
			$settle = self::SETTLEMENT_OFF;
		}
		$sync['gateway_settlement_mode'] = $settle;

		$sync['gateway_settlement_percent'] = self::sanitize_percent($sync['gateway_settlement_percent'] ?? 0);
		$sync['gateway_settlement_fixed'] = max(0.0, (float) ($sync['gateway_settlement_fixed'] ?? 0));

		$rules_raw = isset($sync['gateway_settlement_rules']) ? $sync['gateway_settlement_rules'] : '';
		if (is_array($rules_raw)) {
			$sync['gateway_settlement_rules'] = self::sanitize_rules_array($rules_raw);
		} else {
			$sync['gateway_settlement_rules'] = self::parse_rules_text((string) $rules_raw);
		}

		$sync['gateway_settlement_meta_key'] = isset($sync['gateway_settlement_meta_key'])
			? sanitize_key((string) $sync['gateway_settlement_meta_key'])
			: '_gateway_settlement_fee';

		return $sync;
	}

	/**
	 * @param mixed $value
	 * @return float
	 */
	private static function sanitize_percent($value)
	{
		$p = (float) $value;
		if ($p < 0) {
			return 0.0;
		}
		if ($p > 100) {
			return 100.0;
		}
		return $p;
	}

	/**
	 * قواعد متنی: payment_method|percent|fixed در هر خط
	 *
	 * @param string $raw
	 * @return array<int, array<string, mixed>>
	 */
	public static function parse_rules_text($raw)
	{
		$out = array();
		$raw = trim($raw);
		if ($raw === '') {
			return $out;
		}
		$lines = preg_split('/\r\n|\r|\n/', $raw);
		if (!is_array($lines)) {
			return $out;
		}
		foreach ($lines as $line) {
			$line = trim($line);
			if ($line === '' || strpos($line, '#') === 0) {
				continue;
			}
			$parts = array_map('trim', explode('|', $line));
			if (count($parts) < 1 || $parts[0] === '') {
				continue;
			}
			$out[] = array(
				'payment_method' => sanitize_key($parts[0]),
				'percent' => isset($parts[1]) ? self::sanitize_percent($parts[1]) : 0.0,
				'fixed' => isset($parts[2]) ? max(0.0, (float) $parts[2]) : 0.0,
			);
		}
		return $out;
	}

	/**
	 * @param array<int, mixed> $raw
	 * @return array<int, array<string, mixed>>
	 */
	private static function sanitize_rules_array($raw)
	{
		$out = array();
		foreach ($raw as $row) {
			if (!is_array($row)) {
				continue;
			}
			$pm = isset($row['payment_method']) ? sanitize_key((string) $row['payment_method']) : '';
			if ($pm === '') {
				continue;
			}
			$out[] = array(
				'payment_method' => $pm,
				'percent' => self::sanitize_percent($row['percent'] ?? 0),
				'fixed' => max(0.0, (float) ($row['fixed'] ?? 0)),
			);
		}
		return $out;
	}

	/**
	 * @return array<string,mixed>
	 */
	private static function get_sync()
	{
		return self::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
	}

	/**
	 * @return bool
	 */
	public static function positive_fee_uses_account_adjustment()
	{
		$sync = self::get_sync();
		return $sync['fee_line_mode'] === self::FEE_LINE_ACCOUNT_ADDITION;
	}

	/**
	 * @return bool
	 */
	public static function negative_fee_uses_deduction_adjustment()
	{
		$sync = self::get_sync();
		return $sync['fee_negative_mode'] === self::FEE_NEGATIVE_DEDUCTION;
	}

	/**
	 * @param string $default_code
	 * @param string $default_name
	 * @param string $transient_key
	 * @param int    $configured_id
	 * @return int
	 */
	private static function resolve_account_id($default_code, $default_name, $transient_key, $configured_id)
	{
		if ($configured_id > 0) {
			return $configured_id;
		}

		$cached = get_transient($transient_key);
		if ($cached !== false && absint($cached) > 0) {
			return absint($cached);
		}

		if (!class_exists('Hesabix_V2_Mapper')) {
			return 0;
		}

		$api = new Hesabix_V2_Api();
		$res = $api->get_accounts_flat();
		$items = Hesabix_V2_Mapper::extract_accounts_items_from_api_response_public($res);
		foreach ($items as $row) {
			if (!is_array($row) || empty($row['id'])) {
				continue;
			}
			$code = isset($row['code']) ? trim((string) $row['code']) : '';
			$name = isset($row['name']) ? trim((string) $row['name']) : '';
			if ($code === $default_code || $name === $default_name) {
				$id = absint($row['id']);
				if ($id > 0) {
					set_transient($transient_key, $id, 12 * HOUR_IN_SECONDS);
					return $id;
				}
			}
		}

		return 0;
	}

	/**
	 * @return int
	 */
	public static function resolve_fee_income_account_id()
	{
		$sync = self::get_sync();
		return self::resolve_account_id(
			'60101',
			'درآمد حاصل از فروش خدمات',
			'hesabix_v2_fee_adjustment_account_60101',
			isset($sync['fee_adjustment_account_id']) ? absint($sync['fee_adjustment_account_id']) : 0
		);
	}

	/**
	 * @return int
	 */
	public static function resolve_fee_deduction_account_id()
	{
		$sync = self::get_sync();
		return self::resolve_account_id(
			'70902',
			'کارمزد خدمات بانکی',
			'hesabix_v2_fee_deduction_account_70902',
			isset($sync['fee_deduction_account_id']) ? absint($sync['fee_deduction_account_id']) : 0
		);
	}

	/**
	 * پردازش یک Fee ووکامرس: یا خط خدمت، یا ردیف اضافات/کسورات.
	 *
	 * @param WC_Order              $order
	 * @param WC_Order_Item_Fee     $fee_item
	 * @param float                 $amount_factor
	 * @param array<int, array>     $lines           by reference
	 * @param array<int, array>     $invoice_adjustments by reference
	 * @param float                 $adjustment_net  signed, by reference
	 * @param float                 $adjustment_tax  signed, by reference
	 * @return void
	 */
	public static function apply_wc_fee_item_to_invoice(
		$order,
		$fee_item,
		$amount_factor,
		array &$lines,
		array &$invoice_adjustments,
		&$adjustment_net,
		&$adjustment_tax
	) {
		if (!is_object($fee_item) || !method_exists($fee_item, 'get_total')) {
			return;
		}

		$f = (float) $amount_factor;
		if ($f <= 0 || is_nan($f)) {
			$f = 1.0;
		}

		$fee_total = Hesabix_V2_Validation::sanitize_price((float) $fee_item->get_total() * $f);
		$fee_tax = method_exists($fee_item, 'get_total_tax')
			? Hesabix_V2_Validation::sanitize_price((float) $fee_item->get_total_tax() * $f)
			: 0.0;
		if (abs($fee_total) < 0.00001 && abs($fee_tax) < 0.00001) {
			return;
		}

		$fee_label = method_exists($fee_item, 'get_name') ? trim((string) $fee_item->get_name()) : '';
		if ($fee_label === '') {
			$fee_label = __('کارمزد / هزینه سفارش', 'hesabix-v2');
		}

		$sync = self::get_sync();
		$exclude_profit = !empty($sync['fee_exclude_from_profit']);

		if ($fee_total < 0 && self::negative_fee_uses_deduction_adjustment()) {
			$account_id = self::resolve_fee_deduction_account_id();
			if ($account_id > 0) {
				$abs_net = Hesabix_V2_Validation::sanitize_price(-(float) $fee_total);
				$tax_rate = 0.0;
				if ($abs_net > 0 && $fee_tax > 0) {
					$tax_rate = ((float) $fee_tax / (float) $abs_net) * 100;
				}
				$row = array(
					'kind' => 'deduction',
					'amount' => $abs_net,
					'tax_rate' => $tax_rate,
					'account_id' => $account_id,
					'description' => sanitize_text_field(mb_substr($fee_label, 0, 500)),
					'source' => 'woocommerce_fee',
				);
				if ($exclude_profit) {
					$row['exclude_from_profit'] = true;
				}
				$invoice_adjustments[] = $row;
				$adjustment_net -= (float) $abs_net;
				$adjustment_tax -= (float) $fee_tax;
				return;
			}
			Hesabix_V2_Log_Service::warning(
				'Fee deduction adjustment requested but no expense account resolved; falling back to line discount.',
				array('order_id' => $order->get_id(), 'recommended_account_code' => '70902')
			);
		}

		if ($fee_total > 0 && self::positive_fee_uses_account_adjustment()) {
			$account_id = self::resolve_fee_income_account_id();
			if ($account_id > 0) {
				$tax_rate = 0.0;
				if ($fee_total > 0 && $fee_tax > 0) {
					$tax_rate = ((float) $fee_tax / (float) $fee_total) * 100;
				}
				$row = array(
					'kind' => 'addition',
					'amount' => (float) $fee_total,
					'tax_rate' => $tax_rate,
					'account_id' => $account_id,
					'description' => sanitize_text_field(mb_substr($fee_label, 0, 500)),
					'source' => 'woocommerce_fee',
				);
				if ($exclude_profit) {
					$row['exclude_from_profit'] = true;
				}
				$invoice_adjustments[] = $row;
				$adjustment_net += (float) $fee_total;
				$adjustment_tax += (float) $fee_tax;
				return;
			}
			Hesabix_V2_Log_Service::warning(
				'Fee income adjustment requested but no income account resolved; falling back to service line.',
				array('order_id' => $order->get_id(), 'recommended_account_code' => '60101')
			);
		}

		self::append_fee_service_line($order, $fee_item, $f, $fee_total, $fee_tax, $fee_label, $lines);
	}

	/**
	 * @param WC_Order $order
	 * @param mixed    $fee_item
	 * @param float    $f
	 * @param float    $fee_total
	 * @param float    $fee_tax
	 * @param string   $fee_label
	 * @param array    $lines
	 * @return void
	 */
	private static function append_fee_service_line($order, $fee_item, $f, $fee_total, $fee_tax, $fee_label, array &$lines)
	{
		$fee_product_id = Hesabix_V2_Mapper::get_or_create_fee_product_public();
		if (!$fee_product_id) {
			Hesabix_V2_Log_Service::warning('Fee line skipped — could not resolve fee service product in Hesabix', array(
				'order_id' => $order->get_id(),
				'fee_name' => $fee_label,
			));
			return;
		}

		$warehouse_id = Hesabix_V2_Invoice_Warehouse_Service::resolve_warehouse_id_for_order($order);

		if ($fee_total < 0) {
			$line_extra = array(
				'unit_price' => 0,
				'line_discount' => Hesabix_V2_Validation::sanitize_price(-(float) $fee_total),
				'tax_amount' => $fee_tax,
				'line_total' => $fee_total + $fee_tax,
				'unit' => 'عدد',
				'unit_price_source' => 'base',
				'discount_type' => 'amount',
				'discount_value' => 0,
				'tax_rate' => 0,
				'movement' => 'out',
				'wc_fee_label' => $fee_label,
				'wc_fee_negative' => true,
			);
		} else {
			$line_extra = array(
				'unit_price' => $fee_total,
				'line_discount' => 0,
				'tax_amount' => $fee_tax,
				'line_total' => $fee_total + $fee_tax,
				'unit' => 'عدد',
				'unit_price_source' => 'base',
				'discount_type' => 'amount',
				'discount_value' => 0,
				'tax_rate' => 0,
				'movement' => 'out',
				'wc_fee_label' => $fee_label,
			);
		}

		if ($warehouse_id !== null && $warehouse_id !== '') {
			$line_extra['warehouse_id'] = (int) $warehouse_id;
		}

		$lines[] = array(
			'product_id' => $fee_product_id,
			'quantity' => 1,
			'description' => sanitize_text_field(mb_substr($fee_label, 0, 500)),
			'extra_info' => $line_extra,
		);
	}

	/**
	 * کارمزد تسویه درگاه (کسر از واریز پذیرنده) برای سند دریافت همراه فاکتور.
	 *
	 * @param WC_Order $order
	 * @param float    $payment_amount مبلغ دریافتی مشتری (قبل از کسر کارمزد تسویه)
	 * @param float    $amount_factor
	 * @return float کارمزد (>= 0)
	 */
	public static function resolve_settlement_commission($order, $payment_amount, $amount_factor = 1.0)
	{
		$sync = self::get_sync();
		$mode = $sync['gateway_settlement_mode'];
		if ($mode === self::SETTLEMENT_OFF) {
			return (float) apply_filters('hesabix_v2_order_gateway_commission', 0.0, $order, $payment_amount, $amount_factor, $sync);
		}

		$f = (float) $amount_factor;
		if ($f <= 0 || is_nan($f)) {
			$f = 1.0;
		}

		$base = max(0.0, (float) $payment_amount);
		$commission = 0.0;

		if ($mode === self::SETTLEMENT_ORDER_META) {
			$commission = self::read_commission_from_order_meta($order, $f, $sync);
		} elseif ($mode === self::SETTLEMENT_PERCENT) {
			$commission = $base * ((float) $sync['gateway_settlement_percent'] / 100.0);
		} elseif ($mode === self::SETTLEMENT_FIXED) {
			$commission = (float) $sync['gateway_settlement_fixed'] * $f;
		} elseif ($mode === self::SETTLEMENT_RULES) {
			$commission = self::commission_from_rules($order, $base, $f, $sync['gateway_settlement_rules']);
		}

		$commission = Hesabix_V2_Validation::sanitize_price($commission);
		if ($commission < 0) {
			$commission = 0.0;
		}
		if ($commission > $base) {
			$commission = $base;
		}

		return (float) apply_filters('hesabix_v2_order_gateway_commission', $commission, $order, $payment_amount, $amount_factor, $sync);
	}

	/**
	 * @param WC_Order $order
	 * @param float    $f
	 * @param array    $sync
	 * @return float
	 */
	private static function read_commission_from_order_meta($order, $f, $sync)
	{
		$keys = array(
			isset($sync['gateway_settlement_meta_key']) ? (string) $sync['gateway_settlement_meta_key'] : '',
			'_gateway_settlement_fee',
			'_transaction_fee',
			'gateway_fee',
			'_wc_gateway_fee',
			'_payment_fee',
		);
		foreach ($keys as $key) {
			$key = trim((string) $key);
			if ($key === '') {
				continue;
			}
			$raw = $order->get_meta($key, true);
			if ($raw === '' || $raw === null) {
				continue;
			}
			$val = (float) $raw * $f;
			if ($val > 0) {
				return Hesabix_V2_Validation::sanitize_price($val);
			}
		}
		return 0.0;
	}

	/**
	 * @param WC_Order $order
	 * @param float    $base
	 * @param float    $f
	 * @param array    $rules
	 * @return float
	 */
	private static function commission_from_rules($order, $base, $f, $rules)
	{
		if (!is_array($rules) || empty($rules)) {
			return 0.0;
		}
		$method = method_exists($order, 'get_payment_method') ? sanitize_key((string) $order->get_payment_method()) : '';
		foreach ($rules as $rule) {
			if (!is_array($rule)) {
				continue;
			}
			$pm = isset($rule['payment_method']) ? sanitize_key((string) $rule['payment_method']) : '';
			if ($pm === '' || ($method !== '' && $pm !== $method)) {
				continue;
			}
			$percent = isset($rule['percent']) ? (float) $rule['percent'] : 0.0;
			$fixed = isset($rule['fixed']) ? (float) $rule['fixed'] : 0.0;
			return Hesabix_V2_Validation::sanitize_price($base * ($percent / 100.0) + $fixed * $f);
		}
		return 0.0;
	}
}
