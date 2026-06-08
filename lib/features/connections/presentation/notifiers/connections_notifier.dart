import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/connections_repository.dart';

part 'connections_notifier.g.dart';

/// Manages the list of pending org-membership connections for the wallet banner.
///
/// Exposes [accept] and [decline] which mutate a specific row then refresh
/// the full list so the banner redraws (or disappears) immediately.
@riverpod
class PendingConnectionsNotifier extends _$PendingConnectionsNotifier {
  @override
  Future<List<PendingConnection>> build() async {
    final repo = ref.watch(connectionsRepositoryProvider);
    return repo.fetchPending();
  }

  /// Accepts the given membership and refreshes.
  Future<void> accept(String membershipId) async {
    final repo = ref.read(connectionsRepositoryProvider);
    await repo.accept(membershipId);
    await _refresh(repo);
  }

  /// Declines the given membership and refreshes.
  Future<void> decline(String membershipId) async {
    final repo = ref.read(connectionsRepositoryProvider);
    await repo.decline(membershipId);
    await _refresh(repo);
  }

  Future<void> _refresh(ConnectionsRepository repo) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(repo.fetchPending);
  }
}
