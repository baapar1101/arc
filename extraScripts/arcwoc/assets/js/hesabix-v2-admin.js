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

		summaryRequest: null,

		/**
		 * Initialize
		 */
		init: function() {
			this.bindEvents();
			this.bindChangeBusinessWarning();
			this.initTooltips();
			this.bootstrapConnectionPanels();
		},

		/**
		 * Bind events
		 */
		bindEvents: function() {
			// Test connection
			$(document).on('click', '.hesabix-v2-test-connection', this.testConnection);

			$(document).on('click', '#hesabix-v2-bridge-generate-token', this.bridgeGenerateToken);
		},

		bootstrapConnectionPanels: function() {
			var $settings = $('#hesabix-v2-settings-connection-live');
			var $dash = $('#hesabix-v2-dashboard-connection-extra');

			function fill($container) {
				if (!$container || !$container.length) {
					return;
				}
				var st = hesabix_v2_ajax.strings || {};
				$container.attr('aria-busy', 'true');
				HesabixV2Admin.requestConnectionSummary(function(response) {
					$container.removeAttr('aria-busy');
					if (response.success) {
						$container.html(HesabixV2Admin.buildSnapshotMarkup(response));
					} else {
						$container.html(
							'<p class="hesabix-v2-muted">' + HesabixV2Admin.escapeHtml(st.connection_detail_failed) + '</p>' +
								'<p class="description">' + HesabixV2Admin.escapeHtml(response.message || '') + '</p>'
						);
					}
				});
			}

			fill($settings);
			fill($dash);
		},

		requestConnectionSummary: function(doneCb) {
			if (typeof hesabix_v2_ajax === 'undefined') {
				return;
			}
			if (this.summaryRequest && this.summaryRequest.abort) {
				try {
					this.summaryRequest.abort();
				} catch (e) { /* noop */ }
			}
			this.summaryRequest = $.ajax({
				url: hesabix_v2_ajax.ajax_url,
				type: 'POST',
				data: {
					action: 'hesabix_v2_connection_summary',
					nonce: hesabix_v2_ajax.nonce
				},
				success: function(response) {
					if (typeof doneCb === 'function') {
						doneCb(response || {});
					}
				},
				error: function() {
					if (typeof doneCb === 'function') {
						var st = (hesabix_v2_ajax && hesabix_v2_ajax.strings) ? hesabix_v2_ajax.strings : {};
						doneCb({
							success: false,
							message: st.connection_detail_failed || ''
						});
					}
				}
			});
		},

		escapeHtml: function(value) {
			if (value == null || value === '') {
				return '';
			}
			return $('<span/>').text(String(value)).html();
		},

		buildSnapshotMarkup: function(payload) {
			var st = (hesabix_v2_ajax && hesabix_v2_ajax.strings) ? hesabix_v2_ajax.strings : {};
			if (!payload || !payload.connection) {
				return '<p class="hesabix-v2-muted">' + this.escapeHtml(st.connection_detail_failed) + '</p>';
			}
			var conn = payload.connection || {};
			var rows = [];

			function row(label, value) {
				if (value == null || value === '') {
					return '';
				}
				return '<tr><th scope="row">' + HesabixV2Admin.escapeHtml(label) +
					'</th><td>' + HesabixV2Admin.escapeHtml(value) + '</td></tr>';
			}

			var bid = parseInt(conn.stored_business_id, 10);
			if (!bid) {
				return '<p class="hesabix-v2-muted">' +
					HesabixV2Admin.escapeHtml(st.connection_detail_failed) + '</p>';
			}

			rows.push(row(st.lbl_business_id, String(bid)));

			var b = conn.business;
			if (b && b.name) {
				rows.push(row(st.lbl_linked_business, b.name));
			}
			if (b && b.business_type) {
				rows.push(row(st.lbl_type, b.business_type));
			}
			if (b && b.business_field) {
				rows.push(row(st.lbl_field, b.business_field));
			}
			if (b && (b.role || typeof b.is_owner !== 'undefined')) {
				var rolePart = '';
				if (b.role) {
					rolePart += String(b.role);
				}
				if (b.is_owner && st.lbl_owner_suffix) {
					rolePart += (rolePart ? ' — ' : '') + String(st.lbl_owner_suffix);
				}
				if (rolePart.trim()) {
					rows.push(row(st.lbl_your_role, rolePart.trim()));
				}
			}
			if (conn.owner_display) {
				rows.push(row(st.lbl_owner, conn.owner_display));
			}

			var fy = conn.fiscal_year;
			if (fy && fy.title) {
				var fyLineParts = [];
				fyLineParts.push(String(fy.title));
				if (fy.id) {
					fyLineParts.push('#' + String(fy.id));
				}
				var fyLine = fyLineParts.join(' ');
				if (fy.start_date || fy.end_date) {
					var start = fy.start_date != null ? String(fy.start_date) : '';
					var end = fy.end_date != null ? String(fy.end_date) : '';
					fyLine += ' — ' + start + ' ‒ ' + end;
				}
				rows.push(row(st.lbl_fiscal_current, fyLine.trim()));
			}

			var user = payload.user || {};
			var who = '';
			var fn = (user.first_name || '').trim();
			var ln = (user.last_name || '').trim();
			if (fn || ln) {
				who = (fn + ' ' + ln).trim();
			}
			if (!who && user.email) {
				who = user.email;
			} else if (!who && user.mobile) {
				who = user.mobile;
			}
			if (who || user.id) {
				var uline = who;
				if (user.id) {
					uline += (uline ? ' — ID ' : '') + String(user.id);
				}
				rows.push(row(st.lbl_api_key_owner, uline));
			}

			var notices = '';
			if (conn.business_note) {
				notices += '<p class="hesabix-v2-muted hesabix-v2-connection-note">' +
					this.escapeHtml(conn.business_note) + '</p>';
			}
			if (conn.fiscal_year_note) {
				notices += '<p class="hesabix-v2-muted hesabix-v2-connection-note">' +
					this.escapeHtml(conn.fiscal_year_note) + '</p>';
			}

			var body = notices + '<table class="hesabix-v2-connection-detail-table widefat striped"><tbody>' +
				rows.join('') + '</tbody></table>';
			return body;
		},

		bindChangeBusinessWarning: function() {
			$(document).on('click', '.hesabix-v2-change-connection-trigger', function(e) {
				var dest = $(this).attr('href');
				if (!dest) {
					return;
				}
				e.preventDefault();
				HesabixV2Admin.openChangeBusinessDialog(dest);
			});
		},

		openChangeBusinessDialog: function(destUrl) {
			var st = (hesabix_v2_ajax && hesabix_v2_ajax.strings) ? hesabix_v2_ajax.strings : {};
			var html = ''
				+ '<div class="hesabix-v2-warn-overlay" role="presentation">'
				+ '<div class="hesabix-v2-warn-dialog" role="dialog" aria-labelledby="hesabix-v2-warn-title">'
				+ '<div class="hesabix-v2-warn-dialog__header"><h3 id="hesabix-v2-warn-title">'
				+ this.escapeHtml(st.warn_change_business_title)
				+ '</h3></div>'
				+ '<div class="hesabix-v2-warn-dialog__body"><p>'
				+ this.escapeHtml(st.warn_change_business_body)
				+ '</p></div>'
				+ '<div class="hesabix-v2-warn-dialog__footer">'
				+ '<button type="button" class="button button-primary hesabix-v2-warn-ok">' + this.escapeHtml(st.warn_change_business_ok) + '</button> '
				+ '<button type="button" class="button hesabix-v2-warn-cancel">' + this.escapeHtml(st.warn_change_business_cancel) + '</button>'
				+ '</div></div></div>';

			var $ovl = $(html);
			$('body').append($ovl);

			function teardown() {
				$ovl.remove();
				$(document).off('keydown.hesabixv2warn');
			}

			function go() {
				window.location.href = destUrl;
			}

			$ovl.on('click', function(ev) {
				if (ev.target === $ovl[0]) {
					teardown();
				}
			});

			$ovl.find('.hesabix-v2-warn-cancel').on('click', function() {
				teardown();
			});

			$ovl.find('.hesabix-v2-warn-ok').on('click', function() {
				teardown();
				go();
			});

			$(document).on('keydown.hesabixv2warn', function(ev) {
				if (ev.keyCode === 27) {
					ev.preventDefault();
					teardown();
				}
			});

			setTimeout(function() {
				$ovl.find('.hesabix-v2-warn-cancel').trigger('focus');
			}, 30);
		},

		bridgeGenerateToken: function(e) {
			if (e) {
				e.preventDefault();
			}
			if (typeof hesabix_v2_ajax === 'undefined') {
				return;
			}
			var $btn = $('#hesabix-v2-bridge-generate-token');
			var $out = $('#hesabix-v2-bridge-token-inline');
			$btn.prop('disabled', true);
			$out.text('…');
			$.ajax({
				url: hesabix_v2_ajax.ajax_url,
				type: 'POST',
				data: {
					action: 'hesabix_v2_bridge_generate_token',
					nonce: hesabix_v2_ajax.nonce
				},
				success: function(response) {
					var token = (response && response.data && response.data.token) ? response.data.token : '';
					if (response && response.success && token) {
						$out.html('<strong style="color:#1d2327;">' + HesabixV2Admin.escapeHtml(token) + '</strong>');
					} else {
						var m = (response && response.data && response.data.message) ? response.data.message : '';
						if (!m && response && response.message) {
							m = response.message;
						}
						$out.text(m || 'Error');
					}
				},
				error: function() {
					$out.text('Request failed');
				},
				complete: function() {
					$btn.prop('disabled', false);
				}
			});
		},

		/**
		 * Test API connection
		 */
		testConnection: function(e) {
			if (e) {
				e.preventDefault();
			}

			var $btn = $(this);
			var resultSel = ($btn.attr('data-hesabix-connection-result') || '#connection-result').trim();
			var extraSel = ($btn.attr('data-hesabix-connection-extra') || '#hesabix-v2-dashboard-connection-extra').trim();
			var $result = $(resultSel);
			var extra = $(extraSel);
			var originalText = $btn.data('hesabixOriginalLabel');
			if (typeof originalText !== 'string' || originalText === '') {
				originalText = $btn.text().trim();
				$btn.data('hesabixOriginalLabel', originalText);
			}
			var st = (hesabix_v2_ajax && hesabix_v2_ajax.strings) ? hesabix_v2_ajax.strings : {};
			var testingText = st.testing_connection || '';

			$btn.prop('disabled', true).text(testingText || originalText || '…');
			$result.html('');

			if (extra.length && st.loading_connection_detail) {
				extra.html('<p class="hesabix-v2-muted">' + HesabixV2Admin.escapeHtml(st.loading_connection_detail) + '</p>');
			}

			$.ajax({
				url: hesabix_v2_ajax.ajax_url,
				type: 'POST',
				data: {
					action: 'hesabix_v2_test_connection',
					nonce: hesabix_v2_ajax.nonce
				},
				success: function(response) {
					if (extra.length) {
						if (response.success) {
							extra.html(HesabixV2Admin.buildSnapshotMarkup(response));
						} else if (response.connection) {
							extra.empty();
						}
					}
					var noticeCls = response.success ? 'notice-success' : 'notice-error';
					var msg = HesabixV2Admin.escapeHtml(response.message || (st.error || ''));
					$result.html('<div class="notice ' + noticeCls + '"><p>' + msg + '</p></div>');
				},
				error: function(xhr, status, error) {
					if (extra.length) {
						extra.empty();
					}
					$result.html('<div class="notice notice-error"><p>'
						+ HesabixV2Admin.escapeHtml((st.error || '') + ': ' + (error || status))
						+ '</p></div>');
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
				}
			);
		},

		showLoading: function($element) {
			$element.html('<div class="hesabix-v2-loading">در حال بارگذاری</div>');
		},

		showSuccess: function($element, message) {
			$element.html('<div class="notice notice-success"><p>' + message + '</p></div>');
		},

		showError: function($element, message) {
			$element.html('<div class="notice notice-error"><p>' + message + '</p></div>');
		},

		toPersianNumber: function(num) {
			var persianDigits = '۰۱۲۳۴۵۶۷۸۹';
			return num.toString().replace(/\d/g, function(x) {
				return persianDigits[parseInt(x)];
			});
		}
	};

	$(document).ready(function() {
		HesabixV2Admin.init();

		var $tabWrap = $('.hesabix-v2-settings-tabs');
		if ($tabWrap.length) {
			var $tabs = $tabWrap.find('.nav-tab');
			var $panels = $('.hesabix-v2-tab-panel');
			function activateTab(id) {
				$tabs.removeClass('nav-tab-active').attr('aria-selected', 'false');
				$tabs.filter('[data-tab="' + id + '"]').addClass('nav-tab-active').attr('aria-selected', 'true');
				$panels.attr('hidden', true);
				$panels.filter('[data-tab="' + id + '"]').removeAttr('hidden');
				var $saveWrap = $('#hesabix-v2-settings-save-wrap');
				if ($saveWrap.length) {
					if (id === 'system') {
						$saveWrap.attr('hidden', true);
					} else {
						$saveWrap.removeAttr('hidden');
					}
				}
				if (window.history && window.history.replaceState) {
					window.history.replaceState(null, '', '#hesabix-v2-tab-' + id);
				}
			}
			$tabWrap.on('click', '.nav-tab', function(ev) {
				ev.preventDefault();
				var id = $(this).data('tab');
				if (id) {
					activateTab(id);
				}
			});
			var m = /^#hesabix-v2-tab-(.+)$/.exec(window.location.hash || '');
			if (m && m[1] && $panels.filter('[data-tab="' + m[1] + '"]').length) {
				activateTab(m[1]);
			}
		}

		var $finalizeRow = $('.hesabix-v2-proforma-finalize-settings');
		if ($finalizeRow.length) {
			function hesabixV2ToggleProformaFinalize() {
				var proformaSelected = $('input[name="invoice_doc_mode"][value="proforma"]').is(':checked');
				$finalizeRow.css('display', proformaSelected ? '' : 'none');
			}
			$(document).on('change', 'input[name="invoice_doc_mode"]', hesabixV2ToggleProformaFinalize);
			hesabixV2ToggleProformaFinalize();
		}
	});

	window.HesabixV2Admin = HesabixV2Admin;

})(jQuery);
