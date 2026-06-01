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

                  const SizedBox(height: EqSpacing.xl),
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
