import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../data/connections_repository.dart';
import '../notifiers/connections_notifier.dart';

/// Banner displayed at the top of the wallet when there are pending org
/// access requests. Each row shows the org name and two action buttons.
/// Disappears automatically once all pending items are resolved.
class PendingConnectionsBanner extends ConsumerWidget {
  const PendingConnectionsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingConnectionsNotifierProvider);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (pending) {
        if (pending.isEmpty) return const SizedBox.shrink();
        return _BannerCard(pending: pending);
      },
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.pending});

  final List<PendingConnection> pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: EqSpacing.md),
      decoration: BoxDecoration(
        color: EqColours.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: EqColours.sky, width: 4),
          top: BorderSide(color: EqColours.outlineSoft),
          right: BorderSide(color: EqColours.outlineSoft),
          bottom: BorderSide(color: EqColours.outlineSoft),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(EqSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.business_outlined,
                  size: 18,
                  color: EqColours.sky,
                ),
                const SizedBox(width: EqSpacing.xs),
                Text(
                  'Company access requests',
                  style: EqTypography.headingM,
                ),
              ],
            ),
            const SizedBox(height: EqSpacing.sm),
            for (int i = 0; i < pending.length; i++) ...[
              if (i > 0) const Divider(height: EqSpacing.lg),
              _ConnectionRow(connection: pending[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionRow extends ConsumerWidget {
  const _ConnectionRow({required this.connection});

  final PendingConnection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(pendingConnectionsNotifierProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo or fallback initials avatar.
            _OrgAvatar(
              orgName: connection.orgName,
              logoUrl: connection.orgLogoUrl,
            ),
            const SizedBox(width: EqSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connection.orgName,
                    style: EqTypography.bodyL.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'wants to connect — so they can add you to jobs without '
                    'you re-entering your tickets',
                    style: EqTypography.label.copyWith(color: EqColours.g500),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: EqSpacing.sm),
        Row(
          children: [
            Expanded(
              child: EqButton(
                label: 'Accept',
                onPressed: () async {
                  // Capture before the await so we never use context across
                  // the async gap.
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await notifier.accept(connection.id);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '${connection.orgName} can now see your licences and '
                          "expiries. They can't edit or delete them — you can "
                          'disconnect anytime.',
                        ),
                        duration: const Duration(seconds: 6),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: EqColours.deep,
                      ),
                    );
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Could not connect. Please try again.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                fullWidth: true,
              ),
            ),
            const SizedBox(width: EqSpacing.sm),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: EqColours.deep,
                  side: const BorderSide(color: EqColours.deep),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => notifier.decline(connection.id),
                child: Text(
                  'Decline',
                  style: EqTypography.bodyM.copyWith(
                    color: EqColours.deep,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Circular avatar — shows the org logo when [logoUrl] is set, otherwise
/// a 2-character initials chip in EQ ice/deep colours.
class _OrgAvatar extends StatelessWidget {
  const _OrgAvatar({required this.orgName, this.logoUrl});

  final String orgName;
  final String? logoUrl;

  String get _initials {
    final words = orgName.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return orgName.substring(0, orgName.length.clamp(1, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    return CircleAvatar(
      radius: 20,
      backgroundColor: EqColours.ice,
      backgroundImage: url != null ? NetworkImage(url) : null,
      onBackgroundImageError: url != null ? (_, _) {} : null,
      child: url == null
          ? Text(
              _initials,
              style: EqTypography.label.copyWith(
                color: EqColours.deep,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}
