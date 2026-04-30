<?php
/**
 * Sync view
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}
?>

<div class="wrap hesabix-v2-wrap">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<div class="hesabix-v2-card">
		<h2><?php _e('همگام‌سازی محصولات', 'hesabix-v2'); ?></h2>
		<p><?php _e('تمام محصولات ووکامرس را با حسابیکس همگام‌سازی کنید', 'hesabix-v2'); ?></p>
		<button id="sync-products" class="button button-primary">
			<?php _e('همگام‌سازی همه محصولات', 'hesabix-v2'); ?>
		</button>
		<div id="products-result"></div>
	</div>

	<div class="hesabix-v2-card">
		<h2><?php _e('همگام‌سازی مشتریان', 'hesabix-v2'); ?></h2>
		<p><?php _e('تمام مشتریان ووکامرس را با حسابیکس همگام‌سازی کنید', 'hesabix-v2'); ?></p>
		<button id="sync-customers" class="button button-primary">
			<?php _e('همگام‌سازی همه مشتریان', 'hesabix-v2'); ?>
		</button>
		<div id="customers-result"></div>
	</div>

	<div class="hesabix-v2-card">
		<h2><?php _e('واردات مشتریان از حسابیکس', 'hesabix-v2'); ?></h2>
		<p><?php _e('اشخاص ثبت‌شده در حسابیکس با نقش مشتری (یا بدون نوع مشخص) با کاربران ووکامرس از طریق ایمیل یا موبایل صورت‌حساب تطبیق داده می‌شوند. صورت‌حساب پروفایل به‌روز و لینک در جدول مپینگ ذخیره می‌شود.', 'hesabix-v2'); ?></p>
		<p>
			<label>
				<input type="checkbox" id="hesabix-import-create-missing" value="1">
				<?php _e('ایجاد حساب مشتری در ووکامرس برای اشخاصی که ایمیل معتبر دارند ولی در سایت کاربر نیستند', 'hesabix-v2'); ?>
			</label>
		</p>
		<p class="description"><?php _e('در این حالت رمز عبور تصادفی ساخته می‌شود؛ ممکن است طبق تنظیمات ووکامرس ایمیل ارسال شود.', 'hesabix-v2'); ?></p>
		<p>
			<button type="button" id="import-customers-from-hesabix" class="button button-primary">
				<?php _e('واردات از حسابیکس', 'hesabix-v2'); ?>
			</button>
		</p>
		<div id="import-customers-result"></div>
	</div>

	<div class="hesabix-v2-card">
		<h2><?php _e('وضعیت همگام‌سازی', 'hesabix-v2'); ?></h2>
		<?php
		$db = new Hesabix_V2_DB_Service();
		$pending = $db->get_pending_items(null, 100);
		$errors = $db->get_error_items(null, 100);
		?>
		<p>
			<?php _e('موارد در انتظار:', 'hesabix-v2'); ?> <strong><?php echo count($pending); ?></strong><br>
			<?php _e('موارد با خطا:', 'hesabix-v2'); ?> <strong><?php echo count($errors); ?></strong>
		</p>

		<?php if (!empty($errors)): ?>
			<h3><?php _e('خطاهای اخیر', 'hesabix-v2'); ?></h3>
			<table class="wp-list-table widefat fixed striped">
				<thead>
					<tr>
						<th><?php _e('نوع', 'hesabix-v2'); ?></th>
						<th><?php _e('شناسه', 'hesabix-v2'); ?></th>
						<th><?php _e('پیام خطا', 'hesabix-v2'); ?></th>
						<th><?php _e('تلاش مجدد', 'hesabix-v2'); ?></th>
					</tr>
				</thead>
				<tbody>
					<?php foreach ($errors as $error): ?>
						<tr>
							<td><?php echo esc_html($error['entity_type']); ?></td>
							<td><?php echo esc_html($error['wc_id']); ?></td>
							<td><?php echo esc_html($error['error_message']); ?></td>
							<td><?php echo esc_html($error['retry_count']); ?></td>
						</tr>
					<?php endforeach; ?>
				</tbody>
			</table>
		<?php endif; ?>
	</div>
</div>

<script>
jQuery(document).ready(function($) {
	// Sync products
	$('#sync-products').on('click', function() {
		var $btn = $(this);
		var $result = $('#products-result');
		
		if (!confirm('<?php _e('آیا مطمئن هستید؟ این ممکن است زمان‌بر باشد.', 'hesabix-v2'); ?>')) {
			return;
		}
		
		$btn.prop('disabled', true).text('<?php _e('در حال همگام‌سازی...', 'hesabix-v2'); ?>');
		$result.html('<p><?php _e('لطفاً صبر کنید...', 'hesabix-v2'); ?></p>');
		
		$.ajax({
			url: hesabix_v2_ajax.ajax_url,
			type: 'POST',
			data: {
				action: 'hesabix_v2_sync_products',
				nonce: hesabix_v2_ajax.nonce
			},
			success: function(response) {
				var noticeClass = (response.failed > 0) ? 'notice-warning' : 'notice-success';
				var message = '<?php _e('موفق:', 'hesabix-v2'); ?> ' + response.success + 
							  '<br><?php _e('ناموفق:', 'hesabix-v2'); ?> ' + response.failed +
							  '<br><?php _e('کل:', 'hesabix-v2'); ?> ' + response.total;
				if (response.errors && response.errors.length > 0) {
					message += '<br><br><strong><?php _e('جزئیات خطاها:', 'hesabix-v2'); ?></strong><ul>';
					response.errors.forEach(function(err) {
						var label = err.variation_id ? ('#'.concat(err.product_id) + ' (واریانت ' + err.variation_id + ')') : ('#' + err.product_id);
						message += '<li>' + label + ': ' + (err.message || '') + '</li>';
					});
					message += '</ul>';
				}
				$result.html('<div class="notice ' + noticeClass + '"><p>' + message + '</p></div>');
			},
			error: function() {
				$result.html('<div class="notice notice-error"><p><?php _e('خطا رخ داد', 'hesabix-v2'); ?></p></div>');
			},
			complete: function() {
				$btn.prop('disabled', false).text('<?php _e('همگام‌سازی همه محصولات', 'hesabix-v2'); ?>');
			}
		});
	});

	// Sync customers
	$('#sync-customers').on('click', function() {
		var $btn = $(this);
		var $result = $('#customers-result');
		
		if (!confirm('<?php _e('آیا مطمئن هستید؟', 'hesabix-v2'); ?>')) {
			return;
		}
		
		$btn.prop('disabled', true).text('<?php _e('در حال همگام‌سازی...', 'hesabix-v2'); ?>');
		$result.html('<p><?php _e('لطفاً صبر کنید...', 'hesabix-v2'); ?></p>');
		
		$.ajax({
			url: hesabix_v2_ajax.ajax_url,
			type: 'POST',
			data: {
				action: 'hesabix_v2_sync_customers',
				nonce: hesabix_v2_ajax.nonce
			},
			success: function(response) {
				var noticeClass = (response.failed > 0) ? 'notice-warning' : 'notice-success';
				var message = '<?php _e('موفق:', 'hesabix-v2'); ?> ' + response.success + 
							  '<br><?php _e('ناموفق:', 'hesabix-v2'); ?> ' + response.failed +
							  '<br><?php _e('کل:', 'hesabix-v2'); ?> ' + response.total;
				if (response.errors && response.errors.length > 0) {
					message += '<br><br><strong><?php _e('جزئیات خطاها:', 'hesabix-v2'); ?></strong><ul>';
					response.errors.forEach(function(err) {
						message += '<li>#' + (err.customer_id || '') + ': ' + (err.message || '') + '</li>';
					});
					message += '</ul>';
				}
				$result.html('<div class="notice ' + noticeClass + '"><p>' + message + '</p></div>');
			},
			error: function() {
				$result.html('<div class="notice notice-error"><p><?php _e('خطا رخ داد', 'hesabix-v2'); ?></p></div>');
			},
			complete: function() {
				$btn.prop('disabled', false).text('<?php _e('همگام‌سازی همه مشتریان', 'hesabix-v2'); ?>');
			}
		});
	});

	// Import customers from Hesabix → WooCommerce
	$('#import-customers-from-hesabix').on('click', function() {
		var $btn = $(this);
		var $result = $('#import-customers-result');

		if (!confirm('<?php echo esc_js(__('این عمل ممکن است زمان‌بر باشد. ادامه می‌دهید؟', 'hesabix-v2')); ?>')) {
			return;
		}

		$btn.prop('disabled', true).text('<?php echo esc_js(__('در حال واردات...', 'hesabix-v2')); ?>');
		$result.html('<p><?php echo esc_js(__('لطفاً صبر کنید...', 'hesabix-v2')); ?></p>');

		$.ajax({
			url: typeof hesabix_v2_ajax !== 'undefined' ? hesabix_v2_ajax.ajax_url : ajaxurl,
			type: 'POST',
			data: {
				action: 'hesabix_v2_import_customers_from_hesabix',
				nonce: typeof hesabix_v2_ajax !== 'undefined' ? hesabix_v2_ajax.nonce : '',
				create_missing: $('#hesabix-import-create-missing').is(':checked') ? '1' : ''
			},
			success: function(res) {
				if (!res || !res.success) {
					var errMsg = res && res.message ? res.message : '<?php echo esc_js(__('خطا در واردات', 'hesabix-v2')); ?>';
					$result.html('<div class="notice notice-error"><p>' + errMsg + '</p></div>');
					return;
				}
				var st = res.stats || {};
				var msg = '<strong><?php echo esc_js(__('نتیجه:', 'hesabix-v2')); ?></strong><br>' +
					'<?php echo esc_js(__('کل بررسی‌شده:', 'hesabix-v2')); ?> ' + (st.total_processed || 0) + '<br>' +
					'<?php echo esc_js(__('به‌روزشده (تطبیق یافت):', 'hesabix-v2')); ?> ' + (st.matched_updated || 0) + '<br>' +
					'<?php echo esc_js(__('ایجاد شده:', 'hesabix-v2')); ?> ' + (st.created || 0) + '<br>' +
					'<?php echo esc_js(__('رد شده:', 'hesabix-v2')); ?> ' + (st.skipped || 0) + '<br>' +
					'<?php echo esc_js(__('ناموفق:', 'hesabix-v2')); ?> ' + (st.failed || 0);
				var noticeClass = (st.failed > 0) ? 'notice-warning' : 'notice-success';
				$result.html('<div class="notice ' + noticeClass + '"><p>' + msg + '</p></div>');
			},
			error: function() {
				$result.html('<div class="notice notice-error"><p><?php echo esc_js(__('خطا در ارتباط با سرور', 'hesabix-v2')); ?></p></div>');
			},
			complete: function() {
				$btn.prop('disabled', false).text('<?php echo esc_js(__('واردات از حسابیکس', 'hesabix-v2')); ?>');
			}
		});
	});
});
</script>

