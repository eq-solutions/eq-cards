import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/certificate_repository.dart';
import '../../data/models/certificate.dart';

part 'certificates_list_notifier.g.dart';

@riverpod
class CertificatesListNotifier extends _$CertificatesListNotifier {
  @override
  Future<List<Certificate>> build() {
    return ref.read(certificateRepositoryProvider).getAllForCurrentUser();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      ref.read(certificateRepositoryProvider).getAllForCurrentUser,
    );
  }

  Future<void> deleteCertificate(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(certificateRepositoryProvider).softDelete(id);
      return ref.read(certificateRepositoryProvider).getAllForCurrentUser();
    });
  }
}
