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

	<div class="hesabix-v2-card hesabix-v2-orphan-cleanup" style="margin:12px 0;">
		<h2 style="margin-top:0;"><?php esc_html_e('پاک‌سازی کالاهای یتیم (والد متغیر)', 'hesabix-v2'); ?></h2>
		<p class="description">
			<?php esc_html_e('اگر قبلاً محصول متغیر به‌اشتباه به‌عنوان یک کالای ساده در حسابیکس ساخته شده، اینجا می‌توانید آن‌ها را پیدا کنید. فقط کالاهایی که در فاکتور/سند/انبار استفاده نشده‌اند حذف می‌شوند؛ در غیر این صورت فقط غیرفعال می‌شوند.', 'hesabix-v2'); ?>
		</p>
		<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:10px 0;">
			<button type="button" class="button" id="hesabix-v2-orphans-scan" <?php disabled(!get_option('hesabix_v2_enabled')); ?>>
				<?php esc_html_e('اسکن کاندیداها', 'hesabix-v2'); ?>
			</button>
			<label style="margin-inline-start:4px;">
				<input type="checkbox" id="hesabix-v2-orphans-include-heuristic" value="1" />
				<?php esc_html_e('شامل تشخیص نام (سطح متوسط — نیاز به تأیید)', 'hesabix-v2'); ?>
			</label>
		</div>
		<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:10px 0;">
			<button type="button" class="button" id="hesabix-v2-orphans-dry-run" disabled>
				<?php esc_html_e('پیش‌نمایش انتخاب‌شده‌ها', 'hesabix-v2'); ?>
			</button>
			<button type="button" class="button button-primary" id="hesabix-v2-orphans-cleanup" disabled>
				<?php esc_html_e('پاک‌سازی امن انتخاب‌شده‌ها', 'hesabix-v2'); ?>
			</button>
			<label style="margin-inline-start:4px;">
				<input type="checkbox" id="hesabix-v2-orphans-allow-medium" value="1" />
				<?php esc_html_e('اجازهٔ پاک‌سازی سطح متوسط', 'hesabix-v2'); ?>
			</label>
		</div>
		<div id="hesabix-v2-orphans-summary" class="description" style="margin:8px 0;"></div>
		<div id="hesabix-v2-orphans-table-wrap" style="overflow:auto;max-height:360px;display:none;">
			<table class="widefat striped" id="hesabix-v2-orphans-table">
				<thead>
					<tr>
						<td class="check-column"><input type="checkbox" id="hesabix-v2-orphans-select-all" /></td>
						<th><?php esc_html_e('شناسه حسابیکس', 'hesabix-v2'); ?></th>
						<th><?php esc_html_e('محصول ووکامرس', 'hesabix-v2'); ?></th>
						<th><?php esc_html_e('سطح', 'hesabix-v2'); ?></th>
						<th><?php esc_html_e('منبع', 'hesabix-v2'); ?></th>
						<th><?php esc_html_e('وضعیت', 'hesabix-v2'); ?></th>
						<th><?php esc_html_e('توضیح', 'hesabix-v2'); ?></th>
					</tr>
				</thead>
				<tbody></tbody>
			</table>
		</div>
		<div id="hesabix-v2-orphans-feedback" class="hesabix-v2-orders-feedback" aria-live="polite" style="margin-top:8px;"></div>
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
