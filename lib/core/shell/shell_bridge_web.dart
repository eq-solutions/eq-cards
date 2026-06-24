import 'dart:async';
import 'dart:html' as html;

// Sends REQUEST_SHELL_TOKEN to the Shell parent frame (core.eq.solutions) and
// waits up to 10s for SHELL_TOKEN_RESPONSE { token_hash }. Returns the hash,
// or null on timeout or if not running inside an iframe.
//
// Called by _SplashScreen when ?shell=1 is detected and there is no GoTrue
// session. Shell responds via mint-cards-otp (generateLink → hashed_token).
// Flutter then calls auth.verifyOTP(tokenHash: hash, type: OtpType.magiclink)
// which creates a real auth.sessions row — no broken setSession(custom_jwt).
Future<String?> requestAndReceiveShellToken() async {
  // Bail if not in an iframe.
  if (html.window.parent == null ||
      identical(html.window.parent, html.window)) {
    return null;
  }

  // Request the token from Shell.
  html.window.parent!.postMessage({'type': 'REQUEST_SHELL_TOKEN'}, '*');

  try {
    final event = await html.window.onMessage
        .firstWhere((e) {
          final data = e.data;
          if (data is! Map) return false;
          final map = data as Map;
          return map['type'] == 'SHELL_TOKEN_RESPONSE' &&
              map['token_hash'] != null;
        })
        .timeout(const Duration(seconds: 10));

    final data = event.data as Map;
    return data['token_hash'] as String?;
  } catch (_) {
    // Timeout or unexpected event shape — fall back to normal auth flow.
    return null;
  }
}
