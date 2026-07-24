(function ($) {
	'use strict';

	function getSelectedProductIds() {
		var ids = [];
		$('input[name="product_ids[]"]:checked').each(function () {
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
		$('#hesabix-v2-products-ajax-feedback').append(html);
	}

	function clearFeedback() {
		$('#hesabix-v2-products-ajax-feedback').empty();
	}

	function orphanCfg() {
		return window.hesabix_v2_products || {};
	}

	function orphanStrings() {
		return orphanCfg().strings || {};
	}

	function appendOrphanFeedback(html) {
		$('#hesabix-v2-orphans-feedback').append(html);
	}

	function clearOrphanFeedback() {
		$('#hesabix-v2-orphans-feedback').empty();
	}

	function getSelectedOrphanIds() {
		var ids = [];
		$('#hesabix-v2-orphans-table tbody input.hesabix-v2-orphan-cb:checked').each(function () {
			var v = parseInt($(this).val(), 10);
			if (v > 0) {
				ids.push(v);
			}
		});
		return ids;
	}

	function setOrphanActionButtonsEnabled(enabled) {
		$('#hesabix-v2-orphans-dry-run, #hesabix-v2-orphans-cleanup').prop('disabled', !enabled);
	}

	function escapeHtml(str) {
		return String(str == null ? '' : str)
			.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;')
			.replace(/"/g, '&quot;');
	}

	function renderOrphans(candidates, counts) {
		var $tbody = $('#hesabix-v2-orphans-table tbody');
		$tbody.empty();
		var s = orphanStrings();

		if (!candidates || !candidates.length) {
			$('#hesabix-v2-orphans-table-wrap').hide();
			setOrphanActionButtonsEnabled(false);
			$('#hesabix-v2-orphans-summary').text(
				counts && typeof counts.total !== 'undefined'
					? escapeHtml((counts.total || 0) + ' — ' + (s.orphanDone || ''))
					: ''
			);
			return;
		}

		candidates.forEach(function (row) {
			var hid = parseInt(row.hesabix_id, 10) || 0;
			var tier = row.tier === 'medium' ? s.orphanTierMedium || 'medium' : s.orphanTierHigh || 'high';
			var wcLabel = row.parent_name || '';
			if (row.wc_parent_id) {
				wcLabel = '#' + row.wc_parent_id + (wcLabel ? ' — ' + wcLabel : '');
			}
			var reason = row.reason || row.last_message || '';
			var status = row.status || 'pending';
			var checked =
				status === 'deleted' || status === 'deactivated' ? '' : 'checked';
			var disabled = status === 'deleted' ? 'disabled' : '';
			var tr =
				'<tr data-tier="' +
				escapeHtml(row.tier || 'high') +
				'">' +
				'<th class="check-column"><input type="checkbox" class="hesabix-v2-orphan-cb" value="' +
				hid +
				'" ' +
				checked +
				' ' +
				disabled +
				' /></th>' +
				'<td>' +
				hid +
				'</td>' +
				'<td>' +
				escapeHtml(wcLabel) +
				'</td>' +
				'<td>' +
				escapeHtml(tier) +
				'</td>' +
				'<td>' +
				escapeHtml(row.source || '') +
				'</td>' +
				'<td>' +
				escapeHtml(status) +
				'</td>' +
				'<td>' +
				escapeHtml(reason) +
				'</td>' +
				'</tr>';
			$tbody.append(tr);
		});

		$('#hesabix-v2-orphans-table-wrap').show();
		setOrphanActionButtonsEnabled(true);
		$('#hesabix-v2-orphans-summary').text(
			(counts
				? 'total=' +
				  (counts.total || 0) +
				  ', high=' +
				  (counts.high || 0) +
				  ', medium=' +
				  (counts.medium || 0) +
				  ', pending=' +
				  (counts.pending || 0)
				: '') +
				''
		);
	}

	function runOrphanBatches(ids, dryRun, done) {
		var size = orphanCfg().orphan_chunk_size || 8;
		var batches = chunk(ids, size);
		var i = 0;
		var allowMedium = $('#hesabix-v2-orphans-allow-medium').is(':checked') ? 1 : 0;

		function next() {
			if (i >= batches.length) {
				if (typeof done === 'function') {
					done();
				}
				return;
			}
			var part = batches[i];
			i += 1;
			$.post(orphanCfg().ajax_url, {
				action: 'hesabix_v2_orphans_cleanup_batch',
				nonce: orphanCfg().nonce,
				hesabix_ids: part,
				dry_run: dryRun ? 1 : 0,
				allow_medium: allowMedium,
				deactivate_if_used: 1,
			})
				.done(function (res) {
					if (!res || !res.success) {
						var msg =
							res && res.data && res.data.message
								? res.data.message
								: orphanStrings().genericError || '';
						appendOrphanFeedback('<div class="notice notice-error inline"><p>' + escapeHtml(msg) + '</p></div>');
					} else if (res.data) {
						if (res.data.message) {
							appendOrphanFeedback(
								'<div class="notice notice-info inline"><p>' + escapeHtml(res.data.message) + '</p></div>'
							);
						}
						if (res.data.results && res.data.results.length) {
							res.data.results.forEach(function (row) {
								var ok = !!row.success;
								var cls = ok ? 'notice-success' : 'notice-error';
								if (row.action === 'would_deactivate' || row.action === 'in_use' || row.action === 'deactivated') {
									cls = 'notice-warning';
								}
								appendOrphanFeedback(
									'<div class="notice ' +
										cls +
										' inline"><p><strong>HX#' +
										escapeHtml(row.hesabix_id) +
										'</strong> [' +
										escapeHtml(row.action || '') +
										'] — ' +
										escapeHtml(row.message || '') +
										'</p></div>'
								);
							});
						}
					}
					next();
				})
				.fail(function () {
					appendOrphanFeedback(
						'<div class="notice notice-error inline"><p>' +
							escapeHtml(orphanStrings().requestFailed || '') +
							'</p></div>'
					);
					next();
				});
		}

		next();
	}

	function runBatches(ids, done) {
		var batches = chunk(ids, window.hesabix_v2_products.chunk_size || 8);
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
			$.post(window.hesabix_v2_products.ajax_url, {
				action: 'hesabix_v2_products_sync_batch',
				nonce: window.hesabix_v2_products.nonce,
				product_ids: part,
			})
				.done(function (res) {
					if (!res || !res.success) {
						var msg =
							res && res.data && res.data.message
								? res.data.message
								: window.hesabix_v2_products.strings.genericError || '';
						appendFeedback('<div class="notice notice-error inline"><p>' + msg + '</p></div>');
					} else if (res.data && res.data.results) {
						res.data.results.forEach(function (row) {
							var cls = row.success ? 'notice-success' : 'notice-error';
							var m = row.message || '';
							appendFeedback(
								'<div class="notice ' +
									cls +
									' inline"><p><strong>#' +
									row.product_id +
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
							(window.hesabix_v2_products.strings.requestFailed || '') +
							'</p></div>'
					);
					next();
				});
		}

		next();
	}

	$(function () {
		$(document).on('click', '.hesabix-v2-product-sync', function () {
			var id = parseInt($(this).data('product-id'), 10);
			if (!id) {
				return;
			}
			if (!window.confirm(window.hesabix_v2_products.strings.confirmSync || '')) {
				return;
			}
			clearFeedback();
			runBatches([id], function () {
				window.location.reload();
			});
		});

		$('#hesabix-v2-products-bulk-sync').on('click', function () {
			var ids = getSelectedProductIds();
			if (!ids.length) {
				return;
			}
			if (!window.confirm(window.hesabix_v2_products.strings.confirmBulkSync || '')) {
				return;
			}
			clearFeedback();
			runBatches(ids, function () {
				window.location.reload();
			});
		});

		$('#hesabix-v2-orphans-select-all').on('change', function () {
			var on = $(this).is(':checked');
			$('#hesabix-v2-orphans-table tbody input.hesabix-v2-orphan-cb:not(:disabled)').prop('checked', on);
		});

		$('#hesabix-v2-orphans-scan').on('click', function () {
			var $btn = $(this);
			$btn.prop('disabled', true);
			clearOrphanFeedback();
			$('#hesabix-v2-orphans-summary').text(orphanStrings().orphanScanning || '…');

			$.post(orphanCfg().ajax_url, {
				action: 'hesabix_v2_orphans_scan',
				nonce: orphanCfg().nonce,
				include_name_heuristics: $('#hesabix-v2-orphans-include-heuristic').is(':checked') ? 1 : 0,
			})
				.done(function (res) {
					if (!res || !res.success) {
						var msg =
							res && res.data && res.data.message
								? res.data.message
								: orphanStrings().genericError || '';
						appendOrphanFeedback('<div class="notice notice-error inline"><p>' + escapeHtml(msg) + '</p></div>');
						setOrphanActionButtonsEnabled(false);
						return;
					}
					appendOrphanFeedback(
						'<div class="notice notice-success inline"><p>' +
							escapeHtml((res.data && res.data.message) || '') +
							'</p></div>'
					);
					renderOrphans(
						(res.data && res.data.candidates) || [],
						(res.data && res.data.counts) || {}
					);
				})
				.fail(function () {
					appendOrphanFeedback(
						'<div class="notice notice-error inline"><p>' +
							escapeHtml(orphanStrings().requestFailed || '') +
							'</p></div>'
					);
				})
				.always(function () {
					$btn.prop('disabled', false);
				});
		});

		$('#hesabix-v2-orphans-dry-run').on('click', function () {
			var ids = getSelectedOrphanIds();
			if (!ids.length) {
				window.alert(orphanStrings().orphanNoSelection || '');
				return;
			}
			if (!window.confirm(orphanStrings().orphanConfirmDryRun || '')) {
				return;
			}
			clearOrphanFeedback();
			runOrphanBatches(ids, true, function () {});
		});

		$('#hesabix-v2-orphans-cleanup').on('click', function () {
			var ids = getSelectedOrphanIds();
			if (!ids.length) {
				window.alert(orphanStrings().orphanNoSelection || '');
				return;
			}
			if (!window.confirm(orphanStrings().orphanConfirmCleanup || '')) {
				return;
			}
			clearOrphanFeedback();
			runOrphanBatches(ids, false, function () {
				appendOrphanFeedback(
					'<div class="notice notice-info inline"><p>' +
						escapeHtml(orphanStrings().orphanDone || '') +
						'</p></div>'
				);
			});
		});
	});
})(jQuery);
