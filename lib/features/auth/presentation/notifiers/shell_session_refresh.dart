import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

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

  // Re-mint at 9 min, well inside the 15-min TTL and before Supabase's own
  // auto-refresh fires (it fires at ~70 % of TTL = 10.5 min). If we let
  // Supabase's auto-refresh run first it tries to use the shell JWT as a
  // refresh_token, which the server rejects with "Refresh token invalid".
  static const Duration _refreshInterval = Duration(minutes: 9);
  static const Duration _retryDelay = Duration(seconds: 30);

  @override
  void build() {
    if (!kIsWeb || !HandoffPlatform.isInIframe()) return;
    ref.onDispose(() => _timer?.cancel());
    _schedule(_refreshInterval);

    // Safety-net: if Supabase's auto-refresh fires before our timer (shouldn't
    // happen with the 9-min interval, but belt-and-suspenders) it will try to
    // use the shell JWT as a refresh_token → 401 → signedOut. Catch that and
    // immediately re-request a fresh shell token.
    final client = ref.read(supabaseClientProvider);
    final authSub = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        _timer?.cancel();
        unawaited(_tick());
      }
    });
    ref.onDispose(() => unawaited(authSub.cancel()));
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    final client = ref.read(supabaseClientProvider);
    // In iframe context always try to get a fresh shell token — even if the
    // session is null (which happens when Supabase's auto-refresh fails and
    // fires signedOut). The shell's response is the true gate: if it returns
    // a token we re-establish; if it returns null the user has intentionally
    // signed out of the shell and we let the app redirect to auth.
    var next = _refreshInterval;
    try {
      final token = await HandoffPlatform.requestShellToken();
      if (token != null && token.isNotEmpty) {
        await client.auth.setSession(token, accessToken: token);
      } else {
        next = _retryDelay;
      }
    } catch (e, stack) {
      unawaited(Sentry.captureException(e, stackTrace: stack));
      next = _retryDelay;
    }
    _schedule(next);
  }
}
