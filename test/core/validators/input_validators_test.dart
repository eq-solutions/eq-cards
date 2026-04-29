import 'package:eq_cards/core/validators/input_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateMobile (optional)', () {
    test('null + empty are valid (optional field)', () {
      expect(validateMobile(null), isNull);
      expect(validateMobile(''), isNull);
      expect(validateMobile('   '), isNull);
    });
    test('valid AU mobile passes', () {
      expect(validateMobile('0412 345 678'), isNull);
      expect(validateMobile('+61412345678'), isNull);
      expect(validateMobile('0412345678'), isNull);
    });
    test('non-mobile (landline) fails', () {
      expect(validateMobile('0298765432'), isNotNull);
    });
    test('garbage fails', () {
      expect(validateMobile('not a phone'), isNotNull);
      expect(validateMobile('123'), isNotNull);
    });
  });

  group('validateMobileRequired', () {
    test('empty is rejected', () {
      expect(validateMobileRequired(null), isNotNull);
      expect(validateMobileRequired(''), isNotNull);
    });
    test('valid still passes', () {
      expect(validateMobileRequired('0412345678'), isNull);
    });
  });

  group('validateEmail', () {
    test('null + empty are valid (optional)', () {
      expect(validateEmail(null), isNull);
      expect(validateEmail(''), isNull);
    });
    test('valid emails pass', () {
      expect(validateEmail('royce@eq.solutions'), isNull);
      expect(validateEmail('royce.milmlow+test@example.co.uk'), isNull);
      expect(validateEmail('a@b.co'), isNull);
    });
    test('missing @ fails', () {
      expect(validateEmail('royce.eq.solutions'), isNotNull);
    });
    test('missing TLD fails', () {
      expect(validateEmail('royce@solutions'), isNotNull);
    });
    test('spaces fail', () {
      expect(validateEmail('royce @ eq.solutions'), isNotNull);
    });
  });

  group('validatePostcode', () {
    test('null + empty are valid (optional)', () {
      expect(validatePostcode(null), isNull);
      expect(validatePostcode(''), isNull);
    });
    test('4 digits passes', () {
      expect(validatePostcode('2000'), isNull);
      expect(validatePostcode('3000'), isNull);
    });
    test('non-4 digits fails', () {
      expect(validatePostcode('200'), isNotNull);
      expect(validatePostcode('20000'), isNotNull);
      expect(validatePostcode('20A0'), isNotNull);
    });
  });

  group('validateAuState', () {
    test('null + empty are valid (optional)', () {
      expect(validateAuState(null), isNull);
      expect(validateAuState(''), isNull);
    });
    test('all 8 valid codes pass', () {
      for (final s in ['NSW', 'VIC', 'QLD', 'WA', 'SA', 'TAS', 'NT', 'ACT']) {
        expect(validateAuState(s), isNull, reason: s);
      }
    });
    test('lowercase passes (case-insensitive)', () {
      expect(validateAuState('nsw'), isNull);
      expect(validateAuState('vic'), isNull);
    });
    test('invalid codes fail', () {
      expect(validateAuState('NS'), isNotNull);
      expect(validateAuState('CA'), isNotNull); // California
      expect(validateAuState('XYZ'), isNotNull);
    });
  });

  group('validateDateOfBirth', () {
    final fixedNow = DateTime(2026, 4, 29);
    test('null is valid (optional)', () {
      expect(validateDateOfBirth(null, now: fixedNow), isNull);
    });
    test('past date passes', () {
      expect(validateDateOfBirth(DateTime(1985, 1, 15), now: fixedNow), isNull);
    });
    test('future date fails', () {
      expect(
        validateDateOfBirth(DateTime(2030, 1, 1), now: fixedNow),
        contains('future'),
      );
    });
    test('pre-1900 fails', () {
      expect(
        validateDateOfBirth(DateTime(1899, 12, 31), now: fixedNow),
        contains('plausible'),
      );
    });
  });

  group('validateLicenceNumber', () {
    test('empty fails (required)', () {
      expect(validateLicenceNumber(null), isNotNull);
      expect(validateLicenceNumber(''), isNotNull);
      expect(validateLicenceNumber('   '), isNotNull);
    });
    test('alphanumeric passes', () {
      expect(validateLicenceNumber('ABC12345'), isNull);
      expect(validateLicenceNumber('12345678'), isNull);
      expect(validateLicenceNumber('HLTAID011'), isNull);
    });
    test('hyphens and spaces allowed', () {
      expect(validateLicenceNumber('ABC-1234-XY'), isNull);
      expect(validateLicenceNumber('ABC 1234 XY'), isNull);
      expect(validateLicenceNumber('ABC/1234'), isNull);
    });
    test('special chars rejected', () {
      expect(validateLicenceNumber('ABC@1234'), isNotNull);
      expect(validateLicenceNumber('ABC#1234'), isNotNull);
    });
    test('over-long rejected', () {
      expect(
        validateLicenceNumber('A' * 33),
        contains('too long'),
      );
    });
  });

  group('validateIssueDate', () {
    final fixedNow = DateTime(2026, 4, 29);
    test('null is valid (form-level required check is separate)', () {
      expect(validateIssueDate(null, now: fixedNow), isNull);
    });
    test('past + today passes', () {
      expect(validateIssueDate(DateTime(2024, 1, 1), now: fixedNow), isNull);
      expect(validateIssueDate(fixedNow, now: fixedNow), isNull);
    });
    test('future fails', () {
      expect(
        validateIssueDate(DateTime(2027, 1, 1), now: fixedNow),
        contains('future'),
      );
    });
  });

  group('validateExpiryDate', () {
    test('null is valid (form-level required check separate)', () {
      expect(validateExpiryDate(null, issueDate: DateTime(2024, 1, 1)), isNull);
    });
    test('after issue passes', () {
      expect(
        validateExpiryDate(
          DateTime(2027, 1, 1),
          issueDate: DateTime(2024, 1, 1),
        ),
        isNull,
      );
    });
    test('before issue fails', () {
      expect(
        validateExpiryDate(
          DateTime(2023, 1, 1),
          issueDate: DateTime(2024, 1, 1),
        ),
        contains('after'),
      );
    });
    test('same as issue fails', () {
      expect(
        validateExpiryDate(
          DateTime(2024, 1, 1),
          issueDate: DateTime(2024, 1, 1),
        ),
        contains('after'),
      );
    });
    test('null issue date allows any expiry', () {
      expect(validateExpiryDate(DateTime(2027, 1, 1), issueDate: null), isNull);
    });
    test('post-2100 fails as unrealistic', () {
      expect(
        validateExpiryDate(
          DateTime(2200, 1, 1),
          issueDate: DateTime(2024, 1, 1),
        ),
        contains('unrealistic'),
      );
    });
  });

  group('validateAddressLine', () {
    test('null + empty are valid', () {
      expect(validateAddressLine(null, fieldName: 'Street'), isNull);
      expect(validateAddressLine('', fieldName: 'Street'), isNull);
    });
    test('normal address passes', () {
      expect(
        validateAddressLine('123 King Street', fieldName: 'Street'),
        isNull,
      );
    });
    test('over-long fails with field name in message', () {
      final result = validateAddressLine('A' * 201, fieldName: 'Suburb');
      expect(result, isNotNull);
      expect(result, contains('Suburb'));
    });
  });
}
