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

$sync_settings = get_option('hesabix_v2_sync_settings', array());
$debug_mode = get_option('hesabix_v2_debug_mode', false);
$add_checkout_fields = get_option('hesabix_v2_add_checkout_fields', false);
$api_key = get_option('hesabix_v2_api_key');
$business_id = get_option('hesabix_v2_business_id');
?>

<div class="wrap hesabix-v2-wrap">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php settings_errors('hesabix_v2_messages'); ?>

	<form method="post" action="">
		<?php wp_nonce_field('hesabix_v2_settings'); ?>

		<table class="form-table">
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
				</td>
			</tr>

			<tr>
				<th scope="row"><?php _e('ایجاد فاکتور هنگام ثبت سفارش', 'hesabix-v2'); ?></th>
				<td>
					<label>
						<input type="checkbox" name="sync_on_order_create" value="1" <?php checked($sync_settings['sync_on_order_create'] ?? false); ?>>
						<?php _e('فعال', 'hesabix-v2'); ?>
					</label>
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

