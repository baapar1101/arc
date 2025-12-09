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

	<div class="hesabix-v2-card">
		<h2><?php _e('لاگ‌های سیستم', 'hesabix-v2'); ?></h2>
		
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

