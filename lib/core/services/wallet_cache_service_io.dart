// Non-web stub for [WalletCacheService]'s storage primitives. Cards' offline
// wallet cache is web-only; the VM target used by `flutter test` (and any
// native build) resolves this stub so the import graph compiles without
// dart:html — same pattern as image_download_io.dart.
//
// Every operation is a no-op: reads return null, writes do nothing, and the
// device is always reported online. Consumers already gate the real calls
// behind `kIsWeb`, so these are never exercised at runtime off the web.

/// Reads a raw cache entry. Always null on non-web targets.
String? walletCacheRead(String key) => null;

/// Writes a raw cache entry. No-op on non-web targets.
void walletCacheWrite(String key, String value) {}

/// Whether the device is offline. Always false on non-web targets.
bool walletCacheIsOffline() => false;
