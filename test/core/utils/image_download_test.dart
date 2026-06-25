import 'package:eq_cards/core/utils/image_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('photoDownloadFilename', () {
    test('slugs type, number and slot into a .jpg name', () {
      expect(
        photoDownloadFilename(
          licenceType: 'White Card',
          licenceNumber: 'WC-12345',
          slot: 'front',
        ),
        'white-card-wc-12345-front.jpg',
      );
    });

    test('collapses runs of non-alphanumerics and trims edges', () {
      expect(
        photoDownloadFilename(
          licenceType: '  EWP / WP ',
          licenceNumber: '##99##',
          slot: 'back',
        ),
        'ewp-wp-99-back.jpg',
      );
    });

    test('falls back when every part is empty after slugging', () {
      expect(
        photoDownloadFilename(
          licenceType: '',
          licenceNumber: '!!!',
          slot: '',
        ),
        'licence-photo.jpg',
      );
    });

    test('leads with the slugged holder name when given', () {
      expect(
        photoDownloadFilename(
          holderName: 'Mark Jones',
          licenceType: 'White Card',
          licenceNumber: 'WC-12345',
          slot: 'front',
        ),
        'mark-jones-white-card-wc-12345-front.jpg',
      );
    });

    test('omits the name when null or blank (old shape preserved)', () {
      expect(
        photoDownloadFilename(
          holderName: '   ',
          licenceType: 'White Card',
          licenceNumber: 'WC-12345',
          slot: 'back',
        ),
        'white-card-wc-12345-back.jpg',
      );
    });

    test('caps an overly long holder name without a trailing dash', () {
      final filename = photoDownloadFilename(
        holderName: 'A' * 80,
        licenceType: 'White Card',
        licenceNumber: 'WC-1',
        slot: 'front',
      );
      // Name component capped to 40 chars, then the rest of the stem appended.
      expect(filename, '${'a' * 40}-white-card-wc-1-front.jpg');
    });
  });
}
