import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/clipboard_utils.dart';

/// One row of the profile view — a label + value pair that's tappable to copy
/// the value to the clipboard. Empty values render as `—` and the row is
/// non-tappable.
///
/// When [isPhone] is true, tapping opens a bottom sheet offering "Call" and
/// "Copy number" — useful for the Mobile field. The copy-only behaviour is
/// preserved for all other fields.
///
/// Accessibility: announces as `<label>, <value>, button` when filled, or
/// `<label>, not set` when empty. Children's individual text semantics are
/// excluded so the row reads as a single announcement.
class ProfileFieldRow extends StatelessWidget {
  const ProfileFieldRow({
    super.key,
    required this.label,
    required this.value,
    this.isPhone = false,
  });

  final String label;
  final String? value;

  /// When true, tapping shows a Call / Copy bottom sheet instead of
  /// copying directly. Ignored when [value] is empty.
  final bool isPhone;

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.trim().isNotEmpty;
    return Semantics(
      button: filled,
      label: filled ? '$label, ${value!}' : '$label, not set',
      excludeSemantics: true,
      child: InkWell(
        onTap: filled
            ? () {
                if (isPhone) {
                  unawaited(_showPhoneSheet(context, value!));
                } else {
                  unawaited(copyWithFeedback(
                    context: context,
                    value: value!,
                    label: label,
                  ));
                }
              }
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
                Icon(
                  isPhone ? Icons.phone_outlined : Icons.content_copy_outlined,
                  size: 20,
                  color: EqColours.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPhoneSheet(BuildContext context, String number) {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: EqSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: EqColours.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: EqSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EqSpacing.lg),
              child: Text(
                number,
                style: EqTypography.headingM.copyWith(color: EqColours.ink),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: EqSpacing.sm),
            ListTile(
              leading: const Icon(Icons.phone_outlined, color: EqColours.sky),
              title: const Text('Call'),
              onTap: () {
                Navigator.pop(context);
                unawaited(launchUrl(Uri(scheme: 'tel', path: number)));
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.content_copy_outlined,
                color: EqColours.ink,
              ),
              title: const Text('Copy number'),
              onTap: () {
                Navigator.pop(context);
                unawaited(copyWithFeedback(
                  context: context,
                  value: number,
                  label: 'Mobile',
                ));
              },
            ),
            const SizedBox(height: EqSpacing.md),
          ],
        ),
      ),
    );
  }
}
