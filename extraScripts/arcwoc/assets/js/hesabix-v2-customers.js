(function ($) {
	'use strict';

	function getSelectedCustomerIds() {
		var ids = [];
		$('input[name="customer_ids[]"]:checked').each(function () {
			var v = parseInt($(this).val(), 10);
			if (v > 0) {
				ids.push(v);
			}
		});
		return ids;
	}

	function chunk(arr, size) {
		var out = [];
		for (var i = 0; i < arr.length; i += size) {
			out.push(arr.slice(i, i + size));
		}
		return out;
	}

	function appendFeedback(html) {
		$('#hesabix-v2-customers-ajax-feedback').append(html);
	}

	function clearFeedback() {
		$('#hesabix-v2-customers-ajax-feedback').empty();
	}

	function runBatches(ids, done) {
		var batches = chunk(ids, window.hesabix_v2_customers.chunk_size || 8);
		var i = 0;

		function next() {
			if (i >= batches.length) {
				if (typeof done === 'function') {
					done();
				}
				return;
			}
			var part = batches[i];
			i += 1;
			$.post(window.hesabix_v2_customers.ajax_url, {
				action: 'hesabix_v2_customers_sync_batch',
				nonce: window.hesabix_v2_customers.nonce,
				customer_ids: part,
			})
				.done(function (res) {
					if (!res || !res.success) {
						var msg =
							res && res.data && res.data.message
								? res.data.message
								: window.hesabix_v2_customers.strings.genericError || '';
						appendFeedback('<div class="notice notice-error inline"><p>' + msg + '</p></div>');
					} else if (res.data && res.data.results) {
						res.data.results.forEach(function (row) {
							var cls = row.success ? 'notice-success' : 'notice-error';
							var m = row.message || '';
							appendFeedback(
								'<div class="notice ' +
									cls +
									' inline"><p><strong>#' +
									row.customer_id +
									'</strong> — ' +
									m +
									'</p></div>'
							);
						});
					}
					next();
				})
				.fail(function () {
					appendFeedback(
						'<div class="notice notice-error inline"><p>' +
							(window.hesabix_v2_customers.strings.requestFailed || '') +
							'</p></div>'
					);
					next();
				});
		}

		next();
	}

	$(function () {
		$(document).on('click', '.hesabix-v2-customer-sync', function () {
			var id = parseInt($(this).data('customer-id'), 10);
			if (!id) {
				return;
			}
			if (!window.confirm(window.hesabix_v2_customers.strings.confirmSync || '')) {
				return;
			}
			clearFeedback();
			runBatches([id], function () {
				window.location.reload();
			});
		});

		$('#hesabix-v2-customers-bulk-sync').on('click', function () {
			var ids = getSelectedCustomerIds();
			if (!ids.length) {
				return;
			}
			if (!window.confirm(window.hesabix_v2_customers.strings.confirmBulkSync || '')) {
				return;
			}
			clearFeedback();
			runBatches(ids, function () {
				window.location.reload();
			});
		});
	});
})(jQuery);
