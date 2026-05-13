(function ($) {
	'use strict';

	function s(key) {
		return (window.hesabix_v2_ob_inv && window.hesabix_v2_ob_inv.strings && window.hesabix_v2_ob_inv.strings[key]) || '';
	}

	function logLine(t) {
		var $log = $('#hesabix_v2_obinv_log');
		$log.show().append(document.createTextNode(t + '\n'));
	}

	function toggleEquityRow() {
		var on = $('#ob_inv_auto_balance').is(':checked');
		$('.hesabix-v2-obinv-equity-row').toggle(on);
	}

	function fillAccountSelects(accounts) {
		var invSel = $('#ob_inv_inventory_account_id');
		var eqSel = $('#ob_inv_equity_account_id');
		var invKeep = invSel.val();
		var eqKeep = eqSel.val();
		var $ini = $('#hesabix-v2-obinv-initial');
		var invInit = parseInt($ini.attr('data-inventory-id') || '0', 10);
		var eqInit = parseInt($ini.attr('data-equity-id') || '0', 10);
		invSel.find('option:not(:first)').remove();
		eqSel.find('option:not(:first)').remove();
		(accounts || []).forEach(function (a) {
			invSel.append($('<option></option>').attr('value', a.id).text(a.label));
			eqSel.append($('<option></option>').attr('value', a.id).text(a.label));
		});
		if (invKeep && invKeep !== '0') {
			invSel.val(invKeep);
		} else if (invInit) {
			invSel.val(String(invInit));
		}
		if (eqKeep && eqKeep !== '0') {
			eqSel.val(eqKeep);
		} else if (eqInit) {
			eqSel.val(String(eqInit));
		}
	}

	function loadAccounts(cb) {
		$('#hesabix_v2_obinv_status').text(s('loadAccounts'));
		$.post(window.hesabix_v2_ob_inv.ajax_url, {
			action: 'hesabix_v2_opening_inventory_accounts',
			nonce: window.hesabix_v2_ob_inv.nonce,
		})
			.done(function (res) {
				if (res && res.success && res.data && res.data.accounts) {
					fillAccountSelects(res.data.accounts);
					if (res.data.message) {
						logLine(res.data.message);
					}
					if (cb) {
						cb(true);
					}
				} else {
					var msg =
						(res && res.data && res.data.message) || s('accountsError');
					if (cb) {
						cb(false, msg);
					}
				}
			})
			.fail(function () {
				if (cb) {
					cb(false, s('requestFail'));
				}
			});
	}

	function validateBeforeConfirm() {
		var inv = parseInt($('#ob_inv_inventory_account_id').val() || '0', 10);
		if (!inv) {
			return s('needInventoryAccount');
		}
		if ($('#ob_inv_auto_balance').is(':checked')) {
			var eq = parseInt($('#ob_inv_equity_account_id').val() || '0', 10);
			if (!eq) {
				return s('needEquity');
			}
		}
		var wh = parseInt($('#ob_inv_warehouse_override').val() || '0', 10);
		if (wh < 1) {
			var savedWh = $('#hesabix_v2_default_warehouse_id').val();
			if (!savedWh || savedWh === '0' || savedWh === '') {
				return s('needWarehouse');
			}
		}
		return null;
	}

	function summarizeConfirm() {
		var tax = $('#ob_inv_include_tax').is(':checked') ? s('taxYes') : s('taxNo');
		var post = $('#ob_inv_do_post').is(':checked') ? s('postYes') : s('postNo');
		var bal = $('#ob_inv_auto_balance').is(':checked') ? s('autoBalYes') : s('autoBalNo');
		var basis = $('#ob_inv_cost_basis option:selected').text();
		var lines = [
			s('confirmIntro'),
			'',
			tax,
			basis,
			bal,
			post,
		];
		return lines.join('\n');
	}

	function collectPayload() {
		return {
			include_tax: $('#ob_inv_include_tax').is(':checked') ? 1 : 0,
			cost_basis: $('#ob_inv_cost_basis').val(),
			auto_balance_to_equity: $('#ob_inv_auto_balance').is(':checked') ? 1 : 0,
			do_post: $('#ob_inv_do_post').is(':checked') ? 1 : 0,
			inventory_account_id: parseInt($('#ob_inv_inventory_account_id').val() || '0', 10),
			equity_account_id: parseInt($('#ob_inv_equity_account_id').val() || '0', 10),
			batch_size: parseInt($('#ob_inv_batch_size').val() || '12', 10),
			warehouse_id: parseInt($('#ob_inv_warehouse_override').val() || '0', 10),
		};
	}

	function runBatches(jobId, onDone) {
		function one() {
			$('#hesabix_v2_obinv_status').text(s('running'));
			$.post(window.hesabix_v2_ob_inv.ajax_url, {
				action: 'hesabix_v2_opening_inventory_batch',
				nonce: window.hesabix_v2_ob_inv.nonce,
				job_id: jobId,
			})
				.done(function (res) {
					if (!res || !res.success) {
						var msg = (res && res.data && res.data.message) || s('genericFail');
						var det = res && res.data && res.data.detail;
						if (det && det.length) {
							det.forEach(function (r) {
								logLine('#' + r.wc_id + ' — ' + (r.message || '') + (r.ok ? ' ✓' : ' ✗'));
							});
						}
						$('#hesabix_v2_obinv_status').text(msg);
						$('#hesabix_v2_obinv_run').prop('disabled', false);
						return;
					}
					var d = res.data || {};
					if (d.cursor != null && d.total != null) {
						logLine((d.cursor || 0) + ' / ' + (d.total || 0));
					}
					if (d.detail && d.detail.length) {
						d.detail.forEach(function (r) {
							logLine('#' + r.wc_id + ' — ' + (r.message || '') + (r.ok ? ' ✓' : ' ✗'));
						});
					}
					if (d.done) {
						finalizeJob(jobId, onDone);
					} else {
						one();
					}
				})
				.fail(function (xhr) {
					var msg = s('requestFail');
					var data = xhr.responseJSON && xhr.responseJSON.data;
					if (data && data.message) {
						msg = data.message;
					}
					if (data && data.detail && data.detail.length) {
						data.detail.forEach(function (r) {
							logLine('#' + r.wc_id + ' — ' + (r.message || ''));
						});
					}
					$('#hesabix_v2_obinv_status').text(msg);
					$('#hesabix_v2_obinv_run').prop('disabled', false);
				});
		}
		one();
	}

	function finalizeJob(jobId, onDone) {
		$('#hesabix_v2_obinv_status').text(s('finalizing'));
		$.post(window.hesabix_v2_ob_inv.ajax_url, {
			action: 'hesabix_v2_opening_inventory_finalize',
			nonce: window.hesabix_v2_ob_inv.nonce,
			job_id: jobId,
		})
			.done(function (res) {
				if (!res || !res.success) {
					var msg = (res && res.data && res.data.message) || s('genericFail');
					$('#hesabix_v2_obinv_status').text(msg);
					$('#hesabix_v2_obinv_run').prop('disabled', false);
					return;
				}
				$('#hesabix_v2_obinv_status').text(res.data && res.data.message ? res.data.message : s('done'));
				if (onDone) {
					onDone();
				}
			})
			.fail(function (xhr) {
				var msg = s('requestFail');
				if (xhr.responseJSON && xhr.responseJSON.data && xhr.responseJSON.data.message) {
					msg = xhr.responseJSON.data.message;
				}
				$('#hesabix_v2_obinv_status').text(msg);
				$('#hesabix_v2_obinv_run').prop('disabled', false);
			});
	}

	$(function () {
		if (!window.hesabix_v2_ob_inv) {
			return;
		}
		if (window.hesabix_v2_ob_inv.completed) {
			return;
		}

		$('#ob_inv_auto_balance').on('change', toggleEquityRow);
		toggleEquityRow();

		$('#hesabix_v2_obinv_load_accounts').on('click', function () {
			loadAccounts(function (ok, err) {
				$('#hesabix_v2_obinv_status').text(ok ? '' : err || s('accountsError'));
			});
		});

		$('.hesabix-v2-settings-tabs').on('click', 'a[data-tab="opening_inv"]', function () {
			loadAccounts(function () {
				$('#hesabix_v2_obinv_status').text('');
			});
		});

		$('#hesabix_v2_obinv_run').on('click', function () {
			var err = validateBeforeConfirm();
			if (err) {
				window.alert(err);
				return;
			}
			if (!window.confirm(s('confirmTitle') + '\n\n' + summarizeConfirm())) {
				return;
			}
			$('#hesabix_v2_obinv_log').empty().hide();
			$('#hesabix_v2_obinv_run').prop('disabled', true);
			var payload = collectPayload();
			$.post(window.hesabix_v2_ob_inv.ajax_url, $.extend({ action: 'hesabix_v2_opening_inventory_prepare', nonce: window.hesabix_v2_ob_inv.nonce }, payload))
				.done(function (res) {
					if (!res || !res.success || !res.data || !res.data.job_id) {
						var msg = (res && res.data && res.data.message) || s('genericFail');
						$('#hesabix_v2_obinv_status').text(msg);
						$('#hesabix_v2_obinv_run').prop('disabled', false);
						return;
					}
					var d = res.data;
					var pre = 'job: ' + d.job_id + ', total: ' + d.total;
					if (d.resumed) {
						pre += ' (' + s('resumedHint') + ')';
					}
					logLine(pre);
					if (d.needs_finalize) {
						if (d.message) {
							$('#hesabix_v2_obinv_status').text(d.message);
						}
						finalizeJob(d.job_id, function () {
							window.location.reload();
						});
						return;
					}
					runBatches(d.job_id, function () {
						window.location.reload();
					});
				})
				.fail(function (xhr) {
					var msg = s('requestFail');
					if (xhr.responseJSON && xhr.responseJSON.data && xhr.responseJSON.data.message) {
						msg = xhr.responseJSON.data.message;
					}
					$('#hesabix_v2_obinv_status').text(msg);
					$('#hesabix_v2_obinv_run').prop('disabled', false);
				});
		});
	});
})(jQuery);
