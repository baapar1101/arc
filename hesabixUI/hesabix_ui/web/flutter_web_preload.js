/**
 * پیش‌بار منابع Flutter Web + پیام‌های کاربرپسند.
 */
(function () {
  'use strict';

  function resolveUrl(relativePath) {
    try {
      return new URL(relativePath, document.baseURI).href;
    } catch (e) {
      return relativePath;
    }
  }

  function ui() {
    return window.__hesabixLoaderUI;
  }

  function setStatusKey(key) {
    var L = ui();
    if (L && typeof L.setStatusKey === 'function') {
      L.setStatusKey(key);
      return;
    }
    if (L && typeof L.setStatus === 'function') {
      var s = L.t ? L.t() : null;
      if (s && s[key]) L.setStatus(s[key]);
    }
  }

  function setBarOverall(received, total, rangeStart, rangeEnd, step, totalSteps) {
    var L = ui();
    if (!L || typeof L.setDownloadProgress !== 'function') return;
    if (!total || total <= 0) {
      L.setDownloadProgress(null);
      return;
    }
    var frac = Math.min(1, received / total);
    var overall = rangeStart + frac * (rangeEnd - rangeStart);
    if (typeof L.setInitProgress === 'function' && step > 0 && totalSteps > 0) {
      L.setInitProgress(
        Math.min(100, Math.max(0, overall)),
        step,
        totalSteps,
        null
      );
    } else {
      L.setDownloadProgress(Math.min(100, Math.max(0, overall)));
    }
  }

  function setBarEnd(rangeEnd, step, totalSteps, statusKey) {
    var L = ui();
    if (!L) return;
    var percent = Math.min(100, rangeEnd);
    if (typeof L.setInitProgress === 'function' && step > 0 && totalSteps > 0) {
      L.setInitProgress(percent, step, totalSteps, statusKey || null);
      return;
    }
    if (typeof L.setDownloadProgress === 'function') {
      L.setDownloadProgress(percent);
    }
    if (statusKey) setStatusKey(statusKey);
  }

  function setLoadingPhase(p) {
    var L = ui();
    if (L && typeof L.setLoadingPhase === 'function') {
      L.setLoadingPhase(p);
    }
  }

  function browserEngine() {
    if (navigator.vendor === 'Google Inc.' || (navigator.userAgent && navigator.userAgent.indexOf('Edg/') !== -1)) {
      return 'blink';
    }
    if (navigator.vendor === 'Apple Computer, Inc.') return 'webkit';
    if (navigator.vendor === '' && navigator.userAgent && navigator.userAgent.indexOf('Firefox') !== -1) {
      return 'gecko';
    }
    return 'unknown';
  }

  function supportsChromiumCanvasKit() {
    if (typeof Intl === 'undefined' || typeof Intl.Segmenter === 'undefined') return false;
    if (typeof Intl.v8BreakIterator === 'undefined') return false;
    if (typeof ImageDecoder === 'undefined') return false;
    return browserEngine() === 'blink';
  }

  function canvasKitFolderFromConfig(userConfig) {
    var base = (userConfig && userConfig.canvasKitBaseUrl) || 'canvaskit/';
    if (base.charAt(base.length - 1) !== '/') base += '/';
    var useChromium = supportsChromiumCanvasKit();
    if (userConfig && userConfig.canvasKitVariant === 'full') useChromium = false;
    if (userConfig && userConfig.canvasKitVariant === 'chromium') useChromium = true;
    if (useChromium) return base + 'chromium/';
    return base;
  }

  function pickDart2JsBuild(builds) {
    if (!builds || !builds.length) return null;
    for (var i = 0; i < builds.length; i++) {
      var b = builds[i];
      if (b && b.compileTarget === 'dart2js') return b;
    }
    return null;
  }

  async function fetchWithProgress(url, statusKey, rangeStart, rangeEnd, step, totalSteps) {
    setStatusKey(statusKey);
    var res = await fetch(url);
    if (!res.ok) throw new Error(statusKey + ': ' + res.status);
    var total = 0;
    var cl = res.headers.get('Content-Length');
    if (cl) total = parseInt(cl, 10) || 0;

    if (total > 0) {
      setBarOverall(0, 1, rangeStart, rangeEnd, step, totalSteps);
    } else {
      var Lx = ui();
      if (Lx && typeof Lx.setDownloadProgress === 'function') Lx.setDownloadProgress(null);
    }

    var reader = res.body && res.body.getReader();
    if (!reader) {
      await res.arrayBuffer();
      setBarEnd(rangeEnd, step, totalSteps, statusKey);
      return;
    }

    var received = 0;
    for (;;) {
      var stepRead = await reader.read();
      if (stepRead.done) break;
      received += stepRead.value.length;
      if (total > 0) {
        setBarOverall(received, total, rangeStart, rangeEnd, step, totalSteps);
      }
    }
    setBarEnd(rangeEnd, step, totalSteps, statusKey);
  }

  window.__hesabixFlutterWebPreload = async function () {
    var cfg = window._flutter && window._flutter.buildConfig;
    if (!cfg || !cfg.builds) {
      setLoadingPhase(2);
      setStatusKey('statusEngine');
      return;
    }

    var build = pickDart2JsBuild(cfg.builds);
    if (!build || build.compileTarget !== 'dart2js') {
      setLoadingPhase(2);
      setStatusKey('statusEngine');
      return;
    }

    setLoadingPhase(1);
    setStatusKey('statusApp');

    var userConfig = window._flutterConfig || {};
    var mainPath = build.mainJsPath || 'main.dart.js';
    var mainUrl = resolveUrl(mainPath);
    var ckDir = canvasKitFolderFromConfig(userConfig);
    var ckJs = resolveUrl(ckDir + 'canvaskit.js');
    var ckWasm = resolveUrl(ckDir + 'canvaskit.wasm');
    var webTotalSteps = 8;

    await fetchWithProgress(mainUrl, 'statusApp', 0, 42, 1, webTotalSteps);
    await fetchWithProgress(ckJs, 'statusUi', 42, 58, 2, webTotalSteps);
    await fetchWithProgress(ckWasm, 'statusUi', 58, 94, 3, webTotalSteps);

    setLoadingPhase(2);
    setStatusKey('statusEngine');
    var L = ui();
    if (L && typeof L.setInitProgress === 'function') {
      L.setInitProgress(96, 3, webTotalSteps, 'statusEngine');
    } else if (L && typeof L.setDownloadProgress === 'function') {
      L.setDownloadProgress(96);
    }
  };
})();
