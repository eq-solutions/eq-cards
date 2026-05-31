import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
      _setError(f);
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
      _setError(f);
    } catch (_) {
      state = const AuthFlowError('Something went wrong. Please try again.');
    }
  }

  void reset() => state = const AuthFlowIdle();

  /// Maps [f] to user-facing copy and pushes it to `state`. Failures whose
  /// detail must not reach the user have their raw text sent to Sentry only —
  /// see [_reportOpaque]. [_message] stays pure so the mapping is unit-testable.
  void _setError(Failure f) {
    _reportOpaque(f);
    state = AuthFlowError(_message(f));
  }
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
      // Any other server error: show generic copy, never the raw server text (it
      // can carry internal detail). The raw message is captured for diagnostics in
      // _reportOpaque.
      ServerFailure() => 'Something went wrong. Please try again.',
      NotAuthenticatedFailure() => 'Session expired. Please sign in again.',
      NotFoundFailure() => 'Account not found.',
      ValidationFailure(:final message) => message,
      UnknownFailure() => 'Something went wrong. Please try again.',
    };

/// Sends the raw detail of failures the user only sees as a generic message to
/// Sentry, so the real error stays diagnosable. User-facing copy is produced
/// separately by [_message]; the two never share text.
void _reportOpaque(Failure f) {
  // ServerFailures with specific copy (rate-limit at 429/401, invalid-code at
  // 401) are expected; every other code is opaque to the user and worth
  // capturing. Network / not-found / validation / not-authenticated already map
  // to safe, specific copy and need no capture.
  if (f case ServerFailure(:final code, :final message)
      when code != 429 && code != 401) {
    unawaited(
      Sentry.captureMessage(
        'Auth flow: unmapped server error ($code): $message',
        level: SentryLevel.error,
      ),
    );
  } else if (f is UnknownFailure) {
    unawaited(Sentry.captureException(f.error));
  }
}
