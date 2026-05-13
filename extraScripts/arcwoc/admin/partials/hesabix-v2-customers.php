<?php
/**
 * مشتریان ووکامرس و وضعیت همگام‌سازی حسابیکس
 *
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}
?>

<div class="wrap hesabix-v2-wrap hesabix-v2-customers-page">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php if (!get_option('hesabix_v2_enabled')) : ?>
		<div class="notice notice-warning"><p><?php esc_html_e('افزونه حسابیکس غیرفعال است. آن را از تنظیمات فعال کنید.', 'hesabix-v2'); ?></p></div>
	<?php endif; ?>

	<div class="hesabix-v2-card hesabix-v2-customers-help">
		<p>
			<?php esc_html_e('لیست کاربران با نقش مشتری/مشترک فروشگاه را می‌بینید. از اینجا می‌توانید هر مشتری را به شخص در حسابیکس بفرستید یا به‌روز کنید؛ اگر نگاشت از قبل موجود باشد، به‌روزرسانی می‌شود وگرنه شخص جدید ساخته می‌شود.', 'hesabix-v2'); ?>
		</p>
		<ul class="hesabix-v2-connection-notes-list" style="margin-top:8px;">
			<li><?php esc_html_e('خریدهای مهمان در این لیست نیستند؛ همگام‌سازی مهمان‌ها از مسیر سفارش انجام می‌شود.', 'hesabix-v2'); ?></li>
			<li><?php esc_html_e('در صورت ناهم‌خوانی واحد پول فروشگاه با تنظیمات ارز حسابیکس، همگام‌سازی ممکن است متوقف شود؛ پیغام خطا نشان داده می‌شود.', 'hesabix-v2'); ?></li>
		</ul>
	</div>

	<div class="hesabix-v2-customers-toolbar hesabix-v2-card" style="margin:12px 0;display:flex;flex-wrap:wrap;gap:8px;align-items:center;">
		<button type="button" class="button button-primary" id="hesabix-v2-customers-bulk-sync" <?php disabled(!get_option('hesabix_v2_enabled')); ?>>
			<?php esc_html_e('همگام‌سازی انتخاب‌شده‌ها با حسابیکس', 'hesabix-v2'); ?>
		</button>
		<span class="description" id="hesabix-v2-customers-selection-hint"><?php esc_html_e('ابتدا مشتریان را با چک‌باکس انتخاب کنید.', 'hesabix-v2'); ?></span>
	</div>
	<div id="hesabix-v2-customers-ajax-feedback" class="hesabix-v2-orders-feedback hesabix-v2-customers-feedback" aria-live="polite"></div>

	<form method="get" action="<?php echo esc_url(admin_url('admin.php')); ?>">
		<input type="hidden" name="page" value="hesabix-v2-customers" />
		<?php $list_table->prepare_items(); ?>
		<?php $list_table->search_box(__('جستجو', 'hesabix-v2'), 'hesabix-v2-customer-search'); ?>
		<?php $list_table->display(); ?>
	</form>
</div>
