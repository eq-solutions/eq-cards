import 'package:eq_cards/core/router/routes.dart';
import 'package:eq_cards/features/auth/domain/auth_flow_state.dart';
import 'package:eq_cards/features/auth/presentation/notifiers/auth_flow_notifier.dart';
import 'package:eq_cards/features/auth/presentation/screens/otp_screen.dart';
import 'package:eq_cards/features/auth/presentation/screens/phone_entry_screen.dart';
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
  Future<void> sendOtp(String phone) async {
    sendOtpCalls.add(phone);
    state = AuthFlowAwaitingOtp(phone);
  }
}

GoRouter _router() => GoRouter(
      initialLocation: Routes.phoneEntry,
      routes: [
        GoRoute(
          path: Routes.phoneEntry,
          builder: (context, state) => const PhoneEntryScreen(),
        ),
        GoRoute(
          path: Routes.otp,
          builder: (context, state) {
            final phone = state.extra as String? ?? '';
            return OtpScreen(phone: phone);
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

  group('PhoneEntryScreen', () {
    testWidgets('renders title and CTA', (tester) async {
      await _pump(tester);
      expect(find.text("What's your mobile?"), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid phone', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('Send code'));
      await tester.pump();
      expect(find.text('Enter a valid Australian mobile'), findsOneWidget);
      expect(_FakeAuthFlowNotifier.sendOtpCalls, isEmpty);
    });

    testWidgets('calls notifier with normalised E.164 for 0412 form',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), '0412345678');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(_FakeAuthFlowNotifier.sendOtpCalls, ['+61412345678']);
    });

    testWidgets('strips spaces from typed phone before sending',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), '0412 345 678');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(_FakeAuthFlowNotifier.sendOtpCalls, ['+61412345678']);
    });

    testWidgets('navigates to OTP screen after successful send',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), '+61412345678');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(find.text('Enter code'), findsOneWidget);
      expect(find.textContaining('+61412345678'), findsOneWidget);
    });
  });
}
