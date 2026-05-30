import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase
    show AuthState;

import '../../../../core/supabase/supabase_client_provider.dart';
import '../../domain/auth_state.dart';

part 'auth_state_provider.g.dart';

@riverpod
Stream<AuthState> authStateChanges(AuthStateChangesRef ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange.map((event) {
    return event.session != null
        ? AuthState.authenticated
        : AuthState.unauthenticated;
  });
}

/// Raw Supabase auth events — used by AppLockNotifier to distinguish a fresh
/// sign-in (skip PIN, user just proved identity) from a cold-start session
/// restore (check PIN as normal).
@riverpod
Stream<supabase.AuthState> rawAuthEvents(RawAuthEventsRef ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
}
