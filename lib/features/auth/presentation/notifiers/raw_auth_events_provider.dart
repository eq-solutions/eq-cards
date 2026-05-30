import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../../../../core/supabase/supabase_client_provider.dart';

part 'raw_auth_events_provider.g.dart';

/// Raw Supabase auth events — used by AppLockNotifier to distinguish a fresh
/// sign-in (skip PIN, user just proved identity) from a cold-start session
/// restore (check PIN as normal).
///
/// Kept in its own file (separate from `authStateChanges`, which emits our
/// domain `AuthState`) so that no single library has both gotrue's `AuthState`
/// and our domain `AuthState` in scope. riverpod_generator 3 resolves an
/// `AuthState` type reference by its simple name against the file's imports,
/// so two same-named types in one file make it emit the wrong one in the
/// generated `.g.dart`. One `AuthState` per file keeps generation correct.
@riverpod
Stream<AuthState> rawAuthEvents(Ref ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
}
