import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_icon_preview.dart';
import '../../../../core/design/design_version.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_card.dart';
import '../../../auth/auth.dart';
import '../notifiers/biometric_settings_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _appVersion = '0.1.0+1';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncBiometric = ref.watch(biometricSettingsNotifierProvider);

    return Scaffold(
      appBar: const EqAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.all(EqSpacing.md),
        children: [
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
          "You'll need to verify your phone again next time.",
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
