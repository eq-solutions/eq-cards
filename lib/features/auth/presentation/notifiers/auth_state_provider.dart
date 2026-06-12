import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/supabase/supabase_client_provider.dart';
import '../../domain/auth_state.dart';

part 'auth_state_provider.g.dart';

@riverpod
Stream<AuthState> authStateChanges(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange.map((event) {
    final session = event.session;
    if (session == null) return AuthState.unauthenticated;
    // custom_access_token_hook injects tenant_id into the GoTrue JWT for any
    // user in shell_control.users. If tenant_id is absent the user either
    // hasn't been invited yet, or the hook didn't fire (fail-open → original
    // token returned). Both cases land on notProvisioned.
    final tenantId = session.user.appMetadata['tenant_id'];
    if (tenantId == null) return AuthState.notProvisioned;
    return AuthState.authenticated;
  });
}
