// Web implementation of the handoff browser bridge. dart:html lives
// here behind a conditional import so flutter test (VM target) doesn't
// blow up trying to resolve it.

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

class HandoffPlatform {
  static String currentHash() => html.window.location.hash;

  static void replaceHashWithCleanPath() {
    html.window.history.replaceState(null, '', html.window.location.pathname);
  }

  static String currentHostname() => html.window.location.hostname ?? '';

  static bool isInIframe() {
    try {
      return html.window.self != html.window.top;
    } catch (_) {
      // Cross-origin parent: accessing window.top throws SecurityError.
      // That means we're definitely in an iframe.
      return true;
    }
  }

  static void redirectTo(String url) {
    html.window.location.href = url;
  }

  /// Calls /.netlify/functions/shell-verify (same-origin GET) and returns
  /// the minted Supabase JWT if the shell session cookie is valid, or null
  /// on any failure (no cookie, bad sig, network error).
  static Future<String?> fetchShellVerify() async {
    try {
      final req = await html.HttpRequest.request(
        '/.netlify/functions/shell-verify',
        method: 'GET',
        withCredentials: true,
      );
      if (req.status != 200) return null;
      final raw = req.responseText;
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data['token'] as String?;
    } catch (_) {
      return null;
    }
  }
}
