<?php
/**
 * فهرست محصولات ووکامرس برای پنل حسابیکس.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin
 */

if (!defined('WPINC')) {
	die;
}

if (!class_exists('WP_List_Table')) {
	require_once ABSPATH . 'wp-admin/includes/class-wp-list-table.php';
}

/**
 * @extends WP_List_Table
 */
class Hesabix_V2_Products_List_Table extends WP_List_Table
{
	/**
	 * @param array<string,mixed>|null $row
	 * @return string
	 */
	private static function single_mapping_badge_markup($row)
	{
		if (!$row || empty($row['hesabix_id'])) {
			return '<span class="hesabix-v2-badge hesabix-v2-badge-muted">' . esc_html__('همگام نشده', 'hesabix-v2') . '</span>';
		}
		$st = isset($row['sync_status']) ? (string) $row['sync_status'] : 'synced';
		$hid = (int) $row['hesabix_id'];
		$label = __('شناسه کالا:', 'hesabix-v2') . ' ' . $hid;
		if ($st === 'error') {
			$err = isset($row['error_message']) ? (string) $row['error_message'] : '';
			$short = $err !== '' ? mb_substr($err, 0, 120) : '';
			return '<span class="hesabix-v2-badge hesabix-v2-badge-error">' . esc_html__('خطا', 'hesabix-v2') . '</span><br />'
				. '<small>' . esc_html($label) . '</small>'
				. ($short !== '' ? '<br /><span class="description">' . esc_html($short) . '</span>' : '');
		}
		if ($st === 'pending') {
			return '<span class="hesabix-v2-badge hesabix-v2-badge-pending">' . esc_html__('در انتظار', 'hesabix-v2') . '</span><br /><small>' . esc_html($label) . '</small>';
		}
		$ls = isset($row['last_sync_at']) ? (string) $row['last_sync_at'] : '';
		$extra = '';
		if ($ls !== '') {
			$t = strtotime($ls);
			if ($t > 0) {
				$extra = '<br /><span class="description">' . esc_html(
					wp_date(get_option('date_format') . ' ' . get_option('time_format'), $t)
				) . '</span>';
			}
		}
		return '<span class="hesabix-v2-badge hesabix-v2-badge-ok">' . esc_html__('همگام شده', 'hesabix-v2') . '</span><br /><small>' . esc_html($label) . '</small>' . $extra;
	}

	/**
	 * @param WC_Product $item
	 * @return string
	 */
	private static function hesabix_badge_for_product($item)
	{
		if (!$item instanceof WC_Product) {
			return '—';
		}

		if ($item->is_type('variable')) {
			$children = $item->get_children();
			if (empty($children)) {
				return '<span class="hesabix-v2-badge hesabix-v2-badge-error">' . esc_html__('بدون واریانت', 'hesabix-v2') . '</span>';
			}

			$synced = 0;
			$errors = 0;
			$pending = 0;
			$none = 0;
			$first_err = '';

			foreach ($children as $vid) {
				$row = Hesabix_V2_Product_Service::get_sync_status((int) $item->get_id(), (int) $vid);
				if (!$row || empty($row['hesabix_id'])) {
					$none++;
					continue;
				}
				$st = isset($row['sync_status']) ? (string) $row['sync_status'] : 'synced';
				if ($st === 'error') {
					$errors++;
					if ($first_err === '' && !empty($row['error_message'])) {
						$first_err = (string) $row['error_message'];
					}
				} elseif ($st === 'pending') {
					$pending++;
				} else {
					$synced++;
				}
			}

			$n = count($children);
			/* translators: 1: synced count, 2: total variations */
			$summary = sprintf(__('واریانت: %1$d از %2$d همگام', 'hesabix-v2'), $synced, $n);

			if ($errors > 0) {
				$short = $first_err !== '' ? mb_substr($first_err, 0, 100) : '';
				return '<span class="hesabix-v2-badge hesabix-v2-badge-error">' . esc_html__('خطا', 'hesabix-v2') . '</span><br />'
					. '<small>' . esc_html($summary) . '</small>'
					. ($short !== '' ? '<br /><span class="description">' . esc_html($short) . '</span>' : '');
			}
			if ($pending > 0) {
				return '<span class="hesabix-v2-badge hesabix-v2-badge-pending">' . esc_html__('در انتظار', 'hesabix-v2') . '</span><br /><small>' . esc_html($summary) . '</small>';
			}
			if ($synced >= $n) {
				return '<span class="hesabix-v2-badge hesabix-v2-badge-ok">' . esc_html__('همگام شده', 'hesabix-v2') . '</span><br /><small>' . esc_html($summary) . '</small>';
			}
			return '<span class="hesabix-v2-badge hesabix-v2-badge-muted">' . esc_html__('همگام نشده', 'hesabix-v2') . '</span><br /><small>' . esc_html($summary) . '</small>';
		}

		$row = Hesabix_V2_Product_Service::get_sync_status((int) $item->get_id());
		return self::single_mapping_badge_markup(is_array($row) ? $row : null);
	}

	/**
	 * @return void
	 */
	public function __construct()
	{
		parent::__construct(
			array(
				'singular' => 'product',
				'plural' => 'products',
				'ajax' => false,
			)
		);
	}

	/**
	 * @return array<string,string>
	 */
	protected function get_bulk_actions()
	{
		return array();
	}

	/**
	 * @return void
	 */
	public function no_items()
	{
		esc_html_e('محصولی با این فیلتر یافت نشد.', 'hesabix-v2');
	}

	/**
	 * @return array<string,string>
	 */
	public function get_columns()
	{
		return array(
			'cb' => '<input type="checkbox" />',
			'product' => __('محصول', 'hesabix-v2'),
			'sku_col' => __('SKU', 'hesabix-v2'),
			'type_col' => __('نوع', 'hesabix-v2'),
			'hesabix' => __('حسابیکس', 'hesabix-v2'),
			'actions' => __('عملیات', 'hesabix-v2'),
		);
	}

	/**
	 * @return array<string,array<int,mixed>>
	 */
	protected function get_sortable_columns()
	{
		return array(
			'product' => array('title', false),
			'type_col' => array('type', false),
		);
	}

	/**
	 * @param WC_Product $item
	 * @return string
	 */
	protected function column_cb($item)
	{
		return sprintf(
			'<input type="checkbox" name="product_ids[]" value="%d" />',
			(int) $item->get_id()
		);
	}

	/**
	 * @param WC_Product $item
	 * @return string
	 */
	protected function column_product($item)
	{
		$pid = (int) $item->get_id();
		$url = get_edit_post_link($pid, 'raw');
		$name = $item->get_name();
		return sprintf(
			'<span class="description">#%d</span><br /><a href="%s"><strong>%s</strong></a>',
			$pid,
			esc_url($url ? $url : '#'),
			esc_html($name !== '' ? $name : __('(بدون عنوان)', 'hesabix-v2'))
		);
	}

	/**
	 * @param WC_Product $item
	 * @return string
	 */
	protected function column_sku_col($item)
	{
		$sku = $item->get_sku();
		return $sku !== '' ? esc_html($sku) : '—';
	}

	/**
	 * @param WC_Product $item
	 * @return string
	 */
	protected function column_type_col($item)
	{
		$labels = wc_get_product_types();
		$t = $item->get_type();
		$lab = isset($labels[ $t ]) ? $labels[ $t ] : $t;
		return esc_html((string) $lab);
	}

	/**
	 * @param WC_Product $item
	 * @return string
	 */
	protected function column_hesabix($item)
	{
		return self::hesabix_badge_for_product($item);
	}

	/**
	 * @param WC_Product $item
	 * @return string
	 */
	protected function column_actions($item)
	{
		$label = __('همگام‌سازی با حسابیکس', 'hesabix-v2');
		return sprintf(
			'<button type="button" class="button button-small hesabix-v2-product-sync" data-product-id="%d" %s>%s</button>',
			(int) $item->get_id(),
			disabled(!get_option('hesabix_v2_enabled'), false, false),
			esc_html($label)
		);
	}

	/**
	 * @param WC_Product     $item
	 * @param string         $column_name
	 * @return string
	 */
	protected function column_default($item, $column_name)
	{
		return '';
	}

	/**
	 * @param string $which
	 * @return void
	 */
	protected function extra_tablenav($which)
	{
		if ($which !== 'top') {
			return;
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended
		$current = isset($_GET['hx_prod_filter']) ? sanitize_key(wp_unslash((string) $_GET['hx_prod_filter'])) : 'all';
		if ($current === '') {
			$current = 'all';
		}

		$opts = array(
			'all' => __('همهٔ محصولات (والد)', 'hesabix-v2'),
			'synced' => __('دارای همگام‌سازی موفق', 'hesabix-v2'),
			'not_synced' => __('بدون ردیف نگاشت', 'hesabix-v2'),
			'error' => __('خطای همگام‌سازی', 'hesabix-v2'),
			'pending' => __('در انتظار (نگاشت)', 'hesabix-v2'),
		);

		echo '<div class="alignleft actions hesabix-v2-product-filters">';
		echo '<label for="hx_prod_filter" class="screen-reader-text">' . esc_html__('فیلتر حسابیکس', 'hesabix-v2') . '</label>';
		echo '<select name="hx_prod_filter" id="hx_prod_filter">';
		foreach ($opts as $val => $lab) {
			printf(
				'<option value="%s"%s>%s</option>',
				esc_attr($val),
				selected($current, $val, false),
				esc_html((string) $lab)
			);
		}
		echo '</select>';
		submit_button(__('فیلتر', 'hesabix-v2'), 'secondary', 'filter_action', false);
		echo '</div>';
	}

	/**
	 * @global wpdb $wpdb
	 * @return void
	 */
	public function prepare_items()
	{
		global $wpdb;

		$this->items = array();
		$columns = $this->get_columns();
		$this->_column_headers = array($columns, array(), $this->get_sortable_columns());

		$per_page = 20;
		$current_page = max(1, (int) $this->get_pagenum());

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended
		$filter = isset($_GET['hx_prod_filter']) ? sanitize_key(wp_unslash((string) $_GET['hx_prod_filter'])) : 'all';
		if ($filter === '') {
			$filter = 'all';
		}
		$allowed_filters = array('all', 'synced', 'not_synced', 'error', 'pending');
		if (!in_array($filter, $allowed_filters, true)) {
			$filter = 'all';
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended
		$search_raw = isset($_REQUEST['s']) ? sanitize_text_field(wp_unslash((string) $_REQUEST['s'])) : '';
		if (strlen($search_raw) > 200) {
			$search_raw = mb_substr($search_raw, 0, 200);
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended
		$orderby_raw = isset($_GET['orderby']) ? sanitize_key(wp_unslash((string) $_GET['orderby'])) : '';
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended
		$order_raw = isset($_GET['order']) ? strtolower(wp_unslash((string) $_GET['order'])) : 'asc';
		if (!in_array($order_raw, array('asc', 'desc'), true)) {
			$order_raw = 'asc';
		}

		$business_id = (int) get_option('hesabix_v2_business_id');
		$map_table = $wpdb->prefix . 'hesabix_v2';
		$posts_table = $wpdb->posts;

		$dir = ('DESC' === strtoupper($order_raw)) ? 'DESC' : 'ASC';
		$title_order = 'p.post_title ' . $dir . ', p.ID ' . $dir;
		$date_order = 'p.post_date ' . $dir . ', p.ID ' . $dir;

		$search_clause = '';
		$search_args = array();
		if ($search_raw !== '') {
			$search_clause = ' AND p.post_title LIKE %s ';
			$search_args[] = '%' . $wpdb->esc_like($search_raw) . '%';
		}

		$order_fragment = $title_order;
		if ($orderby_raw === 'date') {
			$order_fragment = $date_order;
		} elseif ($orderby_raw === 'type') {
			$order_fragment = ' p.menu_order ' . $dir . ', p.post_title ASC, p.ID ASC ';
		}

		if ($filter === 'all') {
			$wc_orderby = 'title';
			if ($orderby_raw === 'date') {
				$wc_orderby = 'date';
			} elseif ($orderby_raw === 'type') {
				$wc_orderby = 'menu_order';
			}
			$args = array(
				'status' => 'publish',
				'limit' => $per_page,
				'page' => $current_page,
				'paginate' => true,
				'parent' => 0,
				'orderby' => $wc_orderby,
				'order' => $order_raw === 'desc' ? 'DESC' : 'ASC',
			);
			if ($search_raw !== '') {
				$args['s'] = $search_raw;
			}

			$query = wc_get_products($args);
			if (is_object($query) && isset($query->products)) {
				$this->items = array_values(
					array_filter(
						$query->products,
						static function ($p) {
							return $p instanceof WC_Product;
						}
					)
				);
				$total_items = (int) $query->total;
			} else {
				$this->items = array();
				$total_items = 0;
			}

			$this->set_pagination_args(
				array(
					'total_items' => $total_items,
					'per_page' => $per_page,
					'total_pages' => max(1, (int) ceil(max(1, $total_items) / $per_page)),
				)
			);
			return;
		}

		if ($filter === 'not_synced') {
			$prep_count = array_merge(array($business_id), $search_args);
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			$count_sql = "SELECT COUNT(*) FROM {$posts_table} p
				WHERE p.post_type = 'product' AND p.post_status = 'publish' AND p.post_parent = 0
				AND NOT EXISTS (
					SELECT 1 FROM {$map_table} m
					WHERE m.entity_type = 'product' AND m.business_id = %d
					AND (
						(m.wc_parent_id IS NULL AND m.wc_id = p.ID)
						OR (m.wc_parent_id = p.ID)
					)
				)
				{$search_clause}";
			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			$total_items = (int) $wpdb->get_var($wpdb->prepare($count_sql, ...$prep_count));

			$offset = ($current_page - 1) * $per_page;
			$prep_list = array_merge(array($business_id), $search_args, array($per_page, $offset));
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			$list_sql = "SELECT p.ID FROM {$posts_table} p
				WHERE p.post_type = 'product' AND p.post_status = 'publish' AND p.post_parent = 0
				AND NOT EXISTS (
					SELECT 1 FROM {$map_table} m
					WHERE m.entity_type = 'product' AND m.business_id = %d
					AND (
						(m.wc_parent_id IS NULL AND m.wc_id = p.ID)
						OR (m.wc_parent_id = p.ID)
					)
				)
				{$search_clause}
				ORDER BY {$order_fragment}
				LIMIT %d OFFSET %d";

			// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			$ids_raw = $wpdb->get_col($wpdb->prepare($list_sql, ...$prep_list));

			$this->items = array();
			foreach (array_map('intval', (array) $ids_raw) as $pid) {
				$p = wc_get_product($pid);
				if ($p instanceof WC_Product) {
					$this->items[] = $p;
				}
			}

			$this->set_pagination_args(
				array(
					'total_items' => max(0, $total_items),
					'per_page' => $per_page,
					'total_pages' => max(1, (int) ceil(max(1, max(0, $total_items)) / $per_page)),
				)
			);
			return;
		}

		$status_map = array(
			'synced' => 'synced',
			'error' => 'error',
			'pending' => 'pending',
		);
		$sync_status = $status_map[ $filter ];

		$prep_count = array_merge(array($business_id, $sync_status), $search_args);
		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$count_sql = "SELECT COUNT(DISTINCT CASE
				WHEN m.wc_parent_id IS NULL OR m.wc_parent_id = 0 THEN m.wc_id
				ELSE m.wc_parent_id
			END)
			FROM {$map_table} m
			INNER JOIN {$posts_table} p ON p.ID = CASE
				WHEN m.wc_parent_id IS NULL OR m.wc_parent_id = 0 THEN m.wc_id
				ELSE m.wc_parent_id
			END
			WHERE m.entity_type = 'product' AND m.business_id = %d AND m.sync_status = %s
			AND p.post_type = 'product' AND p.post_status = 'publish' AND p.post_parent = 0
			{$search_clause}";

		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$total_items = (int) $wpdb->get_var($wpdb->prepare($count_sql, ...$prep_count));

		$offset = ($current_page - 1) * $per_page;
		$prep_list = array_merge(array($business_id, $sync_status), $search_args, array($per_page, $offset));
		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$list_sql = "SELECT DISTINCT CASE
				WHEN m.wc_parent_id IS NULL OR m.wc_parent_id = 0 THEN m.wc_id
				ELSE m.wc_parent_id
			END AS pid
			FROM {$map_table} m
			INNER JOIN {$posts_table} p ON p.ID = CASE
				WHEN m.wc_parent_id IS NULL OR m.wc_parent_id = 0 THEN m.wc_id
				ELSE m.wc_parent_id
			END
			WHERE m.entity_type = 'product' AND m.business_id = %d AND m.sync_status = %s
			AND p.post_type = 'product' AND p.post_status = 'publish' AND p.post_parent = 0
			{$search_clause}
			ORDER BY {$order_fragment}
			LIMIT %d OFFSET %d";

		// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$pids = $wpdb->get_col($wpdb->prepare($list_sql, ...$prep_list));

		$this->items = array();
		foreach (array_map('intval', (array) $pids) as $pid) {
			$p = wc_get_product($pid);
			if ($p instanceof WC_Product) {
				$this->items[] = $p;
			}
		}

		$this->set_pagination_args(
			array(
				'total_items' => max(0, $total_items),
				'per_page' => $per_page,
				'total_pages' => max(1, (int) ceil(max(1, max(0, $total_items)) / $per_page)),
			)
		);
	}
}
