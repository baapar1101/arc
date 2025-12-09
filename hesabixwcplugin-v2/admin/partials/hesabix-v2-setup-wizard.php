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

<div class="wrap hesabix-v2-setup-wizard">
	<h1><?php _e('راه‌اندازی حسابیکس V2', 'hesabix-v2'); ?></h1>
	
	<div class="wizard-container">
		<!-- Step 1: Login -->
		<div class="wizard-step" id="step-1" style="display: block;">
			<h2><?php _e('مرحله 1: ورود به حساب حسابیکس', 'hesabix-v2'); ?></h2>
			<p><?php _e('لطفاً ایمیل و رمز عبور حساب حسابیکس خود را وارد کنید', 'hesabix-v2'); ?></p>
			
			<form id="login-form">
				<table class="form-table">
					<tr>
						<th><label for="email"><?php _e('ایمیل', 'hesabix-v2'); ?></label></th>
						<td>
							<input type="email" id="email" name="email" class="regular-text" required>
						</td>
					</tr>
					<tr>
						<th><label for="password"><?php _e('رمز عبور', 'hesabix-v2'); ?></label></th>
						<td>
							<input type="password" id="password" name="password" class="regular-text" required>
						</td>
					</tr>
				</table>
				
				<button type="submit" class="button button-primary">
					<?php _e('ورود و ادامه', 'hesabix-v2'); ?>
				</button>
			</form>
			
			<div id="login-message"></div>
		</div>

		<!-- Step 2: Select Business -->
		<div class="wizard-step" id="step-2" style="display: none;">
			<h2><?php _e('مرحله 2: انتخاب کسب‌وکار', 'hesabix-v2'); ?></h2>
			<p><?php _e('کسب‌وکار و سال مالی مورد نظر را انتخاب کنید', 'hesabix-v2'); ?></p>
			
			<div id="businesses-list"></div>
			
			<button id="complete-setup" class="button button-primary" style="display:none;">
				<?php _e('اتمام راه‌اندازی', 'hesabix-v2'); ?>
			</button>
		</div>

		<!-- Step 3: Complete -->
		<div class="wizard-step" id="step-3" style="display: none;">
			<h2><?php _e('راه‌اندازی تکمیل شد!', 'hesabix-v2'); ?></h2>
			<p><?php _e('افزونه با موفقیت راه‌اندازی شد.', 'hesabix-v2'); ?></p>
			
			<p>
				<a href="<?php echo admin_url('admin.php?page=hesabix-v2'); ?>" class="button button-primary">
					<?php _e('رفتن به داشبورد', 'hesabix-v2'); ?>
				</a>
			</p>
		</div>
	</div>
</div>

<style>
.hesabix-v2-setup-wizard {
	max-width: 800px;
	margin: 50px auto;
}
.wizard-container {
	background: white;
	padding: 30px;
	border: 1px solid #ccc;
	border-radius: 8px;
}
.wizard-step {
	min-height: 300px;
}
#businesses-list {
	margin: 20px 0;
}
.business-item {
	padding: 15px;
	border: 1px solid #ddd;
	margin: 10px 0;
	border-radius: 4px;
	cursor: pointer;
}
.business-item:hover {
	background: #f5f5f5;
}
.business-item.selected {
	background: #e3f2fd;
	border-color: #2271b1;
}
</style>

<script>
jQuery(document).ready(function($) {
	var sessionToken = '';
	var selectedBusiness = null;
	var selectedFiscalYear = null;

	// Step 1: Login
	$('#login-form').on('submit', function(e) {
		e.preventDefault();
		
		var email = $('#email').val();
		var password = $('#password').val();
		var $message = $('#login-message');
		
		$message.html('<p><?php _e('در حال ورود...', 'hesabix-v2'); ?></p>');
		
		// This would normally call the API through backend
		// For now, showing placeholder
		$message.html('<div class="notice notice-info"><p><?php _e('برای تکمیل این بخش نیاز به پیاده‌سازی AJAX handler است', 'hesabix-v2'); ?></p></div>');
		
		// Simulate success for demo
		setTimeout(function() {
			$('#step-1').hide();
			$('#step-2').show();
			loadBusinesses();
		}, 1000);
	});

	function loadBusinesses() {
		// Load businesses from API
		var $list = $('#businesses-list');
		$list.html('<p><?php _e('در حال بارگذاری کسب‌وکارها...', 'hesabix-v2'); ?></p>');
		
		// This needs AJAX implementation
		$list.html('<p><?php _e('برای نمایش لیست کسب‌وکارها نیاز به اتصال API دارد', 'hesabix-v2'); ?></p>');
	}

	$('#complete-setup').on('click', function() {
		// Save settings and complete
		$('#step-2').hide();
		$('#step-3').show();
	});
});
</script>

