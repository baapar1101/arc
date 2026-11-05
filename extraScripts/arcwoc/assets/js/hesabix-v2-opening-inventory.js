(function ($) {
	'use strict';

	var accountsCache = [];
	var activeJobId = '';

	function resetActiveJob() {
		activeJobId = '';
		$('#hesabix_v2_obinv_cancel').hide().prop('disabled', false);
		$('#hesabix_v2_obinv_cancel_hint').hide();
	}

	function s(key) {
		return (window.hesabix_v2_ob_inv && window.hesabix_v2_ob_inv.strings && window.hesabix_v2_ob_inv.strings[key]) || '';
	}

	function prereq() {
		return (window.hesabix_v2_ob_inv && window.hesabix_v2_ob_inv.prereq) || {};
	}

	function checklist() {
		if (!window.hesabix_v2_ob_inv) {
			return {};
		}
		if (!window.hesabix_v2_ob_inv.checklist) {
			window.hesabix_v2_ob_inv.checklist = {};
		}
		return window.hesabix_v2_ob_inv.checklist;
	}

	function setPrereqFromResponse(data) {
		if (!window.hesabix_v2_ob_inv || !data) {
			return;
		}
		if (data.prereq) {
			window.hesabix_v2_ob_inv.prereq = data.prereq;
		}
		if (data.checklist) {
			window.hesabix_v2_ob_inv.checklist = data.checklist;
		}
		refreshChecklistUi();
	}

	function refreshWarehouseRowOnly() {
		var c = checklist();
		var def = parseInt($('#hesabix_v2_default_warehouse_id').val() || '0', 10);
		var ov = parseInt($('#ob_inv_warehouse_override').val() || '0', 10);
		c.warehouse = ov > 0 || def > 0;
		refreshChecklistUi();
	}

	function refreshChecklistUi() {
		var c = checklist();
		$('#hesabix_v2_obinv_checklist li[data-key]').each(function () {
			var k = $(this).attr('data-key');
			var ok = !!c[k];
			$(this).toggleClass('is-ok', ok).toggleClass('is-bad', !ok);
		});
	}

	function logLine(t) {
		var $log = $('#hesabix_v2_obinv_log');
		$log.show().append(document.createTextNode(t + '\n'));
	}

	function toggleEquityRow() {
		var on = $('#ob_inv_auto_balance').is(':checked');
		$('.hesabix-v2-obinv-equity-row').toggle(on);
	}

	function accountSearchQuery() {
		return ($('#hesabix_v2_obinv_account_search').val() || '').trim().toLowerCase();
	}

	function filterAccountsList(all, q) {
		var list = all || [];
		if (!q) {
			return list.slice();
		}
		return list.filter(function (a) {
			var lab = (a.label || '').toLowerCase();
			var code = (a.code || '').toLowerCase();
			var name = (a.name || '').toLowerCase();
			var typ = (a.account_type || '').toLowerCase();
			return (
				lab.indexOf(q) !== -1 ||
				code.indexOf(q) !== -1 ||
				name.indexOf(q) !== -1 ||
				typ.indexOf(q) !== -1
			);
		});
	}

	function accountDisplayLabel(a) {
		var base = a.label || '';
		var t = (a.account_type || '').trim();
		if (!t) {
			return base;
		}
		return base + ' — ' + t;
	}

	function ensureSelectedInList(filtered, selectedId, fullList) {
		var sid = parseInt(selectedId || '0', 10);
		if (!sid) {
			return filtered;
		}
		var inF = false;
		for (var i = 0; i < filtered.length; i++) {
			if (parseInt(filtered[i].id, 10) === sid) {
				inF = true;
				break;
			}
		}
		if (inF) {
			return filtered;
		}
		var extra = null;
		(fullList || []).forEach(function (a) {
			if (parseInt(a.id, 10) === sid) {
				extra = a;
			}
		});
		if (!extra) {
			return filtered;
		}
		return [extra].concat(filtered);
	}

	function locCfg() {
		return window.hesabix_v2_ob_inv || {};
	}

	function savedAccountId(kind) {
		var hiddenId = kind === 'inventory' ? '#ob_inv_inventory_account_id_hidden' : '#ob_inv_equity_account_id_hidden';
		var fromHidden = parseInt($(hiddenId).val() || '0', 10);
		if (fromHidden > 0) {
			return fromHidden;
		}
		var loc = locCfg();
		if (kind === 'inventory') {
			return parseInt(loc.savedInventoryAccountId || '0', 10);
		}
		return parseInt(loc.savedEquityAccountId || '0', 10);
	}

	function defaultAccountCodes(kind) {
		var loc = locCfg();
		var list = kind === 'inventory' ? loc.defaultInventoryCodes : loc.defaultEquityCodes;
		return Array.isArray(list) ? list : [];
	}

	function pickDefaultAccountId($sel, codes) {
		var i;
		for (i = 0; i < codes.length; i++) {
			var $opt = $sel.find('option[data-code="' + String(codes[i]) + '"]').first();
			if ($opt.length) {
				return String($opt.val() || '');
			}
		}
		return '';
	}

	function appendAccountOptions($sel, list) {
		(list || []).forEach(function (a) {
			if (!a || !a.id) {
				return;
			}
			var $opt = $('<option></option>').attr('value', String(a.id)).text(accountDisplayLabel(a));
			if (a.code) {
				$opt.attr('data-code', String(a.code));
			}
			$sel.append($opt);
		});
	}

	function applyAccountSelection($sel, wantedId, defaultCodes) {
		var want = parseInt(wantedId || '0', 10);
		if (want > 0) {
			$sel.val(String(want));
		}
		if (!$sel.val() || $sel.val() === '0') {
			var def = pickDefaultAccountId($sel, defaultCodes);
			if (def) {
				$sel.val(def);
			}
		}
	}

	function syncAccountHidden() {
		var inv = parseInt($('#ob_inv_inventory_account_id').val() || '0', 10);
		var eq = parseInt($('#ob_inv_equity_account_id').val() || '0', 10);
		if (inv > 0) {
			$('#ob_inv_inventory_account_id_hidden').val(String(inv));
		}
		if (eq > 0) {
			$('#ob_inv_equity_account_id_hidden').val(String(eq));
		}
	}

	function accountIdFromUi(selectSel, hiddenSel) {
		var v = parseInt($(selectSel).val() || '0', 10);
		if (v > 0) {
			return v;
		}
		return parseInt($(hiddenSel).val() || '0', 10);
	}

	function fillAccountSelects() {
		var invSel = $('#ob_inv_inventory_account_id');
		var eqSel = $('#ob_inv_equity_account_id');
		var invKeep = parseInt(invSel.val() || '0', 10);
		var eqKeep = parseInt(eqSel.val() || '0', 10);
		var invWant = invKeep > 0 ? invKeep : savedAccountId('inventory');
		var eqWant = eqKeep > 0 ? eqKeep : savedAccountId('equity');
		var q = accountSearchQuery();
		var base = filterAccountsList(accountsCache, q);
		var invList = ensureSelectedInList(base, invWant, accountsCache);
		var eqList = ensureSelectedInList(base, eqWant, accountsCache);

		invSel.find('option:not(:first)').remove();
		eqSel.find('option:not(:first)').remove();
		appendAccountOptions(invSel, invList);
		appendAccountOptions(eqSel, eqList);
		applyAccountSelection(invSel, invWant, defaultAccountCodes('inventory'));
		applyAccountSelection(eqSel, eqWant, defaultAccountCodes('equity'));
		syncAccountHidden();
	}

	function loadAccounts(cb, isAuto) {
		if (!isAuto) {
			$('#hesabix_v2_obinv_status').text(s('loadAccounts'));
		}
		$.post(window.hesabix_v2_ob_inv.ajax_url, {
			action: 'hesabix_v2_opening_inventory_accounts',
			nonce: window.hesabix_v2_ob_inv.nonce,
		})
			.done(function (res) {
				if (res && res.success && res.data && res.data.accounts) {
					accountsCache = res.data.accounts;
					setPrereqFromResponse(res.data);
					fillAccountSelects();
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
		var p = prereq();
		if (!p.fiscal_year_id) {
			return s('needFiscalYear');
		}
		if (!p.currency_id) {
			return s('needCurrency');
		}
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
			inventory_account_id: accountIdFromUi('#ob_inv_inventory_account_id', '#ob_inv_inventory_account_id_hidden'),
			equity_account_id: accountIdFromUi('#ob_inv_equity_account_id', '#ob_inv_equity_account_id_hidden'),
			batch_size: parseInt($('#ob_inv_batch_size').val() || '12', 10),
			warehouse_id: parseInt($('#ob_inv_warehouse_override').val() || '0', 10),
		};
	}

	function collectPreviewPayload() {
		return {
			include_tax: $('#ob_inv_include_tax').is(':checked') ? 1 : 0,
			cost_basis: $('#ob_inv_cost_basis').val(),
			batch_size: parseInt($('#ob_inv_batch_size').val() || '12', 10),
			warehouse_id: parseInt($('#ob_inv_warehouse_override').val() || '0', 10),
		};
	}

	function escapeHtml(t) {
		return $('<span/>').text(String(t)).html();
	}

	function renderPreview(data) {
		var $box = $('#hesabix_v2_obinv_preview_box');
		if (!data) {
			$box.empty().attr('hidden', true);
			return;
		}
		var html = '';
		html += '<p><strong>' + escapeHtml(s('previewTitle')) + '</strong></p>';
		html += '<p class="description">' + escapeHtml(s('previewTotal')) + ': <strong>' + escapeHtml(String(data.total)) + '</strong> — ';
		html += escapeHtml(s('previewBatches')) + ': <strong>' + escapeHtml(String(data.batches_est)) + '</strong>';
		if (data.batch_size) {
			html += ' <span dir="ltr">(batch=' + escapeHtml(String(data.batch_size)) + ')</span>';
		}
		html += '</p>';
		if (data.opening_balance_posted) {
			html += '<div class="notice notice-warning inline"><p>' + escapeHtml(s('previewPostedWarn')) + '</p></div>';
		}
		html += '<table><thead><tr>';
		html += '<th>' + escapeHtml(s('previewColProduct')) + '</th>';
		html += '<th>' + escapeHtml(s('previewColQty')) + '</th>';
		html += '<th>' + escapeHtml(s('previewColCost')) + '</th>';
		html += '<th>' + escapeHtml(s('previewColKind')) + '</th>';
		html += '</tr></thead><tbody>';
		(data.samples || []).forEach(function (row) {
			html += '<tr>';
			html += '<td dir="auto">' + escapeHtml(row.name || '') + ' <code dir="ltr\">#' + escapeHtml(String(row.wc_id)) + '</code></td>';
			html += '<td dir="ltr">' + escapeHtml(String(row.qty)) + '</td>';
			html += '<td dir="ltr">' + escapeHtml(String(row.unit_cost)) + '</td>';
			html += '<td>' + escapeHtml(row.kind || '') + '</td>';
			html += '</tr>';
		});
		html += '</tbody></table>';
		$box.html(html).removeAttr('hidden');
	}

	function updateProgress(cursor, total) {
		var $wrap = $('#hesabix_v2_obinv_progress_wrap');
		var $p = $('#hesabix_v2_obinv_progress');
		var $lbl = $('#hesabix_v2_obinv_progress_label');
		if (cursor == null || total == null || total < 1) {
			$wrap.hide();
			return;
		}
		$wrap.show();
		var pct = Math.min(100, Math.round((cursor / total) * 100));
		$p.attr('max', 100).attr('value', pct);
		$lbl.text(String(cursor) + ' / ' + String(total));
	}

	function hideProgress() {
		$('#hesabix_v2_obinv_progress_wrap').hide();
		$('#hesabix_v2_obinv_progress').attr('value', 0);
	}

	function confirmPostIfNeeded() {
		if (!$('#ob_inv_do_post').is(':checked')) {
			return true;
		}
		var phrase = (window.hesabix_v2_ob_inv && window.hesabix_v2_ob_inv.post_confirm_phrase)
			? String(window.hesabix_v2_ob_inv.post_confirm_phrase).trim()
			: '';
		if (!phrase) {
			return window.confirm(s('confirmPostDanger'));
		}
		var typed = window.prompt(s('confirmPostDanger') + '\n\n«' + phrase + '»', '');
		if (typed !== phrase) {
			window.alert(s('confirmPostMismatch'));
			return false;
		}
		return true;
	}

	function runBatches(jobId, onDone) {
		activeJobId = jobId;
		$('#hesabix_v2_obinv_cancel').show();
		$('#hesabix_v2_obinv_cancel_hint').show();
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
						hideProgress();
						resetActiveJob();
						return;
					}
					var d = res.data || {};
					if (d.cancelled) {
						hideProgress();
						var cmsg = d.message || s('stoppedBetweenBatches');
						logLine(cmsg);
						$('#hesabix_v2_obinv_status').text(cmsg);
						$('#hesabix_v2_obinv_run').prop('disabled', false);
						resetActiveJob();
						return;
					}
					if (d.cursor != null && d.total != null) {
						updateProgress(d.cursor, d.total);
						logLine((d.cursor || 0) + ' / ' + (d.total || 0));
					}
					if (d.detail && d.detail.length) {
						d.detail.forEach(function (r) {
							logLine('#' + r.wc_id + ' — ' + (r.message || '') + (r.ok ? ' ✓' : ' ✗'));
						});
					}
					if (d.done) {
						hideProgress();
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
					hideProgress();
					resetActiveJob();
				});
		}
		one();
	}

	function finalizeJob(jobId, onDone) {
		resetActiveJob();
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

		refreshChecklistUi();
		refreshWarehouseRowOnly();

		$('#ob_inv_auto_balance').on('change', toggleEquityRow);
		toggleEquityRow();

		$('#hesabix_v2_default_warehouse_id').on('change', refreshWarehouseRowOnly);
		$('#ob_inv_warehouse_override').on('input change', refreshWarehouseRowOnly);

		$('#ob_inv_inventory_account_id, #ob_inv_equity_account_id').on('change', syncAccountHidden);

		$('#hesabix_v2_obinv_load_accounts').on('click', function () {
			loadAccounts(function (ok, err) {
				$('#hesabix_v2_obinv_status').text(ok ? '' : err || s('accountsError'));
			}, false);
		});

		loadAccounts(function (ok, err) {
			if (!ok) {
				$('#hesabix_v2_obinv_status').text(err || s('accountsError'));
			}
		}, true);

		$('#hesabix_v2_obinv_preview').on('click', function () {
			var $btn = $(this);
			$btn.prop('disabled', true);
			$('#hesabix_v2_obinv_status').text(s('previewLoading'));
			$.post(
				window.hesabix_v2_ob_inv.ajax_url,
				$.extend(
					{ action: 'hesabix_v2_opening_inventory_preview', nonce: window.hesabix_v2_ob_inv.nonce },
					collectPreviewPayload()
				)
			)
				.done(function (res) {
					$btn.prop('disabled', false);
					if (!res || !res.success || !res.data) {
						var msg = (res && res.data && res.data.message) || s('genericFail');
						$('#hesabix_v2_obinv_status').text(msg);
						return;
					}
					setPrereqFromResponse(res.data);
					renderPreview(res.data);
					$('#hesabix_v2_obinv_status').text('');
				})
				.fail(function (xhr) {
					$btn.prop('disabled', false);
					var msg = s('requestFail');
					if (xhr.responseJSON && xhr.responseJSON.data && xhr.responseJSON.data.message) {
						msg = xhr.responseJSON.data.message;
					}
					$('#hesabix_v2_obinv_status').text(msg);
				});
		});

		$('#hesabix_v2_obinv_account_search').on('input', function () {
			if (accountsCache.length) {
				fillAccountSelects();
			}
		});

		$('#hesabix_v2_obinv_copy_log').on('click', function () {
			var el = document.getElementById('hesabix_v2_obinv_log');
			if (!el || !el.textContent || !el.textContent.trim()) {
				window.alert(s('copyLogEmpty'));
				return;
			}
			if (navigator.clipboard && navigator.clipboard.writeText) {
				navigator.clipboard.writeText(el.textContent).then(function () {
					window.alert(s('copyLogDone'));
				}, function () {
					window.alert(s('genericFail'));
				});
			} else {
				var ta = document.createElement('textarea');
				ta.value = el.textContent;
				document.body.appendChild(ta);
				ta.select();
				try {
					document.execCommand('copy');
					window.alert(s('copyLogDone'));
				} catch (e) {
					window.alert(s('genericFail'));
				}
				document.body.removeChild(ta);
			}
		});

		$('.hesabix-v2-settings-tabs').on('click', 'a[data-tab="opening_inv"]', function () {
			if (accountsCache.length) {
				fillAccountSelects();
				return;
			}
			loadAccounts(function (ok, err) {
				$('#hesabix_v2_obinv_status').text(ok ? '' : (err || s('accountsError')));
			}, true);
		});

		$('#hesabix_v2_obinv_run').on('click', function () {
			var err = validateBeforeConfirm();
			if (err) {
				window.alert(err);
				return;
			}
			if (!confirmPostIfNeeded()) {
				return;
			}
			if (!window.confirm(s('confirmTitle') + '\n\n' + summarizeConfirm())) {
				return;
			}
			resetActiveJob();
			$('#hesabix_v2_obinv_log').empty().hide();
			$('#hesabix_v2_obinv_preview_box').empty().attr('hidden', true);
			hideProgress();
			$('#hesabix_v2_obinv_run').prop('disabled', true);
			var payload = collectPayload();
			$.post(window.hesabix_v2_ob_inv.ajax_url, $.extend({ action: 'hesabix_v2_opening_inventory_prepare', nonce: window.hesabix_v2_ob_inv.nonce }, payload))
				.done(function (res) {
					if (!res || !res.success || !res.data || !res.data.job_id) {
						var msg = (res && res.data && res.data.message) || s('genericFail');
						$('#hesabix_v2_obinv_status').text(msg);
						$('#hesabix_v2_obinv_run').prop('disabled', false);
						resetActiveJob();
						return;
					}
					var d = res.data;
					var pre = 'job: ' + d.job_id + ', total: ' + d.total;
					if (d.resumed) {
						pre += ' (' + s('resumedHint') + ')';
					}
					logLine(pre);
					if (d.total != null) {
						updateProgress(d.cursor != null ? d.cursor : 0, d.total);
					}
					if (d.needs_finalize) {
						if (d.message) {
							$('#hesabix_v2_obinv_status').text(d.message);
						}
						hideProgress();
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
					resetActiveJob();
				});
		});

		$('#hesabix_v2_obinv_cancel').on('click', function () {
			if (!activeJobId) {
				return;
			}
			var $btn = $(this);
			$btn.prop('disabled', true);
			$.post(window.hesabix_v2_ob_inv.ajax_url, {
				action: 'hesabix_v2_opening_inventory_cancel',
				nonce: window.hesabix_v2_ob_inv.nonce,
				job_id: activeJobId,
			})
				.done(function (res) {
					$btn.prop('disabled', false);
					if (res && res.success) {
						var m = (res.data && res.data.message) || s('cancelRequestSent');
						logLine(m);
						$('#hesabix_v2_obinv_status').text(s('cancelRequestSent'));
					} else {
						var err = (res && res.data && res.data.message) || s('cancelRunFail');
						window.alert(err);
					}
				})
				.fail(function (xhr) {
					$btn.prop('disabled', false);
					var err = s('cancelRunFail');
					if (xhr.responseJSON && xhr.responseJSON.data && xhr.responseJSON.data.message) {
						err = xhr.responseJSON.data.message;
					}
					window.alert(err);
				});
		});
	});
})(jQuery);
