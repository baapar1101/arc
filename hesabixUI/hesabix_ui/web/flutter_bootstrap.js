{{flutter_js}}
{{flutter_build_config}}

(function () {
  function hesabixFlutterConfig() {
    var cfg = window._flutterConfig || {};
    return {
      canvasKitBaseUrl: cfg.canvasKitBaseUrl || 'canvaskit/',
      renderer: cfg.renderer || 'canvaskit',
      useLocalCanvasKit: cfg.useLocalCanvasKit !== false,
      fontFallbackBaseUrl: cfg.fontFallbackBaseUrl || (function () {
        try {
          return new URL('fonts/gstatic/s/', document.baseURI).href;
        } catch (e) {
          return 'fonts/gstatic/s/';
        }
      })()
    };
  }

  async function hesabixStartFlutter() {
    if (typeof window.__hesabixFlutterWebPreload === 'function') {
      try {
        await window.__hesabixFlutterWebPreload();
      } catch (e) {
        console.warn('[Hesabix] flutter_web_preload failed, falling back to direct load:', e);
      }
    }
    // Do not register Flutter's deprecated service worker — it unregisters itself and
    // reloads the page during activation, which races with CanvasKit initialization.
    await _flutter.loader.load({ config: hesabixFlutterConfig() });
  }

  hesabixStartFlutter().catch(function (e) {
    console.error('[Hesabix] Flutter bootstrap failed:', e);
  });
})();
