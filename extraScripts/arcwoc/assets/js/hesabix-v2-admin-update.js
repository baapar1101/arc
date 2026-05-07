(function ($) {
	'use strict';

	var cfg = window.HESABIX_V2_UPD || null;
	var lastDashboard = null;

	function tryParseBootstrap() {
		var el = document.getElementById('hesabix-v2-upd-initial-state');
		if (!el || !el.textContent) {
			return;
		}
		try {
			lastDashboard = JSON.parse(el.textContent);
		} catch (e) {
			lastDashboard = null;
		}
	}

	if (!cfg || !cfg.ajaxUrl || !cfg.nonce) {
		return;
	}

	var strings = cfg.strings || {};

	function labelSource(d) {
		if (!d.configured) {
			return strings.sourceLabelOff || '';
		}
		if (d.configured_raw_zip) {
			return strings.sourceRawZip || '';
		}
		if (d.configured_manifest_only) {
			return strings.sourceManifest || '';
		}
		return strings.sourceMixed || '';
	}

	function labelRequires(d) {
		if (!d.remote_loaded) {
			return strings.requirementsUnknown || '';
		}
		var rw = (d.requires_wp || '').toString().trim();
		var rp = (d.requires_php || '').toString().trim();
		if (!rw && !rp) {
			return strings.requirementsUnknown || '';
		}
		var tmpl = strings.requirementsFmt || '{{w}} / {{p}}';
		var wv = rw || '—';
		var pv = rp || '—';
		return tmpl.replace(/\{\{w\}\}/g, wv).replace(/\{\{p\}\}/g, pv);
	}

	function buildSummary(d) {
		if (!d.configured) {
			return strings.sourceDisabledSummary || '';
		}
		if (!d.remote_loaded) {
			return strings.summaryNoRemote || '';
		}
		if (d.update_available) {
			return strings.summaryUpdateReady || '';
		}
		if (d.newer_than_local && !d.env_compatible) {
			return strings.blockedEnv || '';
		}
		return strings.summaryUpToDate || '';
	}

	function applyState(d) {
		lastDashboard = d;
		var $cur = $('#hesabix-v2-upd-current');
		var $rem = $('#hesabix-v2-upd-remote');
		var $sum = $('#hesabix-v2-upd-summary');
		var $req = $('#hesabix-v2-upd-requires');
		var $src = $('#hesabix-v2-upd-source');
		var $inst = $('#hesabix-v2-upd-install');

		if (!$cur.length) {
			return;
		}

		$cur.text(d.current_version || '');
		if (d.remote_loaded && d.remote_version) {
			$rem.text(String(d.remote_version));
		} else {
			$rem.text(strings.remoteShort || '');
		}
		$sum.text(buildSummary(d));
		$req.text(labelRequires(d));
		$src.text(labelSource(d));

		var can = !!(d.update_available && d.can_install);
		if ($inst.length) {
			$inst.prop('disabled', !can).attr('aria-disabled', can ? 'false' : 'true');
		}
	}

	function ajaxPost(action, extra) {
		return $.ajax({
			url: cfg.ajaxUrl,
			type: 'POST',
			dataType: 'json',
			data: $.extend({ action: action, nonce: cfg.nonce }, extra || {}),
		});
	}

	function setRefreshing(busy) {
		var $btn = $('#hesabix-v2-upd-refresh');
		var $inl = $('#hesabix-v2-upd-inline-status');
		if (!$btn.length) {
			return;
		}
		$btn.prop('disabled', !!busy);
		if (busy) {
			$inl.text(strings.checking || '');
		}
	}

	function doneRefresh() {
		$('#hesabix-v2-upd-refresh').prop('disabled', false);
	}

	function setInstalling(busy) {
		var $inst = $('#hesabix-v2-upd-install');
		var $ref = $('#hesabix-v2-upd-refresh');
		var $inl = $('#hesabix-v2-upd-inline-status');
		if (!$inst.length) {
			return;
		}
		if (busy) {
			$inst.prop('disabled', true).attr('aria-disabled', 'true');
			$ref.prop('disabled', true);
			$inl.text(strings.installing || '');
		} else {
			$ref.prop('disabled', false);
			if (lastDashboard) {
				applyState(lastDashboard);
			}
		}
	}

	$(document).ready(function () {
		if (!$('#hesabix-v2-upd-current').length) {
			return;
		}

		tryParseBootstrap();

		strings.remoteShort = strings.remoteShort || '—';
		strings.genericError = strings.genericError || 'Error';

		$('#hesabix-v2-upd-refresh').on('click', function () {
			setRefreshing(true);
			ajaxPost(cfg.actions.check, { refresh: '1' })
				.done(function (res) {
					var $inl = $('#hesabix-v2-upd-inline-status');
					if (!res || !res.success || !res.data) {
						var mf = strings.genericError;
						if (res && res.data && res.data.message) {
							mf = String(res.data.message);
						}
						$inl.text(mf);
						return;
					}
					applyState(res.data);
					$inl.text('');
				})
				.fail(function (xhr) {
					var msg = strings.genericError;
					if (
						xhr.responseJSON &&
						xhr.responseJSON.data &&
						xhr.responseJSON.data.message
					) {
						msg = String(xhr.responseJSON.data.message);
					}
					$('#hesabix-v2-upd-inline-status').text(msg);
				})
				.always(function () {
					doneRefresh();
				});
		});

		$('#hesabix-v2-upd-install').on('click', function () {
			if ($(this).prop('disabled')) {
				return;
			}
			setInstalling(true);
			var $inl = $('#hesabix-v2-upd-inline-status');
			ajaxPost(cfg.actions.install)
				.done(function (res) {
					if (!res) {
						$inl.text(strings.genericError);
						setInstalling(false);
						return;
					}
					if (!res.success) {
						$inl.text(
							res.data && res.data.message ? String(res.data.message) : strings.genericError
						);
						setInstalling(false);
						return;
					}
					$inl.text(strings.reloadHint || '');
					window.setTimeout(function () {
						window.location.reload();
					}, 550);
				})
				.fail(function (xhr) {
					var msg = strings.genericError;
					if (
						xhr.responseJSON &&
						xhr.responseJSON.data &&
						xhr.responseJSON.data.message
					) {
						msg = String(xhr.responseJSON.data.message);
					}
					$inl.text(msg);
					setInstalling(false);
				});
		});
	});
})(jQuery);
