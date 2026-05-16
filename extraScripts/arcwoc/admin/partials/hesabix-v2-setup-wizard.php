<?php
/**
 * Setup Wizard view
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}
?>

<div class="wrap hesabix-v2-wrap hesabix-v2-setup-wizard">
	<h1><?php _e('راه‌اندازی حسابیکس V2', 'hesabix-v2'); ?></h1>

	<?php if (get_option('hesabix_v2_setup_completed') && get_option('hesabix_v2_api_key')): ?>
		<div class="notice notice-warning hesabix-v2-setup-reconnect-note">
			<p><strong><?php esc_html_e('هشدار', 'hesabix-v2'); ?></strong></p>
			<p><?php esc_html_e('برای اتصال کسب‌وکار دیگری به افزونه، ابتدا افزونه را حذف و مجدد نصب کنید تا ارتباطات کسب‌وکار قبلی پاک شود.', 'hesabix-v2'); ?></p>
		</div>
	<?php endif; ?>
	
	<div class="wizard-container">
		<!-- Step 1: API Key -->
		<div class="wizard-step" id="step-1" style="display: block;">
			<h2><?php _e('مرحله 1: کلید API حسابیکس', 'hesabix-v2'); ?></h2>
			<p><?php _e('کلید API خود را از پنل حسابیکس دریافت کرده و در کادر زیر وارد کنید. احراز هویت با استفاده از همین کلید انجام می‌شود.', 'hesabix-v2'); ?></p>
			
			<form id="api-key-form">
				<table class="form-table">
					<tr>
						<th><label for="api_base_url"><?php _e('آدرس سرور API', 'hesabix-v2'); ?></label></th>
						<td>
							<input type="url" id="api_base_url" name="api_base_url" class="regular-text" value="<?php echo esc_attr(get_option('hesabix_v2_api_base_url', HESABIX_V2_API_BASE_URL)); ?>" dir="ltr" placeholder="https://hsxn.hesabix.ir/api/v1">
							<p class="description"><?php _e('آدرس پایه سرور (پیش‌فرض: https://hsxn.hesabix.ir/api/v1).', 'hesabix-v2'); ?></p>
						</td>
					</tr>
					<tr>
						<th><label for="api_key"><?php _e('کلید API', 'hesabix-v2'); ?></label></th>
						<td>
							<input type="password" id="api_key" name="api_key" class="regular-text" placeholder="ak_live_..." required dir="ltr">
							<p class="description"><?php _e('کلید API با پیشوند ak_live_ یا ak_test_ (مثال: ak_live_xxx...). از پنل حسابیکس > تنظیمات > کلیدهای API قابل دریافت است.', 'hesabix-v2'); ?></p>
						</td>
					</tr>
				</table>
				
				<button type="submit" class="button button-primary">
					<?php _e('تأیید و ادامه', 'hesabix-v2'); ?>
				</button>
			</form>
			
			<div id="api-key-message"></div>
		</div>

		<!-- Step 2: Select Business -->
		<div class="wizard-step" id="step-2" style="display: none;">
			<h2><?php _e('مرحله 2: انتخاب کسب‌وکار', 'hesabix-v2'); ?></h2>
			<p><?php esc_html_e('کسب‌وکار مورد نظر را انتخاب کنید. پس از اتمام راه‌اندازی، شناسهٔ سال مالی جاری از حسابیکس خوانده و در افزونه ذخیره می‌شود تا درخواست‌های API (از جمله تراز افتتاحیه) با هدر سال مالی درست ارسال شوند. برای این کار کلید API باید به سال مالی کسب‌وکار دسترسی مشاهده داشته باشد.', 'hesabix-v2'); ?></p>
			
			<div id="businesses-list"></div>
			
			<p style="margin-top: 20px;">
				<button id="complete-setup" class="button button-primary" style="display:none;">
					<?php _e('اتمام راه‌اندازی', 'hesabix-v2'); ?>
				</button>
			</p>
		</div>

		<!-- Step 3: Complete -->
		<div class="wizard-step" id="step-3" style="display: none;">
			<h2><?php _e('راه‌اندازی تکمیل شد!', 'hesabix-v2'); ?></h2>
			<p><?php esc_html_e('افزونه با موفقیت راه‌اندازی شد. در صورت نیاز سال مالی ذخیره‌شده را در تنظیمات حسابیکس، تب «اتصال» (جزئیات اتصال یا تست اتصال) بررسی کنید.', 'hesabix-v2'); ?></p>
			
			<p>
				<a href="<?php echo admin_url('admin.php?page=hesabix-v2'); ?>" class="button button-primary">
					<?php _e('رفتن به داشبورد', 'hesabix-v2'); ?>
				</a>
			</p>
		</div>
	</div>
</div>

<script>
jQuery(document).ready(function($) {
	var apiKey = '';
	var selectedBusiness = null;
	var ajaxUrl = typeof hesabix_v2_ajax !== 'undefined' ? hesabix_v2_ajax.ajax_url : '';
	var nonce = typeof hesabix_v2_ajax !== 'undefined' ? hesabix_v2_ajax.nonce : '';

	function showMessage($el, type, text) {
		type = type || 'info';
		$el.html('<div class="notice notice-' + type + '"><p>' + text + '</p></div>');
	}

	// Step 1: Verify API Key
	$('#api-key-form').on('submit', function(e) {
		e.preventDefault();
		var key = $('#api_key').val();
		var $message = $('#api-key-message');
		var $btn = $(this).find('button[type="submit"]');

		if (!key || !key.trim()) {
			showMessage($message, 'error', '<?php echo esc_js(__('کلید API را وارد کنید.', 'hesabix-v2')); ?>');
			return;
		}

		$btn.prop('disabled', true);
		$message.html('<p><?php echo esc_js(__('در حال تأیید کلید...', 'hesabix-v2')); ?></p>');

		var apiBaseUrl = $('#api_base_url').val();
		$.post(ajaxUrl, {
			action: 'hesabix_v2_setup_verify_api_key',
			nonce: nonce,
			api_key: key.trim(),
			api_base_url: apiBaseUrl || ''
		}).done(function(res) {
			if (res && res.success) {
				apiKey = key.trim();
				$('#step-1').hide();
				$('#step-2').show();
				loadBusinesses();
			} else {
				showMessage($message, 'error', res && res.message ? res.message : '<?php echo esc_js(__('کلید API نامعتبر است.', 'hesabix-v2')); ?>');
				$btn.prop('disabled', false);
			}
		}).fail(function(xhr) {
			var msg = '<?php echo esc_js(__('خطا در ارتباط با سرور.', 'hesabix-v2')); ?>';
			if (xhr.responseJSON && xhr.responseJSON.message) msg = xhr.responseJSON.message;
			else if (xhr.responseText) {
				try { var j = JSON.parse(xhr.responseText); if (j.message) msg = j.message; } catch(e) {}
			}
			showMessage($message, 'error', msg);
			$btn.prop('disabled', false);
		});
	});

	function loadBusinesses() {
		var $list = $('#businesses-list');
		$list.html('<p><?php echo esc_js(__('در حال بارگذاری کسب‌وکارها...', 'hesabix-v2')); ?></p>');

		$.post(ajaxUrl, {
			action: 'hesabix_v2_setup_businesses',
			nonce: nonce,
			api_key: apiKey
		}).done(function(res) {
			if (res && res.success && res.businesses && res.businesses.length) {
				$list.empty();
				res.businesses.forEach(function(b) {
					var id = parseInt(b.id || b.business_id, 10);
					if (!id) return;
					var name = b.name_fa || b.name || b.title || ('کسب‌وکار ' + id);
					var $div = $('<div/>', { 'class': 'business-item', 'data-id': id });
					$div.text(name);
					$list.append($div);
				});
				$('#complete-setup').hide();
			} else if (res && res.success && (!res.businesses || !res.businesses.length)) {
				$list.html('<p><?php echo esc_js(__('کسب‌وکاری یافت نشد.', 'hesabix-v2')); ?></p>');
			} else {
				$list.html('<div class="notice notice-error"><p>' + (res && res.message ? res.message : '<?php echo esc_js(__('بارگذاری ناموفق.', 'hesabix-v2')); ?>') + '</p></div>');
			}
		}).fail(function(xhr) {
			var msg = xhr.responseJSON && xhr.responseJSON.message ? xhr.responseJSON.message : '<?php echo esc_js(__('خطا در بارگذاری.', 'hesabix-v2')); ?>';
			$list.html('<div class="notice notice-error"><p>' + msg + '</p></div>');
		});
	}

	$(document).on('click', '.business-item', function() {
		var id = $(this).data('id');
		$('.business-item').removeClass('selected');
		$(this).addClass('selected');
		selectedBusiness = id;
		$('#complete-setup').show();
	});

	$('#complete-setup').on('click', function() {
		if (!selectedBusiness) {
			alert('<?php echo esc_js(__('کسب‌وکار را انتخاب کنید.', 'hesabix-v2')); ?>');
			return;
		}
		var $btn = $(this);
		$btn.prop('disabled', true).text('<?php echo esc_js(__('در حال ذخیره...', 'hesabix-v2')); ?>');

		$.post(ajaxUrl, {
			action: 'hesabix_v2_setup_complete',
			nonce: nonce,
			api_key: apiKey,
			business_id: selectedBusiness
		}).done(function(res) {
			if (res && res.success) {
				$('#step-2').hide();
				$('#step-3').show();
			} else {
				alert(res && res.message ? res.message : '<?php echo esc_js(__('خطا در ذخیره.', 'hesabix-v2')); ?>');
				$btn.prop('disabled', false).text('<?php echo esc_js(__('اتمام راه‌اندازی', 'hesabix-v2')); ?>');
			}
		}).fail(function() {
			$btn.prop('disabled', false).text('<?php echo esc_js(__('اتمام راه‌اندازی', 'hesabix-v2')); ?>');
			alert('<?php echo esc_js(__('خطا در ارتباط با سرور.', 'hesabix-v2')); ?>');
		});
	});
});
</script>

