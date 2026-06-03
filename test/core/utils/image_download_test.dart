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
  });
}
