import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/validators/input_validators.dart';
import '../../data/aus_phone.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';

class EmailEntryScreen extends ConsumerStatefulWidget {
  const EmailEntryScreen({super.key});

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  bool _googleLoading = false;
  final _joinCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Clear error when the user switches tabs.
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        ref.read(authFlowNotifierProvider.notifier).reset();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    await ref
        .read(authFlowNotifierProvider.notifier)
        .sendOtp(_emailController.text.trim());
  }

  Future<void> _submitPhone() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final phone = normaliseAusMobile(_phoneController.text.trim())!;
    await ref.read(authFlowNotifierProvider.notifier).sendPhoneOtp(phone);
  }

  void _showJoinCodeSheet(BuildContext context) {
    _joinCodeController.clear();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EqColours.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            EqSpacing.xl,
            EqSpacing.lg,
            EqSpacing.xl,
            EqSpacing.xl + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: EqColours.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: EqSpacing.lg),
              Text(
                'Enter your company code',
                style: EqTypography.headingS.copyWith(
                  fontWeight: FontWeight.w700,
                  color: EqColours.ink,
                ),
              ),
              const SizedBox(height: EqSpacing.xs),
              Text(
                'Your manager can give you this code.',
                style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              ),
              const SizedBox(height: EqSpacing.lg),
              TextField(
                controller: _joinCodeController,
                autofocus: true,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.go,
                decoration: const InputDecoration(
                  labelText: 'Company code',
                  hintText: 'e.g. sks',
                ),
                onSubmitted: (_) => _submitJoinCode(ctx),
              ),
              const SizedBox(height: EqSpacing.lg),
              FilledButton(
                onPressed: () => _submitJoinCode(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: EqColours.sky,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Join'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _submitJoinCode(BuildContext sheetContext) {
    final code = _joinCodeController.text.trim().toLowerCase();
    if (code.isEmpty) return;
    Navigator.of(sheetContext).pop();
    context.push('${Routes.join}?tenant=$code');
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // On web this redirects — setState after is a no-op.
    } catch (_) {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authFlowNotifierProvider, (_, next) {
      if (next is AuthFlowAwaitingOtp) {
        unawaited(context.push(Routes.otp));
      }
    });

    final flowState = ref.watch(authFlowNotifierProvider);
    final isLoading = flowState is AuthFlowSendingOtp;
    final error = flowState is AuthFlowError ? flowState.message : null;

    return Scaffold(
      backgroundColor: EqColours.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.xl,
                vertical: EqSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: EqSpacing.xl),

                  // ── Brand ────────────────────────────────────────────────
                  Image.asset(
                    'assets/icon/launcher.png',
                    width: 56,
                    height: 56,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  Text(
                    'Sign in to EQ Cards',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.xs),
                  Text(
                    'Use the email or mobile linked to your account.',
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  ),

                  const SizedBox(height: EqSpacing.xl),

                  // ── Tab bar ──────────────────────────────────────────────
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: EqColours.border),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: EqColours.deep,
                      unselectedLabelColor: EqColours.grey,
                      labelStyle: EqTypography.bodyL.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: EqTypography.bodyL,
                      indicatorColor: EqColours.sky,
                      indicatorWeight: 2,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Email'),
                        Tab(text: 'Mobile'),
                      ],
                    ),
                  ),

                  const SizedBox(height: EqSpacing.lg),

                  // ── Tab content ──────────────────────────────────────────
                  // Fixed height so the Google button doesn't jump when
                  // validation errors appear — error is shown below the tabs.
                  SizedBox(
                    height: 120,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Email tab
                        Form(
                          key: _emailFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submitEmail(),
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  hintText: 'you@example.com',
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Enter your email address';
                                  }
                                  return validateEmail(v);
                                },
                              ),
                            ],
                          ),
                        ),

                        // Mobile tab
                        Form(
                          key: _phoneFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submitPhone(),
                                decoration: const InputDecoration(
                                  labelText: 'Mobile number',
                                  hintText: '0412 345 678',
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Enter your mobile number';
                                  }
                                  final phone = normaliseAusMobile(v.trim());
                                  if (phone == null ||
                                      !isValidAusMobile(phone)) {
                                    return 'Enter a valid Australian mobile number';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Error ────────────────────────────────────────────────
                  if (error != null) ...[
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      error,
                      style:
                          EqTypography.label.copyWith(color: EqColours.error),
                      textAlign: TextAlign.center,
                    ),
                  ] else
                    const SizedBox(height: EqSpacing.sm),

                  // ── Send code button ─────────────────────────────────────
                  FilledButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            if (_tabController.index == 0) {
                              unawaited(_submitEmail());
                            } else {
                              unawaited(_submitPhone());
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: EqColours.sky,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: isLoading
                        ? const _LoadingSpinner()
                        : const Text('Send code'),
                  ),

                  const SizedBox(height: EqSpacing.xl),

                  // ── Divider ──────────────────────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: EqSpacing.md,
                        ),
                        child: Text(
                          'or',
                          style: EqTypography.label
                              .copyWith(color: EqColours.grey),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: EqSpacing.lg),

                  // ── Google sign-in ───────────────────────────────────────
                  OutlinedButton(
                    onPressed: (_googleLoading || isLoading)
                        ? null
                        : _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: EqColours.border),
                      backgroundColor: EqColours.white,
                      foregroundColor: EqColours.ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _googleLoading
                        ? const _LoadingSpinner(color: EqColours.grey)
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgPicture.asset(
                                'assets/icons/google_logo.svg',
                                width: 20,
                                height: 20,
                              ),
                              const SizedBox(width: EqSpacing.sm),
                              Text(
                                'Continue with Google',
                                style: EqTypography.bodyL.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: EqColours.ink,
                                ),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: EqSpacing.md),

                  // ── Join with a join code ────────────────────────────────
                  Center(
                    child: TextButton(
                      onPressed: () => _showJoinCodeSheet(context),
                      child: Text(
                        'Join with a join code',
                        style: EqTypography.bodyM.copyWith(
                          color: EqColours.sky,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: EqSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner({this.color = Colors.white});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(color: color, strokeWidth: 2),
      );
}
