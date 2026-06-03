import 'package:http/http.dart' as http;

import 'image_download_io.dart'
    if (dart.library.html) 'image_download_web.dart';

/// Fetches the image at [url] and triggers a device download named
/// [filename].
///
/// Licence photos live behind short-lived Supabase signed URLs and are
/// cross-origin, so pointing an `<a download>` straight at the URL won't work
/// (the browser ignores the `download` attribute on cross-origin links). We
/// fetch the bytes here with the cross-platform [http] client, then hand them
/// to the platform [saveImageBytes] for the actual save.
///
/// Throws on a non-200 response or network error so the caller can surface a
/// friendly message.
Future<void> downloadImageFromUrl({
  required String url,
  required String filename,
}) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('Could not fetch image (HTTP ${response.statusCode}).');
  }
  final mimeType = response.headers['content-type'] ?? 'image/jpeg';
  saveImageBytes(response.bodyBytes, filename, mimeType);
}

/// Builds a safe, descriptive download filename like
/// `white-card-12345-front.jpg` from a licence's fields and a photo [slot]
/// (`front` or `back`). Falls back to `licence-photo.jpg` if every part is
/// empty after slugging.
String photoDownloadFilename({
  required String licenceType,
  required String licenceNumber,
  required String slot,
}) {
  final stem = [licenceType, licenceNumber, slot]
      .map(_slug)
      .where((s) => s.isNotEmpty)
      .join('-');
  return '${stem.isEmpty ? 'licence-photo' : stem}.jpg';
}

String _slug(String input) => input
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
