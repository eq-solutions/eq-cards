import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/cards_api/cards_data_source_providers.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'models/worker_credential.dart';

export 'models/worker_credential.dart';

part 'worker_house_repository.g.dart';

class WorkerHouseRepository {
  WorkerHouseRepository(this._source);
  final CardsDataSource _source;

  Never _throw(Object e) => throw mapSupabaseError(e);

  Future<List<WorkerCredential>> listMyCredentials() async {
    try {
      final rows = await _source.listWorkerCredentials();
      return rows.map(WorkerCredential.fromJson).toList();
    } catch (e) {
      _throw(e);
    }
  }
}

@riverpod
WorkerHouseRepository workerHouseRepository(Ref ref) =>
    WorkerHouseRepository(ref.watch(cardsDataSourceProvider));
