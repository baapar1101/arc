<?php
/**
 * Customer Service
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Customer_Service
{
	/**
	 * Get all WooCommerce customers
	 *
	 * @since    2.0.0
	 * @param    array    $args
	 * @return   array
	 */
	public static function get_all_customers($args = array())
	{
		$default_args = array(
			'role__in' => array('customer', 'subscriber'),
			'fields' => 'ID',
			'number' => -1,
		);

		$args = array_merge($default_args, $args);
		
		return get_users($args);
	}

	/**
	 * تعداد کاربران با نقش مشتری/مشترک برای همگام‌سازی.
	 *
	 * @since 2.0.7
	 * @return int
	 */
	public static function count_sync_customers()
	{
		$q = new WP_User_Query(
			array(
				'role__in' => array('customer', 'subscriber'),
				'number' => 1,
				'count_total' => true,
				'fields' => 'ID',
			)
		);

		return (int) $q->get_total();
	}

	/**
	 * اسلایس شناسهٔ مشتریان برای همگام‌سازی دسته‌ای.
	 *
	 * @since 2.0.7
	 * @param int $limit
	 * @param int $offset
	 * @return array<int>
	 */
	public static function get_sync_customer_ids_slice($limit, $offset)
	{
		$limit = max(1, (int) $limit);
		$offset = max(0, (int) $offset);

		$ids = get_users(
			array(
				'role__in' => array('customer', 'subscriber'),
				'fields' => 'ID',
				'number' => $limit,
				'offset' => $offset,
			)
		);

		if (!is_array($ids)) {
			return array();
		}

		return array_map('intval', $ids);
	}

	/**
	 * Get sync status for customer
	 *
	 * @since    2.0.0
	 * @param    int    $customer_id
	 * @return   array|null
	 */
	public static function get_sync_status($customer_id)
	{
		$db = new Hesabix_V2_DB_Service();
		return $db->get_mapping('customer', $customer_id);
	}

	/**
	 * یافتن کاربر وردپرس با ایمیل معتبر یا تطبیق نزدیک موبایل صورت‌حساب.
	 *
	 * @param string|null $email   ایمیل سنج‌شده یا null
	 * @param string|null $mobile  موبایل نرمال‌شده (۰۹…) یا null
	 * @return int شناسه کاربر یا ۰
	 */
	public static function find_user_id_by_email_or_mobile($email, $mobile)
	{
		if ($email && is_email($email)) {
			$user = get_user_by('email', $email);
			if ($user) {
				return (int) $user->ID;
			}
		}

		if ($mobile) {
			$found = self::find_user_by_billing_phone_meta((string) $mobile);
			if ($found > 0) {
				return $found;
			}
		}

		return 0;
	}

	/**
	 * جستجوی user_id بر اساس متای billing_phone.
	 *
	 * @param string $normalized_mobile مثل خروجی sanitize_mobile
	 * @return int
	 */
	private static function find_user_by_billing_phone_meta($normalized_mobile)
	{
		global $wpdb;

		if ($normalized_mobile === '') {
			return 0;
		}

		$digits = preg_replace('/[^0-9]/', '', $normalized_mobile);
		if ($digits === '') {
			return 0;
		}

		$last10 = strlen($digits) >= 10 ? substr($digits, -10) : $digits;

		$uids = $wpdb->get_col(
			$wpdb->prepare(
				"SELECT user_id FROM {$wpdb->usermeta} WHERE meta_key = %s AND meta_value LIKE %s LIMIT 25",
				'billing_phone',
				'%' . $wpdb->esc_like($last10) . '%'
			)
		);

		foreach ($uids as $uid) {
			$uid = (int) $uid;
			if ($uid < 1) {
				continue;
			}
			$ph = get_user_meta($uid, 'billing_phone', true);
			$san = Hesabix_V2_Validation::sanitize_mobile((string) $ph);
			if (!$san) {
				continue;
			}
			if ($san === $normalized_mobile || substr($san, -10) === $last10) {
				return $uid;
			}
		}

		return 0;
	}
}

