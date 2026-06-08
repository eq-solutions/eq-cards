import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'pending_connection.dart';

export 'pending_connection.dart';

part 'connections_repository.g.dart';

/// Repository for the worker's org-membership connections.
///
/// Queries `public.org_memberships` (RLS: worker can SELECT/UPDATE their own
/// pending rows). The join to `public.organisations` resolves the display name
/// and logo URL so the banner never needs a second round-trip.
class ConnectionsRepository {
  ConnectionsRepository(this._client);

  final SupabaseClient _client;

  // ------------------------------------------------------------------
  // Queries
  // ------------------------------------------------------------------

  /// Returns all pending org-membership invitations for the current user.
  Future<List<PendingConnection>> fetchPending() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return const [];

      final rows = await _client
          .from('org_memberships')
          .select('id, org_id, invited_at, organisations(name, logo_url)')
          .eq('user_id', uid)
          .eq('status', 'pending');

      return (rows as List<dynamic>).map((dynamic raw) {
        final r = raw as Map<String, dynamic>;
        final org = r['organisations'] as Map<String, dynamic>? ?? {};
        return PendingConnection(
          id: r['id'] as String,
          orgId: r['org_id'] as String,
          orgName: (org['name'] as String?) ?? 'Unknown organisation',
          orgLogoUrl: org['logo_url'] as String?,
          invitedAt: DateTime.parse(r['invited_at'] as String),
        );
      }).toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Accepts a pending membership invitation — sets status to 'active'.
  Future<void> accept(String membershipId) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;

      await _client
          .from('org_memberships')
          .update({
            'status': 'active',
            'accepted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', membershipId)
          .eq('user_id', uid)
          .eq('status', 'pending');
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Declines a pending membership invitation — sets status to 'declined'.
  Future<void> decline(String membershipId) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;

      await _client
          .from('org_memberships')
          .update({'status': 'declined'})
          .eq('id', membershipId)
          .eq('user_id', uid)
          .eq('status', 'pending');
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

@riverpod
ConnectionsRepository connectionsRepository(Ref ref) =>
    ConnectionsRepository(ref.watch(supabaseClientProvider));
