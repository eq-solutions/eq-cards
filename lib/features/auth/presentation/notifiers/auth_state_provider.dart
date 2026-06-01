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
    // by construction — no extra check needed.
    //
    // Phone OTP: AuthRepository.verifyPhoneOtp() calls phoneOtpShellExchange()
    // immediately after GoTrue verifies the code. The exchange calls
    // shell-login-phone-otp on the Shell, which looks up the user in
    // shell_control.users and returns a shell-minted JWT with tenant_id already
    // in app_metadata. setSession() fires another onAuthStateChange event with
    // that JWT — this listener then sees a non-null tenant_id and returns
    // authenticated. If the exchange fails or the user is not in
    // shell_control.users, this listener sees null tenant_id and returns
    // notProvisioned, which routes to the "No workspace access" screen.
    //
    // Email OTP / Google OAuth: the raw GoTrue JWT has no tenant_id (the
    // custom_access_token_hook on eq-canonical is not yet enabled). Those
    // users land on notProvisioned until the hook is live or they are
    // redirected via a Shell handoff link. See docs/cards-canonical-api-rewire.md
    // §5 for the hook design and enablement runbook.
    final tenantId = session.user.appMetadata['tenant_id'];
    if (tenantId == null) return AuthState.notProvisioned;
    return AuthState.authenticated;
  });
}
