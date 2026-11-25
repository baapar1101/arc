/**
 * Hesabix Help front-end interactions.
 */
(function () {
	'use strict';

	var data = window.hhelpData || {};

	function qs(sel, root) {
		return (root || document).querySelector(sel);
	}

	function qsa(sel, root) {
		return Array.prototype.slice.call((root || document).querySelectorAll(sel));
	}

	/* Tree accordion */
	function initTree() {
		qsa('[data-hhelp-tree] .hx-help-tree__toggle').forEach(function (btn) {
			btn.addEventListener('click', function () {
				var item = btn.closest('.hx-help-tree__item');
				if (!item) return;
				var kids = null;
				var child = item.firstElementChild;
				while (child) {
					if (child.classList && child.classList.contains('hx-help-tree__children')) {
						kids = child;
						break;
					}
					child = child.nextElementSibling;
				}
				var open = item.classList.toggle('is-open');
				btn.setAttribute('aria-expanded', open ? 'true' : 'false');
				if (kids) {
					if (open) kids.removeAttribute('hidden');
					else kids.setAttribute('hidden', '');
				}
			});
		});
	}

	/* Mobile nav drawer */
	function initMobileNav() {
		var sidebar = qs('[data-hhelp-sidebar]');
		if (!sidebar) return;

		function openNav() {
			sidebar.classList.add('is-open');
			var backdrop = qs('[data-hhelp-close-nav]', sidebar);
			if (backdrop) backdrop.removeAttribute('hidden');
			document.body.classList.add('hx-help-nav-open');
		}

		function closeNav() {
			sidebar.classList.remove('is-open');
			qsa('[data-hhelp-close-nav]', sidebar).forEach(function (el) {
				if (el.classList.contains('hx-help-sidebar__backdrop')) {
					el.setAttribute('hidden', '');
				}
			});
			document.body.classList.remove('hx-help-nav-open');
		}

		qsa('[data-hhelp-open-nav]').forEach(function (btn) {
			btn.addEventListener('click', openNav);
		});
		qsa('[data-hhelp-close-nav]').forEach(function (btn) {
			btn.addEventListener('click', closeNav);
		});
	}

	/* Live search (uses WP search via REST-less debounce to search page links via admin-ajax alternative: client navigate) */
	function initLiveSearch() {
		var inputs = qsa('[data-hhelp-live-search]');
		if (!inputs.length) return;

		var timer = null;

		inputs.forEach(function (input) {
			var wrap = input.closest('.hx-help-sidebar__search') || input.closest('.hx-help-hero-search');
			var box = wrap ? qs('[data-hhelp-live-results]', wrap.parentElement || wrap) : null;
			if (!box && wrap) {
				box = document.createElement('div');
				box.className = 'hx-help-live-results';
				box.setAttribute('data-hhelp-live-results', '');
				box.hidden = true;
				wrap.appendChild(box);
			}
			if (!box) return;

			input.addEventListener('input', function () {
				var q = input.value.trim();
				clearTimeout(timer);
				if (q.length < 2) {
					box.hidden = true;
					box.innerHTML = '';
					return;
				}
				box.hidden = false;
				box.innerHTML = '<div style="padding:.6rem .75rem;font-size:.8rem;color:#64748b">' + (data.i18n && data.i18n.searching ? data.i18n.searching : '…') + '</div>';
				timer = setTimeout(function () {
					var url = (data.searchUrl || '/help/search/') + (data.searchUrl && data.searchUrl.indexOf('?') >= 0 ? '&' : '?') + 'q=' + encodeURIComponent(q);
					/* Fetch HTML and parse result links — lightweight without custom REST for v1 */
					fetch(url, { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' } })
						.then(function (r) { return r.text(); })
						.then(function (html) {
							var doc = new DOMParser().parseFromString(html, 'text/html');
							var hits = doc.querySelectorAll('.hx-help-search-hit a');
							if (!hits.length) {
								box.innerHTML = '<div style="padding:.6rem .75rem;font-size:.8rem;color:#64748b">' + (data.i18n && data.i18n.noResults ? data.i18n.noResults : '—') + '</div>';
								return;
							}
							var out = '';
							Array.prototype.slice.call(hits, 0, 8).forEach(function (a) {
								var title = a.querySelector('.hx-help-search-hit__title');
								out += '<a href="' + a.getAttribute('href') + '">' + (title ? title.textContent : a.textContent) + '</a>';
							});
							box.innerHTML = out;
						})
						.catch(function () {
							box.hidden = true;
						});
				}, 280);
			});

			document.addEventListener('click', function (e) {
				if (!wrap.contains(e.target)) {
					box.hidden = true;
				}
			});
		});
	}

	/* Buy now → checkout */
	function initBuyNow() {
		qsa('[data-hhelp-buy]').forEach(function (btn) {
			btn.addEventListener('click', function () {
				var productId = btn.getAttribute('data-product-id');
				var lessonId = btn.getAttribute('data-lesson-id');
				if (!productId || !data.ajaxUrl) return;

				btn.classList.add('is-loading');
				var body = new FormData();
				body.append('action', 'hhelp_buy_now');
				body.append('nonce', data.nonce || '');
				body.append('product_id', productId);
				body.append('lesson_id', lessonId || '0');

				fetch(data.ajaxUrl, { method: 'POST', credentials: 'same-origin', body: body })
					.then(function (r) { return r.json(); })
					.then(function (json) {
						btn.classList.remove('is-loading');
						if (json.success && json.data && json.data.checkoutUrl) {
							window.location.href = json.data.checkoutUrl;
							return;
						}
						if (json.data && json.data.loginUrl) {
							window.location.href = json.data.loginUrl;
							return;
						}
						alert((json.data && json.data.message) || (data.i18n && data.i18n.buyError) || 'Error');
					})
					.catch(function () {
						btn.classList.remove('is-loading');
						alert((data.i18n && data.i18n.buyError) || 'Error');
					});
			});
		});
	}

	/* Smooth scroll for TOC */
	function initToc() {
		qsa('.hx-help-toc a[href^="#"]').forEach(function (a) {
			a.addEventListener('click', function (e) {
				var id = a.getAttribute('href').slice(1);
				var el = document.getElementById(id);
				if (!el) return;
				e.preventDefault();
				el.scrollIntoView({ behavior: 'smooth', block: 'start' });
				history.replaceState(null, '', '#' + id);
			});
		});
	}

	document.addEventListener('DOMContentLoaded', function () {
		initTree();
		initMobileNav();
		initLiveSearch();
		initBuyNow();
		initToc();
	});
})();
