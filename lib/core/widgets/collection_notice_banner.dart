import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';
import '../theme/eq_typography.dart';

/// One-time dismissable info strip for APP 5 collection notices. Shown once
/// per screen; dismissed state is persisted by the caller via
/// CollectionNoticePrefs.
class CollectionNoticeBanner extends StatelessWidget {
  const CollectionNoticeBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: EqSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: EqSpacing.md,
        vertical: EqSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: EqColours.ice,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EqColours.sky.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline, size: 16, color: EqColours.sky),
          ),
          const SizedBox(width: EqSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: EqTypography.label.copyWith(
                color: EqColours.deep,
                height: 1.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.only(left: EqSpacing.sm),
              child: Icon(Icons.close, size: 16, color: EqColours.grey),
            ),
          ),
        ],
      ),
    );
  }
}
