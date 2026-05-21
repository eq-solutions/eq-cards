// Cards Unit 4 (2026-05-21) — licenceToUpsertPayload no longer takes
// `userId` as a parameter. The RPC bridge (eq_cards_upsert_my_licence)
// resolves the target staff_id from the JWT, so the client never sends
// it. Tests rewritten to match.

import 'package:eq_cards/features/licences/data/licence_repository.dart';
import 'package:eq_cards/features/licences/licences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Licence base({String? id, Map<String, dynamic>? metadata}) => Licence(
        id: id,
        userId: 'irrelevant', // model field; not sent in payload
        licenceType: 'white_card',
        licenceNumber: 'ABC12345',
        issueDate: DateTime(2024, 1, 15),
        expiryDate: DateTime(2027, 1, 15),
        metadata: metadata ?? const <String, dynamic>{},
      );

  group('licenceToUpsertPayload', () {
    test('user_id is NOT in the payload (RPC resolves it server-side)', () {
      final payload = licenceToUpsertPayload(base());
      expect(payload.containsKey('user_id'), false);
    });

    test('omits id for new licences (insert path)', () {
      final payload = licenceToUpsertPayload(base());
      expect(payload.containsKey('id'), false);
    });

    test('includes id for existing licences (update path)', () {
      final payload = licenceToUpsertPayload(base(id: 'lic-1'));
      expect(payload['id'], 'lic-1');
    });

    test('formats dates as YYYY-MM-DD', () {
      final payload = licenceToUpsertPayload(base());
      expect(payload['issue_date'], '2024-01-15');
      expect(payload['expiry_date'], '2027-01-15');
    });

    test('pads single-digit months and days', () {
      final l = Licence(
        userId: 'u1',
        licenceType: 'white_card',
        licenceNumber: '123',
        issueDate: DateTime(2024, 3, 5),
        expiryDate: DateTime(2027, 7, 9),
      );
      final payload = licenceToUpsertPayload(l);
      expect(payload['issue_date'], '2024-03-05');
      expect(payload['expiry_date'], '2027-07-09');
    });

    test('always includes metadata key, defaulting to empty map', () {
      final payload = licenceToUpsertPayload(base());
      expect(payload['metadata'], isA<Map<String, dynamic>>());
      expect((payload['metadata'] as Map).isEmpty, true);
    });

    test('passes metadata through verbatim for type-specific extras', () {
      final l = base(
        metadata: {'irn': '1', 'class': 'C', 'ticket_number': 'T-9999'},
      );
      final payload = licenceToUpsertPayload(l);
      final metadata = payload['metadata'] as Map<String, dynamic>;
      expect(metadata['irn'], '1');
      expect(metadata['class'], 'C');
      expect(metadata['ticket_number'], 'T-9999');
    });

    test('omits null optional fields', () {
      final payload = licenceToUpsertPayload(base());
      expect(payload.containsKey('issuing_authority'), false);
      expect(payload.containsKey('state'), false);
      expect(payload.containsKey('photo_front_url'), false);
      expect(payload.containsKey('photo_back_url'), false);
      expect(payload.containsKey('notes'), false);
    });

    test('includes optional fields when set', () {
      final l = Licence(
        id: 'lic-1',
        userId: 'u1',
        licenceType: 'driver_licence',
        licenceNumber: 'NSW123456',
        issueDate: DateTime(2024, 1, 15),
        expiryDate: DateTime(2029, 1, 15),
        issuingAuthority: 'Service NSW',
        state: 'NSW',
        photoFrontPath: 't1/s1/lic-1/front.jpg',
        photoBackPath: 't1/s1/lic-1/back.jpg',
        notes: 'Class C',
      );
      final payload = licenceToUpsertPayload(l);
      expect(payload['issuing_authority'], 'Service NSW');
      expect(payload['state'], 'NSW');
      expect(payload['photo_front_url'], 't1/s1/lic-1/front.jpg');
      expect(payload['photo_back_url'], 't1/s1/lic-1/back.jpg');
      expect(payload['notes'], 'Class C');
    });

    test('never serialises transient signed URLs', () {
      final l = base(id: 'lic-1').copyWith(
        photoFrontSignedUrl: 'https://signed.example.com/front',
        photoBackSignedUrl: 'https://signed.example.com/back',
        photoFrontPath: 't1/s1/lic-1/front.jpg',
        photoBackPath: 't1/s1/lic-1/back.jpg',
      );
      final payload = licenceToUpsertPayload(l);
      expect(payload['photo_front_url'], 't1/s1/lic-1/front.jpg');
      expect(payload['photo_back_url'], 't1/s1/lic-1/back.jpg');
      expect(
        payload.values,
        isNot(contains('https://signed.example.com/front')),
      );
      expect(
        payload.values,
        isNot(contains('https://signed.example.com/back')),
      );
    });
  });
}
