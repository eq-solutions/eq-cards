import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/pin_repository.dart';
import '../../domain/app_lock_state.dart';
import 'auth_state_provider.dart';

part 'app_lock_notifier.g.dart';

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

    _checkLockState();
    return AppLockPhase.checking;
  }

  Future<void> _checkLockState() async {
    try {
      final hasPinSet = await ref.read(pinRepositoryProvider).hasPin();
      // A fresh signedIn event may have already unlocked us while the RPC
      // was in flight — don't overwrite that.
      if (state == AppLockPhase.checking) {
        state = hasPinSet ? AppLockPhase.pinEntryRequired : AppLockPhase.pinSetupRequired;
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

  /// Called from PinSetupScreen after the user has confirmed their PIN.
  Future<void> setupPin(String pin) async {
    await ref.read(pinRepositoryProvider).setPin(pin);
    state = AppLockPhase.unlocked;
  }
}
