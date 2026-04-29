import 'package:eq_cards/core/utils/clipboard_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Captures `Clipboard.setData` calls so we can assert what was written.
  final clipboardWrites = <String>[];
  // Captures haptic feedback calls.
  final hapticCalls = <String>[];

  setUp(() {
    clipboardWrites.clear();
    hapticCalls.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map?;
          final text = args?['text'] as String? ?? '';
          clipboardWrites.add(text);
        }
        if (call.method == 'HapticFeedback.vibrate') {
          hapticCalls.add(call.arguments as String? ?? '');
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpAndCopy(
    WidgetTester tester, {
    required String value,
    required String label,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => copyWithFeedback(
                  context: context,
                  value: value,
                  label: label,
                ),
                child: const Text('Copy'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Copy'));
    // Two pumps: one for the future to resolve, one for the snackbar to mount.
    await tester.pump();
    await tester.pump();
  }

  group('copyWithFeedback', () {
    testWidgets('writes the value to the clipboard', (tester) async {
      await pumpAndCopy(tester, value: '+61412345678', label: 'Mobile');
      expect(clipboardWrites, contains('+61412345678'));
    });

    testWidgets('triggers haptic feedback', (tester) async {
      await pumpAndCopy(tester, value: 'ABC12345', label: 'Number');
      expect(hapticCalls, isNotEmpty);
    });

    testWidgets('shows a snackbar with "<label> copied"', (tester) async {
      await pumpAndCopy(tester, value: 'Royce Milmlow', label: 'Full name');
      expect(find.text('Full name copied'), findsOneWidget);
    });
  });
}
