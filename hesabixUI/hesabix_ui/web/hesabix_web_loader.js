/**
 * Hesabix Web — Initial loader UI (i18n, theme, progress, slow-load extras).
 */
(function () {
  'use strict';

  var BRAND = '#0F4C81';
  var SLOW_MS = 3200;
  var RETRY_MS = 45000;
  var loadStartedAt = Date.now();
  var quoteTimer = null;
  var quoteIndex = 0;
  var appReadySignaled = false;

  var STRINGS = {
    fa: {
      title: 'حسابیکس',
      subtitle: 'حسابداری ابری هوشمند برای کسب‌وکار شما',
      statusDefault: 'در حال بارگذاری…',
      statusApp: 'بارگذاری برنامه…',
      statusUi: 'آماده‌سازی رابط کاربری…',
      statusEngine: 'تقریباً آماده است…',
      statusDone: 'ورود به برنامه…',
      trustCloud: 'دسترسی ابری',
      trustSecure: 'رمزنگاری‌شده',
      trustSupport: 'پشتیبانی ۲۴/۷',
      stepConnect: 'اتصال',
      stepAssets: 'منابع',
      stepReady: 'آماده‌سازی',
      retry: 'تلاش مجدد',
      versionPrefix: 'نسخه',
      quotes: [
        'برای امنیت بیشتر، پس از کار از حساب خود خارج شوید.',
        'نسخهٔ وب را به‌روز نگه دارید تا از آخرین بهبودها بهره ببرید.',
        'ثبت منظم اسناد، پایهٔ گزارش‌های دقیق مالی است.',
        'از پشتیبان‌گیری منظم داده‌های کسب‌وکار غافل نشوید.',
      ],
    },
    en: {
      title: 'Hesabix',
      subtitle: 'Smart cloud accounting for your business',
      statusDefault: 'Loading…',
      statusApp: 'Loading application…',
      statusUi: 'Preparing interface…',
      statusEngine: 'Almost ready…',
      statusDone: 'Starting app…',
      trustCloud: 'Cloud access',
      trustSecure: 'Encrypted',
      trustSupport: '24/7 support',
      stepConnect: 'Connect',
      stepAssets: 'Assets',
      stepReady: 'Prepare',
      retry: 'Try again',
      versionPrefix: 'Version',
      quotes: [
        'Sign out when you finish for better security.',
        'Keep your browser updated for the latest improvements.',
        'Consistent bookkeeping leads to accurate reports.',
        'Back up your business data regularly.',
      ],
    },
  };

  function storageGet(key) {
    try {
      return localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  function detectLocale() {
    var saved = storageGet('flutter.app_locale_code');
    if (saved) {
      var code = saved.split('-')[0].toLowerCase();
      if (code === 'en' || code === 'fa') return code;
    }
    var nav = (navigator.language || 'fa').toLowerCase();
    return nav.indexOf('en') === 0 ? 'en' : 'fa';
  }

  function detectDark() {
    var mode = storageGet('flutter.theme_mode');
    if (mode === '2') return true;
    if (mode === '1') return false;
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function t() {
    var loc = detectLocale();
    return STRINGS[loc] || STRINGS.fa;
  }

  function applyTheme() {
    var root = document.documentElement;
    var dark = detectDark();
    root.setAttribute('data-loader-theme', dark ? 'dark' : 'light');
    root.setAttribute('lang', detectLocale() === 'en' ? 'en' : 'fa');
    root.setAttribute('dir', detectLocale() === 'en' ? 'ltr' : 'rtl');
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', dark ? '#0B1520' : BRAND);
  }

  function applyStaticCopy() {
    var s = t();
    var map = {
      'loader-title': s.title,
      'loading-status': s.statusDefault,
      'loader-step-0-label': s.stepConnect,
      'loader-step-1-label': s.stepAssets,
      'loader-step-2-label': s.stepReady,
      'loader-retry-btn': s.retry,
    };
    Object.keys(map).forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.textContent = map[id];
    });
    var quoteEl = document.getElementById('loading-quote-text');
    if (quoteEl && s.quotes.length) quoteEl.textContent = s.quotes[0];

    document.querySelectorAll('.loader-logo').forEach(function (logo) {
      logo.src = detectDark() ? 'assets/images/logo-light.png' : 'assets/images/logo-blue.png';
    });
  }

  function applyLoadingPhase(phase) {
    var steps = document.querySelectorAll('#flutter-loading-screen .loading-step');
    var p = parseInt(phase, 10);
    if (isNaN(p)) p = 0;
    p = Math.max(0, Math.min(2, p));
    var skel = document.querySelector('.app-skeleton');
    if (skel) skel.setAttribute('data-phase', String(p));
    for (var i = 0; i < steps.length; i++) {
      var el = steps[i];
      var idx = parseInt(el.getAttribute('data-step') || String(i), 10);
      el.classList.remove('is-active', 'is-done');
      if (idx < p) el.classList.add('is-done');
      else if (idx === p) el.classList.add('is-active');
    }
  }

  function setDownloadProgress(percent) {
    var wrap = document.getElementById('loading-progress-wrap');
    var bar = document.getElementById('loading-progress-bar');
    var screen = document.getElementById('flutter-loading-screen');
    if (!wrap || !bar) return;

    if (percent == null || typeof percent !== 'number' || isNaN(percent)) {
      wrap.classList.add('is-indeterminate');
      bar.style.width = '0%';
      if (screen) screen.classList.remove('has-definite-progress');
      return;
    }

    wrap.classList.remove('is-indeterminate');
    if (screen) screen.classList.add('has-definite-progress');
    var clamped = Math.max(0, Math.min(100, percent));
    bar.style.width = clamped + '%';
    var pctEl = document.getElementById('loading-progress-pct');
    if (pctEl) {
      pctEl.textContent = Math.round(clamped) + '%';
      pctEl.setAttribute('aria-hidden', 'false');
    }
  }

  function setStatus(line) {
    var el = document.getElementById('loading-status');
    if (el && line) el.textContent = line;
  }

  function setStatusKey(key) {
    var s = t();
    if (s[key]) setStatus(s[key]);
  }

  function startQuoteRotation() {
    if (quoteTimer) return;
    var el = document.getElementById('loading-quote-text');
    if (!el) return;
    var s = t();
    quoteTimer = setInterval(function () {
      quoteIndex = (quoteIndex + 1) % s.quotes.length;
      el.textContent = s.quotes[quoteIndex];
    }, 9000);
  }

  function stopQuoteRotation() {
    if (quoteTimer) {
      clearInterval(quoteTimer);
      quoteTimer = null;
    }
  }

  function markSlowLoad() {
    var screen = document.getElementById('flutter-loading-screen');
    if (screen && !screen.classList.contains('is-slow')) {
      screen.classList.add('is-slow');
      var quote = document.getElementById('loading-quote');
      if (quote) quote.setAttribute('aria-hidden', 'false');
      startQuoteRotation();
    }
  }

  function showRetry() {
    var btn = document.getElementById('loader-retry-wrap');
    if (btn) btn.hidden = false;
  }

  function fetchVersionLabel() {
    fetch('version.json?t=' + Date.now(), { cache: 'no-store', credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) {
        var build = j && typeof j.build === 'string' ? j.build : '';
        var el = document.getElementById('loader-version');
        if (el && build) {
          el.textContent = t().versionPrefix + ' ' + build.slice(0, 12);
        }
      })
      .catch(function () {});
  }

  function hideLoadingScreen() {
    if (appReadySignaled) return;
    appReadySignaled = true;
    var loadingScreen = document.getElementById('flutter-loading-screen');
    if (!loadingScreen) return;
    stopQuoteRotation();
    loadingScreen.setAttribute('aria-busy', 'false');
    loadingScreen.classList.add('is-exiting');
    loadingScreen.classList.add('hidden');
    var dark = detectDark();
    try {
      document.body.style.backgroundColor = dark ? '#101c2a' : '#f4f7fb';
    } catch (_) {}
    setTimeout(function () {
      loadingScreen.remove();
      document.body.classList.add('flutter-ready');
    }, 460);
  }

  window.__hesabixLoaderUI = {
    setLoadingPhase: applyLoadingPhase,
    setDownloadProgress: setDownloadProgress,
    setStatus: setStatus,
    setStatusKey: setStatusKey,
    markSlowLoad: markSlowLoad,
    hide: hideLoadingScreen,
    t: t,
    detectLocale: detectLocale,
  };

  window.__hesabixSignalAppReady = function () {
    setStatusKey('statusDone');
    setDownloadProgress(100);
    hideLoadingScreen();
  };

  function onDomReady() {
    applyTheme();
    applyStaticCopy();
    applyLoadingPhase(0);
    fetchVersionLabel();

    setTimeout(function () {
      applyLoadingPhase(1);
    }, 350);

    setTimeout(markSlowLoad, SLOW_MS);
    setTimeout(showRetry, RETRY_MS);

    if (window.matchMedia) {
      var mq = window.matchMedia('(prefers-color-scheme: dark)');
      var onScheme = function () {
        var mode = storageGet('flutter.theme_mode');
        if (mode === null || mode === '0') {
          applyTheme();
          applyStaticCopy();
        }
      };
      if (typeof mq.addEventListener === 'function') {
        mq.addEventListener('change', onScheme);
      } else if (typeof mq.addListener === 'function') {
        mq.addListener(onScheme);
      }
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onDomReady);
  } else {
    onDomReady();
  }

  window.addEventListener('flutter-first-frame', function () {
    setTimeout(function () {
      var screen = document.getElementById('flutter-loading-screen');
      if (screen && !screen.classList.contains('hidden') && !appReadySignaled) {
        setStatusKey('statusEngine');
      }
    }, 80);
  }, { once: true });

  setTimeout(function () {
    var screen = document.getElementById('flutter-loading-screen');
    if (screen && !screen.classList.contains('hidden') && !appReadySignaled) {
      console.warn('[Hesabix] Loader fallback timeout');
      hideLoadingScreen();
    }
  }, 120000);
})();
