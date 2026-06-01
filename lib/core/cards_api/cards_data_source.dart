// Transport-agnostic contract for EQ Cards' profile + licence data ops.
//
// Two implementations back this interface, selected at build time by the
// CARDS_DATA_TRANSPORT dart-define (see cards_data_source_providers.dart):
//
//   • DirectCardsDataSource — calls the eq_cards_* RPCs directly against
//     eq-canonical. The current, load-bearing default.
//   • CardsApi — proxies through the Shell `cards-api` gateway to the caller's
//     per-tenant database. The conformant path; gated behind
//     CARDS_DATA_TRANSPORT=gateway and its two live preconditions (auth hook +
//     per-tenant data migration). See docs/cards-canonical-api-rewire.md.
//
// Both return raw JSON shapes. Model mapping, signed-URL hydration, the auth
// pre-check, Sentry breadcrumbs and error mapping all stay in the repositories
// so the two transports share identical higher-level behaviour.

/// The set of EQ Cards data operations, abstracted over transport.
abstract interface class CardsDataSource {
  /// The current signed-in user's profile/staff row, or null if none exists.
  Future<Map<String, dynamic>?> currentStaff();

  /// All non-deleted licences owned by the current user.
  Future<List<Map<String, dynamic>>> listMyLicences();

  /// Inserts or updates a single licence from [payload]; returns the saved row.
  Future<Map<String, dynamic>> upsertMyLicence(Map<String, dynamic> payload);

  /// Soft-deletes the licence identified by [licenceId].
  Future<void> softDeleteMyLicence(String licenceId);

  /// Inserts or updates the current user's profile; returns the saved row.
  Future<Map<String, dynamic>> upsertMyProfile(Map<String, dynamic> payload);

  /// All worker-house credentials owned by the current user.
  /// Returns an empty list on the direct transport (worker-house is gateway-only).
  Future<List<Map<String, dynamic>>> listWorkerCredentials();
}
