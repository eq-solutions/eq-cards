import 'package:eq_cards/features/profile/data/profile_repository.dart';
import 'package:eq_cards/features/profile/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profileToUpsertPayload', () {
    // Cards Unit 4 (2026-05-21) — id is NOT in the payload. The RPC
    // bridge (eq_cards_upsert_my_profile) resolves the target staff
    // row from the JWT app_metadata, so sending an id from the client
    // is meaningless and a deliberate guard against cross-row writes.
    test('never includes id (RPC resolves staff_id from JWT)', () {
      const p = Profile(id: 'user-1');
      final payload = profileToUpsertPayload(p);
      expect(payload.containsKey('id'), false);
    });

    test('omits null optional fields', () {
      const p = Profile(id: 'user-1');
      final payload = profileToUpsertPayload(p);
      expect(payload.containsKey('full_name'), false);
      expect(payload.containsKey('email'), false);
      expect(payload.containsKey('mobile'), false);
      expect(payload.containsKey('date_of_birth'), false);
      expect(payload.containsKey('address_street'), false);
      expect(payload.containsKey('emergency_contact_name'), false);
    });

    test('includes filled fields with snake_case keys', () {
      const p = Profile(
        id: 'user-1',
        fullName: 'Royce Milmlow',
        mobile: '+61412345678',
        email: 'royce@example.com',
        addressStreet: '123 King St',
        addressSuburb: 'Sydney',
        addressState: 'NSW',
        addressPostcode: '2000',
        emergencyContactName: 'Emma Curth',
        emergencyContactRelationship: 'Spouse',
        emergencyContactMobile: '+61498765432',
      );
      final payload = profileToUpsertPayload(p);
      expect(payload['full_name'], 'Royce Milmlow');
      expect(payload['mobile'], '+61412345678');
      expect(payload['email'], 'royce@example.com');
      expect(payload['address_street'], '123 King St');
      expect(payload['address_suburb'], 'Sydney');
      expect(payload['address_state'], 'NSW');
      expect(payload['address_postcode'], '2000');
      expect(payload['emergency_contact_name'], 'Emma Curth');
      expect(payload['emergency_contact_relationship'], 'Spouse');
      expect(payload['emergency_contact_mobile'], '+61498765432');
    });

    test('formats date_of_birth as YYYY-MM-DD', () {
      final p = Profile(id: 'user-1', dateOfBirth: DateTime(1985, 1, 15));
      final payload = profileToUpsertPayload(p);
      expect(payload['date_of_birth'], '1985-01-15');
    });

    test('pads single-digit months and days', () {
      final p = Profile(id: 'user-1', dateOfBirth: DateTime(1985, 3, 5));
      final payload = profileToUpsertPayload(p);
      expect(payload['date_of_birth'], '1985-03-05');
    });

    test('does not send server-managed timestamps', () {
      final p = Profile(
        id: 'user-1',
        fullName: 'Royce',
        createdAt: DateTime(2020),
        updatedAt: DateTime(2024),
        deletedAt: DateTime(2025),
      );
      final payload = profileToUpsertPayload(p);
      expect(payload.containsKey('created_at'), false);
      expect(payload.containsKey('updated_at'), false);
      expect(payload.containsKey('deleted_at'), false);
    });
  });
}
