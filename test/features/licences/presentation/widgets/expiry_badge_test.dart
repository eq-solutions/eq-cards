import 'package:eq_cards/features/licences/presentation/widgets/expiry_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, DateTime expiry) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExpiryBadge(expiry: expiry)),
      ),
    );
  }

  group('ExpiryBadge', () {
    testWidgets('shows "Expired" for past expiry', (tester) async {
      final past = DateTime.now().subtract(const Duration(days: 30));
      await pump(tester, past);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('shows "X days left" within 7-day window', (tester) async {
      final soon = DateTime.now().add(const Duration(days: 5));
      await pump(tester, soon);
      expect(find.textContaining('days left'), findsOneWidget);
    });

    testWidgets('shows "X days left" within 30-day window', (tester) async {
      final mid = DateTime.now().add(const Duration(days: 20));
      await pump(tester, mid);
      expect(find.textContaining('days left'), findsOneWidget);
    });

    testWidgets('shows "X days left" within 90-day window', (tester) async {
      final later = DateTime.now().add(const Duration(days: 60));
      await pump(tester, later);
      expect(find.textContaining('days left'), findsOneWidget);
    });

    testWidgets('shows "Valid" for far-future expiry', (tester) async {
      final far = DateTime.now().add(const Duration(days: 365));
      await pump(tester, far);
      expect(find.text('Valid'), findsOneWidget);
    });
  });
}
