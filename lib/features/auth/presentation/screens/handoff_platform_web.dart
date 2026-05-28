// Web implementation of the handoff browser bridge. dart:html lives
// here behind a conditional import so flutter test (VM target) doesn't
// blow up trying to resolve it.

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
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

  /// Sends REQUEST_SHELL_TOKEN to the parent shell and waits (up to 5 s) for
  /// SHELL_TOKEN_RESPONSE. Returns the JWT on success, null on timeout or any
  /// error. This is the preferred initial-auth path — the JWT never appears in
  /// the URL hash or browser history, and it works for both the first load and
  /// subsequent 15-min refresh cycles.
  static Future<String?> requestShellToken() async {
    if (!isInIframe()) return null;
    const shellOrigin = 'https://core.eq.solutions';
    final completer = Completer<String?>();

    late StreamSubscription<html.MessageEvent> sub;
    sub = html.window.onMessage.listen((html.MessageEvent event) {
      if (event.origin != shellOrigin) return;
      try {
        final data = event.data;
        String? type;
        String? token;
        if (data is Map) {
          type = data['type'] as String?;
          token = data['token'] as String?;
        } else if (data is String) {
          final decoded = jsonDecode(data) as Map<String, dynamic>?;
          type = decoded?['type'] as String?;
          token = decoded?['token'] as String?;
        }
        if (type != 'SHELL_TOKEN_RESPONSE') return;
        sub.cancel();
        completer.complete(token != null && token.isNotEmpty ? token : null);
      } catch (_) {
        // ignore malformed messages
      }
    });

    try {
      html.window.parent?.postMessage(
        {'type': 'REQUEST_SHELL_TOKEN'},
        shellOrigin,
      );
    } catch (_) {
      sub.cancel();
      return null;
    }

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub.cancel();
        return null;
      },
    );
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