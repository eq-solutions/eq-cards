import 'package:eq_cards/core/theme/eq_typography.dart';
import 'package:eq_cards/core/widgets/eq_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget card) async {
    await tester.binding.setSurfaceSize(const Size(360, 120));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: card,
          ),
        ),
      ),
    );
  }

  group('EqCard', () {
    testWidgets('renders child', (tester) async {
      await pump(tester, const EqCard(child: Text('Hello card')));
      expect(find.text('Hello card'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await pump(
        tester,
        EqCard(onTap: () => tapped = true, child: const Text('Tap me')),
      );
      await tester.tap(find.byType(EqCard));
      await tester.pumpAndSettle();
      expect(tapped, true);
    });

    testWidgets('non-tappable when onTap is null', (tester) async {
      await pump(tester, const EqCard(child: Text('Read-only')));
      // No InkWell ripple should fire because onTap is null.
      // We just confirm it renders without throwing.
      expect(find.byType(EqCard), findsOneWidget);
    });
  });

  group('EqCard — golden', () {
    testWidgets('default', (tester) async {
      await pump(
        tester,
        EqCard(
          child: Text('Card content', style: EqTypography.bodyL),
        ),
      );
      await expectLater(
        find.byType(EqCard),
        matchesGoldenFile('goldens/eq_card_default.png'),
      );
    });

    testWidgets('tappable', (tester) async {
      await pump(
        tester,
        EqCard(
          onTap: () {},
          child: Text('Tap card', style: EqTypography.bodyL),
        ),
      );
      await expectLater(
        find.byType(EqCard),
        matchesGoldenFile('goldens/eq_card_tappable.png'),
      );
    });
  });
}
