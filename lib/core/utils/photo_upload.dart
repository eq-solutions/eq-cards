import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';
import '../supabase/supabase_client_provider.dart';

part 'photo_upload.g.dart';

class PhotoUpload {
  PhotoUpload(this._client);
  final SupabaseClient _client;

  static const _bucket = 'licence-photos';

  /// Mobile convenience overload — reads bytes from a `File` then delegates.
  Future<String> uploadLicencePhoto({
    required String licenceId,
    required String slot,
    required File source,
  }) async {
    final bytes = await source.readAsBytes();
    return uploadLicencePhotoBytes(
      licenceId: licenceId,
      slot: slot,
      bytes: bytes,
    );
  }

  /// Cross-platform path. Mobile and web both call this via bytes from
  /// `XFile.readAsBytes()`. The helper strips EXIF, resizes, and re-encodes.
  Future<String> uploadLicencePhotoBytes({
    required String licenceId,
    required String slot,
    required Uint8List bytes,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthenticatedFailure();

    final processed = await _stripExifAndCompress(bytes);
    final path = '$userId/$licenceId/$slot.jpg';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          processed,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return path;
  }

  Future<String> signedUrl(String path) {
    return _client.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  Future<Uint8List> _stripExifAndCompress(Uint8List input) =>
      stripExifAndCompress(input);
}

/// Decodes the image, strips ALL EXIF metadata (especially GPS), resizes
/// proportionally so neither dimension is below ~1080px, and re-encodes as
/// JPEG at quality 80. Architecture §11.2.
///
/// Used by:
/// - `PhotoUpload` before persisting to Supabase Storage.
/// - The web OCR path before sending to the `ocr-licence` Edge Function (so
///   the licence image never leaves the device with GPS metadata attached).
Future<Uint8List> stripExifAndCompress(Uint8List input) async {
  final result = await FlutterImageCompress.compressWithList(
    input,
    quality: 80,
    minWidth: 1080,
    minHeight: 1080,
    keepExif: false,
    format: CompressFormat.jpeg,
  );
  if (result.isEmpty) {
    throw const ServerFailure(0, 'Image compression failed');
  }
  return result;
}

@Riverpod(keepAlive: true)
PhotoUpload photoUpload(PhotoUploadRef ref) {
  return PhotoUpload(ref.watch(supabaseClientProvider));
}
