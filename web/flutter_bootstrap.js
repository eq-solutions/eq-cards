{{flutter_js}}
{{flutter_build_config}}

// Service worker enabled for offline wallet support (construction sites with
// no signal). The previous kill-switch (and the one-time legacy purge in
// index.html) removed the old stale SW; the new SW correctly serves the
// current build and also powers the Cache API used by WalletCacheService.
// flutter_service_worker.js is served with Cache-Control: no-store (netlify.toml)
// so the browser always fetches it fresh, preventing the stale-build trap.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
