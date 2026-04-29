import 'package:eq_cards/features/auth/data/aus_phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normaliseAusMobile', () {
    test('passes through valid E.164', () {
      expect(normaliseAusMobile('+61412345678'), '+61412345678');
    });

    test('strips spaces', () {
      expect(normaliseAusMobile('+61 412 345 678'), '+61412345678');
    });

    test('converts national format with leading 0', () {
      expect(normaliseAusMobile('0412345678'), '+61412345678');
    });

    test('converts 9-digit form starting with 4', () {
      expect(normaliseAusMobile('412345678'), '+61412345678');
    });

    test('handles 61 prefix without the +', () {
      expect(normaliseAusMobile('61412345678'), '+61412345678');
    });

    test('returns null for empty input', () {
      expect(normaliseAusMobile(''), null);
      expect(normaliseAusMobile('   '), null);
    });

    test('returns null for too-short input', () {
      expect(normaliseAusMobile('123'), null);
      expect(normaliseAusMobile('41234567'), null);
    });
  });

  group('isValidAusMobile', () {
    test('true for valid mobile', () {
      expect(isValidAusMobile('+61412345678'), true);
      expect(isValidAusMobile('+61498765432'), true);
    });

    test('false for landline format', () {
      expect(isValidAusMobile('+61298765432'), false);
    });

    test('false for missing + prefix', () {
      expect(isValidAusMobile('0412345678'), false);
      expect(isValidAusMobile('61412345678'), false);
    });

    test('false for wrong length', () {
      expect(isValidAusMobile('+6141234567'), false);
      expect(isValidAusMobile('+614123456789'), false);
    });

    test('false for non-mobile number range', () {
      expect(isValidAusMobile('+61512345678'), false);
    });
  });
}
