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
      state = AuthFlowAwaitingOtp.email(email.trim());
    } on Failure catch (f) {
      _setError(f, isPhone: false);
    } catch (e, st) {
      unawaited(Sentry.captureException(e, stackTrace: st));
      state = const AuthFlowError('Something went wrong. Please try again.');
    }
  }

  Future<void> sendPhoneOtp(String e164Phone) async {
    state = const AuthFlowSendingOtp();
    try {
      await ref.read(authRepositoryProvider).sendPhoneOtp(e164Phone);
      state = AuthFlowAwaitingOtp.phone(e164Phone);
    } on Failure catch (f) {
      _setError(f, isPhone: true);
    } catch (e, st) {
      unawaited(Sentry.captureException(e, stackTrace: st));
      state = const AuthFlowError('Something went wrong. Please try again.');
    }
  }

  Future<void> verifyOtp(String email, String token) async {
    state = const AuthFlowVerifying();
    try {
      await ref.read(authRepositoryProvider).verifyOtp(email, token.trim());
      // GoRouter's authStateChangesProvider listener handles redirect on success.
    } on Failure catch (f) {
      _setError(f, isPhone: false);
    } catch (e, st) {
      unawaited(Sentry.captureException(e, stackTrace: st));
      state = const AuthFlowError('Something went wrong. Please try again.');
    }
  }

  Future<void> verifyPhoneOtp(String e164Phone, String token) async {
    state = const AuthFlowVerifying(isPhone: true);
    try {
      await ref.read(authRepositoryProvider).verifyPhoneOtp(e164Phone, token.trim());
    } on Failure catch (f) {
      _setError(f, isPhone: true);
    } catch (e, st) {
      unawaited(Sentry.captureException(e, stackTrace: st));
      state = const AuthFlowError('Something went wrong. Please try again.');
    }
  }

  void reset() => state = const AuthFlowIdle();

  /// Maps [f] to user-facing copy and pushes it to `state`. Failures whose
  /// detail must not reach the user have their raw text sent to Sentry only —
  /// see [_reportOpaque]. [_message] stays pure so the mapping is unit-testable.
  void _setError(Failure f, {required bool isPhone}) {
    _reportOpaque(f);
    state = AuthFlowError(_message(f, isPhone: isPhone));
  }
}

String _message(Failure f, {required bool isPhone}) => switch (f) {
      NetworkFailure() =>
        'No internet connection. Check your network and try again.',
      ServerFailure(code: 429) =>
        'Too many sign-in attempts. Wait a minute and try again.',
      ServerFailure(code: 401, message: final m)
          when m.toLowerCase().contains('rate limit') ||
              m.toLowerCase().contains('exceeded') =>
        'Too many sign-in attempts. Wait a minute and try again.',
      ServerFailure(code: 401) => isPhone
        ? 'Incorrect code — check your messages and try again.'
        : 'Incorrect code — check your email and try again.',
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
