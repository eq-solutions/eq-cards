import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/utils/clipboard_utils.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../data/models/profile.dart';

class CopyInductionBlock extends StatelessWidget {
  const CopyInductionBlock({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: EqButton(
        label: 'Copy all profile fields',
        onPressed: () {
          final block = _formatBlock(profile);
          unawaited(AnalyticsService.track('copy_induction_block'));
          copyWithFeedback(
            context: context,
            value: block,
            label: 'Profile block',
          );
        },
        fullWidth: true,
      ),
    );
  }

  String _formatBlock(Profile p) {
    final dob = p.dateOfBirth == null
        ? null
        : DateFormat('d MMM yyyy').format(p.dateOfBirth!);
    final emergency = [
      p.emergencyContactName,
      if (p.emergencyContactRelationship != null)
        '(${p.emergencyContactRelationship})',
      p.emergencyContactMobile,
    ].where((s) => s != null && s.isNotEmpty).join(' ');

    final lines = <String>[
      if (p.fullName != null) 'Name: ${p.fullName}',
      if (dob != null) 'DOB: $dob',
      if (p.mobile != null) 'Mobile: ${p.mobile}',
      if (p.email != null) 'Email: ${p.email}',
      if (p.fullAddress != null) 'Address: ${p.fullAddress}',
      if (emergency.isNotEmpty) 'Emergency: $emergency',
    ];
    return lines.join('\n');
  }
}
