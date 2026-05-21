import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/design/app_icon_preview.dart';
import '../../../../core/design/design_version.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../../auth/auth.dart';
import '../../../licences/data/models/licence.dart';
import '../../../licences/presentation/notifiers/licences_list_notifier.dart';
import '../../../profile/presentation/notifiers/profile_notifier.dart';
import '../helpers/data_export.dart';
import '../notifiers/biometric_settings_notifier.dart';
import '../notifiers/privacy_settings_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _appVersion = '0.1.0+1';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncBiometric = ref.watch(biometricSettingsNotifierProvider);

    return Scaffold(
      appBar: const EqAppBar(title: 'Settings', withBranding: true),
      body: ListView(
        padding: const EdgeInsets.all(EqSpacing.md),
        children: [
          // Wallet stats — quick at-a-glance summary derived from existing
          // licence data (no new schema). Hidden until the licence list
          // resolves successfully so the page doesn't flicker on cold load.
          ref.watch(licencesListNotifierProvider).maybeWhen(
                data: (licences) => Column(
                  children: [
                    _WalletStats(licences: licences),
                    const SizedBox(height: EqSpacing.md),
                  ],
                ),
                orElse: () => const SizedBox.shrink(),
              ),
          EqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _BiometricRow(
                  asyncEnabled: asyncBiometric,
                  onChanged: (v) => ref
                      .read(biometricSettingsNotifierProvider.notifier)
                      .setEnabled(value: v),
                ),
                const Divider(height: 1),
                const _StaticRow(
                  icon: Icons.info_outline,
                  label: 'Version',
                  subtitle: _appVersion,
                ),
                const Divider(height: 1),
                _SignOutRow(
                  onTap: () => _confirmAndSignOut(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EqSpacing.sm),
            child: Text('Design', style: EqTypography.label),
          ),
          const SizedBox(height: EqSpacing.sm),
          EqCard(
            padding: EdgeInsets.zero,
            child: _DesignPicker(
              selected: ref.watch(designVersionNotifierProvider),
              onChanged: (v) => ref
                  .read(designVersionNotifierProvider.notifier)
                  .set(v),
            ),
          ),
          const SizedBox(height: EqSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EqSpacing.sm),
            child: Text('Privacy', style: EqTypography.label),
          ),
          const SizedBox(height: EqSpacing.sm),
          EqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _PrivacyToggleRow(
                  icon: Icons.insights_outlined,
                  label: 'Send anonymous analytics',
                  subtitle:
                      'Helps us see which features work and which break. '
                      'Never includes the values of your fields.',
                  // Switch is "opt-IN", notifier stores "opt-OUT" — invert.
                  value: !ref.watch(analyticsOptOutNotifierProvider),
                  onChanged: (v) => ref
                      .read(analyticsOptOutNotifierProvider.notifier)
                      .set(value: !v),
                ),
                const Divider(height: 1),
                _PrivacyToggleRow(
                  icon: Icons.bug_report_outlined,
                  label: 'Send crash reports',
                  subtitle:
                      'Stack traces only — no personal data. Helps us '
                      'diagnose bugs you hit.',
                  value: !ref.watch(crashReportsOptOutNotifierProvider),
                  onChanged: (v) => ref
                      .read(crashReportsOptOutNotifierProvider.notifier)
                      .set(value: !v),
                ),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EqSpacing.sm),
            child: Text('Legal', style: EqTypography.label),
          ),
          const SizedBox(height: EqSpacing.sm),
          EqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LegalRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  onTap: () => context.push(Routes.privacyPolicy),
                ),
                const Divider(height: 1),
                _LegalRow(
                  icon: Icons.gavel_outlined,
                  label: 'Terms of Use',
                  onTap: () => context.push(Routes.termsOfUse),
                ),
                const Divider(height: 1),
                _LegalRow(
                  icon: Icons.download_outlined,
                  label: 'Export my data',
                  onTap: () => _exportData(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EqSpacing.sm),
            child: Text('Help & feedback', style: EqTypography.label),
          ),
          const SizedBox(height: EqSpacing.sm),
          EqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LegalRow(
                  icon: Icons.help_outline,
                  label: 'Get help',
                  onTap: () => _composeContactEmail(
                    context,
                    ref,
                    subject: 'EQ Cards — I need help',
                    bodyHint:
                        "Describe what you're stuck on. Screenshots help.",
                  ),
                ),
                const Divider(height: 1),
                _LegalRow(
                  icon: Icons.feedback_outlined,
                  label: 'Send feedback',
                  onTap: () => _composeContactEmail(
                    context,
                    ref,
                    subject: 'EQ Cards — pilot feedback',
                    bodyHint:
                        'What worked? What was confusing? What was missing? '
                        'Anything goes.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a copy-ready composer dialog the user can paste into their mail
  /// client. We don't open a `mailto:` URI directly — that needs
  /// `url_launcher`, which isn't wired in, and on a PWA-installed instance
  /// the OS handler is often unreliable anyway. The dialog presents the
  /// address, subject, and a pre-filled body in one SelectableText block,
  /// plus a "Copy email" action that puts the entire block on the
  /// clipboard so the user can paste it into Gmail / Outlook / whatever.
  ///
  /// The user UUID is appended so a reply can be correlated with Sentry
  /// / Supabase logs without asking the user for an ID.
  ///
  /// Address matches the Privacy Policy contact (`contact@eq.solutions`)
  /// — both flow into the same EQ Solutions inbox.
  Future<void> _composeContactEmail(
    BuildContext context,
    WidgetRef ref, {
    required String subject,
    required String bodyHint,
  }) async {
    const address = 'contact@eq.solutions';
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'unknown';
    final body = '$bodyHint\n\n\n---\n'
        'Please leave the lines below so we can find your account.\n'
        'User: $userId\nApp: EQ Cards web 0.1.0\n';
    final composed = 'To: $address\nSubject: $subject\n\n$body';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Email us'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400, maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste this into your mail app — we read every reply.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                ),
                const SizedBox(height: EqSpacing.md),
                Container(
                  padding: const EdgeInsets.all(EqSpacing.sm),
                  decoration: BoxDecoration(
                    color: EqColours.ice,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    composed,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: composed));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('Copied. Paste into your mail app.'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: EqColours.ink,
                ),
              );
            },
            child: const Text('Copy email'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Per Privacy Policy §9 access right — show every personal-data field
  /// we hold. JSON copied to clipboard + displayed in a dialog so the user
  /// can also screenshot or paste into a doc. v1.1 may add a proper native
  /// share-sheet via share_plus.
  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final profileAsync = ref.read(profileNotifierProvider);
    final licencesAsync = ref.read(licencesListNotifierProvider);
    final profile = profileAsync.valueOrNull;
    final licences = licencesAsync.valueOrNull ?? const <Licence>[];

    final payload = buildExportPayload(
      profile: profile,
      licences: licences,
      now: DateTime.now(),
    );
    final json = exportPayloadToJsonString(payload);

    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your data — copied to clipboard'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          "You'll need to verify your email again next time.",
        ),
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
    // Router redirect handles navigation back to phone entry.
  }
}

class _BiometricRow extends StatelessWidget {
  const _BiometricRow({
    required this.asyncEnabled,
    required this.onChanged,
  });

  final AsyncValue<bool> asyncEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = asyncEnabled.valueOrNull ?? true;
    final ready = asyncEnabled.hasValue;

    return Padding(
      padding: const EdgeInsets.all(EqSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.fingerprint, color: EqColours.ink),
          const SizedBox(width: EqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Biometric unlock', style: EqTypography.bodyL),
                const SizedBox(height: EqSpacing.xs),
                Text(
                  'Re-prompt on cold launch and after 5 min in background. Gating wired in v1.1.',
                  style: EqTypography.label,
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: ready ? onChanged : null,
            activeThumbColor: EqColours.sky,
          ),
        ],
      ),
    );
  }
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                const SizedBox(height: EqSpacing.xs),
                Text(subtitle, style: EqTypography.label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesignPicker extends StatelessWidget {
  const _DesignPicker({required this.selected, required this.onChanged});

  final DesignVersion selected;
  final ValueChanged<DesignVersion> onChanged;

  @override
  Widget build(BuildContext context) {
    const values = DesignVersion.values;
    return Column(
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          Semantics(
            label:
                '${values[i].label}. ${values[i].description}',
            inMutuallyExclusiveGroup: true,
            selected: selected == values[i],
            button: true,
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onChanged(values[i]),
              child: Padding(
                padding: const EdgeInsets.all(EqSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      selected == values[i]
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected == values[i]
                          ? EqColours.sky
                          : EqColours.grey,
                    ),
                    const SizedBox(width: EqSpacing.md),
                    AppIconPreview(version: values[i], size: 56),
                    const SizedBox(width: EqSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(values[i].label, style: EqTypography.bodyL),
                          const SizedBox(height: EqSpacing.xs),
                          Text(
                            values[i].description,
                            style: EqTypography.label,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Stats card surfaced at the top of Settings. Derived from licences
/// already in the store — no new schema. A small "wedge dashboard" hint
/// for what the Pro-tier admin view will eventually show.
class _WalletStats extends StatelessWidget {
  const _WalletStats({required this.licences});

  final List<Licence> licences;

  int get _total => licences.length;
  int get _expiringSoon =>
      licences.where((l) => l.isExpiringWithin(days: 30)).length;
  int get _expired => licences.where((l) => l.isExpired).length;

  @override
  Widget build(BuildContext context) {
    if (_total == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(EqSpacing.md),
      decoration: BoxDecoration(
        color: EqColours.ice,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EqColours.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              value: _total.toString(),
              label: _total == 1 ? 'Licence' : 'Licences',
            ),
          ),
          Container(width: 1, height: 40, color: EqColours.border),
          Expanded(
            child: _StatCell(
              value: _expiringSoon.toString(),
              label: 'Expiring 30d',
              accent:
                  _expiringSoon > 0 ? EqColours.warning : null,
            ),
          ),
          Container(width: 1, height: 40, color: EqColours.border),
          Expanded(
            child: _StatCell(
              value: _expired.toString(),
              label: 'Expired',
              accent: _expired > 0 ? EqColours.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, this.accent});

  final String value;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: EqTypography.headingL.copyWith(
            fontWeight: FontWeight.w700,
            color: accent ?? EqColours.deep,
          ),
        ),
        const SizedBox(height: EqSpacing.xs),
        Text(
          label,
          style: EqTypography.label,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _PrivacyToggleRow extends StatelessWidget {
  const _PrivacyToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                const SizedBox(height: EqSpacing.xs),
                Text(subtitle, style: EqTypography.label),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: EqColours.sky,
          ),
        ],
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
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
            Expanded(child: Text(label, style: EqTypography.bodyL)),
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
      child: const Padding(
        padding: EdgeInsets.all(EqSpacing.md),
        child: Row(
          children: [
            Icon(Icons.logout, color: EqColours.error),
            SizedBox(width: EqSpacing.md),
            Expanded(
              child: Text(
                'Sign out',
                style: TextStyle(
                  color: EqColours.error,
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: EqColours.grey),
          ],
        ),
      ),
    );
  }
}
