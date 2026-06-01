import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';

Failure mapSupabaseError(Object error) {
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
