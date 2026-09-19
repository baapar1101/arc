<?php
/**
 * ارسال عدد موجودی ووکامرس → حسابیکس از طریق حواله تعدیل انبار.
 *
 * فقط وقتی منبع حقیقت «ووکامرس» و گزینه push فعال باشد.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Stock_Push_Service
{
	const APPLYING_FLAG = 'hesabix_v2_stock_pull_applying';

	const META_LAST_PUSHED_QTY = '_hesabix_v2_last_pushed_stock_qty';

	const ORIGIN_KEY = 'arcwoc_origin';

	const ORIGIN_VALUE = 'wc_stock_push';

	/**
	 * ثبت هوک‌های تغییر موجودی ووکامرس.
	 */
	public static function register_hooks()
	{
		add_action('woocommerce_product_set_stock', array(__CLASS__, 'on_product_set_stock'), 40, 1);
		add_action('woocommerce_variation_set_stock', array(__CLASS__, 'on_product_set_stock'), 40, 1);
	}

	/**
	 * جلوگیری از حلقه وقتی کشش موجودی از حسابیکس در حال نوشتن روی WC است.
	 *
	 * @return bool
	 */
	public static function is_stock_pull_applying()
	{
		return !empty($GLOBALS[ self::APPLYING_FLAG ]);
	}

	/**
	 * @param bool $on
	 */
	public static function set_stock_pull_applying($on)
	{
		if ($on) {
			$GLOBALS[ self::APPLYING_FLAG ] = true;
		} else {
			unset($GLOBALS[ self::APPLYING_FLAG ]);
		}
	}

	/**
	 * @param WC_Product $product
	 */
	public static function on_product_set_stock($product)
	{
		if (!$product || !is_a($product, 'WC_Product')) {
			return;
		}
		if (self::is_stock_pull_applying()) {
			return;
		}
		if (!get_option('hesabix_v2_enabled')) {
			return;
		}
		if (!Hesabix_V2_Inventory_Policy::should_push_wc_qty_to_hesabix()) {
			return;
		}
		if ($product->is_type('variable') || $product->is_virtual()) {
			return;
		}
		if (!$product->managing_stock()) {
			return;
		}

		$wc_id = (int) $product->get_id();
		if ($wc_id < 1) {
			return;
		}

		// جلوگیری از دوباره‌کاری در همان درخواست.
		static $done = array();
		if (isset($done[ $wc_id ])) {
			return;
		}
		$done[ $wc_id ] = true;

		try {
			self::push_product_quantity($product);
		} catch (Exception $e) {
			Hesabix_V2_Log_Service::error(
				'WC→Hesabix stock push failed',
				array(
					'entity_type' => 'stock_push',
					'entity_id' => $wc_id,
					'error' => $e->getMessage(),
				)
			);
		}
	}

	/**
	 * هم‌ترازی عدد موجودی یک محصول با حسابیکس (تعدیل انبار).
	 *
	 * @param WC_Product $product
	 * @return array{success:bool, message:string, diff?:float, hesabix_id?:int}
	 */
	public static function push_product_quantity($product)
	{
		$wc_id = (int) $product->get_id();
		$wc_qty = (float) $product->get_stock_quantity();
		if ($wc_qty < 0) {
			$wc_qty = 0.0;
		}

		$db = new Hesabix_V2_DB_Service();
		$parent_id = $product->is_type('variation') ? (int) $product->get_parent_id() : 0;
		$mapping = $parent_id > 0
			? $db->get_mapping('product', $wc_id, $parent_id)
			: $db->get_mapping('product', $wc_id, null);
		if (!$mapping || empty($mapping['hesabix_id'])) {
			return array(
				'success' => false,
				'message' => __('محصول به حسابیکس متصل نیست.', 'hesabix-v2'),
			);
		}

		$hesabix_id = (int) $mapping['hesabix_id'];
		$warehouse_id = absint(get_option('hesabix_v2_default_warehouse_id', 0));
		if ($warehouse_id < 1) {
			return array(
				'success' => false,
				'message' => __('انبار پیش‌فرض برای ارسال موجودی مشخص نیست.', 'hesabix-v2'),
			);
		}

		$last_pushed = $product->get_meta(self::META_LAST_PUSHED_QTY, true);
		if ($last_pushed !== '' && $last_pushed !== null && abs((float) $last_pushed - $wc_qty) < 0.00001) {
			return array(
				'success' => true,
				'message' => __('موجودی قبلاً هم‌تراز است.', 'hesabix-v2'),
				'diff' => 0.0,
				'hesabix_id' => $hesabix_id,
			);
		}

		$api = new Hesabix_V2_Api();
		$hx_qty = self::fetch_hesabix_quantity($api, $hesabix_id, $warehouse_id);
		if (is_wp_error($hx_qty)) {
			return array(
				'success' => false,
				'message' => $hx_qty->get_error_message(),
				'hesabix_id' => $hesabix_id,
			);
		}

		$diff = $wc_qty - (float) $hx_qty;
		if (abs($diff) < 0.00001) {
			$product->update_meta_data(self::META_LAST_PUSHED_QTY, $wc_qty);
			$product->save_meta_data();
			return array(
				'success' => true,
				'message' => __('موجودی حسابیکس با ووکامرس برابر است.', 'hesabix-v2'),
				'diff' => 0.0,
				'hesabix_id' => $hesabix_id,
			);
		}

		$movement = $diff > 0 ? 'in' : 'out';
		$qty = abs($diff);

		$payload = array(
			'doc_type' => 'adjustment',
			'document_date' => function_exists('current_time') ? current_time('Y-m-d') : gmdate('Y-m-d'),
			'warehouse_id_to' => $warehouse_id,
			'warehouse_id_from' => $warehouse_id,
			'description' => sprintf(
				/* translators: 1: WC product id, 2: qty */
				__('تعدیل موجودی از ووکامرس (محصول #%1$d → %2$s)', 'hesabix-v2'),
				$wc_id,
				wc_format_decimal($wc_qty, 4)
			),
			'extra_info' => array(
				self::ORIGIN_KEY => self::ORIGIN_VALUE,
				'wc_product_id' => $wc_id,
				'wc_target_qty' => $wc_qty,
				'hesabix_prev_qty' => (float) $hx_qty,
			),
			'lines' => array(
				array(
					'product_id' => $hesabix_id,
					'quantity' => $qty,
					'movement' => $movement,
					'warehouse_id' => $warehouse_id,
				),
			),
		);

		$create = $api->create_warehouse_document($payload);
		if (empty($create['success'])) {
			$msg = isset($create['message']) ? (string) $create['message'] : __('ایجاد حواله تعدیل ناموفق بود.', 'hesabix-v2');
			Hesabix_V2_Log_Service::error(
				'WC→Hesabix stock push: create warehouse doc failed',
				array(
					'entity_type' => 'stock_push',
					'entity_id' => $wc_id,
					'hesabix_id' => $hesabix_id,
					'request' => array('decoded' => $payload),
					'response' => array('decoded' => $create),
				)
			);
			return array('success' => false, 'message' => $msg, 'hesabix_id' => $hesabix_id, 'diff' => $diff);
		}

		$doc = isset($create['data']) && is_array($create['data']) ? $create['data'] : array();
		$wh_id = isset($doc['id']) ? (int) $doc['id'] : 0;
		if ($wh_id < 1) {
			return array(
				'success' => false,
				'message' => __('شناسه حواله تعدیل دریافت نشد.', 'hesabix-v2'),
				'hesabix_id' => $hesabix_id,
				'diff' => $diff,
			);
		}

		$post = $api->post_warehouse_document($wh_id);
		if (empty($post['success'])) {
			$msg = isset($post['message']) ? (string) $post['message'] : __('قطعی‌سازی حواله تعدیل ناموفق بود.', 'hesabix-v2');
			Hesabix_V2_Log_Service::error(
				'WC→Hesabix stock push: post warehouse doc failed',
				array(
					'entity_type' => 'stock_push',
					'entity_id' => $wc_id,
					'hesabix_id' => $hesabix_id,
					'warehouse_doc_id' => $wh_id,
					'response' => array('decoded' => $post),
				)
			);
			return array('success' => false, 'message' => $msg, 'hesabix_id' => $hesabix_id, 'diff' => $diff);
		}

		$product->update_meta_data(self::META_LAST_PUSHED_QTY, $wc_qty);
		$product->save_meta_data();

		Hesabix_V2_Log_Service::info(
			'WC→Hesabix stock push completed',
			array(
				'entity_type' => 'stock_push',
				'entity_id' => $wc_id,
				'hesabix_id' => $hesabix_id,
				'diff' => $diff,
				'movement' => $movement,
				'warehouse_doc_id' => $wh_id,
				'wc_qty' => $wc_qty,
				'hesabix_prev_qty' => (float) $hx_qty,
			)
		);

		return array(
			'success' => true,
			/* translators: 1: diff, 2: warehouse doc id */
			'message' => sprintf(__('موجودی حسابیکس تعدیل شد (اختلاف %1$s، حواله #%2$d).', 'hesabix-v2'), wc_format_decimal($diff, 4), $wh_id),
			'diff' => $diff,
			'hesabix_id' => $hesabix_id,
			'warehouse_doc_id' => $wh_id,
		);
	}

	/**
	 * @param Hesabix_V2_Api $api
	 * @param int            $hesabix_product_id
	 * @param int            $warehouse_id
	 * @return float|WP_Error
	 */
	private static function fetch_hesabix_quantity($api, $hesabix_product_id, $warehouse_id)
	{
		$res = $api->inventory_stock_report(
			array(
				'product_ids' => array((int) $hesabix_product_id),
				'warehouse_ids' => array((int) $warehouse_id),
				'track_inventory' => true,
				'include_zero' => true,
				'skip' => 0,
				'take' => 50,
			),
			60
		);

		if (empty($res['success'])) {
			$msg = isset($res['message']) ? (string) $res['message'] : __('خطا در خواندن موجودی حسابیکس', 'hesabix-v2');
			return new WP_Error('hesabix_stock_api', $msg);
		}

		$data = isset($res['data']) && is_array($res['data']) ? $res['data'] : array();
		$items = isset($data['items']) && is_array($data['items']) ? $data['items'] : array();
		$total = 0.0;
		$found = false;
		foreach ($items as $it) {
			if (!is_array($it)) {
				continue;
			}
			if ((int) ($it['product_id'] ?? 0) !== (int) $hesabix_product_id) {
				continue;
			}
			$found = true;
			$total += isset($it['quantity']) ? (float) $it['quantity'] : 0.0;
		}

		return $found ? $total : 0.0;
	}
}
