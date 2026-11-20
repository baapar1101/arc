<?php
/** Decimal-string arithmetic for invoice payloads; no float or optional extension. */
class Hesabix_V2_Decimal
{
	private static function parts($value)
	{
		$text = is_float($value) ? json_encode($value, JSON_PRESERVE_ZERO_FRACTION) : (string) $value;
		if (!preg_match('/^([+-]?)([0-9]+)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$/', trim($text), $m)) {
			throw new InvalidArgumentException('Invalid decimal amount');
		}
		$fraction = isset($m[3]) ? $m[3] : '';
		$scale = strlen($fraction) - (isset($m[4]) ? (int) $m[4] : 0);
		$digits = ltrim($m[2] . $fraction, '0');
		if ($scale < 0) {
			$digits .= str_repeat('0', -$scale);
			$scale = 0;
		}
		return array($m[1] === '-' ? -1 : 1, $digits === '' ? '0' : $digits, $scale);
	}

	private static function render($sign, $digits, $scale)
	{
		$digits = ltrim($digits, '0');
		if ($digits === '') {
			return '0';
		}
		if ($scale > 0) {
			$digits = str_pad($digits, $scale + 1, '0', STR_PAD_LEFT);
			$digits = rtrim(substr($digits, 0, -$scale) . '.' . substr($digits, -$scale), '0');
			$digits = rtrim($digits, '.');
		}
		return ($sign < 0 ? '-' : '') . $digits;
	}

	private static function cmp_digits($a, $b)
	{
		$a = ltrim($a, '0');
		$b = ltrim($b, '0');
		return strlen($a) !== strlen($b) ? strlen($a) <=> strlen($b) : strcmp($a, $b);
	}

	private static function add_digits($a, $b)
	{
		$out = '';
		$carry = 0;
		for ($i = strlen($a) - 1, $j = strlen($b) - 1; $i >= 0 || $j >= 0 || $carry; $i--, $j--) {
			$n = ($i >= 0 ? (int) $a[$i] : 0) + ($j >= 0 ? (int) $b[$j] : 0) + $carry;
			$out = ($n % 10) . $out;
			$carry = intdiv($n, 10);
		}
		return $out;
	}

	private static function sub_digits($a, $b)
	{
		$out = '';
		$borrow = 0;
		for ($i = strlen($a) - 1, $j = strlen($b) - 1; $i >= 0; $i--, $j--) {
			$n = (int) $a[$i] - ($j >= 0 ? (int) $b[$j] : 0) - $borrow;
			$borrow = $n < 0 ? 1 : 0;
			$out = ($n < 0 ? $n + 10 : $n) . $out;
		}
		return ltrim($out, '0') ?: '0';
	}

	public static function add($a, $b)
	{
		list($sa, $a, $pa) = self::parts($a);
		list($sb, $b, $pb) = self::parts($b);
		$scale = max($pa, $pb);
		$a .= str_repeat('0', $scale - $pa);
		$b .= str_repeat('0', $scale - $pb);
		if ($sa === $sb) {
			return self::render($sa, self::add_digits($a, $b), $scale);
		}
		return self::cmp_digits($a, $b) >= 0
			? self::render($sa, self::sub_digits($a, $b), $scale)
			: self::render($sb, self::sub_digits($b, $a), $scale);
	}

	public static function subtract($a, $b)
	{
		$b = self::add($b, '0');
		return self::add($a, strpos($b, '-') === 0 ? substr($b, 1) : '-' . $b);
	}

	public static function multiply($a, $b)
	{
		list($sa, $a, $pa) = self::parts($a);
		list($sb, $b, $pb) = self::parts($b);
		$out = '0';
		for ($i = strlen($b) - 1, $zeros = ''; $i >= 0; $i--, $zeros .= '0') {
			$row = '0';
			for ($n = 0; $n < (int) $b[$i]; $n++) {
				$row = self::add_digits($row, $a);
			}
			$out = self::add_digits($out, $row . $zeros);
		}
		return self::render($sa * $sb, $out, $pa + $pb);
	}

	public static function divide($a, $b, $places = 24)
	{
		list($sa, $a, $pa) = self::parts($a);
		list($sb, $b, $pb) = self::parts($b);
		if ($b === '0') {
			throw new InvalidArgumentException('Division by zero');
		}
		$a .= str_repeat('0', $pb + $places);
		$b .= str_repeat('0', $pa);
		$remainder = '0';
		$out = '';
		for ($i = 0; $i < strlen($a); $i++) {
			$remainder = ltrim($remainder . $a[$i], '0') ?: '0';
			$digit = 0;
			while (self::cmp_digits($remainder, $b) >= 0) {
				$remainder = self::sub_digits($remainder, $b);
				$digit++;
			}
			$out .= (string) $digit;
		}
		return self::render($sa * $sb, $out, $places);
	}

	public static function round($value, $places)
	{
		list($sign, $digits, $scale) = self::parts($value);
		if ($scale <= $places) {
			return self::render($sign, $digits, $scale);
		}
		$cut = $scale - $places;
		$digits = str_pad($digits, $cut + 1, '0', STR_PAD_LEFT);
		$head = substr($digits, 0, -$cut);
		if ((int) $digits[strlen($digits) - $cut] >= 5) {
			$head = self::add_digits($head, '1');
		}
		return self::render($sign, $head, $places);
	}

	/** A positive unit quotient must not put an exact half-cent below its boundary. */
	public static function unit_price($amount, $quantity)
	{
		$price = self::divide($amount, $quantity);
		if (self::subtract(self::multiply($price, $quantity), $amount) !== '0') {
			$negative = (strpos((string) $amount, '-') === 0) !== (strpos((string) $quantity, '-') === 0);
			$price = self::add($price, ($negative ? '-' : '') . '0.000000000000000000000001');
		}
		return $price;
	}

	public static function compare($a, $b)
	{
		$delta = self::subtract($a, $b);
		return $delta === '0' ? 0 : (strpos($delta, '-') === 0 ? -1 : 1);
	}

	public static function money($value, array $policy)
	{
		$value = !empty($policy['round_monetary_amounts']) ? self::round($value, $policy['decimal_places']) : self::add($value, '0');
		if (self::subtract($value, self::round($value, 2)) !== '0') {
			throw new RuntimeException('مبلغ سفارش بیش از دو رقم اعشار دارد و در دفتر کل فعلی حسابیکس قابل حفظ نیست.');
		}
		return $value;
	}
}
