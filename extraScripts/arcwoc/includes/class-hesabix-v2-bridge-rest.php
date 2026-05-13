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
		return array(
			'id'            => $order->get_id(),
			'number'        => $order->get_order_number(),
			'status'        => $order->get_status(),
			'currency'      => $order->get_currency(),
			'total'         => (float) $order->get_total(),
			'date_created'  => $order->get_date_created() ? $order->get_date_created()->date('c') : null,
			'customer_id'   => (int) $order->get_customer_id(),
			'billing_name'  => trim($order->get_formatted_billing_full_name()),
			'billing_email' => (string) $order->get_billing_email(),
			'line_count'    => count($order->get_items()),
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
			$items[] = array(
				'id'         => $uid,
				'email'      => (string) $c->get_email(),
				'first_name' => (string) $c->get_first_name(),
				'last_name'  => (string) $c->get_last_name(),
				'username'   => (string) $c->get_username(),
				'date_created' => $c->get_date_created() ? $c->get_date_created()->date('c') : null,
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
}
