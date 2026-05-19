import 'package:eq_cards/core/router/routes.dart';
import 'package:eq_cards/features/auth/domain/auth_flow_state.dart';
import 'package:eq_cards/features/auth/presentation/notifiers/auth_flow_notifier.dart';
import 'package:eq_cards/features/auth/presentation/screens/email_entry_screen.dart';
import 'package:eq_cards/features/auth/presentation/screens/otp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Fake notifier that records `sendOtp` calls and transitions to
/// `AuthFlowAwaitingOtp` synchronously so the navigation step fires.
class _FakeAuthFlowNotifier extends AuthFlowNotifier {
  static final sendOtpCalls = <String>[];

  @override
  AuthFlowState build() => const AuthFlowIdle();

  @override
  Future<void> sendOtp(String email) async {
    sendOtpCalls.add(email);
    state = AuthFlowAwaitingOtp(email);
  }
}

GoRouter _router() => GoRouter(
      initialLocation: Routes.emailEntry,
      routes: [
        GoRoute(
          path: Routes.emailEntry,
          builder: (context, state) => const EmailEntryScreen(),
        ),
        GoRoute(
          path: Routes.otp,
          builder: (context, state) {
            final email = state.extra as String? ?? '';
            return OtpScreen(email: email);
          },
        ),
      ],
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authFlowNotifierProvider.overrideWith(_FakeAuthFlowNotifier.new),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _FakeAuthFlowNotifier.sendOtpCalls.clear());

  group('EmailEntryScreen', () {
    testWidgets('renders title and CTA', (tester) async {
      await _pump(tester);
      expect(find.text("What's your email?"), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid email', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'not-an-email');
      await tester.tap(find.text('Send code'));
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(_FakeAuthFlowNotifier.sendOtpCalls, isEmpty);
    });

    testWidgets('shows validation error for empty email', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Send code'));
      await tester.pump();
      expect(find.text('Enter your email address'), findsOneWidget);
      expect(_FakeAuthFlowNotifier.sendOtpCalls, isEmpty);
    });

    testWidgets('lowercases the typed email before sending', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'Royce@Example.COM');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(_FakeAuthFlowNotifier.sendOtpCalls, ['royce@example.com']);
    });

    testWidgets('trims whitespace from typed email before sending',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), '  user@example.com  ');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(_FakeAuthFlowNotifier.sendOtpCalls, ['user@example.com']);
    });

    testWidgets('navigates to OTP screen after successful send',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'royce@example.com');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(find.text('Enter code'), findsOneWidget);
      expect(find.textContaining('royce@example.com'), findsOneWidget);
    });
  });
}
