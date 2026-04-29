import 'package:eq_cards/core/design/design_version.dart';
import 'package:eq_cards/features/licences/licences.dart';
import 'package:eq_cards/features/licences/presentation/widgets/licence_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Licence base({DateTime? expiry, String? frontUrl}) => Licence(
        id: 'lic-1',
        userId: 'user-1',
        licenceType: 'white_card',
        licenceNumber: 'ABC12345',
        // Stable issue date so goldens don't drift on calendar rollover.
        issueDate: DateTime(2024, 1, 1),
        // Stable expiry date for goldens (far enough in the future to be
        // categorically "Valid"; the relative-day tests use today-relative).
        expiryDate: expiry ?? DateTime(2099, 1, 1),
        photoFrontSignedUrl: frontUrl,
      );

  Future<void> pump(
    WidgetTester tester,
    Licence licence, {
    String typeLabel = 'White Card',
    VoidCallback? onTap,
    DesignVersion version = DesignVersion.linear,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LicenceCard(
            licence: licence,
            typeLabel: typeLabel,
            onTap: onTap,
            version: version,
          ),
        ),
      ),
    );
  }

  group('LicenceCard', () {
    testWidgets('renders type label and licence number', (tester) async {
      await pump(tester, base());
      expect(find.text('White Card'), findsOneWidget);
      expect(find.text('ABC12345'), findsOneWidget);
    });

    testWidgets('renders formatted expiry date', (tester) async {
      await pump(tester, base(expiry: DateTime(2027, 5, 12)));
      expect(find.textContaining('12 May 2027'), findsOneWidget);
    });

    testWidgets('shows placeholder icon when no photo url', (tester) async {
      await pump(tester, base());
      expect(find.byIcon(Icons.badge_outlined), findsOneWidget);
    });

    testWidgets('calls onTap when card tapped', (tester) async {
      var tapped = false;
      await pump(tester, base(), onTap: () => tapped = true);
      await tester.tap(find.byType(LicenceCard));
      await tester.pumpAndSettle();
      expect(tapped, true);
    });

    testWidgets('renders an ExpiryBadge with "Valid" for far-future expiry',
        (tester) async {
      // base() defaults to 2099 expiry → far outside the 90d band → "Valid".
      await pump(tester, base());
      expect(find.text('Valid'), findsOneWidget);
    });
  });

  group('LicenceCard — golden per design variant', () {
    testWidgets('linear variant matches golden', (tester) async {
      await pump(tester, base(), version: DesignVersion.linear);
      await expectLater(
        find.byType(LicenceCard),
        matchesGoldenFile('goldens/licence_card_linear.png'),
      );
    });

    testWidgets('wallet variant matches golden', (tester) async {
      await pump(tester, base(), version: DesignVersion.wallet);
      await expectLater(
        find.byType(LicenceCard),
        matchesGoldenFile('goldens/licence_card_wallet.png'),
      );
    });

    testWidgets('photo-first variant matches golden (no photo url)',
        (tester) async {
      await pump(tester, base(), version: DesignVersion.photoFirst);
      await expectLater(
        find.byType(LicenceCard),
        matchesGoldenFile('goldens/licence_card_photo_first.png'),
      );
    });
  });
}
