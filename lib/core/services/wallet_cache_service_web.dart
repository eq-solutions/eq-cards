// Web implementation of [WalletCacheService]'s storage primitives, backed by
// `window.localStorage` and `navigator.onLine`. dart:html lives here behind a
// conditional import so `flutter test` (VM target) doesn't blow up trying to
// resolve it — the conditional import keeps dart:html off the VM target. Same
// pattern as image_download_web.dart.
//
// We deliberately avoid the browser Cache API: dart:html does not expose a
// `Response` constructor, making cache.put() unusable without reaching into
// dart:js_interop. localStorage stores up to ~5 MB of JSON — more than enough
// for a typical wallet (hundreds of licences/certs) and simpler to reason about.
//
// dart:html is the established web-interop library in this codebase; its legacy
// API surfaces deprecated members. All expected on this web-only file.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Reads a raw string entry from `window.localStorage`, or null if absent.
String? walletCacheRead(String key) => html.window.localStorage[key];

/// Writes a raw string entry to `window.localStorage`.
void walletCacheWrite(String key, String value) {
  html.window.localStorage[key] = value;
}

/// Whether the browser reports no network connectivity via `navigator.onLine`.
/// A null value (property unsupported) is treated as online.
bool walletCacheIsOffline() => html.window.navigator.onLine == false;
