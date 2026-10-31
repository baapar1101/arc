<?php
/**
 * مسیر Native ووکامرس: محصول متغیر → یک کالای حسابیکس با variant_mode=inventory.
 * مسیر Legacy (هر واریانت = یک کالا) دست‌نخورده می‌ماند و پیش‌فرض است.
 *
 * @since      4.11.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Native_Variation_Sync
{
	const MODE_LEGACY = 'legacy';
	const MODE_NATIVE = 'native';
	const MAX_DIMENSIONS = 2;
	const MAX_VARIANTS = 100;

	/**
	 * @param array $sync
	 * @return string
	 */
	public static function normalize_mode($sync)
	{
		$mode = isset($sync['product_variation_mode']) ? sanitize_key((string) $sync['product_variation_mode']) : self::MODE_LEGACY;
		if (!in_array($mode, array(self::MODE_LEGACY, self::MODE_NATIVE), true)) {
			return self::MODE_LEGACY;
		}
		return $mode;
	}

	/**
	 * @return bool
	 */
	public static function is_native_setting_enabled()
	{
		$sync = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
		return self::normalize_mode($sync) === self::MODE_NATIVE;
	}

	/**
	 * @param array|null $row
	 * @return array<string, mixed>
	 */
	public static function mapping_meta($row)
	{
		if (!is_array($row) || empty($row['meta_data'])) {
			return array();
		}
		if (is_array($row['meta_data'])) {
			return $row['meta_data'];
		}
		$decoded = json_decode((string) $row['meta_data'], true);
		return is_array($decoded) ? $decoded : array();
	}

	/**
	 * آیا این والد قبلاً Native نگاشت شده است؟
	 *
	 * @param int                    $parent_id
	 * @param Hesabix_V2_DB_Service  $db
	 * @return bool
	 */
	public static function has_native_parent_mapping($parent_id, $db)
	{
		$parent_id = absint($parent_id);
		$row = $db->get_mapping('product', $parent_id, null);
		if ($row) {
			$meta = self::mapping_meta($row);
			if (!empty($meta['native_variation'])) {
				return true;
			}
		}
		foreach (self::list_child_variation_ids($parent_id) as $vid) {
			$vr = $db->get_mapping('variation', $vid, $parent_id);
			if ($vr && isset($vr['hesabix_type']) && $vr['hesabix_type'] === 'product_variant') {
				return true;
			}
		}
		return false;
	}

	/**
	 * نگاشت Legacy «هر واریانت = یک کالا» برای این والد وجود دارد؟
	 *
	 * @param int                   $parent_id
	 * @param Hesabix_V2_DB_Service $db
	 * @return bool
	 */
	public static function has_legacy_child_product_mappings($parent_id, $db)
	{
		$parent_id = absint($parent_id);
		foreach (self::list_child_variation_ids($parent_id) as $vid) {
			$row = $db->get_mapping('product', $vid, $parent_id);
			if ($row && !empty($row['hesabix_id'])) {
				$type = isset($row['hesabix_type']) ? (string) $row['hesabix_type'] : 'product';
				if ($type !== 'product_variant') {
					return true;
				}
			}
		}
		return false;
	}

	/**
	 * Native فقط برای کالای جدید یا قبلاً Native؛ کالای Legacy-mapped هرگز auto-convert نمی‌شود.
	 *
	 * @param int                   $parent_id
	 * @param Hesabix_V2_DB_Service $db
	 * @return bool
	 */
	public static function should_sync_parent_as_native($parent_id, $db)
	{
		$parent_id = absint($parent_id);
		if ($parent_id < 1 || !$db) {
			return false;
		}
		if (self::has_native_parent_mapping($parent_id, $db)) {
			// کالای قبلاً Native هرگز به Legacy برنمی‌گردد؛ خطا در sync گزارش می‌شود.
			return true;
		}
		if (self::has_legacy_child_product_mappings($parent_id, $db)) {
			return false;
		}
		if (!self::is_native_setting_enabled()) {
			return false;
		}
		$parent = wc_get_product($parent_id);
		if (!$parent || !$parent->is_type('variable')) {
			return false;
		}
		$dims = self::collect_variation_dimensions($parent);
		$n = count($dims);
		return $n >= 1 && $n <= self::MAX_DIMENSIONS;
	}

	/**
	 * @param int $parent_id
	 * @return int[]
	 */
	public static function list_child_variation_ids($parent_id)
	{
		$parent = wc_get_product(absint($parent_id));
		if (!$parent || !method_exists($parent, 'get_children')) {
			return array();
		}
		$out = array();
		foreach ((array) $parent->get_children() as $vid) {
			$vid = absint($vid);
			if ($vid > 0) {
				$out[] = $vid;
			}
		}
		return $out;
	}

	/**
	 * خط فاکتور Native: product_id والد حسابیکس + variant_id.
	 *
	 * @param Hesabix_V2_DB_Service $db
	 * @param int                   $variation_id
	 * @param int                   $parent_id
	 * @return array{product_id:int,variant_id:int}|null
	 */
	public static function resolve_invoice_line($db, $variation_id, $parent_id)
	{
		$variation_id = absint($variation_id);
		$parent_id = absint($parent_id);
		if ($variation_id < 1 || $parent_id < 1) {
			return null;
		}
		$row = $db->get_mapping('variation', $variation_id, $parent_id);
		if (!$row || empty($row['hesabix_id'])) {
			return null;
		}
		if (isset($row['hesabix_type']) && $row['hesabix_type'] !== 'product_variant') {
			return null;
		}
		$meta = self::mapping_meta($row);
		$product_id = isset($meta['hesabix_product_id']) ? absint($meta['hesabix_product_id']) : 0;
		if ($product_id < 1) {
			$parent_map = $db->get_mapping('product', $parent_id, null);
			$product_id = $parent_map && !empty($parent_map['hesabix_id']) ? absint($parent_map['hesabix_id']) : 0;
		}
		$variant_id = absint($row['hesabix_id']);
		if ($product_id < 1 || $variant_id < 1) {
			return null;
		}
		return array(
			'product_id' => $product_id,
			'variant_id' => $variant_id,
		);
	}

	/**
	 * @param Hesabix_V2_Sync_Service $sync
	 * @param int                     $parent_id
	 * @param int|null                $variation_id
	 * @param string|null             $wc_currency_override
	 * @return array
	 */
	public static function sync($sync, $parent_id, $variation_id = null, $wc_currency_override = null)
	{
		$start_time = microtime(true);
		$parent_id = absint($parent_id);
		$variation_id = ($variation_id !== null && (int) $variation_id > 0) ? absint($variation_id) : null;

		try {
			$gate = Hesabix_V2_Currency_Service::evaluate_currency_sync($sync->api_client(), $wc_currency_override);
			if (!$gate['ok']) {
				return array(
					'success' => false,
					'message' => $gate['message'],
					'currency_blocked' => true,
					'native' => true,
				);
			}

			$parent = wc_get_product($parent_id);
			if (!$parent || !$parent->is_type('variable')) {
				return array(
					'success' => false,
					'message' => __('محصول متغیر یافت نشد', 'hesabix-v2'),
					'native' => true,
				);
			}

			$status_ok = Hesabix_V2_Product_Service::is_syncable_product($parent, null);
			$should_sync = (bool) apply_filters('hesabix_v2_should_sync_product', $status_ok, $parent);
			if (!$should_sync) {
				$message = $status_ok
					? __('همگام‌سازی رد شد — فیلتر سفارشی همگام‌سازی را مسدود کرد.', 'hesabix-v2')
					: __('همگام‌سازی رد شد — فقط محصولات منتشرشده به حسابیکس ارسال می‌شوند (پیش‌نویس همگام نمی‌شود).', 'hesabix-v2');
				return array(
					'success' => true,
					'skipped_status' => !$status_ok,
					'skipped_filter' => $status_ok,
					'message' => $message,
					'execution_time' => microtime(true) - $start_time,
					'native' => true,
					'variable_parent_id' => $parent_id,
				);
			}

			$dims = self::collect_variation_dimensions($parent);
			if (count($dims) < 1 || count($dims) > self::MAX_DIMENSIONS) {
				return array(
					'success' => false,
					'message' => __('مسیر Native فقط برای محصول متغیر با یک یا دو ویژگی واریانت است.', 'hesabix-v2'),
					'native' => true,
				);
			}

			$children = self::list_child_variation_ids($parent_id);
			if (empty($children)) {
				return array(
					'success' => true,
					'skipped_empty_variable' => true,
					'message' => __('محصول متغیر بدون واریانت — همگام‌سازی انجام نشد.', 'hesabix-v2'),
					'native' => true,
					'variable_parent_id' => $parent_id,
					'execution_time' => microtime(true) - $start_time,
				);
			}

			$plans = array();
			foreach ($children as $vid) {
				$variation = wc_get_product($vid);
				if (!$variation || !$variation->is_type('variation')) {
					continue;
				}
				if (!Hesabix_V2_Product_Service::is_syncable_product($variation, $parent)) {
					continue;
				}
				$combo = self::variation_combination($variation, $dims);
				if ($combo === null) {
					continue;
				}
				$plans[] = array(
					'wc_id' => $vid,
					'combination' => $combo,
					'variation' => $variation,
				);
			}

			if (empty($plans)) {
				return array(
					'success' => true,
					'skipped_empty_variable' => true,
					'message' => __('واریانت کامل برای مسیر Native یافت نشد.', 'hesabix-v2'),
					'native' => true,
					'variable_parent_id' => $parent_id,
					'execution_time' => microtime(true) - $start_time,
				);
			}

			if (count($plans) > self::MAX_VARIANTS) {
				return array(
					'success' => false,
					'message' => sprintf(
						/* translators: %d: max variants */
						__('سقف تعداد ترکیب Native %d است.', 'hesabix-v2'),
						self::MAX_VARIANTS
					),
					'native' => true,
				);
			}

			$api = $sync->api_client();
			$db = $sync->db_client();
			$attr_map = self::ensure_hesabix_attributes($api, $dims);
			if (is_wp_error($attr_map)) {
				return array(
					'success' => false,
					'message' => $attr_map->get_error_message(),
					'native' => true,
				);
			}

			$attribute_ids = array();
			foreach ($dims as $dim) {
				$attribute_ids[] = (int) $attr_map[ $dim['key'] ]['attribute_id'];
			}

			$product_payload = Hesabix_V2_Mapper::wc_product_to_api($parent, $parent_id, $gate['factor']);
			$product_payload['attribute_ids'] = $attribute_ids;
			$product_payload['track_inventory'] = self::parent_should_track_inventory($parent);

			$sync_settings = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
			$existing_parent = $db->get_mapping('product', $parent_id, null);
			$is_native_parent = self::parent_mapping_is_native($existing_parent, $parent_id, $db);
			if ($existing_parent && !$is_native_parent) {
				self::orphan_non_native_parent_mapping($db, $parent, $parent_id, $existing_parent);
				$existing_parent = null;
			}
			$is_update = !empty($existing_parent);
			$product_payload = Hesabix_V2_Product_Sync_Payload::prepare(
				$product_payload,
				$is_update,
				$sync_settings,
				$parent,
				(int) $parent_id,
				null
			);
			$product_payload['attribute_ids'] = $attribute_ids;
			$product_payload['track_inventory'] = self::parent_should_track_inventory($parent);

			if ($is_update) {
				$api_res = $api->update_product((int) $existing_parent['hesabix_id'], $product_payload);
				$hesabix_product_id = (int) $existing_parent['hesabix_id'];
			} else {
				$api_res = $api->create_product($product_payload);
				$hesabix_product_id = Hesabix_V2_Api::extract_id($api_res);
			}

			if (empty($api_res['success']) || $hesabix_product_id < 1) {
				$msg = isset($api_res['message']) ? (string) $api_res['message'] : __('ایجاد کالای والد Native ناموفق بود.', 'hesabix-v2');
				return array(
					'success' => false,
					'message' => $msg,
					'native' => true,
				);
			}

			$db->save_mapping(
				'product',
				$parent_id,
				null,
				$hesabix_product_id,
				'product',
				array(
					'synced_at' => current_time('mysql'),
					'native_variation' => true,
				)
			);

			$dim_payload = array();
			$sort = 1;
			foreach ($dims as $dim) {
				$dim_payload[] = array(
					'attribute_id' => (int) $attr_map[ $dim['key'] ]['attribute_id'],
					'is_required' => true,
					'sort_order' => $sort,
				);
				$sort++;
			}

			$existing_dims = $api->get_variant_dimensions($hesabix_product_id);
			$existing_attr_ids = array();
			foreach (self::unwrap_api_list($existing_dims) as $row) {
				if (is_array($row) && isset($row['attribute_id'])) {
					$existing_attr_ids[] = (int) $row['attribute_id'];
				}
			}
			$wanted_attr_ids = array();
			foreach ($dim_payload as $row) {
				$wanted_attr_ids[] = (int) $row['attribute_id'];
			}
			sort($existing_attr_ids);
			$wanted_sorted = $wanted_attr_ids;
			sort($wanted_sorted);
			if ($existing_attr_ids !== $wanted_sorted) {
				$dim_res = $api->replace_variant_dimensions($hesabix_product_id, $dim_payload);
				if (empty($dim_res['success'])) {
					$msg = isset($dim_res['message']) ? (string) $dim_res['message'] : __('ثبت ابعاد Native ناموفق بود.', 'hesabix-v2');
					return array(
						'success' => false,
						'message' => $msg,
						'native' => true,
					);
				}
			}

			$existing_variants = self::index_existing_variants($api, $hesabix_product_id);
			$synced_variant_id = null;
			$ok = 0;

			foreach ($plans as $plan) {
				$values = array();
				$labels = array();
				foreach ($plan['combination'] as $key => $opt) {
					if (empty($attr_map[ $key ]['options'][ $opt['match'] ]['id'])) {
						return array(
							'success' => false,
							'message' => sprintf(
								/* translators: %s: option label */
								__('گزینه «%s» به ویژگی حسابیکس وصل نشد.', 'hesabix-v2'),
								isset($opt['label']) ? $opt['label'] : $opt['match']
							),
							'native' => true,
						);
					}
					$values[] = array(
						'attribute_id' => (int) $attr_map[ $key ]['attribute_id'],
						'option_id' => (int) $attr_map[ $key ]['options'][ $opt['match'] ]['id'],
					);
					$labels[] = $opt['label'];
				}
				$combo_key = self::combination_key_from_values($values);
				$variation = $plan['variation'];
				$body = array(
					'display_title' => implode(' / ', $labels),
					'is_active' => true,
					'attribute_values' => $values,
				);
				$barcode = Hesabix_V2_Validation::sanitize_barcode($variation->get_sku());
				if (is_string($barcode) && $barcode !== '') {
					$body['barcode'] = $barcode;
				}
				$sell = 0;
				if ($variation->get_regular_price()) {
					$sell = Hesabix_V2_Validation::sanitize_price((float) $variation->get_regular_price() * (float) $gate['factor']);
				} elseif ($variation->get_price()) {
					$sell = Hesabix_V2_Validation::sanitize_price((float) $variation->get_price() * (float) $gate['factor']);
				}
				if ($sell > 0) {
					$body['sales_price'] = (string) $sell;
				}

				$hx_variant_id = 0;
				if (isset($existing_variants[ $combo_key ])) {
					$hx_variant_id = (int) $existing_variants[ $combo_key ]['id'];
					$upd = $body;
					if (isset($existing_variants[ $combo_key ]['row_version'])) {
						$upd['row_version'] = (int) $existing_variants[ $combo_key ]['row_version'];
					}
					unset($upd['attribute_values']);
					$vres = $api->update_product_variant($hesabix_product_id, $hx_variant_id, $upd);
					if (empty($vres['success'])) {
						return array(
							'success' => false,
							'message' => isset($vres['message']) ? (string) $vres['message'] : __('به‌روزرسانی ترکیب Native ناموفق بود.', 'hesabix-v2'),
							'native' => true,
						);
					}
				} else {
					$vres = $api->create_product_variant($hesabix_product_id, $body);
					$hx_variant_id = Hesabix_V2_Api::extract_id($vres);
					if (empty($vres['success']) || $hx_variant_id < 1) {
						$existing_variants = self::index_existing_variants($api, $hesabix_product_id);
						if (empty($existing_variants[ $combo_key ]['id'])) {
							return array(
								'success' => false,
								'message' => isset($vres['message']) ? (string) $vres['message'] : __('ایجاد ترکیب Native ناموفق بود.', 'hesabix-v2'),
								'native' => true,
							);
						}
						$hx_variant_id = (int) $existing_variants[ $combo_key ]['id'];
						$upd = $body;
						if (isset($existing_variants[ $combo_key ]['row_version'])) {
							$upd['row_version'] = (int) $existing_variants[ $combo_key ]['row_version'];
						}
						unset($upd['attribute_values']);
						$api->update_product_variant($hesabix_product_id, $hx_variant_id, $upd);
					} else {
						$existing_variants[ $combo_key ] = array('id' => $hx_variant_id);
					}
				}

				$db->save_mapping(
					'variation',
					(int) $plan['wc_id'],
					$parent_id,
					$hx_variant_id,
					'product_variant',
					array(
						'native_variation' => true,
						'hesabix_product_id' => $hesabix_product_id,
						'combination_key' => $combo_key,
						'synced_at' => current_time('mysql'),
					)
				);
				$ok++;
				if ($variation_id !== null && (int) $plan['wc_id'] === (int) $variation_id) {
					$synced_variant_id = $hx_variant_id;
				}
			}

			if (self::parent_should_track_inventory($parent)) {
				$enable_res = self::ensure_inventory_mode($api, $hesabix_product_id);
				if (is_wp_error($enable_res)) {
					return array(
						'success' => false,
						'message' => $enable_res->get_error_message(),
						'native' => true,
						'hesabix_id' => $hesabix_product_id,
					);
				}
			}

			if ($synced_variant_id === null && $variation_id !== null) {
				$resolved = self::resolve_invoice_line($db, $variation_id, $parent_id);
				if ($resolved) {
					$synced_variant_id = (int) $resolved['variant_id'];
				}
			}

			$execution_time = microtime(true) - $start_time;
			Hesabix_V2_Log_Service::info('Native variable product synced', array(
				'entity_type' => 'product',
				'entity_id' => $parent_id,
				'hesabix_id' => $hesabix_product_id,
				'variations_synced' => $ok,
				'execution_time' => $execution_time,
			));

			return array(
				'success' => true,
				'native' => true,
				'hesabix_id' => $hesabix_product_id,
				'variant_id' => $synced_variant_id,
				'variable_parent_id' => $parent_id,
				'variations_synced' => $ok,
				'message' => sprintf(
					/* translators: %d: variation count */
					__('محصول متغیر Native: %d ترکیب در یک کالا همگام شد.', 'hesabix-v2'),
					$ok
				),
				'execution_time' => $execution_time,
			);
		} catch (Exception $e) {
			return array(
				'success' => false,
				'message' => $e->getMessage(),
				'native' => true,
			);
		}
	}

	/**
	 * @param WC_Product $parent
	 * @return bool
	 */
	private static function parent_should_track_inventory($parent)
	{
		if (!$parent || $parent->is_virtual()) {
			return false;
		}
		return true;
	}

	/**
	 * @param array|null            $row
	 * @param int                   $parent_id
	 * @param Hesabix_V2_DB_Service $db
	 * @return bool
	 */
	private static function parent_mapping_is_native($row, $parent_id, $db)
	{
		if (!is_array($row) || empty($row['hesabix_id'])) {
			return false;
		}
		$meta = self::mapping_meta($row);
		if (!empty($meta['native_variation'])) {
			return true;
		}
		foreach (self::list_child_variation_ids($parent_id) as $vid) {
			$vr = $db->get_mapping('variation', $vid, $parent_id);
			if ($vr && isset($vr['hesabix_type']) && $vr['hesabix_type'] === 'product_variant') {
				return true;
			}
		}
		return false;
	}

	/**
	 * نگاشت «والد متغیر به‌عنوان کالای ساده» را مثل Legacy یتیم می‌کند تا Native کالای جدید بسازد.
	 *
	 * @param Hesabix_V2_DB_Service $db
	 * @param WC_Product            $parent
	 * @param int                   $parent_id
	 * @param array                 $row
	 * @return void
	 */
	private static function orphan_non_native_parent_mapping($db, $parent, $parent_id, array $row)
	{
		$orphan_hid = isset($row['hesabix_id']) ? absint($row['hesabix_id']) : 0;
		if ($orphan_hid > 0 && class_exists('Hesabix_V2_Orphan_Product_Service')) {
			Hesabix_V2_Orphan_Product_Service::register(
				array(
					'hesabix_id' => $orphan_hid,
					'wc_parent_id' => $parent_id,
					'parent_name' => $parent ? $parent->get_title() : '',
					'source' => 'native_sync',
					'tier' => Hesabix_V2_Orphan_Product_Service::TIER_HIGH,
					'status' => 'pending',
					'force_reopen' => true,
				)
			);
		}
		$db->delete_parent_only_product_mapping($parent_id);
		Hesabix_V2_Log_Service::info('Native sync ignored non-native parent-as-simple mapping', array(
			'entity_type' => 'product',
			'entity_id' => $parent_id,
			'hesabix_id' => $orphan_hid > 0 ? $orphan_hid : null,
		));
	}

	/**
	 * @param Hesabix_V2_Api $api
	 * @param int            $product_id
	 * @return true|WP_Error
	 */
	private static function ensure_inventory_mode($api, $product_id)
	{
		$got = $api->get_product($product_id);
		$item = array();
		if (!empty($got['success']) && isset($got['data']) && is_array($got['data'])) {
			$item = isset($got['data']['item']) && is_array($got['data']['item']) ? $got['data']['item'] : $got['data'];
		}
		$mode = isset($item['variant_mode']) ? (string) $item['variant_mode'] : 'none';
		if ($mode === 'inventory') {
			return true;
		}

		$warehouse_id = absint(get_option('hesabix_v2_default_warehouse_id', 0));
		if ($warehouse_id < 1) {
			return new WP_Error(
				'hesabix_native_wh',
				__('برای مسیر Native باید انبار پیش‌فرض در تب فاکتور انتخاب شود.', 'hesabix-v2')
			);
		}

		$res = $api->enable_inventory_variants(
			$product_id,
			array(
				'warehouse_id' => $warehouse_id,
				'splits' => array(),
			)
		);
		if (empty($res['success'])) {
			return new WP_Error(
				'hesabix_native_enable',
				isset($res['message']) ? (string) $res['message'] : __('فعال‌سازی تفکیک موجودی Native ناموفق بود.', 'hesabix-v2')
			);
		}
		return true;
	}

	/**
	 * @param Hesabix_V2_Api $api
	 * @param int            $product_id
	 * @return array<string, array>
	 */
	private static function index_existing_variants($api, $product_id)
	{
		$res = $api->list_product_variants($product_id);
		$out = array();
		foreach (self::unwrap_api_list($res) as $row) {
			if (!is_array($row) || empty($row['id'])) {
				continue;
			}
			$key = isset($row['combination_key']) ? (string) $row['combination_key'] : '';
			if ($key === '' && !empty($row['attribute_values']) && is_array($row['attribute_values'])) {
				$key = self::combination_key_from_values($row['attribute_values']);
			}
			if ($key === '') {
				continue;
			}
			$out[ $key ] = $row;
		}
		return $out;
	}

	/**
	 * @param array $values
	 * @return string
	 */
	private static function combination_key_from_values(array $values)
	{
		$pairs = array();
		foreach ($values as $row) {
			if (!is_array($row)) {
				continue;
			}
			$aid = isset($row['attribute_id']) ? (int) $row['attribute_id'] : 0;
			$oid = isset($row['option_id']) ? (int) $row['option_id'] : 0;
			if ($aid > 0 && $oid > 0) {
				$pairs[ $aid ] = $oid;
			}
		}
		ksort($pairs, SORT_NUMERIC);
		$parts = array();
		foreach ($pairs as $aid => $oid) {
			$parts[] = $aid . ':' . $oid;
		}
		return implode('|', $parts);
	}

	/**
	 * @param Hesabix_V2_Api $api
	 * @param array          $dims
	 * @return array|WP_Error
	 */
	private static function ensure_hesabix_attributes($api, array $dims)
	{
		$map = array();
		foreach ($dims as $dim) {
			$labels = array();
			foreach ($dim['options'] as $opt) {
				$labels[] = $opt['label'];
			}
			$attr = self::find_or_create_select_attribute($api, $dim['title'], $labels);
			if (is_wp_error($attr)) {
				return $attr;
			}
			$opt_index = array();
			foreach ($attr['option_items'] as $item) {
				$opt_index[ self::norm_label($item['label']) ] = $item;
				if (!empty($item['normalized_label'])) {
					$opt_index[ self::norm_label($item['normalized_label']) ] = $item;
				}
			}
			$options_by_match = array();
			foreach ($dim['options'] as $opt) {
				$hit = null;
				$nlabel = self::norm_label($opt['label']);
				$nslug = self::norm_label($opt['slug']);
				if (isset($opt_index[ $nlabel ])) {
					$hit = $opt_index[ $nlabel ];
				} elseif ($nslug !== '' && isset($opt_index[ $nslug ])) {
					$hit = $opt_index[ $nslug ];
				}
				if (!$hit) {
					return new WP_Error(
						'hesabix_native_opt',
						sprintf(
							/* translators: %s: option label */
							__('گزینه «%s» در حسابیکس ساخته نشد.', 'hesabix-v2'),
							$opt['label']
						)
					);
				}
				$options_by_match[ $opt['slug'] ] = $hit;
				$options_by_match[ $opt['label'] ] = $hit;
				$options_by_match[ $nlabel ] = $hit;
				$options_by_match[ $nslug ] = $hit;
			}
			$map[ $dim['key'] ] = array(
				'attribute_id' => (int) $attr['id'],
				'options' => $options_by_match,
			);
		}
		return $map;
	}

	/**
	 * @param Hesabix_V2_Api $api
	 * @param string         $title
	 * @param string[]       $labels
	 * @return array|WP_Error
	 */
	private static function find_or_create_select_attribute($api, $title, array $labels)
	{
		$title = trim((string) $title);
		$labels = array_values(array_unique(array_filter(array_map('strval', $labels))));
		if ($title === '' || empty($labels)) {
			return new WP_Error('hesabix_native_attr', __('عنوان یا گزینه ویژگی Native خالی است.', 'hesabix-v2'));
		}

		$found = self::find_attribute_by_title($api, $title);
		if ($found) {
			$data_type = isset($found['data_type']) ? (string) $found['data_type'] : 'text';
			if ($data_type !== 'select') {
				$title = $title . ' — Woo';
				$found = self::find_attribute_by_title($api, $title);
			}
		}

		if ($found && (isset($found['data_type']) ? $found['data_type'] : 'select') === 'select') {
			$existing_labels = array();
			if (!empty($found['options']) && is_array($found['options'])) {
				foreach ($found['options'] as $lab) {
					$existing_labels[] = (string) $lab;
				}
			}
			$merged = $existing_labels;
			foreach ($labels as $lab) {
				$hit = false;
				foreach ($existing_labels as $ex) {
					if (self::norm_label($ex) === self::norm_label($lab)) {
						$hit = true;
						break;
					}
				}
				if (!$hit) {
					$merged[] = $lab;
				}
			}
			if ($merged !== $existing_labels) {
				$upd = $api->update_product_attribute(
					(int) $found['id'],
					array(
						'data_type' => 'select',
						'options' => $merged,
					)
				);
				if (empty($upd['success'])) {
					return new WP_Error(
						'hesabix_native_attr',
						isset($upd['message']) ? (string) $upd['message'] : __('به‌روزرسانی ویژگی Native ناموفق بود.', 'hesabix-v2')
					);
				}
				$found = self::unwrap_attribute($upd);
			}
			if (empty($found['option_items'])) {
				$got = $api->get_product_attribute((int) $found['id']);
				$found = self::unwrap_attribute($got);
			}
			return $found;
		}

		$created = $api->create_product_attribute(
			array(
				'title' => $title,
				'data_type' => 'select',
				'options' => $labels,
			)
		);
		if (empty($created['success'])) {
			$retry = self::find_attribute_by_title($api, $title);
			if ($retry && (isset($retry['data_type']) ? $retry['data_type'] : '') === 'select') {
				return self::find_or_create_select_attribute($api, $title, $labels);
			}
			return new WP_Error(
				'hesabix_native_attr',
				isset($created['message']) ? (string) $created['message'] : __('ایجاد ویژگی Native ناموفق بود.', 'hesabix-v2')
			);
		}
		$attr = self::unwrap_attribute($created);
		if (empty($attr['id'])) {
			return new WP_Error('hesabix_native_attr', __('شناسه ویژگی Native در پاسخ نیست.', 'hesabix-v2'));
		}
		return $attr;
	}

	/**
	 * @param Hesabix_V2_Api $api
	 * @param string         $title
	 * @return array|null
	 */
	private static function find_attribute_by_title($api, $title)
	{
		$res = $api->search_product_attributes(
			array(
				'take' => 50,
				'skip' => 0,
				'search' => $title,
			)
		);
		if (empty($res['success']) || empty($res['data']) || !is_array($res['data'])) {
			return null;
		}
		$items = isset($res['data']['items']) && is_array($res['data']['items']) ? $res['data']['items'] : array();
		$want = self::norm_label($title);
		foreach ($items as $item) {
			if (!is_array($item) || empty($item['title'])) {
				continue;
			}
			if (self::norm_label($item['title']) === $want) {
				return $item;
			}
		}
		return null;
	}

	/**
	 * @param array $res
	 * @return array
	 */
	private static function unwrap_api_list($res)
	{
		if (!is_array($res) || empty($res['success']) || !isset($res['data']) || !is_array($res['data'])) {
			return array();
		}
		$data = $res['data'];
		if (isset($data['items']) && is_array($data['items'])) {
			return $data['items'];
		}
		if ($data === array()) {
			return array();
		}
		$keys = array_keys($data);
		if ($keys === range(0, count($data) - 1)) {
			return $data;
		}
		return array();
	}

	/**
	 * @param array $res
	 * @return array
	 */
	private static function unwrap_attribute($res)
	{
		if (!is_array($res)) {
			return array();
		}
		$data = isset($res['data']) && is_array($res['data']) ? $res['data'] : $res;
		if (isset($data['item']) && is_array($data['item'])) {
			$data = $data['item'];
		}
		if (empty($data['option_items']) || !is_array($data['option_items'])) {
			$data['option_items'] = array();
		}
		return $data;
	}

	/**
	 * @param WC_Product|null $parent
	 * @return array<int, array{key:string,title:string,options:array}>
	 */
	public static function collect_variation_dimensions($parent)
	{
		if (!$parent || !is_a($parent, 'WC_Product') || !method_exists($parent, 'get_attributes')) {
			return array();
		}
		$out = array();
		foreach ((array) $parent->get_attributes() as $attribute) {
			if (!is_a($attribute, 'WC_Product_Attribute')) {
				continue;
			}
			if (!$attribute->get_variation()) {
				continue;
			}
			$key = (string) $attribute->get_name();
			$title = function_exists('wc_attribute_label') ? wc_attribute_label($key) : $key;
			$options = array();
			if ($attribute->is_taxonomy()) {
				$terms = $attribute->get_terms();
				if (empty($terms)) {
					$terms = wc_get_product_terms($parent->get_id(), $key, array('fields' => 'all'));
				}
				foreach ((array) $terms as $term) {
					if (!isset($term->slug, $term->name)) {
						continue;
					}
					$options[] = array(
						'slug' => (string) $term->slug,
						'label' => (string) $term->name,
					);
				}
			} else {
				foreach ((array) $attribute->get_options() as $opt) {
					$opt = trim((string) $opt);
					if ($opt === '') {
						continue;
					}
					$options[] = array(
						'slug' => sanitize_title($opt),
						'label' => $opt,
					);
				}
			}
			if (empty($options)) {
				continue;
			}
			$out[] = array(
				'key' => $key,
				'title' => $title !== '' ? $title : $key,
				'options' => $options,
			);
		}
		return $out;
	}

	/**
	 * @param WC_Product $variation
	 * @param array      $dims
	 * @return array<string, array{slug:string,label:string,match:string}>|null
	 */
	private static function variation_combination($variation, array $dims)
	{
		$attrs = $variation->get_attributes();
		if (!is_array($attrs)) {
			$attrs = array();
		}
		$combo = array();
		foreach ($dims as $dim) {
			$key = $dim['key'];
			$raw = '';
			if (isset($attrs[ $key ])) {
				$raw = $attrs[ $key ];
			} elseif (isset($attrs[ 'attribute_' . $key ])) {
				$raw = $attrs[ 'attribute_' . $key ];
			}
			$raw = is_string($raw) ? trim(wp_specialchars_decode($raw)) : '';
			if ($raw === '') {
				return null;
			}
			$hit = null;
			$nraw = self::norm_label($raw);
			foreach ($dim['options'] as $opt) {
				if ($raw === $opt['slug'] || $raw === $opt['label']) {
					$hit = $opt;
					break;
				}
				if ($nraw === self::norm_label($opt['slug']) || $nraw === self::norm_label($opt['label'])) {
					$hit = $opt;
					break;
				}
			}
			if (!$hit) {
				return null;
			}
			$combo[ $key ] = array(
				'slug' => $hit['slug'],
				'label' => $hit['label'],
				'match' => $hit['slug'],
			);
		}
		return $combo;
	}

	/**
	 * @param string $s
	 * @return string
	 */
	private static function norm_label($s)
	{
		$s = trim((string) $s);
		$s = function_exists('mb_strtolower') ? mb_strtolower($s, 'UTF-8') : strtolower($s);
		$s = str_replace(array('ي', 'ك', 'ى'), array('ی', 'ک', 'ی'), $s);
		$s = preg_replace('/\s+/u', ' ', $s);
		return is_string($s) ? $s : '';
	}
}
