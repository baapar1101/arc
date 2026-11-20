<?php
/** Run with: php extraScripts/arcwoc/tests/test-invoice-money-precision.php */
define('WPINC', true);
require_once __DIR__ . '/../includes/class-hesabix-v2-decimal.php';
require_once __DIR__ . '/../includes/class-hesabix-v2-currency-service.php';
require_once __DIR__ . '/../includes/class-hesabix-v2-mapper.php';

function check($actual, $expected, $name)
{
	if ($actual !== $expected) {
		throw new RuntimeException($name . ': ' . json_encode(array($actual, $expected)));
	}
}
function absint($v) { return abs((int) $v); }
function __($v, $domain = '') { return $v; }
function apply_filters($hook, $value, ...$args) { return $value; }
function get_transient($key) { return false; }
function set_transient(...$args) {}
function get_option($key, $default = false)
{
	return array('hesabix_v2_enabled' => true, 'hesabix_v2_business_id' => 1, 'hesabix_v2_currency_id' => 1,
		'hesabix_v2_invoice_payment_destination' => 'cash_register', 'hesabix_v2_default_cash_register_id' => '1')[$key] ?? $default;
}
function current_time($format) { return (new DateTimeImmutable('2026-11-11 12:00:00'))->format($format); }
class Hesabix_V2_Api
{
	public function get_business_currencies() { return $GLOBALS['currency_response']; }
}
class Hesabix_V2_DB_Service { public function get_hesabix_id(...$args) { return 1; } }
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
	public function get_product() { return new stdClass(); }
	public function get_product_id() { return 1; }
	public function get_variation_id() { return 0; }
	public function get_quantity() { return ($this->item ?? $GLOBALS['money_case'])[0]; }
	public function get_total() { return ($this->item ?? $GLOBALS['money_case'])[1]; }
	public function get_total_tax() { return ($this->item ?? $GLOBALS['money_case'])[2]; }
	public function get_id() { return 77; }
}
class MoneyOrder
{
	public function get_items($type = 'line_item')
	{
		if ($type === 'fee') { return array(); }
		return isset($GLOBALS['money_items']) ? array_map(fn($item) => new MoneyItem($item), $GLOBALS['money_items']) : array(new MoneyItem());
	}
	public function get_total() { return $GLOBALS['money_case'][3]; }
	public function get_total_tax() { return $GLOBALS['money_case'][2]; }
	public function get_discount_total() { return '0'; }
	public function get_shipping_total() { return '0'; }
	public function get_currency() { return 'USD'; }
	public function get_id() { return 100; }
	public function get_order_number() { return '100'; }
	public function get_date_created() { return null; }
	public function get_date_paid() { return null; }
	public function is_paid() { return true; }
}
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
	check($payload['lines'][0]['extra_info']['tax_amount'], $items[0][2], 'unrounded tax share');
}
unset($money_items);
$money_case = array(1, '0.01', '0.005', '0.02');
$payload = Hesabix_V2_Mapper::wc_order_to_invoice(new MoneyOrder(), 1, 1, 1);
check($payload['lines'][0]['extra_info']['unit_price'], '0.01', 'half-cent must not increase revenue');
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
	check(is_string($wire['lines'][0]['extra_info']['unit_price']), true, 'price remains a decimal string');
}
try {
	Hesabix_V2_Decimal::money('999999999.99000001', array('decimal_places' => 8, 'round_monetary_amounts' => true));
	throw new LogicException('Unsupported GL precision was accepted');
} catch (RuntimeException $e) {
}
echo "PASS: decimal arithmetic, currency policy and ten Mapper/payment/JSON cases\n";
