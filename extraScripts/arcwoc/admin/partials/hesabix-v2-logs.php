<?php
/**
 * Logs view
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}

$logs = Hesabix_V2_Log_Service::get_recent_logs(100);
?>

<div class="wrap hesabix-v2-wrap">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php if (isset($_GET['logs_cleared'])): ?>
		<div class="notice notice-success is-dismissible"><p><?php _e('لاگ‌ها با موفقیت پاک شدند.', 'hesabix-v2'); ?></p></div>
	<?php endif; ?>

	<div class="hesabix-v2-card">
		<h2><?php _e('لاگ‌های سیستم', 'hesabix-v2'); ?></h2>
		<p style="margin-bottom: 12px;">
			<form method="post" action="" onsubmit="return confirm('<?php echo esc_js(__('آیا از پاک کردن تمام لاگ‌ها اطمینان دارید؟ این عمل قابل بازگشت نیست.', 'hesabix-v2')); ?>');">
				<?php wp_nonce_field('hesabix_v2_clear_logs'); ?>
				<button type="submit" name="hesabix_v2_clear_logs" value="1" class="button button-secondary"><?php _e('پاک کردن لاگ‌ها', 'hesabix-v2'); ?></button>
			</form>
		</p>
		
		<?php if (!empty($logs)): ?>
			<table class="wp-list-table widefat fixed striped">
				<thead>
					<tr>
						<th><?php _e('زمان', 'hesabix-v2'); ?></th>
						<th><?php _e('نوع', 'hesabix-v2'); ?></th>
						<th><?php _e('شناسه', 'hesabix-v2'); ?></th>
						<th><?php _e('عملیات', 'hesabix-v2'); ?></th>
						<th><?php _e('وضعیت', 'hesabix-v2'); ?></th>
						<th><?php _e('پیام', 'hesabix-v2'); ?></th>
					</tr>
				</thead>
				<tbody>
					<?php foreach ($logs as $log): ?>
						<tr>
							<td><?php echo esc_html($log['created_at']); ?></td>
							<td><?php echo esc_html($log['entity_type']); ?></td>
							<td><?php echo esc_html($log['entity_id']); ?></td>
							<td><?php echo esc_html($log['action']); ?></td>
							<td>
								<span class="status-<?php echo esc_attr($log['status']); ?>">
									<?php echo esc_html($log['status']); ?>
								</span>
							</td>
							<td>
								<?php 
								if (!empty($log['error_message'])) {
									echo '<span style="color:red;">' . esc_html($log['error_message']) . '</span>';
								} else {
									echo '—';
								}
								?>
							</td>
						</tr>
					<?php endforeach; ?>
				</tbody>
			</table>
		<?php else: ?>
			<p><?php _e('لاگی وجود ندارد', 'hesabix-v2'); ?></p>
		<?php endif; ?>
	</div>
</div>

