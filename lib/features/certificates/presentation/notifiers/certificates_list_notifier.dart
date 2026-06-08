import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/services/wallet_cache_service.dart';
import '../../data/certificate_repository.dart';
import '../../data/models/certificate.dart';

part 'certificates_list_notifier.g.dart';

@riverpod
class CertificatesListNotifier extends _$CertificatesListNotifier {
  @override
  Future<List<Certificate>> build() => _fetchWithCache();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchWithCache);
  }

  Future<void> deleteCertificate(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(certificateRepositoryProvider).softDelete(id);
      return _fetchWithCache();
    });
  }

  // ---------------------------------------------------------------------------
  // Cache-aware fetch
  // ---------------------------------------------------------------------------

  Future<List<Certificate>> _fetchWithCache() async {
    final repo = ref.read(certificateRepositoryProvider);
    try {
      final certs = await repo.getAllForCurrentUser();
      // Persist to cache on success (web only).
      if (kIsWeb) {
        unawaited(
          WalletCacheService().saveCertificates(
            certs.map((c) => c.toJson()).toList(),
          ),
        );
      }
      return certs;
    } catch (_) {
      // Network / auth failure — try serving from cache on web.
      if (kIsWeb) {
        final cached = await WalletCacheService().loadCertificates();
        if (cached != null) {
          return cached.map(Certificate.fromJson).toList();
        }
      }
      rethrow;
    }
  }
}
