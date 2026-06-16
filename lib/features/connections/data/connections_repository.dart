import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'pending_connection.dart';

export 'pending_connection.dart';

part 'connections_repository.g.dart';

/// Repository for the worker's incoming employer connection requests.
///
/// Backed by the canonical `org_access_requests` RPCs (the privacy-safe
/// employer-connect pathway), NOT raw `org_memberships`:
///   * list    → `eq_cards_list_incoming_requests()`
///   * accept  → `eq_cards_respond_to_access_request(id, true)` — writes the
///     org_membership AND the shell_control identity rows the JWT hook +
///     workspace switcher read, so Field SSO is provisioned on approve.
///   * decline → `eq_cards_respond_to_access_request(id, false)`
///
/// `id` is the access-request id (not a membership id). The RPCs resolve the
/// caller via `auth.uid()` and match by phone, so no user_id is passed.
class ConnectionsRepository {
  ConnectionsRepository(this._client);

  final SupabaseClient _client;

  // ------------------------------------------------------------------
  // Queries
  // ------------------------------------------------------------------

  /// Returns all pending employer access requests addressed to the current
  /// worker. Empty when signed out.
  Future<List<PendingConnection>> fetchPending() async {
    try {
      if (_client.auth.currentUser?.id == null) return const [];

      final rows =
          await _client.rpc<List<dynamic>>('eq_cards_list_incoming_requests');

      return rows.map((dynamic raw) {
        final r = raw as Map<String, dynamic>;
        return PendingConnection(
          id: r['request_id'] as String,
          orgId: r['org_id'] as String,
          orgName: (r['org_name'] as String?) ?? 'Unknown organisation',
          // The RPC does not return a logo; the banner falls back to initials.
          orgLogoUrl: null,
          invitedAt: DateTime.parse(r['requested_at'] as String),
        );
      }).toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Approves the request. The RPC provisions the org_membership AND the
  /// shell_control identity (so Field SSO works); we then refresh the session
  /// so the new workspace is immediately visible in the switcher.
  Future<void> accept(String requestId) async {
    try {
      await _client.rpc<dynamic>(
        'eq_cards_respond_to_access_request',
        params: {'p_request_id': requestId, 'p_approve': true},
      );
      // Non-fatal — the membership is committed; the JWT refreshes on next
      // token expiry even if this throws (offline, transient).
      try {
        await _client.auth.refreshSession();
      } catch (_) {
        // Non-fatal — JWT refreshes on next token expiry.
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Declines the request.
  Future<void> decline(String requestId) async {
    try {
      await _client.rpc<dynamic>(
        'eq_cards_respond_to_access_request',
        params: {'p_request_id': requestId, 'p_approve': false},
      );
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

@riverpod
ConnectionsRepository connectionsRepository(Ref ref) =>
    ConnectionsRepository(ref.watch(supabaseClientProvider));
