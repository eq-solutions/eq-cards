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
    // Shell handoff tokens are HS256-signed by the Shell and carry tenant_id
    // by construction — no extra check needed. For all other sign-in paths
    // (email OTP, phone OTP, Google), the custom_access_token_hook on
    // eq-canonical injects tenant_id only when the user is provisioned in
    // shell_control.users. An unprovisioned user gets a valid Supabase session
    // but no tenant_id, which causes silent 401s on every tenant-aware RPC.
    // Detect this early and surface it as notProvisioned so the router can
    // redirect to a friendly error screen before the user hits any data routes.
    final tenantId = session.user.appMetadata['tenant_id'];
    if (tenantId == null) return AuthState.notProvisioned;
    return AuthState.authenticated;
  });
}
