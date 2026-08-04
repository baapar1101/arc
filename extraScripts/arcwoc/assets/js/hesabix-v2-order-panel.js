/**
 * Order edit screen: refresh invoice profit from Hesabix.
 *
 * @since 4.9.0
 */
(function ($) {
	'use strict';

	function ajaxCfg() {
		return window.hesabix_v2_ajax || {};
	}

	function refreshProfit($btn) {
		var cfg = ajaxCfg();
		if (!cfg.ajax_url) {
			return;
		}
		var orderId = parseInt($btn.data('order-id'), 10);
		if (!orderId) {
			return;
		}
		var st = cfg.strings || {};
		var $panel = $btn.closest('.hesabix-v2-profit-panel');
		$btn.prop('disabled', true);
		var prev = $btn.text();
		$btn.text(st.profit_refreshing || '…');

		$.post(cfg.ajax_url, {
			action: 'hesabix_v2_refresh_order_profit',
			nonce: cfg.nonce,
			order_id: orderId,
		})
			.done(function (res) {
				if (res && res.success && res.data && res.data.html_box) {
					if ($panel.length) {
						$panel.replaceWith(res.data.html_box);
					} else {
						window.location.reload();
					}
					return;
				}
				var msg =
					res && res.data && res.data.message
						? res.data.message
						: st.error || '';
				window.alert(msg);
				$btn.prop('disabled', false).text(prev);
			})
			.fail(function () {
				window.alert(st.error || '');
				$btn.prop('disabled', false).text(prev);
			});
	}

	$(function () {
		$(document).on('click', '.hesabix-v2-refresh-profit', function (e) {
			e.preventDefault();
			refreshProfit($(this));
		});
	});
})(jQuery);
