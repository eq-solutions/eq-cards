import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';

part 'workspace_repository.g.dart';

class TenantMembership {
  const TenantMembership({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.isPersonal,
    required this.isActive,
  });

  factory TenantMembership.fromJson(Map<String, dynamic> json) =>
      TenantMembership(
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        isPersonal: json['is_personal'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? false,
      );

  final String tenantId;
  final String name;
  final String slug;
  final bool isPersonal;
  final bool isActive;
}

class WorkspaceRepository {
  WorkspaceRepository(this._client);
  final SupabaseClient _client;

  Future<List<TenantMembership>> listMyTenants() async {
    final result = await _client.rpc<List<dynamic>>('eq_cards_list_my_tenants');
    return result
        .map((e) => TenantMembership.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setActiveTenant(String tenantId) async {
    await _client.rpc<dynamic>(
      'eq_cards_set_active_tenant',
      params: {'p_tenant_id': tenantId},
    );
    await _client.auth.refreshSession();
  }
}

@riverpod
WorkspaceRepository workspaceRepository(Ref ref) =>
    WorkspaceRepository(ref.watch(supabaseClientProvider));

@riverpod
Future<List<TenantMembership>> myTenants(Ref ref) =>
    ref.watch(workspaceRepositoryProvider).listMyTenants();
