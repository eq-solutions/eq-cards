import 'package:eq_cards/core/widgets/eq_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget field) async {
    await tester.binding.setSurfaceSize(const Size(360, 120));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: field,
          ),
        ),
      ),
    );
  }

  group('EqTextField — render', () {
    testWidgets('label and hint visible', (tester) async {
      await pump(
        tester,
        const EqTextField(label: 'Mobile number', hint: '0412 345 678'),
      );
      expect(find.text('Mobile number'), findsOneWidget);
      expect(find.text('0412 345 678'), findsOneWidget);
    });

    testWidgets('errorText appears when set', (tester) async {
      await pump(
        tester,
        const EqTextField(
          label: 'Mobile',
          errorText: 'Enter a valid Australian mobile',
        ),
      );
      expect(find.text('Enter a valid Australian mobile'), findsOneWidget);
    });

    testWidgets('forwards onChanged', (tester) async {
      var captured = '';
      await pump(
        tester,
        EqTextField(label: 'Test', onChanged: (v) => captured = v),
      );
      await tester.enterText(find.byType(EqTextField), 'hello');
      expect(captured, 'hello');
    });
  });

  group('EqTextField — golden', () {
    testWidgets('empty', (tester) async {
      await pump(
        tester,
        const EqTextField(label: 'Mobile number', hint: '0412 345 678'),
      );
      await expectLater(
        find.byType(EqTextField),
        matchesGoldenFile('goldens/eq_text_field_empty.png'),
      );
    });

    testWidgets('with value', (tester) async {
      final controller = TextEditingController(text: '+61412345678');
      await pump(
        tester,
        EqTextField(controller: controller, label: 'Mobile number'),
      );
      await expectLater(
        find.byType(EqTextField),
        matchesGoldenFile('goldens/eq_text_field_filled.png'),
      );
    });

    testWidgets('with error', (tester) async {
      await pump(
        tester,
        const EqTextField(
          label: 'Mobile number',
          errorText: 'Enter a valid Australian mobile',
        ),
      );
      await expectLater(
        find.byType(EqTextField),
        matchesGoldenFile('goldens/eq_text_field_error.png'),
      );
    });
  });
}
