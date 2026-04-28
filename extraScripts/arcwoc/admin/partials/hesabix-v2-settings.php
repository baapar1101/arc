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
?>

<div class="wrap hesabix-v2-wrap">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php settings_errors('hesabix_v2_messages'); ?>

	<form method="post" action="">
		<?php wp_nonce_field('hesabix_v2_settings'); ?>

		<h2><?php _e('تنظیمات اتصال', 'hesabix-v2'); ?></h2>
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

		<h2><?php _e('تنظیمات همگام‌سازی', 'hesabix-v2'); ?></h2>
		
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

		<h2><?php _e('تنظیمات فاکتور', 'hesabix-v2'); ?></h2>
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
				<th scope="row"><?php _e('بانک پیش‌فرض (پرداخت)', 'hesabix-v2'); ?></th>
				<td>
					<select name="hesabix_v2_default_bank_id" id="hesabix_v2_default_bank_id" class="regular-text">
						<option value=""><?php _e('— انتخاب حساب بانکی —', 'hesabix-v2'); ?></option>
					</select>
					<p class="description"><?php _e('برای ثبت پرداخت هنگام سفارش پرداخت‌شده.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
		</table>
		<script>
		(function($){
			var savedWarehouse = '<?php echo esc_js(get_option('hesabix_v2_default_warehouse_id', '')); ?>';
			var savedBank = '<?php echo esc_js(get_option('hesabix_v2_default_bank_id', '')); ?>';
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
			$(document).ready(function(){ $('#hesabix_v2_load_warehouses_banks').trigger('click'); });

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

		<h2><?php _e('تنظیمات اضافی', 'hesabix-v2'); ?></h2>
		
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

		<?php submit_button(__('ذخیره تنظیمات', 'hesabix-v2'), 'primary', 'hesabix_v2_save_settings'); ?>
	</form>
</div>

