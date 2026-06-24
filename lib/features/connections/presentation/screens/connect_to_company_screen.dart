import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../data/connections_repository.dart';

class ConnectToCompanyScreen extends ConsumerStatefulWidget {
  const ConnectToCompanyScreen({super.key});

  @override
  ConsumerState<ConnectToCompanyScreen> createState() =>
      _ConnectToCompanyScreenState();
}

class _ConnectToCompanyScreenState
    extends ConsumerState<ConnectToCompanyScreen> {
  String _scope = 'full';
  bool _submitting = false;
  String? _error;
  bool _submitted = false;
  String? _submittedOrgName;

  Future<void> _submit(DiscoverableOrg org) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(connectionsRepositoryProvider)
          .submitRequest(org.id, _scope);
      if (mounted) {
        setState(() {
          _submitted = true;
          _submittedOrgName = org.name;
        });
        // Invalidate outgoing requests so profile reflects the new application.
        ref.invalidate(outgoingRequestsProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Scaffold(
        appBar: const EqAppBar(title: 'Application sent'),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(EqSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: EqColours.sky,
                    ),
                    const SizedBox(height: EqSpacing.lg),
                    Text(
                      'Application sent',
                      style: EqTypography.headingL.copyWith(
                        fontWeight: FontWeight.w700,
                        color: EqColours.ink,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      '${_submittedOrgName ?? 'The company'} will review your '
                      'application and get back to you. '
                      'You can check the status on your profile.',
                      style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: EqSpacing.xl),
                    EqButton(
                      label: 'Back to profile',
                      onPressed: () => context.pop(),
                      fullWidth: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final asyncOrgs = ref.watch(discoverableOrgsProvider);

    return Scaffold(
      appBar: const EqAppBar(title: 'Connect to a company'),
      body: asyncOrgs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(EqSpacing.lg),
            child: Text(
              'Could not load companies. Please try again.',
              style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (orgs) {
          if (orgs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(EqSpacing.lg),
                child: Text(
                  'No companies are currently accepting applications.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(EqSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Share your profile with a company so they can add you to '
                    'jobs without re-entering your details.',
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  _SectionLabel('What to share'),
                  const SizedBox(height: EqSpacing.sm),
                  EqCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _ScopeRow(
                          title: 'Full credentials',
                          subtitle: 'Name, phone, all licences and expiry dates',
                          value: 'full',
                          groupValue: _scope,
                          onChanged: (v) => setState(() => _scope = v!),
                        ),
                        const Divider(height: 1),
                        _ScopeRow(
                          title: 'Basic profile only',
                          subtitle: 'Name and phone — no licences',
                          value: 'basic',
                          groupValue: _scope,
                          onChanged: (v) => setState(() => _scope = v!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  _SectionLabel('Available companies'),
                  const SizedBox(height: EqSpacing.sm),
                  for (final org in orgs) ...[
                    _OrgCard(
                      org: org,
                      submitting: _submitting,
                      onApply: () => _submit(org),
                    ),
                    const SizedBox(height: EqSpacing.sm),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      _error!,
                      style: EqTypography.label.copyWith(color: EqColours.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Scope option row ──────────────────────────────────────────────────────────

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final String value;
  final String groupValue;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: EqSpacing.md,
          vertical: EqSpacing.sm,
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue, // ignore: deprecated_member_use // Radio.groupValue is deprecated but no replacement until Flutter 4
              onChanged: onChanged, // ignore: deprecated_member_use // Radio.onChanged is deprecated but no replacement until Flutter 4
              activeColor: EqColours.sky,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: EqSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: EqTypography.bodyL),
                  Text(
                    subtitle,
                    style: EqTypography.label.copyWith(color: EqColours.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Org card ──────────────────────────────────────────────────────────────────

class _OrgCard extends StatelessWidget {
  const _OrgCard({
    required this.org,
    required this.submitting,
    required this.onApply,
  });

  final DiscoverableOrg org;
  final bool submitting;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return EqCard(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: EqColours.ice,
            child: Text(
              _initials(org.name),
              style: EqTypography.label.copyWith(
                color: EqColours.deep,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: EqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(org.name, style: EqTypography.bodyL),
                Text(
                  org.slug,
                  style: EqTypography.label.copyWith(color: EqColours.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: EqSpacing.sm),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: submitting ? null : onApply,
              style: FilledButton.styleFrom(
                backgroundColor: EqColours.sky,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Apply',
                      style: EqTypography.label.copyWith(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(1, 2)).toUpperCase();
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EqSpacing.xs),
      child: Text(label, style: EqTypography.label),
    );
  }
}
