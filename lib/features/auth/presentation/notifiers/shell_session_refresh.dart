import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../../core/supabase/supabase_client_provider.dart';
import '../screens/handoff_platform_io.dart'
    if (dart.library.html) '../screens/handoff_platform_web.dart';

part 'shell_session_refresh.g.dart';

/// Keeps the Shell-minted Supabase JWT fresh while EQ Cards runs inside the
/// EQ Shell iframe.
///
/// Shell JWTs are standalone HS256 access tokens with NO Supabase
/// refresh_token, so the client cannot auto-renew them. Left alone, the
/// session dies at its 15-min TTL and every direct-RPC screen (profile,
/// licences, certs) starts returning 401 / "session expired". This timer
/// re-requests a fresh JWT from the parent shell — the same postMessage
/// handshake the handoff uses — a few minutes before each token expires and
/// applies it via setSession(), so the session never lapses.
///
/// Native / direct-URL (non-iframe) sessions DO carry a refresh_token and
/// rely on Supabase's own auto-refresh, so this is a no-op there.
@Riverpod(keepAlive: true)
class ShellSessionRefresh extends _$ShellSessionRefresh {
  Timer? _timer;

  // Re-mint comfortably inside the 15-min TTL so a slow round-trip never
  // races expiry; on failure retry on [_retryDelay] until it lands.
  static const Duration _refreshInterval = Duration(minutes: 12);
  static const Duration _retryDelay = Duration(seconds: 30);

  @override
  void build() {
    if (!kIsWeb || !HandoffPlatform.isInIframe()) return;
    ref.onDispose(() => _timer?.cancel());
    _schedule(_refreshInterval);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    final client = ref.read(supabaseClientProvider);

    // A null session means pre-handoff or an explicit sign-out — do NOT
    // silently re-establish one; just check back shortly. (An EXPIRED session
    // still returns a non-null currentSession, so it does get refreshed.)
    if (client.auth.currentSession == null) {
      _schedule(_retryDelay);
      return;
    }

    var next = _refreshInterval;
    try {
      final token = await HandoffPlatform.requestShellToken();
      if (token != null && token.isNotEmpty) {
        await client.auth.setSession(token, accessToken: token);
      } else {
        next = _retryDelay; // shell didn't respond — retry before the TTL lapses
      }
    } catch (e, stack) {
      unawaited(Sentry.captureException(e, stackTrace: stack));
      next = _retryDelay;
    }
    _schedule(next);
  }
}
