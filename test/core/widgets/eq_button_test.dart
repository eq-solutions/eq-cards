import 'package:eq_cards/core/widgets/eq_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden tests for `EqButton`. Run `flutter test --update-goldens` once to
/// capture baselines; subsequent runs catch theme / layout regressions.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(320, 80),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  group('EqButton — render', () {
    testWidgets('label is shown', (tester) async {
      await pump(
        tester,
        EqButton(label: 'Send code', onPressed: () {}),
      );
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await pump(tester, const EqButton(label: 'Disabled', onPressed: null));
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('shows spinner when isLoading', (tester) async {
      await pump(
        tester,
        EqButton(label: 'Loading', onPressed: () {}, isLoading: true),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('does not call onPressed while loading', (tester) async {
      var taps = 0;
      await pump(
        tester,
        EqButton(label: 'Save', onPressed: () => taps++, isLoading: true),
      );
      await tester.tap(find.byType(EqButton), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('fullWidth stretches to parent width', (tester) async {
      await pump(
        tester,
        EqButton(label: 'Full', onPressed: () {}, fullWidth: true),
      );
      final size = tester.getSize(find.byType(SizedBox).first);
      // 320 surface - 32px padding = 288 available width.
      expect(size.width, greaterThan(280));
    });
  });

  group('EqButton — golden', () {
    testWidgets('primary variant', (tester) async {
      await pump(
        tester,
        EqButton(label: 'Primary', onPressed: () {}, fullWidth: true),
      );
      await expectLater(
        find.byType(EqButton),
        matchesGoldenFile('goldens/eq_button_primary.png'),
      );
    });

    testWidgets('secondary variant', (tester) async {
      await pump(
        tester,
        EqButton(
          label: 'Secondary',
          onPressed: () {},
          variant: EqButtonVariant.secondary,
          fullWidth: true,
        ),
      );
      await expectLater(
        find.byType(EqButton),
        matchesGoldenFile('goldens/eq_button_secondary.png'),
      );
    });

    testWidgets('destructive variant', (tester) async {
      await pump(
        tester,
        EqButton(
          label: 'Delete',
          onPressed: () {},
          variant: EqButtonVariant.destructive,
          fullWidth: true,
        ),
      );
      await expectLater(
        find.byType(EqButton),
        matchesGoldenFile('goldens/eq_button_destructive.png'),
      );
    });

    testWidgets('disabled state', (tester) async {
      await pump(
        tester,
        const EqButton(label: 'Disabled', onPressed: null, fullWidth: true),
      );
      await expectLater(
        find.byType(EqButton),
        matchesGoldenFile('goldens/eq_button_disabled.png'),
      );
    });

    testWidgets('loading state', (tester) async {
      await pump(
        tester,
        EqButton(
          label: 'Loading',
          onPressed: () {},
          isLoading: true,
          fullWidth: true,
        ),
      );
      await expectLater(
        find.byType(EqButton),
        matchesGoldenFile('goldens/eq_button_loading.png'),
      );
    });
  });
}
