<?php
/**
 * فهرست سفارش‌ها — وضعیت حسابیکس، ارسال دسته‌ای، توقف همگام خودکار
 *
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}
?>

<div class="wrap hesabix-v2-wrap hesabix-v2-orders-page">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php if (!get_option('hesabix_v2_enabled')) : ?>
		<div class="notice notice-warning"><p><?php esc_html_e('افزونه حسابیکس غیرفعال است. آن را از تنظیمات فعال کنید.', 'hesabix-v2'); ?></p></div>
	<?php endif; ?>

	<div class="hesabix-v2-card hesabix-v2-orders-help">
		<p>
			<?php esc_html_e('از اینجا می‌توانید سفارش‌ها را به‌صورت دستی به حسابیکس بفرستید یا به‌روز کنید، ارسال را لغو کنید، و در صورت ویرایش دستی فاکتور در حسابیکس، همگام‌سازی خودکار ووکامرس را برای همان سفارش متوقف کنید.', 'hesabix-v2'); ?>
		</p>
		<ul class="hesabix-v2-connection-notes-list" style="margin-top:8px;">
			<li><?php esc_html_e('«توقف خودکار» فقط رویدادهای خودکار (چک‌اوت، پرداخت، تغییر وضعیت و صف پس‌زمینه) را رد می‌کند؛ دکمهٔ ارسال دستی همچنان کار می‌کند.', 'hesabix-v2'); ?></li>
			<li><?php esc_html_e('با «از سرگیری خودکار»، در چرخهٔ بعدی دوباره همان قوانین تنظیمات افزونه اعمال می‌شود؛ در صورت ویرایش دستی در حسابیکس، ممکن است دادهٔ ووکامرس فاکتور را بازنویسی کند.', 'hesabix-v2'); ?></li>
			<li><?php esc_html_e('«لغو ارسال» فاکتور را در حسابیکس حذف می‌کند (در صورت پذیرش API). اسناد جانبی بسته به قوانین حسابیکس است.', 'hesabix-v2'); ?></li>
		</ul>
	</div>

	<div class="hesabix-v2-orders-toolbar hesabix-v2-card" style="margin:12px 0;display:flex;flex-wrap:wrap;gap:8px;align-items:center;">
		<button type="button" class="button button-primary" id="hesabix-v2-bulk-sync" <?php disabled(!get_option('hesabix_v2_enabled')); ?>>
			<?php esc_html_e('ارسال / به‌روزرسانی انتخاب‌شده‌ها', 'hesabix-v2'); ?>
		</button>
		<button type="button" class="button" id="hesabix-v2-bulk-unsync" <?php disabled(!get_option('hesabix_v2_enabled')); ?>>
			<?php esc_html_e('لغو ارسال انتخاب‌شده‌ها', 'hesabix-v2'); ?>
		</button>
		<span class="description" id="hesabix-v2-orders-selection-hint"><?php esc_html_e('ابتدا سفارش‌ها را با چک‌باکس انتخاب کنید.', 'hesabix-v2'); ?></span>
	</div>
	<div id="hesabix-v2-orders-ajax-feedback" class="hesabix-v2-orders-feedback" aria-live="polite"></div>

	<form method="get" action="<?php echo esc_url(admin_url('admin.php')); ?>">
		<input type="hidden" name="page" value="hesabix-v2-orders" />
		<?php $list_table->display(); ?>
	</form>
</div>
