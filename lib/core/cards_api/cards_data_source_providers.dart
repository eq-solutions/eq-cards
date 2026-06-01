// Flag-gated wiring for the Cards data transport.
//
// The active transport is chosen at build time by the CARDS_DATA_TRANSPORT
// dart-define and defaults to `direct` — so this whole seam is INERT until
// someone explicitly builds with `--dart-define=CARDS_DATA_TRANSPORT=gateway`.
// Flipping the flag re-routes every Cards read/write without touching
// repository code, and flipping it back is an instant rollback.
//
// Do NOT flip to `gateway` until both preconditions in
// docs/cards-canonical-api-rewire.md are live and verified:
//   A. custom_access_token_hook on eq-canonical injects app_metadata.tenant_id
//      into OTP/OAuth JWTs, and
//   B. the target tenant's Cards data is migrated into its per-tenant DB.
// Without (A) the gateway 401s OTP/OAuth users; without (B) they read an empty
// per-tenant DB.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';
import '../supabase/supabase_client_provider.dart';
import 'cards_api.dart';
import 'cards_data_source.dart';

export 'cards_data_source.dart';

part 'cards_data_source_providers.g.dart';

/// Which transport the Cards repositories use for data operations.
enum CardsDataTransport {
  /// Direct `eq_cards_*` RPCs against eq-canonical. The default.
  direct,

  /// The Shell `cards-api` gateway → the caller's per-tenant database.
  gateway,
}

/// Parses the `CARDS_DATA_TRANSPORT` dart-define into a [CardsDataTransport].
///
/// Fail-safe: anything other than the exact string `gateway` resolves to
/// [CardsDataTransport.direct], so a typo or unset value never silently routes
/// live traffic to the gateway.
CardsDataTransport cardsDataTransportFromString(String raw) =>
    raw == 'gateway' ? CardsDataTransport.gateway : CardsDataTransport.direct;

const String _rawTransport = String.fromEnvironment(
  'CARDS_DATA_TRANSPORT',
  defaultValue: 'direct',
);

/// The active transport, resolved at build time from `CARDS_DATA_TRANSPORT`.
/// Defaults to [CardsDataTransport.direct].
@Riverpod(keepAlive: true)
CardsDataTransport cardsDataTransport(Ref ref) =>
    cardsDataTransportFromString(_rawTransport);

/// Direct-RPC transport: `eq_cards_*` calls on eq-canonical. The load-bearing
/// default. Exposed as the [CardsDataSource] interface (not the concrete type)
/// so tests can override it with a fake without a real Supabase client.
@Riverpod(keepAlive: true)
CardsDataSource directCardsDataSource(Ref ref) =>
    DirectCardsDataSource(ref.watch(supabaseClientProvider));

/// Gateway transport: the Shell `cards-api` client, surfaced as the
/// [CardsDataSource] interface so it is overridable in tests.
@Riverpod(keepAlive: true)
CardsDataSource gatewayCardsDataSource(Ref ref) =>
    ref.watch(cardsApiProvider);

/// The active [CardsDataSource]. Both repositories depend on this, so the
/// dart-define is the single switch for the whole data plane. Only the chosen
/// branch's provider is watched, so the unused transport is never constructed.
@Riverpod(keepAlive: true)
CardsDataSource cardsDataSource(Ref ref) {
  switch (ref.watch(cardsDataTransportProvider)) {
    case CardsDataTransport.gateway:
      return ref.watch(gatewayCardsDataSourceProvider);
    case CardsDataTransport.direct:
      return ref.watch(directCardsDataSourceProvider);
  }
}

/// [CardsDataSource] backed by direct `eq_cards_*` RPCs on eq-canonical.
///
/// The load-bearing default path. The RPCs resolve identity from `auth.uid()`
/// server-side, so no `tenant_id` claim is required (unlike the gateway).
class DirectCardsDataSource implements CardsDataSource {
  /// Wraps the app's shared Supabase client.
  DirectCardsDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> currentStaff() async {
    final rows = await _client.rpc<List<dynamic>>('eq_cards_current_staff');
    final list = rows.cast<Map<String, dynamic>>();
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<List<Map<String, dynamic>>> listMyLicences() async {
    final rows = await _client.rpc<List<dynamic>>('eq_cards_list_my_licences');
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> upsertMyLicence(
    Map<String, dynamic> payload,
  ) async {
    final rows = await _client.rpc<List<dynamic>>(
      'eq_cards_upsert_my_licence',
      params: {'p_payload': payload},
    );
    final list = rows.cast<Map<String, dynamic>>();
    if (list.isEmpty) throw const NotFoundFailure();
    return list.first;
  }

  @override
  Future<void> softDeleteMyLicence(String licenceId) async {
    await _client.rpc<void>(
      'eq_cards_soft_delete_my_licence',
      params: {'p_licence_id': licenceId},
    );
  }

  @override
  Future<Map<String, dynamic>> upsertMyProfile(
    Map<String, dynamic> payload,
  ) async {
    final rows = await _client.rpc<List<dynamic>>(
      'eq_cards_upsert_my_profile',
      params: {'p_payload': payload},
    );
    final list = rows.cast<Map<String, dynamic>>();
    if (list.isEmpty) throw const NotFoundFailure();
    return list.first;
  }
}
