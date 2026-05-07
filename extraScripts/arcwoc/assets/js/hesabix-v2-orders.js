(function ($) {
	'use strict';

	function getSelectedIds() {
		var ids = [];
		$('input[name="order_ids[]"]:checked').each(function () {
			var v = parseInt($(this).val(), 10);
			if (v > 0) ids.push(v);
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
		var $box = $('#hesabix-v2-orders-ajax-feedback');
		$box.append(html);
	}

	function clearFeedback() {
		$('#hesabix-v2-orders-ajax-feedback').empty();
	}

	function runBatches(ids, action, done) {
		var batches = chunk(ids, (window.hesabix_v2_orders && window.hesabix_v2_orders.chunk_size) || 5);
		var i = 0;

		function next() {
			if (i >= batches.length) {
				if (typeof done === 'function') done();
				return;
			}
			var part = batches[i];
			i += 1;
			$.post(
				window.hesabix_v2_orders.ajax_url,
				{
					action: action,
					nonce: window.hesabix_v2_orders.nonce,
					order_ids: part,
				}
			)
				.done(function (res) {
					if (!res || !res.success) {
						var msg =
							res && res.data && res.data.message
								? res.data.message
								: (window.hesabix_v2_orders.strings.genericError || '');
						appendFeedback('<div class="notice notice-error inline"><p>' + msg + '</p></div>');
					} else if (res.data && res.data.results) {
						res.data.results.forEach(function (row) {
							var cls = row.success ? 'notice-success' : 'notice-error';
							var m = row.message || '';
							appendFeedback(
								'<div class="notice ' +
									cls +
									' inline"><p><strong>#' +
									row.order_id +
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
							(window.hesabix_v2_orders.strings.requestFailed || '') +
							'</p></div>'
					);
					next();
				});
		}

		next();
	}

	$(function () {
		$(document).on('click', '.hesabix-v2-order-sync', function () {
			var id = parseInt($(this).data('order-id'), 10);
			if (!id) return;
			if (!window.confirm(window.hesabix_v2_orders.strings.confirmSync || '')) return;
			clearFeedback();
			runBatches([id], 'hesabix_v2_orders_sync_batch', function () {
				window.location.reload();
			});
		});

		$(document).on('click', '.hesabix-v2-order-unsync', function () {
			var id = parseInt($(this).data('order-id'), 10);
			if (!id) return;
			if (!window.confirm(window.hesabix_v2_orders.strings.confirmUnsync || '')) return;
			clearFeedback();
			runBatches([id], 'hesabix_v2_orders_unsync_batch', function () {
				window.location.reload();
			});
		});

		$('#hesabix-v2-bulk-sync').on('click', function () {
			var ids = getSelectedIds();
			if (!ids.length) return;
			if (!window.confirm(window.hesabix_v2_orders.strings.confirmBulkSync || '')) return;
			clearFeedback();
			runBatches(ids, 'hesabix_v2_orders_sync_batch', function () {
				window.location.reload();
			});
		});

		$('#hesabix-v2-bulk-unsync').on('click', function () {
			var ids = getSelectedIds();
			if (!ids.length) return;
			if (!window.confirm(window.hesabix_v2_orders.strings.confirmBulkUnsync || '')) return;
			clearFeedback();
			runBatches(ids, 'hesabix_v2_orders_unsync_batch', function () {
				window.location.reload();
			});
		});

		$(document).on('click', '.hesabix-v2-pause-toggle', function () {
			var $b = $(this);
			var orderId = parseInt($b.data('order-id'), 10);
			var currentlyPaused = String($b.data('paused')) === '1';
			if (!currentlyPaused) {
				if (!window.confirm(window.hesabix_v2_orders.strings.confirmPause || '')) return;
			} else {
				if (!window.confirm(window.hesabix_v2_orders.strings.confirmResume || '')) return;
			}
			$.post(window.hesabix_v2_orders.ajax_url, {
				action: 'hesabix_v2_orders_set_pause',
				nonce: window.hesabix_v2_orders.nonce,
				order_id: orderId,
				pause: currentlyPaused ? 0 : 1,
			})
				.done(function (res) {
					if (res && res.success) {
						window.location.reload();
					} else {
						var msg =
							res && res.data && res.data.message
								? res.data.message
								: (window.hesabix_v2_orders.strings.genericError || '');
						window.alert(msg);
					}
				})
				.fail(function () {
					window.alert(window.hesabix_v2_orders.strings.requestFailed || '');
				});
		});
	});
})(jQuery);
