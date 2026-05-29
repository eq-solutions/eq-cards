import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/notifiers/auth_state_provider.dart';
import '../../data/models/profile.dart';
import '../../data/profile_repository.dart';

part 'profile_notifier.g.dart';

@riverpod
class ProfileNotifier extends _$ProfileNotifier {
  @override
  Future<Profile?> build() async {
    // Re-fetch whenever the auth session transitions — critically, once the
    // iframe handoff establishes the session AFTER the pre-auth splash
    // redirect. The router reads this provider during that splash redirect,
    // so without this watch it builds a single time with no session, caches
    // NotAuthenticatedFailure, and never recovers — the Profile tab then
    // shows a false "session expired" while the rest of the app is signed in.
    // select() dedupes so a 15-min token refresh (still authenticated) does
    // not trigger a needless refetch.
    ref.watch(authStateChangesProvider.select((s) => s.valueOrNull));
    final repo = ref.read(profileRepositoryProvider);
    return repo.getCurrent();
  }

  Future<void> save(Profile profile) async {
    final repo = ref.read(profileRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => repo.upsert(profile));
  }

  Future<void> refresh() async {
    final repo = ref.read(profileRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(repo.getCurrent);
  }
}
