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
$business_id = get_option('hesabix_v2_business_id');
$api_base_url = get_option('hesabix_v2_api_base_url', HESABIX_V2_API_BASE_URL);
$invoice_payment_destination = get_option('hesabix_v2_invoice_payment_destination', 'bank');
if ($invoice_payment_destination !== 'cash_register') {
	$invoice_payment_destination = 'bank';
}
$saved_cash_register_id = get_option('hesabix_v2_default_cash_register_id', '');
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
		</style>
		<h2 class="nav-tab-wrapper hesabix-v2-settings-tabs wp-clearfix">
			<a href="#" class="nav-tab nav-tab-active" role="tab" aria-selected="true" data-tab="connection"><?php esc_html_e('اتصال', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="sync"><?php esc_html_e('همگام‌سازی', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="invoice"><?php esc_html_e('فاکتور', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="extra"><?php esc_html_e('سایر', 'hesabix-v2'); ?></a>
			<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="update"><?php esc_html_e('به‌روزرسانی افزونه', 'hesabix-v2'); ?></a>
		</h2>

		<div class="hesabix-v2-tab-panel" data-tab="connection">
			<h2 class="screen-reader-text"><?php esc_html_e('تنظیمات اتصال', 'hesabix-v2'); ?></h2>
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
						<p class="description">
							<?php _e('Business ID:', 'hesabix-v2'); ?> <?php echo esc_html($business_id); ?><br>
							<a href="<?php echo admin_url('admin.php?page=hesabix-v2-setup'); ?>">
								<?php _e('تغییر تنظیمات اتصال', 'hesabix-v2'); ?>
							</a>
						</p>
					<?php else: ?>
						<span style="color: red;">✗ <?php _e('متصل نیست', 'hesabix-v2'); ?></span>
						<p class="description">
							<a href="<?php echo admin_url('admin.php?page=hesabix-v2-setup'); ?>">
								<?php _e('راه‌اندازی اتصال', 'hesabix-v2'); ?>
							</a>
						</p>
					<?php endif; ?>
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
				<th scope="row"><?php _e('همگام‌سازی خودکار مشتریان', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="auto_sync_customers" value="1" <?php checked($sync_settings['auto_sync_customers'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
					<p class="description"><?php _e('ثبت‌نام کاربر با نقش مشتری، ویرایش پروفایل وردپرس، و ذخیرهٔ مشتری از حساب کاربری من ووکامرس (هوک woocommerce_update_customer).', 'hesabix-v2'); ?></p>
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
		</table>
		</div>

		<div class="hesabix-v2-tab-panel" data-tab="invoice" hidden>
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
					<input type="text" name="invoice_extra_tag_ids" class="regular-text" dir="ltr"
						value="<?php echo esc_attr(isset($sync_settings['invoice_extra_tag_ids']) ? $sync_settings['invoice_extra_tag_ids'] : ''); ?>"
						placeholder="12, 34">
					<button type="button" id="hesabix_v2_load_invoice_tags" class="button button-secondary" style="margin-right:8px;"><?php _e('نمایش برچسب‌ها از حسابیکس', 'hesabix-v2'); ?></button>
					<pre id="hesabix_v2_invoice_tags_preview" style="max-height:160px;overflow:auto;background:#f6f7f7;padding:8px;font-size:12px;"></pre>
					<p class="description"><?php _e('شناسه‌های عددی را با ویرگول جدا کنید؛ برای دیدن فهرست دکمه بالا را بزنید.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr>
				<th scope="row"><?php _e('شناسه ارز پیش‌فرض', 'hesabix-v2'); ?></th>
				<td>
					<input type="number" name="hesabix_v2_currency_id" value="<?php echo esc_attr(get_option('hesabix_v2_currency_id', 1)); ?>" min="1" class="small-text">
					<p class="description"><?php _e('برای فاکتورهای ووکامرس (پیش‌فرض: 1 برای ریال)', 'hesabix-v2'); ?></p>
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
					<p class="description"><?php _e('برای خروج از انبار در فاکتور فروش. ابتدا «بارگذاری از حسابیکس» را بزنید.', 'hesabix-v2'); ?></p>
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
			var savedWarehouse = '<?php echo esc_js(get_option('hesabix_v2_default_warehouse_id', '')); ?>';
			var savedBank = '<?php echo esc_js(get_option('hesabix_v2_default_bank_id', '')); ?>';
			var savedCashRegister = '<?php echo esc_js((string) $saved_cash_register_id); ?>';

			function hesabixV2TogglePaymentRows() {
				var v = $('input[name="hesabix_v2_invoice_payment_destination"]:checked').val();
				$('.hesabix-v2-pay-bank').toggle(v === 'bank');
				$('.hesabix-v2-pay-cash').toggle(v === 'cash_register');
			}
			$('input[name="hesabix_v2_invoice_payment_destination"]').on('change', hesabixV2TogglePaymentRows);
			hesabixV2TogglePaymentRows();

			$('#hesabix_v2_load_warehouses_banks').on('click', function(){
				var $btn = $(this);
				var $status = $('#hesabix_v2_wh_bank_status');
				$btn.prop('disabled', true);
				$status.text('<?php echo esc_js(__('در حال بارگذاری...', 'hesabix-v2')); ?>');
				$.post(hesabix_v2_ajax.ajax_url, {
					action: 'hesabix_v2_get_warehouses_and_banks',
					nonce: hesabix_v2_ajax.nonce
				}).done(function(res){
					if (res.success) {
						var $wh = $('#hesabix_v2_default_warehouse_id');
						$wh.find('option:not(:first)').remove();
						(res.warehouses || []).forEach(function(w){
							$wh.append($('<option></option>').val(w.id).text((w.code ? w.code + ' - ' : '') + w.name));
						});
						if (savedWarehouse) $wh.val(savedWarehouse);
						var $bank = $('#hesabix_v2_default_bank_id');
						$bank.find('option:not(:first)').remove();
						(res.banks || []).forEach(function(b){
							$bank.append($('<option></option>').val(b.id).text((b.code ? b.code + ' - ' : '') + b.name));
						});
						if (savedBank) $bank.val(savedBank);
						var $cash = $('#hesabix_v2_default_cash_register_id');
						$cash.find('option:not(:first)').remove();
						(res.cash_registers || []).forEach(function(c){
							$cash.append($('<option></option>').val(c.id).text((c.code ? c.code + ' - ' : '') + c.name));
						});
						if (savedCashRegister) $cash.val(savedCashRegister);
						$status.text('<?php echo esc_js(__('بارگذاری شد.', 'hesabix-v2')); ?>').css('color', 'green');
					} else {
						$status.text(res.message || '<?php echo esc_js(__('خطا در بارگذاری', 'hesabix-v2')); ?>').css('color', 'red');
					}
				}).fail(function(){
					$status.text('<?php echo esc_js(__('خطا در ارتباط با سرور', 'hesabix-v2')); ?>').css('color', 'red');
				}).always(function(){
					$btn.prop('disabled', false);
				});
			});

			$('#hesabix_v2_load_invoice_tags').on('click', function(){
				var $btn = $(this);
				var $pre = $('#hesabix_v2_invoice_tags_preview');
				$btn.prop('disabled', true);
				$pre.text('<?php echo esc_js(__('در حال بارگذاری...', 'hesabix-v2')); ?>');
				$.post(hesabix_v2_ajax.ajax_url, {
					action: 'hesabix_v2_get_invoice_tags',
					nonce: hesabix_v2_ajax.nonce
				}).done(function(res){
					if (res.success && res.tags && res.tags.length) {
						var lines = res.tags.map(function(t){ return t.id + ' — ' + t.name; });
						$pre.text(lines.join("\n"));
					} else {
						$pre.text(res.message || '<?php echo esc_js(__('برچسبی برنگردید یا خطا در API', 'hesabix-v2')); ?>');
					}
				}).fail(function(){
					$pre.text('<?php echo esc_js(__('خطا در ارتباط', 'hesabix-v2')); ?>');
				}).always(function(){
					$btn.prop('disabled', false);
				});
			});
		})(jQuery);
		</script>
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

		<div class="hesabix-v2-settings-submit-wrap">
			<?php submit_button(__('ذخیره تنظیمات', 'hesabix-v2'), 'primary', 'hesabix_v2_save_settings'); ?>
		</div>
	</form>
</div>

