import 'package:eq_cards/features/licences/licences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Licence base({DateTime? expiry, DateTime? issue}) => Licence(
        id: 'lic-1',
        userId: 'user-1',
        licenceType: 'white_card',
        licenceNumber: 'ABC12345',
        issueDate: issue ?? DateTime.now().subtract(const Duration(days: 30)),
        expiryDate: expiry ?? DateTime.now().add(const Duration(days: 365)),
      );

  group('Licence.isExpired', () {
    test('false for future expiry', () {
      final l = base(expiry: DateTime.now().add(const Duration(days: 1)));
      expect(l.isExpired, false);
    });

    test('true for past expiry', () {
      final l = base(expiry: DateTime.now().subtract(const Duration(days: 1)));
      expect(l.isExpired, true);
    });
  });

  group('Licence.daysUntilExpiry', () {
    test('positive for future expiry', () {
      final expiry = DateTime.now().add(const Duration(days: 30));
      // The exact answer depends on time-of-day rounding; allow ±1.
      final days = base(expiry: expiry).daysUntilExpiry;
      expect(days, inInclusiveRange(29, 30));
    });

    test('zero for today', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 23, 59);
      expect(base(expiry: today).daysUntilExpiry, 0);
    });

    test('negative for past expiry', () {
      final expiry = DateTime.now().subtract(const Duration(days: 5));
      expect(base(expiry: expiry).daysUntilExpiry, lessThan(0));
    });
  });

  group('Licence.isExpiringSoon', () {
    test('true when within 90 days and not expired', () {
      final expiry = DateTime.now().add(const Duration(days: 30));
      expect(base(expiry: expiry).isExpiringSoon, true);
    });

    test('false when more than 90 days out', () {
      final expiry = DateTime.now().add(const Duration(days: 120));
      expect(base(expiry: expiry).isExpiringSoon, false);
    });

    test('false when already expired', () {
      final expiry = DateTime.now().subtract(const Duration(days: 1));
      expect(base(expiry: expiry).isExpiringSoon, false);
    });
  });
}
