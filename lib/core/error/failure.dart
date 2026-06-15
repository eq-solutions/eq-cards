/// Sealed hierarchy of error conditions that originate from the data layer.
///
/// Repositories throw these; notifiers catch them and map to user-readable
/// messages. The UI never sees raw `PostgrestException`, `AuthException`,
/// `StorageException` or other backend-specific types — `mapSupabaseError`
/// translates those at the repository boundary.
///
/// Implements [Exception] so `throw mapSupabaseError(e)` satisfies the
/// `only_throw_errors` lint from `very_good_analysis`.
sealed class Failure implements Exception {
  const Failure();
}

/// Network-level failure: device offline, DNS, TLS handshake, etc. UI should
/// surface a retry CTA rather than a hard error.
class NetworkFailure extends Failure {
  const NetworkFailure();
}

/// The current session has no authenticated user. Repositories throw this
/// when `auth.currentUser?.id` is null at the start of a query. UI should
/// bounce to the auth flow.
class NotAuthenticatedFailure extends Failure {
  const NotAuthenticatedFailure();
}

/// The requested entity doesn't exist (or the user can't see it under RLS,
/// which looks identical from the client's perspective).
class NotFoundFailure extends Failure {
  const NotFoundFailure();
}

/// Client-side validation failure. The [message] is intended for direct
/// display to the user (kept short and human-friendly).
class ValidationFailure extends Failure {
  const ValidationFailure(this.message);
  final String message;
}

/// Server returned an error response. [code] is the HTTP / Postgres code,
/// [message] is the server's message — surface with caution; prefer
/// translating well-known codes to friendlier text in the notifier.
class ServerFailure extends Failure {
  const ServerFailure(this.code, this.message);
  final int code;
  final String message;
}

/// Too many requests — the caller is being rate-limited (HTTP 429), e.g. the
/// invite-lookup per-IP / per-slug throttle on the Shell gateway.
/// [retryAfterSeconds] is the server-advised cool-off, when known.
class RateLimitedFailure extends Failure {
  const RateLimitedFailure(this.retryAfterSeconds);
  final int? retryAfterSeconds;
}

/// Catch-all for unexpected errors. Sentry receives the underlying [error]
/// in release builds.
class UnknownFailure extends Failure {
  const UnknownFailure(this.error);
  final Object error;
}
