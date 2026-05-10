<?php
/**
 * Dashboard view
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}

$api_key = get_option('hesabix_v2_api_key');
$is_configured = !empty($api_key);
$db = new Hesabix_V2_DB_Service();
$stats = $db->get_sync_stats();
?>

<div class="wrap hesabix-v2-wrap">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php if (!$is_configured): ?>
		<div class="notice notice-warning">
			<p>
				<?php _e('افزونه هنوز پیکربندی نشده است.', 'hesabix-v2'); ?>
				<a href="<?php echo admin_url('admin.php?page=hesabix-v2-setup'); ?>" class="button button-primary">
					<?php _e('شروع راه‌اندازی', 'hesabix-v2'); ?>
				</a>
			</p>
		</div>
	<?php else: ?>
		<div class="hesabix-v2-dashboard">
			<!-- Connection Status -->
			<div class="hesabix-v2-card">
				<h2><?php _e('وضعیت اتصال', 'hesabix-v2'); ?></h2>
				<div id="hesabix-v2-dashboard-connection-extra" class="hesabix-v2-connection-panel" aria-live="polite"></div>
				<button
					type="button"
					id="test-connection"
					class="button hesabix-v2-test-connection"
					data-hesabix-connection-result="#connection-result"
					data-hesabix-connection-extra="#hesabix-v2-dashboard-connection-extra"
				>
					<?php _e('تست اتصال', 'hesabix-v2'); ?>
				</button>
				<div id="connection-result"></div>
			</div>

			<!-- Statistics -->
			<div class="hesabix-v2-stats">
				<div class="stat-box">
					<h3><?php _e('محصولات', 'hesabix-v2'); ?></h3>
					<p class="stat-number"><?php echo $stats['product']['total'] ?? 0; ?></p>
					<p class="stat-detail">
						<?php _e('موفق:', 'hesabix-v2'); ?> <?php echo $stats['product']['synced'] ?? 0; ?>
						<br>
						<?php _e('خطا:', 'hesabix-v2'); ?> <?php echo $stats['product']['error'] ?? 0; ?>
					</p>
				</div>

				<div class="stat-box">
					<h3><?php _e('مشتریان', 'hesabix-v2'); ?></h3>
					<p class="stat-number"><?php echo $stats['customer']['total'] ?? 0; ?></p>
					<p class="stat-detail">
						<?php _e('موفق:', 'hesabix-v2'); ?> <?php echo $stats['customer']['synced'] ?? 0; ?>
						<br>
						<?php _e('خطا:', 'hesabix-v2'); ?> <?php echo $stats['customer']['error'] ?? 0; ?>
					</p>
					<p class="stat-detail" style="margin-top:10px;">
						<a href="<?php echo esc_url(admin_url('admin.php?page=hesabix-v2-customers')); ?>">
							<?php esc_html_e('فهرست مشتریان و همگام‌سازی دستی', 'hesabix-v2'); ?>
						</a>
					</p>
				</div>

				<div class="stat-box">
					<h3><?php _e('سفارشات', 'hesabix-v2'); ?></h3>
					<p class="stat-number"><?php echo $stats['order']['total'] ?? 0; ?></p>
					<p class="stat-detail">
						<?php _e('موفق:', 'hesabix-v2'); ?> <?php echo $stats['order']['synced'] ?? 0; ?>
						<br>
						<?php _e('خطا:', 'hesabix-v2'); ?> <?php echo $stats['order']['error'] ?? 0; ?>
					</p>
				</div>
			</div>

			<!-- Quick Actions -->
			<div class="hesabix-v2-card">
				<h2><?php _e('عملیات سریع', 'hesabix-v2'); ?></h2>
				<p>
					<a href="<?php echo admin_url('admin.php?page=hesabix-v2-sync'); ?>" class="button button-primary">
						<?php _e('همگام‌سازی', 'hesabix-v2'); ?>
					</a>
					<a href="<?php echo esc_url(admin_url('admin.php?page=hesabix-v2-customers')); ?>" class="button">
						<?php esc_html_e('مشتریان', 'hesabix-v2'); ?>
					</a>
					<a href="<?php echo admin_url('admin.php?page=hesabix-v2-settings'); ?>" class="button">
						<?php _e('تنظیمات', 'hesabix-v2'); ?>
					</a>
					<a href="<?php echo admin_url('admin.php?page=hesabix-v2-logs'); ?>" class="button">
						<?php _e('مشاهده لاگ‌ها', 'hesabix-v2'); ?>
					</a>
				</p>
			</div>

			<!-- Recent Logs -->
			<div class="hesabix-v2-card">
				<h2><?php _e('آخرین لاگ‌ها', 'hesabix-v2'); ?></h2>
				<?php
				$recent_logs = Hesabix_V2_Log_Service::get_recent_logs(10);
				if (!empty($recent_logs)):
				?>
					<table class="wp-list-table widefat fixed striped">
						<thead>
							<tr>
								<th><?php _e('زمان', 'hesabix-v2'); ?></th>
								<th><?php _e('نوع', 'hesabix-v2'); ?></th>
								<th><?php _e('عملیات', 'hesabix-v2'); ?></th>
								<th><?php _e('وضعیت', 'hesabix-v2'); ?></th>
								<th><?php _e('پیام', 'hesabix-v2'); ?></th>
							</tr>
						</thead>
						<tbody>
							<?php foreach ($recent_logs as $log): ?>
								<tr>
									<td><?php echo esc_html($log['created_at']); ?></td>
									<td><?php echo esc_html($log['entity_type']); ?></td>
									<td><code><?php echo esc_html($log['action']); ?></code></td>
									<td>
										<span class="status-<?php echo esc_attr($log['status']); ?>">
											<?php echo esc_html($log['status']); ?>
										</span>
									</td>
									<td>
										<?php
										if (!empty($log['error_message'])) {
											echo '<span style="color:#d63638;">' . esc_html(wp_strip_all_tags($log['error_message'])) . '</span>';
										} elseif (!empty($log['response_data'])) {
											$r = json_decode($log['response_data'], true);
											if (is_array($r) && isset($r['status_code'])) {
												echo '<span>' . esc_html(sprintf(__('پاسخ HTTP %s', 'hesabix-v2'), (string) $r['status_code'])) . '</span>';
											} else {
												echo esc_html(wp_strip_all_tags($log['entity_type']));
											}
										} elseif (!empty($log['request_data'])) {
											$q = json_decode($log['request_data'], true);
											if (is_array($q) && !empty($q['method']) && !empty($q['url'])) {
												echo '<span dir="ltr" style="font-size:12px">' . esc_html($q['method'] . ' ' . $q['url']) . '</span>';
											} else {
												echo '&mdash;';
											}
										} else {
											echo '&mdash;';
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
	<?php endif; ?>
</div>

<style>
.hesabix-v2-wrap {
	margin: 20px;
}
.hesabix-v2-card {
	background: white;
	padding: 20px;
	margin: 20px 0;
	border: 1px solid #ccc;
	border-radius: 4px;
}
.hesabix-v2-stats {
	display: flex;
	gap: 20px;
	margin: 20px 0;
}
.stat-box {
	flex: 1;
	background: white;
	padding: 20px;
	border: 1px solid #ccc;
	border-radius: 4px;
	text-align: center;
}
.stat-number {
	font-size: 48px;
	font-weight: bold;
	color: #2271b1;
	margin: 10px 0;
}
.stat-detail {
	font-size: 14px;
	color: #666;
}
.status-success {
	color: green;
	font-weight: bold;
}
.status-error {
	color: red;
	font-weight: bold;
}
</style>

