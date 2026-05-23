import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/design/design_version.dart';
import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/clipboard_utils.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../data/licence_repository.dart';
import '../../data/models/licence.dart';
import '../notifiers/licence_types_provider.dart';
import '../notifiers/licences_list_notifier.dart';
import '../widgets/expiry_badge.dart';

class LicenceDetailScreen extends ConsumerWidget {
  const LicenceDetailScreen({super.key, required this.licenceId});

  final String licenceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLicence = ref.watch(licenceDetailProvider(licenceId));
    final asyncTypes = ref.watch(licenceTypesProvider);

    return Scaffold(
      appBar: EqAppBar(
        title: 'Licence',
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2_outlined),
            onPressed: () {
              asyncLicence.whenData((l) => _showShareSheet(context, l));
            },
            tooltip: 'Share via QR',
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.go(Routes.licenceEditFor(licenceId)),
            tooltip: 'Edit',
          ),
        ],
      ),
      body: asyncLicence.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(userMessageForError(e))),
        data: (licence) {
          final typeLabel = asyncTypes.maybeWhen(
            data: (types) => types
                .firstWhere(
                  (t) => t.code == licence.licenceType,
                  orElse: () => types.first,
                )
                .label,
            orElse: () => licence.licenceType,
          );
          return LicenceDetailBody(
            licence: licence,
            typeLabel: typeLabel,
            onDelete: () => _confirmDelete(context, ref, licence),
            version: ref.watch(designVersionNotifierProvider),
          );
        },
      ),
    );
  }

  Future<void> _showShareSheet(BuildContext context, Licence licence) async {
    final url = 'https://cards.eq.solutions/share?licence_id=${licence.id}';
    unawaited(
      AnalyticsService.track('qr_generated', {'licence_id': licence.id ?? ''}),
    );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EqColours.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Share this licence', style: EqTypography.headingM),
              const SizedBox(height: EqSpacing.sm),
              Text(
                'Anyone who scans this code can view your licence details. '
                'Share it with a supervisor or site manager to verify your '
                'card on the spot.',
                style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              ),
              const SizedBox(height: EqSpacing.lg),
              Center(
                child: QrImageView(
                  data: url,
                  size: 240,
                  backgroundColor: EqColours.white,
                ),
              ),
              const SizedBox(height: EqSpacing.lg),
              EqButton(
                label: 'Copy link',
                onPressed: () => copyWithFeedback(
                  context: sheetContext,
                  value: url,
                  label: 'Share link',
                ),
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Licence licence,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete licence?'),
        content: Text(
          'This will remove ${licence.licenceNumber} from your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: EqColours.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(licencesListNotifierProvider.notifier)
        .deleteLicence(licence.id!);
    unawaited(AnalyticsService.track('licence_deleted'));
    if (context.mounted) context.go(Routes.licencesList);
  }
}

final licenceDetailProvider =
    FutureProvider.family<Licence, String>((ref, id) async {
  return ref.read(licenceRepositoryProvider).getById(id);
});

/// Pure presentational body for `LicenceDetailScreen`. Public so it can be
/// widget-tested directly with a known `Licence` without a real Supabase
/// client.
class LicenceDetailBody extends StatelessWidget {
  const LicenceDetailBody({
    super.key,
    required this.licence,
    required this.typeLabel,
    required this.onDelete,
    this.version = DesignVersion.linear,
  });

  final Licence licence;
  final String typeLabel;
  final VoidCallback onDelete;
  final DesignVersion version;

  @override
  Widget build(BuildContext context) {
    return switch (version) {
      DesignVersion.linear => _LinearDetail(
          licence: licence,
          typeLabel: typeLabel,
          onDelete: onDelete,
        ),
      DesignVersion.wallet => _WalletDetail(
          licence: licence,
          typeLabel: typeLabel,
          onDelete: onDelete,
        ),
      DesignVersion.photoFirst => _PhotoFirstDetail(
          licence: licence,
          typeLabel: typeLabel,
          onDelete: onDelete,
        ),
    };
  }
}

// ============================================================
// Linear — stacked rows, photos at top, the original 0.1.0.
// ============================================================
class _LinearDetail extends StatelessWidget {
  const _LinearDetail({
    required this.licence,
    required this.typeLabel,
    required this.onDelete,
  });

  final Licence licence;
  final String typeLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final issueText = DateFormat('d MMM yyyy').format(licence.issueDate);
    final expiryText = DateFormat('d MMM yyyy').format(licence.expiryDate);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (licence.photoFrontSignedUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                licence.photoFrontSignedUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 200),
              ),
            ),
          if (licence.photoBackSignedUrl != null) ...[
            const SizedBox(height: EqSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                licence.photoBackSignedUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 200),
              ),
            ),
          ],
          const SizedBox(height: EqSpacing.md),
          EqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Row(label: 'Type', value: typeLabel),
                const Divider(height: 1),
                _CopyRow(label: 'Number', value: licence.licenceNumber),
                const Divider(height: 1),
                _Row(label: 'Issued', value: issueText),
                const Divider(height: 1),
                _Row(
                  label: 'Expires',
                  value: expiryText,
                  trailing: ExpiryBadge(expiry: licence.expiryDate),
                ),
                if (licence.state != null) ...[
                  const Divider(height: 1),
                  _CopyRow(label: 'State', value: licence.state!),
                ],
                if (licence.issuingAuthority != null) ...[
                  const Divider(height: 1),
                  _CopyRow(
                    label: 'Issuing authority',
                    value: licence.issuingAuthority!,
                  ),
                ],
                ..._metadataRowsFor(licence),
                if (licence.notes != null) ...[
                  const Divider(height: 1),
                  _Row(label: 'Notes', value: licence.notes!),
                ],
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.lg),
          EqButton(
            label: 'Delete licence',
            onPressed: onDelete,
            variant: EqButtonVariant.destructive,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Wallet — sticky brand-stripe card header, then rows below. The header
// stays visible while the rows scroll.
// ============================================================
class _WalletDetail extends StatelessWidget {
  const _WalletDetail({
    required this.licence,
    required this.typeLabel,
    required this.onDelete,
  });

  final Licence licence;
  final String typeLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final issueText = DateFormat('d MMM yyyy').format(licence.issueDate);
    final expiryText = DateFormat('d MMM yyyy').format(licence.expiryDate);

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _WalletHeaderDelegate(
            licence: licence,
            typeLabel: typeLabel,
            expiryText: expiryText,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(EqSpacing.md),
          sliver: SliverList.list(
            children: [
              EqCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _CopyRow(label: 'Number', value: licence.licenceNumber),
                    const Divider(height: 1),
                    _Row(label: 'Issued', value: issueText),
                    const Divider(height: 1),
                    _Row(
                      label: 'Expires',
                      value: expiryText,
                      trailing: ExpiryBadge(expiry: licence.expiryDate),
                    ),
                    if (licence.state != null) ...[
                      const Divider(height: 1),
                      _CopyRow(label: 'State', value: licence.state!),
                    ],
                    if (licence.issuingAuthority != null) ...[
                      const Divider(height: 1),
                      _CopyRow(
                        label: 'Issuing authority',
                        value: licence.issuingAuthority!,
                      ),
                    ],
                    ..._metadataRowsFor(licence),
                    if (licence.notes != null) ...[
                      const Divider(height: 1),
                      _Row(label: 'Notes', value: licence.notes!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: EqSpacing.lg),
              EqButton(
                label: 'Delete licence',
                onPressed: onDelete,
                variant: EqButtonVariant.destructive,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletHeaderDelegate extends SliverPersistentHeaderDelegate {
  _WalletHeaderDelegate({
    required this.licence,
    required this.typeLabel,
    required this.expiryText,
  });

  final Licence licence;
  final String typeLabel;
  final String expiryText;

  @override
  double get minExtent => 180;
  @override
  double get maxExtent => 200;

  @override
  bool shouldRebuild(covariant _WalletHeaderDelegate oldDelegate) =>
      oldDelegate.licence != licence;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: EqColours.white,
      padding: const EdgeInsets.fromLTRB(
        EqSpacing.md,
        EqSpacing.md,
        EqSpacing.md,
        EqSpacing.sm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: EqColours.ice,
          child: Stack(
            children: [
              const ColoredBox(
                color: EqColours.sky,
                child: SizedBox(height: 8, width: double.infinity),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  EqSpacing.lg,
                  EqSpacing.lg + 4,
                  EqSpacing.lg,
                  EqSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeLabel.toUpperCase(),
                      style: EqTypography.label.copyWith(
                        letterSpacing: 1.2,
                        color: EqColours.deep,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: EqSpacing.xs),
                    Text(
                      licence.licenceNumber,
                      style: EqTypography.headingL.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          'Expires $expiryText',
                          style: EqTypography.bodyM.copyWith(
                            color: EqColours.grey,
                          ),
                        ),
                        const SizedBox(width: EqSpacing.sm),
                        ExpiryBadge(expiry: licence.expiryDate),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Photo-first — full-bleed photo header, info in a sheet below.
// ============================================================
class _PhotoFirstDetail extends StatelessWidget {
  const _PhotoFirstDetail({
    required this.licence,
    required this.typeLabel,
    required this.onDelete,
  });

  final Licence licence;
  final String typeLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final issueText = DateFormat('d MMM yyyy').format(licence.issueDate);
    final expiryText = DateFormat('d MMM yyyy').format(licence.expiryDate);
    final hasPhoto = licence.photoFrontSignedUrl != null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AspectRatio(
            aspectRatio: 1.586,
            child: ColoredBox(
              color: hasPhoto ? EqColours.ink : EqColours.deep,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasPhoto)
                    Image.network(
                      licence.photoFrontSignedUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    )
                  else
                    const Center(
                      child: Icon(
                        Icons.badge_outlined,
                        color: EqColours.white,
                        size: 80,
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                        stops: [0.55, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: EqSpacing.lg,
                    right: EqSpacing.lg,
                    bottom: EqSpacing.lg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          typeLabel,
                          style: EqTypography.bodyL.copyWith(
                            color: EqColours.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: EqSpacing.xs),
                        Text(
                          licence.licenceNumber,
                          style: EqTypography.headingXL.copyWith(
                            color: EqColours.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(EqSpacing.md),
          sliver: SliverList.list(
            children: [
              EqCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _CopyRow(label: 'Number', value: licence.licenceNumber),
                    const Divider(height: 1),
                    _Row(label: 'Issued', value: issueText),
                    const Divider(height: 1),
                    _Row(
                      label: 'Expires',
                      value: expiryText,
                      trailing: ExpiryBadge(expiry: licence.expiryDate),
                    ),
                    if (licence.state != null) ...[
                      const Divider(height: 1),
                      _CopyRow(label: 'State', value: licence.state!),
                    ],
                    if (licence.issuingAuthority != null) ...[
                      const Divider(height: 1),
                      _CopyRow(
                        label: 'Issuing authority',
                        value: licence.issuingAuthority!,
                      ),
                    ],
                    ..._metadataRowsFor(licence),
                    if (licence.notes != null) ...[
                      const Divider(height: 1),
                      _Row(label: 'Notes', value: licence.notes!),
                    ],
                  ],
                ),
              ),
              if (licence.photoBackSignedUrl != null) ...[
                const SizedBox(height: EqSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    licence.photoBackSignedUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(height: 200),
                  ),
                ),
              ],
              const SizedBox(height: EqSpacing.lg),
              EqButton(
                label: 'Delete licence',
                onPressed: onDelete,
                variant: EqButtonVariant.destructive,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

List<Widget> _metadataRowsFor(Licence l) {
  if (l.metadata.isEmpty) return const [];
  final rows = <Widget>[];
  for (final entry in l.metadata.entries) {
    rows.add(const Divider(height: 1));
    rows.add(_CopyRow(label: _humanise(entry.key), value: '${entry.value}'));
  }
  return rows;
}

String _humanise(String key) {
  return key
      .split('_')
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: EqTypography.label),
                const SizedBox(height: EqSpacing.xs),
                Text(value, style: EqTypography.bodyL),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => copyWithFeedback(
          context: context,
          value: value,
          label: label,
        ),
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: EqTypography.label),
                    const SizedBox(height: EqSpacing.xs),
                    Text(value, style: EqTypography.bodyL),
                  ],
                ),
              ),
              const Icon(
                Icons.content_copy_outlined,
                size: 20,
                color: EqColours.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
