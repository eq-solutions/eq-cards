// Web implementation of the handoff browser bridge. dart:html lives
// here behind a conditional import so flutter test (VM target) doesn't
// blow up trying to resolve it.

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

class HandoffPlatform {
  static String currentHash() => html.window.location.hash;

  static void replaceHashWithCleanPath() {
    html.window.history.replaceState(null, '', html.window.location.pathname);
  }

  static String currentHostname() => html.window.location.hostname ?? '';

  static void redirectTo(String url) {
    html.window.location.href = url;
  }
}
