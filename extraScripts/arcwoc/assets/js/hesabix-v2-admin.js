/**
 * Admin JavaScript for Hesabix V2
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 */

(function($) {
	'use strict';

	/**
	 * Main Hesabix V2 Admin object
	 */
	var HesabixV2Admin = {
		
		/**
		 * Initialize
		 */
		init: function() {
			this.bindEvents();
			this.initTooltips();
		},

		/**
		 * Bind events
		 */
		bindEvents: function() {
			// Test connection
			$(document).on('click', '#test-connection', this.testConnection);

			// Sync products
			$(document).on('click', '#sync-products', this.syncProducts);

			// Sync customers
			$(document).on('click', '#sync-customers', this.syncCustomers);
		},

		/**
		 * Test API connection
		 */
		testConnection: function(e) {
			e.preventDefault();
			
			var $btn = $(this);
			var $result = $('#connection-result');
			var originalText = $btn.text();
			
			$btn.prop('disabled', true).text(hesabix_v2_ajax.strings.syncing);
			$result.html('');
			
			$.ajax({
				url: hesabix_v2_ajax.ajax_url,
				type: 'POST',
				data: {
					action: 'hesabix_v2_test_connection',
					nonce: hesabix_v2_ajax.nonce
				},
				success: function(response) {
					if (response.success) {
						$result.html('<div class="notice notice-success"><p>' + response.message + '</p></div>');
					} else {
						$result.html('<div class="notice notice-error"><p>' + response.message + '</p></div>');
					}
				},
				error: function(xhr, status, error) {
					$result.html('<div class="notice notice-error"><p>' + hesabix_v2_ajax.strings.error + ': ' + error + '</p></div>');
				},
				complete: function() {
					$btn.prop('disabled', false).text(originalText);
				}
			});
		},

		/**
		 * Sync all products
		 */
		syncProducts: function(e) {
			e.preventDefault();
			
			if (!confirm(hesabix_v2_ajax.strings.confirm_sync)) {
				return;
			}
			
			var $btn = $(this);
			var $result = $('#products-result');
			var originalText = $btn.text();
			
			$btn.prop('disabled', true).text(hesabix_v2_ajax.strings.syncing);
			$result.html('<p>' + hesabix_v2_ajax.strings.syncing + '</p>');
			
			$.ajax({
				url: hesabix_v2_ajax.ajax_url,
				type: 'POST',
				data: {
					action: 'hesabix_v2_sync_products',
					nonce: hesabix_v2_ajax.nonce
				},
				timeout: 300000, // 5 minutes
				success: function(response) {
					var message = '<strong>نتیجه همگام‌سازی:</strong><br>' +
								  'موفق: ' + response.success + '<br>' +
								  'ناموفق: ' + response.failed + '<br>' +
								  'کل: ' + response.total;

					if (response.errors && response.errors.length > 0) {
						message += '<br><br><strong>خطاها:</strong><ul>';
						response.errors.forEach(function(error) {
							message += '<li>محصول #' + error.product_id + ': ' + error.message + '</li>';
						});
						message += '</ul>';
					}

					var noticeClass = (response.failed > 0)
						? 'notice-warning'
						: 'notice-success';
					$result.html('<div class="notice ' + noticeClass + '"><p>' + message + '</p></div>');
				},
				error: function(xhr, status, error) {
					$result.html('<div class="notice notice-error"><p>خطا: ' + error + '</p></div>');
				},
				complete: function() {
					$btn.prop('disabled', false).text(originalText);
				}
			});
		},

		/**
		 * Sync all customers
		 */
		syncCustomers: function(e) {
			e.preventDefault();
			
			if (!confirm(hesabix_v2_ajax.strings.confirm_sync)) {
				return;
			}
			
			var $btn = $(this);
			var $result = $('#customers-result');
			var originalText = $btn.text();
			
			$btn.prop('disabled', true).text(hesabix_v2_ajax.strings.syncing);
			$result.html('<p>' + hesabix_v2_ajax.strings.syncing + '</p>');
			
			$.ajax({
				url: hesabix_v2_ajax.ajax_url,
				type: 'POST',
				data: {
					action: 'hesabix_v2_sync_customers',
					nonce: hesabix_v2_ajax.nonce
				},
				timeout: 300000, // 5 minutes
				success: function(response) {
					var message = '<strong>نتیجه همگام‌سازی:</strong><br>' +
								  'موفق: ' + response.success + '<br>' +
								  'ناموفق: ' + response.failed + '<br>' +
								  'کل: ' + response.total;

					var noticeClass = (response.failed > 0)
						? 'notice-warning'
						: 'notice-success';
					$result.html('<div class="notice ' + noticeClass + '"><p>' + message + '</p></div>');
				},
				error: function(xhr, status, error) {
					$result.html('<div class="notice notice-error"><p>خطا: ' + error + '</p></div>');
				},
				complete: function() {
					$btn.prop('disabled', false).text(originalText);
				}
			});
		},

		/**
		 * Initialize tooltips
		 */
		initTooltips: function() {
			$('.hesabix-tooltip').hover(
				function() {
					$(this).attr('title', '');
				},
				function() {
					// Restore
				}
			);
		},

		/**
		 * Show loading
		 */
		showLoading: function($element) {
			$element.html('<div class="hesabix-v2-loading">در حال بارگذاری</div>');
		},

		/**
		 * Show success message
		 */
		showSuccess: function($element, message) {
			$element.html('<div class="notice notice-success"><p>' + message + '</p></div>');
		},

		/**
		 * Show error message
		 */
		showError: function($element, message) {
			$element.html('<div class="notice notice-error"><p>' + message + '</p></div>');
		},

		/**
		 * Format number with Persian digits
		 */
		toPersianNumber: function(num) {
			var persianDigits = '۰۱۲۳۴۵۶۷۸۹';
			return num.toString().replace(/\d/g, function(x) {
				return persianDigits[parseInt(x)];
			});
		}
	};

	// Initialize when document is ready
	$(document).ready(function() {
		HesabixV2Admin.init();
	});

	// Expose to global scope if needed
	window.HesabixV2Admin = HesabixV2Admin;

})(jQuery);

