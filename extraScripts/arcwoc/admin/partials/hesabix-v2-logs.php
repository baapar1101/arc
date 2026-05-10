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
$debug_on = (bool) get_option('hesabix_v2_debug_mode');

/**
 * @param string|null $json_str
 * @return string
 */
function hesabix_v2_logs_render_json_cell($json_str)
{
	if ($json_str === null || $json_str === '') {
		return '&mdash;';
	}
	$dec = json_decode($json_str, true);
	if (!is_array($dec) && !is_object($dec)) {
		return '<pre class="hesabix-v2-log-pre hesabix-v2-log-pre--raw">' . esc_html($json_str) . '</pre>';
	}
	$pretty = wp_json_encode($dec, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
	if ($pretty === false) {
		return '<pre class="hesabix-v2-log-pre hesabix-v2-log-pre--raw">' . esc_html($json_str) . '</pre>';
	}

	return '<details class="hesabix-v2-log-json"><summary><span class="hesabix-v2-log-json-toggle">' . esc_html__('نمایش جزئیات', 'hesabix-v2') . '</span></summary><pre class="hesabix-v2-log-pre">' . esc_html($pretty) . '</pre></details>';
}
?>

<div class="wrap hesabix-v2-wrap">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<div class="notice notice-info hesabix-v2-log-policy" style="margin:12px 0;max-width:60rem;">
		<p style="margin:.4em 0;">
			<?php if ($debug_on): ?>
				<?php esc_html_e('حالت دیباگ فعال است: درخواست‌ها و پاسخ‌های API بین ووکامرس و حسابیکس، همراه با رخدادهای info و warning در جدول زیر ثبت می‌شوند. هدر Authorization در لاگ سانسور می‌شود.', 'hesabix-v2'); ?>
			<?php else: ?>
				<?php esc_html_e('حالت دیباگ غیرفعال است: فقط رخدادهای سطح خطا (error) در این جدول نگه داشته می‌شوند؛ جزئیات بدنهٔ درخواست و پاسخ هرجا در دسترس باشد در ستون‌های زیر ذخیره می‌شود.', 'hesabix-v2'); ?>
			<?php endif; ?>
		</p>
	</div>

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
			<table class="wp-list-table widefat fixed striped hesabix-v2-logs-table">
				<thead>
					<tr>
						<th style="width:9em;"><?php _e('زمان', 'hesabix-v2'); ?></th>
						<th><?php _e('نوع', 'hesabix-v2'); ?></th>
						<th style="width:5em;"><?php _e('شناسه', 'hesabix-v2'); ?></th>
						<th style="width:6em;"><?php _e('عملیات', 'hesabix-v2'); ?></th>
						<th style="width:7em;"><?php _e('وضعیت', 'hesabix-v2'); ?></th>
						<th style="width:5em;"><?php _e('زمان اجرا', 'hesabix-v2'); ?> (s)</th>
						<th><?php _e('خلاصه پیام', 'hesabix-v2'); ?></th>
						<th style="min-width:120px;"><?php _e('درخواست / داده ارسالی', 'hesabix-v2'); ?></th>
						<th style="min-width:120px;"><?php _e('پاسخ / خطا', 'hesabix-v2'); ?></th>
					</tr>
				</thead>
				<tbody>
					<?php foreach ($logs as $log) : ?>
						<?php
						$exec = isset($log['execution_time']) && $log['execution_time'] !== null && $log['execution_time'] !== ''
							? number_format((float) $log['execution_time'], 3, '.', '')
							: '—';
						$summary = '';
						if (!empty($log['error_message'])) {
							$summary = $log['error_message'];
						} elseif ($log['action'] === 'debug') {
							if (!empty($log['request_data'])) {
								$rj = json_decode($log['request_data'], true);
								if (is_array($rj)) {
									if (!empty($rj['url'])) {
										$summary = (isset($rj['method']) ? $rj['method'] . ' ' : '') . $rj['url'];
									} elseif (!empty($rj['_summary'])) {
										$summary = (string) $rj['_summary'];
									} elseif (!empty($rj['endpoint'])) {
										$summary = (string) $rj['endpoint'];
									}
								}
							}
							if ($summary === '' && !empty($log['response_data'])) {
								$r2 = json_decode($log['response_data'], true);
								if (is_array($r2) && isset($r2['status_code'])) {
									$summary = __('HTTP', 'hesabix-v2') . ' ' . (string) $r2['status_code'];
								}
							}
						}
						if ($summary === '') {
							$summary = (string) $log['action'];
						}
						?>
						<tr class="hesabix-v2-log-row hesabix-v2-log-row--<?php echo esc_attr($log['status']); ?>">
							<td><?php echo esc_html($log['created_at']); ?></td>
							<td><?php echo esc_html($log['entity_type']); ?></td>
							<td><?php echo esc_html($log['entity_id']); ?></td>
							<td><code><?php echo esc_html($log['action']); ?></code></td>
							<td>
								<span class="status-<?php echo esc_attr($log['status']); ?>">
									<?php echo esc_html($log['status']); ?>
								</span>
							</td>
							<td dir="ltr" style="text-align:center;"><?php echo esc_html($exec); ?></td>
							<td class="col-summary"><?php echo esc_html(wp_strip_all_tags($summary)); ?></td>
							<td class="col-json"><?php echo wp_kses(hesabix_v2_logs_render_json_cell(isset($log['request_data']) ? $log['request_data'] : null), array(
								'details' => array('class' => true, 'open' => true),
								'summary' => array('class' => true),
								'span' => array('class' => true),
								'pre' => array('class' => true),
								));

							?></td>
							<td class="col-json"><?php echo wp_kses(hesabix_v2_logs_render_json_cell(isset($log['response_data']) ? $log['response_data'] : null), array(
								'details' => array('class' => true, 'open' => true),
								'summary' => array('class' => true),
								'span' => array('class' => true),
								'pre' => array('class' => true),
								)); ?></td>
						</tr>
					<?php endforeach; ?>
				</tbody>
			</table>
		<?php else: ?>
			<p><?php _e('لاگی وجود ندارد', 'hesabix-v2'); ?></p>
		<?php endif; ?>
	</div>
</div>

<style>
.hesabix-v2-logs-table .col-summary { max-width: 14rem; word-break: break-word; }
.hesabix-v2-log-pre {
	margin: .5em 0 0;
	padding: .6em .75em;
	background: #f6f7f7;
	border: 1px solid #ccd0d4;
	border-radius: 3px;
	direction: ltr;
	text-align: left;
	font-size: 11px;
	line-height: 1.35;
	overflow-x: auto;
	max-height: 240px;
	overflow-y: auto;
	white-space: pre-wrap;
	word-break: break-word;
	max-width: 36rem;
}
.hesabix-v2-log-json summary { cursor: pointer; user-select: none; color: #2271b1; font-size: 12px; margin: .15em 0; }
.hesabix-v2-log-json-toggle { border-bottom: 1px dashed currentColor; }
.hesabix-v2-logs-table .status-debug { background: rgba(0,124,186,.06); }
.hesabix-v2-logs-table .status-warning { background: rgba(214,144,17,.06); }
</style>
