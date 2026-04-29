import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/licence_repository.dart';
import '../../data/models/licence.dart';

part 'licences_list_notifier.g.dart';

@riverpod
class LicencesListNotifier extends _$LicencesListNotifier {
  @override
  Future<List<Licence>> build() async {
    final repo = ref.read(licenceRepositoryProvider);
    return repo.getAllForCurrentUser();
  }

  Future<void> refresh() async {
    final repo = ref.read(licenceRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(repo.getAllForCurrentUser);
  }

  Future<void> deleteLicence(String id) async {
    final repo = ref.read(licenceRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await repo.softDelete(id);
      return repo.getAllForCurrentUser();
    });
  }
}
