<?php
/**
 * Migration tool view
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
		<h2><?php _e('مایگریشن از نسخه قدیمی', 'hesabix-v2'); ?></h2>
		
		<div class="notice notice-warning">
			<p>
				<strong><?php _e('توجه:', 'hesabix-v2'); ?></strong>
				<?php _e('این ابزار داده‌های mapping از نسخه قدیمی را به نسخه جدید منتقل می‌کند.', 'hesabix-v2'); ?>
			</p>
		</div>

		<p><?php _e('قبل از شروع مایگریشن، مطمئن شوید که:', 'hesabix-v2'); ?></p>
		<ul>
			<li><?php _e('پشتیبان کامل از دیتابیس گرفته‌اید', 'hesabix-v2'); ?></li>
			<li><?php _e('افزونه نسخه 2 را پیکربندی کرده‌اید', 'hesabix-v2'); ?></li>
			<li><?php _e('Business ID در هر دو نسخه یکسان است', 'hesabix-v2'); ?></li>
		</ul>

		<button id="start-migration" class="button button-primary button-large">
			<?php _e('شروع مایگریشن', 'hesabix-v2'); ?>
		</button>

		<div id="migration-progress" style="display:none; margin-top:20px;">
			<p><?php _e('در حال مایگریشن...', 'hesabix-v2'); ?></p>
			<progress id="migration-bar" max="100" value="0" style="width:100%;"></progress>
			<p id="migration-status"></p>
		</div>

		<div id="migration-result" style="margin-top:20px;"></div>
	</div>
</div>

<script>
jQuery(document).ready(function($) {
	$('#start-migration').on('click', function() {
		if (!confirm('<?php _e('آیا مطمئن هستید؟ این عملیات قابل بازگشت نیست.', 'hesabix-v2'); ?>')) {
			return;
		}

		var $btn = $(this);
		var $progress = $('#migration-progress');
		var $result = $('#migration-result');

		$btn.prop('disabled', true);
		$progress.show();
		$result.html('');

		// This needs backend implementation
		$result.html('<div class="notice notice-info"><p><?php _e('ابزار مایگریشن نیاز به پیاده‌سازی دارد', 'hesabix-v2'); ?></p></div>');
	});
});
</script>

