<?php
/**
 * نام استان‌های ایران برای پیشنهاد در فیلتر (datalist) — دادهٔ ثابت لوکال.
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * @return array<int, string>
 */
function shabake_tamin_get_iran_provinces() {
	static $provinces = null;
	if ( null !== $provinces ) {
		return $provinces;
	}

	$provinces = array(
		'آذربایجان شرقی',
		'آذربایجان غربی',
		'اردبیل',
		'اصفهان',
		'البرز',
		'ایلام',
		'بوشهر',
		'تهران',
		'چهارمحال و بختیاری',
		'خراسان جنوبی',
		'خراسان رضوی',
		'خراسان شمالی',
		'خوزستان',
		'زنجان',
		'سمنان',
		'سیستان و بلوچستان',
		'فارس',
		'قزوین',
		'قم',
		'کردستان',
		'کرمان',
		'کرمانشاه',
		'کهگیلویه و بویراحمد',
		'گلستان',
		'گیلان',
		'لرستان',
		'مازندران',
		'مرکزی',
		'هرمزگان',
		'همدان',
		'یزد',
	);

	/**
	 * فیلتر لیست استان‌های پیشنهادی (مثلاً برای استان‌های محدود یا ترجمه).
	 *
	 * @param array<int, string> $provinces لیست اولیه.
	 */
	return apply_filters( 'shabake_tamin_iran_provinces', $provinces );
}
