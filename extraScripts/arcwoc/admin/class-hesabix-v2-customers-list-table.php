<?php
/**
 * فهرست مشتریان ووکامرس برای پنل حسابیکس.
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
class Hesabix_V2_Customers_List_Table extends WP_List_Table
{
	/** @param WP_User $user */
	private static function formatted_billing_phone($user)
	{
		$p = trim((string) get_user_meta($user->ID, 'billing_phone', true));
		if ($p !== '') {
			return $p;
		}
		return trim((string) get_user_meta($user->ID, 'shipping_phone', true));
	}

	/** @param WP_User $user */
	private static function wc_customer_roles_label($user)
	{
		$names = array();
		foreach ($user->roles as $slug) {
			$r = sanitize_key((string) $slug);
			$names[] = ucwords(str_replace('_', ' ', $r));
		}
		return implode(', ', $names);
	}

	/**
	 * @param array<string,mixed>|null $row
	 * @return string
	 */
	private static function hesabix_badge_markup($row)
	{
		if (!$row || empty($row['hesabix_id'])) {
			return '<span class="hesabix-v2-badge hesabix-v2-badge-muted">' . esc_html__('همگام نشده', 'hesabix-v2') . '</span>';
		}
		$st = isset($row['sync_status']) ? (string) $row['sync_status'] : 'synced';
		$hid = (int) $row['hesabix_id'];
		$label = __('شناسه شخص:', 'hesabix-v2') . ' ' . $hid;
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

	/** @param WP_User $item */
	protected function column_cb($item)
	{
		return sprintf('<input type="checkbox" name="customer_ids[]" value="%d" />', (int) $item->ID);
	}

	public function __construct()
	{
		parent::__construct(
			array(
				'singular' => 'customer',
				'plural' => 'customers',
				'ajax' => false,
			)
		);
	}

	protected function get_bulk_actions()
	{
		return array();
	}

	public function no_items()
	{
		esc_html_e('مشتری‌ای با این فیلتر یافت نشد.', 'hesabix-v2');
	}

	public function get_columns()
	{
		return array(
			'cb' => '<input type="checkbox" />',
			'customer' => __('مشتری', 'hesabix-v2'),
			'phone' => __('تلفن صورتحساب', 'hesabix-v2'),
			'roles_col' => __('نقش', 'hesabix-v2'),
			'hesabix' => __('حسابیکس', 'hesabix-v2'),
			'actions' => __('عملیات', 'hesabix-v2'),
		);
	}

	protected function get_sortable_columns()
	{
		return array(
			/* خروجی لینک: orderby = display_name / user_login تا با WP_User_Query و کوئری نگاشت یکی باشد */
			'customer' => array('display_name', false),
			'roles_col' => array('user_login', false),
		);
	}

	/** @param WP_User $item */
	protected function column_customer($item)
	{
		$edit = get_edit_user_link($item->ID);
		return sprintf(
			'<span class="description">#%d</span><br /><a href="%s"><strong>%s</strong></a><br /><span class="description">%s</span>',
			(int) $item->ID,
			esc_url($edit),
			esc_html((string) $item->display_name),
			esc_html((string) $item->user_email)
		);
	}

	/** @param WP_User $item */
	protected function column_phone($item)
	{
		$p = self::formatted_billing_phone($item);
		return $p !== '' ? esc_html($p) : '—';
	}

	/** @param WP_User $item */
	protected function column_roles_col($item)
	{
		return esc_html(self::wc_customer_roles_label($item));
	}

	/** @param WP_User $item */
	protected function column_hesabix($item)
	{
		$row = Hesabix_V2_Customer_Service::get_sync_status((int) $item->ID);
		return self::hesabix_badge_markup(is_array($row) ? $row : null);
	}

	/** @param WP_User $item */
	protected function column_actions($item)
	{
		$label = __('همگام‌سازی با حسابیکس', 'hesabix-v2');
		return sprintf(
			'<button type="button" class="button button-small hesabix-v2-customer-sync" data-customer-id="%d" %s>%s</button>',
			(int) $item->ID,
			disabled(!get_option('hesabix_v2_enabled'), false, false),
			esc_html($label)
		);
	}

	/** @param WP_User $item @param string $column_name */
	protected function column_default($item, $column_name)
	{
		return '';
	}

	protected function extra_tablenav($which)
	{
		if ($which !== 'top') {
			return;
		}
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended
		$current = isset($_GET['hx_cust_filter']) ? sanitize_key(wp_unslash((string) $_GET['hx_cust_filter'])) : 'all';
		if ($current === '') {
			$current = 'all';
		}

		$opts = array(
			'all' => __('همهٔ مشتریان', 'hesabix-v2'),
			'synced' => __('همگام‌شده با حسابیکس', 'hesabix-v2'),
			'not_synced' => __('همگام‌نشده', 'hesabix-v2'),
			'error' => __('خطای همگام‌سازی', 'hesabix-v2'),
			'pending' => __('در انتظار (نگاشت)', 'hesabix-v2'),
		);

		echo '<div class="alignleft actions hesabix-v2-customer-filters">';
		echo '<label for="hx_cust_filter" class="screen-reader-text">' . esc_html__('فیلتر حسابیکس', 'hesabix-v2') . '</label>';
		echo '<select name="hx_cust_filter" id="hx_cust_filter">';
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
	 * نقشٔ وردپرس در کوئری SQL با تطبیق روی متای serialized capabilities (همان نقش‌ها که role__in).
	 *
	 * @global wpdb $wpdb
	 * @param list<string> $roles
	 * @return array{0:string,1:array<int,mixed>} [ sql_fragment_without_leading_SPACE, ordered_prepare_args_for_fragment ]
	 */
	private static function user_role_exists_fragment_for_sql($wpdb, array $roles)
	{
		if ($roles === array()) {
			return array('', array());
		}

		$meta_key_caps = $wpdb->get_blog_prefix() . 'capabilities';
		$likes_sql = array();
		$like_args = array();
		foreach ($roles as $r) {
			$r = sanitize_key((string) $r);
			if ('' === $r) {
				continue;
			}
			$likes_sql[] = 'um.meta_value LIKE %s';
			// در meta_value نقش‌ها به‌شکل "...\"customer\";..." ذخیره می‌شوند.
			$like_args[] = '%"' . $wpdb->esc_like($r) . '"%';
		}
		if ($likes_sql === array()) {
			return array('', array());
		}

		$sql = ' AND EXISTS ( SELECT 1 FROM ' . $wpdb->usermeta . ' um WHERE um.user_id = u.ID AND um.meta_key = %s AND ( ';
		$sql .= implode(' OR ', $likes_sql);
		$sql .= ' ) ) ';

		$args = array_merge(array($meta_key_caps), $like_args);

		return array($sql, $args);
	}

	public function prepare_items()
	{
		global $wpdb;

		$this->items = array();
		$columns = $this->get_columns();
		$this->_column_headers = array($columns, array(), $this->get_sortable_columns());

		$roles = Hesabix_V2_Customer_Service::get_customer_list_roles();
		if ($roles === array()) {
			$this->set_pagination_args(
				array(
					'total_items' => 0,
					'per_page' => 20,
					'total_pages' => 1,
				)
			);
			return;
		}

		$per_page = 20;
		$current_page = max(1, (int) $this->get_pagenum());

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- browse/filter
		$filter = isset($_GET['hx_cust_filter']) ? sanitize_key(wp_unslash((string) $_GET['hx_cust_filter'])) : 'all';
		if ($filter === '') {
			$filter = 'all';
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- browse/search box
		$search_raw = isset($_REQUEST['s']) ? sanitize_text_field(wp_unslash((string) $_REQUEST['s'])) : '';
		if (strlen($search_raw) > 200) {
			$search_raw = mb_substr($search_raw, 0, 200);
		}

		// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- sortable URLs
		$orderby_raw = isset($_GET['orderby']) ? sanitize_key(wp_unslash((string) $_GET['orderby'])) : '';
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended
		$order_raw = isset($_GET['order']) ? strtolower(wp_unslash((string) $_GET['order'])) : 'desc';
		if ($orderby_raw !== 'registered' && $orderby_raw !== 'display_name' && $orderby_raw !== 'user_login') {
			$orderby_raw = 'registered';
		}
		if (!in_array($order_raw, array('asc', 'desc'), true)) {
			$order_raw = 'desc';
		}

		$business_id = (int) get_option('hesabix_v2_business_id');
		$map_table = $wpdb->prefix . 'hesabix_v2';

		$wp_orderby = ('display_name' === $orderby_raw) ? 'display_name' : ('user_login' === $orderby_raw ? 'login' : 'registered');
		$wp_order = $order_raw;

		$user_query_base = array(
			'role__in' => $roles,
			'orderby' => $wp_orderby,
			'order' => $wp_order,
			'number' => $per_page,
			'offset' => ($current_page - 1) * $per_page,
			'count_total' => true,
			'fields' => 'all',
			'search' => '' !== $search_raw ? '*' . $search_raw . '*' : '',
			'search_columns' => array('user_login', 'user_email', 'user_nicename', 'display_name'),
		);

		if ('not_synced' === $filter) {
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			$mapped = $wpdb->get_col(
				$wpdb->prepare(
					"SELECT DISTINCT wc_id FROM {$map_table} WHERE entity_type = %s AND business_id = %d",
					'customer',
					$business_id
				)
			);
			$user_query_base['exclude'] = array_map('intval', (array) $mapped);
			$q = new WP_User_Query($user_query_base);
			$res = isset($q->results) ? $q->results : array();
			$this->items = array_values(array_filter($res, static function ($x) {
				return $x instanceof WP_User;
			}));
			$this->set_pagination_args(
				array(
					'total_items' => (int) $q->get_total(),
					'per_page' => $per_page,
					'total_pages' => max(1, (int) ceil(max(1, (int) $q->get_total()) / $per_page)),
				)
			);
			return;
		}

		if ('all' === $filter) {
			$q = new WP_User_Query($user_query_base);
			$res = isset($q->results) ? $q->results : array();
			$this->items = array_values(array_filter($res, static function ($x) {
				return $x instanceof WP_User;
			}));
			$this->set_pagination_args(
				array(
					'total_items' => (int) $q->get_total(),
					'per_page' => $per_page,
					'total_pages' => max(1, (int) ceil(max(1, (int) $q->get_total()) / $per_page)),
				)
			);
			return;
		}

		$status_map = array(
			'synced' => 'synced',
			'error' => 'error',
			'pending' => 'pending',
		);
		$sync_status = isset($status_map[ $filter ]) ? $status_map[ $filter ] : 'synced';

		$user_like_clause = '';
		$prep = array($business_id, $sync_status);
		if ('' !== $search_raw) {
			$user_like_clause = ' AND ( u.user_login LIKE %s OR u.user_email LIKE %s OR u.display_name LIKE %s ) ';
			$esc = '%' . $wpdb->esc_like($search_raw) . '%';
			$prep[] = $esc;
			$prep[] = $esc;
			$prep[] = $esc;
		}

		list($role_frag_sql, $role_frag_args) = self::user_role_exists_fragment_for_sql($wpdb, $roles);
		$prep = array_merge($prep, $role_frag_args);

		$dir = ('DESC' === strtoupper($order_raw)) ? 'DESC' : 'ASC';
		$order_fragment = '';
		if ('display_name' === $orderby_raw) {
			$order_fragment = 'ORDER BY u.display_name ' . $dir . ', u.ID ' . $dir;
		} elseif ('user_login' === $orderby_raw) {
			$order_fragment = 'ORDER BY u.user_login ' . $dir . ', u.ID ' . $dir;
		} else {
			$order_fragment = 'ORDER BY u.user_registered ' . $dir . ', u.ID ' . $dir;
		}

		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- map_table / users from prefixes
		$count_sql = "SELECT COUNT(DISTINCT u.ID)
			FROM {$map_table} m
			INNER JOIN {$wpdb->users} u ON u.ID = m.wc_id
			WHERE m.entity_type = 'customer' AND m.business_id = %d AND m.sync_status = %s
			{$user_like_clause}
			{$role_frag_sql}";

		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$total_items = (int) $wpdb->get_var($wpdb->prepare($count_sql, ...$prep));

		$offset_sql = ($current_page - 1) * $per_page;
		$prep_sel = array_merge($prep, array($per_page, $offset_sql));
		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$list_sql = "SELECT DISTINCT u.ID
			FROM {$map_table} m
			INNER JOIN {$wpdb->users} u ON u.ID = m.wc_id
			WHERE m.entity_type = 'customer' AND m.business_id = %d AND m.sync_status = %s
			{$user_like_clause}
			{$role_frag_sql}
			{$order_fragment}
			LIMIT %d OFFSET %d";

		// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$ids_raw = $wpdb->get_col($wpdb->prepare($list_sql, ...$prep_sel));

		$this->items = array();
		foreach (array_map('intval', (array) $ids_raw) as $uid) {
			$res_user = get_userdata($uid);
			if ($res_user instanceof WP_User) {
				$this->items[] = $res_user;
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
