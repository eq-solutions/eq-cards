import 'package:eq_cards/features/licences/data/models/licence.dart';
import 'package:eq_cards/features/licences/presentation/helpers/licences_list_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

Licence _l({
  required String id,
  required String type,
  required String number,
  required DateTime expiry,
  DateTime? issue,
}) =>
    Licence(
      id: id,
      userId: 'u1',
      licenceType: type,
      licenceNumber: number,
      issueDate: issue ?? DateTime(2024, 1, 1),
      expiryDate: expiry,
    );

void main() {
  // Tests use today-relative offsets so they stay green regardless of clock.
  final now = DateTime.now();
  DateTime daysFromNow(int days) => now.add(Duration(days: days));

  group('applyLicenceFilters — filter buckets', () {
    final licences = [
      _l(
        id: '1',
        type: 'white_card',
        number: '12345678',
        expiry: daysFromNow(365),
      ),
      _l(
        id: '2',
        type: 'first_aid',
        number: 'HLTAID011',
        expiry: daysFromNow(20),
      ),
      _l(
        id: '3',
        type: 'driver_licence',
        number: 'NSWABC',
        expiry: daysFromNow(-10),
      ),
      _l(
        id: '4',
        type: 'forklift_hrwl',
        number: 'LF99',
        expiry: daysFromNow(7),
      ),
    ];

    test('all returns everything', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: const {},
        filter: LicenceFilter.all,
        query: '',
      );
      expect(result.length, 4);
    });

    test('expiringSoon excludes expired and >30d-out', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: const {},
        filter: LicenceFilter.expiringSoon,
        query: '',
      );
      expect(result.map((l) => l.id), containsAll(['2', '4']));
      expect(result.length, 2);
    });

    test('expired returns only the expired licence', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: const {},
        filter: LicenceFilter.expired,
        query: '',
      );
      expect(result.map((l) => l.id), ['3']);
    });
  });

  group('applyLicenceFilters — search', () {
    final licences = [
      _l(
        id: '1',
        type: 'white_card',
        number: 'ABC12345',
        expiry: DateTime(2099, 1, 1),
      ),
      _l(
        id: '2',
        type: 'first_aid',
        number: 'HLTAID011',
        expiry: DateTime(2099, 1, 1),
      ),
      _l(
        id: '3',
        type: 'driver_licence',
        number: 'XYZ98765',
        expiry: DateTime(2099, 1, 1),
      ),
    ];
    final labels = {
      'white_card': 'White Card',
      'first_aid': 'First Aid',
      'driver_licence': 'Driver Licence',
    };

    test('matches by type label (case-insensitive)', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: labels,
        filter: LicenceFilter.all,
        query: 'driver',
      );
      expect(result.map((l) => l.id), ['3']);
    });

    test('matches by licence number (case-insensitive)', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: labels,
        filter: LicenceFilter.all,
        query: 'hltaid',
      );
      expect(result.map((l) => l.id), ['2']);
    });

    test('substring match works mid-string', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: labels,
        filter: LicenceFilter.all,
        query: '987',
      );
      expect(result.map((l) => l.id), ['3']);
    });

    test('empty query returns everything', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: labels,
        filter: LicenceFilter.all,
        query: '',
      );
      expect(result.length, 3);
    });

    test('whitespace-only query returns everything', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: labels,
        filter: LicenceFilter.all,
        query: '   ',
      );
      expect(result.length, 3);
    });

    test('falls back to raw type code when label not in map', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: const {},
        filter: LicenceFilter.all,
        query: 'first_aid',
      );
      expect(result.map((l) => l.id), ['2']);
    });
  });

  group('applyLicenceFilters — combined filter + search', () {
    final licences = [
      _l(
        id: '1',
        type: 'white_card',
        number: 'AAA',
        expiry: daysFromNow(365),
      ),
      _l(
        id: '2',
        type: 'white_card',
        number: 'BBB',
        expiry: daysFromNow(20),
      ),
      _l(
        id: '3',
        type: 'driver_licence',
        number: 'CCC',
        expiry: daysFromNow(20),
      ),
    ];
    final labels = {'white_card': 'White Card', 'driver_licence': 'Driver'};

    test('filter narrows first, then search narrows further', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: labels,
        filter: LicenceFilter.expiringSoon,
        query: 'white',
      );
      expect(result.map((l) => l.id), ['2']);
    });

    test('returns empty when filter+search exclude everything', () {
      final result = applyLicenceFilters(
        licences,
        typeLabels: labels,
        filter: LicenceFilter.expired,
        query: 'white',
      );
      expect(result, isEmpty);
    });
  });

  group('LicenceFilterLabel', () {
    test('all values have a non-empty label', () {
      for (final f in LicenceFilter.values) {
        expect(f.label, isNotEmpty);
      }
    });

    test('labels are distinct', () {
      final labels = LicenceFilter.values.map((f) => f.label).toSet();
      expect(labels.length, LicenceFilter.values.length);
    });
  });

  group('ocrErrorMessage — error → user message mapping', () {
    test('maps unsupported_mime_type to format hint', () {
      expect(
        ocrErrorMessage(Exception('unsupported_mime_type')),
        contains('photo format'),
      );
    });

    test('maps 401 / unauthorized to session expired', () {
      expect(
        ocrErrorMessage(Exception('401 Unauthorized')),
        contains('sign-in'),
      );
      expect(
        ocrErrorMessage(Exception('unauthorized')),
        contains('sign-in'),
      );
    });

    test('maps 502 / anthropic upstream to temporary unavailable', () {
      expect(
        ocrErrorMessage(Exception('502 anthropic_upstream_error')),
        contains('temporarily unavailable'),
      );
    });

    test('maps Failed to fetch / network errors', () {
      expect(
        ocrErrorMessage(Exception('TypeError: Failed to fetch')),
        contains('network unreachable'),
      );
      expect(
        ocrErrorMessage(Exception('SocketException')),
        contains('network unreachable'),
      );
      expect(
        ocrErrorMessage(Exception('ClientException: connection failed')),
        contains('network unreachable'),
      );
    });

    test('maps timeout', () {
      expect(
        ocrErrorMessage(Exception('TimeoutException after 30s')),
        contains('took too long'),
      );
    });

    test('falls back to generic for unknown errors', () {
      expect(
        ocrErrorMessage(Exception('completely unexpected weirdness')),
        contains('unexpected'),
      );
    });

    test('case-insensitive matching', () {
      expect(
        ocrErrorMessage(Exception('TypeError: Failed to Fetch')),
        contains('network'),
      );
    });
  });
}
