import 'package:eq_cards/features/licences/licences.dart';
import 'package:eq_cards/features/licences/presentation/screens/licence_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for `LicenceDetailBody` — the presentational body extracted from
/// `LicenceDetailScreen` so it can be tested without faking the full
/// Supabase-backed provider chain.

Licence _seed({
  Map<String, dynamic> metadata = const <String, dynamic>{},
  String? state,
  String? issuingAuthority,
  String? notes,
}) =>
    Licence(
      id: 'lic-1',
      userId: 'u1',
      licenceType: 'driver_licence',
      licenceNumber: 'NSW87654321',
      issueDate: DateTime(2024, 1, 15),
      expiryDate: DateTime(2027, 1, 15),
      state: state,
      issuingAuthority: issuingAuthority,
      notes: notes,
      metadata: metadata,
    );

Future<void> _pump(
  WidgetTester tester,
  Licence licence, {
  String typeLabel = 'Driver Licence',
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LicenceDetailBody(
          licence: licence,
          typeLabel: typeLabel,
          onDelete: onDelete ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('LicenceDetailBody — render', () {
    testWidgets('shows type label, number, issue and expiry dates',
        (tester) async {
      await _pump(tester, _seed());
      expect(find.text('Driver Licence'), findsOneWidget);
      expect(find.text('NSW87654321'), findsOneWidget);
      expect(find.text('15 Jan 2024'), findsOneWidget);
      expect(find.text('15 Jan 2027'), findsOneWidget);
    });

    testWidgets('renders state row when state is set', (tester) async {
      await _pump(tester, _seed(state: 'NSW'));
      expect(find.text('NSW'), findsOneWidget);
      expect(find.text('State'), findsOneWidget);
    });

    testWidgets('renders issuing authority row when set', (tester) async {
      await _pump(tester, _seed(issuingAuthority: 'Service NSW'));
      expect(find.text('Service NSW'), findsOneWidget);
    });

    testWidgets('omits state row when state is null', (tester) async {
      await _pump(tester, _seed());
      expect(find.text('State'), findsNothing);
    });

    testWidgets('renders metadata rows with humanised keys', (tester) async {
      await _pump(
        tester,
        _seed(metadata: {'class': 'C', 'ticket_number': 'T-9999'}),
      );
      expect(find.text('Class'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('Ticket Number'), findsOneWidget);
      expect(find.text('T-9999'), findsOneWidget);
    });

    testWidgets('renders notes when present', (tester) async {
      await _pump(tester, _seed(notes: 'Restricted licence'));
      expect(find.text('Restricted licence'), findsOneWidget);
    });

    testWidgets('shows the delete CTA', (tester) async {
      await _pump(tester, _seed());
      expect(find.text('Delete licence'), findsOneWidget);
    });
  });

  group('LicenceDetailBody — interactions', () {
    testWidgets('calls onDelete when Delete licence tapped', (tester) async {
      var deleted = false;
      await _pump(tester, _seed(), onDelete: () => deleted = true);
      await tester.tap(find.text('Delete licence'));
      await tester.pumpAndSettle();
      expect(deleted, true);
    });

    testWidgets('tapping Number row writes to clipboard', (tester) async {
      final clipboardWrites = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map?;
          clipboardWrites.add(args?['text'] as String? ?? '');
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await _pump(tester, _seed());
      // The licence number row is tappable (it's a _CopyRow).
      await tester.tap(find.text('NSW87654321'));
      await tester.pump();
      expect(clipboardWrites, contains('NSW87654321'));
    });

    testWidgets('tapping metadata row writes its value to clipboard',
        (tester) async {
      final clipboardWrites = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map?;
          clipboardWrites.add(args?['text'] as String? ?? '');
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await _pump(tester, _seed(metadata: {'class': 'C'}));
      await tester.tap(find.text('C'));
      await tester.pump();
      expect(clipboardWrites, contains('C'));
    });
  });
}
