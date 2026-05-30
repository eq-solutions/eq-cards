import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../../licences/presentation/widgets/expiry_badge.dart';
import '../../data/models/certificate.dart';

class CertificateCard extends StatelessWidget {
  const CertificateCard({
    super.key,
    required this.certificate,
    required this.typeLabel,
    this.onTap,
    this.onLongPress,
  });

  final Certificate certificate;
  final String typeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final expiryText = certificate.expiryDate != null
        ? DateFormat('d MMM yyyy').format(certificate.expiryDate!)
        : null;

    return Semantics(
      label: [
        typeLabel,
        if (certificate.issuer != null) certificate.issuer,
        if (expiryText != null) 'expires $expiryText',
      ].join(', '),
      button: onTap != null,
      excludeSemantics: true,
      child: EqCard(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _FileIcon(isPdf: certificate.isPdf, size: 56),
            const SizedBox(width: EqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    certificate.title,
                    style: EqTypography.bodyL.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (certificate.issuer != null) ...[
                    const SizedBox(height: EqSpacing.xs),
                    Text(
                      certificate.issuer!,
                      style:
                          EqTypography.bodyM.copyWith(color: EqColours.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (expiryText != null) ...[
                    const SizedBox(height: EqSpacing.xs),
                    Row(
                      children: [
                        Text(
                          'Expires $expiryText',
                          style: EqTypography.label,
                        ),
                        const SizedBox(width: EqSpacing.sm),
                        ExpiryBadge(expiry: certificate.expiryDate!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.isPdf, required this.size});

  final bool isPdf;
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
      child: Icon(
        isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
        color: EqColours.deep,
        size: size * 0.5,
      ),
    );
  }
}
