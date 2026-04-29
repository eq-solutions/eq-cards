import 'package:eq_cards/features/licences/data/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findLicenceNumberInLines', () {
    test('finds HLTAID first-aid code', () {
      expect(
        findLicenceNumberInLines(['Provide First Aid', 'HLTAID011']),
        'HLTAID011',
      );
    });

    test('finds HLTAID code embedded in a line', () {
      expect(
        findLicenceNumberInLines(['Unit code HLTAID009 - CPR']),
        'HLTAID009',
      );
    });

    test('finds labelled licence number (NO XXXX)', () {
      expect(
        findLicenceNumberInLines(['Service NSW', 'LICENCE NO 12345678']),
        '12345678',
      );
    });

    test('finds labelled card number (CARD: XXXX)', () {
      expect(
        findLicenceNumberInLines(['CARD NUMBER: ABC12345']),
        'ABC12345',
      );
    });

    test('keeps White Card 8-digit numbers (not a date)', () {
      // 87654321 doesn't start with 19xx or 20xx, so it's not a date.
      expect(
        findLicenceNumberInLines(['Construction Induction', '87654321']),
        '87654321',
      );
    });

    test('skips compact dates like 20240115', () {
      // Should fall through to the next candidate; here only the date present.
      expect(
        findLicenceNumberInLines(['Issue date', '20240115']),
        null,
      );
    });

    test('returns null when nothing matches', () {
      expect(findLicenceNumberInLines(['Hello', 'world']), null);
    });

    test('strips internal whitespace from labelled candidates', () {
      expect(
        findLicenceNumberInLines(['LICENCE NO ABC 12345']),
        'ABC12345',
      );
    });
  });

  group('findDatesInText', () {
    test('finds dd/mm/yyyy', () {
      final dates = findDatesInText('Expires 15/01/2027');
      expect(dates.length, 1);
      expect(dates.first, DateTime(2027, 1, 15));
    });

    test('finds dd-mm-yyyy', () {
      final dates = findDatesInText('Issue 01-03-2024');
      expect(dates.length, 1);
      expect(dates.first, DateTime(2024, 3, 1));
    });

    test('finds dd.mm.yyyy', () {
      final dates = findDatesInText('Valid until 31.12.2025');
      expect(dates.length, 1);
      expect(dates.first, DateTime(2025, 12, 31));
    });

    test('expands two-digit years to 2000s', () {
      final dates = findDatesInText('Issued 15/01/24');
      expect(dates.length, 1);
      expect(dates.first, DateTime(2024, 1, 15));
    });

    test('finds multiple dates in same text', () {
      final dates = findDatesInText('Issue 01/01/2024 Expiry 01/01/2027');
      expect(dates.length, 2);
    });

    test('rejects invalid month/day combos', () {
      // 32/13/2024 — invalid day AND month, no matches.
      expect(findDatesInText('Junk 32/13/2024').isEmpty, true);
    });

    test('returns empty for text with no dates', () {
      expect(findDatesInText('Hello world no dates here').isEmpty, true);
    });
  });
}
