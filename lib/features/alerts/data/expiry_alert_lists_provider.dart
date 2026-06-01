import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../licences/licences.dart';
import '../../worker_house/worker_house.dart';

part 'expiry_alert_lists_provider.g.dart';

/// Combined snapshot of every expirable list the scheduler cares about.
/// Returns null until at least one list has settled with data — so the
/// shell only triggers a sync once real data is available.
/// Watching both here means the shell needs a single ref.listen; no
/// cross-reads, no cancelAll race between two independent callbacks.
@riverpod
({List<Licence> licences, List<WorkerCredential> credentials})?
    expiryAlertLists(Ref ref) {
  final licences =
      ref.watch(licencesListNotifierProvider).asData?.value;
  final credentials =
      ref.watch(workerCredentialsListProvider).asData?.value;
  if (licences == null && credentials == null) return null;
  return (
    licences: licences ?? const [],
    credentials: credentials ?? const [],
  );
}
