<?php
/**
 * Settings view
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}

$sync_settings = Hesabix_V2_Invoice_Helper::normalize_sync_settings(get_option('hesabix_v2_sync_settings', array()));
$wc_status_choices = Hesabix_V2_Invoice_Helper::get_wc_order_status_choices();
$debug_mode = get_option('hesabix_v2_debug_mode', false);
$add_checkout_fields = get_option('hesabix_v2_add_checkout_fields', false);
$api_key = get_option('hesabix_v2_api_key');
$api_base_url = get_option('hesabix_v2_api_base_url', HESABIX_V2_API_BASE_URL);
$ob_inv_done = (bool) get_option('hesabix_v2_opening_inventory_completed');
$ob_inv_prefs = get_option('hesabix_v2_opening_inventory_prefs', array());
if (!is_array($ob_inv_prefs)) {
	$ob_inv_prefs = array();
}
$ob_inv_prefs = wp_parse_args(
	$ob_inv_prefs,
	array(
		'include_tax' => false,
		'cost_basis' => 'regular',
		'auto_balance_to_equity' => true,
		'do_post' => false,
		'batch_size' => 12,
		'inventory_account_id' => 0,
		'equity_account_id' => 0,
		'warehouse_override' => 0,
	)
);
$invoice_payment_destination = get_option('hesabix_v2_invoice_payment_destination', 'bank');
if ($invoice_payment_destination !== 'cash_register') {
	$invoice_payment_destination = 'bank';
}

$stock_pull_opts = Hesabix_V2_Stock_Pull_Service::get_options();
$inv_wh_cfg = Hesabix_V2_Invoice_Warehouse_Service::get_config();
$inv_wh_saved_wids = array();
for ($iwp = 0; $iwp < 12; $iwp++) {
	$rww = isset($inv_wh_cfg['rules'][ $iwp ]['warehouse_id']) ? absint($inv_wh_cfg['rules'][ $iwp ]['warehouse_id']) : 0;
	$inv_wh_saved_wids[] = $rww;
}
$saved_cash_register_id = get_option('hesabix_v2_default_cash_register_id', '');
$saved_currency_id = (int) get_option('hesabix_v2_currency_id', 0);
$saved_shipping_adjustment_account_id = isset($sync_settings['shipping_adjustment_account_id']) ? (int) $sync_settings['shipping_adjustment_account_id'] : 0;
$hesabix_v2_upd_defaults = array(
	'current_version' => defined('HESABIX_V2_VERSION') ? HESABIX_V2_VERSION : '',
	'remote_version' => '',
	'remote_loaded' => false,
	'configured' => false,
	'configured_raw_zip' => false,
	'configured_manifest_only' => false,
	'source_kind' => '',
	'download_available' => false,
	'wp_compatible' => true,
	'php_compatible' => true,
	'env_compatible' => true,
	'requires_wp' => '',
	'requires_php' => '',
	'update_available' => false,
	'newer_than_local' => false,
	'can_install' => false,
);
$hesabix_v2_upd_state = $hesabix_v2_upd_defaults;
if (class_exists('Hesabix_V2_Updater', false)) {
	$hesabix_v2_upd_state = array_merge($hesabix_v2_upd_defaults, Hesabix_V2_Updater::instance()->get_update_dashboard_state(false));
}

global $wpdb, $wp_version;
$hsx_plugin_version = defined('HESABIX_V2_VERSION') ? HESABIX_V2_VERSION : '';
$hsx_mysql_version = isset($wpdb) && method_exists($wpdb, 'db_version') ? $wpdb->db_version() : '';
$hsx_php_ver = phpversion();

$hsx_wp_ver = $wp_version;
if ($hsx_wp_ver === '') {
	$hsx_wp_ver = get_bloginfo('version');
}

$hsx_wc_ver = '—';
if (defined('WC_VERSION')) {
	$hsx_wc_ver = WC_VERSION;
} elseif (function_exists('WC') && is_callable(array('WC', 'instance'))) {
	$maybe = WC();
	if ($maybe && isset($maybe->version)) {
		$hsx_wc_ver = $maybe->version;
	}
}

$hsx_conn_ok = !empty(get_option('hesabix_v2_api_key'));

$hsx_bridge_enabled = class_exists('Hesabix_V2_Bridge_Rest', false) && (bool) get_option(Hesabix_V2_Bridge_Rest::OPT_ENABLED);
$hsx_bridge_token_set = class_exists('Hesabix_V2_Bridge_Rest', false) && (string) get_option(Hesabix_V2_Bridge_Rest::OPT_TOKEN_HASH, '') !== '';
$hsx_bridge_base = class_exists('Hesabix_V2_Bridge_Rest', false) ? rest_url(Hesabix_V2_Bridge_Rest::NS) : '';

$hsx_max_exec = (string) ini_get('max_execution_time');
$saved_invoice_extra_tag_ids = Hesabix_V2_Invoice_Helper::parse_extra_tag_ids(
	isset($sync_settings['invoice_extra_tag_ids']) ? (string) $sync_settings['invoice_extra_tag_ids'] : ''
);

if ($hsx_max_exec === '' || $hsx_max_exec === false) {
	$hsx_max_exec_disp = '—';
} elseif ($hsx_max_exec === '0') {
	$hsx_max_exec_disp = __('۰ (بدون محدودیت اعلامی با این کاربر وب)', 'hesabix-v2');
} else {
	$hsx_max_exec_disp = sprintf(
		/* translators: %s: max_execution_time from php.ini */
		__('%s ثانیه', 'hesabix-v2'),
		$hsx_max_exec
	);
}

$mem_wp = '';
if (defined('WP_MEMORY_LIMIT')) {
	$mem_wp = (string) WP_MEMORY_LIMIT;
}

$mem_ini = ini_get('memory_limit');
$hsx_upload = ini_get('upload_max_filesize') ?: '';
$hsx_post = ini_get('post_max_size') ?: '';
?>

<div class="wrap hesabix-v2-wrap">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php settings_errors('hesabix_v2_messages'); ?>

	<form method="post" action="">
		<?php wp_nonce_field('hesabix_v2_settings'); ?>

		<style>
			.hesabix-v2-settings-tabs { margin: 1em 0 0; padding-top: 4px; }
			.hesabix-v2-tab-panel { margin-top: 0.5em; }
			.hesabix-v2-tab-panel[hidden] { display: none !important; }
			.hesabix-v2-settings-submit-wrap {
				margin-top: 1.5em;
				padding: 14px 0 6px;
				border-top: 1px solid #c3c4c7;
				position: sticky;
				bottom: 0;
				background: #fff;
				box-shadow: 0 -6px 16px rgba(0, 0, 0, 0.06);
				z-index: 100;
			}
			.hesabix-v2-settings-submit-wrap .submit { margin: 0; padding: 0; }
			.hesabix-v2-sysinfo { max-width: 920px; margin-top: 0.75em; }
			.hesabix-v2-sysinfo-intro {
				display: flex; flex-wrap: wrap; gap: 12px;
				align-items: center; justify-content: space-between;
				margin-bottom: 16px;
			}
			.hesabix-v2-sysinfo-badge {
				display: inline-flex; align-items: center; gap: 8px;
				padding: 8px 14px; border-radius: 999px;
				font-weight: 600; font-size: 13px;
			}
			.hesabix-v2-sysinfo-badge.connected { background: #d5f5e3; color: #14532d; border: 1px solid #a7dcb5; }
			.hesabix-v2-sysinfo-badge.offline { background: #fde8ea; color: #7f1d1d; border: 1px solid #f5c6cb; }
			.hesabix-v2-sysinfo-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; }
			.hesabix-v2-sysinfo-card {
				background: #fff; border: 1px solid #dcdcde; border-radius: 8px;
				box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
				overflow: hidden;
			}
			.hesabix-v2-sysinfo-card h3 {
				margin: 0; padding: 10px 14px; font-size: 13px; font-weight: 700;
				background: linear-gradient(to bottom, #f6f7f7 0%, #f0f0f1 100%);
				border-bottom: 1px solid #e0e0e0;
			}
			.hesabix-v2-sysinfo-card dl {
				margin: 0; padding: 12px 14px;
			}
			.hesabix-v2-sysinfo-card dt {
				float: left; clear: left; font-weight: 600; font-size: 12px;
				color: #50575e; width: 48%; padding: 6px 0 6px;
			}
			.hesabix-v2-sysinfo-card dd {
				margin: 0 0 0 50%; padding: 6px 0;
				text-align: left; direction: ltr;
				font-size: 12px;
				word-break: break-word;
				color: #1d2327;
			}
			@media (max-width: 600px) {
				.hesabix-v2-sysinfo-card dt,
				.hesabix-v2-sysinfo-card dd {
					width: auto; margin: 0; float: none; text-align: right; direction: rtl;
				}
			}
		</style>
		<h2 class="nav-tab-wrapper hesabix-v2-settings-tabs wp-clearfix">
			<a href="#" class="nav-tab nav-tab-active" role="tab" aria-selected="true" data-tab="connection"><?php esc_html_e('اتصال', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="sync"><?php esc_html_e('همگام‌سازی', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="invoice"><?php esc_html_e('فاکتور', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="opening_inv"><?php esc_html_e('موجودی افتتاحیه', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="extra"><?php esc_html_e('سایر', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="update"><?php esc_html_e('به‌روزرسانی افزونه', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="system"><?php esc_html_e('اطلاعات سیستم', 'hesabix-v2'); ?></a>
		</h2>

		<div class="hesabix-v2-tab-panel" data-tab="connection">
			<h2 class="screen-reader-text"><?php esc_html_e('تنظیمات اتصال', 'hesabix-v2'); ?></h2>

			<div class="notice notice-warning hesabix-v2-connection-notes" role="region" aria-labelledby="hesabix-v2-connection-notes-title">
				<p id="hesabix-v2-connection-notes-title"><strong><?php esc_html_e('نکات مهم', 'hesabix-v2'); ?></strong></p>
				<ul class="hesabix-v2-connection-notes-list">
					<li><?php esc_html_e('برای اتصال به API حسابیکس و فعال‌سازی این افزونه، باید کلید API و توکن ورود خود را در اینجا وارد کنید.', 'hesabix-v2'); ?></li>
					<li><?php esc_html_e('برای یافتن توکن ورود و کلید API، در حسابیکس به مسیر تنظیمات حساب ← کلیدهای API مراجعه کنید.', 'hesabix-v2'); ?></li>
					<li><?php esc_html_e('اگر می‌خواهید کسب‌وکار دیگری را به افزونه متصل کنید، ابتدا افزونه را حذف و مجدد نصب کنید تا ارتباطات کسب‌وکار قبلی پاک شود.', 'hesabix-v2'); ?></li>
				</ul>
				<p class="hesabix-v2-connection-notes-ark">
					<?php esc_html_e('این نسخه برای اتصال به حسابیکس (صرفاً نسخهٔ آرک) طراحی شده است و به نسخه‌های دیگر از جمله نسخهٔ شادمان متصل نخواهد شد.', 'hesabix-v2'); ?>
				</p>
			</div>

		<table class="form-table">
			<tr>
				<th scope="row"><?php _e('آدرس سرور API', 'hesabix-v2'); ?></th>
				<td>
					<input type="url" name="api_base_url" id="api_base_url" value="<?php echo esc_attr($api_base_url); ?>" class="regular-text" dir="ltr">
					<p class="description"><?php _e('آدرس پایه سرور API حسابیکس (مثال: https://hsxn.hesabix.ir/api/v1). مطابق مستندات OpenAPI در آدرس سرور باید مسیر /api/v1 قرار گیرد.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('وضعیت API', 'hesabix-v2'); ?></th>
				<td>
					<?php if ($api_key): ?>
						<span style="color: green;">✓ <?php _e('متصل', 'hesabix-v2'); ?></span>
						<div
							id="hesabix-v2-settings-connection-live"
							class="hesabix-v2-connection-panel hesabix-v2-connection-panel--settings"
							aria-live="polite"
						>
							<p class="hesabix-v2-muted"><?php esc_html_e('در حال دریافت جزئیات کسب‌وکار…', 'hesabix-v2'); ?></p>
						</div>
						<p class="description" style="margin-top:10px;">
							<button
								type="button"
								class="button hesabix-v2-test-connection"
								data-hesabix-connection-result="#hesabix-v2-settings-connection-test-result"
								data-hesabix-connection-extra="#hesabix-v2-settings-connection-live"
							><?php esc_html_e('تست اتصال', 'hesabix-v2'); ?></button>
							<a href="<?php echo esc_url(admin_url('admin.php?page=hesabix-v2-setup')); ?>" class="button hesabix-v2-change-connection-trigger">
								<?php _e('تغییر کسب‌وکار', 'hesabix-v2'); ?>
							</a>
						</p>
						<div id="hesabix-v2-settings-connection-test-result" class="hesabix-v2-settings-test-result"></div>
					<?php else: ?>
						<span style="color: red;">✗ <?php _e('متصل نیست', 'hesabix-v2'); ?></span>
						<p class="description">
							<a href="<?php echo esc_url(admin_url('admin.php?page=hesabix-v2-setup')); ?>">
								<?php _e('راه‌اندازی اتصال', 'hesabix-v2'); ?>
							</a>
						</p>
					<?php endif; ?>
				</td>
			</tr>
		</table>

		<h2 style="margin-top:1.5em;"><?php esc_html_e('پل REST برای حسابیکس', 'hesabix-v2'); ?></h2>
		<p class="description"><?php esc_html_e('با این پل، سرور حسابیکس می‌تواند (با توکن) سفارشات، محصولات و مشتریان ووکامرس را بخواند. آدرس پایهٔ API:', 'hesabix-v2'); ?>
			<code dir="ltr" style="user-select:all;"><?php echo esc_html(rtrim((string) $hsx_bridge_base, '/')); ?></code>
		</p>
		<table class="form-table">
			<tr>
				<th scope="row"><?php esc_html_e('فعال‌سازی پل', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="hesabix_v2_bridge_enabled" value="1" <?php checked($hsx_bridge_enabled); ?>>
						<?php esc_html_e('اجازهٔ دسترسی با توکن (پس از ذخیره، توکن را در حسابیکس وارد کنید)', 'hesabix-v2'); ?>
					</label>
					<p class="description">
						<?php
						echo esc_html(
							$hsx_bridge_token_set
								? __('توکن ذخیره شده است. برای چرخش، دکمهٔ زیر را بزنید.', 'hesabix-v2')
								: __('هنوز توکنی ایجاد نشده است.', 'hesabix-v2')
						);
						?>
					</p>
					<p>
						<button type="button" class="button button-secondary" id="hesabix-v2-bridge-generate-token">
							<?php esc_html_e('تولید / چرخش توکن', 'hesabix-v2'); ?>
						</button>
						<span id="hesabix-v2-bridge-token-inline" class="description" dir="ltr" style="display:block;margin-top:8px;"></span>
					</p>
				</td>
			</tr>
		</table>
		</div>

		<div class="hesabix-v2-tab-panel" data-tab="sync" hidden>
			<h2 class="screen-reader-text"><?php esc_html_e('تنظیمات همگام‌سازی', 'hesabix-v2'); ?></h2>
		<table class="form-table">
			<tr>
				<th scope="row"><?php _e('همگام‌سازی خودکار محصولات', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="auto_sync_products" value="1" <?php checked($sync_settings['auto_sync_products'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('محصولات جدید به طور خودکار به حسابیکس ارسال شوند', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('همگام‌سازی هنگام ویرایش محصول', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="sync_on_product_update" value="1" <?php checked($sync_settings['sync_on_product_update'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('همگام‌سازی دستهٔ محصول با حسابیکس', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="sync_product_categories" value="1" <?php checked(!isset($sync_settings['sync_product_categories']) || !empty($sync_settings['sync_product_categories'])); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('در صورت غیرفعال بودن، محصول بدون دستهٔ حسابیکس ارسال می‌شود.', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('تطبیق دسته با نام موجود در حسابیکس', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="sync_category_link_by_name_in_hesabix" value="1" <?php checked(!empty($sync_settings['sync_category_link_by_name_in_hesabix'])); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('اگر دستهٔ ووکامرس هنوز در افزونه نگاشت نشده باشد، قبل از ساخت رکورد جدید، درخت دسته‌های حسابیکس برای همان نام و همان والد جستجو می‌شود و در صورت انطباق، همان شناسه پیوند می‌خورد (برای جلوگیری از تکرار نام).', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('همگام‌سازی قیمت محصول', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="sync_product_price" value="1" <?php checked($sync_settings['sync_product_price'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('همگام‌سازی موجودی محصول', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="sync_product_stock" value="1" <?php checked($sync_settings['sync_product_stock'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('کنترل موجودی حسابیکس نسبت به ووکامرس', 'hesabix-v2'); ?></th>
				<td>
					<select name="track_inventory_policy" id="hesabix_v2_track_inventory_policy" class="regular-text">
						<option value="wc" <?php selected(($sync_settings['track_inventory_policy'] ?? 'wc'), 'wc'); ?>>
							<?php _e('مطابق ووکامرس (تیک «مدیریت موجودی»)', 'hesabix-v2'); ?>
						</option>
						<option value="physical_always" <?php selected(($sync_settings['track_inventory_policy'] ?? 'wc'), 'physical_always'); ?>>
							<?php _e('برای کالاهای فیزیکی همیشه روشن؛ خدمات ردیابی نمی‌شوند', 'hesabix-v2'); ?>
						</option>
						<option value="always_on" <?php selected(($sync_settings['track_inventory_policy'] ?? 'wc'), 'always_on'); ?>>
							<?php _e('همیشه روشن برای همهٔ اقلام ارسالی (کالا و خدمت)', 'hesabix-v2'); ?>
						</option>
						<option value="always_off" <?php selected(($sync_settings['track_inventory_policy'] ?? 'wc'), 'always_off'); ?>>
							<?php _e('همیشه خاموش', 'hesabix-v2'); ?>
						</option>
					</select>
					<p class="description"><?php _e('فقط هنگامی که «همگام‌سازی موجودی محصول» فعال است اعمال می‌شود؛ در صورت غیرفعال بودن آن، کنترل موجودی در حسابیکس در همگام‌سازی خاموش می‌ماند.', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('همگام‌سازی خودکار مشتریان', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="auto_sync_customers" value="1" <?php checked($sync_settings['auto_sync_customers'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('ثبت‌نام کاربر با نقش مشتری، ویرایش پروفایل وردپرس، و ذخیرهٔ مشتری از حساب کاربری من ووکامرس (هوک woocommerce_update_customer).', 'hesabix-v2'); ?></p>
					<p class="description">
						<?php
						echo wp_kses_post(
							sprintf(
								/* translators: 1: opening <a>, 2: closing </a> — link wraps «صفحهٔ مشتریان و حسابیکس». */
								__('برای مشاهدهٔ وضعیت هر مشتری و همگام‌سازی تکی یا گروهی با حسابیکس، به %1$sصفحهٔ مشتریان و حسابیکس%2$s بروید.', 'hesabix-v2'),
								'<a href="' . esc_url(admin_url('admin.php?page=hesabix-v2-customers')) . '">',
								'</a>'
							)
						);
						?>
					</p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('همگام‌سازی خودکار سفارشات', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="auto_sync_orders" value="1" <?php checked($sync_settings['auto_sync_orders'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('وقتی غیرفعال باشد، هیچ‌کدام از گزینه‌های زیر اجرا نمی‌شوند.', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('تعداد آیتم صف در هر اجرای کرون', 'hesabix-v2'); ?></th>
				<td>
					<label for="hesabix_v2_queue_items_per_cron_run">
						<input type="number" name="queue_items_per_cron_run" id="hesabix_v2_queue_items_per_cron_run"
							min="1" max="500" step="1" class="small-text"
							value="<?php echo esc_attr((string) ($sync_settings['queue_items_per_cron_run'] ?? 15)); ?>">
					</label>
					<p class="description">
						<?php _e('در هر بار فراخوانی خودکار پردازشگر صف (کرون هر ۵ دقیقه یا کرون دستی)، حداکثر این تعداد کار در صف همگام‌سازی یکی‌یکی انجام می‌شود؛ شامل سفارش، مشتری و محصولی که از طریق صف آمده باشند.', 'hesabix-v2'); ?>
					</p>
					<p class="description">
						<?php _e('توجه: API حسابیکس در این افزونه هر فاکتور یا شخص را با یک درخواست جدا می‌فرستد؛ این عدد تنها ظرفیت «خالی‌کردن صف» در هر اجرا را زیاد می‌کند نه ادغام چند فاکتور در یک بدنهٔ HTTP.', 'hesabix-v2'); ?>
					</p>
					<p class="description">
						<?php _e('برای مقادیر زیاد از کرون سیستم واقعی برای wp-cron استفاده کنید و در صورت تایم‌اوت PHP، عدد را کم کنید یا فاصلهٔ اجرای کرون را کمتر کنید.', 'hesabix-v2'); ?>
					</p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('ارسال فاکتور: بعد از چک‌اوت', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="sync_order_on_checkout" value="1" <?php checked(!empty($sync_settings['sync_order_on_checkout'])); ?>>
						<?php _e('فعال (پیشنهادی — پس از تکمیل خرید و ذخیره ردیف‌های سفارش)', 'hesabix-v2'); ?>
					</label>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('ارسال فاکتور: پس از پرداخت', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="sync_order_on_payment_complete" value="1" <?php checked(!empty($sync_settings['sync_order_on_payment_complete'])); ?>>
						<?php _e('فعال (هوک woocommerce_payment_complete)', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('در کنار چک‌اوت می‌تواند دوباره همگام‌سازی را برای به‌روز شدن پرداخت اجرا کند.', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('ارسال فاکتور: با تغییر وضعیت سفارش', 'hesabix-v2'); ?></th>
				<td>
					<fieldset style="max-height:220px;overflow:auto;border:1px solid #ccd0d4;padding:8px;">
						<?php
						$sel = isset($sync_settings['sync_order_on_statuses']) && is_array($sync_settings['sync_order_on_statuses'])
							? $sync_settings['sync_order_on_statuses']
							: array();
						foreach ($wc_status_choices as $slug => $label) :
							?>
							<label style="display:block;margin:4px 0;">
								<input type="checkbox" name="sync_order_on_statuses[]" value="<?php echo esc_attr($slug); ?>"
									<?php checked(in_array($slug, $sel, true)); ?>>
								<?php echo esc_html($label); ?>
								<code style="font-size:11px;">(<?php echo esc_html($slug); ?>)</code>
							</label>
						<?php endforeach; ?>
					</fieldset>
					<p class="description"><?php _e('هر وضعیتی که علامت بزنید، با رسیدن سفارش به همان وضعیت فاکتور در حسابیکس به‌روز می‌شود (در صورت وجود مپینگ، به‌روزرسانی).', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('ایجاد مشتری از سفارش', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="create_customer_on_order" value="1" <?php checked($sync_settings['create_customer_on_order'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('اگر مشتری در حسابیکس وجود نداشت، ایجاد شود', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('سفارش و بازهٔ سال مالی حسابیکس', 'hesabix-v2'); ?></th>
				<td>
					<select name="order_fiscal_year_date_policy">
						<option value="keep" <?php selected(($sync_settings['order_fiscal_year_date_policy'] ?? 'keep'), 'keep'); ?>>
							<?php _e('بدون تغییر — تاریخ ایجاد سفارش ووکامرس همان تاریخ سند حسابیکس', 'hesabix-v2'); ?>
						</option>
						<option value="clamp" <?php selected(($sync_settings['order_fiscal_year_date_policy'] ?? 'keep'), 'clamp'); ?>>
							<?php _e('اصلاح به بازهٔ سال مالی جاری — اگر سفارش قبل از ابتدای سال باشد، تاریخ سند اولین روز سال؛ اگر بعد از انتهای سال باشد، آخرین روز سال (پرداخت‌های همراه فاکتور در صورت نیاز هم‌سو می‌شوند)', 'hesabix-v2'); ?>
						</option>
						<option value="skip" <?php selected(($sync_settings['order_fiscal_year_date_policy'] ?? 'keep'), 'skip'); ?>>
							<?php _e('عدم همگام‌سازی — اگر تاریخ سفارش خارج از سال مالی جاری باشد، فاکتور ارسال نمی‌شود', 'hesabix-v2'); ?>
						</option>
					</select>
					<p class="description"><?php _e('بازهٔ سال از API سال مالی «جاری» حسابیکس خوانده می‌شود و حداکثر یک ساعت کش می‌شود. اگر دریافت بازه ممکن نباشد، رفتار «بدون تغییر» اعمال می‌شود و یک هشدار در لاگ ثبت می‌گردد.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
		</table>
		</div>

		<div class="hesabix-v2-tab-panel" data-tab="invoice" hidden>
			<input type="hidden" name="hesabix_v2_invoice_tab_fields" value="1" />
			<h2 class="screen-reader-text"><?php esc_html_e('تنظیمات فاکتور', 'hesabix-v2'); ?></h2>
		<table class="form-table">
			<tr>
				<th scope="row"><?php _e('نوع سند در حسابیکس', 'hesabix-v2'); ?></th>
				<td>
					<label style="display:block;margin-bottom:6px;">
						<input type="radio" name="invoice_doc_mode" value="final" <?php checked(empty($sync_settings['invoice_is_proforma'])); ?>>
						<?php _e('فاکتور / سند قطعی (غیر پیش‌فاکتور)', 'hesabix-v2'); ?>
					</label>
					<label style="display:block;">
						<input type="radio" name="invoice_doc_mode" value="proforma" <?php checked(!empty($sync_settings['invoice_is_proforma'])); ?>>
						<?php _e('پیش‌فاکتور / پیش‌نویس (is_proforma)', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('برای قطعی‌شدن فروش و ثبت خودکار خروج انبار همسو با گزارش موجودی، گزینهٔ فاکتور قطعی را انتخاب کنید. برای پیش‌فاکتور، حسابیکس حواله انبار از روی همین فاکتور تا قبل از قطعی ایجاد نمی‌کند؛ با همگام‌سازی دوباره و ارسال is_proforma=false، فاکتور در حسابیکس قطعی و حواله طبق تنظیم کسب‌وکار ساخته می‌شود.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr class="hesabix-v2-proforma-finalize-settings">
				<th scope="row"><?php _e('ارتقاء پیش‌فاکتور به قطعی در حسابیکس', 'hesabix-v2'); ?></th>
				<td>
					<label style="display:block;margin-bottom:8px;">
						<input type="checkbox" name="finalize_proforma_on_paid" value="1" <?php checked(!empty($sync_settings['finalize_proforma_on_paid'])); ?>>
						<?php _e('وقتی سفارش در ووکامرس «پرداخت‌شده» شد، در همگام بعدی به‌صورت فاکتور قطعی به‌روزرسانی شود (هوک woocommerce_payment_complete؛ بدون نیاز به تیک «ارسال فاکتور: پس از پرداخت»)', 'hesabix-v2'); ?>
					</label>
					<p class="description" style="margin:8px 0 6px;"><?php _e('یا وقتی وضعیت سفارش به یکی از این موارد رسید تا با همگام‌سازی مجدد، فاکتور قطعی به حسابیکس فرستاده شود (حتی اگر آن وضعیت در لیست بالای «ارسال با تغییر وضعیت» انتخاب نشده باشد):', 'hesabix-v2'); ?></p>
					<fieldset style="max-height:220px;overflow:auto;border:1px solid #ccd0d4;padding:8px;">
						<?php
						$fp_sel = isset($sync_settings['finalize_proforma_order_statuses']) && is_array($sync_settings['finalize_proforma_order_statuses'])
							? $sync_settings['finalize_proforma_order_statuses']
							: array();
						foreach ($wc_status_choices as $slug => $label) :
							?>
							<label style="display:block;margin:4px 0;">
								<input type="checkbox" name="finalize_proforma_order_statuses[]" value="<?php echo esc_attr($slug); ?>"
									<?php checked(in_array($slug, $fp_sel, true)); ?>>
								<?php echo esc_html($label); ?>
								<code style="font-size:11px;">(<?php echo esc_html($slug); ?>)</code>
							</label>
						<?php endforeach; ?>
					</fieldset>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('برچسب «منبع فروش»', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="invoice_tag_website_enabled" value="1" <?php checked(!empty($sync_settings['invoice_tag_website_enabled'])); ?>>
						<?php _e('اختصاص برچسب با نام زیر (در صورت نبود، در حسابیکس ساخته می‌شود)', 'hesabix-v2'); ?>
					</label>
					<p>
						<input type="text" name="invoice_tag_website_name" class="regular-text" value="<?php echo esc_attr($sync_settings['invoice_tag_website_name']); ?>">
					</p>
					<p class="description"><?php _e('پیش‌فرض «فروش سایت» با برچسب‌های اولیه حسابیکس هم‌خوان است؛ می‌توانید مثلاً «وب سایت» بگذارید.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('شناسه برچسب‌های اضافی', 'hesabix-v2'); ?></th>
				<td>
					<select name="invoice_extra_tag_ids[]" id="hesabix_v2_invoice_extra_tag_select" multiple size="8" class="regular-text hesabix-v2-invoice-extra-tags-select" dir="ltr" style="min-width:min(420px,100%);display:block;max-width:100%;"></select>
					<button type="button" id="hesabix_v2_load_invoice_tags" class="button button-secondary" style="margin-top:8px;"><?php _e('بارگذاری فهرست برچسب‌ها از حسابیکس', 'hesabix-v2'); ?></button>
					<span id="hesabix_v2_invoice_tags_status" class="description hesabix-v2-invoice-tags-status" style="margin-right:8px;" aria-live="polite"></span>
					<p class="description"><?php _e('پس از بارگذاری، برچسب‌های حسابیکس در لیست نمایش داده می‌شوند؛ موارد دلخواه را انتخاب کنید (در ویندوز و لینوکس Ctrl، در مک ⌘ برای چند انتخاب). مقادیر ذخیره‌شده با بارگذاری خودکار صفحه اعمال می‌شوند.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('ثبت هزینه حمل ووکامرس', 'hesabix-v2'); ?></th>
				<td>
					<label style="display:block;margin-bottom:6px;">
						<input type="radio" name="shipping_line_mode" value="service" <?php checked(($sync_settings['shipping_line_mode'] ?? 'service'), 'service'); ?>>
						<?php _e('به‌عنوان خدمت در خطوط فاکتور (رفتار فعلی)', 'hesabix-v2'); ?>
					</label>
					<label style="display:block;margin-bottom:8px;">
						<input type="radio" name="shipping_line_mode" value="account_adjustment" <?php checked(($sync_settings['shipping_line_mode'] ?? 'service'), 'account_adjustment'); ?>>
						<?php _e('به‌عنوان ردیف حساب درآمد حمل، خارج از محاسبه سود فاکتور', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('در حالت ردیف حساب، مبلغ حمل به جمع و سند حسابداری فاکتور اضافه می‌شود اما در گزارش سود فاکتور به‌عنوان سود کالا/خدمت محاسبه نمی‌گردد.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr class="hesabix-v2-shipping-account-row">
				<th scope="row"><?php _e('حساب درآمد حمل', 'hesabix-v2'); ?></th>
				<td>
					<select name="shipping_adjustment_account_id" id="hesabix_v2_shipping_adjustment_account_id" class="regular-text">
						<option value="0"><?php _e('— انتخاب حساب —', 'hesabix-v2'); ?></option>
						<?php if ($saved_shipping_adjustment_account_id > 0) : ?>
							<option value="<?php echo esc_attr((string) $saved_shipping_adjustment_account_id); ?>" selected><?php echo esc_html(sprintf(__('حساب ذخیره‌شده #%d', 'hesabix-v2'), $saved_shipping_adjustment_account_id)); ?></option>
						<?php endif; ?>
					</select>
					<button type="button" id="hesabix_v2_load_shipping_accounts" class="button button-secondary" style="margin-right:8px;"><?php _e('بارگذاری حساب‌ها از حسابیکس', 'hesabix-v2'); ?></button>
					<span id="hesabix_v2_shipping_account_status" class="description" style="margin-right:8px;" aria-live="polite"></span>
					<p class="description"><?php _e('پیشنهاد پیش‌فرض حساب «60104 — درآمد حمل کالا» است. اگر حساب انتخاب نشود، افزونه هنگام همگام‌سازی تلاش می‌کند همین حساب را از چارت حساب‌ها پیدا کند.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('ارز فاکتور (حسابیکس)', 'hesabix-v2'); ?></th>
				<td>
					<select name="hesabix_v2_currency_id" id="hesabix_v2_currency_id" class="regular-text">
						<option value="0" <?php selected($saved_currency_id, 0); ?>><?php _e('ارز پیش‌فرض کسب‌وکار در حسابیکس', 'hesabix-v2'); ?></option>
					</select>
					<p class="description"><?php _e('لیست از حسابیکس بارگذاری می‌شود (همراه انبار و بانک). اگر ارز فروشگاه ووکامرس با ارز انتخاب‌شده یکی نباشد — به‌جز جفت تومان/ریال طبق تنظیمات — همگام‌سازی متوقف می‌شود.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('انبار پیش‌فرض', 'hesabix-v2'); ?></th>
				<td>
					<select name="hesabix_v2_default_warehouse_id" id="hesabix_v2_default_warehouse_id" class="regular-text">
						<option value=""><?php _e('— انتخاب انبار —', 'hesabix-v2'); ?></option>
					</select>
					<button type="button" id="hesabix_v2_load_warehouses_banks" class="button button-secondary" style="margin-right: 8px;"><?php _e('بارگذاری از حسابیکس', 'hesabix-v2'); ?></button>
					<span id="hesabix_v2_wh_bank_status" class="description"></span>
					<p class="description"><?php _e('برای خروج از انبار در فاکتور فروش. هنگام باز شدن این صفه لیست از حسابیکس بارگذاری می‌شود؛ در صورت نیاز دکمه را دوباره بزنید.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('انبار در خطوط فاکتور فروش', 'hesabix-v2'); ?></th>
				<td>
					<label style="display:inline-flex;align-items:center;gap:6px;margin-right:16px;">
						<input type="radio" name="invoice_wh_resolution" value="default" <?php checked($inv_wh_cfg['resolution'], 'default'); ?>>
						<?php _e('همیشه انبار پیش‌فرض (بالا)', 'hesabix-v2'); ?>
					</label>
					<label style="display:inline-flex;align-items:center;gap:6px;">
						<input type="radio" name="invoice_wh_resolution" value="rules" <?php checked($inv_wh_cfg['resolution'], 'rules'); ?>>
						<?php _e('اولویت طبق جدول (روش حمل، سپس منطقه ارسال، سپس پیش‌فرض)', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('برای هر سفارش یک انبار واحد برای تمام اقلام فاکتور انتخاب می‌شود. قوانین به‌ترتیب از بالا به پایین ارزیابی می‌شوند؛ اولین تطبیق برنده است. شناسه منطقه را از فروشگاه ووکامرس ← تنظیمات ← حمل‌ونقل ببینید (۱، ۲، …؛ «مکان‌های تحت پوشش» معمولاً ۰). کمبوی انبار با همان بارگذاری «انبار و بانک» از حسابیکس پر می‌شود.', 'hesabix-v2'); ?></p>
					<table id="hesabix_v2_inv_wh_rules_table" class="widefat striped" style="max-width:720px;margin-top:10px;">
						<thead>
							<tr>
								<th><?php _e('نوع', 'hesabix-v2'); ?></th>
								<th><?php _e('کلید', 'hesabix-v2'); ?></th>
								<th><?php _e('انبار (حسابیکس)', 'hesabix-v2'); ?></th>
							</tr>
						</thead>
						<tbody>
							<?php
							for ($rii = 0; $rii < 12; $rii++) :
								$rr = isset($inv_wh_cfg['rules'][ $rii ]) ? $inv_wh_cfg['rules'][ $rii ] : array();
								$r_type = isset($rr['type']) ? $rr['type'] : '';
								$r_key = isset($rr['key']) ? $rr['key'] : '';
								?>
								<tr>
									<td>
										<select name="inv_wh_r_type[]">
											<option value=""><?php _e('—', 'hesabix-v2'); ?></option>
											<option value="shipping_method" <?php selected($r_type, 'shipping_method'); ?>><?php _e('روش حمل', 'hesabix-v2'); ?></option>
											<option value="shipping_zone" <?php selected($r_type, 'shipping_zone'); ?>><?php _e('منطقه ارسال', 'hesabix-v2'); ?></option>
										</select>
									</td>
									<td>
										<input type="text" name="inv_wh_r_key[]" class="regular-text" dir="ltr" style="max-width:100%;"
											value="<?php echo esc_attr($r_key); ?>"
											placeholder="<?php echo esc_attr__('flat_rate:12 یا 2', 'hesabix-v2'); ?>">
									</td>
									<td>
										<select name="inv_wh_r_wid[]" class="hesabix-v2-inv-wh-select regular-text" style="max-width:220px;">
											<option value=""><?php _e('— انتخاب —', 'hesabix-v2'); ?></option>
										</select>
									</td>
								</tr>
								<?php
							endfor;
							?>
						</tbody>
					</table>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('کشش موجودی به ووکامرس', 'hesabix-v2'); ?></th>
				<td>
					<label style="display:block;margin-bottom:8px;">
						<input type="checkbox" name="stock_pull_enabled" value="1" <?php checked(!empty($stock_pull_opts['enabled'])); ?>>
						<?php _e('زمان‌بندی خودکار از حسابیکس (Cron وردپرس)', 'hesabix-v2'); ?>
					</label>
					<p class="description" style="margin-bottom:12px;">
						<?php _e('موجودی قابل‌فروش ووکامرس از گزارش انبار حسابیکس محاسبه و روی هر محصول متصل به‌روز می‌شود. نیاز به دسترسی گزارش (reports.view) برای کلید API دارد. جمع از چند انبار طبق حالت زیر خواهد بود.', 'hesabix-v2'); ?>
					</p>
					<label style="display:inline-flex;align-items:center;gap:6px;margin-right:16px;margin-bottom:6px;">
						<input type="radio" name="stock_pull_warehouse_scope" value="default" <?php checked($stock_pull_opts['warehouse_scope'], 'default'); ?>>
						<?php _e('فقط انبار پیش‌فرض (بالا)', 'hesabix-v2'); ?>
					</label>
					<label style="display:inline-flex;align-items:center;gap:6px;margin-right:16px;margin-bottom:6px;">
						<input type="radio" name="stock_pull_warehouse_scope" value="selected" <?php checked($stock_pull_opts['warehouse_scope'], 'selected'); ?>>
						<?php _e('انبارهای انتخابی (جمع موجودی)', 'hesabix-v2'); ?>
					</label>
					<label style="display:inline-flex;align-items:center;gap:6px;margin-bottom:6px;">
						<input type="radio" name="stock_pull_warehouse_scope" value="all" <?php checked($stock_pull_opts['warehouse_scope'], 'all'); ?>>
						<?php _e('همه انبارها (جمع)', 'hesabix-v2'); ?>
					</label>
					<p style="margin:10px 0 6px;"><?php _e('انتخاب انبارها برای حالت «انبارهای انتخابی»:', 'hesabix-v2'); ?></p>
					<select name="stock_pull_warehouse_ids[]" id="hesabix_v2_stock_pull_wh_select" multiple size="6" style="min-width:280px;display:block;"></select>
					<p class="description"><?php _e('پس از «بارگذاری از حسابیکس»، این لیست پر می‌شود (Ctrl برای چند انتخاب).', 'hesabix-v2'); ?></p>
					<p style="margin-top:12px;">
						<label>
							<?php _e('فاصله اجرای Cron (دقیقه)', 'hesabix-v2'); ?>
							<input type="number" name="stock_pull_cron_minutes" min="5" max="180" step="1" style="width:5em;margin-right:8px;"
								value="<?php echo esc_attr((string) (int) $stock_pull_opts['cron_minutes']); ?>">
						</label>
					</p>
					<label style="display:block;margin:10px 0;">
						<input type="checkbox" name="stock_pull_force_manage_stock" value="1" <?php checked(!empty($stock_pull_opts['force_manage_stock'])); ?>>
						<?php _e('روشن کردن «مدیریت موجودی» در ووکامرس هنگام به‌روزرسانی', 'hesabix-v2'); ?>
					</label>
					<label style="display:block;margin:10px 0;">
						<input type="checkbox" name="stock_pull_disable_wc_reduce" value="1" <?php checked(!empty($stock_pull_opts['disable_wc_stock_reduction'])); ?>>
						<?php _e('کاهش خودکار موجودی ووکامرس هنگام سفارش را غیرفعال کن تا با خروج انبار حسابیکس تداخل نداشته باشد؛ بعد از هر سفارش تا اجرای «کشش موجودی» ممکن است عدد ویترین عقب بمانَد.', 'hesabix-v2'); ?>
					</label>
					<p>
						<button type="button" class="button" id="hesabix_v2_stock_pull_now_btn"><?php _e('اجرا هم‌اکنون', 'hesabix-v2'); ?></button>
						<span id="hesabix_v2_stock_pull_now_status" class="description" style="margin-right:12px;"></span>
					</p>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('ثبت پرداخت فاکتور در', 'hesabix-v2'); ?></th>
				<td>
					<label style="display:block;margin-bottom:6px;">
						<input type="radio" name="hesabix_v2_invoice_payment_destination" value="bank" <?php checked($invoice_payment_destination, 'bank'); ?>>
						<?php _e('حساب بانکی', 'hesabix-v2'); ?>
					</label>
					<label style="display:block;">
						<input type="radio" name="hesabix_v2_invoice_payment_destination" value="cash_register" <?php checked($invoice_payment_destination, 'cash_register'); ?>>
						<?php _e('صندوق', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('برای سفارش‌های پرداخت‌شده، سند دریافت در حسابیکس به این مقصد ثبت می‌شود (فاکتور غیر پیش‌فاکتور). حساب انتخاب‌شده باید با ارز فاکتور هم‌خوان باشد.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr class="hesabix-v2-pay-row hesabix-v2-pay-bank">
				<th scope="row"><?php _e('حساب بانکی پیش‌فرض', 'hesabix-v2'); ?></th>
				<td>
					<select name="hesabix_v2_default_bank_id" id="hesabix_v2_default_bank_id" class="regular-text">
						<option value=""><?php _e('— انتخاب حساب بانکی —', 'hesabix-v2'); ?></option>
					</select>
				</td>
			</tr>
			<tr class="hesabix-v2-pay-row hesabix-v2-pay-cash">
				<th scope="row"><?php _e('صندوق پیش‌فرض', 'hesabix-v2'); ?></th>
				<td>
					<select name="hesabix_v2_default_cash_register_id" id="hesabix_v2_default_cash_register_id" class="regular-text">
						<option value=""><?php _e('— انتخاب صندوق —', 'hesabix-v2'); ?></option>
					</select>
				</td>
			</tr>
		</table>
		<script>
		(function($){
			var savedWarehouse = '<?php echo esc_js((string) get_option('hesabix_v2_default_warehouse_id', '')); ?>';
			var savedBank = '<?php echo esc_js((string) get_option('hesabix_v2_default_bank_id', '')); ?>';
			var savedCashRegister = '<?php echo esc_js((string) $saved_cash_register_id); ?>';
			var savedCurrency = '<?php echo esc_js((string) $saved_currency_id); ?>';
			var savedShippingAdjustmentAccountId = <?php echo (int) $saved_shipping_adjustment_account_id; ?>;
			var savedStockPullWhIds = <?php echo wp_json_encode(array_values(array_map('intval', isset($stock_pull_opts['warehouse_ids']) ? $stock_pull_opts['warehouse_ids'] : array()))); ?>;
			var savedInvoiceWhRuleIds = <?php echo wp_json_encode(array_map('intval', $inv_wh_saved_wids)); ?>;
			var savedInvoiceExtraTagIds = <?php echo wp_json_encode(array_values(array_map('intval', $saved_invoice_extra_tag_ids))); ?>;
			var invoiceTagOrphanSuffix = <?php echo wp_json_encode(__('(ذخیره‌شده)', 'hesabix-v2')); ?>;

			function hesabixV2FillInvoiceWarehouseRuleSelects(warehouses) {
				var warehousesList = warehouses || [];
				var pickLabelEmpty = <?php echo wp_json_encode(__('— انتخاب —', 'hesabix-v2')); ?>;
				$('#hesabix_v2_inv_wh_rules_table .hesabix-v2-inv-wh-select').each(function(index){
					var $sel = $(this);
					var prev = $sel.val();
					var fallback = '';
					if (savedInvoiceWhRuleIds && typeof savedInvoiceWhRuleIds[index] !== 'undefined' && savedInvoiceWhRuleIds[index] > 0) {
						fallback = String(savedInvoiceWhRuleIds[index]);
					}
					$sel.empty().append($('<option></option>').val('').text(pickLabelEmpty));
					warehousesList.forEach(function(w){
						var lbl = (w.code ? String(w.code) + ' — ' : '') + (w.name || String(w.id));
						$sel.append($('<option></option>').val(String(w.id)).text(lbl));
					});
					var desired = prev || fallback;
					if (desired !== '') {
						$sel.val(desired);
					}
				});
			}

			function hesabixV2TogglePaymentRows() {
				var v = $('input[name="hesabix_v2_invoice_payment_destination"]:checked').val();
				$('.hesabix-v2-pay-bank').toggle(v === 'bank');
				$('.hesabix-v2-pay-cash').toggle(v === 'cash_register');
			}
			$('input[name="hesabix_v2_invoice_payment_destination"]').on('change', hesabixV2TogglePaymentRows);
			hesabixV2TogglePaymentRows();

			function hesabixV2ToggleShippingAccountRow() {
				var mode = $('input[name="shipping_line_mode"]:checked').val() || 'service';
				$('.hesabix-v2-shipping-account-row').toggle(mode === 'account_adjustment');
			}
			$('input[name="shipping_line_mode"]').on('change', hesabixV2ToggleShippingAccountRow);
			hesabixV2ToggleShippingAccountRow();

			function hesabixV2FillShippingAccountSelect(accounts) {
				var $sel = $('#hesabix_v2_shipping_adjustment_account_id');
				if (!$sel.length) {
					return;
				}
				var keep = $sel.val();
				var desired = (keep && keep !== '0') ? keep : (savedShippingAdjustmentAccountId > 0 ? String(savedShippingAdjustmentAccountId) : '');
				$sel.empty().append($('<option></option>').val('0').text('<?php echo esc_js(__('— انتخاب حساب —', 'hesabix-v2')); ?>'));
				(accounts || []).forEach(function(a){
					if (!a || !a.id) {
						return;
					}
					var label = a.label || (((a.code || '') ? String(a.code) + ' — ' : '') + (a.name || String(a.id)));
					var $opt = $('<option></option>').val(String(a.id)).text(label);
					if (a.code) {
						$opt.attr('data-code', String(a.code));
					}
					$sel.append($opt);
				});
				if (desired !== '') {
					$sel.val(desired);
				}
				if (($sel.val() === null || $sel.val() === '0') && !desired) {
					var $default = $sel.find('option[data-code="60104"]').first();
					if ($default.length) {
						$sel.val($default.val());
					}
				}
				if (desired !== '' && ($sel.val() === null || $sel.val() === '0')) {
					$sel.append($('<option></option>').val(desired).text(desired + ' — ' + invoiceTagOrphanSuffix).prop('selected', true));
				}
			}

			function hesabixV2LoadShippingAccounts(isAuto) {
				var $btn = $('#hesabix_v2_load_shipping_accounts');
				var $st = $('#hesabix_v2_shipping_account_status');
				if (!$btn.length) {
					return;
				}
				if (!isAuto) {
					$btn.prop('disabled', true);
					$st.text('<?php echo esc_js(__('در حال بارگذاری...', 'hesabix-v2')); ?>').css('color', '');
				}
				$.post(hesabix_v2_ajax.ajax_url, {
					action: 'hesabix_v2_opening_inventory_accounts',
					nonce: hesabix_v2_ajax.nonce
				}).done(function(res){
					var accounts = (res && res.success && res.data && res.data.accounts) ? res.data.accounts : [];
					hesabixV2FillShippingAccountSelect(accounts);
					if (!isAuto) {
						$st.text(accounts.length ? '<?php echo esc_js(__('بارگذاری شد.', 'hesabix-v2')); ?>' : '<?php echo esc_js(__('حسابی برنگشت.', 'hesabix-v2')); ?>').css('color', accounts.length ? 'green' : 'red');
					}
				}).fail(function(){
					if (!isAuto) {
						$st.text('<?php echo esc_js(__('خطا در ارتباط با سرور', 'hesabix-v2')); ?>').css('color', 'red');
					}
				}).always(function(){
					if (!isAuto) {
						$btn.prop('disabled', false);
					}
				});
			}

			$('#hesabix_v2_load_shipping_accounts').on('click', function(){
				hesabixV2LoadShippingAccounts(false);
			});

			function hesabixV2LoadWarehousesBanksCurrencies(isAuto) {
				var $btn = $('#hesabix_v2_load_warehouses_banks');
				var $status = $('#hesabix_v2_wh_bank_status');
				if (!isAuto) {
					$btn.prop('disabled', true);
				}
				if (!isAuto) {
					$status.text('<?php echo esc_js(__('در حال بارگذاری...', 'hesabix-v2')); ?>');
				}
				$.post(hesabix_v2_ajax.ajax_url, {
					action: 'hesabix_v2_get_warehouses_and_banks',
					nonce: hesabix_v2_ajax.nonce
				}).done(function(res){
					if (res.success) {
						var $wh = $('#hesabix_v2_default_warehouse_id');
						$wh.find('option:not(:first)').remove();
						(res.warehouses || []).forEach(function(w){
							$wh.append($('<option></option>').val(String(w.id)).text((w.code ? w.code + ' - ' : '') + w.name));
						});
						if (savedWarehouse !== '') {
							$wh.val(String(savedWarehouse));
						}
						var $spwh = $('#hesabix_v2_stock_pull_wh_select');
						if ($spwh.length) {
							$spwh.empty();
							(res.warehouses || []).forEach(function(w){
								var label = (w.code ? w.code + ' - ' : '') + w.name;
								$spwh.append($('<option></option>').val(String(w.id)).text(label));
							});
							if (savedStockPullWhIds && savedStockPullWhIds.length) {
								savedStockPullWhIds.forEach(function(id){
									$spwh.find('option[value="' + String(id) + '"]').prop('selected', true);
								});
							}
						}
						hesabixV2FillInvoiceWarehouseRuleSelects(res.warehouses || []);

						var $bank = $('#hesabix_v2_default_bank_id');
						$bank.find('option:not(:first)').remove();
						(res.banks || []).forEach(function(b){
							$bank.append($('<option></option>').val(String(b.id)).text((b.code ? b.code + ' - ' : '') + b.name));
						});
						if (savedBank !== '') {
							$bank.val(String(savedBank));
						}
						var $cash = $('#hesabix_v2_default_cash_register_id');
						$cash.find('option:not(:first)').remove();
						(res.cash_registers || []).forEach(function(c){
							$cash.append($('<option></option>').val(String(c.id)).text((c.code ? c.code + ' - ' : '') + c.name));
						});
						if (savedCashRegister !== '') {
							$cash.val(String(savedCashRegister));
						}
						var $cur = $('#hesabix_v2_currency_id');
						var $keep = $cur.find('option[value="0"]');
						$cur.find('option').not($keep).remove();
						(res.currencies || []).forEach(function(c){
							var label = (c.code ? c.code + ' — ' : '') + (c.title || '');
							if (c.is_default) {
								label += ' <?php echo esc_js(__('(پیش‌فرض کسب‌وکار)', 'hesabix-v2')); ?>';
							}
							$cur.append($('<option></option>').val(String(c.id)).text(label));
						});
						if (savedCurrency !== '' && savedCurrency !== '0') {
							$cur.val(String(savedCurrency));
						}
						if (!isAuto) {
							$status.text('<?php echo esc_js(__('بارگذاری شد.', 'hesabix-v2')); ?>').css('color', 'green');
						}
					} else {
						$status.text(res.message || '<?php echo esc_js(__('خطا در بارگذاری', 'hesabix-v2')); ?>').css('color', 'red');
					}
				}).fail(function(){
					$status.text('<?php echo esc_js(__('خطا در ارتباط با سرور', 'hesabix-v2')); ?>').css('color', 'red');
				}).always(function(){
					if (!isAuto) {
						$btn.prop('disabled', false);
					}
				});
			}

			$('#hesabix_v2_load_warehouses_banks').on('click', function(){
				hesabixV2LoadWarehousesBanksCurrencies(false);
			});

			$(function(){
				hesabixV2LoadWarehousesBanksCurrencies(true);
				hesabixV2LoadShippingAccounts(true);
			});

			$('#hesabix_v2_stock_pull_now_btn').on('click', function(){
				var $btn = $(this);
				var $st = $('#hesabix_v2_stock_pull_now_status');
				$btn.prop('disabled', true);
				$st.text('<?php echo esc_js(__('در حال به‌روزرسانی موجودی...', 'hesabix-v2')); ?>').css('color', '');
				$.post(hesabix_v2_ajax.ajax_url, {
					action: 'hesabix_v2_pull_stock_now',
					nonce: hesabix_v2_ajax.nonce
				}).done(function(res){
					if (res && res.success) {
						$st.text(res.message || '<?php echo esc_js(__('انجام شد.', 'hesabix-v2')); ?>').css('color', 'green');
					} else {
						$st.text((res && res.message) ? res.message : '<?php echo esc_js(__('خطا', 'hesabix-v2')); ?>').css('color', 'red');
					}
				}).fail(function(){
					$st.text('<?php echo esc_js(__('خطا در ارتباط با سرور', 'hesabix-v2')); ?>').css('color', 'red');
				}).always(function(){
					$btn.prop('disabled', false);
				});
			});

			function hesabixV2SeedInvoiceExtraTagSelectPlaceholder() {
				var $sel = $('#hesabix_v2_invoice_extra_tag_select');
				if (!$sel.length) {
					return;
				}
				$sel.empty();
				(savedInvoiceExtraTagIds || []).forEach(function(id){
					id = parseInt(id, 10);
					if (!id || id < 1) {
						return;
					}
					var sid = String(id);
					$sel.append($('<option></option>').val(sid).text(sid + ' — ' + invoiceTagOrphanSuffix).prop('selected', true));
				});
			}

			function hesabixV2ApplyInvoiceExtraTagSelection($sel, desiredList) {
				var want = {};
				(desiredList || []).forEach(function(v){ want[String(v)] = true; });
				$sel.find('option').each(function(){
					var v = $(this).val();
					$(this).prop('selected', !!(v !== '' && want[v]));
				});
			}

			function hesabixV2LoadInvoiceTags(isAuto) {
				var $btn = $('#hesabix_v2_load_invoice_tags');
				var $sel = $('#hesabix_v2_invoice_extra_tag_select');
				var $st = $('#hesabix_v2_invoice_tags_status');
				if (!$sel.length) {
					return;
				}
				var cv = $sel.val();
				var prevSel = (cv && $.isArray(cv) && cv.length) ? cv.map(String) : (savedInvoiceExtraTagIds || []).map(String);

				if (!isAuto) {
					$btn.prop('disabled', true);
				}
				if ($st.length && isAuto) {
					$st.text('');
				}
				if (!isAuto) {
					$st.text('<?php echo esc_js(__('در حال بارگذاری...', 'hesabix-v2')); ?>').css('color', '');
				}

				$.post(hesabix_v2_ajax.ajax_url, {
					action: 'hesabix_v2_get_invoice_tags',
					nonce: hesabix_v2_ajax.nonce
				}).done(function(res){
					var tags = (res.success && res.tags && res.tags.length) ? res.tags : [];

					var byRemote = {};
					tags.forEach(function(t){ byRemote[String(t.id)] = t; });

					$sel.empty();
					tags.forEach(function(t){
						var sid = String(t.id);
						var label = sid + ' — ' + (t.name || '');
						$sel.append($('<option></option>').val(sid).text(label));
					});

					prevSel.forEach(function(s){
						var id = parseInt(s, 10);
						if (!id || id < 1 || byRemote[String(id)]) {
							return;
						}
						var sid = String(id);
						$sel.append($('<option></option>').val(sid).text(sid + ' — ' + invoiceTagOrphanSuffix));
					});

					if (!$sel.find('option').length) {
						var msg = '';
						if (res.success && (!tags || !tags.length)) {
							msg = '<?php echo esc_js(__('برچسبی در حسابیکس یافت نشد.', 'hesabix-v2')); ?>';
						} else {
							msg = (res.message && String(res.message)) ? String(res.message) : '<?php echo esc_js(__('دریافت برچسب‌ها ناموفق بود.', 'hesabix-v2')); ?>';
						}
						if ($st.length && !(isAuto && savedInvoiceExtraTagIds && savedInvoiceExtraTagIds.length && !tags.length)) {
							$st.text(msg).css('color', 'red');
						}
					}

					hesabixV2ApplyInvoiceExtraTagSelection($sel, prevSel);

					if ($st.length) {
						if (tags.length) {
							$st.css('color', '').text('<?php echo esc_js(__('فهرست به‌روز شد.', 'hesabix-v2')); ?>');
						} else if (isAuto && savedInvoiceExtraTagIds && savedInvoiceExtraTagIds.length && res.success) {
							$st.css('color', '').text('<?php echo esc_js(__('شناسه‌های ذخیره‌شده نمایش داده شد؛ نام برچسب پس از دریافت موفق فهرست به‌روز می‌شود.', 'hesabix-v2')); ?>');
						}
					}
				}).fail(function(){
					hesabixV2SeedInvoiceExtraTagSelectPlaceholder();
					hesabixV2ApplyInvoiceExtraTagSelection($sel, prevSel);
					if (!isAuto && $st.length) {
						$st.text('<?php echo esc_js(__('خطا در ارتباط با سرور', 'hesabix-v2')); ?>').css('color', 'red');
					}
				}).always(function(){
					if (!$btn.length) {
						return;
					}
					if (!isAuto) {
						$btn.prop('disabled', false);
					}
				});
			}

			hesabixV2SeedInvoiceExtraTagSelectPlaceholder();
			$(function(){
				hesabixV2LoadInvoiceTags(true);
			});
			$('#hesabix_v2_load_invoice_tags').on('click', function(){ hesabixV2LoadInvoiceTags(false); });
		})(jQuery);
		</script>
		</div>

		<div class="hesabix-v2-tab-panel" data-tab="opening_inv" hidden>
			<h2 class="screen-reader-text"><?php esc_html_e('موجودی افتتاحیه ووکامرس در حسابیکس', 'hesabix-v2'); ?></h2>
			<?php if ($ob_inv_done) : ?>
				<div class="notice notice-success inline"><p><?php esc_html_e('ثبت موجودی اولیه از ووکامرس به تراز افتتاحیه یک‌بار با موفقیت انجام شده است. این بخش غیرفعال است.', 'hesabix-v2'); ?></p></div>
			<?php elseif (!get_option('hesabix_v2_enabled')) : ?>
				<div class="notice notice-warning inline"><p><?php esc_html_e('ابتدا افزونه را فعال و متصل کنید.', 'hesabix-v2'); ?></p></div>
			<?php else : ?>
				<p class="description" style="max-width:50rem;">
					<?php esc_html_e('کالاهای منتشرشده با مدیریت موجودی و تعداد › ۰ به‌صورت دسته‌ای در حسابیکس همگام، سپس در «تراز افتتاحیه» سال مالی جاری ادغام می‌شوند. قبل از اجرا گزینه‌ها را ذخیره کنید و دسترسی API به opening_balance و chart_of_accounts را بررسی کنید.', 'hesabix-v2'); ?>
				</p>
				<div id="hesabix-v2-obinv-initial" hidden
					data-inventory-id="<?php echo esc_attr((string) (int) $ob_inv_prefs['inventory_account_id']); ?>"
					data-equity-id="<?php echo esc_attr((string) (int) $ob_inv_prefs['equity_account_id']); ?>"></div>
				<table class="form-table" id="hesabix-v2-opening-inv-form">
					<tr>
						<th scope="row"><?php esc_html_e('مالیات در بهای واحد', 'hesabix-v2'); ?></th>
						<td>
							<label>
								<input type="checkbox" name="ob_inv_include_tax" id="ob_inv_include_tax" value="1" <?php checked(!empty($ob_inv_prefs['include_tax'])); ?>>
								<?php esc_html_e('بله — مالیات بر ارزش افزوده (در صورت تنظیم در ووکامرس) در بهای واحد ارزش‌گذاری موجودی لحاظ شود؛ در غیر این صورت بهای خالص (بدون مالیات) استفاده می‌شود.', 'hesabix-v2'); ?>
							</label>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e('مبنای بهای تمام‌شده', 'hesabix-v2'); ?></th>
						<td>
							<select name="ob_inv_cost_basis" id="ob_inv_cost_basis">
								<option value="regular" <?php selected($ob_inv_prefs['cost_basis'], 'regular'); ?>><?php esc_html_e('قیمت اصلی (یا قیمت فروش در صورت خالی بودن اصلی)', 'hesabix-v2'); ?></option>
								<option value="sale" <?php selected($ob_inv_prefs['cost_basis'], 'sale'); ?>><?php esc_html_e('قیمت فروش جاری', 'hesabix-v2'); ?></option>
								<option value="zero" <?php selected($ob_inv_prefs['cost_basis'], 'zero'); ?>><?php esc_html_e('صفر — فقط تعداد (بدون بدهکار به حساب موجودی مگر تراز خودکار)', 'hesabix-v2'); ?></option>
							</select>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e('بستن خودکار تراز', 'hesabix-v2'); ?></th>
						<td>
							<label>
								<input type="checkbox" name="ob_inv_auto_balance" id="ob_inv_auto_balance" value="1" <?php checked(!empty($ob_inv_prefs['auto_balance_to_equity'])); ?>>
								<?php esc_html_e('اختلاف بدهکار/بستانکار تراز افتتاحیه به‌صورت خودکار به حساب حقوق صاحبان سهام بسته شود.', 'hesabix-v2'); ?>
							</label>
						</td>
					</tr>
					<tr class="hesabix-v2-obinv-equity-row">
						<th scope="row"><?php esc_html_e('حساب حقوق صاحبان سهام', 'hesabix-v2'); ?></th>
						<td>
							<select name="ob_inv_equity_account_id" id="ob_inv_equity_account_id" class="regular-text hesabix-v2-obinv-accounts">
								<option value="0"><?php esc_html_e('— انتخاب —', 'hesabix-v2'); ?></option>
							</select>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e('حساب موجودی کالا', 'hesabix-v2'); ?></th>
						<td>
							<select name="ob_inv_inventory_account_id" id="ob_inv_inventory_account_id" class="regular-text hesabix-v2-obinv-accounts">
								<option value="0"><?php esc_html_e('— انتخاب —', 'hesabix-v2'); ?></option>
							</select>
							<button type="button" class="button" id="hesabix_v2_obinv_load_accounts"><?php esc_html_e('بارگذاری حساب‌ها از حسابیکس', 'hesabix-v2'); ?></button>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e('انبار (اختیاری)', 'hesabix-v2'); ?></th>
						<td>
							<input type="number" name="ob_inv_warehouse_override" id="ob_inv_warehouse_override" class="small-text" min="0" step="1"
								value="<?php echo esc_attr((string) (int) $ob_inv_prefs['warehouse_override']); ?>"
								placeholder="<?php esc_attr_e('۰ = انبار پیش‌فرض تب فاکتور', 'hesabix-v2'); ?>">
							<p class="description"><?php esc_html_e('در صورت ۰، همان انبار پیش‌فرض ذخیره‌شده در تب فاکتور استفاده می‌شود.', 'hesabix-v2'); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e('اندازهٔ هر دسته', 'hesabix-v2'); ?></th>
						<td>
							<input type="number" name="ob_inv_batch_size" id="ob_inv_batch_size" class="small-text" min="3" max="40" step="1"
								value="<?php echo esc_attr((string) (int) $ob_inv_prefs['batch_size']); ?>">
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e('نهایی‌سازی سند', 'hesabix-v2'); ?></th>
						<td>
							<label>
								<input type="checkbox" name="ob_inv_do_post" id="ob_inv_do_post" value="1" <?php checked(!empty($ob_inv_prefs['do_post'])); ?>>
								<?php esc_html_e('پس از ذخیرهٔ کامل، سند تراز افتتاحیه در حسابیکس نهایی (قفل) شود.', 'hesabix-v2'); ?>
							</label>
						</td>
					</tr>
				</table>
				<p>
					<button type="button" class="button button-primary" id="hesabix_v2_obinv_run" <?php disabled(!get_option('hesabix_v2_enabled')); ?>>
						<?php esc_html_e('شروع ثبت موجودی اولیه (گروهی)', 'hesabix-v2'); ?>
					</button>
					<span id="hesabix_v2_obinv_status" class="description" style="margin-right:12px;" aria-live="polite"></span>
				</p>
				<pre id="hesabix_v2_obinv_log" style="max-height:220px;overflow:auto;background:#f6f7f7;padding:10px;font-size:12px;display:none;"></pre>
			<?php endif; ?>
		</div>

		<div class="hesabix-v2-tab-panel" data-tab="extra" hidden>
			<h2 class="screen-reader-text"><?php esc_html_e('تنظیمات اضافی', 'hesabix-v2'); ?></h2>
		<table class="form-table">
			<tr>
				<th scope="row"><?php _e('فیلدهای اضافی checkout', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="add_checkout_fields" value="1" <?php checked($add_checkout_fields); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('اضافه کردن فیلد کد ملی و کد اقتصادی به صفحه تسویه حساب', 'hesabix-v2'); ?></p>
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('حالت Debug', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="debug_mode" value="1" <?php checked($debug_mode); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('ثبت جزئیات کامل API requests برای عیب‌یابی', 'hesabix-v2'); ?></p>
				</td>
			</tr>
		</table>
		</div>

		<div class="hesabix-v2-tab-panel" data-tab="update" hidden>
			<h2 class="screen-reader-text"><?php esc_html_e('به‌روزرسانی افزونه از مخزن', 'hesabix-v2'); ?></h2>
			<p class="description" style="max-width:54rem;margin-top:0;"><?php esc_html_e('نسخه از فایل hesabix-v2.php در مخزن (مسیر raw) خوانده می‌شود و بستهٔ zip همان شاخه جایگزین می‌شود. برای آدرس دلخواه، ثابت‌های HESABIX_V2_UPDATE_RAW_PHP_URL و HESABIX_V2_UPDATE_ARCHIVE_ZIP_URL را در wp-config تنظیم کنید.', 'hesabix-v2'); ?></p>
			<?php
			$upd = $hesabix_v2_upd_state;
			$upd_remote_disp = __('نامشخص', 'hesabix-v2');
			if (!empty($upd['remote_loaded']) && isset($upd['remote_version']) && (string) $upd['remote_version'] !== '') {
				$upd_remote_disp = (string) $upd['remote_version'];
			}
			$upd_summary_txt = '';
			if (empty($upd['configured'])) {
				$upd_summary_txt = __('منبع به‌روزرسانی تنظیم نشده؛ ثابت‌های فایل اصلی افزونه یا wp-config را بررسی کنید.', 'hesabix-v2');
			} elseif (empty($upd['remote_loaded'])) {
				$upd_summary_txt = __('به منبع وصل نشد یا نسخه‌ای خوانده نشد؛ «بررسی مجدد» را بزنید.', 'hesabix-v2');
			} elseif (!empty($upd['update_available'])) {
				$upd_summary_txt = __('نسخهٔ جدیدتری موجود است؛ می‌توانید با «به‌روزرسانی خودکار» از بستهٔ zip نصب کنید.', 'hesabix-v2');
			} elseif (!empty($upd['newer_than_local']) && empty($upd['env_compatible'])) {
				$upd_summary_txt = __('نسخهٔ جدید روی مخزن است؛ اما نسخهٔ وردپرس یا PHP سایت به حد لازم نمی‌رسد.', 'hesabix-v2');
			} else {
				$upd_summary_txt = __('نسخهٔ نصب‌شده با آخرین نسخهٔ تشخیص‌داده‌شده از منبع برابر است (یا از راه‌دور جدیدتر دارید).', 'hesabix-v2');
			}
			$upd_install_disabled = empty($upd['update_available']) || empty($upd['can_install']);
			$upd_requires_label = __('نامشخص', 'hesabix-v2');
			if (!empty($upd['remote_loaded'])) {
				$upd_rw = isset($upd['requires_wp']) ? (string) $upd['requires_wp'] : '';
				$upd_rp = isset($upd['requires_php']) ? (string) $upd['requires_php'] : '';
				if ('' !== $upd_rw || '' !== $upd_rp) {
					$upd_requires_label = sprintf(
						__('وردپرس ≥ %1$s؛ PHP ≥ %2$s', 'hesabix-v2'),
						'' !== $upd_rw ? $upd_rw : '—',
						'' !== $upd_rp ? $upd_rp : '—'
					);
				}
			}
			$upd_source_label = __('نامشخص', 'hesabix-v2');
			if (empty($upd['configured'])) {
				$upd_source_label = __('تنظیم نشده', 'hesabix-v2');
			} elseif (!empty($upd['configured_raw_zip'])) {
				$upd_source_label = __('فایل خام hesabix-v2.php + بستهٔ zip', 'hesabix-v2');
			} elseif (!empty($upd['configured_manifest_only'])) {
				$upd_source_label = __('مانیفست JSON', 'hesabix-v2');
			} else {
				$upd_source_label = __('ترکیبی', 'hesabix-v2');
			}
			?>
			<table class="form-table hesabix-v2-upd-versions" role="presentation">
				<tr>
					<th scope="row"><?php esc_html_e('نسخهٔ نصب‌شدهٔ فعلی', 'hesabix-v2'); ?></th>
					<td><strong id="hesabix-v2-upd-current"><?php echo esc_html((string) ($upd['current_version'] ?? '')); ?></strong></td>
				</tr>
				<tr>
					<th scope="row"><?php esc_html_e('آخرین نسخهٔ منتشرشده (از منبع)', 'hesabix-v2'); ?></th>
					<td><strong id="hesabix-v2-upd-remote"><?php echo esc_html($upd_remote_disp); ?></strong></td>
				</tr>
				<tr>
					<th scope="row"><?php esc_html_e('نوع منبع', 'hesabix-v2'); ?></th>
					<td id="hesabix-v2-upd-source"><?php echo esc_html($upd_source_label); ?></td>
				</tr>
				<tr>
					<th scope="row"><?php esc_html_e('الزامات اعلام‌شده در منبع', 'hesabix-v2'); ?></th>
					<td id="hesabix-v2-upd-requires"><?php echo esc_html($upd_requires_label); ?></td>
				</tr>
				<tr>
					<th scope="row"><?php esc_html_e('خلاصهٔ وضعیت', 'hesabix-v2'); ?></th>
					<td id="hesabix-v2-upd-summary"><?php echo esc_html($upd_summary_txt); ?></td>
				</tr>
			</table>
			<p class="submit" style="padding-top:8px;display:flex;flex-wrap:wrap;gap:10px;align-items:center;">
				<button type="button" class="button button-secondary" id="hesabix-v2-upd-refresh"><?php esc_html_e('بررسی مجدد از سرور', 'hesabix-v2'); ?></button>
				<button type="button" class="button button-primary" id="hesabix-v2-upd-install"<?php echo $upd_install_disabled ? ' disabled aria-disabled="true"' : ''; ?>><?php esc_html_e('به‌روزرسانی خودکار (Ajax)', 'hesabix-v2'); ?></button>
				<span class="description" id="hesabix-v2-upd-inline-status" aria-live="polite" style="flex-basis:100%;"></span>
			</p>
			<p class="notice notice-alt" style="max-width:52rem;"><strong><?php esc_html_e('مجوز:', 'hesabix-v2'); ?></strong>
				<?php
				if (!empty($upd['can_install'])) {
					echo esc_html__('شما حق به‌روزرسانی این افزونه از این برگه را دارید.', 'hesabix-v2');
				} else {
					echo esc_html__('برای نصب باید «مدیریت ووکامرس» و «به‌روزرسانی افزونه‌ها» هر دو فعال باشند.', 'hesabix-v2');
				}
				?>
			</p>
			<script type="application/json" id="hesabix-v2-upd-initial-state"><?php echo wp_json_encode($upd); ?></script>
		</div>

		<div class="hesabix-v2-tab-panel" data-tab="system" hidden>
			<h2 class="screen-reader-text"><?php esc_html_e('اطلاعات سیستم', 'hesabix-v2'); ?></h2>
			<div class="hesabix-v2-sysinfo">
				<div class="hesabix-v2-sysinfo-intro">
					<div class="hesabix-v2-sysinfo-headline">
						<p style="margin:0 0 6px;"><strong><?php esc_html_e('نسخه افزونه:', 'hesabix-v2'); ?></strong> <?php echo esc_html($hsx_plugin_version ?: '—'); ?></p>
						<p style="margin:0;display:flex;align-items:center;flex-wrap:wrap;gap:8px;">
							<strong><?php esc_html_e('وضعیت اتصال:', 'hesabix-v2'); ?></strong>
							<span class="hesabix-v2-sysinfo-badge <?php echo $hsx_conn_ok ? 'connected' : 'offline'; ?>">
								<?php echo esc_html($hsx_conn_ok ? __('متصل', 'hesabix-v2') : __('قطع', 'hesabix-v2')); ?>
							</span>
						</p>
					</div>
				</div>
				<p class="description" style="margin: -4px 0 16px;"><?php esc_html_e('مقادیر زیر تنها جهت تشخیص محیط برای پشتیبانی نمایش داده می‌شود.', 'hesabix-v2'); ?></p>
				<div class="hesabix-v2-sysinfo-cards">
					<div class="hesabix-v2-sysinfo-card">
						<h3><?php esc_html_e('اطلاعات سرور', 'hesabix-v2'); ?></h3>
						<dl>
							<dt><?php esc_html_e('نسخه PHP', 'hesabix-v2'); ?></dt>
							<dd><?php echo esc_html($hsx_php_ver); ?></dd>
							<dt><?php esc_html_e('نسخه وردپرس', 'hesabix-v2'); ?></dt>
							<dd><?php echo esc_html($hsx_wp_ver); ?></dd>
							<dt><?php esc_html_e('نسخه ووکامرس', 'hesabix-v2'); ?></dt>
							<dd><?php echo esc_html($hsx_wc_ver); ?></dd>
							<dt><?php esc_html_e('نسخه MySQL', 'hesabix-v2'); ?></dt>
							<dd><?php echo esc_html($hsx_mysql_version ?: '—'); ?></dd>
						</dl>
					</div>
					<div class="hesabix-v2-sysinfo-card">
						<h3><?php esc_html_e('تنظیمات PHP (کلاینت وب)', 'hesabix-v2'); ?></h3>
						<dl>
							<dt><?php esc_html_e('حداکثر زمان اجرا', 'hesabix-v2'); ?></dt>
							<dd><?php echo esc_html($hsx_max_exec_disp); ?></dd>
							<dt><?php esc_html_e('محدودیت حافظه (ini)', 'hesabix-v2'); ?></dt>
							<dd><?php echo esc_html($mem_ini ?: '—'); ?></dd>
							<?php if ('' !== $mem_wp): ?>
								<dt><?php esc_html_e('WP_MEMORY_LIMIT', 'hesabix-v2'); ?></dt>
								<dd><?php echo esc_html($mem_wp); ?></dd>
							<?php endif; ?>
							<dt><?php esc_html_e('حداکثر آپلود', 'hesabix-v2'); ?></dt>
							<dd><?php echo esc_html($hsx_upload ?: '—'); ?></dd>
							<dt><?php esc_html_e('حداکثر POST', 'hesabix-v2'); ?></dt>
							<dd><?php echo esc_html($hsx_post ?: '—'); ?></dd>
						</dl>
					</div>
				</div>
			</div>
		</div>

		<div id="hesabix-v2-settings-save-wrap" class="hesabix-v2-settings-submit-wrap">
			<?php submit_button(__('ذخیره تنظیمات', 'hesabix-v2'), 'primary', 'hesabix_v2_save_settings'); ?>
		</div>
	</form>
</div>

