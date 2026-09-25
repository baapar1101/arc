/**
 * پیش‌بار منابع سنگین Flutter Web با fetch و به‌روزرسانی UI لودینگ (متن، نوار، مرحله).
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

  function formatBytes(n) {
    if (n < 1024) return n + ' B';
    if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
    return (n / 1048576).toFixed(2) + ' MB';
  }

  function ui() {
    return window.__hesabixLoaderUI;
  }

  function setStatus(line) {
    var el = document.getElementById('loading-status');
    if (el) el.textContent = line;
  }

  function setBarOverall(received, total, rangeStart, rangeEnd) {
    var L = ui();
    if (!L || typeof L.setDownloadProgress !== 'function') return;
    if (!total || total <= 0) {
      L.setDownloadProgress(null);
      return;
    }
    var frac = Math.min(1, received / total);
    var overall = rangeStart + frac * (rangeEnd - rangeStart);
    L.setDownloadProgress(Math.min(100, Math.max(0, overall)));
  }

  function setBarEnd(rangeEnd) {
    var L = ui();
    if (L && typeof L.setDownloadProgress === 'function') {
      L.setDownloadProgress(Math.min(100, rangeEnd));
    }
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

  async function fetchWithProgress(url, label, rangeStart, rangeEnd) {
    var res = await fetch(url);
    if (!res.ok) throw new Error(label + ': ' + res.status);
    var total = 0;
    var cl = res.headers.get('Content-Length');
    if (cl) total = parseInt(cl, 10) || 0;

    if (total > 0) {
      setBarOverall(0, 1, rangeStart, rangeEnd);
    } else {
      var Lx = ui();
      if (Lx && typeof Lx.setDownloadProgress === 'function') Lx.setDownloadProgress(null);
    }

    var reader = res.body && res.body.getReader();
    if (!reader) {
      await res.arrayBuffer();
      setBarEnd(rangeEnd);
      setStatus(label + ' — انجام شد');
      return;
    }

    var received = 0;
    for (;;) {
      var step = await reader.read();
      if (step.done) break;
      var chunk = step.value;
      received += chunk.length;
      if (total > 0) {
        setBarOverall(received, total, rangeStart, rangeEnd);
        var pct = Math.min(100, Math.round((received / total) * 100));
        setStatus(label + ' — ' + pct + '% (' + formatBytes(received) + ' / ' + formatBytes(total) + ')');
      } else {
        setStatus(label + ' — ' + formatBytes(received));
      }
    }
    setBarEnd(rangeEnd);
    setStatus(label + ' — انجام شد');
  }

  window.__hesabixFlutterWebPreload = async function () {
    var cfg = window._flutter && window._flutter.buildConfig;
    if (!cfg || !cfg.builds) {
      setLoadingPhase(2);
      return;
    }

    var build = pickDart2JsBuild(cfg.builds);
    if (!build || build.compileTarget !== 'dart2js') {
      setLoadingPhase(2);
      return;
    }

    setLoadingPhase(1);

    var userConfig = window._flutterConfig || {};
    var mainPath = build.mainJsPath || 'main.dart.js';
    var mainUrl = resolveUrl(mainPath);
    var ckDir = canvasKitFolderFromConfig(userConfig);
    var ckJs = resolveUrl(ckDir + 'canvaskit.js');
    var ckWasm = resolveUrl(ckDir + 'canvaskit.wasm');

    setStatus('در حال دریافت ' + mainPath + '…');
    await fetchWithProgress(mainUrl, mainPath, 0, 38);
    setStatus('در حال دریافت canvaskit.js…');
    await fetchWithProgress(ckJs, 'canvaskit.js', 38, 48);
    setStatus('در حال دریافت canvaskit.wasm…');
    await fetchWithProgress(ckWasm, 'canvaskit.wasm', 48, 92);

    setLoadingPhase(2);
    setStatus('آماده‌سازی موتور Flutter…');
    var L = ui();
    if (L && typeof L.setDownloadProgress === 'function') {
      L.setDownloadProgress(100);
    }
  };
})();
