import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/validators/input_validators.dart';
import '../../data/aus_phone.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';
import '../notifiers/join_context_notifier.dart';

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
    super.dispose();
  }

  void _showJoinCodeSheet(BuildContext context) {
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EqColours.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: EqSpacing.xl,
          right: EqSpacing.xl,
          top: EqSpacing.lg,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + EqSpacing.xl,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter your join code',
                style: EqTypography.headingM.copyWith(
                  fontWeight: FontWeight.w700,
                  color: EqColours.deep,
                ),
              ),
              const SizedBox(height: EqSpacing.sm),
              Text(
                'Your manager will give you a short code for your team.',
                style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              ),
              const SizedBox(height: EqSpacing.lg),
              TextFormField(
                controller: codeController,
                autocorrect: false,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Join code',
                  hintText: 'e.g. sks',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter your join code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: EqSpacing.lg),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final slug = codeController.text.toLowerCase().trim();
                  Navigator.of(ctx).pop();
                  // Clear any stale join context before setting the new one.
                  ref.read(joinContextNotifierProvider.notifier).clear();
                  unawaited(context.push('${Routes.join}?tenant=$slug'));
                },
                style: FilledButton.styleFrom(
                  backgroundColor: EqColours.sky,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    ));
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
                    width: 240,
                    height: 240,
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

                  const SizedBox(height: EqSpacing.md),

                  // ── Join with a join code ────────────────────────────────
                  TextButton(
                    onPressed: () => _showJoinCodeSheet(context),
                    child: Text(
                      'Join with a join code',
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.sky,
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
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
}
