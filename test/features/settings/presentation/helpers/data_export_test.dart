import 'dart:convert';

import 'package:eq_cards/features/licences/data/models/licence.dart';
import 'package:eq_cards/features/profile/data/models/profile.dart';
import 'package:eq_cards/features/settings/presentation/helpers/data_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 4, 29, 22, 30);

  group('buildExportPayload', () {
    test('embeds the format header and timestamp', () {
      final payload = buildExportPayload(
        profile: null,
        licences: const [],
        now: now,
      );
      expect(payload['_format'], 'eq-cards-export');
      expect(payload['_format_version'], 1);
      expect(payload['_generated_at'], '2026-04-29T22:30:00.000Z');
      expect(payload['_notes'], contains('Privacy Policy'));
    });

    test('null profile renders as null, not absent', () {
      final payload = buildExportPayload(
        profile: null,
        licences: const [],
        now: now,
      );
      expect(payload.containsKey('profile'), true);
      expect(payload['profile'], isNull);
    });

    test('full profile maps every field including nested address', () {
      final profile = Profile(
        id: 'u1',
        fullName: 'Royce Milmlow',
        dateOfBirth: DateTime(1985, 1, 15),
        mobile: '+61412345678',
        email: 'royce@eq.solutions',
        addressStreet: '123 King St',
        addressSuburb: 'Sydney',
        addressState: 'NSW',
        addressPostcode: '2000',
        emergencyContactName: 'Emma',
        emergencyContactRelationship: 'Spouse',
        emergencyContactMobile: '+61498765432',
      );
      final payload = buildExportPayload(
        profile: profile,
        licences: const [],
        now: now,
      );
      final p = payload['profile'] as Map<String, dynamic>;
      expect(p['id'], 'u1');
      expect(p['full_name'], 'Royce Milmlow');
      expect(p['date_of_birth'], '1985-01-15');
      expect(p['mobile'], '+61412345678');
      expect(p['email'], 'royce@eq.solutions');

      final addr = p['address'] as Map<String, dynamic>;
      expect(addr['street'], '123 King St');
      expect(addr['suburb'], 'Sydney');
      expect(addr['state'], 'NSW');
      expect(addr['postcode'], '2000');

      final ec = p['emergency_contact'] as Map<String, dynamic>;
      expect(ec['name'], 'Emma');
      expect(ec['relationship'], 'Spouse');
      expect(ec['mobile'], '+61498765432');
    });

    test('licences are mapped including metadata + signed URLs', () {
      final licence = Licence(
        id: 'lic-1',
        userId: 'u1',
        licenceType: 'driver_licence',
        licenceNumber: '12345678',
        issueDate: DateTime(2024, 1, 1),
        expiryDate: DateTime(2027, 1, 1),
        issuingAuthority: 'Service NSW',
        state: 'NSW',
        notes: 'C class',
        metadata: const {'class': 'C'},
        photoFrontSignedUrl: 'https://example.com/front.jpg?token=abc',
      );
      final payload = buildExportPayload(
        profile: null,
        licences: [licence],
        now: now,
      );
      final list = payload['licences'] as List<dynamic>;
      expect(list.length, 1);
      final l = list.first as Map<String, dynamic>;
      expect(l['licence_number'], '12345678');
      expect(l['issue_date'], '2024-01-01');
      expect(l['expiry_date'], '2027-01-01');
      expect(l['state'], 'NSW');
      expect(l['notes'], 'C class');
      expect((l['metadata'] as Map)['class'], 'C');
      expect(
        l['photo_front_signed_url'],
        'https://example.com/front.jpg?token=abc',
      );
      expect(l['photo_back_signed_url'], isNull);
    });

    test('multiple licences preserve order', () {
      final l1 = Licence(
        id: '1',
        userId: 'u1',
        licenceType: 'white_card',
        licenceNumber: 'A',
        issueDate: DateTime(2024, 1, 1),
        expiryDate: DateTime(2099, 1, 1),
      );
      final l2 = Licence(
        id: '2',
        userId: 'u1',
        licenceType: 'first_aid',
        licenceNumber: 'B',
        issueDate: DateTime(2024, 1, 1),
        expiryDate: DateTime(2099, 1, 1),
      );
      final payload = buildExportPayload(
        profile: null,
        licences: [l1, l2],
        now: now,
      );
      final list = payload['licences'] as List<dynamic>;
      expect((list[0] as Map<String, dynamic>)['id'], '1');
      expect((list[1] as Map<String, dynamic>)['id'], '2');
    });
  });

  group('exportPayloadToJsonString', () {
    test('produces parseable, indented JSON', () {
      final payload = buildExportPayload(
        profile: null,
        licences: const [],
        now: now,
      );
      final s = exportPayloadToJsonString(payload);
      expect(s, contains('  ')); // indentation present
      // Round-trip parse must succeed.
      final parsed = jsonDecode(s) as Map<String, dynamic>;
      expect(parsed['_format'], 'eq-cards-export');
    });
  });
}
