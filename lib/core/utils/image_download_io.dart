import 'dart:typed_data';

/// Non-web stub for the image-download save step. Cards is web-only post-flip,
/// so the file save is only wired for the browser target. The VM (test) build
/// resolves this stub so the import graph compiles without dart:html.
void saveImageBytes(Uint8List bytes, String filename, String mimeType) {
  throw UnsupportedError('Image download is only supported on the web build.');
}
