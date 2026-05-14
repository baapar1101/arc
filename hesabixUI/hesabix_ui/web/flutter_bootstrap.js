{{flutter_js}}
{{flutter_build_config}}

(function () {
  async function hesabixStartFlutter() {
    if (typeof window.__hesabixFlutterWebPreload === 'function') {
      try {
        await window.__hesabixFlutterWebPreload();
      } catch (e) {
        console.warn('[Hesabix] flutter_web_preload failed, falling back to direct load:', e);
      }
    }
    var swVersion = {{flutter_service_worker_version}};
    var opts = {};
    if (swVersion != null) {
      opts.serviceWorkerSettings = { serviceWorkerVersion: swVersion };
    }
    await _flutter.loader.load(opts);
  }

  hesabixStartFlutter().catch(function (e) {
    console.error('[Hesabix] Flutter bootstrap failed:', e);
  });
})();
