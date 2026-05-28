// Non-web stub for the iframe-handoff browser bridge. Cards is
// web-only post-flip, but flutter test runs in the VM target where
// dart:html isn't available. This stub exists so the test runner can
// load IframeHandoffScreen without crashing — every method here just
// returns the not-supported sentinel. The handoff UI gates on kIsWeb
// before calling any of these.

class HandoffPlatform {
  static String currentHash() => '';
  static void replaceHashWithCleanPath() {}
  static String currentHostname() => '';
  static bool isInIframe() => false;
  static void redirectTo(String url) {}
  static Future<String?> requestShellToken() async => null;
  static Future<String?> fetchShellVerify() async => null;
}