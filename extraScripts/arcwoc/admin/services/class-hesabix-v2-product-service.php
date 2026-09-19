<?php
/**
 * Product Service
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

class Hesabix_V2_Product_Service
{
	/**
	 * Get all WooCommerce products
	 *
	 * @since    2.0.0
	 * @param    array    $args
	 * @return   array
	 */
	public static function get_all_products($args = array())
	{
		$default_args = array(
			'status' => self::syncable_statuses(),
			'limit' => -1,
			'return' => 'ids',
		);

		$args = array_merge($default_args, $args);
		
		return wc_get_products($args);
	}

	/**
	 * تعداد تقریبی محصولات قابل‌همگام‌سازی (پست والد، بدون واریانت به‌عنوان پست جدا).
	 *
	 * @since 2.0.7
	 * @return int
	 */
	public static function count_published_parent_products()
	{
		$c = wp_count_posts('product');
		$total = 0;
		foreach (self::syncable_statuses() as $st) {
			if (isset($c->$st)) {
				$total += (int) $c->$st;
			}
		}

		return $total;
	}

	/**
	 * اسلایس شناسهٔ محصولات والد برای همگام‌سازی دسته‌ای (کاهش تایم‌اوت).
	 *
	 * @since 2.0.7
	 * @param int $limit  حداکثر تعداد پست محصول در این مرحله.
	 * @param int $offset جابجایی نسبت به فهرست منتشرشده.
	 * @return array<int>
	 */
	public static function get_published_parent_product_ids_slice($limit, $offset)
	{
		$limit = max(1, (int) $limit);
		$offset = max(0, (int) $offset);

		$ids = wc_get_products(
			array(
				'status' => self::syncable_statuses(),
				'limit' => $limit,
				'offset' => $offset,
				'return' => 'ids',
			)
		);

		return is_array($ids) ? array_map('intval', $ids) : array();
	}

	/**
	 * وضعیت‌های مجاز برای همگام‌سازی محصول به حسابیکس.
	 * پیش‌فرض فقط publish — هم‌راستا با همگام‌سازی دسته‌ای.
	 *
	 * @since 4.7.1
	 * @return string[]
	 */
	public static function syncable_statuses()
	{
		$statuses = array('publish');

		/**
		 * فیلتر وضعیت‌های پست محصول که اجازهٔ همگام‌سازی دارند.
		 * مثال: افزودن private با return array('publish', 'private');
		 *
		 * @param string[] $statuses
		 */
		$filtered = apply_filters('hesabix_v2_syncable_product_statuses', $statuses);
		if (!is_array($filtered)) {
			return $statuses;
		}

		$out = array();
		foreach ($filtered as $st) {
			if (is_string($st) && $st !== '') {
				$out[] = sanitize_key($st);
			}
		}

		return !empty($out) ? array_values(array_unique($out)) : $statuses;
	}

	/**
	 * آیا محصول (و در صورت واریانت، والد آن) وضعیت مجاز برای همگام‌سازی دارد؟
	 *
	 * @since 4.7.1
	 * @param WC_Product      $product
	 * @param WC_Product|null $parent_product
	 * @return bool
	 */
	public static function is_syncable_product($product, $parent_product = null)
	{
		if (!$product || !is_a($product, 'WC_Product')) {
			return false;
		}

		$allowed = self::syncable_statuses();
		$status = (string) $product->get_status();
		if (!in_array($status, $allowed, true)) {
			return false;
		}

		if ($parent_product && is_a($parent_product, 'WC_Product')) {
			$parent_status = (string) $parent_product->get_status();
			if (!in_array($parent_status, $allowed, true)) {
				return false;
			}
		}

		return true;
	}

	/**
	 * Get product variations
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 * @return   array
	 */
	public static function get_variations($product_id)
	{
		$product = wc_get_product($product_id);

		if (!$product || !$product->is_type('variable')) {
			return array();
		}

		return $product->get_children();
	}

	/**
	 * Get sync status for product
	 *
	 * @since    2.0.0
	 * @param    int    $product_id
	 * @param    int    $variation_id
	 * @return   array|null
	 */
	public static function get_sync_status($product_id, $variation_id = null)
	{
		$db = new Hesabix_V2_DB_Service();
		$wc_id = $variation_id ?: $product_id;
		$wc_parent_id = $variation_id ? $product_id : null;

		return $db->get_mapping('product', $wc_id, $wc_parent_id);
	}
}

