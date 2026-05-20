/**
 * کاتالوگ عمومی — بدون وابستگی به CDN؛ فقط fetch به REST وردپرس.
 */
(function () {
	'use strict';

	function t(key) {
		var S = window.shabakeTamin || {};
		var i = S.i18n || {};
		return i[key] || key;
	}

	function absUrl(path) {
		var base = (window.shabakeTamin && window.shabakeTamin.apiPublicBase) || '';
		if (!path) return '';
		if (/^https?:\/\//i.test(path)) return path;
		if (!base) return path;
		return base.replace(/\/$/, '') + (path.charAt(0) === '/' ? path : '/' + path);
	}

	function esc(s) {
		var d = document.createElement('div');
		d.textContent = s == null ? '' : String(s);
		return d.innerHTML;
	}

	function nl2br(s) {
		return esc(s).replace(/\n/g, '<br />');
	}

	function parseCfg(root) {
		var el = root.querySelector('.st-json-config');
		if (!el || !el.textContent) return {};
		try {
			return JSON.parse(el.textContent);
		} catch (e) {
			return {};
		}
	}

	function fmtPrice(n) {
		if (n === null || n === undefined || n === '') return t('priceNA');
		var x = Number(n);
		if (isNaN(x)) return t('priceNA');
		try {
			return new Intl.NumberFormat('fa-IR').format(x);
		} catch (e) {
			return String(x);
		}
	}

	function fmtCount(n) {
		if (n === Infinity || n === 'Infinity') {
			return '…';
		}
		var x = Number(n);
		if (isNaN(x)) {
			return String(n);
		}
		try {
			return new Intl.NumberFormat('fa-IR').format(x);
		} catch (e2) {
			return String(x);
		}
	}

	function errMsg(payload) {
		if (!payload) return t('errorGeneric');
		if (payload.error && typeof payload.error === 'string') return payload.error;
		var r = payload.remote;
		if (r && r.error && r.error.message) return r.error.message;
		if (r && r.detail && r.detail.error && r.detail.error.message) return r.detail.error.message;
		if (r && r.detail && r.detail.message) return r.detail.message;
		if (r && r.detail && typeof r.detail === 'string') return r.detail;
		return t('errorGeneric');
	}

	function initRoot(root) {
		var cfg = parseCfg(root);
		var rest = (window.shabakeTamin && window.shabakeTamin.restBase) || '';
		var configured = window.shabakeTamin && window.shabakeTamin.configured;
		var grid = root.querySelector('.st-grid');
		var statusEl = root.querySelector('.st-catalog-status');
		var loadBtn = root.querySelector('.st-loadmore');
		var searchInp = root.querySelector('.st-search-input');
		var searchBtn = root.querySelector('.st-search-btn');
		var statsEl = root.querySelector('.st-pub-result-stats');

		if (searchInp) searchInp.placeholder = t('search');

		var skip = 0;
		var take = cfg.take || 20;
		var total = Infinity;
		var loading = false;
		var q = '';

		function updateResultStats() {
			if (!statsEl) return;
			var tpl = t('resultCountTemplate');
			var totStr = total === Infinity ? '…' : fmtCount(total);
			statsEl.textContent = tpl.replace('{shown}', fmtCount(skip)).replace('{total}', totStr);
		}

		function setStatus( msg, isErr, isInfo ) {
			if (!statusEl) return;
			if (!msg) {
				statusEl.hidden = true;
				statusEl.textContent = '';
				statusEl.classList.remove('st-is-error', 'st-is-info');
				return;
			}
			statusEl.hidden = false;
			statusEl.textContent = msg;
			statusEl.classList.toggle('st-is-error', !!isErr);
			statusEl.classList.toggle('st-is-info', !!isInfo && !isErr);
		}

		function setLoading(on) {
			root.classList.toggle('st-is-loading', !!on);
		}

		var provInput = root.querySelector('.st-filter-province');
		var cityInput = root.querySelector('.st-filter-city');
		var filterBtn = root.querySelector('.st-filter-apply');

		function effectiveProvince() {
			if (provInput) return String(provInput.value || '').trim();
			return cfg.province != null && cfg.province !== '' ? String(cfg.province) : '';
		}

		function effectiveCity() {
			if (cityInput) return String(cityInput.value || '').trim();
			return cfg.city != null && cfg.city !== '' ? String(cfg.city) : '';
		}

		function params() {
			var p = new URLSearchParams();
			p.set('skip', String(skip));
			p.set('take', String(take));
			if (cfg.businessId) p.set('business_id', String(cfg.businessId));
			if (cfg.categoryId) p.set('category_id', String(cfg.categoryId));
			var pv = effectiveProvince();
			var cv = effectiveCity();
			if (pv) p.set('province', pv);
			if (cv) p.set('city', cv);
			if (q) p.set('search', q);
			return p.toString();
		}

		function renderItem(row) {
			var p = row.product || {};
			var sup = row.supplier || {};
			var uuid = p.catalog_public_uuid || '';
			var img = p.thumbnail_url || p.image_url || '';
			var imgSrc = img ? absUrl(img) : '';
			var price = fmtPrice(p.base_sales_price);
			var card = document.createElement('article');
			card.className = 'st-card';
			card.dataset.uuid = uuid;
			card.dataset.businessId = String(row.business_id || '');

			var html = '';
			html += '<div class="st-card-img-wrap">';
			if (imgSrc) {
				html += '<img class="st-card-img" src="' + esc(imgSrc) + '" alt="" loading="lazy" />';
			} else {
				html += '<div class="st-card-img st-card-img--ph"></div>';
			}
			html += '</div>';
			html += '<div class="st-card-body">';
			html += '<h3 class="st-card-title">' + esc(p.name || '') + '</h3>';
			if (p.category_name) html += '<div class="st-card-meta">' + esc(p.category_name) + '</div>';
			html += '<div class="st-card-price">' + esc(price) + '</div>';
			if (sup.business_name) html += '<div class="st-card-supplier">' + esc(sup.business_name) + '</div>';
			html += '<div class="st-card-actions">';
			if (cfg.showProductDetails !== false) {
				html += '<button type="button" class="st-btn-details button">' + esc(t('details')) + '</button>';
			}
			html += '<button type="button" class="st-btn-contact button">' + esc(t('contact')) + '</button>';
			html += '</div></div>';
			card.innerHTML = html;
			return card;
		}

		function appendItems(items) {
			if (!grid) return;
			for (var i = 0; i < items.length; i++) {
				grid.appendChild(renderItem(items[i]));
			}
			Array.prototype.forEach.call(grid.querySelectorAll('.st-btn-contact'), function (btn) {
				btn.addEventListener('click', onContactClick);
			});
			Array.prototype.forEach.call(grid.querySelectorAll('.st-btn-details'), function (btn) {
				btn.addEventListener('click', onDetailClick);
			});
		}

		function onContactClick(ev) {
			ev.preventDefault();
			ev.stopPropagation();
			var card = ev.target.closest('.st-card');
			if (!card) return;
			openContactModal({
				businessId: parseInt(card.dataset.businessId, 10),
				productUuid: card.dataset.uuid || null,
			});
		}

		function onDetailClick(ev) {
			ev.preventDefault();
			ev.stopPropagation();
			var card = ev.target.closest('.st-card');
			if (!card) return;
			var id = card.dataset.uuid || '';
			if (id) openProductDetail(id);
		}

		function openProductDetail(uuid) {
			if (!uuid || !configured) {
				if (!configured) window.alert(t('notConfigured'));
				return;
			}
			var overlay = document.createElement('div');
			overlay.className = 'st-modal-overlay st-detail-overlay';
			overlay.setAttribute('role', 'dialog');
			overlay.setAttribute('aria-modal', 'true');
			overlay.innerHTML =
				'<div class="st-modal st-detail-modal">' +
				'<button type="button" class="st-modal-close" aria-label="' +
				esc(t('close')) +
				'">&times;</button>' +
				'<div class="st-detail-loading">' +
				esc(t('loading')) +
				'</div></div>';
			document.body.appendChild(overlay);

			function closeDetail() {
				overlay.remove();
			}
			overlay.querySelector('.st-modal-close').addEventListener('click', closeDetail);
			overlay.addEventListener('click', function (e) {
				if (e.target === overlay) closeDetail();
			});

			fetch(rest + 'product/' + encodeURIComponent(uuid), { credentials: 'same-origin' })
				.then(function (r) {
					return r.json().then(function (j) {
						return { ok: r.ok, json: j };
					});
				})
				.then(function (x) {
					var j = x.json;
					if (!x.ok || !j.ok || !j.data || !j.data.item) throw new Error(errMsg(j));
					var row = j.data.item;
					var p = row.product || {};
					var sup = row.supplier || {};
					var bid = parseInt(row.business_id, 10) || 0;
					var img = p.thumbnail_url || p.image_url || '';
					var imgSrc = img ? absUrl(img) : '';
					var parts = [];
					parts.push(
						'<button type="button" class="st-modal-close" aria-label="' +
							esc(t('close')) +
							'">&times;</button>'
					);
					parts.push('<h2 class="st-modal-title st-detail-title">' + esc(p.name || '') + '</h2>');
					if (imgSrc) {
						parts.push(
							'<div class="st-detail-img-wrap"><img class="st-detail-img" src="' +
								esc(imgSrc) +
								'" alt="" /></div>'
						);
					}
					if (p.category_name) {
						parts.push('<div class="st-detail-meta">' + esc(p.category_name) + '</div>');
					}
					parts.push('<div class="st-detail-price">' + esc(fmtPrice(p.base_sales_price)) + '</div>');
					if (sup.business_name) {
						parts.push(
							'<div class="st-detail-supplier"><strong>' +
								esc(t('supplierLabel')) +
								'</strong> ' +
								esc(sup.business_name) +
								'</div>'
						);
					}
					var addrBits = [];
					if (sup.address) addrBits.push(esc(sup.address));
					var loc = [sup.province, sup.city].filter(Boolean).join(' — ');
					if (loc) addrBits.push(esc(loc));
					if (addrBits.length) {
						parts.push('<div class="st-detail-address">' + addrBits.join('<br />') + '</div>');
					}
					if (sup.show_contact) {
						if (sup.phone) {
							parts.push(
								'<div class="st-detail-phone"><strong>' +
									esc(t('phoneLabel')) +
									'</strong> ' +
									esc(sup.phone) +
									'</div>'
							);
						}
						if (sup.mobile) {
							parts.push(
								'<div class="st-detail-mobile"><strong>' +
									esc(t('mobileLabel')) +
									'</strong> ' +
									esc(sup.mobile) +
									'</div>'
							);
						}
					}
					if (p.main_unit) {
						parts.push(
							'<div class="st-detail-unit"><strong>' +
								esc(t('unitLabel')) +
								'</strong> ' +
								esc(p.main_unit) +
								'</div>'
						);
					}
					if (p.updated_at) {
						parts.push(
							'<div class="st-detail-updated"><strong>' +
								esc(t('updatedLabel')) +
								'</strong> ' +
								esc(p.updated_at) +
								'</div>'
						);
					}
					if (p.description) {
						parts.push(
							'<div class="st-detail-desc-wrap"><strong class="st-detail-desc-label">' +
								esc(t('descriptionLabel')) +
								'</strong><div class="st-detail-desc">' +
								nl2br(p.description) +
								'</div></div>'
						);
					}
					parts.push('<div class="st-detail-actions">');
					if (bid > 0) {
						parts.push(
							'<button type="button" class="button st-detail-contact">' +
								esc(t('contact')) +
								'</button>'
						);
					}
					parts.push('</div>');

					var modal = overlay.querySelector('.st-detail-modal');
					modal.innerHTML = parts.join('');
					modal.querySelector('.st-modal-close').addEventListener('click', closeDetail);
					var cbtn = modal.querySelector('.st-detail-contact');
					if (cbtn) {
						cbtn.addEventListener('click', function () {
							closeDetail();
							openContactModal({ businessId: bid, productUuid: uuid });
						});
					}
				})
				.catch(function (e) {
					var modal = overlay.querySelector('.st-detail-modal');
					modal.innerHTML =
						'<button type="button" class="st-modal-close" aria-label="' +
						esc(t('close')) +
						'">&times;</button>' +
						'<p class="st-detail-error">' +
						esc(e.message || t('detailLoadError')) +
						'</p>';
					modal.querySelector('.st-modal-close').addEventListener('click', closeDetail);
				});
		}

		function openContactModal(ctx) {
			if (!ctx.businessId || isNaN(ctx.businessId) || ctx.businessId < 1) {
				window.alert(t('errorGeneric'));
				return;
			}
			var overlay = document.createElement('div');
			overlay.className = 'st-modal-overlay';
			overlay.innerHTML =
				'<div class="st-modal" role="dialog" aria-modal="true">' +
				'<button type="button" class="st-modal-close" aria-label="' +
				esc(t('close')) +
				'">&times;</button>' +
				'<h2 class="st-modal-title">' +
				esc(t('contact')) +
				'</h2>' +
				'<form class="st-contact-form">' +
				'<label>' +
				esc(t('name')) +
				'<input type="text" name="sender_name" required maxlength="200" /></label>' +
				'<label>' +
				esc(t('contactField')) +
				'<input type="text" name="sender_contact" required maxlength="200" /></label>' +
				'<label>' +
				esc(t('message')) +
				'<textarea name="message" required maxlength="2000" rows="4"></textarea></label>' +
				'<div class="st-captcha-row">' +
				'<img class="st-captcha-img" alt="" />' +
				'<button type="button" class="st-captcha-refresh">' +
				esc(t('refreshCaptcha')) +
				'</button></div>' +
				'<label>' +
				esc(t('captcha')) +
				'<input type="text" name="captcha_code" required maxlength="16" autocomplete="off" /></label>' +
				'<input type="hidden" name="captcha_id" />' +
				'<div class="st-form-status" hidden></div>' +
				'<button type="submit" class="button st-submit">' +
				esc(t('send')) +
				'</button>' +
				'</form></div>';

			document.body.appendChild(overlay);

			var form = overlay.querySelector('.st-contact-form');
			var capImg = overlay.querySelector('.st-captcha-img');
			var capId = form.querySelector('input[name="captcha_id"]');
			var formStatus = overlay.querySelector('.st-form-status');

			function close() {
				overlay.remove();
			}
			overlay.querySelector('.st-modal-close').addEventListener('click', close);
			overlay.addEventListener('click', function (e) {
				if (e.target === overlay) close();
			});

			function loadCaptcha() {
				return fetch(rest + 'captcha', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					credentials: 'same-origin',
					body: '{}',
				})
					.then(function (r) {
						return r.json().then(function (j) {
							return { ok: r.ok, json: j };
						});
					})
					.then(function (x) {
						var j = x.json;
						if (!x.ok || !j.ok || !j.data) throw new Error(errMsg(j));
						capId.value = j.data.captcha_id || '';
						var b64 = j.data.image_base64 || '';
						capImg.src = 'data:image/png;base64,' + b64;
					});
			}

			overlay.querySelector('.st-captcha-refresh').addEventListener('click', function () {
				loadCaptcha().catch(function (e) {
					formStatus.hidden = false;
					formStatus.textContent = e.message || t('errorGeneric');
				});
			});

			loadCaptcha().catch(function (e) {
				formStatus.hidden = false;
				formStatus.textContent = e.message || t('errorGeneric');
			});

			form.addEventListener('submit', function (e) {
				e.preventDefault();
				formStatus.hidden = true;
				var fd = new FormData(form);
				var body = {
					business_id: ctx.businessId,
					sender_name: fd.get('sender_name'),
					sender_contact: fd.get('sender_contact'),
					message: fd.get('message'),
					captcha_id: fd.get('captcha_id'),
					captcha_code: fd.get('captcha_code'),
				};
				if (ctx.productUuid) body.product_catalog_uuid = ctx.productUuid;

				fetch(rest + 'contact', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					credentials: 'same-origin',
					body: JSON.stringify(body),
				})
					.then(function (r) {
						return r.json().then(function (j) {
							return { ok: r.ok, json: j };
						});
					})
					.then(function (x) {
						if (x.json && x.json.ok && x.json.data && x.json.data.saved) {
							formStatus.hidden = false;
							formStatus.classList.remove('st-is-error');
							formStatus.textContent = t('sentOk');
							form.reset();
							loadCaptcha();
							return;
						}
						throw new Error(errMsg(x.json));
					})
					.catch(function (err) {
						formStatus.hidden = false;
						formStatus.classList.add('st-is-error');
						formStatus.textContent = err.message || t('errorGeneric');
						loadCaptcha();
					});
			});
		}

		function load(reset) {
			if (!configured) {
				setStatus(t('notConfigured'), true);
				return;
			}
			if (loading) return;
			loading = true;
			if (reset) {
				skip = 0;
				total = Infinity;
				if (grid) grid.innerHTML = '';
			}
			setStatus('');
			setLoading(true);
			if (loadBtn) loadBtn.disabled = true;

			fetch(rest + 'catalog?' + params(), { credentials: 'same-origin' })
				.then(function (r) {
					return r.json().then(function (j) {
						return { ok: r.ok, json: j };
					});
				})
				.then(function (x) {
					var j = x.json;
					if (!x.ok || !j.ok) throw new Error(errMsg(j));
					var data = j.data || {};
					var items = data.items || [];
					total = typeof data.total_count === 'number' ? data.total_count : total;
					appendItems(items);
					skip += items.length;
					if (loadBtn) {
						loadBtn.hidden = skip >= total;
						loadBtn.disabled = false;
						loadBtn.textContent = t('loadMore');
					}
					if (reset && items.length === 0) {
						setStatus(t('emptyResults'), false, true);
					}
					if (statsEl) {
						updateResultStats();
					}
				})
				.catch(function (e) {
					setStatus(e.message || t('errorGeneric'), true, false);
					if (loadBtn) loadBtn.disabled = false;
				})
				.then(function () {
					loading = false;
					setLoading(false);
				});
		}

		if (loadBtn) {
			loadBtn.addEventListener('click', function () {
				load(false);
			});
		}

		function doSearch() {
			q = searchInp ? String(searchInp.value || '').trim() : '';
			load(true);
		}

		function doApplyLocation() {
			load(true);
		}

		if (filterBtn) {
			filterBtn.addEventListener('click', doApplyLocation);
		}
		function bindEnterApply(el) {
			if (!el) return;
			el.addEventListener('keydown', function (e) {
				if (e.key === 'Enter') {
					e.preventDefault();
					doApplyLocation();
				}
			});
		}
		bindEnterApply(provInput);
		bindEnterApply(cityInput);

		if (searchBtn && searchInp) {
			searchBtn.addEventListener('click', doSearch);
			searchInp.addEventListener('keydown', function (e) {
				if (e.key === 'Enter') {
					e.preventDefault();
					doSearch();
				}
			});
		}

		load(true);
	}

	function boot() {
		var roots = document.querySelectorAll('.st-catalog-root[data-st-root="1"]');
		for (var i = 0; i < roots.length; i++) {
			initRoot(roots[i]);
		}
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', boot);
	} else {
		boot();
	}
})();
