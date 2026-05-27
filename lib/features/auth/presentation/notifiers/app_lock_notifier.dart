import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/pin_repository.dart';
import '../../domain/app_lock_state.dart';
import 'auth_state_provider.dart';

part 'app_lock_notifier.g.dart';

// How old a session can be (in seconds) and still be treated as a fresh
// sign-in. Covers the OAuth redirect reload on web, where the signedIn event
// fires during Supabase.initialize() before any listener is registered.
const _freshSessionThresholdSecs = 30;

@riverpod
class AppLockNotifier extends _$AppLockNotifier {
  @override
  AppLockPhase build() {
    // Fresh sign-in (Google OAuth, OTP, etc.) — user just proved identity,
    // skip PIN entirely for this session.
    ref.listen(rawAuthEventsProvider, (_, next) {
      next.whenData((supabaseAuthState) {
        if (supabaseAuthState.event == AuthChangeEvent.signedIn) {
          state = AppLockPhase.unlocked;
        } else if (supabaseAuthState.event == AuthChangeEvent.signedOut) {
          state = AppLockPhase.unlocked;
        }
      });
    });

    // Cold-start: re-check PIN when notifier rebuilds with a live session
    // (e.g. app reopened, token refreshed). Skip if already unlocked this
    // session — avoids gating on tokenRefreshed events mid-flow.
    ref.listen(authStateChangesProvider, (_, next) {
      next.whenData((authState) {
        final session = Supabase.instance.client.auth.currentSession;
        final hasSession = session != null && !session.isExpired;
        if (!hasSession) {
          state = AppLockPhase.unlocked;
        } else if (state == AppLockPhase.checking) {
          _checkLockState();
        }
      });
    });

    // Synchronous initial check — Supabase restores the session from
    // flutter_secure_storage during Supabase.initialize(), so currentSession
    // is available immediately at build time.
    final session = Supabase.instance.client.auth.currentSession;
    final hasSession = session != null && !session.isExpired;
    if (!hasSession) return AppLockPhase.unlocked;

    // On web, Google OAuth is a redirect flow — the app reloads on return and
    // Supabase fires signedIn during initialization, before this notifier
    // exists. Catch that case by checking the JWT iat: if the session was
    // issued very recently the user just proved their identity and PIN is
    // redundant.
    final iat = _jwtIssuedAt(session.accessToken);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (iat != null && nowSec - iat < _freshSessionThresholdSecs) {
      return AppLockPhase.unlocked;
    }

    _checkLockState();
    return AppLockPhase.checking;
  }

  /// Decode the `iat` (issued-at) claim from a JWT without verifying the
  /// signature — we trust the value only for a freshness check, not auth.
  static int? _jwtIssuedAt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = base64Url.normalize(parts[1]);
      final data =
          jsonDecode(utf8.decode(base64Url.decode(payload))) as Map<String, dynamic>;
      return data['iat'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkLockState() async {
    try {
      final hasPinSet = await ref.read(pinRepositoryProvider).hasPin();
      // A fresh signedIn event may have already unlocked us while the RPC
      // was in flight — don't overwrite that.
      if (state == AppLockPhase.checking) {
        // PIN is opt-in: only gate on entry if the user already set one.
        // pinSetupRequired is only used by the voluntary PIN-setup flow
        // (e.g. Settings → Set up PIN), not enforced on cold start.
        state = hasPinSet ? AppLockPhase.pinEntryRequired : AppLockPhase.unlocked;
      }
    } catch (_) {
      if (state == AppLockPhase.checking) {
        state = AppLockPhase.unlocked;
      }
    }
  }

  /// Called from PinEntryScreen. Returns true if the PIN matched.
  Future<bool> verifyPin(String pin) async {
    try {
      final ok = await ref.read(pinRepositoryProvider).verifyPin(pin);
      if (ok) state = AppLockPhase.unlocked;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Called from PinSetupScreen "Skip for now" — dismisses setup without saving.
  void skipPinSetup() => state = AppLockPhase.unlocked;

  /// Called from PinSetupScreen after the user has confirmed their PIN.
  Future<void> setupPin(String pin) async {
    try {
      await ref.read(pinRepositoryProvider).setPin(pin);
      state = AppLockPhase.unlocked;
    } catch (e, stack) {
      unawaited(Sentry.captureException(e, stackTrace: stack));
      rethrow;
    }
  }
}
