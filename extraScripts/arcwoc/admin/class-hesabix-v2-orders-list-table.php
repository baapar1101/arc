<?php
/**
 * فهرست سفارش‌ها برای پنل حسابیکس.
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
class Hesabix_V2_Orders_List_Table extends WP_List_Table
{
	/**
	 * @return void
	 */
	public function __construct()
	{
		parent::__construct(
			array(
				'singular' => 'order',
				'plural' => 'orders',
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
		esc_html_e('سفارشی در این فیلتر یافت نشد.', 'hesabix-v2');
	}

	/**
	 * @return array<string,string>
	 */
	public function get_columns()
	{
		return array(
			'cb' => '<input type="checkbox" />',
			'order' => __('سفارش', 'hesabix-v2'),
			'date' => __('تاریخ', 'hesabix-v2'),
			'status' => __('وضعیت', 'hesabix-v2'),
			'customer' => __('خریدار', 'hesabix-v2'),
			'total' => __('مبلغ', 'hesabix-v2'),
			'hesabix' => __('حسابیکس', 'hesabix-v2'),
			'pause' => __('همگام خودکار', 'hesabix-v2'),
			'actions' => __('عملیات', 'hesabix-v2'),
		);
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_cb($item)
	{
		return sprintf('<input type="checkbox" name="order_ids[]" value="%d" />', (int) $item->get_id());
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_order($item)
	{
		$edit = $item->get_edit_order_url();
		$num = $item->get_order_number();
		$link = sprintf('<a href="%s"><strong>#%s</strong></a>', esc_url($edit), esc_html((string) $num));
		return $link;
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_date($item)
	{
		$d = $item->get_date_created();
		return $d ? esc_html($d->date_i18n(get_option('date_format') . ' ' . get_option('time_format'))) : '—';
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_status($item)
	{
		return esc_html(wc_get_order_status_name($item->get_status()));
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_customer($item)
	{
		$name = trim($item->get_formatted_billing_full_name());
		if ($name === '') {
			$name = __('بدون نام', 'hesabix-v2');
		}
		$email = $item->get_billing_email();
		$phone = $item->get_billing_phone();
		$bits = array(esc_html($name));
		if ($email !== '') {
			$bits[] = '<span class="description">' . esc_html($email) . '</span>';
		}
		if ($phone !== '') {
			$bits[] = '<span class="description">' . esc_html($phone) . '</span>';
		}
		return implode('<br />', $bits);
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_total($item)
	{
		return wp_kses_post($item->get_formatted_order_total());
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_hesabix($item)
	{
		$row = Hesabix_V2_Invoice_Service::get_sync_status((int) $item->get_id());
		if (!$row || empty($row['hesabix_id'])) {
			return '<span class="hesabix-v2-badge hesabix-v2-badge-muted">' . esc_html__('ارسال نشده', 'hesabix-v2') . '</span>';
		}
		$st = isset($row['sync_status']) ? (string) $row['sync_status'] : 'synced';
		$hid = (int) $row['hesabix_id'];
		$label = __('شناسه فاکتور:', 'hesabix-v2') . ' ' . $hid;

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

		return '<span class="hesabix-v2-badge hesabix-v2-badge-ok">' . esc_html__('ارسال شده', 'hesabix-v2') . '</span><br /><small>' . esc_html($label) . '</small>';
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_pause($item)
	{
		$oid = (int) $item->get_id();
		$paused = Hesabix_V2_Order_Sync_Meta::is_pause_auto_sync($oid);
		$paused_attr = $paused ? '1' : '0';
		if ($paused) {
			$txt = '<span class="hesabix-v2-badge hesabix-v2-badge-warn">' . esc_html__('متوقف', 'hesabix-v2') . '</span>';
		} else {
			$txt = '<span class="hesabix-v2-badge hesabix-v2-badge-muted">' . esc_html__('فعال', 'hesabix-v2') . '</span>';
		}
		$btn_label = $paused ? __('از سرگیری خودکار', 'hesabix-v2') : __('توقف خودکار', 'hesabix-v2');
		$btn = sprintf(
			'<button type="button" class="button button-small hesabix-v2-pause-toggle" data-order-id="%d" data-paused="%s">%s</button>',
			$oid,
			esc_attr($paused_attr),
			esc_html($btn_label)
		);
		return $txt . '<br />' . $btn;
	}

	/**
	 * @param WC_Order $item
	 * @return string
	 */
	protected function column_actions($item)
	{
		$syn = __('ارسال / به‌روزرسانی', 'hesabix-v2');
		$uns = __('لغو ارسال', 'hesabix-v2');
		$oid = (int) $item->get_id();
		return sprintf(
			'<button type="button" class="button button-small hesabix-v2-order-sync" data-order-id="%d">%s</button> '
			. '<button type="button" class="button button-small hesabix-v2-order-unsync" data-order-id="%d">%s</button>',
			$oid,
			esc_html($syn),
			$oid,
			esc_html($uns)
		);
	}

	/**
	 * @param WC_Order $item
	 * @param string   $column_name
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

		$current = isset($_GET['hesabix_filter']) ? sanitize_key(wp_unslash((string) $_GET['hesabix_filter'])) : 'all';
		$opts = array(
			'all' => __('همهٔ سفارش‌ها', 'hesabix-v2'),
			'synced' => __('ارسال‌شده به حسابیکس', 'hesabix-v2'),
			'not_synced' => __('ارسال‌نشده', 'hesabix-v2'),
			'error' => __('خطای همگام‌سازی', 'hesabix-v2'),
			'pending' => __('در انتظار (نگاشت)', 'hesabix-v2'),
		);
		echo '<div class="alignleft actions hesabix-v2-order-filters">';
		echo '<label for="hesabix_filter" class="screen-reader-text">' . esc_html__('فیلتر حسابیکس', 'hesabix-v2') . '</label>';
		echo '<select name="hesabix_filter" id="hesabix_filter">';
		foreach ($opts as $val => $lab) {
			printf(
				'<option value="%s"%s>%s</option>',
				esc_attr($val),
				selected($current, $val, false),
				esc_html($lab)
			);
		}
		echo '</select>';
		submit_button(__('فیلتر', 'hesabix-v2'), 'secondary', 'filter_action', false);
		echo '</div>';
	}

	/**
	 * Default wc_get_orders() uses statuses from wc_get_order_statuses() or equivalent; checkout-draft is excluded from that set (e.g. HPOS OrdersTableQuery::sanitize_status). Include it explicitly for CPT + HPOS.
	 *
	 * @return array<int,string>
	 */
	private static function order_statuses_for_list_query()
	{
		$statuses = array_keys( wc_get_order_statuses() );
		if (!in_array('wc-checkout-draft', $statuses, true)) {
			$statuses[] = 'wc-checkout-draft';
		}
		return $statuses;
	}

	/**
	 * @return void
	 */
	public function prepare_items()
	{
		$per_page = 20;
		$current_page = max(1, (int) $this->get_pagenum());
		$filter = isset($_GET['hesabix_filter']) ? sanitize_key(wp_unslash((string) $_GET['hesabix_filter'])) : 'all';
		$business_id = (int) get_option('hesabix_v2_business_id');

		global $wpdb;
		$map_table = $wpdb->prefix . 'hesabix_v2';

		if (in_array($filter, array('synced', 'error', 'pending'), true)) {
			$status_map = array(
				'synced' => 'synced',
				'error' => 'error',
				'pending' => 'pending',
			);
			$st = $status_map[ $filter ];
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared -- table name from trusted prefix
			$total_items = (int) $wpdb->get_var(
				$wpdb->prepare(
					"SELECT COUNT(*) FROM {$map_table} WHERE entity_type = %s AND business_id = %d AND sync_status = %s",
					'order',
					$business_id,
					$st
				)
			);
			$offset = ($current_page - 1) * $per_page;
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			$wc_ids = $wpdb->get_col(
				$wpdb->prepare(
					"SELECT wc_id FROM {$map_table} WHERE entity_type = %s AND business_id = %d AND sync_status = %s ORDER BY COALESCE(last_sync_at, created_at) DESC, wc_id DESC LIMIT %d OFFSET %d",
					'order',
					$business_id,
					$st,
					$per_page,
					$offset
				)
			);
			$this->items = array_values(
				array_filter(
					array_map('wc_get_order', array_map('intval', $wc_ids))
				)
			);
		} elseif ($filter === 'not_synced') {
			// phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			$mapped = $wpdb->get_col(
				$wpdb->prepare(
					"SELECT wc_id FROM {$map_table} WHERE entity_type = %s AND business_id = %d",
					'order',
					$business_id
				)
			);
			$mapped = array_map('intval', $mapped);
			$args = array(
				'limit' => $per_page,
				'page' => $current_page,
				'paginate' => true,
				'orderby' => 'date',
				'order' => 'DESC',
				'status' => self::order_statuses_for_list_query(),
			);
			if (!empty($mapped)) {
				$args['exclude'] = $mapped;
			}
			$query = wc_get_orders($args);
			if (is_object($query) && isset($query->orders)) {
				$this->items = $query->orders;
				$total_items = (int) $query->total;
			} else {
				$this->items = is_array($query) ? $query : array();
				$total_items = count($this->items);
			}
		} else {
			$query = wc_get_orders(
				array(
					'limit' => $per_page,
					'page' => $current_page,
					'paginate' => true,
					'orderby' => 'date',
					'order' => 'DESC',
					'status' => self::order_statuses_for_list_query(),
				)
			);
			$this->items = $query->orders;
			$total_items = (int) $query->total;
		}

		$this->set_pagination_args(
			array(
				'total_items' => $total_items,
				'per_page' => $per_page,
				'total_pages' => max(1, (int) ceil($total_items / $per_page)),
			)
		);
	}
}
