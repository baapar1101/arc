<?php
/**
 * REST Bridge برای خواندن سفارشات / محصولات / مشتریان توسط سرور حسابیکس.
 *
 * @package Hesabix_V2
 * @since   3.6.0
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Bridge_Rest
{
	const NS = 'hesabix/v1';

	const OPT_ENABLED = 'hesabix_v2_bridge_enabled';

	const OPT_TOKEN_HASH = 'hesabix_v2_bridge_token_hash';

	const HEADER_TOKEN = 'X-Hesabix-Bridge-Token';

	const MAX_PER_PAGE = 50;

	/**
	 * @return string
	 */
	private static function token_pepper()
	{
		if (defined('AUTH_KEY') && AUTH_KEY !== '') {
			return (string) AUTH_KEY;
		}
		if (defined('SECURE_AUTH_KEY') && SECURE_AUTH_KEY !== '') {
			return (string) SECURE_AUTH_KEY;
		}
		return 'hesabix_v2_bridge';
	}

	/**
	 * @param string $plain
	 * @return string
	 */
	public static function hash_token($plain)
	{
		$plain = trim((string) $plain);
		return hash('sha256', self::token_pepper() . '|' . $plain);
	}

	/**
	 * @param string $plain
	 * @return void
	 */
	public static function save_token_hash($plain)
	{
		update_option(self::OPT_TOKEN_HASH, self::hash_token($plain), false);
	}

	/**
	 * @param string $plain
	 * @return bool
	 */
	public static function verify_token($plain)
	{
		$stored = get_option(self::OPT_TOKEN_HASH, '');
		if (!is_string($stored) || $stored === '') {
			return false;
		}
		$plain = trim((string) $plain);
		if ($plain === '') {
			return false;
		}
		return hash_equals($stored, self::hash_token($plain));
	}

	/**
	 * @return void
	 */
	public static function register_routes()
	{
		register_rest_route(
			self::NS,
			'/health',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_health'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/orders',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_orders'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
				'args'                => self::orders_query_args(),
			)
		);

		register_rest_route(
			self::NS,
			'/products',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_products'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
				'args'                => array_merge(
					self::paging_args(),
					array(
						'search' => array(
							'type'              => 'string',
							'required'          => false,
							'sanitize_callback' => 'sanitize_text_field',
						),
					)
				),
			)
		);

		register_rest_route(
			self::NS,
			'/customers',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_customers'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
				'args'                => array_merge(
					self::paging_args(),
					array(
						'search' => array(
							'type'              => 'string',
							'required'          => false,
							'sanitize_callback' => 'sanitize_text_field',
						),
					)
				),
			)
		);

		register_rest_route(
			self::NS,
			'/reports/summary',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_reports_summary'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
				'args'                => array(
					'after'  => array(
						'type'              => 'string',
						'required'          => false,
						'sanitize_callback' => 'sanitize_text_field',
					),
					'before' => array(
						'type'              => 'string',
						'required'          => false,
						'sanitize_callback' => 'sanitize_text_field',
					),
				),
			)
		);

		$control_logs_args = array_merge(
			self::paging_args(),
			array(
				'action' => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_text_field',
				),
			)
		);

		register_rest_route(
			self::NS,
			'/control/sync-stats',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_control_sync_stats'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/settings-summary',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_control_settings_summary'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/logs',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_control_logs'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
				'args'                => $control_logs_args,
			)
		);

		register_rest_route(
			self::NS,
			'/control/connection',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_control_connection'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/plugin',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_control_plugin'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/sync/product',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_sync_product'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/sync/orders',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_sync_orders'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/sync/products',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_sync_products'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/sync/customers',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_sync_customers'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/queue/snapshot',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_control_queue_snapshot'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/queue/process-once',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_queue_process_once'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/plugin/update-check',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_plugin_update_check'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/settings/patch',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_settings_patch'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/opening-inventory/status',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_control_opening_inventory_status'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/opening-inventory/accounts',
			array(
				'methods'             => 'GET',
				'callback'            => array(__CLASS__, 'route_control_opening_inventory_accounts'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/opening-inventory/preview',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_opening_inventory_preview'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/opening-inventory/prepare',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_opening_inventory_prepare'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/opening-inventory/batch',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_opening_inventory_batch'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/opening-inventory/finalize',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_opening_inventory_finalize'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);

		register_rest_route(
			self::NS,
			'/control/opening-inventory/cancel',
			array(
				'methods'             => 'POST',
				'callback'            => array(__CLASS__, 'route_control_opening_inventory_cancel'),
				'permission_callback' => array(__CLASS__, 'permission_with_token'),
			)
		);
	}

	/**
	 * @return array<string, array<string, mixed>>
	 */
	private static function paging_args()
	{
		return array(
			'page'     => array(
				'type'              => 'integer',
				'default'           => 1,
				'minimum'           => 1,
				'sanitize_callback' => 'absint',
			),
			'per_page' => array(
				'type'              => 'integer',
				'default'           => 20,
				'minimum'           => 1,
				'maximum'           => self::MAX_PER_PAGE,
				'sanitize_callback' => 'absint',
			),
			'status'   => array(
				'type'              => 'string',
				'required'          => false,
				'sanitize_callback' => 'sanitize_text_field',
			),
			'after'    => array(
				'type'              => 'string',
				'required'          => false,
				'sanitize_callback' => 'sanitize_text_field',
			),
			'before'   => array(
				'type'              => 'string',
				'required'          => false,
				'sanitize_callback' => 'sanitize_text_field',
			),
		);
	}

	/**
	 * پارامترهای GET سفارشات (صفحه‌بندی + فیلتر).
	 *
	 * @return array<string, array<string, mixed>>
	 */
	private static function orders_query_args()
	{
		return array_merge(
			self::paging_args(),
			array(
				'customer_id' => array(
					'type'              => 'integer',
					'required'          => false,
					'minimum'           => 0,
					'sanitize_callback' => 'absint',
				),
				'search'      => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_text_field',
				),
				'orderby'     => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_key',
				),
				'order'       => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => array(__CLASS__, 'sanitize_order_dir'),
				),
			)
		);
	}

	/**
	 * @param mixed $v
	 * @return string
	 */
	public static function sanitize_order_dir($v)
	{
		$v = strtoupper(trim((string) $v));
		return 'ASC' === $v ? 'ASC' : 'DESC';
	}

	/**
	 * خلاصهٔ نگاشت حسابیکس از جدول wp_hesabix_v2 (در صورت پیکربندی نشدن business_id خالی برمی‌گردد).
	 *
	 * @param string   $entity_type   product|customer|order|variation|category
	 * @param int      $wc_id
	 * @param int|null $wc_parent_id
	 * @return array<string, mixed>
	 */
	private static function hesabix_mapping_summary($entity_type, $wc_id, $wc_parent_id = null)
	{
		global $wpdb;

		$empty = array(
			'hesabix_id'    => null,
			'sync_status'   => null,
			'last_sync_at'  => null,
			'error_message' => null,
		);

		$business_id = (int) get_option('hesabix_v2_business_id', 0);
		$wc_id       = (int) $wc_id;
		if ($business_id < 1 || $wc_id < 1) {
			return $empty;
		}

		$table = $wpdb->prefix . 'hesabix_v2';
		if (null !== $wc_parent_id && (int) $wc_parent_id > 0) {
			$row = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT hesabix_id, sync_status, last_sync_at, error_message FROM {$table}
					WHERE entity_type = %s AND wc_id = %d AND wc_parent_id = %d AND business_id = %d
					LIMIT 1",
					$entity_type,
					$wc_id,
					(int) $wc_parent_id,
					$business_id
				),
				ARRAY_A
			);
		} else {
			$row = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT hesabix_id, sync_status, last_sync_at, error_message FROM {$table}
					WHERE entity_type = %s AND wc_id = %d AND wc_parent_id IS NULL AND business_id = %d
					LIMIT 1",
					$entity_type,
					$wc_id,
					$business_id
				),
				ARRAY_A
			);
		}

		if (!is_array($row)) {
			return $empty;
		}

		$hid = isset($row['hesabix_id']) ? (int) $row['hesabix_id'] : 0;

		return array(
			'hesabix_id'    => $hid > 0 ? $hid : null,
			'sync_status'   => isset($row['sync_status']) ? (string) $row['sync_status'] : null,
			'last_sync_at'  => isset($row['last_sync_at']) ? (string) $row['last_sync_at'] : null,
			'error_message' => isset($row['error_message']) && (string) $row['error_message'] !== ''
				? (string) $row['error_message']
				: null,
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return true|WP_Error
	 */
	public static function permission_with_token($request)
	{
		if (!class_exists('WooCommerce')) {
			return new WP_Error('wc_missing', __('ووکامرس فعال نیست.', 'hesabix-v2'), array('status' => 503));
		}
		if (!get_option(self::OPT_ENABLED)) {
			return new WP_Error('bridge_disabled', __('پل REST غیرفعال است.', 'hesabix-v2'), array('status' => 403));
		}
		$token = $request->get_header(self::HEADER_TOKEN);
		if (!$token) {
			$token = isset($_SERVER['HTTP_X_HESABIX_BRIDGE_TOKEN']) ? sanitize_text_field(wp_unslash((string) $_SERVER['HTTP_X_HESABIX_BRIDGE_TOKEN'])) : '';
		}
		if (!self::verify_token($token)) {
			return new WP_Error('invalid_token', __('توکن نامعتبر است.', 'hesabix-v2'), array('status' => 401));
		}
		return true;
	}

	/**
	 * خلاصهٔ آماری برای گزارش در حسابیکس (تعداد سفارش به تفکیک وضعیت، محصولات، مشتریان).
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_reports_summary($request)
	{
		global $wpdb;

		$after  = trim((string) $request->get_param('after'));
		$before = trim((string) $request->get_param('before'));

		$counts_by_status = array();
		$orders_total     = 0;

		$use_hpos = class_exists('\Automattic\WooCommerce\Utilities\OrderUtil')
			&& \Automattic\WooCommerce\Utilities\OrderUtil::custom_orders_table_usage_is_enabled();

		if ($use_hpos) {
			$table = $wpdb->prefix . 'wc_orders';
			$where = "type = 'shop_order' AND status != 'trash'";
			if ($after !== '') {
				$where .= $wpdb->prepare(' AND date_created_gmt >= %s', $after);
			}
			if ($before !== '') {
				$where .= $wpdb->prepare(' AND date_created_gmt <= %s', $before);
			}
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- table name from prefix
			$sql  = "SELECT status, COUNT(*) AS c FROM {$table} WHERE {$where} GROUP BY status";
			$rows = $wpdb->get_results($sql, ARRAY_A);
		} else {
			$where = "post_type = 'shop_order' AND post_status LIKE 'wc-%'";
			if ($after !== '') {
				$where .= $wpdb->prepare(' AND post_date_gmt >= %s', $after);
			}
			if ($before !== '') {
				$where .= $wpdb->prepare(' AND post_date_gmt <= %s', $before);
			}
			$sql  = "SELECT post_status AS status, COUNT(*) AS c FROM {$wpdb->posts} WHERE {$where} GROUP BY post_status";
			$rows = $wpdb->get_results($sql, ARRAY_A);
		}

		if (is_array($rows)) {
			foreach ($rows as $row) {
				$st = isset($row['status']) ? (string) $row['status'] : '';
				$c  = isset($row['c']) ? (int) $row['c'] : 0;
				if ($st === '') {
					continue;
				}
				$key = str_replace('wc-', '', $st);
				if (!isset($counts_by_status[ $key ])) {
					$counts_by_status[ $key ] = 0;
				}
				$counts_by_status[ $key ] += $c;
				$orders_total += $c;
			}
		}

		$products_total = (int) $wpdb->get_var(
			"SELECT COUNT(ID) FROM {$wpdb->posts} WHERE post_type = 'product' AND post_status IN ('publish','draft','private')"
		);

		$customers_total = 0;
		if (function_exists('count_users')) {
			$uc = count_users();
			if (isset($uc['avail_roles']['customer'])) {
				$customers_total = (int) $uc['avail_roles']['customer'];
			}
		}

		$since_gmt = gmdate('Y-m-d H:i:s', time() - 7 * DAY_IN_SECONDS);
		$recent    = 0;
		if ($use_hpos) {
			$table  = $wpdb->prefix . 'wc_orders';
			$recent = (int) $wpdb->get_var(
				$wpdb->prepare(
					"SELECT COUNT(*) FROM {$table} WHERE type = %s AND status != %s AND date_created_gmt >= %s",
					'shop_order',
					'trash',
					$since_gmt
				)
			);
		} else {
			$recent = (int) $wpdb->get_var(
				$wpdb->prepare(
					"SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type = %s AND post_status LIKE %s AND post_date_gmt >= %s",
					'shop_order',
					'wc-%',
					$since_gmt
				)
			);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'counts_by_status'     => $counts_by_status,
					'orders_total'         => $orders_total,
					'products_total'       => $products_total,
					'customers_total'      => $customers_total,
					'orders_last_7_days'   => $recent,
					'after'                => $after,
					'before'               => $before,
					'orders_storage'       => $use_hpos ? 'hpos' : 'posts',
				),
			),
			200
		);
	}

	public static function route_health($request)
	{
		unset($request);
		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'bridge_version' => 3,
					'plugin_version' => defined('HESABIX_V2_VERSION') ? HESABIX_V2_VERSION : '',
					'wc_version'     => defined('WC_VERSION') ? WC_VERSION : '',
					'wp_version'     => get_bloginfo('version'),
					'site_url'       => get_site_url(),
					'bridge_enabled' => (bool) get_option(self::OPT_ENABLED),
				),
			),
			200
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_orders($request)
	{
		$page     = max(1, (int) $request->get_param('page'));
		$per_page = min(self::MAX_PER_PAGE, max(1, (int) $request->get_param('per_page')));
		$status   = trim((string) $request->get_param('status'));
		$after    = trim((string) $request->get_param('after'));
		$before   = trim((string) $request->get_param('before'));
		$cust_id  = absint((int) $request->get_param('customer_id'));
		$search   = trim((string) $request->get_param('search'));
		$orderby  = sanitize_key((string) $request->get_param('orderby'));
		$order    = self::sanitize_order_dir($request->get_param('order'));

		$args = array(
			'limit'    => $per_page,
			'page'     => $page,
			'paginate' => true,
			'orderby'  => 'date',
			'order'    => $order,
		);
		if ($orderby !== '' && in_array($orderby, array('date', 'modified', 'id'), true)) {
			$args['orderby'] = $orderby;
		}
		if ($cust_id > 0) {
			$args['customer_id'] = $cust_id;
		}
		if ($search !== '') {
			$args['search'] = $search;
		}
		if ($status !== '') {
			$parts = array_filter(array_map('trim', explode(',', $status)));
			$clean = array();
			foreach ($parts as $p) {
				$p = sanitize_text_field($p);
				if ($p !== '') {
					$clean[] = $p;
				}
			}
			if (!empty($clean)) {
				$args['status'] = count($clean) > 1 ? $clean : array($clean[0]);
			}
		}
		if ($after !== '' && $before !== '') {
			$args['date_created'] = $after . '...' . $before;
		} elseif ($after !== '') {
			$args['date_created'] = $after . '...';
		} elseif ($before !== '') {
			$args['date_created'] = '...' . $before;
		}

		$result = wc_get_orders($args);
		if (!is_object($result) || !isset($result->orders)) {
			return new WP_REST_Response(array('success' => true, 'data' => array('items' => array(), 'total' => 0, 'page' => $page, 'per_page' => $per_page)), 200);
		}

		$items = array();
		foreach ($result->orders as $order) {
			if (!$order instanceof WC_Order) {
				continue;
			}
			$items[] = self::map_order_summary($order);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'items'    => $items,
					'total'    => (int) $result->total,
					'page'     => $page,
					'per_page' => $per_page,
				),
			),
			200
		);
	}

	/**
	 * @param WC_Order $order
	 * @return array<string, mixed>
	 */
	private static function map_order_summary($order)
	{
		$map = self::hesabix_mapping_summary('order', (int) $order->get_id(), null);

		return array(
			'id'            => $order->get_id(),
			'number'        => $order->get_order_number(),
			'type'          => (string) $order->get_type(),
			'status'        => $order->get_status(),
			'currency'      => $order->get_currency(),
			'total'         => (float) $order->get_total(),
			'date_created'  => $order->get_date_created() ? $order->get_date_created()->date('c') : null,
			'customer_id'   => (int) $order->get_customer_id(),
			'billing_name'  => trim($order->get_formatted_billing_full_name()),
			'billing_email' => (string) $order->get_billing_email(),
			'line_count'    => count($order->get_items()),
			'hesabix_id'    => $map['hesabix_id'],
			'sync_status'   => $map['sync_status'],
			'hesabix_last_sync_at' => $map['last_sync_at'],
			'hesabix_error_message' => $map['error_message'],
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_products($request)
	{
		$page     = max(1, (int) $request->get_param('page'));
		$per_page = min(self::MAX_PER_PAGE, max(1, (int) $request->get_param('per_page')));
		$search   = trim((string) $request->get_param('search'));
		$offset   = ($page - 1) * $per_page;

		$args = array(
			'limit'   => $per_page,
			'offset'  => $offset,
			'orderby' => 'date',
			'order'   => 'DESC',
			'status'  => array('publish', 'draft', 'private'),
			'return'  => 'objects',
		);
		if ($search !== '') {
			$args['s'] = $search;
		}

		$products = wc_get_products($args);
		$items    = array();
		foreach ($products as $p) {
			if (!$p instanceof WC_Product) {
				continue;
			}
			$items[] = self::map_product_summary($p);
		}

		$total = (int) (new WP_Query(
			array(
				'post_type'      => 'product',
				'post_status'    => array('publish', 'draft', 'private'),
				'posts_per_page' => 1,
				'fields'         => 'ids',
				's'              => $search,
			)
		))->found_posts;

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'items'    => $items,
					'total'    => $total,
					'page'     => $page,
					'per_page' => $per_page,
				),
			),
			200
		);
	}

	/**
	 * @param WC_Product $p
	 * @return array<string, mixed>
	 */
	private static function map_product_summary($p)
	{
		$type = $p->get_type();
		$map  = self::hesabix_mapping_summary('product', (int) $p->get_id(), null);
		$row = array(
			'id'         => $p->get_id(),
			'name'       => $p->get_name(),
			'sku'        => (string) $p->get_sku(),
			'type'       => $type,
			'status'     => $p->get_status(),
			'price'      => (float) $p->get_regular_price(),
			'sale_price' => (float) $p->get_sale_price(),
			'stock_quantity' => $p->managing_stock() ? $p->get_stock_quantity() : null,
			'permalink'  => $p->get_permalink(),
			'hesabix_id' => $map['hesabix_id'],
			'sync_status' => $map['sync_status'],
			'hesabix_last_sync_at' => $map['last_sync_at'],
			'hesabix_error_message' => $map['error_message'],
		);
		if ($type === 'variable') {
			/** @var WC_Product_Variable $p */
			$row['children_count'] = count($p->get_children());
		}
		return $row;
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_customers($request)
	{
		$page     = max(1, (int) $request->get_param('page'));
		$per_page = min(self::MAX_PER_PAGE, max(1, (int) $request->get_param('per_page')));
		$search   = trim((string) $request->get_param('search'));

		if (!class_exists('WC_Customer_Query')) {
			return new WP_REST_Response(array('success' => true, 'data' => array('items' => array(), 'total' => 0, 'page' => $page, 'per_page' => $per_page)), 200);
		}

		$cq_args = array(
			'limit'   => $per_page,
			'offset'  => ($page - 1) * $per_page,
			'orderby' => 'registered_date',
			'order'   => 'DESC',
		);
		if ($search !== '') {
			$cq_args['search'] = '*' . wc_clean($search) . '*';
		}
		$q     = new WC_Customer_Query($cq_args);
		$ids   = $q->get_results();
		$total = method_exists($q, 'get_total') ? (int) $q->get_total() : count($ids);

		$items = array();
		foreach ($ids as $uid) {
			$uid = (int) $uid;
			if ($uid <= 0) {
				continue;
			}
			$c = new WC_Customer($uid);
			$map = self::hesabix_mapping_summary('customer', $uid, null);
			$items[] = array(
				'id'         => $uid,
				'email'      => (string) $c->get_email(),
				'first_name' => (string) $c->get_first_name(),
				'last_name'  => (string) $c->get_last_name(),
				'username'   => (string) $c->get_username(),
				'date_created' => $c->get_date_created() ? $c->get_date_created()->date('c') : null,
				'hesabix_id' => $map['hesabix_id'],
				'sync_status' => $map['sync_status'],
				'hesabix_last_sync_at' => $map['last_sync_at'],
				'hesabix_error_message' => $map['error_message'],
			);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'items'    => $items,
					'total'    => (int) $total,
					'page'     => $page,
					'per_page' => $per_page,
				),
			),
			200
		);
	}

	/**
	 * خلاصهٔ آمار نگاشت از Hesabix_V2_DB_Service::get_sync_stats.
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response
	 */
	public static function route_control_sync_stats($request)
	{
		$db = new Hesabix_V2_DB_Service();
		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'stats' => $db->get_sync_stats(),
				),
			),
			200
		);
	}

	/**
	 * @param string $api_key
	 * @return string
	 */
	private static function mask_api_key_fragment($api_key)
	{
		$api_key = trim((string) $api_key);
		if ($api_key === '') {
			return '';
		}
		$len = strlen($api_key);
		if ($len <= 8) {
			return '********';
		}
		return substr($api_key, 0, 4) . '…' . substr($api_key, -4);
	}

	/**
	 * تنظیمات افزونه (بدون کلید کامل API) برای نمایش از راه دور در حسابیکس.
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response
	 */
	public static function route_control_settings_summary($request)
	{
		$raw_sync = get_option('hesabix_v2_sync_settings', array());
		$sync     = Hesabix_V2_Invoice_Helper::normalize_sync_settings(is_array($raw_sync) ? $raw_sync : array());
		$bulk     = get_option('hesabix_v2_bulk_sync', array());
		$stock    = get_option('hesabix_v2_stock_pull', array());

		$data = array(
			'hesabix_v2_enabled'            => (bool) get_option('hesabix_v2_enabled'),
			'hesabix_v2_setup_completed'   => (bool) get_option('hesabix_v2_setup_completed'),
			'hesabix_v2_business_id'       => (int) get_option('hesabix_v2_business_id', 0),
			'hesabix_v2_fiscal_year_id'    => (int) get_option('hesabix_v2_fiscal_year_id', 0),
			'hesabix_v2_api_base_url'      => (string) get_option('hesabix_v2_api_base_url', ''),
			'hesabix_v2_api_key_masked'    => self::mask_api_key_fragment((string) get_option('hesabix_v2_api_key', '')),
			'hesabix_v2_debug_mode'        => (bool) get_option('hesabix_v2_debug_mode'),
			'hesabix_v2_bridge_enabled'    => (bool) get_option(self::OPT_ENABLED),
			'hesabix_v2_add_checkout_fields' => (bool) get_option('hesabix_v2_add_checkout_fields'),
			'hesabix_v2_default_warehouse_id' => (string) get_option('hesabix_v2_default_warehouse_id', ''),
			'hesabix_v2_default_bank_id'   => (string) get_option('hesabix_v2_default_bank_id', ''),
			'hesabix_v2_default_cash_register_id' => (string) get_option('hesabix_v2_default_cash_register_id', ''),
			'hesabix_v2_currency_id'       => (int) get_option('hesabix_v2_currency_id', 0),
			'hesabix_v2_invoice_payment_destination' => (string) get_option('hesabix_v2_invoice_payment_destination', 'bank'),
			'hesabix_v2_opening_inventory_completed' => (bool) get_option('hesabix_v2_opening_inventory_completed'),
			'sync_settings'                => $sync,
			'bulk_sync_options'          => is_array($bulk) ? $bulk : array(),
			'stock_pull'                 => is_array($stock) ? $stock : array(),
		);

		return new WP_REST_Response(array('success' => true, 'data' => $data), 200);
	}

	/**
	 * لاگ‌های جدول wp_hesabix_v2_sync_log با صفحه‌بندی.
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_logs($request)
	{
		global $wpdb;

		$page     = max(1, (int) $request->get_param('page'));
		$per_page = min(100, max(1, (int) $request->get_param('per_page')));
		$offset   = ($page - 1) * $per_page;
		$action_f = trim((string) $request->get_param('action'));
		$preview  = (int) apply_filters('hesabix_v2_bridge_control_log_preview_chars', 1500);
		if ($preview < 200) {
			$preview = 200;
		}
		if ($preview > 8000) {
			$preview = 8000;
		}

		$table = $wpdb->prefix . 'hesabix_v2_sync_log';

		if ($action_f !== '') {
			$total = (int) $wpdb->get_var(
				$wpdb->prepare("SELECT COUNT(*) FROM {$table} WHERE action = %s", $action_f)
			);
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- table from prefix
			$rows = $wpdb->get_results(
				$wpdb->prepare(
					"SELECT id, entity_type, entity_id, action, status, error_message, execution_time, created_at,
					SUBSTRING(COALESCE(request_data,''), 1, %d) AS request_data_preview,
					SUBSTRING(COALESCE(response_data,''), 1, %d) AS response_data_preview
					FROM {$table} WHERE action = %s ORDER BY id DESC LIMIT %d OFFSET %d",
					$preview,
					$preview,
					$action_f,
					$per_page,
					$offset
				),
				ARRAY_A
			);
		} else {
			$total = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$table}");
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			$rows = $wpdb->get_results(
				$wpdb->prepare(
					"SELECT id, entity_type, entity_id, action, status, error_message, execution_time, created_at,
					SUBSTRING(COALESCE(request_data,''), 1, %d) AS request_data_preview,
					SUBSTRING(COALESCE(response_data,''), 1, %d) AS response_data_preview
					FROM {$table} ORDER BY id DESC LIMIT %d OFFSET %d",
					$preview,
					$preview,
					$per_page,
					$offset
				),
				ARRAY_A
			);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'items'    => is_array($rows) ? $rows : array(),
					'total'    => $total,
					'page'     => $page,
					'per_page' => $per_page,
				),
			),
			200
		);
	}

	/**
	 * همان منطق sanitize_connection_ajax_payload در ادمین (بدون وابستگی به کلاس ادمین).
	 *
	 * @param array<string,mixed> $result
	 * @return array<string,mixed>
	 */
	private static function sanitize_connection_payload(array $result)
	{
		if (isset($result['user']) && is_array($result['user'])) {
			$user = array();
			foreach (array('id', 'email', 'mobile', 'first_name', 'last_name') as $k) {
				if (!empty($result['user'][ $k ])) {
					$user[ $k ] = $result['user'][ $k ];
				}
			}
			$result['user'] = count($user) ? $user : null;
		}

		if (isset($result['connection']) && is_array($result['connection'])) {
			$conn = $result['connection'];
			if (!empty($conn['business']) && is_array($conn['business'])) {
				$row = array();
				foreach (array(
					'id',
					'name',
					'name_fa',
					'title',
					'business_type',
					'business_field',
					'owner_id',
					'is_owner',
					'role',
				) as $bk) {
					if (isset($conn['business'][ $bk ])) {
						$row[ $bk ] = $conn['business'][ $bk ];
					}
				}
				if (empty($row['name']) && !empty($row['name_fa'])) {
					$row['name'] = $row['name_fa'];
				} elseif (empty($row['name']) && !empty($row['title'])) {
					$row['name'] = $row['title'];
				}
				if (empty($row['name']) && !empty($row['id'])) {
					$row['name'] = sprintf(__('کسب‌وکار #%d', 'hesabix-v2'), (int) $row['id']);
				}
				$conn['business'] = !empty($row['id']) ? $row : null;
			}
			if (!empty($conn['fiscal_year']) && is_array($conn['fiscal_year'])) {
				$f = array();
				foreach (array('id', 'title', 'start_date', 'end_date', 'is_current', 'is_last') as $fk) {
					if (isset($conn['fiscal_year'][ $fk ])) {
						$f[ $fk ] = $conn['fiscal_year'][ $fk ];
					}
				}
				$conn['fiscal_year'] = $f ?: null;
			}
			$result['connection'] = $conn;
		}

		return $result;
	}

	/**
	 * تست اتصال API حسابیکس از دید افزونه (بدون نمایش کلید).
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response
	 */
	public static function route_control_connection($request)
	{
		if (!get_option('hesabix_v2_api_key')) {
			return new WP_REST_Response(
				array(
					'success' => true,
					'data'    => array(
						'ok'      => false,
						'message' => __('کلید API تنظیم نشده است.', 'hesabix-v2'),
						'payload' => null,
					),
				),
				200
			);
		}

		$api    = new Hesabix_V2_Api();
		$result = $api->test_connection();
		$ok     = !empty($result['success']);
		if ($ok) {
			$result = self::sanitize_connection_payload($result);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'ok'      => $ok,
					'message' => isset($result['message']) ? (string) $result['message'] : '',
					'payload' => $ok ? $result : null,
				),
			),
			200
		);
	}

	/**
	 * نسخهٔ محلی و وضعیت به‌روزرسانی (بدون نصب خودکار).
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response
	 */
	public static function route_control_plugin($request)
	{
		$current = defined('HESABIX_V2_VERSION') ? (string) HESABIX_V2_VERSION : '';
		$state   = null;
		if (class_exists('Hesabix_V2_Updater')) {
			$state = Hesabix_V2_Updater::instance()->get_update_dashboard_state(false);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'current_version' => $current,
					'updater'         => is_array($state) ? $state : null,
				),
			),
			200
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return array<string,mixed>
	 */
	private static function read_json_body($request)
	{
		$params = $request->get_json_params();
		return is_array($params) ? $params : array();
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_sync_product($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params         = self::read_json_body($request);
		$product_id     = isset($params['product_id']) ? absint($params['product_id']) : 0;
		$variation_raw  = isset($params['variation_id']) ? $params['variation_id'] : null;
		$variation_id   = ($variation_raw !== null && $variation_raw !== '') ? absint($variation_raw) : null;
		if ($variation_id !== null && $variation_id < 1) {
			$variation_id = null;
		}

		if ($product_id < 1) {
			return new WP_Error('invalid_product', __('شناسهٔ محصول نامعتبر است.', 'hesabix-v2'), array('status' => 400));
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$result       = $sync_service->sync_product($product_id, $variation_id);

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => $result,
			),
			200
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_sync_orders($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params = self::read_json_body($request);
		$raw    = isset($params['order_ids']) && is_array($params['order_ids']) ? $params['order_ids'] : array();

		$bulk_opts = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$o_max     = isset($bulk_opts['wc_orders_ajax_batch']) ? (int) $bulk_opts['wc_orders_ajax_batch'] : 40;
		$o_max     = max(5, min(Hesabix_V2_Sync_Service::BULK_WC_CHUNK_MAX_ITEMS, $o_max));

		$ids = array_slice(array_filter(array_map('absint', $raw)), 0, $o_max);
		if (empty($ids)) {
			return new WP_Error('empty_orders', __('سفارشی انتخاب نشده است.', 'hesabix-v2'), array('status' => 400));
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$bulk         = $sync_service->bulk_sync_orders($ids);

		$results = array();
		foreach ($ids as $oid) {
			if (isset($bulk['per_order'][ $oid ])) {
				$po      = $bulk['per_order'][ $oid ];
				$paused = !empty($po['skipped_pause']);
				$results[] = array(
					'order_id'       => (int) $oid,
					'success'        => $paused ? true : (!empty($po['success'])),
					'skipped_pause'  => $paused,
					'message'        => isset($po['message']) ? (string) $po['message'] : '',
				);
				continue;
			}
			$results[] = array(
				'order_id' => (int) $oid,
				'success'  => false,
				'message'  => sprintf(__('خلاصهٔ نتیجه برای سفارش %d موجود نبود.', 'hesabix-v2'), (int) $oid),
			);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'results' => $results,
					'summary' => array(
						'success' => isset($bulk['success']) ? (int) $bulk['success'] : 0,
						'failed'  => isset($bulk['failed']) ? (int) $bulk['failed'] : 0,
					),
				),
			),
			200
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_sync_products($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params = self::read_json_body($request);
		$raw    = isset($params['product_ids']) && is_array($params['product_ids']) ? $params['product_ids'] : array();

		$b_opts = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$p_max  = isset($b_opts['wc_product_parents_per_ajax']) ? (int) $b_opts['wc_product_parents_per_ajax'] : 35;
		$p_max  = max(5, min(Hesabix_V2_Sync_Service::BULK_WC_CHUNK_MAX_ITEMS, $p_max));

		$ids = array_slice(array_filter(array_map('absint', $raw)), 0, $p_max);
		if (empty($ids)) {
			return new WP_Error('empty_products', __('محصولی انتخاب نشده است.', 'hesabix-v2'), array('status' => 400));
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$bulk         = $sync_service->bulk_sync_products($ids);

		$failed_messages = array();
		if (!empty($bulk['errors']) && is_array($bulk['errors'])) {
			foreach ($bulk['errors'] as $err) {
				if (!is_array($err)) {
					continue;
				}
				$failed_messages[] = $err;
			}
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'summary' => array(
						'success' => isset($bulk['success']) ? (int) $bulk['success'] : 0,
						'failed'  => isset($bulk['failed']) ? (int) $bulk['failed'] : 0,
					),
					'errors_preview' => $failed_messages,
				),
			),
			200
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_sync_customers($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params = self::read_json_body($request);
		$raw    = isset($params['customer_ids']) && is_array($params['customer_ids']) ? $params['customer_ids'] : array();

		$c_opts = Hesabix_V2_Sync_Service::get_bulk_sync_options();
		$c_max  = isset($c_opts['wc_customers_per_ajax']) ? (int) $c_opts['wc_customers_per_ajax'] : 45;
		$c_max  = max(5, min(500, $c_max));

		$ids = array_slice(array_filter(array_map('absint', $raw)), 0, $c_max);
		if (empty($ids)) {
			return new WP_Error('empty_customers', __('مشتری انتخاب نشده است.', 'hesabix-v2'), array('status' => 400));
		}

		$eligible  = array();
		$precheck  = array();
		foreach ($ids as $uid) {
			if (! Hesabix_V2_Customer_Service::user_has_customer_list_role((int) $uid)) {
				$precheck[] = array(
					'customer_id' => (int) $uid,
					'success'     => false,
					'message'     => sprintf(__('شناسه %d جزو نقش‌های مجاز مشتری نیست؛ رد شد.', 'hesabix-v2'), (int) $uid),
				);
				continue;
			}
			$eligible[] = (int) $uid;
		}

		$sync_service = new Hesabix_V2_Sync_Service();
		$r            = empty($eligible) ? array(
			'success'       => 0,
			'failed'        => count($precheck),
			'per_customer'  => array(),
		) : $sync_service->bulk_sync_customers($eligible);

		$results = $precheck;
		foreach ($eligible as $cid) {
			$slot = isset($r['per_customer'][ $cid ]) ? $r['per_customer'][ $cid ] : array(
				'success' => false,
				'message' => sprintf(__('نتیجه‌ای برای مشتری %d برنگشت.', 'hesabix-v2'), (int) $cid),
			);
			$results[] = array(
				'customer_id' => (int) $cid,
				'success'     => !empty($slot['success']),
				'message'     => isset($slot['message']) ? (string) $slot['message'] : '',
			);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array('results' => $results),
			),
			200
		);
	}

	/**
	 * شمارش ردیف‌های صف به تفکیک وضعیت + اندازهٔ دستهٔ کرون.
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response
	 */
	public static function route_control_queue_snapshot($request)
	{
		global $wpdb;

		$table = $wpdb->prefix . 'hesabix_v2_queue';
		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- table from prefix
		$rows = $wpdb->get_results("SELECT status, COUNT(*) AS c FROM {$table} GROUP BY status", ARRAY_A);

		$by_status = array();
		if (is_array($rows)) {
			foreach ($rows as $row) {
				$st = isset($row['status']) ? (string) $row['status'] : '';
				$c  = isset($row['c']) ? (int) $row['c'] : 0;
				if ($st !== '') {
					$by_status[ $st ] = $c;
				}
			}
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'by_status'  => $by_status,
					'batch_size' => Hesabix_V2_Queue_Service::get_batch_size(),
				),
			),
			200
		);
	}

	/**
	 * یک اجرای منطقی همان process_due (محدود به اندازهٔ دسته) + شمارندهٔ تقریبی.
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_queue_process_once($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		global $wpdb;
		$table  = $wpdb->prefix . 'hesabix_v2_queue';
		$before = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$table} WHERE status = 'pending'");

		if (function_exists('wp_raise_memory_limit')) {
			wp_raise_memory_limit('admin');
		}
		@set_time_limit(120);

		Hesabix_V2_Queue_Service::process_due();

		$after = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$table} WHERE status = 'pending'");

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'pending_before'   => $before,
					'pending_after'    => $after,
					'pending_delta'    => max(0, $before - $after),
					'batch_size_limit' => Hesabix_V2_Queue_Service::get_batch_size(),
				),
			),
			200
		);
	}

	/**
	 * تازه‌سازی کش بررسی نسخه (بدون نصب).
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_plugin_update_check($request)
	{
		if (!class_exists('Hesabix_V2_Updater')) {
			return new WP_REST_Response(
				array(
					'success' => true,
					'data'    => array(
						'current_version' => defined('HESABIX_V2_VERSION') ? (string) HESABIX_V2_VERSION : '',
						'updater'         => null,
					),
				),
				200
			);
		}

		$params = self::read_json_body($request);
		$force  = !empty($params['force']);

		$state = Hesabix_V2_Updater::instance()->get_update_dashboard_state($force);

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array(
					'current_version' => defined('HESABIX_V2_VERSION') ? (string) HESABIX_V2_VERSION : '',
					'updater'         => is_array($state) ? $state : null,
					'force_refresh'   => $force,
				),
			),
			200
		);
	}

	/**
	 * به‌روزرسانی محدود گزینه‌ها (فقط کلیدهای مجاز؛ بدون ذخیرهٔ کلید API و business_id).
	 *
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_settings_patch($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params  = self::read_json_body($request);
		$applied = array();

		if (array_key_exists('hesabix_v2_debug_mode', $params)) {
			$applied['hesabix_v2_debug_mode'] = (bool) $params['hesabix_v2_debug_mode'];
			update_option('hesabix_v2_debug_mode', $applied['hesabix_v2_debug_mode'], false);
		}

		if (empty($applied)) {
			return new WP_Error(
				'no_allowed_keys',
				__('هیچ فیلد مجاز برای به‌روزرسانی ارسال نشد. در حال حاضر فقط hesabix_v2_debug_mode پشتیبانی می‌شود.', 'hesabix-v2'),
				array('status' => 400)
			);
		}

		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => array('applied' => $applied),
			),
			200
		);
	}

	/**
	 * @return int
	 */
	private static function opening_inventory_bridge_user_id()
	{
		return Hesabix_V2_Opening_Inventory_Service::BRIDGE_JOB_USER_ID;
	}

	/**
	 * @param string $message
	 * @return WP_REST_Response
	 */
	private static function opening_inventory_rest_fail($message)
	{
		return new WP_REST_Response(
			array(
				'success' => false,
				'message' => (string) $message,
			),
			200
		);
	}

	/**
	 * @param array<string,mixed> $data
	 * @return WP_REST_Response
	 */
	private static function opening_inventory_rest_ok(array $data)
	{
		return new WP_REST_Response(
			array(
				'success' => true,
				'data'    => $data,
			),
			200
		);
	}

	/**
	 * @param array<string,mixed> $params
	 * @return array<string,mixed>
	 */
	private static function opening_inventory_prepare_options_from_params(array $params)
	{
		$cost = isset($params['cost_basis']) ? sanitize_key((string) $params['cost_basis']) : 'regular';
		if (!in_array($cost, array('regular', 'sale', 'zero'), true)) {
			$cost = 'regular';
		}
		return array(
			'include_tax'            => !empty($params['include_tax']),
			'cost_basis'             => $cost,
			'auto_balance_to_equity' => !empty($params['auto_balance_to_equity']),
			'do_post'                => !empty($params['do_post']),
			'inventory_account_id'   => isset($params['inventory_account_id']) ? absint($params['inventory_account_id']) : 0,
			'equity_account_id'      => isset($params['equity_account_id']) ? absint($params['equity_account_id']) : 0,
			'batch_size'             => isset($params['batch_size']) ? absint($params['batch_size']) : 12,
			'warehouse_id'           => isset($params['warehouse_id']) ? absint($params['warehouse_id']) : 0,
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_opening_inventory_status($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$uid     = self::opening_inventory_bridge_user_id();
		$pending = Hesabix_V2_Opening_Inventory_Service::get_pending_job_summary_for_user($uid);
		$ui      = Hesabix_V2_Opening_Inventory_Service::get_connection_prereq_for_ui();

		return self::opening_inventory_rest_ok(
			array(
				'opening_inventory_completed' => (bool) get_option('hesabix_v2_opening_inventory_completed'),
				'pending_job'                   => $pending,
				'prereq'                        => $ui['prereq'],
				'checklist'                     => $ui['checklist'],
				'post_confirm_phrase'           => Hesabix_V2_Opening_Inventory_Service::post_confirm_phrase(),
			)
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_opening_inventory_accounts($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$api = new Hesabix_V2_Api();
		Hesabix_V2_Opening_Inventory_Service::sync_and_get_stored_fiscal_year_id($api);

		$res   = $api->get_accounts_flat();
		$items = array();
		$data  = Hesabix_V2_Opening_Inventory_Service::get_api_data_array($res);
		$ids_with_children = array();
		if (is_array($data) && isset($data['items']) && is_array($data['items'])) {
			foreach ($data['items'] as $row) {
				if (!is_array($row)) {
					continue;
				}
				$pp = isset($row['parent_id']) ? (int) $row['parent_id'] : 0;
				if ($pp > 0) {
					$ids_with_children[ $pp ] = true;
				}
			}
			foreach ($data['items'] as $row) {
				if (!is_array($row) || empty($row['id'])) {
					continue;
				}
				$id = (int) $row['id'];
				if (!empty($ids_with_children[ $id ])) {
					continue;
				}
				$code     = isset($row['code']) ? (string) $row['code'] : '';
				$name     = isset($row['name']) ? (string) $row['name'] : '';
				$acc_type = isset($row['account_type']) ? (string) $row['account_type'] : '';
				$items[]  = array(
					'id'             => $id,
					'code'           => $code,
					'name'           => $name,
					'account_type'   => $acc_type,
					'label'          => trim($code . ' — ' . $name),
				);
			}
		}

		Hesabix_V2_Opening_Inventory_Service::invalidate_connection_prereq_ui_cache();
		$ui_snap = Hesabix_V2_Opening_Inventory_Service::get_connection_prereq_for_ui();

		return self::opening_inventory_rest_ok(
			array(
				'accounts'  => $items,
				'prereq'    => $ui_snap['prereq'],
				'checklist' => $ui_snap['checklist'],
				'message'   => empty($items) ? __('حسابی برنگشت؛ دسترسی chart_of_accounts.view و اتصال را بررسی کنید.', 'hesabix-v2') : '',
			)
		);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_opening_inventory_preview($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params = self::read_json_body($request);
		$cost   = isset($params['cost_basis']) ? sanitize_key((string) $params['cost_basis']) : 'regular';
		if (!in_array($cost, array('regular', 'sale', 'zero'), true)) {
			$cost = 'regular';
		}
		$post_like = array(
			'include_tax'    => !empty($params['include_tax']),
			'cost_basis'     => $cost,
			'batch_size'     => isset($params['batch_size']) ? absint($params['batch_size']) : 12,
			'warehouse_id'   => isset($params['warehouse_id']) ? absint($params['warehouse_id']) : 0,
		);

		$res = Hesabix_V2_Opening_Inventory_Service::build_preview_payload($post_like);
		if (empty($res['success'])) {
			return self::opening_inventory_rest_fail($res['message'] ?? __('پیش‌نمایش ناموفق', 'hesabix-v2'));
		}
		unset($res['success']);
		return self::opening_inventory_rest_ok($res);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_opening_inventory_prepare($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params   = self::read_json_body($request);
		$options  = self::opening_inventory_prepare_options_from_params($params);
		$uid      = self::opening_inventory_bridge_user_id();
		$response = Hesabix_V2_Opening_Inventory_Service::job_prepare($uid, $options);
		if (empty($response['success'])) {
			return self::opening_inventory_rest_fail($response['message'] ?? __('آماده‌سازی ناموفق', 'hesabix-v2'));
		}
		unset($response['success']);
		return self::opening_inventory_rest_ok($response);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_opening_inventory_batch($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params = self::read_json_body($request);
		$job_id = isset($params['job_id']) ? sanitize_key((string) $params['job_id']) : '';
		$uid    = self::opening_inventory_bridge_user_id();
		$res    = Hesabix_V2_Opening_Inventory_Service::job_run_batch($job_id, $uid);
		if (empty($res['success'])) {
			return self::opening_inventory_rest_fail($res['message'] ?? __('اجرای دسته ناموفق', 'hesabix-v2'));
		}
		return self::opening_inventory_rest_ok($res);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_opening_inventory_finalize($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params = self::read_json_body($request);
		$job_id = isset($params['job_id']) ? sanitize_key((string) $params['job_id']) : '';
		$uid    = self::opening_inventory_bridge_user_id();
		$job    = Hesabix_V2_Opening_Inventory_Service::get_job($job_id, $uid);
		if (!$job) {
			return self::opening_inventory_rest_fail(__('نشست کار نامعتبر است.', 'hesabix-v2'));
		}
		$opts = isset($job['options']) && is_array($job['options']) ? $job['options'] : array();
		if (!empty($opts['do_post'])) {
			$typed = isset($params['confirm_post_phrase']) ? trim((string) $params['confirm_post_phrase']) : '';
			if ($typed !== Hesabix_V2_Opening_Inventory_Service::post_confirm_phrase()) {
				return self::opening_inventory_rest_fail(
					__(
						'برای نهایی‌سازی سند، فیلد JSON confirm_post_phrase باید دقیقاً برابر مقدار post_confirm_phrase از پاسخ status باشد.',
						'hesabix-v2'
					)
				);
			}
		}

		$res = Hesabix_V2_Opening_Inventory_Service::job_finalize($job_id, $uid);
		if (empty($res['success'])) {
			return self::opening_inventory_rest_fail($res['message'] ?? __('نهایی‌سازی ناموفق', 'hesabix-v2'));
		}
		return self::opening_inventory_rest_ok($res);
	}

	/**
	 * @param WP_REST_Request $request
	 * @return WP_REST_Response|WP_Error
	 */
	public static function route_control_opening_inventory_cancel($request)
	{
		if (!get_option('hesabix_v2_enabled')) {
			return new WP_Error('plugin_disabled', __('افزونه حسابیکس غیرفعال است.', 'hesabix-v2'), array('status' => 400));
		}

		$params = self::read_json_body($request);
		$job_id = isset($params['job_id']) ? sanitize_key((string) $params['job_id']) : '';
		$uid    = self::opening_inventory_bridge_user_id();
		$res    = Hesabix_V2_Opening_Inventory_Service::mark_job_cancel_requested($job_id, $uid);
		if (empty($res['success'])) {
			return self::opening_inventory_rest_fail($res['message'] ?? __('درخواست توقف ناموفق', 'hesabix-v2'));
		}
		unset($res['success']);
		return self::opening_inventory_rest_ok($res);
	}
}
