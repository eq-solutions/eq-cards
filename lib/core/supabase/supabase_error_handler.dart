import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';

Failure mapSupabaseError(Object error) {
  if (error is AuthException) {
    return ServerFailure(401, error.message);
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
