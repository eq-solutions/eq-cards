import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/supabase/supabase_client_provider.dart';

part 'org_admin_provider.g.dart';

/// The current user's active admin org, or null if they are not an org admin.
/// Used to gate the admin UI throughout the app.
@riverpod
Future<String?> orgAdminOrgId(Ref ref) async {
  final client = ref.watch(supabaseClientProvider);
  final uid = client.auth.currentUser?.id;
  if (uid == null) return null;

  final rows = await client
      .from('org_memberships')
      .select('org_id')
      .eq('user_id', uid)
      .eq('role', 'admin')
      .eq('status', 'active')
      .limit(1);

  if (rows.isEmpty) return null;
  return rows.first['org_id'] as String;
}
