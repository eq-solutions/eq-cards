import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';

Failure mapSupabaseError(Object error) {
  // Already-typed failures pass straight through — never re-wrap a Failure as
  // UnknownFailure. This matters now that the gateway transport (CardsApi)
  // throws typed Failures directly, and DirectCardsDataSource throws
  // NotFoundFailure on an empty result; both flow up through the repositories'
  // `catch (e) => mapSupabaseError(e)`.
  if (error is Failure) return error;
  // Network-class errors first — both dart:io (mobile) and the
  // web-platform "ClientException: Failed to fetch" string surface
  // through here. Detecting them produces the user-friendly
  // "Network unavailable" message rather than a generic UnknownFailure.
  if (error is SocketException ||
      error is HttpException ||
      _looksLikeNetworkError(error)) {
    return const NetworkFailure();
  }
  if (error is AuthException) {
    // AuthException.statusCode is a String? — parse it for rate-limit detection.
    final statusCode = int.tryParse(error.statusCode ?? '') ?? 401;
    // Supabase returns HTTP 403 with code='otp_expired' when the SMS code
    // window closes before the user submits. Without this guard the 403 falls
    // through to ServerFailure(403) → "Session expired", which is wrong — the
    // user's session is fine, just their code timed out.
    if (error.code == 'otp_expired') {
      return const ValidationFailure(
        'Your sign-in code expired. Tap Resend to get a new one.',
      );
    }
    return ServerFailure(statusCode, error.message);
  }
  if (error is PostgrestException) {
    final code = int.tryParse(error.code ?? '') ?? 500;
    return ServerFailure(code, error.message);
  }
  if (error is StorageException) {
    return ServerFailure(500, error.message);
  }
  return UnknownFailure(error);
}

bool _looksLikeNetworkError(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('authretryablefetchexception') ||
      s.contains('clientexception') ||
      s.contains('failed host lookup') ||
      s.contains('failed to fetch') ||
      s.contains('connection closed') ||
      s.contains('connection refused') ||
      s.contains('connection reset');
}
