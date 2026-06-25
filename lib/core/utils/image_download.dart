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
/// `mark-jones-white-card-12345-front.jpg` from the holder's name, a licence's
/// fields and a photo [slot] (`front` or `back`).
///
/// The optional [holderName] leads the stem so a folder of many saved photos
/// clusters by person — the surface that matters when handling them in bulk.
/// It's slugged and length-capped so an unusually long legal name can't push
/// the filename past filesystem limits. When omitted (or empty after slugging)
/// the name is simply dropped, preserving the old `white-card-12345-front.jpg`
/// shape.
///
/// Falls back to `licence-photo.jpg` if every part is empty after slugging.
String photoDownloadFilename({
  required String licenceType,
  required String licenceNumber,
  required String slot,
  String? holderName,
}) {
  final name = _slug(holderName ?? '');
  final cappedName = (name.length > 40 ? name.substring(0, 40) : name)
      .replaceAll(RegExp(r'-+$'), '');
  final stem = [cappedName, _slug(licenceType), _slug(licenceNumber), _slug(slot)]
      .where((s) => s.isNotEmpty)
      .join('-');
  return '${stem.isEmpty ? 'licence-photo' : stem}.jpg';
}

String _slug(String input) => input
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
