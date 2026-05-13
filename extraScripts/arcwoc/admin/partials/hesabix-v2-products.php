<?php
/**
 * فهرست محصولات ووکامرس و همگام‌سازی با حسابیکس
 *
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}
?>

<div class="wrap hesabix-v2-wrap hesabix-v2-products-page">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php if (!get_option('hesabix_v2_enabled')) : ?>
		<div class="notice notice-warning"><p><?php esc_html_e('افزونه حسابیکس غیرفعال است. آن را از تنظیمات فعال کنید.', 'hesabix-v2'); ?></p></div>
	<?php endif; ?>

	<div class="hesabix-v2-card hesabix-v2-products-help">
		<p>
			<?php esc_html_e('محصولات منتشرشدهٔ والد (شامل ساده و متغیر) را می‌بینید. برای هر کالا می‌توانید همگام‌سازی با حسابیکس را دستی اجرا کنید؛ برای محصول متغیر، همهٔ واریانت‌ها در یک عملیات bulk ارسال می‌شوند.', 'hesabix-v2'); ?>
		</p>
		<ul class="hesabix-v2-connection-notes-list" style="margin-top:8px;">
			<li><?php esc_html_e('فیلتر «دارای همگام‌سازی موفق» هر محصولی را نشان می‌دهد که حداقل یک ردیف نگاشت با وضعیت «همگام شده» دارد.', 'hesabix-v2'); ?></li>
			<li><?php esc_html_e('فیلتر «بدون ردیف نگاشت» محصولاتی است که هنوز هیچ ردیفی در جدول نگاشت افزونه برای آن‌ها ثبت نشده است.', 'hesabix-v2'); ?></li>
			<li><?php esc_html_e('در صورت ناهم‌خوانی واحد پول فروشگاه با ارز فاکتور حسابیکس، همگام‌سازی متوقف می‌شود؛ پیام خطا در خروجی عملیات نمایش داده می‌شود.', 'hesabix-v2'); ?></li>
		</ul>
	</div>

	<div class="hesabix-v2-products-toolbar hesabix-v2-card" style="margin:12px 0;display:flex;flex-wrap:wrap;gap:8px;align-items:center;">
		<button type="button" class="button button-primary" id="hesabix-v2-products-bulk-sync" <?php disabled(!get_option('hesabix_v2_enabled')); ?>>
			<?php esc_html_e('همگام‌سازی انتخاب‌شده‌ها با حسابیکس', 'hesabix-v2'); ?>
		</button>
		<span class="description" id="hesabix-v2-products-selection-hint"><?php esc_html_e('ابتدا محصولات را با چک‌باکس انتخاب کنید.', 'hesabix-v2'); ?></span>
	</div>
	<div id="hesabix-v2-products-ajax-feedback" class="hesabix-v2-orders-feedback hesabix-v2-products-feedback" aria-live="polite"></div>

	<form method="get" action="<?php echo esc_url(admin_url('admin.php')); ?>">
		<input type="hidden" name="page" value="hesabix-v2-products" />
		<?php $list_table->prepare_items(); ?>
		<?php $list_table->search_box(__('جستجو', 'hesabix-v2'), 'hesabix-v2-product-search'); ?>
		<?php $list_table->display(); ?>
	</form>
</div>
