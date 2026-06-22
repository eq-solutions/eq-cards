import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'pending_connection.dart';

export 'pending_connection.dart';

part 'connections_repository.g.dart';

/// An employer organisation that accepts self-signup applications from workers.
class DiscoverableOrg {
  const DiscoverableOrg({
    required this.id,
    required this.name,
    required this.slug,
  });

  final String id;
  final String name;
  final String slug;
}

/// A worker's own outgoing application to an employer.
class OutgoingRequest {
  const OutgoingRequest({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.sharingScope,
    required this.status,
    required this.submittedAt,
    this.respondedAt,
  });

  final String id;
  final String orgId;
  final String orgName;
  final String sharingScope;
  final String status;
  final DateTime submittedAt;
  final DateTime? respondedAt;
}

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

  // ------------------------------------------------------------------
  // Self-signup / outgoing flow
  // ------------------------------------------------------------------

  /// Organisations that accept self-signup applications from workers.
  Future<List<DiscoverableOrg>> listDiscoverableOrgs() async {
    try {
      final rows =
          await _client.rpc<List<dynamic>>('eq_cards_list_discoverable_orgs');
      return rows.map((dynamic raw) {
        final r = raw as Map<String, dynamic>;
        return DiscoverableOrg(
          id: r['org_id'] as String,
          name: (r['org_name'] as String?) ?? 'Unknown',
          slug: (r['org_slug'] as String?) ?? '',
        );
      }).toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Submits a self-signup application to [orgId] with the given [sharingScope]
  /// ('basic' or 'full'). Returns the new request id.
  Future<String> submitRequest(String orgId, String sharingScope) async {
    try {
      final id = await _client.rpc<dynamic>(
        'eq_cards_submit_access_request',
        params: {'p_org_id': orgId, 'p_sharing_scope': sharingScope},
      );
      return id as String;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// The worker's own outgoing applications and their statuses.
  Future<List<OutgoingRequest>> fetchOutgoing() async {
    try {
      final rows =
          await _client.rpc<List<dynamic>>('eq_cards_list_my_outgoing_requests');
      return rows.map((dynamic raw) {
        final r = raw as Map<String, dynamic>;
        return OutgoingRequest(
          id: r['request_id'] as String,
          orgId: r['org_id'] as String,
          orgName: (r['org_name'] as String?) ?? 'Unknown',
          sharingScope: (r['sharing_scope'] as String?) ?? 'full',
          status: (r['status'] as String?) ?? 'pending',
          submittedAt: DateTime.parse(r['submitted_at'] as String),
          respondedAt: r['responded_at'] != null
              ? DateTime.parse(r['responded_at'] as String)
              : null,
        );
      }).toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

/// Discoverable orgs — used by ConnectToCompanyScreen.
final discoverableOrgsProvider =
    FutureProvider.autoDispose<List<DiscoverableOrg>>((ref) async {
  return ref.watch(connectionsRepositoryProvider).listDiscoverableOrgs();
});

/// The worker's own outgoing applications — used in Profile.
final outgoingRequestsProvider =
    FutureProvider.autoDispose<List<OutgoingRequest>>((ref) async {
  return ref.watch(connectionsRepositoryProvider).fetchOutgoing();
});

@riverpod
ConnectionsRepository connectionsRepository(Ref ref) =>
    ConnectionsRepository(ref.watch(supabaseClientProvider));
