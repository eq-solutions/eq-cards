import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/routes.dart';
import '../../core/theme/eq_colours.dart';
import '../../core/theme/eq_spacing.dart';
import '../../core/theme/eq_typography.dart';

// ignore: specify_nonobvious_property_types
final consentStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return true;
  final res = await Supabase.instance.client
      .from('profiles')
      .select('consented_at')
      .eq('id', user.id)
      .maybeSingle();
  if (res == null) return false;
  return res['consented_at'] != null;
});

/// Wraps [child] with a full-screen consent gate shown once — the first
/// time a worker opens their wallet after account creation. Records
/// `profiles.consented_at` via the authenticated client on agreement.
class ConsentGate extends ConsumerWidget {
  const ConsentGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGate = ref.watch(consentStatusProvider).maybeWhen(
          data: (hasConsented) => !hasConsented,
          orElse: () => false,
        );

    return Stack(
      children: [
        child,
        if (showGate)
          _ConsentOverlay(
            onAgreed: () => ref.invalidate(consentStatusProvider),
          ),
      ],
    );
  }
}

class _ConsentOverlay extends StatefulWidget {
  const _ConsentOverlay({required this.onAgreed});

  final VoidCallback onAgreed;

  @override
  State<_ConsentOverlay> createState() => _ConsentOverlayState();
}

class _ConsentOverlayState extends State<_ConsentOverlay> {
  bool _saving = false;

  Future<void> _agree() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final now = DateTime.now().toUtc().toIso8601String();
        await Supabase.instance.client.from('profiles').upsert(
          {'id': user.id, 'consented_at': now},
          onConflict: 'id',
        );
      }
      widget.onAgreed();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: EqColours.ink.withValues(alpha: 0.93),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EqSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EQ Cards',
                  style: EqTypography.headingL.copyWith(
                    color: EqColours.sky,
                  ),
                ),
                const SizedBox(height: EqSpacing.lg),
                Text(
                  'Before you open your wallet',
                  style: EqTypography.headingM.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: EqSpacing.md),
                Text(
                  'EQ Cards stores your professional credentials — licences, '
                  'qualifications, and identity documents — so your employer '
                  'can verify them when required.\n\n'
                  'By continuing, you consent to EQ Solutions collecting and '
                  'storing this information in accordance with the Australian '
                  'Privacy Act 1988. Your data is encrypted, hosted in '
                  'Australia, and shared only with employers you connect to.',
                  style: EqTypography.bodyM.copyWith(
                    color: Colors.white.withValues(alpha: 0.80),
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: EqSpacing.sm),
                GestureDetector(
                  onTap: () => context.push(Routes.privacyPolicy),
                  child: Text(
                    'Read our Privacy Policy →',
                    style: EqTypography.bodyS.copyWith(color: EqColours.sky),
                  ),
                ),
                const SizedBox(height: EqSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _agree,
                    style: FilledButton.styleFrom(
                      backgroundColor: EqColours.sky,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          EqColours.sky.withValues(alpha: 0.5),
                      padding:
                          const EdgeInsets.symmetric(vertical: EqSpacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('I agree and continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
