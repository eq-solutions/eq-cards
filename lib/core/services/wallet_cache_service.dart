// dart:html is the established web-interop library in this codebase — see
// lib/core/utils/image_download_web.dart for the same pattern. The newer
// package:web + dart:js_interop approach requires a separate conditional
// import setup that would add significant scaffolding; dart:html works
// correctly on all Flutter web targets supported by this app.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
//
// Web-only offline cache for wallet data (licences + certificates).
// Uses dart:html window.localStorage — same pattern as the SW legacy-purge
// flag in index.html and the existing image_download_web.dart usage of dart:html.
//
// We deliberately avoid the browser Cache API here because dart:html does not
// expose a `Response` constructor, making cache.put() unusable without reaching
// into js_util / dart:js_interop. localStorage stores up to ~5 MB of JSON —
// more than enough for a typical wallet (hundreds of licences/certs) and
// simpler to test in both web and headless environments.

import 'dart:convert';

import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Reads and writes wallet credential data to `window.localStorage` so the
/// wallet screen is usable when the device has no network connectivity.
///
/// Keys:
///   `eq_wallet_licences`      — JSON-encoded List<Map>
///   `eq_wallet_certificates`  — JSON-encoded List<Map>
///
/// Storage persists across page reloads and PWA installs. It is cleared if
/// the user explicitly wipes site data, which is acceptable (the data will
/// re-populate on the next online fetch).
///
/// All reads and writes are best-effort: a failure (e.g. storage quota in
/// private mode) is logged but never surfaced to the user.
class WalletCacheService {
  static const _licencesKey = 'eq_wallet_licences';
  static const _certificatesKey = 'eq_wallet_certificates';

  /// Write the licences list to localStorage as JSON.
  ///
  /// [rows] should be the raw JSON maps from the repository (the `toJson()`
  /// output of the Licence freezed model). Signed photo URLs are excluded by
  /// the model's `@JsonKey(includeToJson: false)` annotation, which is correct
  /// — signed URLs expire in 1 hour so they are useless in offline cache.
  Future<void> saveLicences(List<Map<String, dynamic>> rows) =>
      _write(_licencesKey, rows);

  /// Read licences from localStorage. Returns null if nothing is cached.
  Future<List<Map<String, dynamic>>?> loadLicences() => _read(_licencesKey);

  /// Write the certificates list to localStorage as JSON.
  Future<void> saveCertificates(List<Map<String, dynamic>> rows) =>
      _write(_certificatesKey, rows);

  /// Read certificates from localStorage. Returns null if nothing is cached.
  Future<List<Map<String, dynamic>>?> loadCertificates() =>
      _read(_certificatesKey);

  /// True when the browser reports no network connectivity.
  ///
  /// Uses `navigator.onLine` — synchronous, no async overhead.
  /// Null (browser doesn't support the property) is treated as online.
  static bool get isOffline {
    if (!kIsWeb) return false;
    return html.window.navigator.onLine == false;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _write(String key, List<Map<String, dynamic>> rows) async {
    try {
      html.window.localStorage[key] = jsonEncode(rows);
    } catch (e) {
      // Best-effort. Private mode or quota exceeded — silently ignore.
      debugPrint('[WalletCacheService] write failed for $key: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> _read(String key) async {
    try {
      final raw = html.window.localStorage[key];
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('[WalletCacheService] read failed for $key: $e');
      return null;
    }
  }
}
