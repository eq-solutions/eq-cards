import 'package:flutter/material.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/clipboard_utils.dart';

/// One row of the profile view — a label + value pair that's tappable to copy
/// the value to the clipboard. Empty values render as `—` and the row is
/// non-tappable.
///
/// Accessibility: announces as `<label>, <value>, button` when filled, or
/// `<label>, not set` when empty. Children's individual text semantics are
/// excluded so the row reads as a single announcement.
class ProfileFieldRow extends StatelessWidget {
  const ProfileFieldRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.trim().isNotEmpty;
    return Semantics(
      button: filled,
      label: filled ? '$label, ${value!}' : '$label, not set',
      excludeSemantics: true,
      child: InkWell(
        onTap: filled
            ? () => copyWithFeedback(
                  context: context,
                  value: value!,
                  label: label,
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EqSpacing.md,
            vertical: EqSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: EqTypography.label),
                    const SizedBox(height: EqSpacing.xs),
                    Text(
                      filled ? value! : '—',
                      style: EqTypography.bodyL.copyWith(
                        color: filled ? EqColours.ink : EqColours.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (filled)
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
