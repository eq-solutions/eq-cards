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
    // Re-evaluate whenever auth state changes (OTP sign-in, sign-out).
    ref.listen(authStateChangesProvider, (_, next) {
      next.whenData((authState) {
        final session = Supabase.instance.client.auth.currentSession;
        final hasSession = session != null && !session.isExpired;
        if (!hasSession) {
          state = AppLockPhase.unlocked; // OTP is the gate, not PIN
        } else {
          state = AppLockPhase.checking;
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
      state =
          hasPinSet ? AppLockPhase.pinEntryRequired : AppLockPhase.pinSetupRequired;
    } catch (_) {
      // If the RPC fails (e.g. JWT very fresh, network hiccup) default to
      // setup so the user can always get in — worst case they re-set their PIN.
      state = AppLockPhase.pinSetupRequired;
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
