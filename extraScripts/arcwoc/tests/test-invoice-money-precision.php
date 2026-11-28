<?php
/** Run with: php extraScripts/arcwoc/tests/test-invoice-money-precision.php */
define('WPINC', true);
require_once __DIR__ . '/../includes/class-hesabix-v2-decimal.php';
require_once __DIR__ . '/../includes/class-hesabix-v2-currency-service.php';
require_once __DIR__ . '/../includes/class-hesabix-v2-mapper.php';
require_once __DIR__ . '/../includes/class-hesabix-v2-gateway-fee.php';
require_once __DIR__ . '/../includes/class-hesabix-v2-validation.php';

function check($actual, $expected, $name)
{
	if ($actual !== $expected) {
		throw new RuntimeException($name . ': ' . json_encode(array($actual, $expected)));
	}
}
function absint($v) { return abs((int) $v); }
function sanitize_text_field($v) { return $v; }
if (!function_exists('mb_substr')) { function mb_substr($v, $start, $length) { return substr($v, $start, $length); } }
function __($v, $domain = '') { return $v; }
function sanitize_key($key) { return preg_replace('/[^a-z0-9_\-]/', '', strtolower($key)); }
function has_filter($hook) { return $hook === 'hesabix_v2_order_gateway_commission' && isset($GLOBALS['commission_filter']) ? 10 : false; }
function apply_filters($hook, $value, ...$args) { return has_filter($hook) !== false ? ($GLOBALS['commission_filter'])($value, ...$args) : $value; }
function get_transient($key) { return false; }
function set_transient(...$args) {}
function get_option($key, $default = false)
{
	if ($key === 'hesabix_v2_sync_settings') { return $GLOBALS['commission_settings'] ?? array(); }
	if ($key === 'hesabix_v2_fee_product_id') { return 123; }
	return array('hesabix_v2_enabled' => true, 'hesabix_v2_business_id' => 1, 'hesabix_v2_currency_id' => 1,
		'hesabix_v2_invoice_payment_destination' => 'cash_register', 'hesabix_v2_default_cash_register_id' => '1')[$key] ?? $default;
}
function current_time($format) { return (new DateTimeImmutable('2026-11-11 12:00:00'))->format($format); }
class Hesabix_V2_Api
{
	public function get_business_currencies() { return $GLOBALS['currency_response']; }
}
class Hesabix_V2_DB_Service { public function get_hesabix_id(...$args) { return $args[1] === 42 && $args[2] === 1 ? 842 : 1; } }
class Hesabix_V2_Invoice_Warehouse_Service { public static function resolve_warehouse_id_for_order($order) { return null; } }
class Hesabix_V2_Invoice_Helper
{
	public static function normalize_sync_settings($options) { return array(); }
	public static function resolve_invoice_tag_ids() { return array(); }
}
class Hesabix_V2_Log_Service { public static function warning(...$args) {} }
class MoneyItem
{
	private $item;
	public function __construct($item = null) { $this->item = $item; }
	public function get_product() { return new class { public function is_virtual() { return false; } }; }
	public function get_product_id() { return 1; }
	public function get_variation_id() { return $GLOBALS['money_variation_id'] ?? 0; }
	public function get_quantity() { return ($this->item ?? $GLOBALS['money_case'])[0]; }
	public function get_total() { return ($this->item ?? $GLOBALS['money_case'])[1]; }
	public function get_total_tax() { return ($this->item ?? $GLOBALS['money_case'])[2]; }
	public function get_id() { return 77; }
}
class MoneyFee
{
	private $net;
	private $tax;
	public function __construct($net, $tax) { $this->net = $net; $this->tax = $tax; }
	public function get_total() { return $this->net; }
	public function get_total_tax() { return $this->tax; }
	public function get_name() { return 'Test fee'; }
}
class MoneyOrder
{
	public function get_items($type = 'line_item')
	{
		if ($type === 'fee') { return $GLOBALS['money_fees'] ?? array(); }
		return isset($GLOBALS['money_items']) ? array_map(fn($item) => new MoneyItem($item), $GLOBALS['money_items']) : array(new MoneyItem());
	}
	public function get_total() { return $GLOBALS['money_case'][3]; }
	public function get_total_tax() { return $GLOBALS['money_case'][2]; }
	public function get_discount_total() { return '0'; }
	public function get_shipping_total() { return '0'; }
	public function get_currency() { return $GLOBALS['money_currency'] ?? 'USD'; }
	public function get_id() { return 100; }
	public function get_order_number() { return '100'; }
	public function get_date_created() { return null; }
	public function get_date_paid() { return null; }
	public function is_paid() { return true; }
	public function get_payment_method() { return 'test_gateway'; }
	public function get_meta($key, $single) { return $GLOBALS['commission_meta'][$key] ?? ''; }
}
$money_case = array(3, '30.01', '3.01', '33.02');
$money_currency = 'IRT';
$currency_response = array('success' => true, 'data' => array(array('id' => 1, 'code' => 'IRR', 'decimal_places' => 2, 'round_monetary_amounts' => true)));
$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync(null, 'IRT');
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, $gate['factor'], $gate['currency_id']);
check($payload['lines'][0]['extra_info']['unit_price'], (30.01 * 10 / 3), 'legacy converted price encoding');
check($payload['lines'][0]['extra_info']['tax_amount'], (3.01 * 10), 'legacy converted tax encoding');
check($payload['payments'][0]['amount'], '330.2', 'converted payment is still exact');
unset($money_currency);
foreach (array(
	array(array(1, '0.005', '0'), array(1, '0.005', '0'), '0.01'),
	array(array(1, '1', '0.005'), array(1, '1', '0.005'), '2.01'),
) as $items) {
	$money_case = array(1, '0', '0', $items[2], 2, true);
	$money_case[2] = Hesabix_V2_Decimal::add($items[0][2], $items[1][2]);
	$money_items = array($items[0], $items[1]);
	$currency_response = array('success' => true, 'data' => array(array('id' => 1, 'code' => 'USD', 'decimal_places' => 2, 'round_monetary_amounts' => true)));
	$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
	check($payload['payments'][0]['amount'], $items[2], 'multi-line payment');
	check(Hesabix_V2_Decimal::subtract($payload['lines'][0]['extra_info']['tax_amount'], $items[0][2]), '0', 'unrounded tax share');
}
unset($money_items);
$money_case = array(1, '0.01', '0.005', '0.02');
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
check(Hesabix_V2_Decimal::subtract($payload['lines'][0]['extra_info']['unit_price'], '0.01'), '0', 'half-cent must not increase revenue');
check($payload['lines'][0]['extra_info']['line_total'], '0.015', 'server rounds the aggregate');
check($payload['payments'][0]['amount'], '0.02', 'half-cent payment');

check(Hesabix_V2_Decimal::add('999999999.99', '0.01'), '1000000000', 'carry');
check(Hesabix_V2_Decimal::subtract('-1.01', '-2'), '0.99', 'signed subtraction');
check(Hesabix_V2_Decimal::multiply('30.01', '10'), '300.1', 'toman conversion');
check(Hesabix_V2_Decimal::multiply('1.25', '0.08'), '0.1', 'fractional multiplier');
check(Hesabix_V2_Decimal::round('9.995', 2), '10', 'positive halfway');
check(Hesabix_V2_Decimal::round('-9.995', 2), '-10', 'negative halfway');
check(Hesabix_V2_Decimal::round('0.00001', 2), '0', 'leading zeros');
check(Hesabix_V2_Decimal::divide('999999999.99', '7'), '142857142.855714285714285714285714', 'exact quotient');
check(Hesabix_V2_Decimal::divide('1', '0.125'), '8', 'fractional quantity');
check(Hesabix_V2_Decimal::divide('0', '7'), '0', 'zero');
check(Hesabix_V2_Decimal::round(Hesabix_V2_Decimal::multiply(Hesabix_V2_Decimal::unit_price('0.005', 7), 7), 2), '0.01', 'quotient preserves a half-cent');

foreach (array(
	array(7, '999999999.99', '0', '999999999.99', 8, true, '999999999.99'),
	array(7, '100.01', '0', '100.01', 2, true, '100.01'),
	array(7, '100.4', '0', '100.4', 0, true, '100'),
	array(7, '100.01', '0', '100.01', 0, false, '100.01'),
	array(3, '30.01', '3.01', '33.02', 2, true, '33.02'),
	array(7, '100', '0', '100.01', 2, true, '100.01'),
	array(7, '999999999.99', '0', '1000000000.99', 8, true, '1000000000.99'),
) as $money_case) {
	$currency_response = array('success' => true, 'data' => array(array('id' => 1, 'code' => 'USD',
		'decimal_places' => $money_case[4], 'round_monetary_amounts' => $money_case[5], 'is_default' => true)));
	$policy = Hesabix_V2_Currency_Service::invoice_money_policy(1);
	check($policy, array('decimal_places' => $money_case[4], 'round_monetary_amounts' => $money_case[5]), 'API currency policy');
	$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
	$wire = json_decode(json_encode($payload), true);
	check($wire['payments'][0]['amount'], $money_case[6], 'payment amount');
	check($wire['extra_info']['totals']['net'], $money_case[6], 'order amount');
	check($wire['lines'][0]['extra_info']['line_total'], $money_case[6], 'line amount');
	if ($money_case[1] === '999999999.99' && $money_case[3] === $money_case[1]) {
		check(is_string($wire['lines'][0]['extra_info']['unit_price']), true, 'insufficient JSON number uses exact price');
	}
	if ($money_case[1] === '100.01' && $money_case[4] === 2) {
		check($wire['lines'][0]['extra_info']['unit_price'], (100.01 / 7), 'safe legacy price encoding remains stable');
	}
}
try {
	Hesabix_V2_Decimal::money('999999999.99000001', array('decimal_places' => 8, 'round_monetary_amounts' => true));
	throw new LogicException('Unsupported GL precision was accepted');
} catch (RuntimeException $e) {
}
$money_case = array(3, '30.01', '3.01', '33.02');
$money_variation_id = 42;
$currency_response = array('success' => true, 'data' => array(array('id' => 1, 'code' => 'USD', 'decimal_places' => 2, 'round_monetary_amounts' => true)));
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
check($payload['lines'][0]['product_id'], 842, 'fork variation mapping preserved');
check($payload['lines'][0]['extra_info']['unit'], 'عدد', 'fork unit preserved');
check(isset($payload['lines'][0]['allocations']), false, 'legacy variation uses existing mapped product');
check($payload['payments'][0]['amount'], '33.02', 'variation exact payment');
unset($money_variation_id);
// Real gateway-fee service, including policy rounding and legacy filter safety.
$money_case = array(1, '33.02', '0', '33.02');
$currency_response = array('success' => true, 'data' => array(array('id' => 1, 'code' => 'USD', 'decimal_places' => 2, 'round_monetary_amounts' => true)));
$commission_meta = array('_gateway_settlement_fee' => '0.125');
foreach (array(
	array(array('gateway_settlement_mode' => 'percent', 'gateway_settlement_percent' => '2.5'), '0.83'),
	array(array('gateway_settlement_mode' => 'fixed', 'gateway_settlement_fixed' => '0.25'), '0.25'),
	array(array('gateway_settlement_mode' => 'rules', 'gateway_settlement_rules' => 'test_gateway|2.5|0.10'), '0.93'),
	array(array('gateway_settlement_mode' => 'order_meta'), '0.13'),
	array(array('gateway_settlement_mode' => 'fixed', 'gateway_settlement_fixed' => '100'), '33.02'),
) as $case) {
	$commission_settings = $case[0];
	$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
	check($payload['payments'][0]['commission'], $case[1], 'exact settlement commission');
	check($payload['payments'][0]['amount'], '33.02', 'commission does not change payment gross');
}
$commission_settings = array('gateway_settlement_mode' => 'off');
$commission_filter = function ($value, $order, $base) {
	check(is_float($value), true, 'legacy commission filter value type');
	check(is_float($base), true, 'legacy commission filter base type');
	return 1000;
};
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
check($payload['payments'][0]['commission'], '33.02', 'filter cannot exceed payment');
$commission_filter = function () { return -1; };
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
check(isset($payload['payments'][0]['commission']), false, 'negative commission is omitted');
unset($commission_filter);
$commission_settings = array('gateway_settlement_mode' => 'fixed', 'gateway_settlement_fixed' => '0.25');
$currency_response['data'][0]['decimal_places'] = 0;
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
check(isset($payload['payments'][0]['commission']), false, 'zero-decimal policy rounds commission');
$currency_response['data'][0]['decimal_places'] = 2;
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 10, 1);
check($payload['payments'][0]['commission'], '2.5', 'fixed commission converted by factor');
unset($commission_settings, $commission_meta);
echo "PASS: exact settlement commissions and filter compatibility\n";
// Match backend invoice adjustment sign and per-row tax rounding.
foreach (array(
	array('1.25', '0.125', 'addition', '1.25', '0.13'),
	array('-1.25', '-0.125', 'deduction', '-1.25', '-0.13'),
	array('0.03', '0.005', 'addition', '0.03', '0.01'),
) as $fee_case) {
	$commission_settings = array('fee_line_mode' => 'account_adjustment', 'fee_negative_mode' => 'deduction_adjustment',
		'fee_adjustment_account_id' => 9, 'fee_deduction_account_id' => 10);
	$lines = array(); $adjustments = array(); $net = '0'; $tax = '0';
	Hesabix_V2_Gateway_Fee_Service::apply_wc_fee_item_to_invoice(new MoneyOrder(), new MoneyFee($fee_case[0], $fee_case[1]), 1, $lines, $adjustments, $net, $tax);
	check($adjustments[0]['kind'], $fee_case[2], 'adjustment kind');
	check($net, $fee_case[3], 'signed adjustment net');
	check($tax, $fee_case[4], 'signed posted adjustment tax');
	check($lines, array(), 'account adjustment does not add a service line');
}
foreach (array(array('1.25','-0.1'), array('-1.25','0.1'), array('0.001','0'), array('1','2')) as $bad_fee) {
	$lines = array(); $adjustments = array(); $net = '0'; $tax = '0'; $rejected = false;
	try {
		Hesabix_V2_Gateway_Fee_Service::apply_wc_fee_item_to_invoice(new MoneyOrder(), new MoneyFee($bad_fee[0], $bad_fee[1]), 1, $lines, $adjustments, $net, $tax);
	} catch (RuntimeException $e) { $rejected = true; }
	check($rejected, true, 'unsupported adjustment rejected');
	check($adjustments, array(), 'no partial adjustment');
}
unset($commission_settings);
foreach (array(array('0.005','0.005','0.01'), array('-0.125','-0.025','-0.15')) as $fee_case) {
	$lines = array(); $adjustments = array(); $net = '0'; $tax = '0';
	Hesabix_V2_Gateway_Fee_Service::apply_wc_fee_item_to_invoice(new MoneyOrder(), new MoneyFee($fee_case[0], $fee_case[1]), 1, $lines, $adjustments, $net, $tax);
	check($lines[0]['extra_info']['line_total'], $fee_case[2], 'exact service line net');
	check($lines[0]['extra_info']['wc_line_kind'], 'fee', 'native fee metadata');
	check($lines[0]['extra_info']['tax_amount'], $fee_case[1], 'exact signed service line tax');
}
$money_case = array(1, '1', '0.005', '1.01');
$money_items = array(array(1, '1', '0'));
$money_fees = array(new MoneyFee('0.005','0.005'));
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
check($payload['payments'][0]['amount'], '1.01', 'service fee payment stays exact');
check($payload['lines'][1]['extra_info']['line_total'], '0.01', 'service fee retains fractional source amount');
unset($money_fees, $money_items);
echo "PASS: fee service line and signed account adjustment precision\n";
// Load a native-variation test double only after exercising legacy mappings.
if (!class_exists('Hesabix_V2_Native_Variation_Sync')) {
	class Hesabix_V2_Native_Variation_Sync {
		public static function resolve_invoice_line($db, $variation, $parent) {
			return $variation === 42 && $parent === 1 ? array('product_id' => 901, 'variant_id' => 902) : null;
		}
		public static function has_native_parent_mapping($parent, $db) { return $parent === 1; }
	}
}
$money_case = array(3, '30.01', '3.01', '33.02');
$money_variation_id = 42;
$currency_response = array('success' => true, 'data' => array(array('id' => 1, 'code' => 'USD', 'decimal_places' => 2, 'round_monetary_amounts' => true)));
$commission_settings = array('gateway_settlement_mode' => 'fixed', 'gateway_settlement_fixed' => '0.25');
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1, null, true);
check($payload['lines'][0]['product_id'], 901, 'native parent product');
check($payload['lines'][0]['allocations'], array(array('variant_id' => 902, 'quantity' => 3)), 'native allocation preserved');
check($payload['lines'][0]['extra_info']['allocations'], $payload['lines'][0]['allocations'], 'native allocation metadata preserved');
check($payload['lines'][0]['extra_info']['unit'], 'main', 'native first sale main unit');
check($payload['lines'][0]['extra_info']['wc_line_kind'], 'product', 'native product metadata');
check($payload['payments'][0]['commission'], '0.25', 'native invoice commission exact');
check($payload['payments'][0]['amount'], '33.02', 'native payment amount');
unset($money_variation_id, $commission_settings);
echo "PASS: native variation allocation plus precise commission\n";
echo "PASS: decimal arithmetic, currency policy and eleven Mapper/payment/JSON cases\n";
