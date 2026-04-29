import 'failure.dart';

/// Translates a raw error (from a `catch` block or `AsyncValue.error`) into a
/// short, user-friendly string. Use anywhere a screen would otherwise show
/// `'$e'` directly.
///
/// Repository code throws [Failure] subtypes; this helper translates each to
/// the right tone. Anything else falls through to a generic message — Sentry
/// has the underlying object via [UnknownFailure] for diagnostics.
String userMessageForError(Object error) {
  if (error is NetworkFailure) {
    return 'Network unavailable. Check your connection and try again.';
  }
  if (error is NotAuthenticatedFailure) {
    return 'Your session has expired. Please sign in again.';
  }
  if (error is NotFoundFailure) {
    return "We couldn't find that record.";
  }
  if (error is ValidationFailure) {
    return error.message;
  }
  if (error is ServerFailure) {
    return error.message.isNotEmpty
        ? error.message
        : 'Server error (${error.code}). Try again in a moment.';
  }
  if (error is UnknownFailure) {
    return 'Something unexpected happened. Try again.';
  }
  return 'Something went wrong. Try again.';
}
