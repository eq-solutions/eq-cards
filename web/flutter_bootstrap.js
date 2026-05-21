{{flutter_js}}
{{flutter_build_config}}

// Service worker intentionally disabled. Cards is served inside an iframe
// on eq-canonical; aggressive SW caching trapped users on stale builds
// after deploys (old email-OTP screen persisted after the Cards flip).
// Without a SW the browser fetches the versioned main.dart.js directly
// each time — correct for a shell-embedded micro-frontend.
_flutter.loader.load();
