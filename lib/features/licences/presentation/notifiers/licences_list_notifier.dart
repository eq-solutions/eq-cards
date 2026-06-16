import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/services/wallet_cache_service.dart';
import '../../data/licence_repository.dart';
import '../../data/models/licence.dart';

export '../../data/models/licence.dart';

part 'licences_list_notifier.g.dart';

/// Tracks whether the licences list was most recently served from the local
/// cache rather than a live Supabase fetch. Consumed by `OfflineBanner`.
@riverpod
class LicencesFromCache extends _$LicencesFromCache {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties -- named param avoids bool trap
  void setValue({required bool fromCache}) => state = fromCache;
}

@riverpod
class LicencesListNotifier extends _$LicencesListNotifier {
  @override
  Future<List<Licence>> build() => _fetchWithCache();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchWithCache);
  }

  Future<void> deleteLicence(String id) async {
    final repo = ref.read(licenceRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await repo.softDelete(id);
      return _fetchWithCache();
    });
  }

  // ---------------------------------------------------------------------------
  // Cache-aware fetch
  // ---------------------------------------------------------------------------

  Future<List<Licence>> _fetchWithCache() async {
    final repo = ref.read(licenceRepositoryProvider);
    try {
      final licences = await repo.getAllForCurrentUser();
      // Persist to cache on success (web only). Clear the fromCache flag.
      if (kIsWeb) {
        ref
            .read(licencesFromCacheProvider.notifier)
            .setValue(fromCache: false);
        unawaited(
          WalletCacheService().saveLicences(
            licences.map((l) => l.toJson()).toList(),
          ),
        );
      }
      return licences;
    } catch (_) {
      // Network / auth failure — try serving from cache on web.
      if (kIsWeb) {
        final cached = await WalletCacheService().loadLicences();
        if (cached != null) {
          ref
              .read(licencesFromCacheProvider.notifier)
              .setValue(fromCache: true);
          return cached.map(Licence.fromJson).toList();
        }
      }
      rethrow;
    }
  }
}
