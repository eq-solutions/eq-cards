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
      state = AuthFlowError(_message(f));
    } catch (_) {
      state = const AuthFlowError('Something went wrong. Please try again.');
    }
  }

  Future<void> verifyOtp(String email, String token) async {
    state = const AuthFlowVerifying();
    try {
      await ref.read(authRepositoryProvider).verifyOtp(email, token.trim());
      // GoRouter's authStateChangesProvider listener handles redirect on success.
    } on Failure catch (f) {
      state = AuthFlowError(_message(f));
    } catch (_) {
      state = const AuthFlowError('Something went wrong. Please try again.');
    }
  }

  void reset() => state = const AuthFlowIdle();
}

String _message(Failure f) => switch (f) {
      NetworkFailure() =>
        'No internet connection. Check your network and try again.',
      ServerFailure(code: 429) =>
        'Too many sign-in attempts. Wait a minute and try again.',
      ServerFailure(code: 401, message: final m)
          when m.toLowerCase().contains('rate limit') ||
              m.toLowerCase().contains('exceeded') =>
        'Too many sign-in attempts. Wait a minute and try again.',
      ServerFailure(code: 401) =>
        'Incorrect code — check your email and try again.',
      ServerFailure(:final message) => message,
      NotAuthenticatedFailure() => 'Session expired. Please sign in again.',
      NotFoundFailure() => 'Account not found.',
      ValidationFailure(:final message) => message,
      UnknownFailure() => 'Something went wrong. Please try again.',
    };
