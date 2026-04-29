import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/profile.dart';
import '../../data/profile_repository.dart';

part 'profile_notifier.g.dart';

@riverpod
class ProfileNotifier extends _$ProfileNotifier {
  @override
  Future<Profile?> build() async {
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
