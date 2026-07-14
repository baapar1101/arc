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
      tagline: 'حسابداری ابری هوشمند برای کسب‌وکار شما',
      statusDefault: 'در حال بارگذاری…',
      statusApp: 'بارگذاری برنامه…',
      statusUi: 'آماده‌سازی رابط کاربری…',
      statusEngine: 'تقریباً آماده است…',
      statusDone: 'ورود به برنامه…',
      retry: 'تلاش مجدد',
      quotes: [
        'برای امنیت بیشتر، پس از کار از حساب خود خارج شوید.',
        'ثبت منظم اسناد، پایهٔ گزارش‌های دقیق مالی است.',
        'از پشتیبان‌گیری منظم داده‌های کسب‌وکار غافل نشوید.',
      ],
    },
    en: {
      title: 'Hesabix',
      tagline: 'Smart cloud accounting for your business',
      statusDefault: 'Loading…',
      statusApp: 'Loading application…',
      statusUi: 'Preparing interface…',
      statusEngine: 'Almost ready…',
      statusDone: 'Starting app…',
      retry: 'Try again',
      quotes: [
        'Sign out when you finish for better security.',
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

  /** Flutter web SharedPreferences مقادیر را JSON-encoded ذخیره می‌کند. */
  function parseStoredValue(raw) {
    if (raw == null || raw === '') return null;
    try {
      return JSON.parse(raw);
    } catch (e) {
      return raw;
    }
  }

  function normalizeLangCode(value) {
    if (value == null) return null;
    var s = String(value).trim().replace(/^["']|["']$/g, '');
    if (!s) return null;
    var code = s.split('-')[0].toLowerCase();
    if (code === 'en' || code === 'fa') return code;
    return null;
  }

  function readLocaleFromStorage() {
    var keys = [
      'hesabix_locale',
      'flutter.app_locale_code',
      'flutter.String.app_locale_code',
    ];
    for (var i = 0; i < keys.length; i++) {
      var raw = storageGet(keys[i]);
      var parsed = parseStoredValue(raw);
      var code = normalizeLangCode(parsed != null ? parsed : raw);
      if (code) return code;
    }
    return null;
  }

  function detectLocale() {
    var fromStorage = readLocaleFromStorage();
    if (fromStorage) return fromStorage;
    return 'fa';
  }

  function readThemeModeFromStorage() {
    var keys = ['hesabix_theme_mode', 'flutter.theme_mode'];
    for (var i = 0; i < keys.length; i++) {
      var raw = storageGet(keys[i]);
      if (raw == null || raw === '') continue;
      var parsed = parseStoredValue(raw);
      var n = parseInt(parsed != null ? parsed : raw, 10);
      if (!isNaN(n) && n >= 0 && n <= 2) return n;
    }
    return null;
  }

  function detectDark() {
    var mode = readThemeModeFromStorage();
    if (mode === 2) return true;
    if (mode === 1) return false;
    if (mode === 0) {
      return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    }
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function applyDocumentLocale(loc) {
    var isEn = loc === 'en';
    var root = document.documentElement;
    root.setAttribute('lang', isEn ? 'en' : 'fa');
    root.setAttribute('dir', isEn ? 'ltr' : 'rtl');
    if (document.body) {
      document.body.setAttribute('dir', isEn ? 'ltr' : 'rtl');
    }
    var screen = document.getElementById('flutter-loading-screen');
    if (screen) screen.setAttribute('dir', isEn ? 'ltr' : 'rtl');
  }

  function t() {
    var loc = detectLocale();
    return STRINGS[loc] || STRINGS.fa;
  }

  function applyTheme() {
    var root = document.documentElement;
    var loc = detectLocale();
    var dark = detectDark();
    applyDocumentLocale(loc);
    root.setAttribute('data-loader-theme', dark ? 'dark' : 'light');
    root.setAttribute('data-loader-locale', loc);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', dark ? '#0B1520' : BRAND);
  }

  function applyStaticCopy() {
    var s = t();
    var dark = detectDark();
    var map = {
      'loader-title': s.title,
      'loader-tagline': s.tagline,
      'loading-status': s.statusDefault,
      'loader-retry-btn': s.retry,
    };
    Object.keys(map).forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.textContent = map[id];
    });
    var quoteEl = document.getElementById('loading-quote-text');
    if (quoteEl && s.quotes.length) quoteEl.textContent = s.quotes[0];

    var logo = document.querySelector('.loader-logo');
    if (logo) {
      logo.src = dark ? 'assets/images/logo-light.png' : 'assets/images/logo-blue.png';
    }
  }

  function applyLoadingPhase(_phase) {
    /* مراحل بصری حذف شد — سازگاری با flutter_web_preload */
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

  function hideLoadingScreen() {
    if (appReadySignaled) return;
    appReadySignaled = true;
    var loadingScreen = document.getElementById('flutter-loading-screen');
    if (!loadingScreen) return;
    stopQuoteRotation();
    loadingScreen.setAttribute('aria-busy', 'false');
    loadingScreen.classList.add('hidden');
    setTimeout(function () {
      loadingScreen.remove();
      document.body.classList.add('flutter-ready');
    }, 420);
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
    setTimeout(markSlowLoad, SLOW_MS);
    setTimeout(showRetry, RETRY_MS);
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
