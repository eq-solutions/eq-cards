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
      await ref.read(authRepositoryProvider).sendOtp(email.trim());
      state = AuthFlowAwaitingOtp(email.trim());
    } on Failure catch (f) {
      state = AuthFlowError(_message(f), email: email.trim());
    } catch (_) {
      state = AuthFlowError('Something went wrong. Please try again.', email: email.trim());
    }
  }

  Future<void> verifyOtp(String email, String token) async {
    state = const AuthFlowVerifying();
    try {
      await ref.read(authRepositoryProvider).verifyOtp(email, token.trim());
      // GoRouter's authStateChangesProvider listener handles redirect on success.
    } on Failure catch (f) {
      state = AuthFlowError(_message(f), email: email);
    } catch (_) {
      state = AuthFlowError('Something went wrong. Please try again.', email: email);
    }
  }

  void reset() => state = const AuthFlowIdle();
}

String _message(Failure f) => switch (f) {
      NetworkFailure() =>
        'No internet connection. Check your network and try again.',
      ServerFailure(code: 401) =>
        'Incorrect code. Check your email and try again.',
      ServerFailure(:final message) => message,
      NotAuthenticatedFailure() => 'Session expired. Please sign in again.',
      NotFoundFailure() => 'Account not found.',
      ValidationFailure(:final message) => message,
      UnknownFailure() => 'Something went wrong. Please try again.',
    };
