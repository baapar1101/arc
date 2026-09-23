/**
 * Hesabix Web — Initial loader UI (i18n, theme, progress, slow-load extras).
 */
(function () {
  'use strict';

  function storageGetEarly(key) {
    try {
      return localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  function parseStoredEarly(raw) {
    if (raw == null || raw === '') return null;
    try {
      return JSON.parse(raw);
    } catch (e) {
      return raw;
    }
  }

  function readBrandEarly() {
    var raw = storageGetEarly('hesabix_theme_brand');
    if (raw == null || raw === '') return null;
    var parsed = parseStoredEarly(raw);
    var s = String(parsed != null ? parsed : raw).trim();
    if (/^#[0-9A-Fa-f]{6}$/.test(s)) return s.toUpperCase();
    return null;
  }

  var BRAND = readBrandEarly() || '#0F4C81';
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
      statusTimeout: 'راه‌اندازی برنامه طولانی شده است؛ لطفاً تلاش مجدد را بزنید.',
      loadingLanguageSettings: 'در حال بارگذاری تنظیمات زبان…',
      loadingCalendarSettings: 'در حال بارگذاری تنظیمات تقویم…',
      loadingThemeSettings: 'در حال بارگذاری تنظیمات تم…',
      loadingAuthentication: 'در حال بارگذاری احراز هویت…',
      initializing: 'در حال راه‌اندازی…',
      retry: 'تلاش مجدد',
      stepOf: function (current, total) {
        return 'مرحله ' + current + ' از ' + total;
      },
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
      statusTimeout: 'The app is taking longer than expected to start. Please try again.',
      loadingLanguageSettings: 'Loading language settings…',
      loadingCalendarSettings: 'Loading calendar settings…',
      loadingThemeSettings: 'Loading theme settings…',
      loadingAuthentication: 'Loading authentication…',
      initializing: 'Initializing…',
      retry: 'Try again',
      stepOf: function (current, total) {
        return 'Step ' + current + ' of ' + total;
      },
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

  function readBrandFromStorage() {
    var keys = ['hesabix_theme_brand'];
    for (var i = 0; i < keys.length; i++) {
      var raw = storageGet(keys[i]);
      if (raw == null || raw === '') continue;
      var parsed = parseStoredValue(raw);
      var s = String(parsed != null ? parsed : raw).trim();
      if (/^#[0-9A-Fa-f]{6}$/.test(s)) return s.toUpperCase();
    }
    return BRAND;
  }

  function hexToRgba(hex, alpha) {
    var h = String(hex || '').replace('#', '');
    if (h.length !== 6) return 'rgba(15, 76, 129, ' + alpha + ')';
    var r = parseInt(h.slice(0, 2), 16);
    var g = parseInt(h.slice(2, 4), 16);
    var b = parseInt(h.slice(4, 6), 16);
    return 'rgba(' + r + ', ' + g + ', ' + b + ', ' + alpha + ')';
  }

  function applyBrandCss(brand) {
    var root = document.documentElement;
    var b = brand || BRAND;
    root.style.setProperty('--brand', b);
    root.style.setProperty('--brand-soft', hexToRgba(b, 0.14));
    root.style.setProperty('--loader-fill', b);
    root.style.setProperty('--loader-track', hexToRgba(b, 0.1));
    root.style.setProperty('--loader-quote-bg', hexToRgba(b, 0.06));
    root.style.setProperty('--loader-logo-shadow', '0 8px 32px ' + hexToRgba(b, 0.1));
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
    var brand = readBrandFromStorage();
    applyDocumentLocale(loc);
    root.setAttribute('data-loader-theme', dark ? 'dark' : 'light');
    root.setAttribute('data-loader-locale', loc);
    applyBrandCss(brand);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', dark ? '#0B1520' : brand);
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
    var wrap = document.querySelector('.loader-logo-wrap');
    if (logo) {
      logo.src = 'images/logo-light.png';
      logo.alt = 'Hesabix';
      if (dark) {
        logo.style.opacity = '1';
        logo.style.filter = 'none';
        if (wrap) {
          wrap.classList.remove('loader-logo-wrap--tinted');
          wrap.style.removeProperty('--loader-logo-tint');
        }
      } else {
        // سیلوئت سفید مخفی؛ رنگ برند روی wrap با mask
        logo.style.opacity = '0';
        if (wrap) {
          wrap.classList.add('loader-logo-wrap--tinted');
          wrap.style.setProperty('--loader-logo-tint', readBrandFromStorage());
        }
      }
    }
  }

  function applyLoadingPhase(_phase) {
    /* مراحل بصری حذف شد — سازگاری با flutter_web_preload */
  }

  function setDownloadProgress(percent) {
    var wrap = document.getElementById('loading-progress-wrap');
    var bar = document.getElementById('loading-progress-bar');
    var screen = document.getElementById('flutter-loading-screen');
    var percentEl = document.getElementById('loading-percent');
    var spinner = document.getElementById('loader-spinner');
    if (!wrap || !bar) return;

    if (percent == null || typeof percent !== 'number' || isNaN(percent)) {
      wrap.classList.add('is-indeterminate');
      bar.style.width = '0%';
      if (screen) screen.classList.remove('has-definite-progress');
      if (percentEl) percentEl.textContent = '';
      if (spinner) spinner.hidden = false;
      return;
    }

    wrap.classList.remove('is-indeterminate');
    if (screen) screen.classList.add('has-definite-progress');
    var clamped = Math.max(0, Math.min(100, percent));
    bar.style.width = clamped + '%';
    if (percentEl) percentEl.textContent = Math.round(clamped) + '%';
    if (spinner) spinner.hidden = true;
  }

  function setInitProgress(percent, currentStep, totalSteps, statusKey) {
    setDownloadProgress(percent);
    var stepEl = document.getElementById('loading-step');
    if (stepEl && currentStep > 0 && totalSteps > 0) {
      var s = t();
      stepEl.textContent = s.stepOf
        ? s.stepOf(currentStep, totalSteps)
        : currentStep + ' / ' + totalSteps;
    }
    if (statusKey) setStatusKey(statusKey);
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
    setInitProgress: setInitProgress,
    setStatus: setStatus,
    setStatusKey: setStatusKey,
    markSlowLoad: markSlowLoad,
    hide: hideLoadingScreen,
    t: t,
    detectLocale: detectLocale,
  };

  window.__hesabixSignalAppReady = function () {
    setStatusKey('statusDone');
    setInitProgress(100, 8, 8, 'statusDone');
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
      setStatusKey('statusTimeout');
      markSlowLoad();
      showRetry();
    }
  }, 120000);
})();
