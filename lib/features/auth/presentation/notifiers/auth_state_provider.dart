import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/supabase/supabase_client_provider.dart';
import '../../domain/auth_state.dart';

part 'auth_state_provider.g.dart';

@riverpod
Stream<AuthState> authStateChanges(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange.map((event) {
    return event.session != null
        ? AuthState.authenticated
        : AuthState.unauthenticated;
  });
}
