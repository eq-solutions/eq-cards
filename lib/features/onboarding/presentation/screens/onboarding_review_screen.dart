import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/invite/invite_context_provider.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../certificates/certificates.dart';
import '../../../licences/licences.dart';
import '../../../profile/presentation/notifiers/profile_notifier.dart';
import '../widgets/wizard_shell.dart';

class OnboardingReviewScreen extends ConsumerStatefulWidget {
  const OnboardingReviewScreen({super.key});

  @override
  ConsumerState<OnboardingReviewScreen> createState() =>
      _OnboardingReviewScreenState();
}

class _OnboardingReviewScreenState
    extends ConsumerState<OnboardingReviewScreen> {
  bool _consented = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileNotifierProvider).value;
    final orgName = ref.watch(initialOrgNameProvider);
    final licenceCount =
        ref.watch(licencesListNotifierProvider).value?.length ?? 0;
    final certCount =
        ref.watch(certificatesListNotifierProvider).value?.length ?? 0;
    final walletTotal = licenceCount + certCount;

    final consentText = orgName != null
        ? "I confirm that the information I've provided is accurate and consent to it being shared with $orgName for employment purposes."
        : "I confirm that the information I've provided is accurate and consent to it being used for employment purposes.";

    return WizardShell(
      step: 4,
      totalSteps: 4,
      actionLabel: 'Submit onboarding',
      onAction: () => context.go(Routes.onboardingDone),
      onBack: () => context.go(Routes.onboardingWallet),
      actionEnabled: _consented,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          EqSpacing.xl, EqSpacing.lg, EqSpacing.xl, EqSpacing.lg,
        ),
        children: [
          Text('Review your details', style: EqTypography.headingL),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'Check everything looks right before submitting.',
            style: EqTypography.bodyM.copyWith(color: EqColours.g500),
          ),
          const SizedBox(height: EqSpacing.xl),

          // You
          _ReviewSection(
            title: 'You',
            rows: [
              _ReviewRow('Name', profile?.fullName),
              _ReviewRow(
                'Date of birth',
                profile?.dateOfBirth != null
                    ? DateFormat('d MMM yyyy').format(profile!.dateOfBirth!)
                    : null,
              ),
              _ReviewRow('Mobile', profile?.mobile),
              _ReviewRow('Email', profile?.email),
            ],
          ),
          const SizedBox(height: EqSpacing.lg),

          // Address
          _ReviewSection(
            title: 'Address',
            rows: [
              _ReviewRow('Street', profile?.addressStreet),
              _ReviewRow('Suburb', profile?.addressSuburb),
              _ReviewRow('State', profile?.addressState),
              _ReviewRow('Postcode', profile?.addressPostcode),
            ],
          ),
          const SizedBox(height: EqSpacing.lg),

          // Emergency contact
          _ReviewSection(
            title: 'Emergency contact',
            rows: [
              _ReviewRow('Name', profile?.emergencyContactName),
              _ReviewRow(
                  'Relationship', profile?.emergencyContactRelationship),
              _ReviewRow('Mobile', profile?.emergencyContactMobile),
            ],
          ),
          const SizedBox(height: EqSpacing.lg),

          // Wallet
          _ReviewSection(
            title: 'Wallet',
            rows: [
              _ReviewRow(
                'Items',
                walletTotal == 0
                    ? 'None added yet'
                    : '$walletTotal item${walletTotal == 1 ? '' : 's'}',
              ),
            ],
          ),
          const SizedBox(height: EqSpacing.xl),

          // Consent block (ice bg, V9 spec)
          GestureDetector(
            onTap: () => setState(() => _consented = !_consented),
            child: Container(
              padding: const EdgeInsets.all(EqSpacing.md),
              decoration: BoxDecoration(
                color: EqColours.ice,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _consented ? EqColours.sky : EqColours.outline,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _consented,
                      onChanged: (v) =>
                          setState(() => _consented = v ?? false),
                      activeColor: EqColours.sky,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: EqSpacing.sm),
                  Expanded(
                    child: Text(
                      consentText,
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: EqSpacing.md),
        ],
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.title, required this.rows});

  final String title;
  final List<_ReviewRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sky section header (V9 rev-h spec)
        Padding(
          padding: const EdgeInsets.only(bottom: EqSpacing.sm),
          child: Text(
            title.toUpperCase(),
            style: EqTypography.label.copyWith(
              color: EqColours.sky,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: EqColours.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: EqColours.outlineSoft),
          ),
          child: Column(
            children: rows.map((row) {
              final isLast = row == rows.last;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: EqSpacing.md,
                  vertical: 12,
                ),
                decoration: isLast
                    ? null
                    : const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: EqColours.outlineSoft),
                        ),
                      ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        row.label,
                        style: EqTypography.bodyM.copyWith(
                          color: EqColours.g500,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row.value ?? '—',
                        style: EqTypography.bodyM.copyWith(
                          color: row.value != null
                              ? EqColours.ink
                              : EqColours.g500,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ReviewRow {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String? value;
}
