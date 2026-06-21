import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/shell/complete_profile_banner.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../../licences/presentation/notifiers/licence_types_provider.dart';
import '../../../licences/presentation/notifiers/licences_list_notifier.dart';
import '../../../profile/presentation/notifiers/profile_notifier.dart';
import '../../../settings/data/workspace_repository.dart';
import '../../../workers/data/models/worker.dart';

// Colours specific to the ink/dark ID card — not in the shared palette.
const _cardSecondary = Color(0xFFB9C2D6);
const _cardMuted = Color(0xFF7E879C);
const _cardVerifiedBg = Color(0x2E22C55E);
const _cardVerifiedFg = Color(0xFF86EFAC);
const _cardSeparator = Color(0x1AFFFFFF);
const _cardQrBg = Color(0x12FFFFFF);
const _cardQrFg = Color(0xFFCBD5E1);
const _cardChipBg = Color(0x1AFFFFFF);
const _cardChipFg = Color(0xFFE6EBF5);

class CardScreen extends ConsumerWidget {
  const CardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileNotifierProvider).value;
    final licences = ref.watch(licencesListNotifierProvider).value ?? const [];
    final licenceTypes = ref.watch(licenceTypesProvider).value ?? const [];

    final typeMap = {for (final t in licenceTypes) t.code: t.label};

    final user = Supabase.instance.client.auth.currentUser;
    final appMeta = user?.appMetadata ?? const {};
    final role = appMeta['eq_role'] as String?;

    final asyncTenants = ref.watch(myTenantsProvider);
    final tenants = asyncTenants.value ?? const [];
    final activeTenant = tenants.isEmpty
        ? null
        : tenants.firstWhere((t) => t.isActive, orElse: () => tenants.first);
    final orgName = activeTenant == null
        ? (appMeta['tenant_name'] as String? ?? '—')
        : activeTenant.isPersonal
            ? 'Personal'
            : activeTenant.name;

    final displayName = profile?.fullName;
    final initials = _initials(displayName ?? '');
    final roleLabel = role != null ? kEqRoleLabels[role] : null;
    final typeLabel = _typeLabel(role);
    final workerId = _workerId(user?.id ?? '');
    final issued = _issuedDate(user?.createdAt);

    // Licence health counts — certs live in the licences branch but are
    // a separate provider; using the licences list gives a quick summary
    // matching the existing _WalletStats pattern from Settings.
    final validCount = licences
        .where((l) => !l.isExpired && !l.isExpiringWithin(days: 30))
        .length;
    final expiringCount =
        licences.where((l) => l.isExpiringWithin(days: 30)).length;
    final expiredCount = licences.where((l) => l.isExpired).length;

    // Needs-attention items — expired first, then expiring soon.
    final expired = licences.where((l) => l.isExpired).toList();
    final expiring =
        licences.where((l) => !l.isExpired && l.isExpiringWithin(days: 30)).toList();
    final urgent = [...expired, ...expiring];

    return Scaffold(
      appBar: const EqAppBar(title: 'My card', withBranding: true),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileNotifierProvider);
          ref.invalidate(licencesListNotifierProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(EqSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CompleteProfileBanner(),
              _IdCard(
                initials: initials,
                displayName: displayName,
                roleLabel: roleLabel,
                typeLabel: typeLabel,
                orgName: orgName,
                workerId: workerId,
                issued: issued,
                onQrTap: () => _showQrStub(context),
              ),
              const SizedBox(height: EqSpacing.md),
              if (licences.isEmpty) ...[
                _EmptyWalletNudge(
                  onTap: () => context.go(Routes.licencesList),
                ),
                const SizedBox(height: EqSpacing.md),
              ],
              if (licences.isNotEmpty || expiredCount > 0) ...[
                _HealthCard(
                  validCount: validCount,
                  expiringCount: expiringCount,
                  expiredCount: expiredCount,
                  onViewAll: () => context.go(Routes.licencesList),
                ),
                const SizedBox(height: EqSpacing.md),
              ],
              if (urgent.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(
                      left: EqSpacing.xs, bottom: EqSpacing.sm),
                  child: Text('Needs attention', style: EqTypography.label),
                ),
                ...urgent.take(4).map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: EqSpacing.sm),
                      child: _AlertTile(
                        licence: l,
                        label: typeMap[l.licenceType] ?? l.licenceType,
                        onTap: () {
                          if (l.id != null) {
                            unawaited(context.push(Routes.licenceDetailFor(l.id!)));
                          }
                        },
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'EQ';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String? _typeLabel(String? role) => switch (role) {
        'employee' => 'Direct employee',
        'labour_hire' => 'Labour hire',
        'manager' => 'Manager',
        'supervisor' => 'Supervisor',
        'apprentice' => 'Apprentice',
        _ => null,
      };

  static String _workerId(String uuid) {
    final hex = uuid.replaceAll('-', '');
    if (hex.length < 4) return 'EQ-0000';
    final tail = hex.substring(hex.length - 4);
    final n = int.parse(tail, radix: 16) % 9000 + 1000;
    return 'EQ-$n';
  }

  static String _issuedDate(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '—';
    try {
      return DateFormat('MMM yyyy').format(DateTime.parse(createdAt));
    } catch (_) {
      return '—';
    }
  }

  static void _showQrStub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR sign-in coming soon.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: EqColours.ink,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ── Digital ID card ───────────────────────────────────────────────────────────

class _IdCard extends StatelessWidget {
  const _IdCard({
    required this.initials,
    required this.displayName,
    required this.roleLabel,
    required this.typeLabel,
    required this.orgName,
    required this.workerId,
    required this.issued,
    required this.onQrTap,
  });

  final String initials;
  final String? displayName;
  final String? roleLabel;
  final String? typeLabel;
  final String orgName;
  final String workerId;
  final String issued;
  final VoidCallback onQrTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EqColours.ink,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: wordmark + verified pill
          Row(
            children: [
              Text(
                'EQ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'WORKER CARD',
                style: TextStyle(
                  color: _cardMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _cardVerifiedBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.verified_outlined,
                        size: 10, color: _cardVerifiedFg),
                    SizedBox(width: 4),
                    Text(
                      'Verified',
                      style: TextStyle(
                        color: _cardVerifiedFg,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: EqSpacing.md),
          // Identity: avatar + name + trade + type chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: EqColours.sky,
                  borderRadius: BorderRadius.circular(10),
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
                      displayName ?? '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (roleLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        roleLabel!,
                        style: const TextStyle(
                          color: _cardSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (typeLabel != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _cardChipBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: EqColours.sky,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              typeLabel!,
                              style: const TextStyle(
                                color: _cardChipFg,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: EqSpacing.md),
          // Meta grid: Company / Worker ID / Issued
          Container(
            padding: const EdgeInsets.only(top: EqSpacing.md),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _cardSeparator)),
            ),
            child: Row(
              children: [
                Expanded(child: _GridCell(label: 'Company', value: orgName)),
                Expanded(child: _GridCell(label: 'Worker ID', value: workerId)),
                Expanded(child: _GridCell(label: 'Issued', value: issued)),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.sm),
          // Tap to show QR
          GestureDetector(
            onTap: onQrTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _cardQrBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.qr_code, size: 13, color: _cardQrFg),
                  SizedBox(width: 6),
                  Text(
                    'Tap to show QR for site sign-in',
                    style: TextStyle(
                      color: _cardQrFg,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _cardMuted,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Licence health card ───────────────────────────────────────────────────────

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.validCount,
    required this.expiringCount,
    required this.expiredCount,
    required this.onViewAll,
  });

  final int validCount;
  final int expiringCount;
  final int expiredCount;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return EqCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.md, vertical: 10),
            child: Row(
              children: [
                Text(
                  'Licence health',
                  style: EqTypography.label
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onViewAll,
                  child: Text(
                    'View all',
                    style:
                        EqTypography.label.copyWith(color: EqColours.sky),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _HealthCell(
                    count: validCount,
                    label: 'Valid',
                    color: EqColours.success,
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: _HealthCell(
                    count: expiringCount,
                    label: 'Expiring',
                    color: EqColours.warning,
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: _HealthCell(
                    count: expiredCount,
                    label: 'Expired',
                    color: EqColours.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCell extends StatelessWidget {
  const _HealthCell({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EqSpacing.md),
      child: Column(
        children: [
          Text(
            '$count',
            style: EqTypography.headingL.copyWith(
              fontWeight: FontWeight.w800,
              color: count > 0 ? color : EqColours.ink,
            ),
          ),
          const SizedBox(height: EqSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: count > 0 ? color : EqColours.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: EqTypography.label,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Needs-attention alert tile ────────────────────────────────────────────────

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.licence,
    required this.label,
    required this.onTap,
  });

  final Licence licence;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isExpired = licence.isExpired;
    final bgColor = isExpired
        ? EqColours.error.withValues(alpha: 0.08)
        : EqColours.warning.withValues(alpha: 0.08);
    final borderColor = isExpired
        ? EqColours.error.withValues(alpha: 0.25)
        : EqColours.warning.withValues(alpha: 0.25);
    final accentColor = isExpired ? EqColours.error : EqColours.warning;
    final days = licence.daysUntilExpiry;

    final subtitle = isExpired
        ? 'Expired — renew to stay site-ready'
        : 'Expires in $days day${days == 1 ? '' : 's'}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(EqSpacing.md),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isExpired ? Icons.warning_amber_rounded : Icons.schedule,
                size: 18,
                color: accentColor,
              ),
            ),
            const SizedBox(width: EqSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: EqTypography.bodyM.copyWith(
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: EqTypography.label,
                  ),
                ],
              ),
            ),
            const SizedBox(width: EqSpacing.sm),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isExpired ? 'Renew' : 'View',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWalletNudge extends StatelessWidget {
  const _EmptyWalletNudge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EqCard(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline, color: EqColours.sky, size: 28),
          const SizedBox(width: EqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add your licences',
                  style: EqTypography.bodyL.copyWith(
                    fontWeight: FontWeight.w600,
                    color: EqColours.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'White card, tickets, certificates — all in one place.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: EqSpacing.sm),
          const Icon(Icons.chevron_right, color: EqColours.sky),
        ],
      ),
    );
  }
}
