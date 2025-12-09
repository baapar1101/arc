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
				var message = '<?php _e('موفق:', 'hesabix-v2'); ?> ' + response.success + 
							  '<br><?php _e('ناموفق:', 'hesabix-v2'); ?> ' + response.failed +
							  '<br><?php _e('کل:', 'hesabix-v2'); ?> ' + response.total;
				$result.html('<div class="notice notice-success"><p>' + message + '</p></div>');
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
				var message = '<?php _e('موفق:', 'hesabix-v2'); ?> ' + response.success + 
							  '<br><?php _e('ناموفق:', 'hesabix-v2'); ?> ' + response.failed +
							  '<br><?php _e('کل:', 'hesabix-v2'); ?> ' + response.total;
				$result.html('<div class="notice notice-success"><p>' + message + '</p></div>');
			},
			error: function() {
				$result.html('<div class="notice notice-error"><p><?php _e('خطا رخ داد', 'hesabix-v2'); ?></p></div>');
			},
			complete: function() {
				$btn.prop('disabled', false).text('<?php _e('همگام‌سازی همه مشتریان', 'hesabix-v2'); ?>');
			}
		});
	});
});
</script>

