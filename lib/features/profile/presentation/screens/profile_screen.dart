import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/user_messages.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../../auth/auth.dart';
import '../../../settings/data/workspace_repository.dart';
import '../../../workers/data/models/worker.dart';
import '../../data/models/profile.dart';
import '../notifiers/profile_notifier.dart';
import '../widgets/copy_induction_block.dart';
import '../widgets/profile_field_row.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String? _workspaceBusy;
  String? _workspaceError;

  Future<void> _switchWorkspace(String tenantId) async {
    setState(() {
      _workspaceBusy = tenantId;
      _workspaceError = null;
    });
    try {
      await ref.read(workspaceRepositoryProvider).setActiveTenant(tenantId);
      ref.invalidate(myTenantsProvider);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _workspaceError = 'Could not switch workspace. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _workspaceBusy = null);
    }
  }

  Future<void> _disconnectWorkspace(TenantMembership tenant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disconnect from ${tenant.name}?'),
        content: Text(
          "You'll stop seeing ${tenant.name}'s licences in your wallet "
          'and switch back to your personal wallet.\n\n'
          'You can reconnect later with a join code from ${tenant.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Disconnect',
              style: TextStyle(color: EqColours.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _workspaceBusy = tenant.tenantId;
      _workspaceError = null;
    });
    try {
      await ref
          .read(workspaceRepositoryProvider)
          .revokeOrgAccess(tenant.tenantId);
      ref.invalidate(myTenantsProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _workspaceError =
            'Could not disconnect from ${tenant.name}. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _workspaceBusy = null);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content:
            const Text("You'll need to verify your phone again next time."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Sign out',
              style: TextStyle(color: EqColours.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(profileNotifierProvider);
    final tenants = ref.watch(myTenantsProvider).value ?? const [];

    final user = Supabase.instance.client.auth.currentUser;
    final appMeta = user?.appMetadata ?? const {};
    final role = appMeta['eq_role'] as String?;
    final roleLabel =
        role != null ? kEqRoleLabels[role] ?? role : null;
    final initials = _initials(asyncProfile.value?.fullName ?? '');

    // Join QR — only shown to managers and supervisors.
    final isQrEligible = role == 'manager' || role == 'supervisor';
    final tenantSlug = appMeta['tenant_slug'] as String?;
    final joinUrl = isQrEligible && tenantSlug != null && tenantSlug.isNotEmpty
        ? 'https://cards.eq.solutions/join?tenant=$tenantSlug'
        : null;

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
        data: (profile) => _Body(
          profile: profile,
          initials: initials,
          roleLabel: roleLabel,
          tenants: tenants,
          workspaceBusy: _workspaceBusy,
          workspaceError: _workspaceError,
          joinUrl: joinUrl,
          onSwitchWorkspace: _switchWorkspace,
          onDisconnectWorkspace: _disconnectWorkspace,
          onSignOut: _signOut,
          onSetupProfile: () => context.push(Routes.profileEdit),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'EQ';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.profile,
    required this.initials,
    required this.roleLabel,
    required this.tenants,
    required this.workspaceBusy,
    required this.workspaceError,
    required this.joinUrl,
    required this.onSwitchWorkspace,
    required this.onDisconnectWorkspace,
    required this.onSignOut,
    required this.onSetupProfile,
  });

  final Profile? profile;
  final String initials;
  final String? roleLabel;
  final List<TenantMembership> tenants;
  final String? workspaceBusy;
  final String? workspaceError;
  final String? joinUrl;
  final void Function(String tenantId) onSwitchWorkspace;
  final void Function(TenantMembership tenant) onDisconnectWorkspace;
  final VoidCallback onSignOut;
  final VoidCallback onSetupProfile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Avatar header ──────────────────────────────────────────────
          _ProfileHeader(
            initials: initials,
            displayName: profile?.fullName,
            roleLabel: roleLabel,
          ),
          const SizedBox(height: EqSpacing.md),

          // ── Personal details ───────────────────────────────────────────
          if (profile == null) ...[
            _EmptyState(onTap: onSetupProfile),
          ] else ...[
            if (!profile!.isComplete)
              _IncompleteHint(
                  onTap: () => context.go(Routes.profileEdit)),
            _DetailsCard(profile: profile!),
            const SizedBox(height: EqSpacing.md),
            CopyInductionBlock(profile: profile!),
          ],
          const SizedBox(height: EqSpacing.md),

          // ── Workspaces ─────────────────────────────────────────────────
          if (tenants.length >= 2) ...[
            _SectionLabel('Workspaces'),
            const SizedBox(height: EqSpacing.sm),
            EqCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < tenants.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _WorkspaceRow(
                      tenant: tenants[i],
                      loading: workspaceBusy == tenants[i].tenantId,
                      onSwitch: workspaceBusy == null
                          ? () => onSwitchWorkspace(tenants[i].tenantId)
                          : null,
                      onDisconnect:
                          workspaceBusy == null && tenants[i].isDisconnectable
                              ? () => onDisconnectWorkspace(tenants[i])
                              : null,
                    ),
                  ],
                  if (workspaceError != null) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(EqSpacing.md),
                      child: Text(
                        workspaceError!,
                        style: EqTypography.label
                            .copyWith(color: EqColours.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: EqSpacing.md),
          ],

          // ── Team / join QR (managers + supervisors only) ──────────────
          if (joinUrl != null) ...[
            _SectionLabel('Team'),
            const SizedBox(height: EqSpacing.sm),
            _JoinQrCard(joinUrl: joinUrl!),
            const SizedBox(height: EqSpacing.md),
          ],

          // ── Companies ──────────────────────────────────────────────────
          _SectionLabel('Companies'),
          const SizedBox(height: EqSpacing.sm),
          EqCard(
            padding: EdgeInsets.zero,
            child: _SettingsRow(
              icon: Icons.business_center_outlined,
              label: 'Connect to a company',
              subtitle: 'Apply to share your credentials with an employer',
              onTap: () => context.push(Routes.connect),
            ),
          ),
          const SizedBox(height: EqSpacing.md),

          // ── Account rows ───────────────────────────────────────────────
          _SectionLabel('Account'),
          const SizedBox(height: EqSpacing.sm),
          EqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsRow(
                  icon: Icons.settings_outlined,
                  label: 'Account settings',
                  subtitle: 'Privacy, legal, biometrics',
                  onTap: () => context.push(Routes.settings),
                ),
                const Divider(height: 1),
                _SignOutRow(onTap: onSignOut),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.xl),
        ],
      ),
    );
  }
}

// ── Profile header ────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.initials,
    required this.displayName,
    required this.roleLabel,
  });

  final String initials;
  final String? displayName;
  final String? roleLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: EqColours.deep,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: EqSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName ?? 'Your profile',
                style: EqTypography.headingM,
              ),
              if (roleLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  roleLabel!,
                  style: EqTypography.label,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Personal details card ─────────────────────────────────────────────────────

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.profile});

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

    return EqCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ProfileFieldRow(label: 'Full name', value: profile.fullName),
          const Divider(height: 1),
          ProfileFieldRow(label: 'Date of birth', value: dob),
          const Divider(height: 1),
          ProfileFieldRow(
              label: 'Mobile', value: profile.mobile, isPhone: true),
          const Divider(height: 1),
          ProfileFieldRow(label: 'Email', value: profile.email),
          const Divider(height: 1),
          ProfileFieldRow(label: 'Address', value: profile.fullAddress),
          const Divider(height: 1),
          ProfileFieldRow(
            label: 'Emergency contact',
            value: emergency.isEmpty ? null : emergency,
          ),
        ],
      ),
    );
  }
}

// ── Workspace row ─────────────────────────────────────────────────────────────

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.tenant,
    required this.loading,
    required this.onSwitch,
    required this.onDisconnect,
  });

  final TenantMembership tenant;
  final bool loading;
  final VoidCallback? onSwitch;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Row(
        children: [
          Icon(
            tenant.isPersonal
                ? Icons.person_outline
                : Icons.domain_outlined,
            color: EqColours.ink,
          ),
          const SizedBox(width: EqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tenant.isPersonal ? 'Personal wallet' : tenant.name,
                  style: EqTypography.bodyL,
                ),
                if (!tenant.isPersonal) ...[
                  const SizedBox(height: EqSpacing.xs),
                  Text(tenant.slug, style: EqTypography.label),
                ],
              ],
            ),
          ),
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(EqColours.sky),
              ),
            )
          else ...[
            if (tenant.isActive)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle,
                      color: EqColours.sky, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Active',
                    style:
                        EqTypography.label.copyWith(color: EqColours.sky),
                  ),
                ],
              )
            else
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: onSwitch,
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    side: BorderSide(
                      color: onSwitch != null
                          ? EqColours.sky
                          : EqColours.border,
                    ),
                    foregroundColor: EqColours.sky,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Switch',
                    style: EqTypography.label.copyWith(
                      color: onSwitch != null
                          ? EqColours.sky
                          : EqColours.grey,
                    ),
                  ),
                ),
              ),
            if (onDisconnect != null)
              IconButton(
                onPressed: onDisconnect,
                visualDensity: VisualDensity.compact,
                tooltip: 'Disconnect',
                icon: const Icon(Icons.link_off, color: EqColours.grey),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Join QR card ──────────────────────────────────────────────────────────────

class _JoinQrCard extends StatelessWidget {
  const _JoinQrCard({required this.joinUrl});

  final String joinUrl;

  @override
  Widget build(BuildContext context) {
    return EqCard(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.qr_code_outlined, color: EqColours.ink),
              SizedBox(width: EqSpacing.md),
              Text('Worker join QR', style: EqTypography.bodyL),
            ],
          ),
          const SizedBox(height: EqSpacing.xs),
          Text(
            'Share this QR at induction. Workers scan to join your team.',
            style: EqTypography.label,
          ),
          const SizedBox(height: EqSpacing.md),
          Center(
            child: QrImageView(
              data: joinUrl,
              version: QrVersions.auto,
              size: 200,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: EqColours.ink,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: EqColours.ink,
              ),
              backgroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings / account rows ───────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(EqSpacing.md),
        child: Row(
          children: [
            Icon(icon, color: EqColours.ink),
            const SizedBox(width: EqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: EqTypography.bodyL),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: EqTypography.label),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: EqColours.grey),
          ],
        ),
      ),
    );
  }
}

class _SignOutRow extends StatelessWidget {
  const _SignOutRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(EqSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.logout, color: EqColours.error),
            const SizedBox(width: EqSpacing.md),
            Expanded(
              child: Text(
                'Sign out',
                style: EqTypography.bodyL.copyWith(color: EqColours.error),
              ),
            ),
            const Icon(Icons.chevron_right, color: EqColours.grey),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
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
