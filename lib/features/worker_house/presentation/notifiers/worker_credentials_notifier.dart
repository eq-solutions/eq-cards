import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/worker_house_repository.dart';

export '../../data/models/worker_credential.dart';

part 'worker_credentials_notifier.g.dart';

@riverpod
Future<List<WorkerCredential>> workerCredentialsList(Ref ref) async {
  final repo = ref.watch(workerHouseRepositoryProvider);
  return repo.listMyCredentials();
}
