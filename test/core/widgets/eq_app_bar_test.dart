import 'package:eq_cards/core/widgets/eq_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, EqAppBar appBar) async {
    await tester.binding.setSurfaceSize(const Size(360, 120));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: appBar,
          body: const SizedBox.expand(),
        ),
      ),
    );
  }

  group('EqAppBar', () {
    testWidgets('shows title', (tester) async {
      await pump(tester, const EqAppBar(title: 'Licences'));
      expect(find.text('Licences'), findsOneWidget);
    });

    testWidgets('shows actions when provided', (tester) async {
      await pump(
        tester,
        EqAppBar(
          title: 'Profile',
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {},
            ),
          ],
        ),
      );
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('preferredSize is kToolbarHeight', (tester) async {
      const bar = EqAppBar(title: 'X');
      expect(bar.preferredSize, const Size.fromHeight(64));
    });
  });

  group('EqAppBar — golden', () {
    testWidgets('default', (tester) async {
      await pump(tester, const EqAppBar(title: 'Licences'));
      await expectLater(
        find.byType(AppBar),
        matchesGoldenFile('goldens/eq_app_bar_default.png'),
      );
    });

    testWidgets('with action', (tester) async {
      await pump(
        tester,
        EqAppBar(
          title: 'Profile',
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {},
            ),
          ],
        ),
      );
      await expectLater(
        find.byType(AppBar),
        matchesGoldenFile('goldens/eq_app_bar_with_action.png'),
      );
    });
  });
}
