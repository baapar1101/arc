<?php
/**
 * ساخت payload همگام‌سازی محصول WC → Hesabix با تفکیک CREATE/UPDATE و preset مالکیت فیلد.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Product_Sync_Payload
{
	public const PRESET_IMPORT_ONLY = 'import_only';
	public const PRESET_ACCOUNTING = 'accounting';
	public const PRESET_LIVE_STORE = 'live_store';
	public const PRESET_ADVANCED = 'advanced';

	/**
	 * فیلدهایی که ووکامرس منبع معتبر برای آن‌ها ندارد یا مالکیت حسابیکس است.
	 *
	 * @return string[]
	 */
	public static function hesabix_owned_fields()
	{
		return array(
			'base_purchase_price',
			'base_purchase_note',
		);
	}

	/**
	 * @return string[]
	 */
	public static function preset_choices()
	{
		return array(
			self::PRESET_IMPORT_ONLY,
			self::PRESET_ACCOUNTING,
			self::PRESET_LIVE_STORE,
			self::PRESET_ADVANCED,
		);
	}

	/**
	 * @param array<string, mixed> $sync
	 * @return array<string, mixed>
	 */
	public static function normalize_sync_settings($sync)
	{
		if (!is_array($sync)) {
			$sync = array();
		}

		$preset = isset($sync['product_sync_preset']) ? sanitize_key((string) $sync['product_sync_preset']) : '';
		if ($preset === '' || !in_array($preset, self::preset_choices(), true)) {
			$preset = self::PRESET_ACCOUNTING;
		}
		$sync['product_sync_preset'] = $preset;

		$sync['sync_product_name'] = !empty($sync['sync_product_name']);
		$sync['sync_product_description'] = !empty($sync['sync_product_description']);
		$sync['sync_product_barcode'] = !empty($sync['sync_product_barcode']);

		return $sync;
	}

	/**
	 * پرچم‌های مؤثر همگام‌سازی فیلد بر اساس preset و تنظیمات ذخیره‌شده.
	 *
	 * @param array<string, mixed> $sync_settings
	 * @return array<string, bool>
	 */
	public static function effective_field_flags(array $sync_settings)
	{
		$sync_settings = self::normalize_sync_settings($sync_settings);
		$preset = $sync_settings['product_sync_preset'];

		$flags = array(
			'sync_product_name' => false,
			'sync_product_description' => false,
			'sync_product_barcode' => false,
			'sync_product_price' => false,
			'sync_product_categories' => false,
			'sync_product_stock' => false,
			'sync_item_type' => false,
			'sync_main_unit' => false,
		);

		switch ($preset) {
			case self::PRESET_IMPORT_ONLY:
				break;

			case self::PRESET_LIVE_STORE:
				$flags['sync_product_name'] = true;
				$flags['sync_product_description'] = true;
				$flags['sync_product_barcode'] = true;
				$flags['sync_product_price'] = true;
				$flags['sync_product_categories'] = true;
				$flags['sync_product_stock'] = !empty($sync_settings['sync_product_stock']);
				$flags['sync_item_type'] = true;
				break;

			case self::PRESET_ADVANCED:
				$flags['sync_product_name'] = !empty($sync_settings['sync_product_name']);
				$flags['sync_product_description'] = !empty($sync_settings['sync_product_description']);
				$flags['sync_product_barcode'] = !empty($sync_settings['sync_product_barcode']);
				$flags['sync_product_price'] = !empty($sync_settings['sync_product_price']);
				$flags['sync_product_categories'] = !isset($sync_settings['sync_product_categories']) || !empty($sync_settings['sync_product_categories']);
				$flags['sync_product_stock'] = !empty($sync_settings['sync_product_stock']);
				$flags['sync_item_type'] = !empty($sync_settings['sync_product_name']);
				break;

			case self::PRESET_ACCOUNTING:
			default:
				// هویت فروشگاهی (نام) از ووکامرس می‌آید؛ داده‌های مالی حسابیکس حفظ می‌شوند.
				$flags['sync_product_name'] = true;
				$flags['sync_product_price'] = !empty($sync_settings['sync_product_price']);
				$flags['sync_product_stock'] = !empty($sync_settings['sync_product_stock']);
				break;
		}

		return $flags;
	}

	/**
	 * @param array<string, mixed> $data
	 * @param bool                 $is_update
	 * @param array<string, mixed> $sync_settings
	 * @param WC_Product           $wc_product
	 * @param int                  $wc_id
	 * @param int|null             $wc_parent_id
	 * @return array<string, mixed>
	 */
	public static function prepare(array $data, $is_update, array $sync_settings, $wc_product, $wc_id, $wc_parent_id = null)
	{
		foreach (self::hesabix_owned_fields() as $owned_key) {
			unset($data[ $owned_key ]);
		}

		if (!$is_update) {
			if (empty($sync_settings['sync_product_price'])) {
				unset($data['base_sales_price']);
			}

			if (!empty($sync_settings['sync_product_stock'])) {
				$policy = isset($sync_settings['track_inventory_policy']) ? (string) $sync_settings['track_inventory_policy'] : 'wc';
				$data['track_inventory'] = Hesabix_V2_Mapper::resolve_track_inventory_by_policy($wc_product, $policy);
			} else {
				$data['track_inventory'] = false;
			}

			if (empty($sync_settings['sync_product_categories'])) {
				unset($data['category_id']);
			}

			/**
			 * فیلتر نهایی payload محصول قبل از ارسال به API حسابیکس.
			 *
			 * @param array<string, mixed> $data
			 * @param WC_Product           $wc_product
			 * @param int                  $wc_id
			 * @param bool                 $is_update
			 * @param int|null             $wc_parent_id
			 */
			$data = apply_filters('hesabix_v2_product_data', $data, $wc_product, $wc_id, $is_update, $wc_parent_id);

			return self::prune_empty_payload($data);
		}

		$flags = self::effective_field_flags($sync_settings);

		unset($data['is_active']);

		if (empty($flags['sync_product_name'])) {
			unset($data['name']);
		}
		if (empty($flags['sync_item_type'])) {
			unset($data['item_type']);
		}
		if (empty($flags['sync_main_unit'])) {
			unset($data['main_unit']);
		}
		if (empty($flags['sync_product_description'])) {
			unset($data['description']);
		} elseif (!isset($data['description']) || $data['description'] === null || $data['description'] === '') {
			unset($data['description']);
		}
		if (empty($flags['sync_product_barcode'])) {
			unset($data['barcode']);
		} elseif (!isset($data['barcode']) || $data['barcode'] === null || $data['barcode'] === '') {
			unset($data['barcode']);
		}
		if (empty($flags['sync_product_price'])) {
			unset($data['base_sales_price']);
		}
		if (empty($flags['sync_product_categories'])) {
			unset($data['category_id']);
		}

		if (!empty($flags['sync_product_stock'])) {
			$policy = isset($sync_settings['track_inventory_policy']) ? (string) $sync_settings['track_inventory_policy'] : 'wc';
			$data['track_inventory'] = Hesabix_V2_Mapper::resolve_track_inventory_by_policy($wc_product, $policy);
		} else {
			unset($data['track_inventory']);
		}

		/**
		 * فیلتر نهایی payload محصول قبل از ارسال به API حسابیکس.
		 *
		 * @param array<string, mixed> $data
		 * @param WC_Product           $wc_product
		 * @param int                  $wc_id
		 * @param bool                 $is_update
		 * @param int|null             $wc_parent_id
		 */
		$data = apply_filters('hesabix_v2_product_data', $data, $wc_product, $wc_id, $is_update, $wc_parent_id);

		return self::prune_empty_payload($data);
	}

	/**
	 * @param array<string, mixed> $data
	 * @return array<string, mixed>
	 */
	public static function prune_empty_payload(array $data)
	{
		foreach ($data as $key => $value) {
			if ($value === null) {
				unset($data[ $key ]);
			}
		}

		return $data;
	}

	/**
	 * @param array<string, mixed> $data
	 * @return bool
	 */
	public static function is_noop_update(array $data)
	{
		return count($data) === 0;
	}
}
