import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../auth/data/aus_phone.dart';
import '../../data/worker_self_repository.dart';

/// Shown when a worker lands on /claim?tenant=<slug> without a token —
/// i.e. they scanned the tenant QR code rather than an individual invite link.
///
/// The worker enters their mobile number, the screen calls
/// [WorkerSelfRepository.lookupInviteByPhone] to find their unclaimed invite,
/// then redirects to /claim?token=<uuid> so the normal claim flow takes over.
class ClaimByPhoneScreen extends ConsumerStatefulWidget {
  const ClaimByPhoneScreen({super.key, required this.tenantSlug});

  final String tenantSlug;

  @override
  ConsumerState<ClaimByPhoneScreen> createState() => _ClaimByPhoneScreenState();
}

enum _Phase { idle, loading, notFound, error }

class _ClaimByPhoneScreenState extends ConsumerState<ClaimByPhoneScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  _Phase _phase = _Phase.idle;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = normaliseAusMobile(_phoneController.text.trim())!;

    setState(() {
      _phase = _Phase.loading;
      _errorMessage = null;
    });

    try {
      final token = await ref
          .read(workerSelfRepositoryProvider)
          .lookupInviteByPhone(phone, widget.tenantSlug);

      if (!mounted) return;

      if (token == null) {
        setState(() => _phase = _Phase.notFound);
      } else {
        // Hand off to the standard claim flow.
        unawaited(context.push('${Routes.claim}?token=$token'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _phase == _Phase.loading;

    return Scaffold(
      backgroundColor: EqColours.white,
      appBar: AppBar(
        backgroundColor: EqColours.white,
        elevation: 0,
        leading: BackButton(
          color: EqColours.ink,
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.xl,
                vertical: EqSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Brand ─────────────────────────────────────────────────
                  Image.asset(
                    'assets/icon/launcher.png',
                    width: 56,
                    height: 56,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: EqSpacing.lg),

                  Text(
                    'Find your invite',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.xs),
                  Text(
                    'Enter the mobile number your manager used '
                    'when setting up your account.',
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  ),

                  const SizedBox(height: EqSpacing.xl),

                  // ── Phone form ────────────────────────────────────────────
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      autocorrect: false,
                      textInputAction: TextInputAction.go,
                      onFieldSubmitted: (_) => unawaited(_lookup()),
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        hintText: '0412 345 678',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter your mobile number';
                        }
                        final phone = normaliseAusMobile(v.trim());
                        if (phone == null || !isValidAusMobile(phone)) {
                          return 'Enter a valid Australian mobile number';
                        }
                        return null;
                      },
                    ),
                  ),

                  const SizedBox(height: EqSpacing.lg),

                  // ── Error / not-found feedback ────────────────────────────
                  if (_phase == _Phase.notFound) ...[
                    Container(
                      padding: const EdgeInsets.all(EqSpacing.md),
                      decoration: BoxDecoration(
                        color: EqColours.ice,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: EqColours.sky.withAlpha(80)),
                      ),
                      child: Text(
                        'No invite found for that number. '
                        'Ask your manager to send you an invite link.',
                        style: EqTypography.bodyM.copyWith(
                          color: EqColours.deep,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: EqSpacing.lg),
                  ] else if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: EqTypography.label.copyWith(
                        color: EqColours.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: EqSpacing.lg),
                  ],

                  // ── CTA ───────────────────────────────────────────────────
                  FilledButton(
                    onPressed: isLoading ? null : () => unawaited(_lookup()),
                    style: FilledButton.styleFrom(
                      backgroundColor: EqColours.sky,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Find my invite'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
