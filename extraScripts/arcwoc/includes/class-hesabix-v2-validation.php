<?php
/**
 * Data validation class
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

class Hesabix_V2_Validation
{
	/**
	 * Validate and sanitize product name
	 *
	 * @since    2.0.0
	 * @param    string    $name
	 * @return   string
	 */
	public static function sanitize_product_name($name)
	{
		if (empty($name)) {
			return 'محصول بدون نام';
		}
		
		// Remove extra spaces
		$name = preg_replace('/\s+/', ' ', $name);
		$name = trim($name);
		
		// Limit length
		if (mb_strlen($name) > 250) {
			$name = mb_substr($name, 0, 250);
		}
		
		return $name;
	}

	/**
	 * Validate and sanitize barcode
	 *
	 * @since    2.0.0
	 * @param    string    $barcode
	 * @return   string|null
	 */
	public static function sanitize_barcode($barcode)
	{
		if (empty($barcode)) {
			return null;
		}
		
		// Remove non-alphanumeric characters
		$barcode = preg_replace('/[^a-zA-Z0-9\-_]/', '', $barcode);
		
		// Limit length
		if (strlen($barcode) > 50) {
			$barcode = substr($barcode, 0, 50);
		}
		
		return $barcode;
	}

	/**
	 * Validate price
	 *
	 * @since    2.0.0
	 * @param    mixed    $price
	 * @return   float
	 */
	public static function sanitize_price($price)
	{
		if (empty($price) || !is_numeric($price)) {
			return 0.0;
		}
		
		return floatval($price);
	}

	/**
	 * Validate mobile number
	 *
	 * @since    2.0.0
	 * @param    string    $mobile
	 * @return   string|null
	 */
	public static function sanitize_mobile($mobile)
	{
		if (empty($mobile)) {
			return null;
		}
		
		// Remove non-numeric characters
		$mobile = preg_replace('/[^0-9]/', '', $mobile);
		
		// Check for valid Iranian mobile format
		if (preg_match('/^09\d{9}$/', $mobile)) {
			return $mobile;
		}
		
		if (preg_match('/^9\d{9}$/', $mobile)) {
			return '0' . $mobile;
		}
		
		if (preg_match('/^989\d{9}$/', $mobile)) {
			return '0' . substr($mobile, 2);
		}
		
		return null;
	}

	/**
	 * Validate email
	 *
	 * @since    2.0.0
	 * @param    string    $email
	 * @return   string|null
	 */
	public static function sanitize_email($email)
	{
		if (empty($email)) {
			return null;
		}
		
		$email = sanitize_email($email);
		
		if (!is_email($email)) {
			return null;
		}
		
		return $email;
	}

	/**
	 * Validate national ID (کد ملی)
	 *
	 * @since    2.0.0
	 * @param    string    $national_id
	 * @return   string|null
	 */
	public static function sanitize_national_id($national_id)
	{
		if (empty($national_id)) {
			return null;
		}
		
		// Remove non-numeric characters
		$national_id = preg_replace('/[^0-9]/', '', $national_id);
		
		// Check length
		if (strlen($national_id) !== 10) {
			return null;
		}
		
		return $national_id;
	}

	/**
	 * Validate postal code
	 *
	 * @since    2.0.0
	 * @param    string    $postal_code
	 * @return   string|null
	 */
	public static function sanitize_postal_code($postal_code)
	{
		if (empty($postal_code)) {
			return null;
		}
		
		// Remove non-numeric characters
		$postal_code = preg_replace('/[^0-9]/', '', $postal_code);
		
		// Check length (10 digits for Iran)
		if (strlen($postal_code) !== 10) {
			return null;
		}
		
		return $postal_code;
	}

	/**
	 * Sanitize address
	 *
	 * @since    2.0.0
	 * @param    string    $address
	 * @return   string|null
	 */
	public static function sanitize_address($address)
	{
		if (empty($address)) {
			return null;
		}
		
		$address = sanitize_textarea_field($address);
		
		// Limit length
		if (mb_strlen($address) > 500) {
			$address = mb_substr($address, 0, 500);
		}
		
		return $address;
	}
}

