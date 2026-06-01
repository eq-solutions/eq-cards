import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../data/models/profile.dart';
import '../notifiers/profile_notifier.dart';
import '../widgets/copy_induction_block.dart';
import '../widgets/profile_field_row.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(profileNotifierProvider);

    return Scaffold(
      appBar: EqAppBar(
        title: 'Profile',
        withBranding: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(Routes.profileEdit),
            tooltip: 'Edit',
          ),
        ],
      ),
      body: asyncProfile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(EqSpacing.lg),
            child: Text(
              'Could not load profile.\n${userMessageForError(e)}',
              style: EqTypography.bodyM,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return _EmptyState(
              onTap: () => context.push(Routes.profileEdit),
            );
          }
          return _Populated(profile: profile);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EqSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'No profile yet',
            style: EqTypography.headingL,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'Add your details once and tap-to-copy them onto every induction form.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xl),
          EqButton(
            label: 'Set up profile',
            onPressed: onTap,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _Populated extends StatelessWidget {
  const _Populated({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final dob = profile.dateOfBirth == null
        ? null
        : DateFormat('d MMM yyyy').format(profile.dateOfBirth!);
    final emergency = [
      profile.emergencyContactName,
      if (profile.emergencyContactRelationship != null)
        '(${profile.emergencyContactRelationship})',
      profile.emergencyContactMobile,
    ].where((s) => s != null && s.isNotEmpty).join(' ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!profile.isComplete)
            _IncompleteHint(
              onTap: () => context.go(Routes.profileEdit),
            ),
          EqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ProfileFieldRow(label: 'Full name', value: profile.fullName),
                const Divider(height: 1),
                ProfileFieldRow(label: 'Date of birth', value: dob),
                const Divider(height: 1),
                ProfileFieldRow(label: 'Mobile', value: profile.mobile, isPhone: true),
                const Divider(height: 1),
                ProfileFieldRow(label: 'Email', value: profile.email),
                const Divider(height: 1),
                ProfileFieldRow(
                  label: 'Address',
                  value: profile.fullAddress,
                ),
                const Divider(height: 1),
                ProfileFieldRow(
                  label: 'Emergency contact',
                  value: emergency.isEmpty ? null : emergency,
                ),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.md),
          CopyInductionBlock(profile: profile),
        ],
      ),
    );
  }
}

class _IncompleteHint extends StatelessWidget {
  const _IncompleteHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: EqSpacing.md),
      padding: const EdgeInsets.all(EqSpacing.md),
      decoration: BoxDecoration(
        color: EqColours.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: EqColours.warning),
          const SizedBox(width: EqSpacing.sm),
          const Expanded(
            child: Text(
              'Profile incomplete — finish to unlock full induction-block copy.',
              style: EqTypography.bodyM,
            ),
          ),
          TextButton(onPressed: onTap, child: const Text('Finish')),
        ],
      ),
    );
  }
}
