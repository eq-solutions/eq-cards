import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/licence_types_repository.dart';
import '../../data/models/licence_type.dart';

part 'licence_types_provider.g.dart';

@Riverpod(keepAlive: true)
Future<List<LicenceType>> licenceTypes(Ref ref) async {
  final repo = ref.read(licenceTypesRepositoryProvider);
  return repo.getAll();
}
