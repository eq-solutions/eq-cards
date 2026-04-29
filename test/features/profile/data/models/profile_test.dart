import 'package:eq_cards/features/profile/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Profile fullyFilled() => Profile(
        id: 'user-1',
        fullName: 'Royce Milmlow',
        dateOfBirth: DateTime(1985, 1, 15),
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

  group('Profile.isComplete', () {
    test('true when all required fields are filled', () {
      expect(fullyFilled().isComplete, true);
    });

    test('false when full name missing', () {
      expect(fullyFilled().copyWith(fullName: null).isComplete, false);
      expect(fullyFilled().copyWith(fullName: '').isComplete, false);
      expect(fullyFilled().copyWith(fullName: '   ').isComplete, false);
    });

    test('false when DOB missing', () {
      expect(fullyFilled().copyWith(dateOfBirth: null).isComplete, false);
    });

    test('false when address fields missing', () {
      expect(fullyFilled().copyWith(addressStreet: null).isComplete, false);
      expect(fullyFilled().copyWith(addressSuburb: null).isComplete, false);
      expect(fullyFilled().copyWith(addressState: null).isComplete, false);
      expect(
        fullyFilled().copyWith(addressPostcode: null).isComplete,
        false,
      );
    });

    test('false when emergency contact missing', () {
      expect(
        fullyFilled().copyWith(emergencyContactName: null).isComplete,
        false,
      );
      expect(
        fullyFilled().copyWith(emergencyContactMobile: null).isComplete,
        false,
      );
    });

    test('email is NOT required for completeness', () {
      expect(fullyFilled().copyWith(email: null).isComplete, true);
    });

    test('emergency contact relationship is NOT required', () {
      expect(
        fullyFilled().copyWith(emergencyContactRelationship: null).isComplete,
        true,
      );
    });
  });

  group('Profile.fullAddress', () {
    test('joins all four parts with comma + space', () {
      expect(fullyFilled().fullAddress, '123 King St, Sydney, NSW, 2000');
    });

    test('skips null and empty parts', () {
      final p = fullyFilled().copyWith(addressSuburb: null);
      expect(p.fullAddress, '123 King St, NSW, 2000');
    });

    test('returns null when all parts empty', () {
      final p = fullyFilled().copyWith(
        addressStreet: null,
        addressSuburb: null,
        addressState: null,
        addressPostcode: null,
      );
      expect(p.fullAddress, null);
    });
  });
}
