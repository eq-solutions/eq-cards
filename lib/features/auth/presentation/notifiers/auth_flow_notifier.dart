import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_flow_state.dart';

part 'auth_flow_notifier.g.dart';

@riverpod
class AuthFlowNotifier extends _$AuthFlowNotifier {
  @override
  AuthFlowState build() => const AuthFlowIdle();

  Future<void> sendOtp(String email) async {
    state = const AuthFlowSendingOtp();
    try {
      await ref.read(authRepositoryProvider).sendOtp(email);
      state = AuthFlowAwaitingOtp(email);
    } on Failure catch (f) {
      state = AuthFlowError(_messageFor(f));
    }
  }

  Future<void> verifyOtp(String email, String code) async {
    state = const AuthFlowVerifying();
    try {
      await ref.read(authRepositoryProvider).verifyOtp(email, code);
      // Success: authStateChangesProvider emits authenticated, router redirects to home.
      state = const AuthFlowIdle();
    } on Failure catch (f) {
      state = AuthFlowError(_messageFor(f));
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }

  void clearError() {
    if (state is AuthFlowError) state = const AuthFlowIdle();
  }

  String _messageFor(Failure f) {
    return switch (f) {
      NetworkFailure() => 'Network unavailable. Check your connection and try again.',
      ServerFailure(:final message) => message,
      ValidationFailure(:final message) => message,
      _ => 'Something went wrong. Try again.',
    };
  }
}
