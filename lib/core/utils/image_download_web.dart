// Web implementation of the image-download save step. dart:html lives here
// behind a conditional import so flutter test (VM target) doesn't blow up
// trying to resolve it — conditional import keeps dart:html off the VM target.
//
// dart:html is required to build the object-URL blob and click the anchor; its
// legacy API surfaces deprecated members. All expected on this web-only file.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser "save file" download of [bytes] named [filename].
///
/// The bytes are wrapped in a same-origin object-URL blob — this sidesteps the
/// cross-origin `download`-attribute restriction that would apply if we linked
/// straight to the signed storage URL.
void saveImageBytes(Uint8List bytes, String filename, String mimeType) {
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
