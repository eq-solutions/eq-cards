import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/design_version.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../data/models/licence.dart';
import 'expiry_badge.dart';

/// Public licence card. Dispatches to one of three layouts based on the
/// passed-in [version]. Default is `linear` so existing widget tests that
/// don't construct a ProviderScope keep producing the original rendering.
class LicenceCard extends StatelessWidget {
  const LicenceCard({
    super.key,
    required this.licence,
    required this.typeLabel,
    this.onTap,
    this.onLongPress,
    this.version = DesignVersion.linear,
  });

  final Licence licence;
  final String typeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final DesignVersion version;

  @override
  Widget build(BuildContext context) {
    final expiry = DateFormat('d MMMM yyyy').format(licence.expiryDate);
    return Semantics(
      // One coherent screen-reader announcement per card regardless of which
      // visual variant is rendered. Without this the wallet/photo variants
      // would announce raw text fragments in unpredictable order.
      label: '$typeLabel, ${licence.licenceNumber}, expires $expiry',
      button: onTap != null,
      excludeSemantics: true,
      child: switch (version) {
        DesignVersion.linear => _LinearVariant(
            licence: licence,
            typeLabel: typeLabel,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        DesignVersion.wallet => _WalletVariant(
            licence: licence,
            typeLabel: typeLabel,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        DesignVersion.photoFirst => _PhotoFirstVariant(
            licence: licence,
            typeLabel: typeLabel,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
      },
    );
  }
}

// =====================================================================
// Linear — thin border, no shadow, fields stacked. The original 0.1.0
// treatment kept as the safe default.
// =====================================================================
class _LinearVariant extends StatelessWidget {
  const _LinearVariant({
    required this.licence,
    required this.typeLabel,
    this.onTap,
    this.onLongPress,
  });

  final Licence licence;
  final String typeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final expiryText = DateFormat('d MMM yyyy').format(licence.expiryDate);
    return EqCard(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Thumbnail(url: licence.photoFrontSignedUrl, size: 56),
          const SizedBox(width: EqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: EqTypography.bodyL.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: EqSpacing.xs),
                Text(
                  licence.licenceNumber,
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                ),
                const SizedBox(height: EqSpacing.xs),
                Row(
                  children: [
                    Text(
                      'Expires $expiryText',
                      style: EqTypography.label,
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
    );
  }
}

// =====================================================================
// Wallet — Apple Wallet pass-style. Brand stripe at top, type as oversized
// title, photo overlapping bottom edge. Tradies recognise the metaphor.
// =====================================================================
class _WalletVariant extends StatelessWidget {
  const _WalletVariant({
    required this.licence,
    required this.typeLabel,
    this.onTap,
    this.onLongPress,
  });

  final Licence licence;
  final String typeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final expiryText = DateFormat('d MMM yyyy').format(licence.expiryDate);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EqSpacing.xs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: EqColours.white,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              children: [
                // Brand stripe header.
                Container(
                  height: 8,
                  decoration: const BoxDecoration(color: EqColours.sky),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    EqSpacing.md,
                    EqSpacing.lg + 4,
                    EqSpacing.md,
                    EqSpacing.md,
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
                      const SizedBox(height: EqSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EXPIRES',
                                  style: EqTypography.label.copyWith(
                                    letterSpacing: 1.2,
                                    color: EqColours.grey,
                                  ),
                                ),
                                const SizedBox(height: EqSpacing.xs),
                                Text(
                                  expiryText,
                                  style: EqTypography.bodyL.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ExpiryBadge(expiry: licence.expiryDate),
                          const SizedBox(width: EqSpacing.sm),
                          _Thumbnail(
                            url: licence.photoFrontSignedUrl,
                            size: 64,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Photo-first — licence photo dominates, text overlays a scrim. Most "card
// in your pocket" feel. Falls back to a tinted placeholder when no photo.
// =====================================================================
class _PhotoFirstVariant extends StatelessWidget {
  const _PhotoFirstVariant({
    required this.licence,
    required this.typeLabel,
    this.onTap,
    this.onLongPress,
  });

  final Licence licence;
  final String typeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final expiryText = DateFormat('d MMM yyyy').format(licence.expiryDate);
    final hasPhoto = licence.photoFrontSignedUrl != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EqSpacing.xs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: hasPhoto ? EqColours.ink : EqColours.deep,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: AspectRatio(
              aspectRatio: 1.586, // ID-1 card ratio (CR80, ISO/IEC 7810).
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasPhoto)
                    Image.network(
                      licence.photoFrontSignedUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  else
                    const Center(
                      child: Icon(
                        Icons.badge_outlined,
                        color: EqColours.white,
                        size: 64,
                      ),
                    ),
                  // Bottom scrim — make text legible regardless of photo.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: EqSpacing.md,
                    right: EqSpacing.md,
                    bottom: EqSpacing.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                typeLabel,
                                style: EqTypography.bodyL.copyWith(
                                  color: EqColours.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ExpiryBadge(expiry: licence.expiryDate),
                          ],
                        ),
                        const SizedBox(height: EqSpacing.xs),
                        Text(
                          licence.licenceNumber,
                          style: EqTypography.headingM.copyWith(
                            color: EqColours.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: EqSpacing.xs),
                        Text(
                          'Expires $expiryText',
                          style: EqTypography.label.copyWith(
                            color: EqColours.white.withValues(alpha: 0.85),
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
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url == null) return _Placeholder(size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _Placeholder(size: size),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: EqColours.ice,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.badge_outlined, color: EqColours.grey),
    );
  }
}
