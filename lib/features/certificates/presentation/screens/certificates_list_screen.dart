import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../auth/auth.dart';
import '../../data/models/certificate.dart';
import '../notifiers/certificates_list_notifier.dart';
import '../widgets/certificate_card.dart';

enum _CertFilter { all, expiringSoon, expired }

extension _CertFilterLabel on _CertFilter {
  String get label => switch (this) {
        _CertFilter.all => 'All',
        _CertFilter.expiringSoon => 'Expiring soon',
        _CertFilter.expired => 'Expired',
      };
}

class CertificatesListScreen extends ConsumerStatefulWidget {
  const CertificatesListScreen({super.key});

  @override
  ConsumerState<CertificatesListScreen> createState() =>
      _CertificatesListScreenState();
}

class _CertificatesListScreenState
    extends ConsumerState<CertificatesListScreen> {
  _CertFilter _filter = _CertFilter.all;

  List<Certificate> _applyFilter(List<Certificate> input) {
    return input.where((c) {
      switch (_filter) {
        case _CertFilter.all:
          return true;
        case _CertFilter.expiringSoon:
          return c.isExpiringWithin(days: 30);
        case _CertFilter.expired:
          return c.isExpired;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final asyncCerts = ref.watch(certificatesListNotifierProvider);

    return Scaffold(
      appBar: EqAppBar(
        title: 'Certificates',
        withBranding: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add certificate',
            onPressed: () => context.go(Routes.certificateCreate),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.read(certificatesListNotifierProvider.notifier).refresh(),
        child: asyncCerts.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(EqSpacing.lg),
                child: _ErrorState(
                  error: e,
                  onRetry: () => ref
                      .read(certificatesListNotifierProvider.notifier)
                      .refresh(),
                  onSignInAgain: () =>
                      ref.read(authRepositoryProvider).signOut(),
                ),
              ),
            ],
          ),
          data: (certs) {
            if (certs.isEmpty) {
              return ListView(
                children: [
                  _EmptyState(
                    onAdd: () => context.go(Routes.certificateCreate),
                  ),
                ],
              );
            }

            final filtered = _applyFilter(certs);

            return ListView(
              padding: const EdgeInsets.all(EqSpacing.md),
              children: [
                // Filter chips
                if (certs.length > 2) ...[
                  Row(
                    children: [
                      for (final f in _CertFilter.values) ...[
                        ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                          selectedColor: EqColours.deep,
                          backgroundColor: EqColours.ice,
                          labelStyle: TextStyle(
                            color: _filter == f
                                ? EqColours.white
                                : EqColours.ink,
                            fontWeight: _filter == f
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide.none,
                          ),
                        ),
                        const SizedBox(width: EqSpacing.xs),
                      ],
                    ],
                  ),
                  const SizedBox(height: EqSpacing.sm),
                ],
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: EqSpacing.xl,
                      horizontal: EqSpacing.lg,
                    ),
                    child: Text(
                      'No matches for this filter.',
                      style: EqTypography.bodyM
                          .copyWith(color: EqColours.grey),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final cert in filtered) ...[
                    CertificateCard(
                      certificate: cert,
                      typeLabel: certTypeLabels[cert.certificateType] ??
                          cert.certificateType,
                      onTap: () => context
                          .go(Routes.certificateDetailFor(cert.id!)),
                    ),
                    const SizedBox(height: EqSpacing.sm),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: EqSpacing.lg,
        vertical: EqSpacing.xxl,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            size: 64,
            color: EqColours.grey,
          ),
          const SizedBox(height: EqSpacing.md),
          Text(
            'No certificates yet',
            style: EqTypography.headingL,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'Add your First Aid cert, Working at Heights ticket, '
            'LV CPR card — anything you carry on site.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xl),
          EqButton(label: 'Add certificate', onPressed: onAdd, fullWidth: true),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.onRetry,
    required this.onSignInAgain,
  });

  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignInAgain;

  bool get _isAuthError {
    if (error is NotAuthenticatedFailure) return true;
    if (error is ServerFailure) {
      final msg = (error as ServerFailure).message.toLowerCase();
      return msg.contains('jwt') || msg.contains('token');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          _isAuthError ? Icons.lock_outline : Icons.cloud_off_outlined,
          size: 48,
          color: EqColours.grey,
        ),
        const SizedBox(height: EqSpacing.md),
        Text(
          _isAuthError ? 'Sign in again' : "Couldn't load certificates",
          style: EqTypography.headingL,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: EqSpacing.sm),
        Text(
          userMessageForError(error),
          style: EqTypography.bodyM.copyWith(color: EqColours.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: EqSpacing.xl),
        EqButton(
          label: _isAuthError ? 'Sign in again' : 'Try again',
          onPressed: _isAuthError ? onSignInAgain : onRetry,
          fullWidth: true,
        ),
      ],
    );
  }
}
