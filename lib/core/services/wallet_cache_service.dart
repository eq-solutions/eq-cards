import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'wallet_cache_service_io.dart'
    if (dart.library.html) 'wallet_cache_service_web.dart';

/// Reads and writes wallet credential data to the browser's `localStorage` so
/// the wallet screen is usable when the device has no network connectivity.
///
/// Keys:
///   `eq_wallet_licences`      — JSON-encoded List<Map>
///   `eq_wallet_certificates`  — JSON-encoded List<Map>
///
/// Storage is web-only. The platform-specific reads/writes live behind a
/// conditional import — `wallet_cache_service_web.dart` (dart:html) on web and
/// the no-op stub `wallet_cache_service_io.dart` everywhere else — so the Dart
/// VM target used by `flutter test` compiles without pulling in dart:html. On
/// non-web targets every operation is a no-op and [isOffline] reports online.
///
/// Storage persists across page reloads and PWA installs. It is cleared if the
/// user explicitly wipes site data, which is acceptable (the data will
/// re-populate on the next online fetch).
///
/// All reads and writes are best-effort: a failure (e.g. storage quota in
/// private mode) is logged but never surfaced to the user.
class WalletCacheService {
  static const _licencesKey = 'eq_wallet_licences';
  static const _certificatesKey = 'eq_wallet_certificates';

  /// Write the licences list to storage as JSON.
  ///
  /// [rows] should be the raw JSON maps from the repository (the `toJson()`
  /// output of the Licence freezed model). Signed photo URLs are excluded by
  /// the model's `@JsonKey(includeToJson: false)` annotation, which is correct
  /// — signed URLs expire in 1 hour so they are useless in offline cache.
  Future<void> saveLicences(List<Map<String, dynamic>> rows) =>
      _write(_licencesKey, rows);

  /// Read licences from storage. Returns null if nothing is cached.
  Future<List<Map<String, dynamic>>?> loadLicences() => _read(_licencesKey);

  /// Write the certificates list to storage as JSON.
  Future<void> saveCertificates(List<Map<String, dynamic>> rows) =>
      _write(_certificatesKey, rows);

  /// Read certificates from storage. Returns null if nothing is cached.
  Future<List<Map<String, dynamic>>?> loadCertificates() =>
      _read(_certificatesKey);

  /// True when the browser reports no network connectivity.
  ///
  /// Backed by `navigator.onLine` on web; always false on non-web targets
  /// (the import stub reports online).
  static bool get isOffline => walletCacheIsOffline();

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _write(String key, List<Map<String, dynamic>> rows) async {
    try {
      walletCacheWrite(key, jsonEncode(rows));
    } catch (e) {
      // Best-effort. Private mode or quota exceeded — silently ignore.
      debugPrint('[WalletCacheService] write failed for $key: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> _read(String key) async {
    try {
      final raw = walletCacheRead(key);
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
