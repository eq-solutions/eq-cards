import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client_provider.dart';

part 'shell_session_refresh.g.dart';

/// Proactive session refresh for EQ Cards.
///
/// Phone-OTP sessions carry a real GoTrue refresh_token, so GoTrue's built-in
/// auto-refresh handles renewal. This timer fires a few minutes before the
/// GoTrue JWT expires as a belt-and-suspenders fallback for cases where the
/// auto-refresh timer lagged (e.g. device sleep / backgrounded tab).
///
/// Only active on web in-iframe context (where background-tab throttling most
/// often causes the lag). Native and direct-URL builds rely on Supabase's own
/// auto-refresh exclusively.
@Riverpod(keepAlive: true)
class ShellSessionRefresh extends _$ShellSessionRefresh {
  Timer? _timer;

  // Fire at 7 min — well before the 15-min GoTrue TTL expires, and a couple
  // minutes ahead of Supabase's own auto-refresh (~10.5 min). Gives headroom
  // for device sleep / backgrounded tab delaying the internal timer.
  static const Duration _refreshInterval = Duration(minutes: 7);
  static const Duration _retryDelay = Duration(seconds: 30);

  @override
  void build() {
    if (!kIsWeb) return;
    ref.onDispose(() => _timer?.cancel());
    _schedule(_refreshInterval);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _tick);
  }

  bool _isRefreshTokenFailure(AuthException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('refresh token') ||
        msg.contains('token not found') ||
        e.code == 'refresh_token_not_found';
  }

  Future<void> _tick() async {
    final client = ref.read(supabaseClientProvider);
    // Skip when there is no session — firing with no session throws
    // AuthSessionMissingException, which is not worth capturing.
    if (client.auth.currentSession == null) {
      _schedule(_refreshInterval);
      return;
    }
    // Phone-OTP sessions carry a real GoTrue refresh_token; use native refresh.
    // gotrue_dart 2.20.0+ calls getUser() inside setSession, which rejects
    // shell-minted JWTs (no auth.sessions row → session_not_found), so we no
    // longer use the postMessage shell-token path here.
    var next = _refreshInterval;
    try {
      await client.auth.refreshSession();
    } catch (e, stack) {
      // Refresh-token failures are permanent — retrying is pointless and the
      // exceptions are expected lifecycle, not bugs. Sign out cleanly so
      // GoRouter's auth redirect takes the user to the login screen.
      if (e is AuthException && _isRefreshTokenFailure(e)) {
        try {
          await client.auth.signOut();
        } catch (_) {}
        return;
      }
      unawaited(Sentry.captureException(e, stackTrace: stack));
      next = _retryDelay;
    }
    _schedule(next);
  }
}
